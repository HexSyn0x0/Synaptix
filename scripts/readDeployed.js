// scripts/readDeployed.js
// Simple helper to instantiate deployed contracts (edit addresses below)

const hre = require("hardhat");
const { ethers } = hre;

async function main() {
  const addresses = {
    token: "0x...replace...",
    staking: "0x...replace...",
    registry: "0x...replace...",
    dex: "0x...replace..."
  };

  for (const [name, addr] of Object.entries(addresses)) {
    if (addr.includes("0x")) {
      try {
        const c = await ethers.getContractAt(name === "token" ? "SynaptixToken" : name === "staking" ? "StakingRewards" : name === "registry" ? "NodeRegistry" : "SynaptixDEX", addr);
        console.log(`${name} @ ${addr} -- OK`);
      } catch (e) {
        console.log(`Cannot attach to ${name} at ${addr}:`, e.message);
      }
    }
  }
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
