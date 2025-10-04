# KipuBank - Simple Ethereum Vault Contract

A simple Ethereum smart contract that allows users to deposit and withdraw ETH with built-in safety limits. Think of it as a personal vault with security features to prevent misuse or accidental losses.

---

## 🔹 What does this contract do?

KipuBank implements a minimal banking system with the following features:

- Users can deposit ETH into their own vault.
- Users can withdraw ETH, but with a **per-transaction limit** (0.1 ETH max).
- The bank has a **maximum capacity** — once reached, no further deposits are allowed.
- Protects against **common attacks**, including reentrancy.
- Tracks total number of deposits and withdrawals.
- Emits events for successful deposits and withdrawals.

**Security features:**

- **Withdraw limit**: Limits the maximum ETH that can be withdrawn per transaction.
- **Bank capacity**: Prevents the contract from holding more ETH than intended.
- **Reentrancy guard**: Uses a `noReentrancy` modifier to prevent malicious contract interactions.
- **CEI pattern**: Implements Checks → Effects → Interactions for secure ETH transfers.

---

## 🔹 Deployment on Remix

1. Go to [Remix](https://remix.ethereum.org)
2. Create a new file called `KipuBank.sol` and paste the contract code.
3. Compile the contract using Solidity `0.8.2` or above.
4. Go to the "Deploy & Run Transactions" tab.
5. Enter a value for `_bankCap` in **wei** (must be higher than `WITHDRAW_LIMIT`).  
   Example: `1000000000000000000` for 1 ETH.
6. Click **Deploy**.
7. Copy the contract address for interaction or verification on Etherscan.

---

## 🔹 Interacting with the Contract

Once deployed, the following functions are available:

### Depositing ETH

- **Option 1:** Call `deposit()` and enter ETH in the "Value" field.
- **Option 2:** Send ETH directly to the contract — it will automatically credit your balance.

### Withdrawing ETH

- Call `withdraw(amount)` specifying the amount in wei.  
  **Note:** Max 0.1 ETH per transaction.

Example: Withdraw 0.05 ETH → `50000000000000000` wei.

### Viewing Balances and Info

- `balances(address)` → alternative mapping view for deposited amounts.
- `depositCount` / `withdrawCount` → total number of transactions.
- `BANK_CAP` / `WITHDRAW_LIMIT` → view limits.
- `address(this).balance` → current ETH held by the bank.

### Example Workflow

1. Deploy contract with `_bankCap` = 2 ETH (`2000000000000000000` wei)
2. Deposit 0.5 ETH
3. Check your balance with `balances(your_address)`
4. Withdraw 0.1 ETH
5. Check remaining capacity: `BANK_CAP - address(this).balance`

---

## 🔹 Notes

- All amounts are in **wei** (1 ETH = 10¹⁸ wei).
- Withdraw limit is **constant** to simplify testing and reduce risk.
- Bank capacity is **immutable** after deployment.
- Contract demonstrates **Solidity best practices**: CEI pattern, reentrancy protection, custom errors, and event emission.
- Designed for **educational purposes** and as a foundation for further smart contract projects.

---

## 🔹 Contract on Etherscan

Test it on a public testnet:
https://sepolia.etherscan.io/address/0x558288c1c1db5be897b09895bc8ed592ccc1f415
