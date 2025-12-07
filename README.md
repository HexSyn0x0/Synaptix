# Synaptix
Synaptix is a next-generation decentralized exchange (DEX) built on Ethereum, powered by a community-driven DePIN infrastructure. It combines node-based rewards, transparent tokenomics, and on-chain trading for a fully decentralized financial ecosystem.


# Synaptix Protocol

**Synaptix** is a decentralized exchange (DEX) built on Ethereum, powered by a **DePIN node network** that merges peer-to-peer computing with transparent, on-chain finance.

## 🚀 Vision
To create a fully decentralized financial ecosystem where liquidity, computation, and governance are powered by the community itself.

## 🔧 Core Modules
- **SynaptixToken.sol** → Native ERC-20 token (SYNX)
- **StakingRewards.sol** → Node & user staking system
- **NodeRegistry.sol** → Decentralized node validation layer
- **SynaptixDEX.sol** → Automated Market Maker (AMM) and trading core
- **Utils.sol** → Math and shared library functions

💰 Tokenomics

Total Supply: 100,000,000 SYNX
Presale: 60%
Liquidity: 15%
Team & Partnerships: 5%
Node Rewards: 20%
SYNX is a fixed-supply token; no minting after deployment.

## 🧠 Architecture
Synaptix uses a **DePIN architecture**, where distributed nodes perform off-chain validation, aggregation, and routing tasks while maintaining a verifiable on-chain record.

## 🛠 Requirements
- Node.js >= 18  
- Hardhat >= 2.20  
- Solidity ^0.8.20  

## ⚙️ Quick Start
```bash
npm install
npx hardhat compile
npx hardhat test



REPOSITORY STRUCTURE

contracts/       → Smart contracts (Solidity)
test/            → Unit & integration tests
scripts/         → Deployment & verification scripts
docs/            → Whitepaper, architecture diagrams
frontend/        → Website (static or React version)
