const helpers = require("@nomicfoundation/hardhat-network-helpers");
const { ethers } = require("hardhat");
const USDT_ABI = require("../abi/usdt_abi.json");

// USDT_ADDRESS = "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9";
USDT_ADDRESS = "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9";

async function addLiquity() {}

async function main() {
  const address = "0x0d0707963952f2fba59dd06f2b425ace40b492fe";
  await helpers.impersonateAccount(address);
  const impersonatedSigner = await ethers.getSigner(address);

  const recipientAddress = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";
  const provider = new ethers.providers.JsonRpcProvider(
    "http://127.0.0.1:8545"
  );
  number = await provider.getBlockNumber();
  console.log(number);

  const USDT = new ethers.Contract(USDT_ADDRESS, USDT_ABI, provider);

  //   totalSupply = await USDT.connect(impersonatedSigner).totalSupply();
  //   console.log(totalSupply);
  //   balance = await USDT.balanceOf(recipientAddress);
  //   console.log(balance);

  await USDT.connect(impersonatedSigner).transfer(
    recipientAddress,
    ethers.utils.parseUnits("10000", 6)
  );

  balance = await USDT.balanceOf(recipientAddress);
  console.log(balance);

  number = await provider.getBlockNumber();
  console.log(number);

  const accounts = await ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
