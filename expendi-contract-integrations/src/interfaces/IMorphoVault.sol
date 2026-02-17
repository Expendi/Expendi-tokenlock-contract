// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC4626} from "./IERC4626.sol";

/**
 * @title IMorphoVault
 * @notice Interface for Morpho MetaMorpho vaults on Ethereum.
 * @dev MetaMorpho vaults are ERC-4626 compliant and also implement the full
 *      ERC-20 interface for the vault share token. This interface extends
 *      IERC4626 with the ERC-20 functions needed for share token management.
 */
interface IMorphoVault is IERC4626 {
    // =========================================================================
    //                          ERC-20 View Functions
    // =========================================================================

    /**
     * @notice Returns the share token balance of `account`.
     * @param account The address to query.
     * @return balance The number of vault shares held by `account`.
     */
    function balanceOf(address account) external view returns (uint256 balance);

    /**
     * @notice Returns the remaining number of shares that `spender` is allowed
     *         to transfer on behalf of `owner`.
     * @param owner The address that owns the shares.
     * @param spender The address approved to spend the shares.
     * @return remaining The remaining allowance.
     */
    function allowance(address owner, address spender) external view returns (uint256 remaining);

    // =========================================================================
    //                          ERC-20 State-Changing Functions
    // =========================================================================

    /**
     * @notice Approves `spender` to transfer up to `amount` shares on behalf
     *         of the caller.
     * @param spender The address being approved to spend shares.
     * @param amount The maximum number of shares `spender` can transfer.
     * @return success True if the approval succeeded.
     */
    function approve(address spender, uint256 amount) external returns (bool success);

    /**
     * @notice Transfers `amount` vault shares from the caller to `to`.
     * @param to The recipient address.
     * @param amount The number of shares to transfer.
     * @return success True if the transfer succeeded.
     */
    function transfer(address to, uint256 amount) external returns (bool success);

    /**
     * @notice Transfers `amount` vault shares from `from` to `to`, using the
     *         caller's allowance.
     * @param from The address to transfer shares from.
     * @param to The address to transfer shares to.
     * @param amount The number of shares to transfer.
     * @return success True if the transfer succeeded.
     */
    function transferFrom(address from, address to, uint256 amount) external returns (bool success);
}
