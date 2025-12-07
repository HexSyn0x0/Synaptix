const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("SynaptixDEX", function () {
  let token, dex;
  let deployer, user;

  const collateralAmount = ethers.utils.parseUnits("500", 18);
  const userInitialBalance = ethers.utils.parseUnits("1000", 18);
  const entryPrice = ethers.utils.parseUnits("1000", 18);

  beforeEach(async function () {
    [deployer, user] = await ethers.getSigners();

    // Deploy token
    const Token = await ethers.getContractFactory("SynaptixToken");
    token = await Token.deploy();
    await token.deployed();

    // Transfer initial balance to user
    await token.transfer(user.address, userInitialBalance);

    // Deploy DEX
    const Dex = await ethers.getContractFactory("SynaptixDEX");
    dex = await Dex.deploy(token.address, token.address);
    await dex.deployed();
  });

  it("user can open a long position", async function () {
    await token.connect(user).approve(dex.address, collateralAmount);
    await dex.connect(user).openPosition(collateralAmount, collateralAmount, entryPrice, 2);

    const pos = await dex.positions(user.address);
    expect(pos.isActive).to.be.true;
    expect(pos.size).to.equal(collateralAmount);
    expect(pos.collateral).to.equal(collateralAmount);
  });

  it("user can open a short position", async function () {
    await token.connect(user).approve(dex.address, collateralAmount);
    await dex.connect(user).openPosition(-collateralAmount, collateralAmount, entryPrice, 2);

    const pos = await dex.positions(user.address);
    expect(pos.isActive).to.be.true;
    expect(pos.size).to.equal(collateralAmount.mul(-1));
    expect(pos.collateral).to.equal(collateralAmount);
  });

  it("user can partially close a position", async function () {
    await token.connect(user).approve(dex.address, collateralAmount);
    await dex.connect(user).openPosition(collateralAmount, collateralAmount, entryPrice, 2);

    const closeAmount = ethers.utils.parseUnits("200", 18);
    await dex.connect(user).closePosition(closeAmount, entryPrice.add(ethers.utils.parseUnits("100", 18)));

    const pos = await dex.positions(user.address);
    expect(pos.size).to.equal(collateralAmount.sub(closeAmount));
    expect(pos.isActive).to.be.true;
  });

  it("cannot open a position exceeding leverage", async function () {
    await token.connect(user).approve(dex.address, collateralAmount);
    const excessiveSize = collateralAmount.mul(12); // over 5x leverage limit
    await expect(
      dex.connect(user).openPosition(excessiveSize, collateralAmount, entryPrice, 12)
    ).to.be.revertedWith("Leverage too high");
  });

  it("cannot open a zero-size position", async function () {
    await token.connect(user).approve(dex.address, collateralAmount);
    await expect(
      dex.connect(user).openPosition(0, collateralAmount, entryPrice, 2)
    ).to.be.revertedWith("Size cannot be 0");
  });

  it("liquidates under-collateralized positions", async function () {
    await token.connect(user).approve(dex.address, collateralAmount);
    await dex.connect(user).openPosition(collateralAmount, collateralAmount, entryPrice, 2);

    const priceDrop = entryPrice.sub(entryPrice.mul(96).div(100)); // triggers liquidation (threshold 95%)
    await dex.connect(deployer).liquidate(user.address, priceDrop);

    const pos = await dex.positions(user.address);
    expect(pos.isActive).to.be.false;
  });
});
