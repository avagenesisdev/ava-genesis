# Security

## Smart Contracts

All Ava Genesis contracts are open source, verified, and based on OpenZeppelin 5.

### Deployed Addresses

| Network | Factory Contract | Explorer |
|---|---|---|
| Ethereum Mainnet | `0x737D278EC194E2e6FC9d634Bd3010d35794cee9f` | [Etherscan](https://etherscan.io/address/0x737D278EC194E2e6FC9d634Bd3010d35794cee9f#code) |
| Base | `0xD8833c0007cb65f264023b34e968381bA3d7a711` | [BaseScan](https://basescan.org/address/0xD8833c0007cb65f264023b34e968381bA3d7a711#code) |
| BNB Chain | `0x48f982e265c2c8482469b67fA644Cf72D86c911E` | [BscScan](https://bscscan.com/address/0x48f982e265c2c8482469b67fA644Cf72D86c911E#code) |
| Polygon | `0x48f982e265c2c8482469b67fA644Cf72D86c911E` | [PolygonScan](https://polygonscan.com/address/0x48f982e265c2c8482469b67fA644Cf72D86c911E#code) |
| Sepolia Testnet | `0x48f982e265c2c8482469b67fA644Cf72D86c911E` | [Etherscan](https://sepolia.etherscan.io/address/0x48f982e265c2c8482469b67fA644Cf72D86c911E#code) |

### Architecture

- **ERC20Token.sol** — Cloneable ERC-20 implementation (EIP-1167 proxy target). Built on OpenZeppelin ERC20Upgradeable, ERC20BurnableUpgradeable, ERC20PausableUpgradeable, Ownable2StepUpgradeable.
- **TokenFactory.sol** — Clone factory with 3-tier pricing. Uses OpenZeppelin Clones, Ownable2Step, ReentrancyGuard, SafeERC20.

### OpenZeppelin Foundation

The token implementation inherits from [OpenZeppelin Contracts Upgradeable v5](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable) — the industry standard audited library for ERC-20 tokens.

### Fee Flow

All fees are sent **directly** to the treasury wallet at deploy time. No funds are ever held in the factory contract. ETH excess is refunded in the same transaction.

### Platform Allocation

The Starter tier mints 3% of the initial token supply to the Ava Genesis treasury. This is:
- Fully transparent and visible on-chain
- Disclosed to users before deployment
- Hard-coded in the contract — not adjustable per deployment

## Reporting Vulnerabilities

If you discover a vulnerability, please email **support@avagenesis.com** with:
- A description of the vulnerability
- Steps to reproduce
- Potential impact

We aim to respond within 48 hours.