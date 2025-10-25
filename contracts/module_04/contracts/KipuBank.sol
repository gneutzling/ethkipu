// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title KipuBank
 * @notice A vault contract for depositing and withdrawing Ether with safety limits
 * @dev Educational, showing production-lean patterns (CEI, reentrancy guard, OZ, Chainlink, EIP-7528).
 */

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

using SafeERC20 for IERC20;

contract KipuBank is AccessControl {
    // ========= Constants / Roles =========
    uint8   public constant ORACLE_DECIMALS     = 8;
    uint8   public constant ACCOUNTING_DECIMALS = 6; // USDC-like accounting
    uint256 public constant MAX_WITHDRAW_USD    = 1000 * 1e8; // 8 decimals
    address public constant ETH_ALIAS           = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    bytes32 public constant MANAGER_ROLE        = keccak256("MANAGER_ROLE");

    uint256 private constant ETH_DECIMALS = 1e18;

    // ========= User-defined value types (units) =========
    // These add unit safety internally (compile down to uint256).
    type Wei   is uint256; // ETH base-1e18
    type Usd8  is uint256; // 8-dec USD (Chainlink)
    type Usdc6 is uint256; // 6-dec accounting

    // small helpers
    function _wei(uint256 v)  internal pure returns (Wei)  { return Wei.wrap(v);  }
    function _usd8(uint256 v) internal pure returns (Usd8) { return Usd8.wrap(v); }
    function _unwrapWei(Wei v)  internal pure returns (uint256) { return Wei.unwrap(v);  }
    function _unwrapUsd8(Usd8 v) internal pure returns (uint256) { return Usd8.unwrap(v); }

    // ========= Immutables / Storage =========
    AggregatorV3Interface public immutable priceFeed; // Chainlink ETH/USD
    uint256 public immutable BANK_CAP;
    uint256 public nativePerTxCapWei; // Per-transaction native cap in wei

    // balances[user][token]; token == ETH_ALIAS => ETH (EIP-7528 style)
    mapping(address user => mapping(address token => uint256)) public balances;
    uint256 public depositCount;
    uint256 public withdrawCount;

    bool private locked; // reentrancy lock

    // ========= Events =========
    event Deposited(address indexed user, address indexed token, uint256 amount, uint256 newBalance);
    event Withdrawn(address indexed user, address indexed token, uint256 amount, uint256 usdValue, uint256 newBalance);
    event FundsRecovered(address indexed manager, address indexed user, address indexed token, uint256 oldBalance, uint256 newBalance);
    event NativePerTxCapUpdated(uint256 oldCap, uint256 newCap);

    // ========= Errors =========
    error BankCapacityExceeded(uint256 currentBalance, uint256 depositAmount, uint256 maxCapacity);
    error WithdrawLimitExceeded(uint256 requestedAmount, uint256 maxLimit);
    error InsufficientBalance(address token, uint256 requestedAmount, uint256 availableBalance);
    error ZeroAmountNotAllowed();
    error NonZeroAmountForETH();
    error UnexpectedMsgValue();
    error EtherTransferFailed(address recipient, uint256 amount);
    error ReentrancyDetected();
    error InvalidOraclePrice(int256 price);
    error ZeroAddressNotAllowed();
    error ZeroBankCapNotAllowed();
    error StaleOracleData(uint256 updatedAt, uint256 currentTime);
    error InvalidOracleDecimals(uint8 decimals);

    // ========= Modifiers =========
    modifier noReentrancy() {
        if (locked) revert ReentrancyDetected();
        locked = true;
        _;
        locked = false;
    }

    // ========= Constructor =========
    constructor(uint256 _bankCap, address _priceFeed) {
        if (_bankCap == 0) revert ZeroBankCapNotAllowed();
        if (_priceFeed == address(0)) revert ZeroAddressNotAllowed();

        BANK_CAP = _bankCap;
        priceFeed = AggregatorV3Interface(_priceFeed);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);
    }

    // ========= Fallback (ETH) =========
    receive() external payable {
        _deposit(msg.sender, ETH_ALIAS, msg.value);
    }

    // ========= External =========
    /**
     * @notice Deposit ETH (address(0) or ETH_ALIAS) or ERC20.
     * For ERC20, we credit the actual `received` amount (fee-on-transfer safe).
     */
    function deposit(address _token, uint256 _amount) external payable noReentrancy {
        if (isETH(_token)) {
            if (msg.value == 0) revert ZeroAmountNotAllowed();
            if (_amount != 0) revert NonZeroAmountForETH();
            _deposit(msg.sender, ETH_ALIAS, msg.value);
        } else {
            if (msg.value != 0) revert UnexpectedMsgValue();
            if (_amount == 0) revert ZeroAmountNotAllowed();

            // CEI: Compute received amount first, then update state
            IERC20 token = IERC20(_token);
            uint256 beforeBal = token.balanceOf(address(this));
            token.safeTransferFrom(msg.sender, address(this), _amount);
            uint256 received = token.balanceOf(address(this)) - beforeBal;

            _deposit(msg.sender, _token, received);
        }
    }

    function withdraw(address _token, uint256 _amount) external noReentrancy {
        if (_amount == 0) revert ZeroAmountNotAllowed();

        address canon = canonical(_token);
        uint256 bal = balances[msg.sender][canon];
        if (bal < _amount) revert InsufficientBalance(_token, _amount, bal);

        bool native = isETH(_token);
        uint256 usdValueOut = 0;

        if (native) {
            // Check USD limit
            Usd8 usdValue = convertEthToUsd(_wei(_amount));
            uint256 usd = _unwrapUsd8(usdValue);
            if (usd > MAX_WITHDRAW_USD) {
                revert WithdrawLimitExceeded(usd, MAX_WITHDRAW_USD);
            }
            
            // Check native per-transaction cap
            if (nativePerTxCapWei != 0 && _amount > nativePerTxCapWei) {
                revert WithdrawLimitExceeded(_amount, nativePerTxCapWei);
            }
            
            usdValueOut = usd;
        }

        balances[msg.sender][canon] = bal - _amount;
        unchecked { withdrawCount++; }

        if (native) {
            (bool sent, ) = payable(msg.sender).call{value: _amount}("");
            if (!sent) revert EtherTransferFailed(msg.sender, _amount);
        } else {
            IERC20(canon).safeTransfer(msg.sender, _amount);
        }

        emit Withdrawn(msg.sender, canon, _amount, usdValueOut, balances[msg.sender][canon]);
    }

    function recoverFunds(address _user, address _token, uint256 _newBalance)
        external
        onlyRole(MANAGER_ROLE)
    {
        if (_user == address(0)) revert ZeroAddressNotAllowed();
        address canon = canonical(_token);
        uint256 oldBalance = balances[_user][canon];
        balances[_user][canon] = _newBalance;
        emit FundsRecovered(msg.sender, _user, canon, oldBalance, _newBalance);
    }

    function setNativePerTxCapWei(uint256 _cap) external onlyRole(MANAGER_ROLE) {
        uint256 oldCap = nativePerTxCapWei;
        nativePerTxCapWei = _cap;
        emit NativePerTxCapUpdated(oldCap, _cap);
    }

    // ========= Public Views =========
    function getBankBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getRemainingCapacity() external view returns (uint256) {
        return BANK_CAP - address(this).balance;
    }

    function balanceInUSDCDecimals(address _user, address _token) external view returns (uint256) {
        address canon = canonical(_token);
        uint256 amount = balances[_user][canon];
        uint8 decimals = tokenDecimals(canon);
        return convertToAccountingUnits(amount, decimals);
    }

    // ========= Internal =========
    function _deposit(address _user, address _token, uint256 _amount) private {
        if (_amount == 0) revert ZeroAmountNotAllowed();
        
        // For ETH, check capacity pre-state to avoid post-state grief
        if (isETH(_token)) {
            uint256 before = address(this).balance - _amount;
            if (before + _amount > BANK_CAP) {
                revert BankCapacityExceeded(before, _amount, BANK_CAP);
            }
        }
        
        balances[_user][_token] += _amount;
        unchecked { depositCount++; }
        emit Deposited(_user, _token, _amount, balances[_user][_token]);
    }

    /// @notice Chainlink price with freshness checks
    function getEthUsdPrice() internal view returns (uint256) {
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        
        if (answer <= 0) revert InvalidOraclePrice(answer);
        if (answeredInRound < roundId) revert StaleOracleData(updatedAt, block.timestamp);
        
        // Check oracle decimals
        uint8 decimals = priceFeed.decimals();
        if (decimals != ORACLE_DECIMALS) revert InvalidOracleDecimals(decimals);
        
        return uint256(answer); // 8 decimals
    }

    /// @notice Typed converter: Wei -> Usd8 (internal)
    function convertEthToUsd(Wei _ethAmount) internal view returns (Usd8) {
        uint256 price = getEthUsdPrice(); // 8 decimals
        uint256 usdValue = (_unwrapWei(_ethAmount) * price) / ETH_DECIMALS;
        return _usd8(usdValue);
    }

    // ========= Token utils =========
    function isETH(address _token) internal pure returns (bool) {
        return _token == address(0) || _token == ETH_ALIAS;
    }
    function canonical(address _token) internal pure returns (address) {
        return isETH(_token) ? ETH_ALIAS : _token;
    }
    function tokenDecimals(address _token) internal view returns (uint8) {
        if (isETH(_token)) return 18;
        try IERC20Metadata(_token).decimals() returns (uint8 d) { return d; } catch { return 18; }
    }

    // ========= Decimals conversion (accounting) =========
    function convertToAccountingUnits(uint256 _amount, uint8 _decimals) internal pure returns (uint256) {
        if (_decimals == ACCOUNTING_DECIMALS) return _amount;
        if (_decimals > ACCOUNTING_DECIMALS) {
            return _amount / (10 ** (_decimals - ACCOUNTING_DECIMALS));
        }
        return _amount * (10 ** (ACCOUNTING_DECIMALS - _decimals));
    }
}
