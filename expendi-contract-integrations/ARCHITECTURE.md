# Expendi Contract Integrations -- Architecture

## 1. Overview

This project contains two Solidity smart contracts built for the **Expendi platform**, compiled with Solidity 0.8.20 using the Foundry toolchain.

| Contract | Purpose |
|---|---|
| **TimeLock** | Lock ETH or ERC-20 tokens for a fixed duration without generating yield. Funds are returned to the original depositor once the lock period expires. |
| **MorphoVaultDepositor** | Deposit ERC-20 tokens into Morpho MetaMorpho ERC-4626 vaults on Ethereum mainnet, earning yield while the contract custodies vault shares on behalf of users. |

Both contracts inherit from OpenZeppelin's `Ownable` and `ReentrancyGuard`, and both target the Ethereum network.

---

## 2. Contract Architecture

### 2.1 TimeLock Contract

**Source:** `src/TimeLock.sol`

#### Purpose and Design Rationale

TimeLock provides a simple, non-yield-bearing escrow mechanism. Users deposit ETH or ERC-20 tokens together with a future unlock timestamp. The deposited assets are held by the contract until that timestamp is reached, at which point only the original depositor may withdraw. This pattern is useful for vesting schedules, commitment mechanisms, or any scenario that requires provably locked funds without DeFi yield exposure.

#### State Variables

```solidity
struct Lock {
    address depositor;   // the address entitled to withdraw
    address token;       // ERC-20 token address, or address(0) for native ETH
    uint256 amount;      // locked amount in base units
    uint256 unlockTime;  // Unix timestamp after which withdrawal is allowed
    bool withdrawn;      // whether funds have already been claimed
}

mapping(uint256 => Lock) public locks;          // lockId => Lock
mapping(address => uint256[]) public userLocks; // user => array of lockIds
uint256 public nextLockId;                      // auto-incrementing counter
```

- **`locks`** -- The canonical store of every lock ever created, keyed by a unique auto-incrementing ID.
- **`userLocks`** -- A reverse index allowing enumeration of all locks belonging to a given address.
- **`nextLockId`** -- A monotonically increasing counter that ensures each lock receives a unique identifier starting from 0.

#### Lock Lifecycle

```
  User calls              Time passes              User calls
  lockETH() or            until                    withdraw()
  lockERC20()             block.timestamp >=
                          unlockTime
 +-----------+          +-----------+            +-----------+
 |  CREATE   |  ----->  |   WAIT    |  ------>   | WITHDRAW  |
 +-----------+          +-----------+            +-----------+
                              |
                              | Owner calls extendLock()
                              | (pushes unlockTime further)
                              v
                        +-----------+
                        | WAIT MORE |
                        +-----------+
```

1. **Create** -- The depositor calls `lockETH` (with `msg.value`) or `lockERC20` (with a prior ERC-20 approval). A `Lock` struct is written to storage and the lock ID is returned.
2. **Wait** -- Funds sit in the contract. The contract owner may call `extendLock` to push the unlock time further into the future, but can never shorten it.
3. **Withdraw** -- Once `block.timestamp >= unlockTime`, the original depositor calls `withdraw(lockId)`. The `withdrawn` flag is set to `true` and funds are transferred back.

#### Access Control Model

| Role | Capabilities |
|---|---|
| **Depositor** (`msg.sender` at lock creation) | Create locks, withdraw after expiry |
| **Owner** (set at construction, transferable via `Ownable`) | Extend lock periods via `extendLock`. Cannot shorten locks. Cannot withdraw any user funds. |

This separation ensures that an administrative entity can enforce longer holding periods (e.g., for compliance) but can never access deposited funds.

#### Security Features

- **ReentrancyGuard** -- The `nonReentrant` modifier is applied to `lockETH`, `lockERC20`, and `withdraw`, preventing reentrant calls during ETH transfers.
- **Checks-effects-interactions** -- In `withdraw`, the `lock.withdrawn` flag is set to `true` *before* the external ETH or token transfer is made.
- **SafeERC20** -- All ERC-20 interactions use OpenZeppelin's `SafeERC20` wrapper (`safeTransferFrom`, `safeTransfer`), which handles tokens that do not return a boolean on `transfer`/`transferFrom`.
- **Custom errors** -- Gas-efficient revert reasons replace `require` strings.

#### Function Descriptions

