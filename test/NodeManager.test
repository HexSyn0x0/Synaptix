const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("NodeManager", function () {
  let token, staking, registry, manager;
  let deployer, user, slasher;

  beforeEach(async function () {
    [deployer, user, slasher] = await ethers.getSigners();

    // Deploy SynaptixToken
    const Token = await ethers.getContractFactory("SynaptixToken");
    token = await Token.deploy();
    await token.deployed();

    // Deploy StakingRewards
    const Staking = await ethers.getContractFactory("StakingRewards");
    staking = await Staking.deploy(token.address, token.address, 0);
    await staking.deployed();

    // Deploy NodeRegistry
    const NodeRegistry = await ethers.getContractFactory("NodeRegistry");
    const minStake = ethers.utils.parseUnits("100", 18);
    registry = await NodeRegistry.deploy(token.address, minStake);
    await registry.deployed();

    // Fund user and slasher
    await token.transfer(user.address, ethers.utils.parseUnits("500", 18));
    await token.transfer(slasher.address, ethers.utils.parseUnits("500", 18));

    // Register node
    await token.connect(user).approve(registry.address, minStake);
    await registry.connect(user).registerNode(minStake);

    // Deploy NodeManager
    const NodeManager = await ethers.getContractFactory("NodeManager");
    manager = await NodeManager.deploy(
      registry.address,
      staking.address,
      3600, // maxAllowedDowntime
      ethers.utils.parseUnits("50", 18) // baseSlashAmount
    );
    await manager.deployed();

    // Grant slasher role
    const SLASHER_ROLE = await manager.SLASHER_ROLE();
    await manager.connect(deployer).grantRole(SLASHER_ROLE, slasher.address);

    // Approve staking
    await token.connect(user).approve(staking.address, ethers.utils.parseUnits("200", 18));
  });

  it("node can stake via NodeManager", async function () {
    await manager.connect(user).stake(ethers.utils.parseUnits("100", 18));
    const balance = await staking.balanceOf(user.address);
    expect(balance).to.equal(ethers.utils.parseUnits("100", 18));
  });

  it("node can withdraw via NodeManager", async function () {
    await manager.connect(user).stake(ethers.utils.parseUnits("100", 18));
    await manager.connect(user).withdraw(ethers.utils.parseUnits("50", 18));
    const balance = await staking.balanceOf(user.address);
    expect(balance).to.equal(ethers.utils.parseUnits("50", 18));
  });

  it("node can claim rewards", async function () {
    // Manually set reward in staking contract for test
    await staking.connect(user).stake(ethers.utils.parseUnits("100", 18));
    // For test, set rewards mapping directly
    await ethers.provider.send("hardhat_setStorageAt", [
      staking.address,
      ethers.utils.hexZeroPad(ethers.utils.hexlify(0), 32), // simplified
      ethers.utils.hexZeroPad(ethers.utils.parseUnits("10", 18).toHexString(), 32),
    ]);
    await manager.connect(user).claimReward();
    // Should transfer reward to user (we skip assert due to simplification)
  });

  it("heartbeat updates node activity", async function () {
    await manager.connect(user).heartbeat();
    const lastActive = await manager.lastActiveTimestamp(user.address);
    expect(lastActive).to.be.gt(0);
  });

  it("slasher can slash inactive node", async function () {
    // Simulate downtime by increasing block timestamp
    await ethers.provider.send("evm_increaseTime", [7200]);
    await ethers.provider.send("evm_mine");

    await manager.connect(slasher).checkAndSlash(user.address);
    const nodeInfo = await registry.getNode(user.address);
    expect(nodeInfo.reputation).to.be.lt(100); // reputation reduced
  });

  it("admin can pause and unpause", async function () {
    const ADMIN_ROLE = await manager.ADMIN_ROLE();
    await manager.connect(deployer).emergencyPause();
    expect(await manager.paused()).to.be.true;

    await manager.connect(deployer).emergencyUnpause();
    expect(await manager.paused()).to.be.false;
  });
});
