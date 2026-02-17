// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {YieldTimeLock} from "../src/YieldTimeLock.sol";

/**
 * @title DeployYieldTimeLock
 * @notice Deploys the YieldTimeLock contract.
 *
 * Usage:
 *   forge script script/DeployYieldTimeLock.s.sol:DeployYieldTimeLock \
 *     --rpc-url $RPC_URL \
 *     --broadcast \
 *     --verify \
 *     --etherscan-api-key $ETHERSCAN_API_KEY \
 *     -vvvv
 *
 * Environment variables:
 *   DEPLOYER_PRIVATE_KEY   - Private key of the deployer account.
 *   YIELD_TIMELOCK_OWNER   - Address that will own the contract. Defaults to deployer.
 *   FEE_RECIPIENT          - Address that receives withdrawal fees. Required.
 */
contract DeployYieldTimeLock is Script {
    function run() external returns (YieldTimeLock yieldTimeLock) {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address owner = vm.envOr("YIELD_TIMELOCK_OWNER", deployer);
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");

        console.log("Deployer:", deployer);
        console.log("YieldTimeLock owner:", owner);
        console.log("Fee recipient:", feeRecipient);

        vm.startBroadcast(deployerKey);

        yieldTimeLock = new YieldTimeLock(owner, feeRecipient);

        vm.stopBroadcast();

        console.log("YieldTimeLock deployed at:", address(yieldTimeLock));
        console.log("Default fee: 0.5% (50 bps)");
    }
}
