// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title IERC4626
 * @notice Standard ERC-4626 Tokenized Vault interface.
 * @dev Defines the interface for ERC-4626 vaults, which provide a standard API
 *      for tokenized yield-bearing vaults that represent shares of a single
 *      underlying ERC-20 token. Used here to interact with Morpho MetaMorpho vaults.
 */
interface IERC4626 {
    // =========================================================================
    //                          Deposit / Mint
    // =========================================================================

    /**
     * @notice Deposits `assets` of the underlying token and mints vault shares
     *         to `receiver`.
     * @param assets The amount of underlying tokens to deposit.
     * @param receiver The address that will receive the minted shares.
     * @return shares The amount of vault shares minted to `receiver`.
     */
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    /**
     * @notice Mints exactly `shares` vault shares to `receiver` by depositing
     *         the required amount of underlying tokens.
     * @param shares The exact number of vault shares to mint.
     * @param receiver The address that will receive the minted shares.
     * @return assets The amount of underlying tokens deposited.
     */
    function mint(uint256 shares, address receiver) external returns (uint256 assets);

    // =========================================================================
    //                          Withdraw / Redeem
    // =========================================================================

    /**
     * @notice Burns shares from `owner` and sends exactly `assets` underlying
     *         tokens to `receiver`.
     * @param assets The amount of underlying tokens to withdraw.
     * @param receiver The address that will receive the underlying tokens.
     * @param owner The address whose shares will be burned.
     * @return shares The amount of vault shares burned.
     */
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);

    /**
     * @notice Redeems `shares` from `owner` and sends the corresponding amount
     *         of underlying tokens to `receiver`.
     * @param shares The amount of vault shares to redeem.
     * @param receiver The address that will receive the underlying tokens.
     * @param owner The address whose shares will be burned.
     * @return assets The amount of underlying tokens sent to `receiver`.
     */
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);

    // =========================================================================
    //                          Accounting View Functions
    // =========================================================================

    /**
     * @notice Returns the total amount of the underlying asset managed by the vault.
     * @return totalManagedAssets The total amount of underlying assets.
     */
    function totalAssets() external view returns (uint256 totalManagedAssets);

    /**
     * @notice Converts a given amount of assets to the equivalent amount of shares.
     * @param assets The amount of underlying tokens to convert.
     * @return shares The equivalent amount of vault shares.
     */
    function convertToShares(uint256 assets) external view returns (uint256 shares);

    /**
     * @notice Converts a given amount of shares to the equivalent amount of assets.
     * @param shares The amount of vault shares to convert.
     * @return assets The equivalent amount of underlying tokens.
     */
    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    // =========================================================================
    //                          Max Capacity View Functions
    // =========================================================================

    /**
     * @notice Returns the maximum amount of underlying tokens that can be
     *         deposited for `receiver`.
     * @param receiver The address that would receive the shares.
     * @return maxAssets The maximum depositable amount.
     */
    function maxDeposit(address receiver) external view returns (uint256 maxAssets);

    /**
     * @notice Returns the maximum amount of shares that can be minted for `receiver`.
     * @param receiver The address that would receive the shares.
     * @return maxShares The maximum mintable shares.
     */
    function maxMint(address receiver) external view returns (uint256 maxShares);

    /**
     * @notice Returns the maximum amount of underlying tokens that `owner`
     *         can withdraw.
     * @param owner The address whose withdrawal limit is queried.
     * @return maxAssets The maximum withdrawable amount.
     */
    function maxWithdraw(address owner) external view returns (uint256 maxAssets);

    /**
     * @notice Returns the maximum amount of shares that `owner` can redeem.
     * @param owner The address whose redeem limit is queried.
     * @return maxShares The maximum redeemable shares.
     */
    function maxRedeem(address owner) external view returns (uint256 maxShares);

    // =========================================================================
    //                          Preview View Functions
    // =========================================================================

    /**
     * @notice Simulates the amount of shares that would be minted for a given
     *         deposit amount.
     * @param assets The amount of underlying tokens to simulate depositing.
     * @return shares The estimated shares that would be minted.
     */
    function previewDeposit(uint256 assets) external view returns (uint256 shares);

    /**
     * @notice Simulates the amount of assets required to mint a given amount
     *         of shares.
     * @param shares The amount of shares to simulate minting.
     * @return assets The estimated underlying tokens required.
     */
    function previewMint(uint256 shares) external view returns (uint256 assets);

    /**
     * @notice Simulates the amount of shares that would be burned for a given
     *         withdrawal amount.
     * @param assets The amount of underlying tokens to simulate withdrawing.
     * @return shares The estimated shares that would be burned.
     */
    function previewWithdraw(uint256 assets) external view returns (uint256 shares);

    /**
     * @notice Simulates the amount of assets that would be returned for a given
     *         redemption amount.
     * @param shares The amount of shares to simulate redeeming.
     * @return assets The estimated underlying tokens that would be returned.
     */
    function previewRedeem(uint256 shares) external view returns (uint256 assets);

    // =========================================================================
    //                          Asset Info
    // =========================================================================

    /**
     * @notice Returns the address of the underlying ERC-20 token used by the vault.
     * @return assetTokenAddress The address of the underlying token.
     */
    function asset() external view returns (address assetTokenAddress);
}
