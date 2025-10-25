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
    registry = await NodeRegistry.deploy(token.address, 100);
    await registry.deployed();

    await token.transfer(user.address, 500);
  });

  it("user can register node", async function () {
    await token.connect(user).approve(registry.address, 100);
    await registry.connect(user).registerNode();
    const nodeInfo = await registry.nodes(user.address);
    expect(nodeInfo.isActive).to.be.true;
  });

  it("cannot register node without minimum stake", async function () {
    await token.connect(user).approve(registry.address, 50);
    await expect(registry.connect(user).registerNode()).to.be.reverted;
  });
});
