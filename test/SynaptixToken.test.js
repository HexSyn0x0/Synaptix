const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("SynaptixToken", function () {
  let token;
  let deployer, user;

  const TOTAL_SUPPLY = ethers.utils.parseUnits("100000000", 18); // 100M SYNX

  beforeEach(async function () {
    [deployer, user] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("SynaptixToken");
    token = await Token.deploy();
    await token.deployed();
  });

  it("should assign the total supply to the deployer", async function () {
    const deployerBalance = await token.balanceOf(deployer.address);
    expect(deployerBalance).to.equal(TOTAL_SUPPLY);
  });

  it("should transfer tokens correctly", async function () {
    const transferAmount = ethers.utils.parseUnits("1000", 18);
    await token.transfer(user.address, transferAmount);
    const userBalance = await token.balanceOf(user.address);
    expect(userBalance).to.equal(transferAmount);

    const deployerBalance = await token.balanceOf(deployer.address);
    expect(deployerBalance).to.equal(TOTAL_SUPPLY.sub(transferAmount));
  });

  it("should not allow transferring more than balance", async function () {
    const excessiveAmount = TOTAL_SUPPLY.add(ethers.utils.parseUnits("1", 18));
    await expect(token.transfer(user.address, excessiveAmount)).to.be.revertedWith(
      "ERC20: transfer amount exceeds balance"
    );
  });

  it("should allow multiple sequential transfers", async function () {
    const amount1 = ethers.utils.parseUnits("5000", 18);
    const amount2 = ethers.utils.parseUnits("2000", 18);

    await token.transfer(user.address, amount1);
    await token.transfer(user.address, amount2);

    const userBalance = await token.balanceOf(user.address);
    expect(userBalance).to.equal(amount1.add(amount2));

    const deployerBalance = await token.balanceOf(deployer.address);
    expect(deployerBalance).to.equal(TOTAL_SUPPLY.sub(amount1.add(amount2)));
  });
});
