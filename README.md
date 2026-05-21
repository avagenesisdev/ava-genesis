# Ava Genesis — ERC-20 Token Deployment MCP Server

> Deploy ERC-20 tokens on Ethereum, Base, BNB Chain, and Polygon via a single MCP call. Built for AI agents.

[![Glama Score](https://glama.ai/mcp/badges/com.avagenesis/ava-genesis-agent-api/score)](https://glama.ai/mcp/connectors/com.avagenesis/ava-genesis-agent-api)
[![Status](https://img.shields.io/badge/status-healthy-brightgreen)](https://avagenesis.com/api/mcp)

## What it does

One MCP tool call returns a deployed, verified ERC-20 contract address. No Solidity knowledge required. Same OpenZeppelin contracts used by human users on the website — your agent owns the contract from deploy.

## Pricing

| Network | Cost |
|---|---|
| Sepolia testnet | **Free** — unlimited, no wallet needed |
| Ethereum mainnet | $10 flat + gas |
| Base | $10 flat + gas (lowest fees) |
| BNB Chain | $10 flat + gas (lowest fees) |
| Polygon | $10 flat + gas |

## Quick Start

**Step 1 - Get a free API key**
```bash
curl -X POST https://avagenesis.com/api/agents/keys \
  -H "Content-Type: application/json" \
  -d '{"name": "My Agent"}'
# Returns: { "key": "ava_live_..." }
```

**Step 2 - Deploy on Sepolia (free)**
```bash
curl -X POST https://avagenesis.com/api/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"ava_deploy_token","arguments":{"apiKey":"ava_live_...","chain":"sepolia","name":"My Token","symbol":"MTK","supply":"1000000"}}}'
# Returns: { "contractAddress": "0x...", "explorerUrl": "https://sepolia.etherscan.io/..." }
```

**Step 3 - Deploy on mainnet (agent signs with own wallet)**
```bash
curl -X POST https://avagenesis.com/api/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"ava_create_token_intent","arguments":{"apiKey":"ava_live_...","chain":"base","name":"My Token","symbol":"MTK","supply":"1000000"}}}'
# Returns encoded calldata - sign and broadcast from your agent wallet
```

## MCP Endpoint

```
https://avagenesis.com/api/mcp
```

- Protocol: `2024-11-05`
- Transport: Streamable HTTP + SSE
- Auth: API key (`ava_live_...`)

## Available Tools

| Tool | Description |
|---|---|
| `ava_deploy_token` | Deploy on Sepolia testnet - free, no wallet required |
| `ava_create_token_intent` | Deploy on mainnet - agent signs with own wallet |
| `ava_confirm_deployment` | Submit txHash, receive contract address |
| `ava_get_deployment_status` | Poll deployment status by intentId |
| `ava_simulate_token` | Validate config + fee estimate, zero gas spent |
| `ava_get_gas_prices` | Live gas prices across all supported chains |
| `ava_list_templates` | Pre-configured token templates |
| `ava_list_my_tokens` | List all tokens deployed by your API key |
| `ava_create_api_key` | Bootstrap - get your API key |

## Token Features

| Feature | Tier |
|---|---|
| Burnable | Basic ($20) |
| Mintable | Premium ($50) |
| Pausable | Premium ($50) |
| Blacklist | Premium ($50) |
| Buy/Sell Tax | Premium ($50) |
| Anti-Whale | Premium ($50) |

## Supported Chains

- Ethereum mainnet (chainId: 1)
- Base (chainId: 8453)
- BNB Chain (chainId: 56)
- Polygon (chainId: 137)
- Sepolia testnet (chainId: 11155111) - free

## Use Cases

- **Agent Treasuries** - AI agents deploy their own governance tokens
- **Autonomous DAOs** - spin up membership tokens without human intervention
- **Reward Automation** - bots deploy and distribute reward tokens on-chain
- **Agent-to-Agent Commerce** - settle value transfers between autonomous systems
- **Web3 CI/CD** - integrate token deployment into automated pipelines

## Compatible With

Claude · Cursor · Windsurf · Cline · Any MCP client

## Links

- Website: [avagenesis.com](https://avagenesis.com)
- Agent Docs: [avagenesis.com/docs/agents](https://avagenesis.com/docs/agents)
- Glama Listing: [glama.ai/mcp/connectors/com.avagenesis/ava-genesis-agent-api](https://glama.ai/mcp/connectors/com.avagenesis/ava-genesis-agent-api)
- PulseMCP: [pulsemcp.com/servers/avagenesisdev-ava-genesis](https://www.pulsemcp.com/servers/avagenesisdev-ava-genesis)
- Support: support@avagenesis.com
- X/Twitter: [@avacorex](https://x.com/avacorex)
