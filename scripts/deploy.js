// scripts/deploy.js
// Usage:
//  npx hardhat run scripts/deploy.js --network hardhat
//  npx hardhat run scripts/deploy.js --network sepolia

const hre = require("hardhat");
const { ethers } = hre;

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with:", deployer.address);

  // 1) Deploy SynaptixToken
  const Token = await ethers.getContractFactory("SynaptixToken");
  const token = await Token.deploy();
  await token.deployed();
  console.log("SynaptixToken deployed at:", token.address);

  // 2) Deploy StakingRewards (use token as staking & reward for now)
  const Staking = await ethers.getContractFactory("StakingRewards");
  const staking = await Staking.deploy(token.address, token.address, 0); // rewardRate initially 0
  await staking.deployed();
  console.log("StakingRewards deployed at:", staking.address);

  // 3) Deploy NodeRegistry (minStake example: 100 SYNX)
  const NodeRegistry = await ethers.getContractFactory("NodeRegistry");
  const minStake = ethers.utils.parseUnits("100", 18);
  const registry = await NodeRegistry.deploy(token.address, minStake);
  await registry.deployed();
  console.log("NodeRegistry deployed at:", registry.address);

  // 4) Deploy SynaptixDEX (proto)
  const Dex = await ethers.getContractFactory("SynaptixDEX");
  // tokenA & tokenB: for prototype, we pass the same token (SYNX)
  const dex = await Dex.deploy(token.address, token.address);
  await dex.deployed();
  console.log("SynaptixDEX deployed at:", dex.address);

  // 5) Bootstrap token distribution (example values)
  const totalSupply = await token.totalSupply();
  console.log("Total supply:", ethers.utils.formatUnits(totalSupply, 18));

  // send some tokens to staking contract (e.g., 1_000_000 SYNX)
  const toStaking = ethers.utils.parseUnits("1000000", 18);
  await token.transfer(staking.address, toStaking);
  console.log("Transferred to StakingRewards:", ethers.utils.formatUnits(toStaking, 18));

  // send some tokens to DEX for liquidity (e.g., 500_000 SYNX)
  const toDex = ethers.utils.parseUnits("500000", 18);
  await token.transfer(dex.address, toDex);
  console.log("Transferred to Dex:", ethers.utils.formatUnits(toDex, 18));

  console.log("Deployment finished.");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
