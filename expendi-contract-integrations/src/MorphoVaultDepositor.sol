// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IMorphoVault} from "./interfaces/IMorphoVault.sol";

/**
 * @title MorphoVaultDepositor
 * @notice Facilitates depositing ERC-20 tokens into Morpho MetaMorpho ERC-4626
 *         vaults and tracks per-user share balances. Only owner-whitelisted
 *         vaults can be used for deposits.
 * @dev This contract acts as an intermediary: it holds the vault shares on behalf
 *      of users and maintains an internal accounting ledger (`userShares`).
 *      When a user withdraws, the contract redeems the corresponding shares
 *      from the vault and forwards the underlying assets back to the user.
 */
contract MorphoVaultDepositor is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =========================================================================
    //                                State
    // =========================================================================

    /// @notice Basis points denominator (100% = 10_000 bps).
    uint256 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Maximum fee in basis points (10%).
    uint256 public constant MAX_FEE_BPS = 1_000;

    /// @notice Default fee: 0.5% = 50 bps.
    uint256 public constant DEFAULT_FEE_BPS = 50;

    /// @notice Whether a vault address is whitelisted for deposits.
    mapping(address => bool) public whitelistedVaults;

    /// @notice Tracks shares held per user per vault: user => vault => shares.
    mapping(address => mapping(address => uint256)) public userShares;

    /// @notice Array of all vaults that have ever been whitelisted (for enumeration).
    address[] public vaultList;

    /// @notice Withdrawal fee in basis points (1 bp = 0.01%).
    uint256 public feeBps;

    /// @notice Address that receives the withdrawal fees.
    address public feeRecipient;

    // =========================================================================
    //                               Events
    // =========================================================================

    /**
     * @notice Emitted when a user deposits assets into a Morpho vault.
     * @param user   The address that initiated the deposit.
     * @param vault  The Morpho vault that received the deposit.
     * @param assets The amount of underlying tokens deposited.
     * @param shares The amount of vault shares received.
     */
    event Deposited(address indexed user, address indexed vault, uint256 assets, uint256 shares);

    /**
     * @notice Emitted when a user withdraws by redeeming shares from a vault.
     * @param user   The address that initiated the withdrawal.
     * @param vault  The Morpho vault from which shares were redeemed.
     * @param shares The amount of vault shares redeemed.
     * @param assets The amount of underlying tokens returned to the user.
     */
    event WithdrawnFromVault(address indexed user, address indexed vault, uint256 shares, uint256 assets);

    /**
     * @notice Emitted when a vault is added to the whitelist.
     * @param vault The vault address that was whitelisted.
     */
    event VaultAdded(address indexed vault);

    /**
     * @notice Emitted when a vault is removed from the whitelist.
     * @param vault The vault address that was removed.
     */
    event VaultRemoved(address indexed vault);

    /**
     * @notice Emitted when the withdrawal fee is updated.
     * @param oldFeeBps The previous fee in basis points.
     * @param newFeeBps The new fee in basis points.
     */
    event FeeUpdated(uint256 oldFeeBps, uint256 newFeeBps);

    /**
     * @notice Emitted when the fee recipient is updated.
     * @param oldRecipient The previous fee recipient.
     * @param newRecipient The new fee recipient.
     */
    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);

    /**
     * @notice Emitted when fees are collected during a withdrawal.
     * @param vault  The vault the withdrawal was from.
     * @param token  The underlying asset token.
     * @param amount The fee amount collected.
     */
    event FeeCollected(address indexed vault, address indexed token, uint256 amount);

    // =========================================================================
    //                               Errors
    // =========================================================================

    /// @notice Thrown when attempting to interact with a non-whitelisted vault.
    error VaultNotWhitelisted();

    /// @notice Thrown when the deposit amount is zero.
    error AmountMustBeGreaterThanZero();

    /// @notice Thrown when the shares amount is zero.
    error SharesMustBeGreaterThanZero();

    /// @notice Thrown when the user does not have enough tracked shares.
    error InsufficientShares();

    /// @notice Thrown when trying to add a vault that is already whitelisted.
    error VaultAlreadyWhitelisted();

    /// @notice Thrown when trying to remove a vault that is not whitelisted.
    error VaultNotInWhitelist();

    /// @notice Thrown when a zero address is provided where a valid address is required.
    error ZeroAddress();

    /// @notice Thrown when the fee exceeds the maximum allowed.
    error FeeTooHigh();

    // =========================================================================
    //                            Constructor
    // =========================================================================

    /**
     * @notice Deploys the MorphoVaultDepositor and sets the initial owner.
     * @param initialOwner The address that will be the contract owner.
     * @param _feeRecipient The address that will receive withdrawal fees.
     */
    constructor(address initialOwner, address _feeRecipient) Ownable(initialOwner) {
        if (_feeRecipient == address(0)) revert ZeroAddress();
        feeRecipient = _feeRecipient;
        feeBps = DEFAULT_FEE_BPS;
    }

    // =========================================================================
    //                        External Functions
    // =========================================================================

    /**
     * @notice Deposits `amount` of the vault's underlying asset into a
     *         whitelisted Morpho vault. The resulting shares are tracked
     *         internally for the caller.
     * @dev The caller must have approved this contract to spend at least `amount`
     *      of the vault's underlying asset before calling.
     * @param vault  The address of the whitelisted Morpho vault.
     * @param amount The amount of the underlying asset to deposit.
     */
    function depositToVault(address vault, uint256 amount) external nonReentrant {
        if (!whitelistedVaults[vault]) revert VaultNotWhitelisted();
        if (amount == 0) revert AmountMustBeGreaterThanZero();

        // Retrieve the underlying asset of the vault.
        address asset = IMorphoVault(vault).asset();

        // Transfer the underlying tokens from the caller to this contract.
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        // Approve the vault to pull the tokens from this contract.
        IERC20(asset).forceApprove(address(vault), amount);

        // Deposit into the ERC-4626 vault; this contract receives the shares.
        uint256 sharesReceived = IMorphoVault(vault).deposit(amount, address(this));

        // Track shares for the user.
        userShares[msg.sender][vault] += sharesReceived;

        emit Deposited(msg.sender, vault, amount, sharesReceived);
    }

    /**
     * @notice Redeems `shares` from a Morpho vault, takes a withdrawal fee,
     *         and sends the remaining underlying assets back to the caller.
     * @dev The caller must have at least `shares` tracked in `userShares`.
     *      The fee is taken from the redeemed assets and sent to `feeRecipient`.
     * @param vault  The address of the Morpho vault to redeem from.
     * @param shares The number of vault shares to redeem.
     */
    function withdrawFromVault(address vault, uint256 shares) external nonReentrant {
        if (!whitelistedVaults[vault]) revert VaultNotWhitelisted();
        if (shares == 0) revert SharesMustBeGreaterThanZero();
        if (userShares[msg.sender][vault] < shares) revert InsufficientShares();

        // Deduct the shares from the user's tracked balance first (checks-effects-interactions).
        userShares[msg.sender][vault] -= shares;

        // Redeem shares from the vault; underlying assets are sent to this contract.
        uint256 assetsReceived = IMorphoVault(vault).redeem(shares, address(this), address(this));

        // Calculate and deduct fee.
        uint256 fee = (assetsReceived * feeBps) / BPS_DENOMINATOR;
        uint256 assetsAfterFee = assetsReceived - fee;

        // Transfer fee to fee recipient and remaining assets to the user.
        address asset = IMorphoVault(vault).asset();
        if (fee > 0) {
            IERC20(asset).safeTransfer(feeRecipient, fee);
            emit FeeCollected(vault, asset, fee);
        }
        IERC20(asset).safeTransfer(msg.sender, assetsAfterFee);

        emit WithdrawnFromVault(msg.sender, vault, shares, assetsAfterFee);
    }

    // =========================================================================
    //                     Owner-Only Vault Management
    // =========================================================================

    /**
     * @notice Adds a vault to the whitelist. Only the owner can call this.
     * @param vault The address of the Morpho vault to whitelist.
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
     * @dev This does not affect existing user shares in the removed vault.
     *      Users will not be able to deposit or withdraw until the vault is
     *      re-added.
     * @param vault The address of the Morpho vault to remove.
     */
    function removeVault(address vault) external onlyOwner {
        if (!whitelistedVaults[vault]) revert VaultNotInWhitelist();

        whitelistedVaults[vault] = false;

        // Remove from the vaultList array by swapping with the last element.
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
     * @notice Returns the number of tracked shares a user has in a given vault.
     * @param user  The user address.
     * @param vault The vault address.
     * @return shares The number of shares tracked for the user.
     */
    function getUserShares(address user, address vault) external view returns (uint256 shares) {
        shares = userShares[user][vault];
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
}