| Function | Visibility | Modifier | Parameters | Returns | Description |
|---|---|---|---|---|---|
| `lockETH` | `external payable` | `nonReentrant` | `uint256 unlockTime` | `uint256 lockId` | Locks `msg.value` of native ETH until `unlockTime`. |
| `lockERC20` | `external` | `nonReentrant` | `address token, uint256 amount, uint256 unlockTime` | `uint256 lockId` | Transfers `amount` of `token` from caller and locks until `unlockTime`. |
| `withdraw` | `external` | `nonReentrant` | `uint256 lockId` | -- | Withdraws funds from an expired lock. Caller must be the original depositor. |
| `extendLock` | `external` | `onlyOwner` | `uint256 lockId, uint256 newUnlockTime` | -- | Extends the unlock time. `newUnlockTime` must be strictly greater than the current value. |
| `getLock` | `external view` | -- | `uint256 lockId` | `Lock memory` | Returns the full `Lock` struct for a given ID. |
| `getUserLockIds` | `external view` | -- | `address user` | `uint256[] memory` | Returns all lock IDs belonging to `user`. |
| `isUnlocked` | `external view` | -- | `uint256 lockId` | `bool` | Returns `true` if `block.timestamp >= lock.unlockTime`. |

#### Events

| Event | Indexed Fields | Description |
|---|---|---|
| `LockCreated(uint256 lockId, address depositor, address token, uint256 amount, uint256 unlockTime)` | `lockId`, `depositor`, `token` | Emitted when a new lock is created. |
| `Withdrawn(uint256 lockId, address depositor, address token, uint256 amount)` | `lockId`, `depositor`, `token` | Emitted when a lock is successfully withdrawn. |
| `LockExtended(uint256 lockId, uint256 oldUnlockTime, uint256 newUnlockTime)` | `lockId` | Emitted when the owner extends a lock's duration. |

#### Custom Errors

| Error | Condition |
|---|---|
| `UnlockTimeNotInFuture()` | `unlockTime <= block.timestamp` at lock creation. |
| `AmountMustBeGreaterThanZero()` | `msg.value == 0` for ETH or `amount == 0` for ERC-20. |
| `NotDepositor()` | Caller of `withdraw` is not the original depositor. |
| `LockNotExpired()` | `block.timestamp < lock.unlockTime` at withdrawal. |
| `AlreadyWithdrawn()` | The lock has already been withdrawn. |
| `NewUnlockTimeMustBeAfterCurrent()` | `newUnlockTime <= lock.unlockTime` in `extendLock`. |
| `InvalidTokenAddress()` | `token == address(0)` passed to `lockERC20` (use `lockETH` instead). |
| `ETHTransferFailed()` | Low-level ETH `.call` returned `false`. |

---

### 2.2 MorphoVaultDepositor Contract

**Source:** `src/MorphoVaultDepositor.sol`

#### Purpose and Design Rationale

MorphoVaultDepositor acts as an intermediary custodian that deposits user assets into Morpho MetaMorpho vaults and tracks ownership of vault shares internally. Rather than users interacting with Morpho vaults directly, the Expendi platform routes deposits through this contract so that:

1. Only owner-whitelisted vaults can be used, preventing interaction with malicious or untrusted vault contracts.
2. The contract maintains an internal accounting ledger of per-user, per-vault share balances, enabling the platform to attribute yield accurately.
3. The contract holds the actual ERC-4626 vault shares on behalf of all users, simplifying the custody model.

#### Interaction with Morpho MetaMorpho Vaults (ERC-4626)

MetaMorpho vaults implement the ERC-4626 tokenized vault standard. This contract interacts with them through the `IMorphoVault` interface, calling:

- `vault.asset()` -- to discover the underlying ERC-20 token.
- `vault.deposit(assets, receiver)` -- to deposit underlying tokens and receive shares.
- `vault.redeem(shares, receiver, owner)` -- to burn shares and receive underlying tokens.

#### Vault Whitelist Management

The contract owner maintains a whitelist of approved vault addresses:

```solidity
mapping(address => bool) public whitelistedVaults;
address[] public vaultList;
```

- `addVault(address vault)` -- Adds a vault to the whitelist and appends it to `vaultList`. Reverts if the vault is already whitelisted or is the zero address.
- `removeVault(address vault)` -- Sets the whitelist flag to `false` and removes the vault from `vaultList` using a swap-and-pop pattern. Existing user shares in the removed vault are preserved but deposits and withdrawals are blocked until the vault is re-added.

