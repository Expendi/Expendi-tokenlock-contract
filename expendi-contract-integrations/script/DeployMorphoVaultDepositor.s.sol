// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MorphoVaultDepositor} from "../src/MorphoVaultDepositor.sol";

/**
 * @title DeployMorphoVaultDepositor
 * @notice Deploys the MorphoVaultDepositor contract.
 *
 * Usage:
 *   forge script script/DeployMorphoVaultDepositor.s.sol:DeployMorphoVaultDepositor \
 *     --rpc-url $RPC_URL \
 *     --broadcast \
 *     --verify \
 *     --etherscan-api-key $ETHERSCAN_API_KEY \
 *     -vvvv
 *
 * Environment variables:
 *   DEPLOYER_PRIVATE_KEY  - Private key of the deployer account.
 *   DEPOSITOR_OWNER       - Address that will own the contract. Defaults to deployer.
 *   FEE_RECIPIENT         - Address that receives withdrawal fees. Required.
 */
contract DeployMorphoVaultDepositor is Script {
    function run() external returns (MorphoVaultDepositor depositor) {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address owner = vm.envOr("DEPOSITOR_OWNER", deployer);
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");

        console.log("Deployer:", deployer);
        console.log("MorphoVaultDepositor owner:", owner);
        console.log("Fee recipient:", feeRecipient);

        vm.startBroadcast(deployerKey);

        depositor = new MorphoVaultDepositor(owner, feeRecipient);

        vm.stopBroadcast();

        console.log("MorphoVaultDepositor deployed at:", address(depositor));
        console.log("Default fee: 0.5% (50 bps)");
    }
}
