// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;


/**
 * @title KipuBank
 * @notice A simple vault contract that allows users to deposit and withdraw Ether with safety limits
 * @dev This contract implements a basic banking system with the following features:
 *      - Deposit functionality with bank capacity limits
 *      - Withdrawal functionality with per-transaction limits
 *      - Reentrancy protection using a custom modifier
 *      - Event emission for all deposits and withdrawals
 *      - Custom error handling for various failure scenarios
 * 
 * Security Features:
 * - Maximum bank capacity to prevent excessive funds accumulation
 * - Per-withdrawal limit to control risk exposure
 * - Reentrancy guard to prevent malicious contract interactions
 * - CEI pattern (Checks-Effects-Interactions) implementation
 * 
 * @author Gabriel Neutzling
 * @custom:educational This contract is designed for learning purposes and demonstrates
 *                      custom errors, events, modifiers, and best practices in Solidity
 */
contract KipuBank {
    /**
     * @notice Thrown when a deposit would exceed the bank's maximum capacity
     * @param totalBalance The current total balance in the bank
     * @param depositAmount The amount being deposited
     * @param bankCap The maximum capacity allowed for the bank
     */
    error BankCapacityExceeded(uint256 totalBalance, uint256 depositAmount, uint256 bankCap);
    
    /**
     * @notice Thrown when a withdrawal amount exceeds the per-transaction limit
     * @param requested The amount requested for withdrawal
     * @param limit The maximum amount allowed per withdrawal
     */
    error WithdrawLimitExceeded(uint256 requested, uint256 limit);
    
    /**
     * @notice Thrown when a user attempts to withdraw more than their account balance
     * @param requested The amount the user requested to withdraw
     * @param accountBalance The user's current account balance
     */
    error InsufficientBalance(uint256 requested, uint256 accountBalance);
    
    /**
     * @notice Thrown when a zero amount is provided for operations that require a positive value
     */
    error ZeroAmountNotAllowed();
    
    /**
     * @notice Thrown when the Ether transfer to the user fails during withdrawal
     * @param receiver The address that should have received the Ether
     * @param amount The amount that failed to transfer
     */
    error EtherTransferFailed(address receiver, uint256 amount);
    
    /**
     * @notice Thrown when contract initialization fails due to invalid parameters
     * @param bankCap The bank capacity value that caused the failure
     * @param withdrawLimit The withdraw limit value used for validation
     */
    error InvalidConstructorParams(uint256 bankCap, uint256 withdrawLimit);
    
    /**
     * @notice Thrown when a reentrancy attack is detected
     * @dev This error is triggered by the noReentrancy modifier when the locked state is true
     */
    error ReentrancyDetected();


    /**
     * @notice Emitted when a user successfully deposits Ether into the bank
     * @param user The address of the user who made the deposit
     * @param amount The amount of Ether deposited in wei
     */
    event Deposited(address indexed user, uint256 amount);
    
    /**
     * @notice Emitted when a user successfully withdraws Ether from the bank
     * @param user The address of the user who made the withdrawal
     * @param amount The amount of Ether withdrawn in wei
     */
    event Withdrawn(address indexed user, uint256 amount);


    /**
     * @notice Maximum amount that can be withdrawn in a single transaction
     * @dev Set to 0.1 ether to limit risk exposure per withdrawal
     */
    uint256 public constant WITHDRAW_LIMIT = 0.1 ether;
    
    /**
     * @notice Maximum total capacity the bank can hold
     * @dev Set during contract deployment and cannot be changed afterwards
     */
    uint256 public immutable BANK_CAP;
    
    /**
     * @notice Mapping of user addresses to their deposited balances
     * @dev Tracks how much Ether each user has deposited in the bank
     */
    mapping(address => uint256) public balances;
    
    /**
     * @notice Total number of deposits made to the bank
     * @dev Incremented with each successful deposit operation
     */
    uint256 public depositCount = 0;
    
    /**
     * @notice Total number of withdrawals made from the bank
     * @dev Incremented with each successful withdrawal operation
     */
    uint256 public withdrawCount = 0;
    
    /**
     * @dev Reentrancy guard state variable
     * @notice Used by the noReentrancy modifier to prevent reentrancy attacks
     */
    bool private locked;


    /**
     * @notice Initializes the KipuBank contract with a maximum capacity
     * @param _bankCap The maximum amount of Ether the bank can hold
     * @dev The bank capacity must be greater than the withdraw limit and non-zero
     */
    constructor(uint256 _bankCap) {
        if (_bankCap == 0 || _bankCap <= WITHDRAW_LIMIT) revert InvalidConstructorParams(_bankCap, WITHDRAW_LIMIT);

        BANK_CAP = _bankCap;
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
        _deposit(msg.sender, msg.value);
    }

    
    /**
     * @notice Allows users to deposit Ether into their bank account
     * @dev Calls the internal _deposit function to handle the deposit logic
     *      Requires sending Ether with the transaction (payable)
     */
    function deposit() external payable {
        _deposit(msg.sender, msg.value);
    }


    /**
     * @notice Internal function to handle deposit logic
     * @param _user The address of the user making the deposit
     * @param _amount The amount of Ether being deposited (in wei)
     * @dev Validates amount is non-zero and doesn't exceed bank capacity
     *      Updates user balance and deposit count, then emits Deposited event
     *      Used by both deposit() function and receive() function
     */
    function _deposit(address _user, uint256 _amount) private {
        uint256 prevBalance = address(this).balance - _amount;
        uint256 totalAfter = prevBalance + _amount;

        // 1. Check
        if (_amount == 0) revert ZeroAmountNotAllowed();
        if (totalAfter > BANK_CAP) revert BankCapacityExceeded(prevBalance, _amount, BANK_CAP);

        // 2. Effect
        balances[_user] += _amount;
        depositCount++;

        // 3. Interaction
        emit Deposited(_user, _amount);
    }


    /**
     * @notice Allows users to withdraw Ether from their bank account
     * @param _amount The amount of Ether to withdraw (in wei)
     * @dev Implements the CEI pattern (Checks-Effects-Interactions) for security
     *      Protected against reentrancy attacks using the noReentrancy modifier
     *      Validates amount is non-zero, within user balance, and under withdrawal limit
     */
    function withdraw(uint256 _amount) external noReentrancy {
        // 1. Check
        if (_amount == 0) revert ZeroAmountNotAllowed();
        if (balances[msg.sender] < _amount) revert InsufficientBalance(_amount, balances[msg.sender]);
        if (_amount > WITHDRAW_LIMIT) revert WithdrawLimitExceeded(_amount, WITHDRAW_LIMIT);

        // 2. Effect
        balances[msg.sender] -= _amount;
        withdrawCount++;

        // 3. Interaction
        address payable receiver = payable(msg.sender);
        (bool sent,) = receiver.call{value: _amount}("");

        if (!sent) revert EtherTransferFailed(receiver, _amount);

        emit Withdrawn(msg.sender, _amount);
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
}