Both functions are restricted to the contract owner via the `onlyOwner` modifier.

#### Deposit Flow

```
  User                   MorphoVaultDepositor              Morpho Vault
   |                            |                              |
   |-- approve(depositor, N) -->|                              |
   |-- depositToVault(vault,N)->|                              |
   |                            |-- safeTransferFrom(user) --->|
   |                            |-- forceApprove(vault, N) --->|
   |                            |-- vault.deposit(N, self) --->|
   |                            |<--- shares ------------------|
   |                            |                              |
   |                            | userShares[user][vault] += shares
   |                            |                              |
   |<-- emit Deposited --------|                              |
```

1. The user approves the depositor contract to spend `amount` of the vault's underlying asset.
2. The user calls `depositToVault(vault, amount)`.
3. The contract transfers the tokens from the user to itself via `safeTransferFrom`.
4. The contract approves the vault to pull the tokens using `forceApprove` (handles non-standard ERC-20 tokens that require setting allowance to zero before setting a new value).
5. The contract calls `vault.deposit(amount, address(this))` -- the vault mints shares to the depositor contract.
6. The internal ledger `userShares[msg.sender][vault]` is incremented by the shares received.

#### Withdrawal Flow

```
  User                   MorphoVaultDepositor              Morpho Vault
   |                            |                              |
   |-- withdrawFromVault ------>|                              |
   |       (vault, shares)      |                              |
   |                            | userShares[user][vault] -= shares
   |                            |                              |
   |                            |-- vault.redeem(shares, ----->|
   |                            |      user, self)             |
   |                            |<--- assets ------------------|
   |<-- assets transferred -----|                              |
   |<-- emit WithdrawnFromVault-|                              |
```

1. The user calls `withdrawFromVault(vault, shares)`.
2. The contract verifies the vault is whitelisted and the user has sufficient tracked shares.
3. The internal ledger is decremented **before** the external call (checks-effects-interactions).
4. The contract calls `vault.redeem(shares, msg.sender, address(this))` -- the vault burns shares owned by the depositor contract and sends the underlying assets directly to the user.

#### Internal Share Accounting

```solidity
mapping(address => mapping(address => uint256)) public userShares;
// userShares[user][vault] = number of vault shares attributed to user
```

This double mapping tracks the fractional ownership each user has in each vault. The actual ERC-4626 shares are held by the contract itself (its `balanceOf` on the vault token), while the `userShares` mapping records the attribution. This means the sum of all `userShares[*][vault]` for a given vault should equal the contract's share balance in that vault under normal operation.

#### Security Features

- **ReentrancyGuard** -- Applied to `depositToVault` and `withdrawFromVault`.
- **Checks-effects-interactions** -- `userShares` is decremented before calling `vault.redeem` in `withdrawFromVault`.
- **SafeERC20 with `forceApprove`** -- `forceApprove` is used instead of `approve` to handle tokens like USDT that require the allowance to be set to zero before setting a non-zero value.
- **Vault whitelist** -- Only owner-approved vaults can be deposited into or withdrawn from, preventing interaction with arbitrary external contracts.
- **Zero-address checks** -- `addVault` rejects `address(0)`.

#### Function Descriptions

| Function | Visibility | Modifier | Parameters | Description |
|---|---|---|---|---|
| `depositToVault` | `external` | `nonReentrant` | `address vault, uint256 amount` | Deposits `amount` of the vault's underlying asset. Shares are tracked internally for the caller. |
| `withdrawFromVault` | `external` | `nonReentrant` | `address vault, uint256 shares` | Redeems `shares` from the vault and sends the underlying assets to the caller. |
| `addVault` | `external` | `onlyOwner` | `address vault` | Adds a vault to the whitelist. |
| `removeVault` | `external` | `onlyOwner` | `address vault` | Removes a vault from the whitelist. |
| `getUserShares` | `external view` | -- | `address user, address vault` | Returns the tracked share balance for a user in a specific vault. |
| `isVaultWhitelisted` | `external view` | -- | `address vault` | Returns whether a vault is currently whitelisted. |
| `getVaultList` | `external view` | -- | -- | Returns the array of all currently whitelisted vault addresses. |

#### Events

