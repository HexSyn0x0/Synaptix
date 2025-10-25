// scripts/verify.js
// Usage (after deploy on a public network):
// npx hardhat run scripts/verify.js --network sepolia

const hre = require("hardhat");

async function main() {
  // Modify addresses below after deployment or read from a JSON file
  const addresses = {
    SynaptixToken: "0x...replace_with_deployed_address...",
    StakingRewards: "0x...replace_with_deployed_address...",
    NodeRegistry: "0x...replace_with_deployed_address...",
    SynaptixDEX: "0x...replace_with_deployed_address..."
  };

  for (const [name, addr] of Object.entries(addresses)) {
    if (addr && addr !== "0x...replace_with_deployed_address...") {
      console.log(`Verifying ${name} at ${addr}...`);
      try {
        await hre.run("verify:verify", {
          address: addr
          // constructorArguments: [] // add if needed
        });
        console.log(`${name} verified`);
      } catch (e) {
        console.error(`Failed verifying ${name}:`, e.message || e);
      }
    } else {
      console.log(`Skipping ${name} — address placeholder found`);
    }
  }
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
