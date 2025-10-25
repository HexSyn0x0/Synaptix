const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("StakingRewards", function () {
  let token, staking;
  let deployer, user;

  beforeEach(async function () {
    [deployer, user] = await ethers.getSigners();
    const Token = await ethers.getContractFactory("SynaptixToken");
    token = await Token.deploy();
    await token.deployed();

    const Staking = await ethers.getContractFactory("StakingRewards");
    staking = await Staking.deploy(token.address, token.address, 0);
    await staking.deployed();

    await token.transfer(user.address, 1000);
  });

  it("user can stake tokens", async function () {
    await token.connect(user).approve(staking.address, 1000);
    await staking.connect(user).stake(1000);
    const balance = await staking.balanceOf(user.address);
    expect(balance).to.equal(1000);
  });

  it("user cannot stake more than balance", async function () {
    await token.connect(user).approve(staking.address, 2000);
    await expect(staking.connect(user).stake(2000)).to.be.reverted;
  });
});
