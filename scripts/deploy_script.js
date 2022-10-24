const { ethers } = require("hardhat");

async function main() {
  // We get the contract to deploy
  const signers = await ethers.getSigners();
  const TokenContract = await ethers.getContractFactory("NftyDToken");
  const tokenContract = await TokenContract.deploy(
    "Dream",
    "DRM",
    signers[0].address,
    signers[1].address,
    signers[2].address,
    signers[3].address,
    signers[4].address,
    signers[5].address
  );

  await tokenContract.deployed();

  console.log("Token deployed to:", tokenContract.address);

  const VestingContract = await ethers.getContractFactory("TokenVesting");
  const vestingContract = await VestingContract.deploy(tokenContract.address);
  await vestingContract.deployed();
  console.log("TokenVesting deployed to:", vestingContract.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
// npx hardhat verify 0x64472c0e743a2B3Fe5B111e15239925dF757345e --network rinkeby --constructor-args
