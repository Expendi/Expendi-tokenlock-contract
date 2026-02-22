# **CHAINCHECK SECURITY REVIEW**
## **Auditors**
1) Craig - Lead Security Researcher
2) 0xf4ld3 - Lead Security Researcher

## **About ChainCheck Audits**
- ChainCheck Audits is a blockchain security marketplace that connects leading security researchers and auditing specialists with projects seeking robust security assurance.

## **Disclaimer**
ChainCheck Audits provides an in-depth assessment of a project’s security posture based on the code available at a specific point in time. While every effort is made to identify potential security vulnerabilities and implementation risks, the review cannot guarantee that all issues will be uncovered or that the codebase will remain immune to every possible attack vector. This evaluation applies only to the exact code version and commit that were reviewed. Any subsequent modifications may introduce new vulnerabilities not covered in this report. Therefore, projects are strongly advised to request a follow-up review after making any changes to the code. Please note that this assessment should not be considered a substitute for continuous security practices such as penetration testing, automated vulnerability scanning, and periodic internal or external audits. 

## **Risk Assessment**
------------------------------------------------------------------------------------------------------------------------------------
| **Severity** |     **Description**                                                                                                    
|--------------|--------------------------------------------------------------------------------------------------------------------
| Critical     |  Must be fixed immediately (especially if the system is already deployed).
| High         |  Can result in significant asset loss (>10%) or major impact on most users. 
| Medium       |  May cause limited losses (<10%) or affect only a few users but remains unacceptable. 
| Low          |  Minor issues causing limited or temporary disruption; includes griefing or inefficiency risks. 
| Gas Optimization  |  Recommendations for improving gas efficiency and reducing operational costs. 
| Informational |  Non-critical insights, best practices, or suggestions for improving code readability and maintainability. 
------------------------------------------------------------------------------------------------------------------------------------

## **Severity Classification** 
Each issue identified during the review is classified according to its potential impact and likelihood of exploitation. 
- Critical vulnerabilities pose an immediate and severe threat; these must be resolved urgently. 
- High severity issues are easily exploitable or highly incentivized and should be addressed as soon as possible.
- Medium severity issues are plausible under specific conditions or with moderate incentive and should be remediated promptly. 
- Low severity findings require unlikely conditions to exploit or pose minimal incentive but should still be fixed for completeness. 
- Gas Optimization and Informational findings do not directly impact security but represent meaningful improvements to performance, efficiency, and code quality.

# **Expendi TokenLock Contract Security Review**

--- 

## **Auditor Overview:**

- **Project:** Expendi TokenLock Contract Security Review
- **Github Repo:** https://github.com/Expendi/Expendi-tokenlock-contract/blob/main/expendi-contract-integrations/src/YieldTimeLock.sol
- **Commit Hash:** 23204ad3a0e5de30c19c90402d810145d76ccd76
- **Auditor:** ChainCheck Audits
- **Audit Duration:** February 18-21, 2026
- **Total Issues:** 5(1 Medium, 1 Low and 3 Informational)
- **Contract Version:**  0.8.20

## **Summary**
- Smart contract for time-locked deposits into Morpho ERC-4626 vaults with yield generation.

## **Detailed Findings**

---

### **Medium Findings**

---

#### **M-1: No Batch `YieldTimeLock.emergencyWithdraw()` — Manual Per-Lock Processing Is Operationally Risky**

#### **Severity: Medium**

#### **Description**
`YieldTimeLock.emergencyWithdraw()` processes exactly one lock per transaction. In the event of a vault exploit or emergency affecting many users, the owner must submit one transaction per lock. Under network congestion, it may be practically impossible to rescue all locks before the vault becomes entirely insolvent or further drained. The lack of a batching mechanism creates a operational scalability limitation during time-critical incidents during time-critical incidents.

#### **Root Cause**
Function `emergencyWithdraw(uint256 lockId)` accepts only a single lock ID. There is no loop or batch variant available.

#### **Impact**
- In a mass emergency scenario, some depositors will inevitably have their funds left in a failing vault longer than necessary, potentially losing more value while the owner processes locks one-by-one.

#### **Recommendation**
- Implement a batch emergency withdrawal function that accepts an array of lock IDs.

#### **Example Fix:**
```solidity
function emergencyWithdrawBatch(uint256[] memory lockIds) external onlyOwner nonReentrant {
    for (uint256 i = 0; i < lockIds.length; i++) {
        uint256 lockId = lockIds[i];
        YieldLock storage lock = yieldLocks[lockId];
        if (lock.withdrawn || lock.isEmergencyWithdrawn) revert LockAlreadyProcessed();

        lock.isEmergencyWithdrawn = true;
        uint256 assetsReceived = IMorphoVault(lock.vault).redeem(lock.shares, address(this), address(this));
        emergencyAssets[lockId] = assetsReceived;

        emit EmergencyWithdrawal(lockId, lock.vault, lock.shares, assetsReceived);
    }
}
```

