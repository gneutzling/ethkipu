# KipuBank - Multi-Token Ethereum Vault Contract

A comprehensive Ethereum smart contract that allows users to deposit and withdraw both ETH and ERC20 tokens with built-in safety limits and price protection. Think of it as a secure vault with advanced features to prevent misuse and protect against market volatility.

---

## 🔹 What does this contract do?

KipuBank implements a modern banking system with the following features:

- Users can deposit **ETH** and **ERC20 tokens** into their vault.
- Users can withdraw tokens, but with a **USD value limit** ($1000 max per transaction).
- **Real-time price protection** using Chainlink ETH/USD price feeds.
- The bank has a **maximum capacity** — once reached, no further ETH deposits are allowed.
- **Manager role** for fund recovery and administrative functions.
- Protects against **common attacks**, including reentrancy and stale price data.
- Tracks total number of deposits and withdrawals.
- Emits events for successful deposits and withdrawals.

**Security features:**

- **USD withdrawal limit**: Limits withdrawals to $1000 USD value per transaction (prevents large losses during price volatility).
- **Bank capacity**: Prevents the contract from holding more ETH than intended.
- **Price feed validation**: Ensures price data is fresh (max 1 hour old) and valid.
- **Reentrancy guard**: Uses a `noReentrancy` modifier to prevent malicious contract interactions.
- **CEI pattern**: Implements Checks → Effects → Interactions for secure token transfers.
- **Access control**: Manager role for administrative functions with proper role-based permissions.

---

## 🔹 Deployment on Remix

1. Go to [Remix](https://remix.ethereum.org)
2. Create a new file called `KipuBank.sol` and paste the contract code.
3. Compile the contract using Solidity `0.8.30` or above.
4. Go to the "Deploy & Run Transactions" tab.
5. Enter parameters for deployment:
   - `_bankCap`: Bank capacity in **wei** (e.g., `1000000000000000000` for 1 ETH)
   - `_priceFeed`: Chainlink ETH/USD price feed address
     - **Sepolia testnet**: `0x694AA1769357215DE4FAC081bf1f309aDC325306`
     - **Mainnet**: `0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419`
6. Click **Deploy**.
7. Copy the contract address for interaction or verification on Etherscan.

---

## 🔹 Interacting with the Contract

Once deployed, the following functions are available:

### Depositing Tokens

**ETH Deposits:**

- **Option 1:** Call `deposit(address(0), 0)` and enter ETH in the "Value" field.
- **Option 2:** Send ETH directly to the contract — it will automatically credit your balance.

**ERC20 Token Deposits:**

- Call `deposit(tokenAddress, amount)` specifying the token address and amount.
- **Note:** You must first approve the contract to spend your tokens.

### Withdrawing Tokens

**ETH Withdrawals:**

- Call `withdraw(address(0), amount)` specifying the amount in wei.
- **Note:** Max $1000 USD value per transaction (calculated using Chainlink price feed).

**ERC20 Token Withdrawals:**

- Call `withdraw(tokenAddress, amount)` specifying the token address and amount.
- **Note:** No USD limit for ERC20 tokens, only ETH withdrawals are limited.

### Viewing Balances and Info

- `balances(userAddress, tokenAddress)` → view deposited amounts for specific tokens.
- `depositCount` / `withdrawCount` → total number of transactions.
- `BANK_CAP` → maximum ETH capacity.
- `getBankBalance()` → current ETH held by the bank.
- `getRemainingCapacity()` → remaining ETH capacity.
- `balanceInUSDCDecimals(userAddress, tokenAddress)` → balance converted to 6-decimal accounting units.

### Manager Functions (Admin Only)

- `recoverFunds(userAddress, tokenAddress, newBalance)` → adjust user balances (emergency recovery).

### Example Workflow

1. Deploy contract with `_bankCap` = 2 ETH and Chainlink price feed
2. Deposit 0.5 ETH: `deposit(address(0), 0)` with 0.5 ETH value
3. Deposit USDC: First approve USDC contract, then `deposit(usdcAddress, 1000000000)` (1000 USDC)
4. Check ETH balance: `balances(your_address, 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)`
5. Withdraw 0.1 ETH: `withdraw(address(0), 100000000000000000)` (if ETH price < $10,000)
6. Withdraw USDC: `withdraw(usdcAddress, 500000000)` (500 USDC)

---

## 🔹 Notes

- All amounts are in **wei** for ETH (1 ETH = 10¹⁸ wei) and **token units** for ERC20 tokens.
- ETH withdrawal limit is **$1000 USD** calculated using Chainlink price feeds (prevents large losses during volatility).
- Bank capacity only applies to **ETH deposits** (ERC20 tokens have no capacity limit).
- Price feed data must be **fresh** (max 1 hour old) for ETH withdrawals to succeed.
- Contract uses **OpenZeppelin** libraries for security and **Chainlink** for price feeds.
- **Manager role** can recover funds in emergency situations (requires proper access control).
- Contract demonstrates **Solidity best practices**: CEI pattern, reentrancy protection, custom errors, typed values, and event emission.
- Designed for **educational purposes** and as a foundation for production-ready DeFi applications.

### Testing with Mock Tokens

For testing purposes, deploy the included `MockERC20.sol` contract:

1. Deploy MockERC20 with name, symbol, and initial supply
2. Use the mock token address for testing ERC20 deposits/withdrawals
3. Example: Deploy with name "Test USDC", symbol "tUSDC", supply 1000000

---

## 🔹 Contract on Etherscan

Test it on a public testnet:
https://sepolia.etherscan.io/address/0x558288c1c1db5be897b09895bc8ed592ccc1f415
