// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {TimeLock} from "../src/TimeLock.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract TimeLockTest is Test {
    // Re-declare events from TimeLock so we can use them with vm.expectEmit
    event LockCreated(
        uint256 indexed lockId, address indexed depositor, address indexed token, uint256 amount, uint256 unlockTime
    );
    event Withdrawn(uint256 indexed lockId, address indexed depositor, address indexed token, uint256 amount);
    event LockExtended(uint256 indexed lockId, uint256 oldUnlockTime, uint256 newUnlockTime);

    TimeLock public timeLock;
    MockERC20 public token;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 public constant LOCK_AMOUNT = 1 ether;
    uint256 public constant TOKEN_AMOUNT = 1000e18;
    uint256 public constant INITIAL_BALANCE = 100 ether;
    uint256 public constant INITIAL_TOKEN_BALANCE = 1_000_000e18;

    // Convenience: unlock time 1 day from now
    uint256 public unlockTime;

    function setUp() public {
        // Deploy contracts
        timeLock = new TimeLock(owner);
        token = new MockERC20("Mock Token", "MTK");

        // Fund test accounts with ETH
        vm.deal(alice, INITIAL_BALANCE);
        vm.deal(bob, INITIAL_BALANCE);

        // Mint tokens and approve
        token.mint(alice, INITIAL_TOKEN_BALANCE);
        token.mint(bob, INITIAL_TOKEN_BALANCE);

        vm.prank(alice);
        token.approve(address(timeLock), type(uint256).max);

        vm.prank(bob);
        token.approve(address(timeLock), type(uint256).max);

        // Set a default unlock time (1 day from now)
        unlockTime = block.timestamp + 1 days;
    }

    // =========================================================================
    //                       ETH Locking Tests
    // =========================================================================

    function test_lockETH_Success() public {
        vm.prank(alice);
        uint256 lockId = timeLock.lockETH{value: LOCK_AMOUNT}(unlockTime);

        assertEq(lockId, 0, "First lock ID should be 0");

        TimeLock.Lock memory lock = timeLock.getLock(lockId);
        assertEq(lock.depositor, alice, "Depositor should be alice");
        assertEq(lock.token, address(0), "Token should be address(0) for ETH");
        assertEq(lock.amount, LOCK_AMOUNT, "Amount should match");
        assertEq(lock.unlockTime, unlockTime, "Unlock time should match");
        assertFalse(lock.withdrawn, "Should not be withdrawn");

        // Verify contract balance
        assertEq(address(timeLock).balance, LOCK_AMOUNT, "Contract should hold the ETH");
    }

    function test_lockETH_RevertZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(TimeLock.AmountMustBeGreaterThanZero.selector);
        timeLock.lockETH{value: 0}(unlockTime);
    }

    function test_lockETH_RevertPastUnlockTime() public {
        uint256 pastTime = block.timestamp - 1;

        vm.prank(alice);
        vm.expectRevert(TimeLock.UnlockTimeNotInFuture.selector);
        timeLock.lockETH{value: LOCK_AMOUNT}(pastTime);
    }

    function test_lockETH_RevertCurrentTimestamp() public {
        uint256 currentTime = block.timestamp;

        vm.prank(alice);
        vm.expectRevert(TimeLock.UnlockTimeNotInFuture.selector);
        timeLock.lockETH{value: LOCK_AMOUNT}(currentTime);
    }

    function test_lockETH_MultipleLocks() public {
        uint256 unlockTime2 = block.timestamp + 2 days;
        uint256 unlockTime3 = block.timestamp + 3 days;

        vm.startPrank(alice);
        uint256 lockId1 = timeLock.lockETH{value: 1 ether}(unlockTime);
        uint256 lockId2 = timeLock.lockETH{value: 2 ether}(unlockTime2);
        uint256 lockId3 = timeLock.lockETH{value: 3 ether}(unlockTime3);
        vm.stopPrank();

        assertEq(lockId1, 0, "First lock ID should be 0");
        assertEq(lockId2, 1, "Second lock ID should be 1");
        assertEq(lockId3, 2, "Third lock ID should be 2");

        // Verify user lock IDs array
        uint256[] memory aliceLocks = timeLock.getUserLockIds(alice);
        assertEq(aliceLocks.length, 3, "Alice should have 3 locks");
        assertEq(aliceLocks[0], 0);
        assertEq(aliceLocks[1], 1);
        assertEq(aliceLocks[2], 2);

        // Verify each lock has correct details
        assertEq(timeLock.getLock(lockId1).amount, 1 ether);
        assertEq(timeLock.getLock(lockId2).amount, 2 ether);
        assertEq(timeLock.getLock(lockId3).amount, 3 ether);

        // Verify total ETH in contract
        assertEq(address(timeLock).balance, 6 ether, "Contract should hold all locked ETH");
    }

    function test_lockETH_EmitsEvent() public {
        vm.prank(alice);

        vm.expectEmit(true, true, true, true);
        emit LockCreated(0, alice, address(0), LOCK_AMOUNT, unlockTime);

        timeLock.lockETH{value: LOCK_AMOUNT}(unlockTime);
    }

    // =========================================================================
    //                       ERC20 Locking Tests
    // =========================================================================

    function test_lockERC20_Success() public {
        vm.prank(alice);
        uint256 lockId = timeLock.lockERC20(address(token), TOKEN_AMOUNT, unlockTime);

        assertEq(lockId, 0, "First lock ID should be 0");

        TimeLock.Lock memory lock = timeLock.getLock(lockId);
        assertEq(lock.depositor, alice, "Depositor should be alice");
        assertEq(lock.token, address(token), "Token address should match");
        assertEq(lock.amount, TOKEN_AMOUNT, "Amount should match");
        assertEq(lock.unlockTime, unlockTime, "Unlock time should match");
        assertFalse(lock.withdrawn, "Should not be withdrawn");
    }

    function test_lockERC20_RevertZeroAddress() public {
        vm.prank(alice);
        vm.expectRevert(TimeLock.InvalidTokenAddress.selector);
        timeLock.lockERC20(address(0), TOKEN_AMOUNT, unlockTime);
    }

    function test_lockERC20_RevertZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(TimeLock.AmountMustBeGreaterThanZero.selector);
        timeLock.lockERC20(address(token), 0, unlockTime);
    }

    function test_lockERC20_RevertPastUnlockTime() public {
        uint256 pastTime = block.timestamp - 1;

        vm.prank(alice);
        vm.expectRevert(TimeLock.UnlockTimeNotInFuture.selector);
        timeLock.lockERC20(address(token), TOKEN_AMOUNT, pastTime);
    }

    function test_lockERC20_TransfersTokens() public {
        uint256 aliceBalanceBefore = token.balanceOf(alice);
        uint256 contractBalanceBefore = token.balanceOf(address(timeLock));

        vm.prank(alice);
        timeLock.lockERC20(address(token), TOKEN_AMOUNT, unlockTime);

        uint256 aliceBalanceAfter = token.balanceOf(alice);
        uint256 contractBalanceAfter = token.balanceOf(address(timeLock));

        assertEq(aliceBalanceAfter, aliceBalanceBefore - TOKEN_AMOUNT, "Alice balance should decrease");
        assertEq(contractBalanceAfter, contractBalanceBefore + TOKEN_AMOUNT, "Contract balance should increase");
    }

    // =========================================================================
    //                       Withdrawal Tests
    // =========================================================================

    function test_withdrawETH_Success() public {
        // Create a lock
        vm.prank(alice);
        uint256 lockId = timeLock.lockETH{value: LOCK_AMOUNT}(unlockTime);

        // Warp to after unlock time
        vm.warp(unlockTime + 1);

        uint256 aliceBalanceBefore = alice.balance;

        vm.prank(alice);
        timeLock.withdraw(lockId);

        // Verify ETH returned
        assertEq(alice.balance, aliceBalanceBefore + LOCK_AMOUNT, "Alice should receive locked ETH");

        // Verify lock marked as withdrawn
        TimeLock.Lock memory lock = timeLock.getLock(lockId);
        assertTrue(lock.withdrawn, "Lock should be marked withdrawn");

        // Verify contract balance decreased
        assertEq(address(timeLock).balance, 0, "Contract should have no remaining ETH");
    }

    function test_withdrawERC20_Success() public {
        // Create a lock
        vm.prank(alice);
        uint256 lockId = timeLock.lockERC20(address(token), TOKEN_AMOUNT, unlockTime);

        // Warp to after unlock time
        vm.warp(unlockTime + 1);

        uint256 aliceBalanceBefore = token.balanceOf(alice);

        vm.prank(alice);
        timeLock.withdraw(lockId);

        // Verify tokens returned
        assertEq(token.balanceOf(alice), aliceBalanceBefore + TOKEN_AMOUNT, "Alice should receive locked tokens");

        // Verify lock marked as withdrawn
        TimeLock.Lock memory lock = timeLock.getLock(lockId);
        assertTrue(lock.withdrawn, "Lock should be marked withdrawn");

        // Verify contract token balance decreased
        assertEq(token.balanceOf(address(timeLock)), 0, "Contract should have no remaining tokens");
    }

    function test_withdraw_RevertNotDepositor() public {
        // Alice creates a lock
        vm.prank(alice);
        uint256 lockId = timeLock.lockETH{value: LOCK_AMOUNT}(unlockTime);

        // Warp past unlock time
        vm.warp(unlockTime + 1);

        // Bob tries to withdraw Alice's lock
        vm.prank(bob);
        vm.expectRevert(TimeLock.NotDepositor.selector);
        timeLock.withdraw(lockId);
    }

    function test_withdraw_RevertLockNotExpired() public {
        vm.prank(alice);
        uint256 lockId = timeLock.lockETH{value: LOCK_AMOUNT}(unlockTime);

        // Try to withdraw before unlock time (don't warp)
        vm.prank(alice);
        vm.expectRevert(TimeLock.LockNotExpired.selector);
        timeLock.withdraw(lockId);
    }

    function test_withdraw_RevertAlreadyWithdrawn() public {
        vm.prank(alice);
        uint256 lockId = timeLock.lockETH{value: LOCK_AMOUNT}(unlockTime);

        // Warp past unlock time and withdraw once
        vm.warp(unlockTime + 1);

        vm.prank(alice);
        timeLock.withdraw(lockId);

        // Try to withdraw again
        vm.prank(alice);
        vm.expectRevert(TimeLock.AlreadyWithdrawn.selector);
        timeLock.withdraw(lockId);
    }

    function test_withdraw_EmitsEvent() public {
        vm.prank(alice);
        uint256 lockId = timeLock.lockETH{value: LOCK_AMOUNT}(unlockTime);

        vm.warp(unlockTime + 1);

        vm.prank(alice);

        vm.expectEmit(true, true, true, true);
        emit Withdrawn(lockId, alice, address(0), LOCK_AMOUNT);

        timeLock.withdraw(lockId);
    }

    // =========================================================================
    //                       ExtendLock Tests
    // =========================================================================

    function test_extendLock_Success() public {
        // Alice creates a lock
        vm.prank(alice);
        uint256 lockId = timeLock.lockETH{value: LOCK_AMOUNT}(unlockTime);

        uint256 newUnlockTime = unlockTime + 7 days;

        // Owner extends the lock
        vm.prank(owner);
        timeLock.extendLock(lockId, newUnlockTime);

        // Verify updated unlock time
        TimeLock.Lock memory lock = timeLock.getLock(lockId);
        assertEq(lock.unlockTime, newUnlockTime, "Unlock time should be updated");
    }

    function test_extendLock_RevertNotOwner() public {
        vm.prank(alice);
        uint256 lockId = timeLock.lockETH{value: LOCK_AMOUNT}(unlockTime);

        uint256 newUnlockTime = unlockTime + 7 days;

        // Alice (non-owner) tries to extend
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        timeLock.extendLock(lockId, newUnlockTime);
    }

    function test_extendLock_RevertShortenLock() public {
        vm.prank(alice);
        uint256 lockId = timeLock.lockETH{value: LOCK_AMOUNT}(unlockTime);

        uint256 shorterTime = unlockTime - 1;

        vm.prank(owner);
        vm.expectRevert(TimeLock.NewUnlockTimeMustBeAfterCurrent.selector);
        timeLock.extendLock(lockId, shorterTime);
    }

    function test_extendLock_RevertSameTime() public {
        vm.prank(alice);
        uint256 lockId = timeLock.lockETH{value: LOCK_AMOUNT}(unlockTime);

        // Try to "extend" with the same unlock time
        vm.prank(owner);
        vm.expectRevert(TimeLock.NewUnlockTimeMustBeAfterCurrent.selector);
        timeLock.extendLock(lockId, unlockTime);
    }

    function test_extendLock_EmitsEvent() public {
        vm.prank(alice);
        uint256 lockId = timeLock.lockETH{value: LOCK_AMOUNT}(unlockTime);

        uint256 newUnlockTime = unlockTime + 7 days;

        vm.prank(owner);

        vm.expectEmit(true, false, false, true);
        emit LockExtended(lockId, unlockTime, newUnlockTime);

        timeLock.extendLock(lockId, newUnlockTime);
    }

    // =========================================================================
    //                       View Function Tests
    // =========================================================================

    function test_getLock() public {
        vm.prank(alice);
        uint256 lockId = timeLock.lockETH{value: LOCK_AMOUNT}(unlockTime);

        TimeLock.Lock memory lock = timeLock.getLock(lockId);

        assertEq(lock.depositor, alice);
        assertEq(lock.token, address(0));
        assertEq(lock.amount, LOCK_AMOUNT);
        assertEq(lock.unlockTime, unlockTime);
        assertFalse(lock.withdrawn);
    }

    function test_getUserLockIds() public {
        vm.startPrank(alice);
        timeLock.lockETH{value: 1 ether}(unlockTime);
        timeLock.lockERC20(address(token), TOKEN_AMOUNT, unlockTime);
        vm.stopPrank();

        uint256[] memory lockIds = timeLock.getUserLockIds(alice);

        assertEq(lockIds.length, 2, "Alice should have 2 locks");
        assertEq(lockIds[0], 0, "First lock ID should be 0");
        assertEq(lockIds[1], 1, "Second lock ID should be 1");
    }

    function test_isUnlocked_BeforeUnlock() public {
        vm.prank(alice);
        uint256 lockId = timeLock.lockETH{value: LOCK_AMOUNT}(unlockTime);

        // Before unlock time
        assertFalse(timeLock.isUnlocked(lockId), "Should not be unlocked before unlock time");
    }

    function test_isUnlocked_AfterUnlock() public {
        vm.prank(alice);
        uint256 lockId = timeLock.lockETH{value: LOCK_AMOUNT}(unlockTime);

        // Warp to exactly the unlock time
        vm.warp(unlockTime);
        assertTrue(timeLock.isUnlocked(lockId), "Should be unlocked at exact unlock time");

        // Warp past unlock time
        vm.warp(unlockTime + 1);
        assertTrue(timeLock.isUnlocked(lockId), "Should be unlocked after unlock time");
    }

    // =========================================================================
    //                       Edge Case Tests
    // =========================================================================

    function test_multipleLocksByDifferentUsers() public {
        // Alice locks ETH
        vm.prank(alice);
        uint256 aliceLockId = timeLock.lockETH{value: 1 ether}(unlockTime);

        // Bob locks ERC20
        vm.prank(bob);
        uint256 bobLockId = timeLock.lockERC20(address(token), TOKEN_AMOUNT, unlockTime);

        // Verify isolation: lock details are independent
        TimeLock.Lock memory aliceLock = timeLock.getLock(aliceLockId);
        TimeLock.Lock memory bobLock = timeLock.getLock(bobLockId);

        assertEq(aliceLock.depositor, alice);
        assertEq(bobLock.depositor, bob);

        assertEq(aliceLock.token, address(0));
        assertEq(bobLock.token, address(token));

        // Verify user lock arrays are separate
        uint256[] memory aliceLocks = timeLock.getUserLockIds(alice);
        uint256[] memory bobLocks = timeLock.getUserLockIds(bob);

        assertEq(aliceLocks.length, 1);
        assertEq(bobLocks.length, 1);
        assertEq(aliceLocks[0], aliceLockId);
        assertEq(bobLocks[0], bobLockId);

        // Warp and verify each user can only withdraw their own
        vm.warp(unlockTime + 1);

        vm.prank(bob);
        vm.expectRevert(TimeLock.NotDepositor.selector);
        timeLock.withdraw(aliceLockId);

        vm.prank(alice);
        vm.expectRevert(TimeLock.NotDepositor.selector);
        timeLock.withdraw(bobLockId);

        // Each can withdraw their own
        vm.prank(alice);
        timeLock.withdraw(aliceLockId);

        vm.prank(bob);
        timeLock.withdraw(bobLockId);
    }

    function test_lockIdAutoIncrements() public {
        vm.startPrank(alice);
        uint256 id0 = timeLock.lockETH{value: 1 ether}(unlockTime);
        uint256 id1 = timeLock.lockETH{value: 1 ether}(unlockTime);
        vm.stopPrank();

        vm.prank(bob);
        uint256 id2 = timeLock.lockERC20(address(token), TOKEN_AMOUNT, unlockTime);

        assertEq(id0, 0, "First lock ID should be 0");
        assertEq(id1, 1, "Second lock ID should be 1");
        assertEq(id2, 2, "Third lock ID should be 2");
        assertEq(timeLock.nextLockId(), 3, "nextLockId should be 3 after 3 locks");
    }
}