---

### **Low Findings**

---

#### **L-1: Unbounded Loops in `YieldTimeLock.getUserLocksByLabel()`**

#### **Severity: Low**

#### **Root Cause**
`YieldTimeLock.getUserLocksByLabel()` performs two full iterations over a user's entire lock history. A user with a very large number of locks (e.g., a contract that creates many locks) can cause this view function to run out of gas, making it uncallable.

#### **Impact**
- Off-chain integrations and frontends relying on `YieldTimeLock.getUserLocksByLabel()` will fail when called. While this is a view function and does not affect on-chain state, it degrades protocol usability.

#### **Recommendation**
- Consider adding pagination parameters (offset, limit) to the function.

---

### **Informational**

---

#### **I-1: `YieldTimeLock.extendLock()` Can Be Called on Already-Withdrawn or Non-Existent Locks**

#### **Severity: Informational**

#### **Root Cause**
`YieldTimeLock.extendLock` has no check for `lock.withdrawn`, `lock.isEmergencyWithdrawn`, or whether the `lockId` actually exists (i.e., `lock.depositor != address(0)`). Since `yieldLocks` is a mapping, accessing a non-existent ID returns a zero-initialized struct where `unlockTime == 0`, and any `newUnlockTime > 0` will pass the check.

#### **Impact**
- The owner can extend the unlock time of locks that have already been withdrawn or that do not exist, emitting misleading `LockExtended` events. While this has no on-chain financial consequence for completed locks, it pollutes the event log and may confuse indexers or frontends.

#### **Recommendation**
- Add guards to `extendLock`:

#### **Example Fix:**

```solidity
function extendLock(uint256 lockId, uint256 newUnlockTime) external onlyOwner {
    YieldLock storage lock = yieldLocks[lockId];
    if (lock.depositor == address(0)) revert LockDoesNotExist();
    if (lock.withdrawn || lock.isEmergencyWithdrawn) revert LockAlreadyProcessed();
    if (newUnlockTime <= lock.unlockTime) revert NewUnlockTimeMustBeAfterCurrent();

    uint256 oldUnlockTime = lock.unlockTime;
    lock.unlockTime = newUnlockTime;
    emit LockExtended(lockId, oldUnlockTime, newUnlockTime);
}
```

---

#### **I-2: `YieldTimeLock.isUnlocked()` Returns `true` for Non-Existent Lock IDs**

#### **Severity: Informational**

#### **Root Cause**
For a lock ID that has never been created, `yieldLocks[lockId].unlockTime` returns `0`. Since `block.timestamp >= 0` is always true, `YieldTimeLock.isUnlocked()` returns `true` for any non-existent lock.

#### **Impact**
- Callers relying on `YieldTimeLock.isUnlocked()` may incorrectly treat a non-existent lock as "ready to withdraw," causing confusion to indexers or failed transactions downstream.

#### **Recommendation**
- Check for lock existence before evaluating the unlock time:

#### **Example Fix:**
```solidity
function isUnlocked(uint256 lockId) external view returns (bool unlocked) {
    YieldLock storage lock = yieldLocks[lockId];
    if (lock.depositor == address(0)) revert LockDoesNotExist();
    unlocked = block.timestamp >= lock.unlockTime;
}
```

---

#### **I-3: `YieldTimeLock.previewWithdraw()` and `YieldTimeLock.getAccruedYield()` Return Stale Values After Withdrawal**

#### **Severity: Informational**

#### **Root Cause**
After a lock is withdrawn, `lock.shares` still holds the original share count and `lock.principalAssets` retains the original deposit amount. `YieldTimeLock.previewWithdraw()` calls `IMorphoVault(lock.vault).previewRedeem(lock.shares)` on shares that no longer exist in the YieldTimeLock's vault position. `YieldTimeLock.getAccruedYield()` similarly uses the stale share balance. Neither function checks `lock.withdrawn`.

#### **Impact**
- These view functions silently return incorrect values for locks that have already been fully redeemed, misleading users or integrators who query historical locks.

#### **Recommendation**
- Add a check for `lock.withdrawn` at the start of both view functions and return `(0, 0, 0)`:

#### **Example Fix:**
```solidity
function previewWithdraw(uint256 lockId)
    external view returns (uint256 totalAssets, uint256 fee, uint256 netAssets)
{
    YieldLock storage lock = yieldLocks[lockId];
    if (lock.withdrawn) return (0, 0, 0);
    // ... rest of logic
}
```
