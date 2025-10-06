// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

/**
 * @title KipuBank
 * @notice A vault contract for depositing and withdrawing Ether with safety limits
 * @dev Features include:
 *      - Deposit and withdrawal limits
 *      - Reentrancy protection
 *      - Event logging for transactions
 *      - Custom error handling
 * 
 * Security:
 * - Bank capacity and withdrawal limits
 * - Reentrancy guard
 * - CEI pattern (Checks-Effects-Interactions)
 * 
 * @custom:educational Designed for learning purposes, demonstrating best practices in Solidity
 */

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";


using SafeERC20 for IERC20;

contract KipuBank {
    // Errors
    error BankCapacityExceeded(uint256 totalBalance, uint256 depositAmount, uint256 bankCap);
    error WithdrawLimitExceeded(uint256 usdValue, uint256 usdLimit);
    error InsufficientBalance(address token, uint256 requested, uint256 accountBalance);
    error EtherTransferFailed(address receiver, uint256 amount);
    error InvalidConstructorParams(uint256 bankCap);
    error ZeroAmountNotAllowed();
    error NonZeroAmountForETH();
    error UnexpectedMsgValue();
    error ReentrancyDetected();
    error ERC20TransferFailed(address token, uint256 amount);
    error InvalidOraclePrice();

    // Events
    event Deposited(address indexed user, address indexed token, uint256 amount);
    event Withdrawn(address indexed user, address indexed token, uint256 amount, uint256 usdValue);

    // Constants
    uint8 public constant ORACLE_DECIMALS = 8;
    uint256 public constant MAX_WITHDRAW_USD = 1000 * 1e8; // $1000 with 8 decimals precision
    uint256 private constant ETH_DECIMALS = 1e18;

    // Immutables
    AggregatorV3Interface public immutable priceFeed; // Chainlink ETH/USD feed
    uint256 public immutable BANK_CAP; // total allowed ETH in the bank
    
    /**
     * @notice Mapping of user addresses to their deposited token balances
     * @dev Tracks how much of each token type each user has deposited in the bank
     *      balances[user][token] => user's balance in a specific token
     *      token == address(0) => ETH
     */
    mapping(address user => mapping(address token => uint256)) public balances;

    uint256 public depositCount = 0;
    uint256 public withdrawCount = 0;

    // Reentrancy guard state variable
    bool private locked;


    constructor(uint256 _bankCap, address _priceFeed) {
        if (_bankCap == 0) revert InvalidConstructorParams(_bankCap, 0);

        BANK_CAP = _bankCap;
        priceFeed = AggregatorV3Interface(_priceFeed);
    }


    /**
     * @notice Prevents reentrancy attacks by using a simple lock mechanism
     * @dev Sets locked to true before function execution and false after completion
     *      Reverts if the function is called while already executing
     */
    modifier noReentrancy() {
        if (locked) revert ReentrancyDetected();

        locked = true;
        _;
        locked = false;
    }


    /**
     * @notice Allows the contract to receive Ether directly and automatically deposit it
     * @dev Called when Ether is sent to the contract without any function call data
     *      Automatically credits the sender's balance using the internal _deposit function
     */
    receive() external payable {
        _deposit(msg.sender, address(0), msg.value);
    }

    
    /**
     * @notice Allows users to deposit Ether into their bank account
     * @dev Calls the internal _deposit function to handle the deposit logic
     *      Requires sending Ether with the transaction (payable)
     */
    function deposit(address _token, uint256 _amount) external payable noReentrancy {
        // ETH deposit
        if (_token == address(0)) {
            if (msg.value == 0) revert ZeroAmountNotAllowed();
            if (_amount != 0) revert NonZeroAmountForETH();

            _deposit(msg.sender, _token, msg.value);
        } 
        // ERC20 deposit
        else {
            if (msg.value != 0) revert UnexpectedMsgValue();
            if (_amount == 0) revert ZeroAmountNotAllowed();

            IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
            _deposit(msg.sender, _token, _amount);
        }
    }


    /**
     * @notice Handles the logic for depositing tokens or Ether into the bank
     * @param _user The address of the user making the deposit
     * @param _token The address of the token being deposited; use address(0) for Ether
     * @param _amount The amount being deposited, in wei for Ether or smallest unit for tokens
     * @dev Ensures the deposit amount is non-zero and does not exceed the bank's capacity
     *      Updates the user's balance and increments the deposit count
     *      Emits a Deposited event upon successful deposit
     *      Invoked by both the deposit() and receive() functions
     */
    function _deposit(address _user, address _token, uint256 _amount) private {
        // 1. Check
        if (_amount == 0) revert ZeroAmountNotAllowed();
        if (_token == address(0) && address(this).balance > BANK_CAP) {
            revert BankCapacityExceeded(address(this).balance, _amount, BANK_CAP);
        }

        // 2. Effect
        balances[_user][_token] += _amount;
        depositCount++;

        // 3. Interaction
        emit Deposited(_user, _token, _amount);
    }


    /**
     * @notice Allows users to withdraw Ether from their bank account
     * @param _amount The amount of Ether to withdraw (in wei)
     * @dev Implements the CEI pattern (Checks-Effects-Interactions) for security
     *      Protected against reentrancy attacks using the noReentrancy modifier
     *      Validates amount is non-zero, within user balance, and under withdrawal limit
     */
    function withdraw(address _token, uint256 _amount) external noReentrancy {
        // 1. Check
        if (_amount == 0) revert ZeroAmountNotAllowed();

        uint256 tokenBalance = balances[msg.sender][_token];
        if (tokenBalance < _amount) revert InsufficientBalance(_token, _amount, tokenBalance);

        if (_token == address(0)) {
            uint256 usdValue = convertEthToUsd(_amount);
            
            if (usdValue > MAX_WITHDRAW_USD) {
                revert WithdrawLimitExceeded(usdValue, MAX_WITHDRAW_USD);
            }
        }

        // 2. Effect
        balances[msg.sender][_token] -= _amount;
        withdrawCount++;

        // 3. Interaction
        if (_token == address(0)) {
            (bool sent, ) = payable(msg.sender).call{value: _amount}("");
            if (!sent) revert EtherTransferFailed(msg.sender, _amount);
        } else {
            IERC20(_token).safeTransfer(msg.sender, _amount);
        }

        emit Withdrawn(msg.sender, _token, _amount, usdValue);
    }


    /**
     * @notice Returns the total Ether balance held by the bank contract
     * @return The total amount of Ether in the contract in wei
     * @dev This represents the sum of all user deposits currently held by the bank
     *      This is a view function that doesn't modify state
     */
    function getBankBalance() external view returns (uint256) {
        return address(this).balance;
    }


    /**
     * @notice Returns the remaining capacity of the bank
     * @return The remaining capacity of the bank in wei
     * @dev This represents the difference between the bank capacity and the current balance
     *      This is a view function that doesn't modify state
     */
    function getRemainingCapacity() external view returns (uint256) {
        return BANK_CAP - address(this).balance;
    }
    

    /**
     * @notice Retrieves the latest ETH/USD price from the Chainlink oracle
     * @return The latest ETH/USD price with 8 decimals
     * @dev Ensures the price is greater than zero to validate oracle data
     */
    function getEthUsdPrice() internal view returns (uint256) {
        (, int256 answer,,,) = priceFeed.latestRoundData();
        
        if (answer <= 0) revert InvalidOraclePrice();
        
        return uint256(answer);
    }
    
    /**
     * @notice Converts a given amount of Ether in wei to its USD value
     * @param ethAmountWei The amount of Ether in wei to be converted
     * @return The USD value of the given Ether amount with 8 decimals
     * @dev Uses the latest ETH/USD price from the oracle for conversion
     *      The result maintains 8 decimals as per the price feed
     */
    function convertEthToUsd(uint256 ethAmountWei) internal view returns (uint256) {
        uint256 price = getEthUsdPrice();
        uint256 usdValue = (ethAmountWei * price) / ETH_DECIMALS;
        return usdValue;
    }

}