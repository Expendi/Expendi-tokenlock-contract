// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IMorphoVault} from "./interfaces/IMorphoVault.sol";

/**
 * @title YieldTimeLock
 * @notice Combines time-locked deposits with Morpho vault yield generation.
 *         Users lock ERC-20 tokens for a duration; assets are deposited into
 *         whitelisted ERC-4626 vaults to earn yield during the lock period.
 * @dev Only supports ERC-20 tokens (no native ETH). Users must wrap ETH to WETH
 *      before depositing. Emergency withdrawal is owner-initiated only.
 */
contract YieldTimeLock is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =========================================================================
    //                                Types
    // =========================================================================

    /**
     * @notice Represents a yield-generating time-locked deposit.
     * @param depositor The address that created the lock and can withdraw.
     * @param vault The ERC-4626 vault holding the assets.
     * @param underlyingToken The underlying asset token (cached for gas).
     * @param shares The vault shares received at deposit.
     * @param principalAssets The original deposit amount (for yield calculation).
     * @param unlockTime The Unix timestamp after which withdrawal is allowed.
     * @param withdrawn Whether the lock has been withdrawn normally.
     * @param isEmergencyWithdrawn Whether the lock was emergency-withdrawn by owner.
     * @param label User-defined label to categorize the lock (e.g., "rent", "savings").
     */
    struct YieldLock {
        address depositor;
        address vault;
        address underlyingToken;
        uint256 shares;
        uint256 principalAssets;
        uint256 unlockTime;
        bool withdrawn;
        bool isEmergencyWithdrawn;
        string label;
    }

    // =========================================================================
    //                              State
    // =========================================================================

    /// @notice Basis points denominator (100% = 10_000 bps).
    uint256 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Maximum fee in basis points (10%).
    uint256 public constant MAX_FEE_BPS = 1_000;

    /// @notice Default fee: 0.5% = 50 bps.
    uint256 public constant DEFAULT_FEE_BPS = 50;

    /// @notice Maps lock ID to its YieldLock struct.
    mapping(uint256 => YieldLock) public yieldLocks;

    /// @notice Maps a user address to an array of their lock IDs.
    mapping(address => uint256[]) public userYieldLocks;

    /// @notice Stores raw tokens after emergency redemption (lockId => amount).
    mapping(uint256 => uint256) public emergencyAssets;

    /// @notice Whether a vault address is whitelisted for deposits.
    mapping(address => bool) public whitelistedVaults;

    /// @notice Array of all vaults that have ever been whitelisted.
    address[] public vaultList;

    /// @notice Withdrawal fee in basis points.
    uint256 public feeBps;

    /// @notice Address that receives the withdrawal fees.
    address public feeRecipient;

    /// @notice The next lock ID to be assigned.
    uint256 public nextLockId;

    // =========================================================================
    //                              Events
    // =========================================================================

    /**
     * @notice Emitted when a new yield lock is created.
     * @param lockId The unique identifier of the lock.
     * @param depositor The address that created the lock.
     * @param vault The ERC-4626 vault used.
     * @param underlyingToken The underlying asset token.
     * @param principalAssets The amount of assets deposited.
     * @param shares The vault shares received.
     * @param unlockTime The Unix timestamp when withdrawal becomes available.
     * @param label The user-defined label for categorization.
     */
    event YieldLockCreated(
        uint256 indexed lockId,
        address indexed depositor,
        address indexed vault,
        address underlyingToken,
        uint256 principalAssets,
        uint256 shares,
        uint256 unlockTime,
        string label
    );

    /**
     * @notice Emitted when a yield lock is withdrawn.
     * @param lockId The lock ID.
     * @param depositor The address that withdrew.
     * @param vault The vault from which shares were redeemed.
     * @param shares The shares redeemed.
     * @param totalAssets The total assets received before fee.
     * @param fee The fee deducted.
     * @param netAssets The assets sent to the depositor.
     */
    event YieldLockWithdrawn(
        uint256 indexed lockId,
        address indexed depositor,
        address indexed vault,
        uint256 shares,
        uint256 totalAssets,
        uint256 fee,
        uint256 netAssets
    );

    /**
     * @notice Emitted when the owner extends a lock's unlock time.
     * @param lockId The lock ID.
     * @param oldUnlockTime The previous unlock time.
     * @param newUnlockTime The new, extended unlock time.
     */
    event LockExtended(uint256 indexed lockId, uint256 oldUnlockTime, uint256 newUnlockTime);

    /**
     * @notice Emitted when the owner triggers an emergency withdrawal.
     * @param lockId The lock ID.
     * @param vault The vault from which shares were redeemed.
     * @param shares The shares redeemed.
     * @param assets The raw tokens now held by the contract.
     */
    event EmergencyWithdrawal(uint256 indexed lockId, address indexed vault, uint256 shares, uint256 assets);

    /**
     * @notice Emitted when a depositor claims funds after emergency withdrawal.
     * @param lockId The lock ID.
     * @param depositor The address that claimed.
     * @param totalAssets The total assets available.
     * @param fee The fee deducted.
     * @param netAssets The assets sent to the depositor.
     */
    event EmergencyFundsClaimed(
        uint256 indexed lockId, address indexed depositor, uint256 totalAssets, uint256 fee, uint256 netAssets
    );

    /**
     * @notice Emitted when a vault is added to the whitelist.
     * @param vault The vault address.
     */
    event VaultAdded(address indexed vault);

    /**
     * @notice Emitted when a vault is removed from the whitelist.
     * @param vault The vault address.
     */
    event VaultRemoved(address indexed vault);

    /**
     * @notice Emitted when the withdrawal fee is updated.
     * @param oldFeeBps The previous fee.
     * @param newFeeBps The new fee.
     */
    event FeeUpdated(uint256 oldFeeBps, uint256 newFeeBps);

    /**
     * @notice Emitted when the fee recipient is updated.
     * @param oldRecipient The previous recipient.
     * @param newRecipient The new recipient.
     */
    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);

    /**
     * @notice Emitted when fees are collected.
     * @param lockId The lock ID.
     * @param token The token in which fees were collected.
     * @param amount The fee amount.
     */
    event FeeCollected(uint256 indexed lockId, address indexed token, uint256 amount);

    // =========================================================================
    //                              Errors
    // =========================================================================

    /// @notice Thrown when the specified unlock time is not in the future.
    error UnlockTimeNotInFuture();

    /// @notice Thrown when the deposit amount is zero.
    error AmountMustBeGreaterThanZero();

    /// @notice Thrown when the caller is not the original depositor.
    error NotDepositor();

    /// @notice Thrown when trying to withdraw a lock that hasn't expired yet.
    error LockNotExpired();

    /// @notice Thrown when trying to withdraw a lock that was already withdrawn.
    error AlreadyWithdrawn();

    /// @notice Thrown when trying to perform normal withdrawal on emergency-withdrawn lock.
    error LockIsEmergencyWithdrawn();

    /// @notice Thrown when the lock is not emergency-withdrawn.
    error NotEmergencyWithdrawn();

    /// @notice Thrown when the new unlock time is not strictly after the current one.
    error NewUnlockTimeMustBeAfterCurrent();

    /// @notice Thrown when attempting to interact with a non-whitelisted vault.
    error VaultNotWhitelisted();

    /// @notice Thrown when trying to add a vault that is already whitelisted.
    error VaultAlreadyWhitelisted();

    /// @notice Thrown when trying to remove a vault that is not whitelisted.
    error VaultNotInWhitelist();

    /// @notice Thrown when a zero address is provided where a valid address is required.
    error ZeroAddress();

    /// @notice Thrown when the fee exceeds the maximum allowed.
    error FeeTooHigh();

    /// @notice Thrown when trying to emergency withdraw a lock that's already processed.
    error LockAlreadyProcessed();

    /// @notice Thrown when trying to interact with a lock that does not exist.
    error LockDoesNotExist();

    // =========================================================================
    //                            Constructor
    // =========================================================================

    /**
     * @notice Deploys the YieldTimeLock contract.
     * @param initialOwner The address that will be the contract owner.
     * @param _feeRecipient The address that will receive withdrawal fees.
     */
    constructor(address initialOwner, address _feeRecipient) Ownable(initialOwner) {
        if (_feeRecipient == address(0)) revert ZeroAddress();
        feeRecipient = _feeRecipient;
        feeBps = DEFAULT_FEE_BPS;
    }

    // =========================================================================
    //                          External Functions
    // =========================================================================

    /**
     * @notice Locks tokens into a yield-generating ERC-4626 vault until `unlockTime`.
     * @dev The caller must have approved this contract to spend at least `amount`
     *      of the vault's underlying asset. The vault must be whitelisted.
     * @param vault The address of the whitelisted ERC-4626 vault.
     * @param amount The amount of the underlying asset to lock.
     * @param unlockTime The Unix timestamp after which withdrawal is allowed.
     * @param label A user-defined label to categorize this lock (e.g., "rent", "savings").
     * @return lockId The unique identifier assigned to this lock.
     */
    function lockWithYield(address vault, uint256 amount, uint256 unlockTime, string calldata label)
        external
        nonReentrant
        returns (uint256 lockId)
    {
        if (!whitelistedVaults[vault]) revert VaultNotWhitelisted();
        if (amount == 0) revert AmountMustBeGreaterThanZero();
        if (unlockTime <= block.timestamp) revert UnlockTimeNotInFuture();

        address underlyingToken = IMorphoVault(vault).asset();

        IERC20(underlyingToken).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(underlyingToken).forceApprove(vault, amount);

        uint256 sharesReceived = IMorphoVault(vault).deposit(amount, address(this));

        lockId = nextLockId++;

        yieldLocks[lockId] = YieldLock({
            depositor: msg.sender,
            vault: vault,
            underlyingToken: underlyingToken,
            shares: sharesReceived,
            principalAssets: amount,
            unlockTime: unlockTime,
            withdrawn: false,
            isEmergencyWithdrawn: false,
            label: label
        });

        userYieldLocks[msg.sender].push(lockId);

        emit YieldLockCreated(lockId, msg.sender, vault, underlyingToken, amount, sharesReceived, unlockTime, label);
    }

    /**
     * @notice Withdraws a yield lock after the unlock time has passed.
     * @dev Only the original depositor can call this. Redeems vault shares,
     *      takes a fee from the total assets, and sends the remainder to the depositor.
     *      Withdrawal ignores vault whitelist status (only deposit checks it).
     * @param lockId The unique identifier of the lock to withdraw.
     */
    function withdraw(uint256 lockId) external nonReentrant {
        YieldLock storage lock = yieldLocks[lockId];

        if (lock.depositor != msg.sender) revert NotDepositor();
        if (block.timestamp < lock.unlockTime) revert LockNotExpired();
        if (lock.withdrawn) revert AlreadyWithdrawn();
        if (lock.isEmergencyWithdrawn) revert LockIsEmergencyWithdrawn();

        lock.withdrawn = true;

        uint256 assetsReceived = IMorphoVault(lock.vault).redeem(lock.shares, address(this), address(this));

        uint256 fee = (assetsReceived * feeBps) / BPS_DENOMINATOR;
        uint256 netAssets = assetsReceived - fee;

        if (fee > 0) {
            IERC20(lock.underlyingToken).safeTransfer(feeRecipient, fee);
            emit FeeCollected(lockId, lock.underlyingToken, fee);
        }
        IERC20(lock.underlyingToken).safeTransfer(msg.sender, netAssets);

        emit YieldLockWithdrawn(lockId, msg.sender, lock.vault, lock.shares, assetsReceived, fee, netAssets);
    }

    /**
     * @notice Extends the unlock time of a lock. Only the contract owner can call this.
     * @dev The new unlock time must be strictly later than the current unlock time.
     *      The owner can never shorten a lock.
     * @param lockId The unique identifier of the lock to extend.
     * @param newUnlockTime The new unlock time (must be > current unlockTime).
     */
    function extendLock(uint256 lockId, uint256 newUnlockTime) external onlyOwner {
        YieldLock storage lock = yieldLocks[lockId];

        if (lock.depositor == address(0)) revert LockDoesNotExist();
        if (lock.withdrawn || lock.isEmergencyWithdrawn) revert LockAlreadyProcessed();
        if (newUnlockTime <= lock.unlockTime) revert NewUnlockTimeMustBeAfterCurrent();

        uint256 oldUnlockTime = lock.unlockTime;
        lock.unlockTime = newUnlockTime;

        emit LockExtended(lockId, oldUnlockTime, newUnlockTime);
    }

    /**
     * @notice Emergency withdrawal: redeems shares to the contract if vault has issues.
     * @dev Only the owner can call this. Use when a vault has liquidity problems.
     *      The depositor can later claim the raw tokens via `claimEmergencyFunds`.
     * @param lockId The unique identifier of the lock.
     */
    function emergencyWithdraw(uint256 lockId) external onlyOwner nonReentrant {
        YieldLock storage lock = yieldLocks[lockId];

        if (lock.withdrawn || lock.isEmergencyWithdrawn) revert LockAlreadyProcessed();

        lock.isEmergencyWithdrawn = true;

        uint256 assetsReceived = IMorphoVault(lock.vault).redeem(lock.shares, address(this), address(this));

        emergencyAssets[lockId] = assetsReceived;

        emit EmergencyWithdrawal(lockId, lock.vault, lock.shares, assetsReceived);
    }

    /**
     * @notice Batch emergency withdrawal: redeems shares for multiple locks.
     * @dev Only the owner can call this. Use when a vault has liquidity problems
     *      and multiple locks need to be rescued quickly.
     * @param lockIds The array of lock IDs to emergency withdraw.
     */
    function emergencyWithdrawBatch(uint256[] calldata lockIds) external onlyOwner nonReentrant {
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

    /**
     * @notice Claims funds after an emergency withdrawal, once the lock has expired.
     * @dev Only the original depositor can call this. A fee is taken from the assets.
     * @param lockId The unique identifier of the lock.
     */
    function claimEmergencyFunds(uint256 lockId) external nonReentrant {
        YieldLock storage lock = yieldLocks[lockId];

        if (lock.depositor != msg.sender) revert NotDepositor();
        if (!lock.isEmergencyWithdrawn) revert NotEmergencyWithdrawn();
        if (lock.withdrawn) revert AlreadyWithdrawn();
        if (block.timestamp < lock.unlockTime) revert LockNotExpired();

        lock.withdrawn = true;

        uint256 totalAssets = emergencyAssets[lockId];
        delete emergencyAssets[lockId];

        uint256 fee = (totalAssets * feeBps) / BPS_DENOMINATOR;
        uint256 netAssets = totalAssets - fee;

        if (fee > 0) {
            IERC20(lock.underlyingToken).safeTransfer(feeRecipient, fee);
            emit FeeCollected(lockId, lock.underlyingToken, fee);
        }
        IERC20(lock.underlyingToken).safeTransfer(msg.sender, netAssets);

        emit EmergencyFundsClaimed(lockId, msg.sender, totalAssets, fee, netAssets);
    }

    // =========================================================================
    //                     Owner-Only Vault Management
    // =========================================================================

    /**
     * @notice Adds a vault to the whitelist. Only the owner can call this.
     * @param vault The address of the ERC-4626 vault to whitelist.
     */
    function addVault(address vault) external onlyOwner {
        if (vault == address(0)) revert ZeroAddress();
        if (whitelistedVaults[vault]) revert VaultAlreadyWhitelisted();

        whitelistedVaults[vault] = true;
        vaultList.push(vault);

        emit VaultAdded(vault);
    }

    /**
     * @notice Removes a vault from the whitelist. Only the owner can call this.
     * @dev This does not affect existing locks. Users can still withdraw from
     *      delisted vaults (only deposits require whitelist).
     * @param vault The address of the vault to remove.
     */
    function removeVault(address vault) external onlyOwner {
        if (!whitelistedVaults[vault]) revert VaultNotInWhitelist();

        whitelistedVaults[vault] = false;

        uint256 length = vaultList.length;
        for (uint256 i = 0; i < length; i++) {
            if (vaultList[i] == vault) {
                vaultList[i] = vaultList[length - 1];
                vaultList.pop();
                break;
            }
        }

        emit VaultRemoved(vault);
    }

    // =========================================================================
    //                     Owner-Only Fee Management
    // =========================================================================

    /**
     * @notice Updates the withdrawal fee. Only the owner can call this.
     * @param newFeeBps The new fee in basis points (max 1000 = 10%).
     */
    function setFeeBps(uint256 newFeeBps) external onlyOwner {
        if (newFeeBps > MAX_FEE_BPS) revert FeeTooHigh();

        uint256 oldFeeBps = feeBps;
        feeBps = newFeeBps;

        emit FeeUpdated(oldFeeBps, newFeeBps);
    }

    /**
     * @notice Updates the fee recipient address. Only the owner can call this.
     * @param newFeeRecipient The new address to receive fees.
     */
    function setFeeRecipient(address newFeeRecipient) external onlyOwner {
        if (newFeeRecipient == address(0)) revert ZeroAddress();

        address oldRecipient = feeRecipient;
        feeRecipient = newFeeRecipient;

        emit FeeRecipientUpdated(oldRecipient, newFeeRecipient);
    }

    // =========================================================================
    //                           View Functions
    // =========================================================================

    /**
     * @notice Returns the full YieldLock struct for a given lock ID.
     * @param lockId The unique identifier of the lock.
     * @return lock The YieldLock struct.
     */
    function getYieldLock(uint256 lockId) external view returns (YieldLock memory lock) {
        lock = yieldLocks[lockId];
    }

    /**
     * @notice Returns all lock IDs belonging to a user.
     * @param user The address to query.
     * @return lockIds An array of lock IDs created by the user.
     */
    function getUserYieldLockIds(address user) external view returns (uint256[] memory lockIds) {
        lockIds = userYieldLocks[user];
    }

    /**
     * @notice Checks whether a lock's unlock time has passed.
     * @param lockId The unique identifier of the lock.
     * @return unlocked True if `block.timestamp >= lock.unlockTime`.
     */
    function isUnlocked(uint256 lockId) external view returns (bool unlocked) {
        YieldLock storage lock = yieldLocks[lockId];
        if (lock.depositor == address(0)) revert LockDoesNotExist();
        unlocked = block.timestamp >= lock.unlockTime;
    }

    /**
     * @notice Checks whether a vault is currently whitelisted.
     * @param vault The vault address to check.
     * @return whitelisted True if the vault is whitelisted.
     */
    function isVaultWhitelisted(address vault) external view returns (bool whitelisted) {
        whitelisted = whitelistedVaults[vault];
    }

    /**
     * @notice Returns the full list of currently whitelisted vaults.
     * @return vaults An array of whitelisted vault addresses.
     */
    function getVaultList() external view returns (address[] memory vaults) {
        vaults = vaultList;
    }

    /**
     * @notice Previews the withdrawal amount for a lock (assets after fee).
     * @dev For emergency-withdrawn locks, uses the cached emergencyAssets.
     *      For normal locks, queries the vault for current share value.
     * @param lockId The lock ID to preview.
     * @return totalAssets The total assets available (before fee).
     * @return fee The fee that would be deducted.
     * @return netAssets The assets the depositor would receive.
     */
    function previewWithdraw(uint256 lockId)
        external
        view
        returns (uint256 totalAssets, uint256 fee, uint256 netAssets)
    {
        YieldLock storage lock = yieldLocks[lockId];

        if (lock.withdrawn) {
            return (0, 0, 0);
        }

        if (lock.isEmergencyWithdrawn) {
            totalAssets = emergencyAssets[lockId];
        } else {
            totalAssets = IMorphoVault(lock.vault).previewRedeem(lock.shares);
        }

        fee = (totalAssets * feeBps) / BPS_DENOMINATOR;
        netAssets = totalAssets - fee;
    }

    /**
     * @notice Returns the accrued yield for a lock.
     * @dev Calculates current asset value minus principal. Can be negative
     *      if the vault has lost value (returned as 0 in that case).
     * @param lockId The lock ID to query.
     * @return yield The yield accrued (0 if negative).
     * @return currentAssets The current total asset value.
     */
    function getAccruedYield(uint256 lockId) external view returns (uint256 yield, uint256 currentAssets) {
        YieldLock storage lock = yieldLocks[lockId];

        if (lock.withdrawn) {
            return (0, 0);
        }

        if (lock.isEmergencyWithdrawn) {
            currentAssets = emergencyAssets[lockId];
        } else {
            currentAssets = IMorphoVault(lock.vault).previewRedeem(lock.shares);
        }

        if (currentAssets > lock.principalAssets) {
            yield = currentAssets - lock.principalAssets;
        }
    }

    /**
     * @notice Returns all lock IDs belonging to a user with a specific label.
     * @dev Warning: May run out of gas for users with many locks. Use the
     *      paginated version (with offset/limit) for production integrations.
     * @param user The address to query.
     * @param label The label to filter by.
     * @return lockIds An array of lock IDs matching the label.
     */
    function getUserLocksByLabel(address user, string calldata label)
        external
        view
        returns (uint256[] memory lockIds)
    {
        uint256[] storage allLockIds = userYieldLocks[user];
        uint256 length = allLockIds.length;
        uint256 count;

        for (uint256 i = 0; i < length; i++) {
            if (_stringsEqual(yieldLocks[allLockIds[i]].label, label)) {
                count++;
            }
        }

        lockIds = new uint256[](count);
        uint256 idx;

        for (uint256 i = 0; i < length; i++) {
            if (_stringsEqual(yieldLocks[allLockIds[i]].label, label)) {
                lockIds[idx++] = allLockIds[i];
            }
        }
    }

    /**
     * @notice Returns lock IDs belonging to a user with a specific label (paginated).
     * @dev Use this function for users with many locks to avoid gas limit issues.
     * @param user The address to query.
     * @param label The label to filter by.
     * @param offset The starting index in the user's lock array.
     * @param limit The maximum number of matching locks to return.
     * @return lockIds An array of lock IDs matching the label.
     * @return hasMore True if there are more locks beyond this page.
     */
    function getUserLocksByLabelPaginated(address user, string calldata label, uint256 offset, uint256 limit)
        external
        view
        returns (uint256[] memory lockIds, bool hasMore)
    {
        uint256[] storage allLockIds = userYieldLocks[user];
        uint256 length = allLockIds.length;

        if (offset >= length) {
            return (new uint256[](0), false);
        }

        uint256[] memory tempMatches = new uint256[](limit);
        uint256 matchCount;
        uint256 i = offset;

        while (i < length && matchCount < limit) {
            if (_stringsEqual(yieldLocks[allLockIds[i]].label, label)) {
                tempMatches[matchCount++] = allLockIds[i];
            }
            i++;
        }

        hasMore = i < length;

        lockIds = new uint256[](matchCount);
        for (uint256 j = 0; j < matchCount; j++) {
            lockIds[j] = tempMatches[j];
        }
    }

    /**
     * @notice Compares two strings for equality.
     * @param a First string.
     * @param b Second string.
     * @return True if strings are equal.
     */
    function _stringsEqual(string memory a, string calldata b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
