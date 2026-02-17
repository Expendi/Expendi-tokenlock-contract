// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MorphoVaultDepositor} from "../src/MorphoVaultDepositor.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockMorphoVault} from "./mocks/MockMorphoVault.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MorphoVaultDepositorTest is Test {
    MorphoVaultDepositor public depositor;
    MockERC20 public token;
    MockMorphoVault public vault;
    MockMorphoVault public vault2;
    MockMorphoVault public vault3;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public nonOwner = makeAddr("nonOwner");
    address public feeRecipient = makeAddr("feeRecipient");

    uint256 public constant INITIAL_BALANCE = 1_000_000e18;
    uint256 public constant DEPOSIT_AMOUNT = 1_000e18;
    uint256 public constant DEFAULT_FEE_BPS = 50; // 0.5%
    uint256 public constant BPS_DENOMINATOR = 10_000;

    // Re-declare events from MorphoVaultDepositor to use in expectEmit
    event Deposited(address indexed user, address indexed vault, uint256 assets, uint256 shares);
    event WithdrawnFromVault(address indexed user, address indexed vault, uint256 shares, uint256 assets);
    event VaultAdded(address indexed vault);
    event VaultRemoved(address indexed vault);
    event FeeUpdated(uint256 oldFeeBps, uint256 newFeeBps);
    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    event FeeCollected(address indexed vault, address indexed token, uint256 amount);

    function setUp() public {
        // Deploy underlying ERC20 token
        token = new MockERC20("Mock USDC", "mUSDC");

        // Deploy three ERC4626 vaults backed by the same token
        vault = new MockMorphoVault(address(token));
        vault2 = new MockMorphoVault(address(token));
        vault3 = new MockMorphoVault(address(token));

        // Deploy MorphoVaultDepositor with owner and fee recipient
        depositor = new MorphoVaultDepositor(owner, feeRecipient);

        // Mint tokens to test users
        token.mint(alice, INITIAL_BALANCE);
        token.mint(bob, INITIAL_BALANCE);

        // Approve depositor to spend tokens on behalf of users
        vm.prank(alice);
        token.approve(address(depositor), type(uint256).max);

        vm.prank(bob);
        token.approve(address(depositor), type(uint256).max);

        // Owner whitelists the first vault by default for deposit/withdraw tests
        vm.prank(owner);
        depositor.addVault(address(vault));
    }

    // =========================================================================
    //                      Vault Management Tests
    // =========================================================================

    /// @notice Owner can add a vault; whitelist flag and vaultList are updated.
    function test_addVault_Success() public {
        vm.prank(owner);
        depositor.addVault(address(vault2));

        assertTrue(depositor.isVaultWhitelisted(address(vault2)));

        address[] memory list = depositor.getVaultList();
        assertEq(list.length, 2);
        assertEq(list[0], address(vault));
        assertEq(list[1], address(vault2));
    }

    /// @notice Cannot add the zero address as a vault.
    function test_addVault_RevertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(MorphoVaultDepositor.ZeroAddress.selector);
        depositor.addVault(address(0));
    }

    /// @notice Cannot add a vault that is already whitelisted.
    function test_addVault_RevertAlreadyWhitelisted() public {
        vm.prank(owner);
        vm.expectRevert(MorphoVaultDepositor.VaultAlreadyWhitelisted.selector);
        depositor.addVault(address(vault)); // vault already added in setUp
    }

    /// @notice Non-owner cannot add a vault.
    function test_addVault_RevertNotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        depositor.addVault(address(vault2));
    }

    /// @notice Adding a vault emits the VaultAdded event.
    function test_addVault_EmitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, false, address(depositor));
        emit VaultAdded(address(vault2));
        depositor.addVault(address(vault2));
    }

    /// @notice Owner can remove a vault; whitelist flag is cleared and vaultList is updated.
    function test_removeVault_Success() public {
        vm.prank(owner);
        depositor.removeVault(address(vault));

        assertFalse(depositor.isVaultWhitelisted(address(vault)));

        address[] memory list = depositor.getVaultList();
        assertEq(list.length, 0);
    }

    /// @notice Cannot remove a vault that is not whitelisted.
    function test_removeVault_RevertNotInWhitelist() public {
        vm.prank(owner);
        vm.expectRevert(MorphoVaultDepositor.VaultNotInWhitelist.selector);
        depositor.removeVault(address(vault2)); // vault2 not whitelisted
    }

    /// @notice Non-owner cannot remove a vault.
    function test_removeVault_RevertNotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        depositor.removeVault(address(vault));
    }

    /// @notice Removing a vault emits the VaultRemoved event.
    function test_removeVault_EmitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, false, address(depositor));
        emit VaultRemoved(address(vault));
        depositor.removeVault(address(vault));
    }

    // =========================================================================
    //                          Deposit Tests
    // =========================================================================

    /// @notice Alice deposits assets and her tracked shares increase.
    function test_depositToVault_Success() public {
        vm.prank(alice);
        depositor.depositToVault(address(vault), DEPOSIT_AMOUNT);

        uint256 shares = depositor.getUserShares(alice, address(vault));
        assertGt(shares, 0, "shares should be > 0 after deposit");

        // In a 1:1 vault with no prior deposits, shares == amount deposited
        assertEq(shares, DEPOSIT_AMOUNT);

        // Token transferred from alice
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - DEPOSIT_AMOUNT);
    }

    /// @notice Cannot deposit to a non-whitelisted vault.
    function test_depositToVault_RevertNotWhitelisted() public {
        vm.prank(alice);
        vm.expectRevert(MorphoVaultDepositor.VaultNotWhitelisted.selector);
        depositor.depositToVault(address(vault2), DEPOSIT_AMOUNT);
    }

    /// @notice Cannot deposit zero amount.
    function test_depositToVault_RevertZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(MorphoVaultDepositor.AmountMustBeGreaterThanZero.selector);
        depositor.depositToVault(address(vault), 0);
    }

    /// @notice Multiple deposits accumulate shares correctly.
    function test_depositToVault_MultipleDeposits() public {
        vm.startPrank(alice);
        depositor.depositToVault(address(vault), DEPOSIT_AMOUNT);
        depositor.depositToVault(address(vault), DEPOSIT_AMOUNT);
        vm.stopPrank();

        uint256 shares = depositor.getUserShares(alice, address(vault));
        assertEq(shares, DEPOSIT_AMOUNT * 2);
    }

    /// @notice Depositing emits the Deposited event with correct parameters.
    function test_depositToVault_EmitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true, address(depositor));
        emit Deposited(alice, address(vault), DEPOSIT_AMOUNT, DEPOSIT_AMOUNT);
        depositor.depositToVault(address(vault), DEPOSIT_AMOUNT);
    }

    /// @notice Multiple users deposit independently; shares are tracked per-user.
    function test_depositToVault_MultipleUsers() public {
        uint256 aliceAmount = 500e18;
        uint256 bobAmount = 700e18;

        vm.prank(alice);
        depositor.depositToVault(address(vault), aliceAmount);

        vm.prank(bob);
        depositor.depositToVault(address(vault), bobAmount);

        assertEq(depositor.getUserShares(alice, address(vault)), aliceAmount);
        assertEq(depositor.getUserShares(bob, address(vault)), bobAmount);

        // Verify alice and bob shares are isolated (alice has no bob-level shares and vice-versa)
        assertEq(depositor.getUserShares(alice, address(vault)), aliceAmount);
        assertEq(depositor.getUserShares(bob, address(vault)), bobAmount);
    }

    // =========================================================================
    //                        Withdrawal Tests
    // =========================================================================

    /// @notice Alice deposits then withdraws all shares, receiving assets minus fee.
    function test_withdrawFromVault_Success() public {
        vm.prank(alice);
        depositor.depositToVault(address(vault), DEPOSIT_AMOUNT);

        uint256 shares = depositor.getUserShares(alice, address(vault));

        vm.prank(alice);
        depositor.withdrawFromVault(address(vault), shares);

        // All shares withdrawn
        assertEq(depositor.getUserShares(alice, address(vault)), 0);

        // Alice receives assets minus fee (0.5% fee on 1000e18 = 5e17)
        uint256 fee = (DEPOSIT_AMOUNT * DEFAULT_FEE_BPS) / BPS_DENOMINATOR;
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - fee);
        assertEq(token.balanceOf(feeRecipient), fee);
    }

    /// @notice Cannot withdraw from a non-whitelisted vault.
    function test_withdrawFromVault_RevertNotWhitelisted() public {
        vm.prank(alice);
        vm.expectRevert(MorphoVaultDepositor.VaultNotWhitelisted.selector);
        depositor.withdrawFromVault(address(vault2), 100e18);
    }

    /// @notice Cannot withdraw zero shares.
    function test_withdrawFromVault_RevertZeroShares() public {
        vm.prank(alice);
        vm.expectRevert(MorphoVaultDepositor.SharesMustBeGreaterThanZero.selector);
        depositor.withdrawFromVault(address(vault), 0);
    }

    /// @notice Cannot withdraw more shares than the user owns.
    function test_withdrawFromVault_RevertInsufficientShares() public {
        vm.prank(alice);
        depositor.depositToVault(address(vault), DEPOSIT_AMOUNT);

        vm.prank(alice);
        vm.expectRevert(MorphoVaultDepositor.InsufficientShares.selector);
        depositor.withdrawFromVault(address(vault), DEPOSIT_AMOUNT + 1);
    }

    /// @notice Partial withdrawal leaves remaining shares intact; fee applies to redeemed portion.
    function test_withdrawFromVault_PartialWithdraw() public {
        vm.prank(alice);
        depositor.depositToVault(address(vault), DEPOSIT_AMOUNT);

        uint256 halfShares = DEPOSIT_AMOUNT / 2;

        vm.prank(alice);
        depositor.withdrawFromVault(address(vault), halfShares);

        assertEq(depositor.getUserShares(alice, address(vault)), DEPOSIT_AMOUNT - halfShares);

        // Alice receives half minus fee
        uint256 halfAssets = halfShares; // 1:1 ratio
        uint256 fee = (halfAssets * DEFAULT_FEE_BPS) / BPS_DENOMINATOR;
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - DEPOSIT_AMOUNT + halfAssets - fee);
        assertEq(token.balanceOf(feeRecipient), fee);
    }

    /// @notice Withdrawing emits the WithdrawnFromVault event with post-fee amount.
    function test_withdrawFromVault_EmitsEvent() public {
        vm.prank(alice);
        depositor.depositToVault(address(vault), DEPOSIT_AMOUNT);

        uint256 shares = depositor.getUserShares(alice, address(vault));
        uint256 fee = (DEPOSIT_AMOUNT * DEFAULT_FEE_BPS) / BPS_DENOMINATOR;
        uint256 assetsAfterFee = DEPOSIT_AMOUNT - fee;

        vm.prank(alice);
        vm.expectEmit(true, true, false, true, address(depositor));
        emit WithdrawnFromVault(alice, address(vault), shares, assetsAfterFee);
        depositor.withdrawFromVault(address(vault), shares);
    }

    // =========================================================================
    //                        View Function Tests
    // =========================================================================

    /// @notice getUserShares returns correct share balance before and after deposit.
    function test_getUserShares() public {
        // Before deposit: zero
        assertEq(depositor.getUserShares(alice, address(vault)), 0);

        vm.prank(alice);
        depositor.depositToVault(address(vault), DEPOSIT_AMOUNT);

        // After deposit: DEPOSIT_AMOUNT (1:1 ratio in fresh vault)
        assertEq(depositor.getUserShares(alice, address(vault)), DEPOSIT_AMOUNT);
    }

    /// @notice isVaultWhitelisted returns correct true/false status.
    function test_isVaultWhitelisted() public {
        // vault was added in setUp
        assertTrue(depositor.isVaultWhitelisted(address(vault)));

        // vault2 was not added
        assertFalse(depositor.isVaultWhitelisted(address(vault2)));

        // After adding vault2
        vm.prank(owner);
        depositor.addVault(address(vault2));
        assertTrue(depositor.isVaultWhitelisted(address(vault2)));

        // After removing vault
        vm.prank(owner);
        depositor.removeVault(address(vault));
        assertFalse(depositor.isVaultWhitelisted(address(vault)));
    }

    /// @notice getVaultList returns the correct list after adds and removes.
    function test_getVaultList() public {
        // Initially only vault is in the list (added in setUp)
        address[] memory list = depositor.getVaultList();
        assertEq(list.length, 1);
        assertEq(list[0], address(vault));

        // Add vault2
        vm.prank(owner);
        depositor.addVault(address(vault2));

        list = depositor.getVaultList();
        assertEq(list.length, 2);
        assertEq(list[0], address(vault));
        assertEq(list[1], address(vault2));

        // Remove vault (swap-and-pop: vault2 moves to index 0)
        vm.prank(owner);
        depositor.removeVault(address(vault));

        list = depositor.getVaultList();
        assertEq(list.length, 1);
        assertEq(list[0], address(vault2));
    }

    // =========================================================================
    //                          Edge Case Tests
    // =========================================================================

    /// @notice Add 3 vaults, remove the middle one, and verify list integrity
    ///         via the swap-and-pop mechanism.
    function test_removeVault_SwapAndPop() public {
        // vault is already added in setUp at index 0
        // Add vault2 and vault3
        vm.startPrank(owner);
        depositor.addVault(address(vault2));
        depositor.addVault(address(vault3));
        vm.stopPrank();

        // Verify initial list: [vault, vault2, vault3]
        address[] memory list = depositor.getVaultList();
        assertEq(list.length, 3);
        assertEq(list[0], address(vault));
        assertEq(list[1], address(vault2));
        assertEq(list[2], address(vault3));

        // Remove the middle vault (vault2)
        // Swap-and-pop should move vault3 to index 1
        vm.prank(owner);
        depositor.removeVault(address(vault2));

        // Verify resulting list: [vault, vault3]
        list = depositor.getVaultList();
        assertEq(list.length, 2);
        assertEq(list[0], address(vault));
        assertEq(list[1], address(vault3));

        // Verify whitelist states
        assertTrue(depositor.isVaultWhitelisted(address(vault)));
        assertFalse(depositor.isVaultWhitelisted(address(vault2)));
        assertTrue(depositor.isVaultWhitelisted(address(vault3)));
    }

    /// @notice Full deposit-then-withdraw lifecycle: user ends with balance minus fee
    ///         and zero tracked shares.
    function test_depositAndWithdrawFullCycle() public {
        uint256 balanceBefore = token.balanceOf(alice);

        // Deposit
        vm.prank(alice);
        depositor.depositToVault(address(vault), DEPOSIT_AMOUNT);

        // Verify intermediate state
        uint256 shares = depositor.getUserShares(alice, address(vault));
        assertGt(shares, 0);
        assertEq(token.balanceOf(alice), balanceBefore - DEPOSIT_AMOUNT);

        // Withdraw all
        vm.prank(alice);
        depositor.withdrawFromVault(address(vault), shares);

        // Shares zeroed out
        assertEq(depositor.getUserShares(alice, address(vault)), 0);

        // Balance restored minus fee
        uint256 fee = (DEPOSIT_AMOUNT * DEFAULT_FEE_BPS) / BPS_DENOMINATOR;
        assertEq(token.balanceOf(alice), balanceBefore - fee);
        assertEq(token.balanceOf(feeRecipient), fee);
    }

    // =========================================================================
    //                          Fee Management Tests
    // =========================================================================

    /// @notice Constructor sets default fee to 0.5% (50 bps).
    function test_constructor_DefaultFee() public view {
        assertEq(depositor.feeBps(), DEFAULT_FEE_BPS);
        assertEq(depositor.feeRecipient(), feeRecipient);
    }

    /// @notice Constructor reverts if fee recipient is zero address.
    function test_constructor_RevertZeroFeeRecipient() public {
        vm.expectRevert(MorphoVaultDepositor.ZeroAddress.selector);
        new MorphoVaultDepositor(owner, address(0));
    }

    /// @notice Owner can set the fee to a new value.
    function test_setFeeBps_Success() public {
        vm.prank(owner);
        depositor.setFeeBps(100); // 1%

        assertEq(depositor.feeBps(), 100);
    }

    /// @notice Owner can set fee to zero (no fee).
    function test_setFeeBps_Zero() public {
        vm.prank(owner);
        depositor.setFeeBps(0);

        assertEq(depositor.feeBps(), 0);

        // Deposit and withdraw with no fee
        vm.prank(alice);
        depositor.depositToVault(address(vault), DEPOSIT_AMOUNT);

        uint256 shares = depositor.getUserShares(alice, address(vault));

        vm.prank(alice);
        depositor.withdrawFromVault(address(vault), shares);

        // Full amount returned, no fee taken
        assertEq(token.balanceOf(alice), INITIAL_BALANCE);
        assertEq(token.balanceOf(feeRecipient), 0);
    }

    /// @notice Cannot set fee above MAX_FEE_BPS (10%).
    function test_setFeeBps_RevertFeeTooHigh() public {
        vm.prank(owner);
        vm.expectRevert(MorphoVaultDepositor.FeeTooHigh.selector);
        depositor.setFeeBps(1_001); // > 10%
    }

    /// @notice Non-owner cannot set fee.
    function test_setFeeBps_RevertNotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        depositor.setFeeBps(100);
    }

    /// @notice Setting fee emits FeeUpdated event.
    function test_setFeeBps_EmitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(false, false, false, true, address(depositor));
        emit FeeUpdated(DEFAULT_FEE_BPS, 200);
        depositor.setFeeBps(200);
    }

    /// @notice Owner can update the fee recipient.
    function test_setFeeRecipient_Success() public {
        address newRecipient = makeAddr("newRecipient");

        vm.prank(owner);
        depositor.setFeeRecipient(newRecipient);

        assertEq(depositor.feeRecipient(), newRecipient);
    }

    /// @notice Cannot set fee recipient to zero address.
    function test_setFeeRecipient_RevertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(MorphoVaultDepositor.ZeroAddress.selector);
        depositor.setFeeRecipient(address(0));
    }

    /// @notice Non-owner cannot set fee recipient.
    function test_setFeeRecipient_RevertNotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        depositor.setFeeRecipient(makeAddr("someone"));
    }

    /// @notice Setting fee recipient emits FeeRecipientUpdated event.
    function test_setFeeRecipient_EmitsEvent() public {
        address newRecipient = makeAddr("newRecipient");

        vm.prank(owner);
        vm.expectEmit(true, true, false, false, address(depositor));
        emit FeeRecipientUpdated(feeRecipient, newRecipient);
        depositor.setFeeRecipient(newRecipient);
    }

    /// @notice Withdrawal with custom fee: set to 2%, verify correct fee deduction.
    function test_withdrawFromVault_CustomFee() public {
        // Set fee to 2%
        vm.prank(owner);
        depositor.setFeeBps(200);

        vm.prank(alice);
        depositor.depositToVault(address(vault), DEPOSIT_AMOUNT);

        uint256 shares = depositor.getUserShares(alice, address(vault));

        vm.prank(alice);
        depositor.withdrawFromVault(address(vault), shares);

        // 2% of 1000e18 = 20e18
        uint256 fee = (DEPOSIT_AMOUNT * 200) / BPS_DENOMINATOR;
        assertEq(fee, 20e18);
        assertEq(token.balanceOf(feeRecipient), fee);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - fee);
    }

    /// @notice Withdrawal emits FeeCollected event when fee > 0.
    function test_withdrawFromVault_EmitsFeeCollected() public {
        vm.prank(alice);
        depositor.depositToVault(address(vault), DEPOSIT_AMOUNT);

        uint256 shares = depositor.getUserShares(alice, address(vault));
        uint256 fee = (DEPOSIT_AMOUNT * DEFAULT_FEE_BPS) / BPS_DENOMINATOR;

        vm.prank(alice);
        vm.expectEmit(true, true, false, true, address(depositor));
        emit FeeCollected(address(vault), address(token), fee);
        depositor.withdrawFromVault(address(vault), shares);
    }

    /// @notice Fee recipient change takes effect on next withdrawal.
    function test_feeGoesToUpdatedRecipient() public {
        address newRecipient = makeAddr("treasury");

        vm.prank(alice);
        depositor.depositToVault(address(vault), DEPOSIT_AMOUNT);

        // Change fee recipient before withdrawal
        vm.prank(owner);
        depositor.setFeeRecipient(newRecipient);

        uint256 shares = depositor.getUserShares(alice, address(vault));

        vm.prank(alice);
        depositor.withdrawFromVault(address(vault), shares);

        uint256 fee = (DEPOSIT_AMOUNT * DEFAULT_FEE_BPS) / BPS_DENOMINATOR;
        assertEq(token.balanceOf(newRecipient), fee);
        assertEq(token.balanceOf(feeRecipient), 0); // old recipient gets nothing
    }
}
