// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {TimeLock} from "../src/TimeLock.sol";
import {MorphoVaultDepositor} from "../src/MorphoVaultDepositor.sol";
import {YieldTimeLock} from "../src/YieldTimeLock.sol";

/**
 * @title DeployAll
 * @notice Deploys all Expendi contracts in a single transaction batch.
 *
 * Usage:
 *   forge script script/DeployAll.s.sol:DeployAll \
 *     --rpc-url $RPC_URL \
 *     --broadcast \
 *     --verify \
 *     --etherscan-api-key $ETHERSCAN_API_KEY \
 *     -vvvv
 *
 * Environment variables:
 *   DEPLOYER_PRIVATE_KEY   - Private key of the deployer account.
 *   TIMELOCK_OWNER         - Owner of TimeLock. Defaults to deployer.
 *   DEPOSITOR_OWNER        - Owner of MorphoVaultDepositor. Defaults to deployer.
 *   YIELD_TIMELOCK_OWNER   - Owner of YieldTimeLock. Defaults to deployer.
 *   FEE_RECIPIENT          - Address that receives withdrawal fees. Required.
 */
contract DeployAll is Script {
    function run() external returns (TimeLock timeLock, MorphoVaultDepositor depositor, YieldTimeLock yieldTimeLock) {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address timeLockOwner = vm.envOr("TIMELOCK_OWNER", deployer);
        address depositorOwner = vm.envOr("DEPOSITOR_OWNER", deployer);
        address yieldTimeLockOwner = vm.envOr("YIELD_TIMELOCK_OWNER", deployer);
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");

        console.log("=== Expendi Contract Deployment ===");
        console.log("Deployer:", deployer);
        console.log("TimeLock owner:", timeLockOwner);
        console.log("MorphoVaultDepositor owner:", depositorOwner);
        console.log("YieldTimeLock owner:", yieldTimeLockOwner);
        console.log("Fee recipient:", feeRecipient);
        console.log("");

        vm.startBroadcast(deployerKey);

        timeLock = new TimeLock(timeLockOwner);
        depositor = new MorphoVaultDepositor(depositorOwner, feeRecipient);
        yieldTimeLock = new YieldTimeLock(yieldTimeLockOwner, feeRecipient);

        vm.stopBroadcast();

        console.log("=== Deployment Complete ===");
        console.log("TimeLock:", address(timeLock));
        console.log("MorphoVaultDepositor:", address(depositor));
        console.log("YieldTimeLock:", address(yieldTimeLock));
    }
}