| Event | Indexed Fields | Description |
|---|---|---|
| `Deposited(address user, address vault, uint256 assets, uint256 shares)` | `user`, `vault` | Emitted on successful deposit. |
| `WithdrawnFromVault(address user, address vault, uint256 shares, uint256 assets)` | `user`, `vault` | Emitted on successful share redemption. |
| `VaultAdded(address vault)` | `vault` | Emitted when a vault is added to the whitelist. |
| `VaultRemoved(address vault)` | `vault` | Emitted when a vault is removed from the whitelist. |

#### Custom Errors

| Error | Condition |
|---|---|
| `VaultNotWhitelisted()` | The target vault is not on the whitelist. |
| `AmountMustBeGreaterThanZero()` | Deposit `amount` is zero. |
| `SharesMustBeGreaterThanZero()` | Withdrawal `shares` is zero. |
| `InsufficientShares()` | User's tracked share balance is less than the requested redemption. |
| `VaultAlreadyWhitelisted()` | Attempting to add a vault that is already whitelisted. |
| `VaultNotInWhitelist()` | Attempting to remove a vault that is not whitelisted. |
| `ZeroAddress()` | `address(0)` passed to `addVault`. |

---

## 3. Interfaces

### IERC4626

**Source:** `src/interfaces/IERC4626.sol`

