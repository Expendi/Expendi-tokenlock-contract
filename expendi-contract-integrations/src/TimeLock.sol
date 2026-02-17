// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title TimeLock
 * @notice Allows users to lock ETH or ERC-20 tokens for a specified duration
 *         without generating any yield. Funds can only be withdrawn by the
 *         original depositor after the lock period expires.
 * @dev Each lock is identified by a unique, auto-incrementing lock ID.
 *      The contract owner can extend lock periods but can never shorten them
 *      or withdraw any user funds.
 */
contract TimeLock is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =========================================================================
    //                                Types
    // =========================================================================

    /**
     * @notice Represents a single time-locked deposit.
     * @param depositor The address that created the lock and is entitled to withdraw.
     * @param token     The ERC-20 token address, or `address(0)` for native ETH.
     * @param amount    The locked amount (in wei for ETH, or token base units).
     * @param unlockTime The Unix timestamp after which the lock can be withdrawn.
     * @param withdrawn Whether the funds have already been withdrawn.
     */
    struct Lock {
        address depositor;
        address token; // address(0) for ETH
        uint256 amount;
        uint256 unlockTime;
        bool withdrawn;
    }

    // =========================================================================
    //                              State
    // =========================================================================

    /// @notice Maps lock ID to its Lock struct.
    mapping(uint256 => Lock) public locks;

    /// @notice Maps a user address to an array of their lock IDs.
    mapping(address => uint256[]) public userLocks;

    /// @notice The next lock ID to be assigned. Starts at 0.
    uint256 public nextLockId;

    // =========================================================================
    //                              Events
    // =========================================================================

    /**
     * @notice Emitted when a new lock is created.
     * @param lockId     The unique identifier of the lock.
     * @param depositor  The address that created the lock.
     * @param token      The locked token address (`address(0)` for ETH).
     * @param amount     The amount locked.
     * @param unlockTime The Unix timestamp when the lock becomes withdrawable.
     */
    event LockCreated(
        uint256 indexed lockId, address indexed depositor, address indexed token, uint256 amount, uint256 unlockTime
    );

    /**
     * @notice Emitted when a lock is withdrawn.
     * @param lockId    The unique identifier of the lock.
     * @param depositor The address that withdrew the funds.
     * @param token     The withdrawn token address (`address(0)` for ETH).
     * @param amount    The amount withdrawn.
     */
    event Withdrawn(uint256 indexed lockId, address indexed depositor, address indexed token, uint256 amount);

    /**
     * @notice Emitted when the owner extends a lock's unlock time.
     * @param lockId        The unique identifier of the lock.
     * @param oldUnlockTime The previous unlock time.
     * @param newUnlockTime The new, extended unlock time.
     */
    event LockExtended(uint256 indexed lockId, uint256 oldUnlockTime, uint256 newUnlockTime);

    // =========================================================================
    //                              Errors
    // =========================================================================

    /// @notice Thrown when the specified unlock time is not in the future.
    error UnlockTimeNotInFuture();

    /// @notice Thrown when the deposited amount is zero.
    error AmountMustBeGreaterThanZero();

    /// @notice Thrown when the caller is not the original depositor.
    error NotDepositor();

    /// @notice Thrown when trying to withdraw a lock that hasn't expired yet.
    error LockNotExpired();

    /// @notice Thrown when trying to withdraw a lock that was already withdrawn.
    error AlreadyWithdrawn();

    /// @notice Thrown when the new unlock time is not strictly after the current one.
    error NewUnlockTimeMustBeAfterCurrent();

    /// @notice Thrown when the token address is the zero address (use lockETH instead).
    error InvalidTokenAddress();

    /// @notice Thrown when an ETH transfer fails.
    error ETHTransferFailed();

    // =========================================================================
    //                            Constructor
    // =========================================================================

    /**
     * @notice Deploys the TimeLock contract and sets the initial owner.
     * @param initialOwner The address that will be the contract owner.
     */
    constructor(address initialOwner) Ownable(initialOwner) {}

    // =========================================================================
    //                          External Functions
    // =========================================================================

    /**
     * @notice Locks the sent ETH until `unlockTime`.
     * @dev The caller must send ETH with this call (`msg.value > 0`).
     * @param unlockTime The Unix timestamp after which the ETH can be withdrawn.
     * @return lockId The unique identifier assigned to this lock.
     */
    function lockETH(uint256 unlockTime) external payable nonReentrant returns (uint256 lockId) {
        if (msg.value == 0) revert AmountMustBeGreaterThanZero();
        if (unlockTime <= block.timestamp) revert UnlockTimeNotInFuture();

        lockId = nextLockId++;

        locks[lockId] = Lock({
            depositor: msg.sender,
            token: address(0),
            amount: msg.value,
            unlockTime: unlockTime,
            withdrawn: false
        });

        userLocks[msg.sender].push(lockId);

        emit LockCreated(lockId, msg.sender, address(0), msg.value, unlockTime);
    }

    /**
     * @notice Locks `amount` of `token` until `unlockTime`.
     * @dev The caller must have approved this contract to spend at least `amount`
     *      of `token` before calling. Uses SafeERC20 for the transfer.
     * @param token The ERC-20 token to lock.
     * @param amount The amount of tokens to lock.
     * @param unlockTime The Unix timestamp after which the tokens can be withdrawn.
     * @return lockId The unique identifier assigned to this lock.
     */
    function lockERC20(address token, uint256 amount, uint256 unlockTime)
        external
        nonReentrant
        returns (uint256 lockId)
    {
        if (token == address(0)) revert InvalidTokenAddress();
        if (amount == 0) revert AmountMustBeGreaterThanZero();
        if (unlockTime <= block.timestamp) revert UnlockTimeNotInFuture();

        lockId = nextLockId++;

        locks[lockId] =
            Lock({depositor: msg.sender, token: token, amount: amount, unlockTime: unlockTime, withdrawn: false});

        userLocks[msg.sender].push(lockId);

        // Transfer tokens from the caller to this contract.
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        emit LockCreated(lockId, msg.sender, token, amount, unlockTime);
    }

    /**
     * @notice Withdraws the funds from a lock after the unlock time has passed.
     * @dev Only the original depositor can call this. The lock must not have
     *      been previously withdrawn.
     * @param lockId The unique identifier of the lock to withdraw.
     */
    function withdraw(uint256 lockId) external nonReentrant {
        Lock storage lock = locks[lockId];

        if (lock.depositor != msg.sender) revert NotDepositor();
        if (block.timestamp < lock.unlockTime) revert LockNotExpired();
        if (lock.withdrawn) revert AlreadyWithdrawn();

        lock.withdrawn = true;

        if (lock.token == address(0)) {
            // Transfer ETH back to the depositor.
            (bool success,) = payable(msg.sender).call{value: lock.amount}("");
            if (!success) revert ETHTransferFailed();
        } else {
            // Transfer ERC-20 tokens back to the depositor.
            IERC20(lock.token).safeTransfer(msg.sender, lock.amount);
        }

        emit Withdrawn(lockId, msg.sender, lock.token, lock.amount);
    }

    /**
     * @notice Extends the unlock time of a lock. Only the contract owner can
     *         call this. The new unlock time must be strictly later than the
     *         current unlock time (the owner can never shorten a lock).
     * @param lockId The unique identifier of the lock to extend.
     * @param newUnlockTime The new unlock time (must be > current unlockTime).
     */
    function extendLock(uint256 lockId, uint256 newUnlockTime) external onlyOwner {
        Lock storage lock = locks[lockId];

        if (newUnlockTime <= lock.unlockTime) revert NewUnlockTimeMustBeAfterCurrent();

        uint256 oldUnlockTime = lock.unlockTime;
        lock.unlockTime = newUnlockTime;

        emit LockExtended(lockId, oldUnlockTime, newUnlockTime);
    }

    // =========================================================================
    //                           View Functions
    // =========================================================================

    /**
     * @notice Returns the full Lock struct for a given lock ID.
     * @param lockId The unique identifier of the lock.
     * @return lock The Lock struct containing all lock details.
     */
    function getLock(uint256 lockId) external view returns (Lock memory lock) {
        lock = locks[lockId];
    }

    /**
     * @notice Returns all lock IDs belonging to `user`.
     * @param user The address to query.
     * @return lockIds An array of lock IDs created by `user`.
     */
    function getUserLockIds(address user) external view returns (uint256[] memory lockIds) {
        lockIds = userLocks[user];
    }

    /**
     * @notice Checks whether a lock's unlock time has passed.
     * @param lockId The unique identifier of the lock.
     * @return unlocked True if `block.timestamp >= lock.unlockTime`.
     */
    function isUnlocked(uint256 lockId) external view returns (bool unlocked) {
        unlocked = block.timestamp >= locks[lockId].unlockTime;
    }
}
