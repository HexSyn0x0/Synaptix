const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("SynaptixDEX", function () {
  let token, dex;
  let deployer, user;

  beforeEach(async function () {
    [deployer, user] = await ethers.getSigners();
    const Token = await ethers.getContractFactory("SynaptixToken");
    token = await Token.deploy();
    await token.deployed();

    const Dex = await ethers.getContractFactory("SynaptixDEX");
    dex = await Dex.deploy(token.address, token.address);
    await dex.deployed();

    await token.transfer(user.address, 1000);
  });

  it("user can open long position", async function () {
    await token.connect(user).approve(dex.address, 1000);
    await dex.connect(user).openPosition(500, 500, 1000, 2);
    const pos = await dex.positions(user.address);
    expect(pos.isActive).to.be.true;
    expect(pos.size).to.equal(500);
  });

  it("user can close part of position", async function () {
    await token.connect(user).approve(dex.address, 500);
    await dex.connect(user).openPosition(500, 500, 1000, 2);
    await dex.connect(user).closePosition(200, 1100);
    const pos = await dex.positions(user.address);
    expect(pos.size).to.equal(300);
  });

  it("cannot open position exceeding leverage", async function () {
    await token.connect(user).approve(dex.address, 1000);
    await expect(dex.connect(user).openPosition(6000, 500, 1000, 12)).to.be.reverted;
  });
});
