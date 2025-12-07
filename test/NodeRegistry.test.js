const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("NodeRegistry", function () {
  let token, registry;
  let deployer, user;

  beforeEach(async function () {
    [deployer, user] = await ethers.getSigners();
    const Token = await ethers.getContractFactory("SynaptixToken");
    token = await Token.deploy();
    await token.deployed();

    const NodeRegistry = await ethers.getContractFactory("NodeRegistry");
    const minStake = 100;
    registry = await NodeRegistry.deploy(token.address, minStake, 3600, 100, 250); // complete constructor
    await registry.deployed();

    await token.transfer(user.address, 500);
  });

  it("user can register node", async function () {
    await token.connect(user).approve(registry.address, 100);
    await registry.connect(user).registerNode(100);

    const nodeInfo = await registry.getNode(user.address);
    expect(nodeInfo.status).to.equal(1); // NodeStatus.Active
    expect(nodeInfo.stakedAmount).to.equal(100);
  });

  it("cannot register node without minimum stake", async function () {
    await token.connect(user).approve(registry.address, 50);
    await expect(registry.connect(user).registerNode(50)).to.be.revertedWith("stake below minimum");
  });
});
