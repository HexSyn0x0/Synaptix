const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("StakingRewards", function () {
  let token, staking;
  let deployer, user;

  const initialUserBalance = ethers.utils.parseUnits("1000", 18);
  const stakeAmount = ethers.utils.parseUnits("500", 18);
  const rewardRate = ethers.utils.parseUnits("1", 18); // 1 SYNX per second

  beforeEach(async function () {
    [deployer, user] = await ethers.getSigners();

    // Deploy token
    const Token = await ethers.getContractFactory("SynaptixToken");
    token = await Token.deploy();
    await token.deployed();

    // Transfer initial balance to user
    await token.transfer(user.address, initialUserBalance);

    // Deploy StakingRewards
    const Staking = await ethers.getContractFactory("StakingRewards");
    staking = await Staking.deploy(token.address, token.address, rewardRate);
    await staking.deployed();
  });

  it("user can stake tokens", async function () {
    await token.connect(user).approve(staking.address, stakeAmount);
    await staking.connect(user).stake(stakeAmount);

    const balance = await staking.balanceOf(user.address);
    const totalSupply = await staking.totalSupply();
    expect(balance).to.equal(stakeAmount);
    expect(totalSupply).to.equal(stakeAmount);
  });

  it("user cannot stake more than balance", async function () {
    const tooMuch = ethers.utils.parseUnits("2000", 18);
    await token.connect(user).approve(staking.address, tooMuch);
    await expect(staking.connect(user).stake(tooMuch)).to.be.revertedWith(
      "ERC20: transfer amount exceeds balance"
    );
  });

  it("user can withdraw staked tokens", async function () {
    await token.connect(user).approve(staking.address, stakeAmount);
    await staking.connect(user).stake(stakeAmount);

    await staking.connect(user).withdraw(stakeAmount);

    const balance = await staking.balanceOf(user.address);
    const totalSupply = await staking.totalSupply();
    expect(balance).to.equal(0);
    expect(totalSupply).to.equal(0);
  });

  it("user can claim rewards", async function () {
    await token.connect(user).approve(staking.address, stakeAmount);
    await staking.connect(user).stake(stakeAmount);

    // simulate some time passing
    await ethers.provider.send("evm_increaseTime", [10]); // 10 seconds
    await ethers.provider.send("evm_mine");

    const rewardsBefore = await staking.earned(user.address);
    expect(rewardsBefore).to.be.gt(0);

    const userBalanceBefore = await token.balanceOf(user.address);
    await staking.connect(user).getReward();
    const userBalanceAfter = await token.balanceOf(user.address);

    expect(userBalanceAfter.sub(userBalanceBefore)).to.equal(rewardsBefore);
  });

  it("user can exit (withdraw + claim rewards)", async function () {
    await token.connect(user).approve(staking.address, stakeAmount);
    await staking.connect(user).stake(stakeAmount);

    await ethers.provider.send("evm_increaseTime", [10]);
    await ethers.provider.send("evm_mine");

    const rewardsBefore = await staking.earned(user.address);
    const userBalanceBefore = await token.balanceOf(user.address);

    await staking.connect(user).exit();

    const userBalanceAfter = await token.balanceOf(user.address);
    const stakedBalance = await staking.balanceOf(user.address);
    const totalSupply = await staking.totalSupply();

    expect(stakedBalance).to.equal(0);
    expect(totalSupply).to.equal(0);
    expect(userBalanceAfter.sub(userBalanceBefore)).to.equal(stakeAmount.add(rewardsBefore));
  });
});
