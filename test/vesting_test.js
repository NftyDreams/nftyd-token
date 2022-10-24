const { expect } = require("chai");
const should = require("chai").should();
const { ethers, waffle } = require("hardhat");

describe("Vesting contract", () => {
  let owner, teamAddr, opAddr, proAddr, rcAddr, treasury, addr;
  let tokenContract, vestingContract;
  let provider;

  before(async () => {
    [owner, teamAddr, opAddr, proAddr, rcAddr, treasury, ...addr] =
      await ethers.getSigners();
    provider = ethers.provider;
    let NftyDToken = await ethers.getContractFactory("NftyDToken", owner);
    tokenContract = await NftyDToken.deploy(
      "Dream",
      "DRM",
      owner.address,
      teamAddr.address,
      opAddr.address,
      proAddr.address,
      rcAddr.address,
      treasury.address
    );
    await tokenContract.deployed();

    let Vesting = await ethers.getContractFactory("TokenVesting", owner);
    vestingContract = await Vesting.deploy(tokenContract.address);
    await vestingContract.deployed();
  });

  it("assigns the token contract", async () => {
    expect(await vestingContract.tokenContract()).to.equal(
      tokenContract.address
    );
  });

  it("does not accept ether", async () => {
    // var value = ethers.utils.parseEther("1");
    var tx = {
      to: vestingContract.address,
      value: ethers.utils.parseEther("1"),
    };

    await expect(addr[0].sendTransaction(tx)).to.be.reverted;
  });

  it("allows only owner to authorize and deauthorize an account", async () => {
    await expect(
      vestingContract.connect(addr[0]).authorizeAddress(addr[1].address)
    ).to.be.reverted;

    var tx = await vestingContract.authorizeAddress(addr[1].address);
    await tx.wait();

    expect(await vestingContract.authorizedAddresses(addr[1].address)).to.equal(
      true
    );

    await expect(
      vestingContract.connect(addr[0]).deauthorizeAddress(addr[1].address)
    ).to.be.reverted;

    var tx = await vestingContract.deauthorizeAddress(addr[1].address);
    await tx.wait();

    expect(await vestingContract.authorizedAddresses(addr[1].address)).to.equal(
      false
    );
  });

  describe("grant vesting", () => {
    it("does not allow unauthorized addresses to grant tokens", async () => {
      var block = await provider.getBlock("latest");
      await expect(
        vestingContract.grant(
          addr[0].address,
          1000,
          block.timestamp,
          60,
          120,
          true
        )
      ).to.be.reverted;
    });

    it("allows authorizedAddresses to grant tokens", async () => {
      var tx = await vestingContract.authorizeAddress(rcAddr.address);
      await tx.wait();
      var tx = await tokenContract
        .connect(rcAddr)
        .approve(vestingContract.address, 100000);
      await tx.wait();
      var block = await provider.getBlock("latest");
      var tx = await vestingContract
        .connect(rcAddr)
        .grant(
          addr[0].address,
          100000,
          block.timestamp,
          2628288,
          63072000,
          true
        );
      await tx.wait();
      vestingGrant = await vestingContract.vestingGrants(addr[0].address);
      expect(vestingGrant.grantdreams).to.equal(100000);
    });

    it("transfers the unvested  tokens to the vesting escrow", async () => {
      expect(await tokenContract.balanceOf(vestingContract.address)).to.equal(
        100000
      );
    });

    it("does not allow tokens to be released before the cliff period", async () => {
      await provider.send("evm_increaseTime", [2628200]);
      await expect(
        vestingContract.releaseFor(addr[0].address)
      ).to.be.revertedWith("Cannot release tokens before cliff period");
    });

    it("allows tokens to be released per seconds passed after the cliff period", async () => {
      await provider.send("evm_increaseTime", [10628290]);

      var tx = await vestingContract.releaseFor(addr[0].address);
      await tx.wait();
      expect(await tokenContract.balanceOf(addr[0].address)).to.be.greaterThan(
        0
      );
    });

    it("allows unvested tokens to be revoked only by the issuer", async () => {
      await expect(vestingContract.revoke(addr[0].address)).to.be.revertedWith(
        "Not an issuer"
      );
      vestingGrant = await vestingContract.vestingGrants(addr[0].address);
      var initBalance = await tokenContract.balanceOf(rcAddr.address);
      revokedDreams = vestingGrant.grantdreams - vestingGrant.releaseddreams;
      var tx = await vestingContract.connect(rcAddr).revoke(addr[0].address);
      await tx.wait();
      var finalBalance = await tokenContract.balanceOf(rcAddr.address);

      expect(finalBalance - initBalance).to.equal(revokedDreams);
    });
  });
});
