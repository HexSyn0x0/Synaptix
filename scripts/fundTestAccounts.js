// scripts/fundTestAccounts.js
// Usage: npx hardhat run scripts/fundTestAccounts.js --network hardhat

const hre = require("hardhat");
const { ethers } = hre;

async function main() {
  const [deployer, a, b, c] = await ethers.getSigners();

  const tokenAddress = "0x...replace_with_token_address...";
  if (!tokenAddress || tokenAddress === "0x...replace_with_token_address...") {
    console.error("Please edit tokenAddress in this script before running.");
    return;
  }

  const Token = await ethers.getContractAt("SynaptixToken", tokenAddress);
  const amount = ethers.utils.parseUnits("10000", 18);

  for (const acct of [a.address, b.address, c.address]) {
    const tx = await Token.transfer(acct, amount);
    await tx.wait();
    console.log("Funded", acct, "with", ethers.utils.formatUnits(amount, 18));
  }
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
