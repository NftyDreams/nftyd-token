const { expect } = require("chai");
const should = require("chai").should();
const { ethers } = require("hardhat");

describe("NftyDToken Contract", () => {
  let owner, teamAddr, opAddr, proAddr, rcAddr, treasury, addr;
  let contract;

  before(async () => {
    [owner, teamAddr, opAddr, proAddr, rcAddr, treasury, ...addr] =
      await ethers.getSigners();
    let NftyDToken = await ethers.getContractFactory("NftyDToken", owner);
    contract = await NftyDToken.deploy(
      "Dream",
      "DRM",
      owner.address,
      teamAddr.address,
      opAddr.address,
      proAddr.address,
      rcAddr.address,
      treasury.address
    );
    await contract.deployed();
  });

  it("Allocates the supply to  different addresses", async () => {
    expect(await contract.balanceOf(owner.address)).to.equal(50000000);
    expect(await contract.balanceOf(teamAddr.address)).to.equal(100000000);
    expect(await contract.balanceOf(opAddr.address)).to.equal(60000000);
    expect(await contract.balanceOf(proAddr.address)).to.equal(90000000);
    expect(await contract.balanceOf(rcAddr.address)).to.equal(200000000);
    expect(await contract.balanceOf(treasury.address)).to.equal(500000000);
  });

  it("does not accept ether", async () => {
    // var value = ethers.utils.parseEther("1");
    var tx = {
      to: contract.address,
      value: ethers.utils.parseEther("1"),
    };

    await expect(addr[0].sendTransaction(tx)).to.be.reverted;
  });
});
