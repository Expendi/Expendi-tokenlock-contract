// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {TimeLock} from "../src/TimeLock.sol";

/**
 * @title DeployTimeLock
 * @notice Deploys the TimeLock contract.
 *
 * Usage:
 *   forge script script/DeployTimeLock.s.sol:DeployTimeLock \
 *     --rpc-url $RPC_URL \
 *     --broadcast \
 *     --verify \
 *     --etherscan-api-key $ETHERSCAN_API_KEY \
 *     -vvvv
 *
 * Environment variables:
 *   DEPLOYER_PRIVATE_KEY  - Private key of the deployer account.
 *   TIMELOCK_OWNER        - Address that will own the TimeLock contract.
 *                           Defaults to the deployer if not set.
 */
contract DeployTimeLock is Script {
    function run() external returns (TimeLock timeLock) {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address owner = vm.envOr("TIMELOCK_OWNER", deployer);

        console.log("Deployer:", deployer);
        console.log("TimeLock owner:", owner);

        vm.startBroadcast(deployerKey);

        timeLock = new TimeLock(owner);

        vm.stopBroadcast();

        console.log("TimeLock deployed at:", address(timeLock));
    }
}
