# Dune Analytics Dashboard for Expendi Vaults

This directory contains SQL queries for tracking the Expendi Vaults smart contracts on Dune Analytics.

## Prerequisites

### 1. Submit Contracts for Decoding

Before these queries will work, submit your contracts at [dune.com/contracts/new](https://dune.com/contracts/new):

| Contract | Description |
|----------|-------------|
| **TimeLock** | Non-yield-bearing time-locked escrow |
| **YieldTimeLock** | Time-locked deposits with ERC-4626 vault yield |
| **MorphoVaultDepositor** | Intermediary custodian for Morpho vaults |

For each contract:
1. Provide contract address + chain (Base recommended)
2. Upload ABI from `out/` folder (after running `forge build`)
3. Wait ~24 hours for decoding

### 2. Update Namespace

After decoding, Dune assigns a namespace. Replace `expendi_base` in all queries with your actual namespace:

```
expendi_<chain>.<ContractName>_evt_<EventName>
```

Example:
```sql
-- Before
from expendi_base.TimeLock_evt_LockCreated

-- After (if your namespace is different)
from expendi_ethereum.TimeLock_evt_LockCreated
```

## Queries

| File | Description | Visualization |
|------|-------------|---------------|
| `01_timelock_tvl.sql` | Total Value Locked by token | Counter, Table |
| `02_daily_lock_activity.sql` | Daily lock creation metrics | Area chart |
| `03_yield_performance.sql` | Yield earned per withdrawal | Line chart, Table |
| `04_fee_revenue.sql` | Weekly fee collection | Bar chart |
| `05_morpho_vault_usage.sql` | Deposit/withdrawal flows | Stacked bar |
| `06_user_cohort_analysis.sql` | User retention by cohort | Heatmap |
| `07_emergency_withdrawal_monitor.sql` | Emergency events list | Table |
| `08_lock_duration_distribution.sql` | Lock duration buckets | Pie chart |

## Dashboard Structure

Recommended dashboard layout:

### Section 1: Overview
- **TVL Counter** (Query 1 - aggregate)
- **Daily Activity Chart** (Query 2)

### Section 2: TimeLock Analytics
- **Lock Duration Distribution** (Query 8)
- **Daily Locks Created** (Query 2)

### Section 3: YieldTimeLock Analytics
- **Yield Performance Over Time** (Query 3)
- **Fee Revenue** (Query 4)

### Section 4: MorphoVaultDepositor
- **Net Flows by Vault** (Query 5)
- **Depositor Activity** (Query 5)

### Section 5: Users
- **Cohort Retention Heatmap** (Query 6)
- **Unique Depositors Counter** (Query 2)

### Section 6: Monitoring
- **Emergency Withdrawals Table** (Query 7)

## Event Reference

### TimeLock Events
```solidity
event LockCreated(uint256 indexed lockId, address indexed depositor, address indexed token, uint256 amount, uint256 unlockTime)
event Withdrawn(uint256 indexed lockId, address indexed depositor, address indexed token, uint256 amount)
event LockExtended(uint256 indexed lockId, uint256 oldUnlockTime, uint256 newUnlockTime)
```

### YieldTimeLock Events
```solidity
event YieldLockCreated(uint256 indexed lockId, address indexed depositor, address indexed vault, address underlyingToken, uint256 principalAssets, uint256 shares, uint256 unlockTime, string label)
event YieldLockWithdrawn(uint256 indexed lockId, address indexed depositor, address indexed vault, uint256 shares, uint256 totalAssets, uint256 fee, uint256 netAssets)
event EmergencyWithdrawal(uint256 indexed lockId, address indexed vault, uint256 shares, uint256 assets)
event FeeCollected(uint256 indexed lockId, address indexed token, uint256 amount)
```

### MorphoVaultDepositor Events
```solidity
event Deposited(address indexed user, address indexed vault, uint256 assets, uint256 shares)
event WithdrawnFromVault(address indexed user, address indexed vault, uint256 shares, uint256 assets)
event FeeCollected(address indexed vault, address indexed token, uint256 amount)
```

## Notes

- All queries use `/1e18` for decimal adjustment - modify if tokens have different decimals
- Join with `tokens.erc20` for accurate decimal handling per token
- Add `contract_address` filter if deploying multiple contract instances
- Time filters default to recent data; adjust intervals as needed
