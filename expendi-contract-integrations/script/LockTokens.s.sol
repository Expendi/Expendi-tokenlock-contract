// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {YieldTimeLock} from "../src/YieldTimeLock.sol";

/**
 * @title LockTokens
 * @notice Locks USDC into a Morpho vault via YieldTimeLock.
 *
 * Usage:
 *   forge script script/LockTokens.s.sol:LockTokens \
 *     --rpc-url $BASE_MAINNET_RPC_URL \
 *     --broadcast \
 *     -vvvv
 */
contract LockTokens is Script {
    address constant YIELD_TIMELOCK = 0x3e6305dBC35f4782fc5267dfa0c202aFB441DC74;
    address constant GAUNTLET_USDC_PRIME = 0x050cE30b927Da55177A4914EC73480238BAD56f0;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    uint256 constant AMOUNT = 1e6; // 1 USDC (6 decimals)
    uint256 constant LOCK_DURATION = 7 days;
    string constant LABEL = "zanzalu";

    function run() external {
        uint256 privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address depositor = vm.addr(privateKey);

        uint256 unlockTime = block.timestamp + LOCK_DURATION;

        console.log("Depositor:", depositor);
        console.log("Vault:", GAUNTLET_USDC_PRIME);
        console.log("Amount:", AMOUNT, "USDC (1 dollar)");
        console.log("Unlock time:", unlockTime);
        console.log("Label:", LABEL);

        uint256 balance = IERC20(USDC).balanceOf(depositor);
        console.log("USDC balance:", balance);
        require(balance >= AMOUNT, "Insufficient USDC balance");

        vm.startBroadcast(privateKey);

        IERC20(USDC).approve(YIELD_TIMELOCK, AMOUNT);
        console.log("Approved YieldTimeLock to spend USDC");

        uint256 lockId = YieldTimeLock(YIELD_TIMELOCK).lockWithYield(
            GAUNTLET_USDC_PRIME,
            AMOUNT,
            unlockTime,
            LABEL
        );

        vm.stopBroadcast();

        console.log("Lock created with ID:", lockId);
    }
}
