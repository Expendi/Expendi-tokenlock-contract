# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
forge build           # Compile contracts
forge test            # Run all tests
forge test --mt <fn>  # Run single test by function name
forge test -vvvv      # Run tests with max verbosity
forge fmt             # Format Solidity code
forge snapshot        # Generate gas snapshots
```

## Deployment

```bash
# Deploy all contracts
forge script script/DeployAll.s.sol:DeployAll \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY

# Required env vars: DEPLOYER_PRIVATE_KEY, FEE_RECIPIENT
# Optional: TIMELOCK_OWNER, DEPOSITOR_OWNER (default to deployer)
```

## Architecture

This is a Foundry-based Solidity project for the Expendi platform. Compiler: Solidity 0.8.20.

### Core Contracts

**TimeLock** (`src/TimeLock.sol`)
- Non-yield-bearing escrow for ETH and ERC-20 tokens
- Users lock funds until a specified unlock timestamp
- Only depositors can withdraw; owner can only extend lock periods (not shorten or withdraw)
- Uses lock IDs with internal mapping for per-user lock tracking

**MorphoVaultDepositor** (`src/MorphoVaultDepositor.sol`)
- Intermediary custodian for Morpho MetaMorpho (ERC-4626) vaults on Ethereum mainnet
- Holds vault shares on behalf of users with internal share accounting (`userShares[user][vault]`)
- Owner-controlled vault whitelist restricts which vaults can be used
- Uses `forceApprove` for USDT-style tokens requiring zero-allowance reset

### Key Patterns

- Both contracts inherit `Ownable` and `ReentrancyGuard` from OpenZeppelin
- Checks-effects-interactions pattern: state updated before external calls
- SafeERC20 for all token operations
- Custom errors instead of require strings

### Remappings

```
@openzeppelin/ -> lib/openzeppelin-contracts/
forge-std/ -> lib/forge-std/src/
```
