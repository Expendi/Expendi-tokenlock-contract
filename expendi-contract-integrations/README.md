# Expendi Contract Integrations

Smart contracts for time-locked yield-generating deposits using ERC-4626 vaults.

## Contracts

| Contract | Description |
|----------|-------------|
| **YieldTimeLock** | Time-locked deposits into Morpho ERC-4626 vaults with yield generation |
| **TimeLock** | Non-yield-bearing escrow for ETH and ERC-20 tokens |
| **MorphoVaultDepositor** | Intermediary custodian for Morpho MetaMorpho vaults |

## Deployments

### YieldTimeLock (v2 - Current)

| Network | Address | Explorer |
|---------|---------|----------|
| Base Mainnet | `0x3da4E8d093051603519aCE4E3472C7c5d5Cf56d6` | [basescan.org](https://basescan.org/address/0x3da4E8d093051603519aCE4E3472C7c5d5Cf56d6) |
| Base Sepolia | `0xeA70131274f6a69c7175be61Cef4fcFaF30579e9` | [sepolia.basescan.org](https://sepolia.basescan.org/address/0xeA70131274f6a69c7175be61Cef4fcFaF30579e9) |

### YieldTimeLock (v1 - Deprecated)

| Network | Address | Explorer |
|---------|---------|----------|
| Base Mainnet | `0x3e6305dBC35f4782fc5267dfa0c202aFB441DC74` | [basescan.org](https://basescan.org/address/0x3e6305dBC35f4782fc5267dfa0c202aFB441DC74) |
| Base Sepolia | `0x3da4E8d093051603519aCE4E3472C7c5d5Cf56d6` | [sepolia.basescan.org](https://sepolia.basescan.org/address/0x3da4E8d093051603519aCE4E3472C7c5d5Cf56d6) |

> **Note:** v1 contracts remain active for existing locks. New deposits should use v2.

**Configuration:**
- Owner: `0xAE609c3904C539aF2Ac11a86D0B030a77dB0a509`
- Fee Recipient: `0x27e5Cf811c4294211367C69a8C305bcB9A79fEbA`
- Default Fee: 0.5% (50 bps)

## Build & Test

```bash
forge build           # Compile contracts
forge test            # Run all tests
forge test --mt <fn>  # Run single test by function name
forge test -vvvv      # Run tests with max verbosity
forge fmt             # Format Solidity code
```

## Deployment

```bash
# 1. Set up environment
cp .env.example .env
# Edit .env with: DEPLOYER_PRIVATE_KEY, FEE_RECIPIENT, BASESCAN_API_KEY

# 2. Source environment
source .env

# 3. Deploy to Base Sepolia (testnet)
forge script script/DeployYieldTimeLock.s.sol:DeployYieldTimeLock \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --broadcast \
  -vvvv

# 4. Deploy to Base Mainnet
forge script script/DeployYieldTimeLock.s.sol:DeployYieldTimeLock \
  --rpc-url $BASE_MAINNET_RPC_URL \
  --broadcast \
  -vvvv
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `DEPLOYER_PRIVATE_KEY` | Private key for deployer account |
| `FEE_RECIPIENT` | Address to receive withdrawal fees |
| `YIELD_TIMELOCK_OWNER` | Contract owner (optional, defaults to deployer) |
| `BASE_MAINNET_RPC_URL` | `https://mainnet.base.org` |
| `BASE_SEPOLIA_RPC_URL` | `https://sepolia.base.org` |
| `BASESCAN_API_KEY` | API key from [basescan.org](https://basescan.org/myapikey) |

## Post-Deployment

After deploying YieldTimeLock, whitelist vaults for deposits:

```bash
cast send $YIELD_TIMELOCK_ADDRESS "addVault(address)" $VAULT_ADDRESS \
  --rpc-url $BASE_MAINNET_RPC_URL \
  --private-key $DEPLOYER_PRIVATE_KEY
```

## License

MIT
