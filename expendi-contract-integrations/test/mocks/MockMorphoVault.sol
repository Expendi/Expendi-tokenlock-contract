// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MockERC20} from "./MockERC20.sol";

/**
 * @title MockMorphoVault
 * @notice A minimal ERC4626-compliant vault mock for testing MorphoVaultDepositor.
 * @dev Implements the IMorphoVault interface (ERC20 + ERC4626) manually because
 *      the OpenZeppelin ERC4626 extension requires Solidity ^0.8.24 while this
 *      project is pinned to 0.8.20. Uses a simple 1:1 share-to-asset ratio.
 */
contract MockMorphoVault is ERC20 {
    using SafeERC20 for IERC20;
    using Math for uint256;

    IERC20 private immutable _asset;

    constructor(address underlyingAsset) ERC20("Mock Vault Shares", "mvSHARE") {
        _asset = IERC20(underlyingAsset);
    }

    // =========================================================================
    //                     Test Helper: Yield Simulation
    // =========================================================================

    function simulateYield(uint256 yieldAmount) external {
        MockERC20(address(_asset)).mint(address(this), yieldAmount);
    }

    function simulateLoss(uint256 lossAmount) external {
        IERC20(_asset).safeTransfer(address(1), lossAmount);
    }

    // =========================================================================
    //                          ERC-4626 Functions
    // =========================================================================

    function asset() external view returns (address) {
        return address(_asset);
    }

    function totalAssets() public view returns (uint256) {
        return _asset.balanceOf(address(this));
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return assets;
        return assets.mulDiv(supply, totalAssets(), Math.Rounding.Floor);
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return shares;
        return shares.mulDiv(totalAssets(), supply, Math.Rounding.Floor);
    }

    function maxDeposit(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) external view returns (uint256) {
        return convertToAssets(balanceOf(owner));
    }

    function maxRedeem(address owner) external view returns (uint256) {
        return balanceOf(owner);
    }

    function previewDeposit(uint256 assets) public view returns (uint256) {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return shares;
        return shares.mulDiv(totalAssets(), supply, Math.Rounding.Ceil);
    }

    function previewWithdraw(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return assets;
        return assets.mulDiv(supply, totalAssets(), Math.Rounding.Ceil);
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        return convertToAssets(shares);
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        shares = previewDeposit(assets);
        _asset.safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
    }

    function mint(uint256 shares, address receiver) external returns (uint256 assets) {
        assets = previewMint(shares);
        _asset.safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        shares = previewWithdraw(assets);
        if (msg.sender != owner) {
            uint256 allowed = allowance(owner, msg.sender);
            if (allowed != type(uint256).max) {
                require(allowed >= shares, "ERC4626: allowance exceeded");
                _approve(owner, msg.sender, allowed - shares);
            }
        }
        _burn(owner, shares);
        _asset.safeTransfer(receiver, assets);
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        assets = previewRedeem(shares);
        if (msg.sender != owner) {
            uint256 allowed = allowance(owner, msg.sender);
            if (allowed != type(uint256).max) {
                require(allowed >= shares, "ERC4626: allowance exceeded");
                _approve(owner, msg.sender, allowed - shares);
            }
        }
        _burn(owner, shares);
        _asset.safeTransfer(receiver, assets);
    }
}
