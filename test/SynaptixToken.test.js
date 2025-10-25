const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("SynaptixToken", function () {
  let token;
  let deployer, user;

  beforeEach(async function () {
    [deployer, user] = await ethers.getSigners();
    const Token = await ethers.getContractFactory("SynaptixToken");
    token = await Token.deploy();
    await token.deployed();
  });

  it("should assign total supply to deployer", async function () {
    const totalSupply = await token.totalSupply();
    const deployerBalance = await token.balanceOf(deployer.address);
    expect(deployerBalance).to.equal(totalSupply);
  });

  it("should transfer tokens correctly", async function () {
    await token.transfer(user.address, 1000);
    expect(await token.balanceOf(user.address)).to.equal(1000);
  });

  it("should not allow transferring more than balance", async function () {
    await expect(token.transfer(user.address, ethers.utils.parseUnits("100000000", 18)))
      .to.be.reverted;
  });
});
