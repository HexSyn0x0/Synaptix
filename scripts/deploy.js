// scripts/deploy.js
// Usage:
//  npx hardhat run scripts/deploy.js --network hardhat
//  npx hardhat run scripts/deploy.js --network sepolia

const hre = require("hardhat");
const { ethers } = hre;

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with:", deployer.address);

  // ---------------------
  // 1) Deploy SynaptixToken
  // ---------------------
  const Token = await ethers.getContractFactory("SynaptixToken");

  // Placeholder wallets (da sostituire con wallet reali)
  const presaleWallet = deployer.address;
  const liquidityWallet = deployer.address;
  const teamWallet = deployer.address;
  const nodeRewardsWallet = deployer.address;

  const token = await Token.deploy(
    presaleWallet,
    liquidityWallet,
    teamWallet,
    nodeRewardsWallet
  );
  await token.deployed();
  console.log("SynaptixToken deployed at:", token.address);

  // ---------------------
  // 2) Deploy StakingRewards
  // ---------------------
  const Staking = await ethers.getContractFactory("StakingRewards");

  // Reward rate iniziale = 0 (da aggiornare dopo)
  const rewardRate = 0;

  const staking = await Staking.deploy(token.address, token.address, rewardRate);
  await staking.deployed();
  console.log("StakingRewards deployed at:", staking.address);

  // ---------------------
  // 3) Deploy NodeRegistry
  // ---------------------
  const NodeRegistry = await ethers.getContractFactory("NodeRegistry");

  const minStake = ethers.utils.parseUnits("100", 18);   // esempio: 100 SYNX min stake
  const withdrawalDelay = 86400;                          // 1 giorno in secondi
  const maxReputation = 100;
  const slashPenaltyMultiplier = 250;                    // 2.5% se divisore = 10000

  const registry = await NodeRegistry.deploy(
    token.address,
    minStake,
    withdrawalDelay,
    maxReputation,
    slashPenaltyMultiplier
  );
  await registry.deployed();
  console.log("NodeRegistry deployed at:", registry.address);

  // ---------------------
  // 4) Deploy SynaptixDEX
  // ---------------------
  const Dex = await ethers.getContractFactory("SynaptixDEX");

  // Per prototipo, usiamo SYNX come tokenA e tokenB
  const dex = await Dex.deploy(token.address, token.address);
  await dex.deployed();
  console.log("SynaptixDEX deployed at:", dex.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
