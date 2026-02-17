// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {YieldTimeLock} from "../src/YieldTimeLock.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockMorphoVault} from "./mocks/MockMorphoVault.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract YieldTimeLockTest is Test {
    YieldTimeLock public yieldTimeLock;
    MockERC20 public token;
    MockMorphoVault public vault;
    MockMorphoVault public vault2;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public nonOwner = makeAddr("nonOwner");
    address public feeRecipient = makeAddr("feeRecipient");

    uint256 public constant INITIAL_BALANCE = 1_000_000e18;
    uint256 public constant DEPOSIT_AMOUNT = 1_000e18;
    uint256 public constant DEFAULT_FEE_BPS = 50;
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant ONE_DAY = 1 days;
    uint256 public constant ONE_WEEK = 7 days;

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
    event YieldLockWithdrawn(
        uint256 indexed lockId,
        address indexed depositor,
        address indexed vault,
        uint256 shares,
        uint256 totalAssets,
        uint256 fee,
        uint256 netAssets
    );
    event LockExtended(uint256 indexed lockId, uint256 oldUnlockTime, uint256 newUnlockTime);
    event EmergencyWithdrawal(uint256 indexed lockId, address indexed vault, uint256 shares, uint256 assets);
    event EmergencyFundsClaimed(
        uint256 indexed lockId, address indexed depositor, uint256 totalAssets, uint256 fee, uint256 netAssets
    );
    event VaultAdded(address indexed vault);
    event VaultRemoved(address indexed vault);
    event FeeUpdated(uint256 oldFeeBps, uint256 newFeeBps);
    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    event FeeCollected(uint256 indexed lockId, address indexed token, uint256 amount);

    function setUp() public {
        token = new MockERC20("Mock USDC", "mUSDC");
        vault = new MockMorphoVault(address(token));
        vault2 = new MockMorphoVault(address(token));

        yieldTimeLock = new YieldTimeLock(owner, feeRecipient);

        token.mint(alice, INITIAL_BALANCE);
        token.mint(bob, INITIAL_BALANCE);

        vm.prank(alice);
        token.approve(address(yieldTimeLock), type(uint256).max);

        vm.prank(bob);
        token.approve(address(yieldTimeLock), type(uint256).max);

        vm.prank(owner);
        yieldTimeLock.addVault(address(vault));
    }

    // =========================================================================
    //                      Constructor Tests
    // =========================================================================

    function test_constructor_SetsDefaults() public view {
        assertEq(yieldTimeLock.feeBps(), DEFAULT_FEE_BPS);
        assertEq(yieldTimeLock.feeRecipient(), feeRecipient);
        assertEq(yieldTimeLock.owner(), owner);
    }

    function test_constructor_RevertZeroFeeRecipient() public {
        vm.expectRevert(YieldTimeLock.ZeroAddress.selector);
        new YieldTimeLock(owner, address(0));
    }

    // =========================================================================
    //                      Vault Management Tests
    // =========================================================================

    function test_addVault_Success() public {
        vm.prank(owner);
        yieldTimeLock.addVault(address(vault2));

        assertTrue(yieldTimeLock.isVaultWhitelisted(address(vault2)));

        address[] memory list = yieldTimeLock.getVaultList();
        assertEq(list.length, 2);
        assertEq(list[1], address(vault2));
    }

    function test_addVault_RevertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(YieldTimeLock.ZeroAddress.selector);
        yieldTimeLock.addVault(address(0));
    }

    function test_addVault_RevertAlreadyWhitelisted() public {
        vm.prank(owner);
        vm.expectRevert(YieldTimeLock.VaultAlreadyWhitelisted.selector);
        yieldTimeLock.addVault(address(vault));
    }

    function test_addVault_RevertNotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        yieldTimeLock.addVault(address(vault2));
    }

    function test_addVault_EmitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, false, address(yieldTimeLock));
        emit VaultAdded(address(vault2));
        yieldTimeLock.addVault(address(vault2));
    }

    function test_removeVault_Success() public {
        vm.prank(owner);
        yieldTimeLock.removeVault(address(vault));

        assertFalse(yieldTimeLock.isVaultWhitelisted(address(vault)));
        address[] memory list = yieldTimeLock.getVaultList();
        assertEq(list.length, 0);
    }

    function test_removeVault_RevertNotInWhitelist() public {
        vm.prank(owner);
        vm.expectRevert(YieldTimeLock.VaultNotInWhitelist.selector);
        yieldTimeLock.removeVault(address(vault2));
    }

    function test_removeVault_RevertNotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        yieldTimeLock.removeVault(address(vault));
    }

    // =========================================================================
    //                      Lock With Yield Tests
    // =========================================================================

    function test_lockWithYield_Success() public {
        uint256 unlockTime = block.timestamp + ONE_WEEK;

        vm.prank(alice);
        uint256 lockId = yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, unlockTime, "rent");

        assertEq(lockId, 0);

        YieldTimeLock.YieldLock memory lock = yieldTimeLock.getYieldLock(lockId);
        assertEq(lock.depositor, alice);
        assertEq(lock.vault, address(vault));
        assertEq(lock.underlyingToken, address(token));
        assertEq(lock.shares, DEPOSIT_AMOUNT);
        assertEq(lock.principalAssets, DEPOSIT_AMOUNT);
        assertEq(lock.unlockTime, unlockTime);
        assertFalse(lock.withdrawn);
        assertFalse(lock.isEmergencyWithdrawn);
        assertEq(lock.label, "rent");

        assertEq(token.balanceOf(alice), INITIAL_BALANCE - DEPOSIT_AMOUNT);
        assertEq(vault.balanceOf(address(yieldTimeLock)), DEPOSIT_AMOUNT);
    }

    function test_lockWithYield_RevertVaultNotWhitelisted() public {
        vm.prank(alice);
        vm.expectRevert(YieldTimeLock.VaultNotWhitelisted.selector);
        yieldTimeLock.lockWithYield(address(vault2), DEPOSIT_AMOUNT, block.timestamp + ONE_WEEK, "");
    }

    function test_lockWithYield_RevertZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(YieldTimeLock.AmountMustBeGreaterThanZero.selector);
        yieldTimeLock.lockWithYield(address(vault), 0, block.timestamp + ONE_WEEK, "");
    }

    function test_lockWithYield_RevertUnlockTimeNotInFuture() public {
        vm.prank(alice);
        vm.expectRevert(YieldTimeLock.UnlockTimeNotInFuture.selector);
        yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, block.timestamp, "");
    }

    function test_lockWithYield_EmitsEvent() public {
        uint256 unlockTime = block.timestamp + ONE_WEEK;

        vm.prank(alice);
        vm.expectEmit(true, true, true, true, address(yieldTimeLock));
        emit YieldLockCreated(0, alice, address(vault), address(token), DEPOSIT_AMOUNT, DEPOSIT_AMOUNT, unlockTime, "savings");
        yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, unlockTime, "savings");
    }

    function test_lockWithYield_MultipleLocks() public {
        vm.startPrank(alice);
        uint256 lockId1 = yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, block.timestamp + ONE_WEEK, "rent");
        uint256 lockId2 = yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, block.timestamp + ONE_WEEK * 2, "vacation");
        vm.stopPrank();

        assertEq(lockId1, 0);
        assertEq(lockId2, 1);

        uint256[] memory lockIds = yieldTimeLock.getUserYieldLockIds(alice);
        assertEq(lockIds.length, 2);
        assertEq(lockIds[0], 0);
        assertEq(lockIds[1], 1);
    }

    // =========================================================================
    //                      Withdraw Tests
    // =========================================================================

    function test_withdraw_Success() public {
        uint256 unlockTime = block.timestamp + ONE_WEEK;

        vm.prank(alice);
        uint256 lockId = yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, unlockTime, "");

        vm.warp(unlockTime);

        vm.prank(alice);
        yieldTimeLock.withdraw(lockId);

        YieldTimeLock.YieldLock memory lock = yieldTimeLock.getYieldLock(lockId);
        assertTrue(lock.withdrawn);

        uint256 fee = (DEPOSIT_AMOUNT * DEFAULT_FEE_BPS) / BPS_DENOMINATOR;
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - fee);
        assertEq(token.balanceOf(feeRecipient), fee);
    }

    function test_withdraw_WithYield() public {
        uint256 unlockTime = block.timestamp + ONE_WEEK;

        vm.prank(alice);
        uint256 lockId = yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, unlockTime, "");

        uint256 yieldAmount = 100e18;
        vault.simulateYield(yieldAmount);

        vm.warp(unlockTime);

        vm.prank(alice);
        yieldTimeLock.withdraw(lockId);

        uint256 totalAssets = DEPOSIT_AMOUNT + yieldAmount;
        uint256 fee = (totalAssets * DEFAULT_FEE_BPS) / BPS_DENOMINATOR;
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - DEPOSIT_AMOUNT + totalAssets - fee);
        assertEq(token.balanceOf(feeRecipient), fee);
    }

    function test_withdraw_RevertNotDepositor() public {
        uint256 unlockTime = block.timestamp + ONE_WEEK;

        vm.prank(alice);
        uint256 lockId = yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, unlockTime, "");

        vm.warp(unlockTime);

        vm.prank(bob);
        vm.expectRevert(YieldTimeLock.NotDepositor.selector);
        yieldTimeLock.withdraw(lockId);
    }

    function test_withdraw_RevertLockNotExpired() public {
        uint256 unlockTime = block.timestamp + ONE_WEEK;

        vm.prank(alice);
        uint256 lockId = yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, unlockTime, "");

        vm.prank(alice);
        vm.expectRevert(YieldTimeLock.LockNotExpired.selector);
        yieldTimeLock.withdraw(lockId);
    }

    function test_withdraw_RevertAlreadyWithdrawn() public {
        uint256 unlockTime = block.timestamp + ONE_WEEK;

        vm.prank(alice);
        uint256 lockId = yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, unlockTime, "");

        vm.warp(unlockTime);

        vm.prank(alice);
        yieldTimeLock.withdraw(lockId);

        vm.prank(alice);
        vm.expectRevert(YieldTimeLock.AlreadyWithdrawn.selector);
        yieldTimeLock.withdraw(lockId);
    }

    function test_withdraw_WorksAfterVaultDelisted() public {
        uint256 unlockTime = block.timestamp + ONE_WEEK;

        vm.prank(alice);
        uint256 lockId = yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, unlockTime, "");

        vm.prank(owner);
        yieldTimeLock.removeVault(address(vault));

        vm.warp(unlockTime);

        vm.prank(alice);
        yieldTimeLock.withdraw(lockId);

        YieldTimeLock.YieldLock memory lock = yieldTimeLock.getYieldLock(lockId);
        assertTrue(lock.withdrawn);
    }

    function test_withdraw_EmitsEvents() public {
        uint256 unlockTime = block.timestamp + ONE_WEEK;

        vm.prank(alice);
        uint256 lockId = yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, unlockTime, "");

        vm.warp(unlockTime);

        uint256 fee = (DEPOSIT_AMOUNT * DEFAULT_FEE_BPS) / BPS_DENOMINATOR;
        uint256 netAssets = DEPOSIT_AMOUNT - fee;

        vm.prank(alice);
        vm.expectEmit(true, true, false, true, address(yieldTimeLock));
        emit FeeCollected(lockId, address(token), fee);
        vm.expectEmit(true, true, true, true, address(yieldTimeLock));
        emit YieldLockWithdrawn(lockId, alice, address(vault), DEPOSIT_AMOUNT, DEPOSIT_AMOUNT, fee, netAssets);
        yieldTimeLock.withdraw(lockId);
    }

    // =========================================================================
    //                      Extend Lock Tests
    // =========================================================================

    function test_extendLock_Success() public {
        uint256 unlockTime = block.timestamp + ONE_WEEK;

        vm.prank(alice);
        uint256 lockId = yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, unlockTime, "");

        uint256 newUnlockTime = unlockTime + ONE_WEEK;

        vm.prank(owner);
        yieldTimeLock.extendLock(lockId, newUnlockTime);

        YieldTimeLock.YieldLock memory lock = yieldTimeLock.getYieldLock(lockId);
        assertEq(lock.unlockTime, newUnlockTime);
    }

    function test_extendLock_RevertNotOwner() public {
        uint256 unlockTime = block.timestamp + ONE_WEEK;

        vm.prank(alice);
        uint256 lockId = yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, unlockTime, "");

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        yieldTimeLock.extendLock(lockId, unlockTime + ONE_WEEK);
    }

    function test_extendLock_RevertNewTimeMustBeAfter() public {
        uint256 unlockTime = block.timestamp + ONE_WEEK;

        vm.prank(alice);
        uint256 lockId = yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, unlockTime, "");

        vm.prank(owner);
        vm.expectRevert(YieldTimeLock.NewUnlockTimeMustBeAfterCurrent.selector);
        yieldTimeLock.extendLock(lockId, unlockTime - 1);
    }

    function test_extendLock_EmitsEvent() public {
        uint256 unlockTime = block.timestamp + ONE_WEEK;

        vm.prank(alice);
        uint256 lockId = yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, unlockTime, "");

        uint256 newUnlockTime = unlockTime + ONE_WEEK;

        vm.prank(owner);
        vm.expectEmit(true, false, false, true, address(yieldTimeLock));
        emit LockExtended(lockId, unlockTime, newUnlockTime);
        yieldTimeLock.extendLock(lockId, newUnlockTime);
    }

    // =========================================================================
    //                      Emergency Withdrawal Tests
    // =========================================================================

    function test_emergencyWithdraw_Success() public {
        uint256 unlockTime = block.timestamp + ONE_WEEK;

        vm.prank(alice);
        uint256 lockId = yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, unlockTime, "");

        vm.prank(owner);
        yieldTimeLock.emergencyWithdraw(lockId);

        YieldTimeLock.YieldLock memory lock = yieldTimeLock.getYieldLock(lockId);
        assertTrue(lock.isEmergencyWithdrawn);
        assertFalse(lock.withdrawn);

        assertEq(yieldTimeLock.emergencyAssets(lockId), DEPOSIT_AMOUNT);
        assertEq(token.balanceOf(address(yieldTimeLock)), DEPOSIT_AMOUNT);
    }

    function test_emergencyWithdraw_RevertNotOwner() public {
        uint256 unlockTime = block.timestamp + ONE_WEEK;

        vm.prank(alice);
        uint256 lockId = yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, unlockTime, "");

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        yieldTimeLock.emergencyWithdraw(lockId);
    }

    function test_emergencyWithdraw_RevertAlreadyProcessed() public {
        uint256 unlockTime = block.timestamp + ONE_WEEK;

        vm.prank(alice);
        uint256 lockId = yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, unlockTime, "");

        vm.prank(owner);
        yieldTimeLock.emergencyWithdraw(lockId);

        vm.prank(owner);
        vm.expectRevert(YieldTimeLock.LockAlreadyProcessed.selector);
        yieldTimeLock.emergencyWithdraw(lockId);
    }

    function test_emergencyWithdraw_EmitsEvent() public {
        uint256 unlockTime = block.timestamp + ONE_WEEK;

        vm.prank(alice);
        uint256 lockId = yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, unlockTime, "");

        vm.prank(owner);
        vm.expectEmit(true, true, false, true, address(yieldTimeLock));
        emit EmergencyWithdrawal(lockId, address(vault), DEPOSIT_AMOUNT, DEPOSIT_AMOUNT);
        yieldTimeLock.emergencyWithdraw(lockId);
    }

    function test_withdraw_RevertIfEmergencyWithdrawn() public {
        uint256 unlockTime = block.timestamp + ONE_WEEK;

        vm.prank(alice);
        uint256 lockId = yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, unlockTime, "");

        vm.prank(owner);
        yieldTimeLock.emergencyWithdraw(lockId);

        vm.warp(unlockTime);

        vm.prank(alice);
        vm.expectRevert(YieldTimeLock.LockIsEmergencyWithdrawn.selector);
        yieldTimeLock.withdraw(lockId);
    }

    // =========================================================================
    //                      Claim Emergency Funds Tests
    // =========================================================================

    function test_claimEmergencyFunds_Success() public {
        uint256 unlockTime = block.timestamp + ONE_WEEK;

        vm.prank(alice);
        uint256 lockId = yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, unlockTime, "");

        vm.prank(owner);
        yieldTimeLock.emergencyWithdraw(lockId);

        vm.warp(unlockTime);

        vm.prank(alice);
        yieldTimeLock.claimEmergencyFunds(lockId);

        YieldTimeLock.YieldLock memory lock = yieldTimeLock.getYieldLock(lockId);
        assertTrue(lock.withdrawn);

        uint256 fee = (DEPOSIT_AMOUNT * DEFAULT_FEE_BPS) / BPS_DENOMINATOR;
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - fee);
        assertEq(token.balanceOf(feeRecipient), fee);
        assertEq(yieldTimeLock.emergencyAssets(lockId), 0);
    }

    function test_claimEmergencyFunds_RevertNotDepositor() public {
        uint256 unlockTime = block.timestamp + ONE_WEEK;

        vm.prank(alice);
        uint256 lockId = yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, unlockTime, "");

        vm.prank(owner);
        yieldTimeLock.emergencyWithdraw(lockId);

        vm.warp(unlockTime);

        vm.prank(bob);
        vm.expectRevert(YieldTimeLock.NotDepositor.selector);
        yieldTimeLock.claimEmergencyFunds(lockId);
    }

    function test_claimEmergencyFunds_RevertNotEmergencyWithdrawn() public {
        uint256 unlockTime = block.timestamp + ONE_WEEK;

        vm.prank(alice);
        uint256 lockId = yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, unlockTime, "");

        vm.warp(unlockTime);

        vm.prank(alice);
        vm.expectRevert(YieldTimeLock.NotEmergencyWithdrawn.selector);
        yieldTimeLock.claimEmergencyFunds(lockId);
    }

    function test_claimEmergencyFunds_RevertLockNotExpired() public {
        uint256 unlockTime = block.timestamp + ONE_WEEK;

        vm.prank(alice);
        uint256 lockId = yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, unlockTime, "");

        vm.prank(owner);
        yieldTimeLock.emergencyWithdraw(lockId);

        vm.prank(alice);
        vm.expectRevert(YieldTimeLock.LockNotExpired.selector);
        yieldTimeLock.claimEmergencyFunds(lockId);
    }

    function test_claimEmergencyFunds_RevertAlreadyWithdrawn() public {
        uint256 unlockTime = block.timestamp + ONE_WEEK;

        vm.prank(alice);
        uint256 lockId = yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, unlockTime, "");

        vm.prank(owner);
        yieldTimeLock.emergencyWithdraw(lockId);

        vm.warp(unlockTime);

        vm.prank(alice);
        yieldTimeLock.claimEmergencyFunds(lockId);

        vm.prank(alice);
        vm.expectRevert(YieldTimeLock.AlreadyWithdrawn.selector);
        yieldTimeLock.claimEmergencyFunds(lockId);
    }

    function test_claimEmergencyFunds_EmitsEvents() public {
        uint256 unlockTime = block.timestamp + ONE_WEEK;

        vm.prank(alice);
        uint256 lockId = yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, unlockTime, "");

        vm.prank(owner);
        yieldTimeLock.emergencyWithdraw(lockId);

        vm.warp(unlockTime);

        uint256 fee = (DEPOSIT_AMOUNT * DEFAULT_FEE_BPS) / BPS_DENOMINATOR;
        uint256 netAssets = DEPOSIT_AMOUNT - fee;

        vm.prank(alice);
        vm.expectEmit(true, true, false, true, address(yieldTimeLock));
        emit FeeCollected(lockId, address(token), fee);
        vm.expectEmit(true, true, false, true, address(yieldTimeLock));
        emit EmergencyFundsClaimed(lockId, alice, DEPOSIT_AMOUNT, fee, netAssets);
        yieldTimeLock.claimEmergencyFunds(lockId);
    }

    // =========================================================================
    //                      Fee Management Tests
    // =========================================================================

    function test_setFeeBps_Success() public {
        vm.prank(owner);
        yieldTimeLock.setFeeBps(100);

        assertEq(yieldTimeLock.feeBps(), 100);
    }

    function test_setFeeBps_Zero() public {
        vm.prank(owner);
        yieldTimeLock.setFeeBps(0);

        uint256 unlockTime = block.timestamp + ONE_WEEK;

        vm.prank(alice);
        uint256 lockId = yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, unlockTime, "");

        vm.warp(unlockTime);

        vm.prank(alice);
        yieldTimeLock.withdraw(lockId);

        assertEq(token.balanceOf(alice), INITIAL_BALANCE);
        assertEq(token.balanceOf(feeRecipient), 0);
    }

    function test_setFeeBps_RevertFeeTooHigh() public {
        vm.prank(owner);
        vm.expectRevert(YieldTimeLock.FeeTooHigh.selector);
        yieldTimeLock.setFeeBps(1_001);
    }

    function test_setFeeBps_RevertNotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        yieldTimeLock.setFeeBps(100);
    }

    function test_setFeeBps_EmitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(false, false, false, true, address(yieldTimeLock));
        emit FeeUpdated(DEFAULT_FEE_BPS, 200);
        yieldTimeLock.setFeeBps(200);
    }

    function test_setFeeRecipient_Success() public {
        address newRecipient = makeAddr("newRecipient");

        vm.prank(owner);
        yieldTimeLock.setFeeRecipient(newRecipient);

        assertEq(yieldTimeLock.feeRecipient(), newRecipient);
    }

    function test_setFeeRecipient_RevertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(YieldTimeLock.ZeroAddress.selector);
        yieldTimeLock.setFeeRecipient(address(0));
    }

    function test_setFeeRecipient_RevertNotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        yieldTimeLock.setFeeRecipient(makeAddr("someone"));
    }

    function test_setFeeRecipient_EmitsEvent() public {
        address newRecipient = makeAddr("newRecipient");

        vm.prank(owner);
        vm.expectEmit(true, true, false, false, address(yieldTimeLock));
        emit FeeRecipientUpdated(feeRecipient, newRecipient);
        yieldTimeLock.setFeeRecipient(newRecipient);
    }

    // =========================================================================
    //                      View Function Tests
    // =========================================================================

    function test_previewWithdraw_NoYield() public {
        uint256 unlockTime = block.timestamp + ONE_WEEK;

        vm.prank(alice);
        uint256 lockId = yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, unlockTime, "");

        (uint256 totalAssets, uint256 fee, uint256 netAssets) = yieldTimeLock.previewWithdraw(lockId);

        assertEq(totalAssets, DEPOSIT_AMOUNT);
        assertEq(fee, (DEPOSIT_AMOUNT * DEFAULT_FEE_BPS) / BPS_DENOMINATOR);
        assertEq(netAssets, totalAssets - fee);
    }

    function test_previewWithdraw_WithYield() public {
        uint256 unlockTime = block.timestamp + ONE_WEEK;

        vm.prank(alice);
        uint256 lockId = yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, unlockTime, "");

        uint256 yieldAmount = 100e18;
        vault.simulateYield(yieldAmount);

        (uint256 totalAssets, uint256 fee, uint256 netAssets) = yieldTimeLock.previewWithdraw(lockId);

        assertEq(totalAssets, DEPOSIT_AMOUNT + yieldAmount);
        assertEq(fee, (totalAssets * DEFAULT_FEE_BPS) / BPS_DENOMINATOR);
        assertEq(netAssets, totalAssets - fee);
    }

    function test_previewWithdraw_EmergencyWithdrawn() public {
        uint256 unlockTime = block.timestamp + ONE_WEEK;

        vm.prank(alice);
        uint256 lockId = yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, unlockTime, "");

        vm.prank(owner);
        yieldTimeLock.emergencyWithdraw(lockId);

        (uint256 totalAssets, uint256 fee, uint256 netAssets) = yieldTimeLock.previewWithdraw(lockId);

        assertEq(totalAssets, DEPOSIT_AMOUNT);
        assertEq(fee, (DEPOSIT_AMOUNT * DEFAULT_FEE_BPS) / BPS_DENOMINATOR);
        assertEq(netAssets, totalAssets - fee);
    }

    function test_getAccruedYield_NoYield() public {
        uint256 unlockTime = block.timestamp + ONE_WEEK;

        vm.prank(alice);
        uint256 lockId = yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, unlockTime, "");

        (uint256 yield_, uint256 currentAssets) = yieldTimeLock.getAccruedYield(lockId);

        assertEq(yield_, 0);
        assertEq(currentAssets, DEPOSIT_AMOUNT);
    }

    function test_getAccruedYield_WithYield() public {
        uint256 unlockTime = block.timestamp + ONE_WEEK;

        vm.prank(alice);
        uint256 lockId = yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, unlockTime, "");

        uint256 yieldAmount = 100e18;
        vault.simulateYield(yieldAmount);

        (uint256 yield_, uint256 currentAssets) = yieldTimeLock.getAccruedYield(lockId);

        assertEq(yield_, yieldAmount);
        assertEq(currentAssets, DEPOSIT_AMOUNT + yieldAmount);
    }

    function test_getAccruedYield_WithLoss() public {
        uint256 unlockTime = block.timestamp + ONE_WEEK;

        vm.prank(alice);
        uint256 lockId = yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, unlockTime, "");

        uint256 lossAmount = 100e18;
        vault.simulateLoss(lossAmount);

        (uint256 yield_, uint256 currentAssets) = yieldTimeLock.getAccruedYield(lockId);

        assertEq(yield_, 0);
        assertEq(currentAssets, DEPOSIT_AMOUNT - lossAmount);
    }

    function test_isUnlocked() public {
        uint256 unlockTime = block.timestamp + ONE_WEEK;

        vm.prank(alice);
        uint256 lockId = yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, unlockTime, "");

        assertFalse(yieldTimeLock.isUnlocked(lockId));

        vm.warp(unlockTime - 1);
        assertFalse(yieldTimeLock.isUnlocked(lockId));

        vm.warp(unlockTime);
        assertTrue(yieldTimeLock.isUnlocked(lockId));
    }

    // =========================================================================
    //                      Full Lifecycle Tests
    // =========================================================================

    function test_fullLifecycle_NormalWithdraw() public {
        uint256 unlockTime = block.timestamp + ONE_WEEK;

        vm.prank(alice);
        uint256 lockId = yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, unlockTime, "savings");

        uint256 yieldAmount = 50e18;
        vault.simulateYield(yieldAmount);

        vm.warp(unlockTime);

        (, uint256 previewFee, uint256 previewNet) = yieldTimeLock.previewWithdraw(lockId);

        vm.prank(alice);
        yieldTimeLock.withdraw(lockId);

        uint256 aliceBalanceAfter = token.balanceOf(alice);
        uint256 expectedBalance = INITIAL_BALANCE - DEPOSIT_AMOUNT + previewNet;
        assertEq(aliceBalanceAfter, expectedBalance);
        assertEq(token.balanceOf(feeRecipient), previewFee);
    }

    function test_fullLifecycle_EmergencyWithdraw() public {
        uint256 unlockTime = block.timestamp + ONE_WEEK;

        vm.prank(alice);
        uint256 lockId = yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, unlockTime, "");

        uint256 yieldAmount = 50e18;
        vault.simulateYield(yieldAmount);

        vm.prank(owner);
        yieldTimeLock.emergencyWithdraw(lockId);

        vm.warp(unlockTime);

        uint256 expectedTotal = DEPOSIT_AMOUNT + yieldAmount;
        uint256 expectedFee = (expectedTotal * DEFAULT_FEE_BPS) / BPS_DENOMINATOR;
        uint256 expectedNet = expectedTotal - expectedFee;

        vm.prank(alice);
        yieldTimeLock.claimEmergencyFunds(lockId);

        assertEq(token.balanceOf(alice), INITIAL_BALANCE - DEPOSIT_AMOUNT + expectedNet);
        assertEq(token.balanceOf(feeRecipient), expectedFee);
    }

    function test_multipleUsersMultipleLocks() public {
        uint256 unlockTime1 = block.timestamp + ONE_WEEK;
        uint256 unlockTime2 = block.timestamp + ONE_WEEK * 2;

        vm.prank(alice);
        uint256 aliceLock1 = yieldTimeLock.lockWithYield(address(vault), 500e18, unlockTime1, "rent");

        vm.prank(bob);
        uint256 bobLock1 = yieldTimeLock.lockWithYield(address(vault), 300e18, unlockTime1, "");

        vm.prank(alice);
        uint256 aliceLock2 = yieldTimeLock.lockWithYield(address(vault), 200e18, unlockTime2, "vacation");

        vault.simulateYield(100e18);

        vm.warp(unlockTime1);

        vm.prank(alice);
        yieldTimeLock.withdraw(aliceLock1);

        vm.prank(bob);
        yieldTimeLock.withdraw(bobLock1);

        YieldTimeLock.YieldLock memory lock = yieldTimeLock.getYieldLock(aliceLock2);
        assertFalse(lock.withdrawn);

        vm.warp(unlockTime2);

        vm.prank(alice);
        yieldTimeLock.withdraw(aliceLock2);

        uint256[] memory aliceLocks = yieldTimeLock.getUserYieldLockIds(alice);
        uint256[] memory bobLocks = yieldTimeLock.getUserYieldLockIds(bob);

        assertEq(aliceLocks.length, 2);
        assertEq(bobLocks.length, 1);
    }

    // =========================================================================
    //                      Label Tests
    // =========================================================================

    function test_getUserLocksByLabel_Success() public {
        uint256 unlockTime = block.timestamp + ONE_WEEK;

        vm.startPrank(alice);
        yieldTimeLock.lockWithYield(address(vault), 100e18, unlockTime, "rent");
        yieldTimeLock.lockWithYield(address(vault), 200e18, unlockTime, "rent");
        yieldTimeLock.lockWithYield(address(vault), 300e18, unlockTime, "vacation");
        yieldTimeLock.lockWithYield(address(vault), 400e18, unlockTime, "");
        vm.stopPrank();

        uint256[] memory rentLocks = yieldTimeLock.getUserLocksByLabel(alice, "rent");
        assertEq(rentLocks.length, 2);
        assertEq(rentLocks[0], 0);
        assertEq(rentLocks[1], 1);

        uint256[] memory vacationLocks = yieldTimeLock.getUserLocksByLabel(alice, "vacation");
        assertEq(vacationLocks.length, 1);
        assertEq(vacationLocks[0], 2);

        uint256[] memory emptyLabelLocks = yieldTimeLock.getUserLocksByLabel(alice, "");
        assertEq(emptyLabelLocks.length, 1);
        assertEq(emptyLabelLocks[0], 3);

        uint256[] memory nonExistentLocks = yieldTimeLock.getUserLocksByLabel(alice, "nonexistent");
        assertEq(nonExistentLocks.length, 0);
    }

    function test_getUserLocksByLabel_EmptyForNonUser() public {
        uint256[] memory locks = yieldTimeLock.getUserLocksByLabel(alice, "rent");
        assertEq(locks.length, 0);
    }

    function test_label_StoredCorrectly() public {
        uint256 unlockTime = block.timestamp + ONE_WEEK;

        vm.prank(alice);
        uint256 lockId = yieldTimeLock.lockWithYield(address(vault), DEPOSIT_AMOUNT, unlockTime, "monthly-rent");

        YieldTimeLock.YieldLock memory lock = yieldTimeLock.getYieldLock(lockId);
        assertEq(lock.label, "monthly-rent");
    }
}
