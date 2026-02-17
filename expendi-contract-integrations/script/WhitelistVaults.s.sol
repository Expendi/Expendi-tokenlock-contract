// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {YieldTimeLock} from "../src/YieldTimeLock.sol";

/**
 * @title WhitelistVaults
 * @notice Whitelists Morpho USDC vaults on Base for YieldTimeLock.
 *
 * Usage:
 *   forge script script/WhitelistVaults.s.sol:WhitelistVaults \
 *     --rpc-url $BASE_RPC_URL \
 *     --broadcast \
 *     -vvvv
 *
 * Environment variables:
 *   OWNER_PRIVATE_KEY      - Private key of the YieldTimeLock owner.
 *   YIELD_TIMELOCK_ADDRESS - Deployed YieldTimeLock contract address.
 */
contract WhitelistVaults is Script {
    address constant GAUNTLET_USDC_PRIME = 0x050cE30b927Da55177A4914EC73480238BAD56f0;
    address constant STEAKHOUSE_PRIME_INSTANT = 0xbeef0e0834849aCC03f0089F01f4F1Eeb06873C9;
    address constant STEAKHOUSE_HIGH_YIELD = 0xbeeff7aE5E00Aae3Db302e4B0d8C883810a58100;

    function run() external {
        uint256 ownerKey = vm.envUint("OWNER_PRIVATE_KEY");
        address yieldTimeLockAddr = vm.envAddress("YIELD_TIMELOCK_ADDRESS");

        YieldTimeLock yieldTimeLock = YieldTimeLock(yieldTimeLockAddr);

        address[] memory vaults = new address[](3);
        vaults[0] = GAUNTLET_USDC_PRIME;
        vaults[1] = STEAKHOUSE_PRIME_INSTANT;
        vaults[2] = STEAKHOUSE_HIGH_YIELD;

        string[3] memory names = ["Gauntlet USDC Prime", "Steakhouse Prime Instant", "Steakhouse High Yield"];

        console.log("YieldTimeLock:", yieldTimeLockAddr);
        console.log("Whitelisting 3 Morpho USDC vaults on Base...");

        vm.startBroadcast(ownerKey);

        for (uint256 i = 0; i < vaults.length; i++) {
            if (!yieldTimeLock.isVaultWhitelisted(vaults[i])) {
                yieldTimeLock.addVault(vaults[i]);
                console.log("Added:", names[i], vaults[i]);
            } else {
                console.log("Already whitelisted:", names[i], vaults[i]);
            }
        }

        vm.stopBroadcast();

        console.log("Done. Whitelisted vaults:", yieldTimeLock.getVaultList().length);
    }
}