The standard [ERC-4626 Tokenized Vault](https://eips.ethereum.org/EIPS/eip-4626) interface. It defines a common API for yield-bearing vaults that accept deposits of a single underlying ERC-20 token and issue shares representing proportional ownership of the vault's assets.

This project uses IERC4626 because Morpho MetaMorpho vaults are fully ERC-4626 compliant. Key functions used by the depositor contract:

```solidity
function deposit(uint256 assets, address receiver) external returns (uint256 shares);
function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
function asset() external view returns (address assetTokenAddress);
```

The interface also includes accounting view functions (`totalAssets`, `convertToShares`, `convertToAssets`), capacity functions (`maxDeposit`, `maxMint`, `maxWithdraw`, `maxRedeem`), and preview functions (`previewDeposit`, `previewMint`, `previewWithdraw`, `previewRedeem`) that are available for off-chain or on-chain integrations but are not directly called by the depositor contract.

### IMorphoVault

**Source:** `src/interfaces/IMorphoVault.sol`

Extends `IERC4626` with the ERC-20 functions needed to manage the vault's share token:

```solidity
interface IMorphoVault is IERC4626 {
    function balanceOf(address account) external view returns (uint256 balance);
    function allowance(address owner, address spender) external view returns (uint256 remaining);
    function approve(address spender, uint256 amount) external returns (bool success);
    function transfer(address to, uint256 amount) external returns (bool success);
    function transferFrom(address from, address to, uint256 amount) external returns (bool success);
}
```

MetaMorpho vault shares are themselves ERC-20 tokens. This extended interface makes it possible to query share balances, approve transfers, and move shares between accounts if needed. The depositor contract relies on this interface as the primary type for interacting with Morpho vaults.

---

## 4. Morpho Integration Details

### What Are MetaMorpho Vaults?

MetaMorpho vaults are ERC-4626 compliant yield-bearing vaults deployed on Ethereum mainnet. They are managed by curators who allocate deposited assets across multiple Morpho Blue lending markets to optimize yield. From a smart contract perspective, they behave like any ERC-4626 vault: you deposit an underlying asset and receive shares; the share price increases over time as yield accrues.

Available MetaMorpho vaults can be browsed at: [https://app.morpho.org/ethereum/earn](https://app.morpho.org/ethereum/earn)

### How Deposits Work

1. The caller approves the depositor contract to spend the underlying asset.
2. The depositor contract transfers the asset from the caller to itself.
3. The depositor contract approves the MetaMorpho vault to pull the asset:
   ```solidity
   IERC20(asset).forceApprove(address(vault), amount);
   ```
4. The depositor contract calls the ERC-4626 `deposit` function:
   ```solidity
   uint256 sharesReceived = IMorphoVault(vault).deposit(amount, address(this));
   ```
5. The vault mints shares to the depositor contract. The number of shares depends on the current exchange rate (share price).

### How Withdrawals Work

1. The caller specifies a number of shares to redeem.
2. The depositor contract calls the ERC-4626 `redeem` function:
   ```solidity
   uint256 assetsReceived = IMorphoVault(vault).redeem(shares, msg.sender, address(this));
   ```
3. The vault burns shares owned by the depositor contract and transfers the corresponding underlying assets directly to the caller.
4. If yield has accrued since deposit, the assets returned will be worth more than the assets originally deposited (the share price has increased).

### The Depositor Contract as Intermediary Custodian

The `MorphoVaultDepositor` contract holds all vault shares on behalf of its users. Individual user ownership is tracked via the `userShares` mapping rather than through the vault's own share token balances. This custodial model provides:

- **Platform-level control** over which vaults are accessible (whitelist).
- **Simplified accounting** for the Expendi platform to attribute yield per user.
- **A single point of integration** rather than requiring each user to interact with vaults directly.

---

## 5. Security Considerations

### Reentrancy Protection

Both contracts inherit `ReentrancyGuard` from OpenZeppelin. The `nonReentrant` modifier is applied to every state-changing function that makes external calls:

- **TimeLock:** `lockETH`, `lockERC20`, `withdraw`
- **MorphoVaultDepositor:** `depositToVault`, `withdrawFromVault`

This is particularly important for `TimeLock.withdraw`, which makes a low-level ETH `.call` that forwards all available gas to the recipient, creating a potential reentrancy vector.

### Checks-Effects-Interactions Pattern

Both contracts follow the checks-effects-interactions pattern:

- **TimeLock.withdraw** -- Sets `lock.withdrawn = true` before transferring ETH or tokens.
- **MorphoVaultDepositor.withdrawFromVault** -- Decrements `userShares[msg.sender][vault]` before calling `vault.redeem`.

This ordering ensures that even without the reentrancy guard, a reentrant call would see already-updated state and revert.

### SafeERC20 and forceApprove

Both contracts use OpenZeppelin's `SafeERC20` library:

- `safeTransfer` and `safeTransferFrom` handle tokens that do not return a boolean value (e.g., USDT on mainnet).
- `forceApprove` (used in `MorphoVaultDepositor.depositToVault`) sets the allowance to zero before setting the desired value. This is required for tokens like USDT that revert if `approve` is called with a non-zero current allowance.

### Owner Restrictions in TimeLock

The contract owner can **extend** lock durations via `extendLock` but is deliberately prevented from:

- **Shortening** lock periods -- `newUnlockTime` must be strictly greater than the current `unlockTime`.
- **Withdrawing** user funds -- only the original depositor can call `withdraw`.

This design ensures that administrative key compromise cannot lead to theft, only to extended lock durations.

### Vault Whitelist

The `MorphoVaultDepositor` restricts all deposit and withdrawal operations to owner-whitelisted vaults. This prevents users (or the platform) from interacting with arbitrary contracts that could exploit the approval and transfer flow. Removing a vault from the whitelist blocks further deposits and withdrawals but does not destroy existing share accounting -- the vault can be re-added later to restore access.

---

## 6. Dependency Map

### OpenZeppelin Contracts

Imported via `lib/openzeppelin-contracts/` and remapped as `@openzeppelin/`.

| Module | Used By | Purpose |
|---|---|---|
| `contracts/access/Ownable.sol` | TimeLock, MorphoVaultDepositor | Single-owner access control with ownership transfer. |
| `contracts/utils/ReentrancyGuard.sol` | TimeLock, MorphoVaultDepositor | `nonReentrant` modifier to prevent reentrancy attacks. |
| `contracts/token/ERC20/IERC20.sol` | TimeLock, MorphoVaultDepositor | Standard ERC-20 interface for token interactions. |
| `contracts/token/ERC20/utils/SafeERC20.sol` | TimeLock, MorphoVaultDepositor | Safe wrappers for ERC-20 calls (`safeTransfer`, `safeTransferFrom`, `forceApprove`). |

### forge-std

Imported via `lib/forge-std/` and remapped as `forge-std/`.

Used exclusively as the testing framework (Foundry's standard library). Provides `Test` base contract, cheatcodes (`vm`), assertions, and utilities for writing Solidity tests. Not imported by any production contract.

### Project Interfaces

| Interface | Source | Inherits | Purpose |
|---|---|---|---|
| `IERC4626` | `src/interfaces/IERC4626.sol` | -- | Standard ERC-4626 vault interface. |
| `IMorphoVault` | `src/interfaces/IMorphoVault.sol` | `IERC4626` | ERC-4626 + ERC-20 share token functions for MetaMorpho vaults. |

### Compiler Configuration

From `foundry.toml`:

```toml
solc_version = "0.8.20"

remappings = [
    "@openzeppelin/=lib/openzeppelin-contracts/",
    "forge-std/=lib/forge-std/src/"
]

[fuzz]
runs = 256
```
