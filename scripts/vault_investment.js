const { ethers } = require("hardhat");
const { mine } = require("@nomicfoundation/hardhat-network-helpers");
require("dotenv").config();

const PROVIDER = new ethers.providers.JsonRpcProvider();
const EXTERNAL_WHALE_ADDRESS = process.env.EXTERNAL_WHALE_ADDRESS;
const ARBITRUM_USDT_ADDRESS = process.env.ARBITRUM_USDT_ADDRESS;
const ARBITRUM_USDT_ABI = require("../abi/arbitrum_usdt_abi.json");
const CONTRACT_ADDRESS = "0xFa64f316e627aD8360de2476aF0dD9250018CFc5";

async function getMoney(amount) {
  const impersonatedSigner = await ethers.getImpersonatedSigner(
    EXTERNAL_WHALE_ADDRESS
  );

  await PROVIDER.getBalance(EXTERNAL_WHALE_ADDRESS).then((balance) => {
    let etherString = ethers.utils.formatEther(balance);
    console.log(EXTERNAL_WHALE_ADDRESS + " Balance is: " + etherString);
  });

  // 获取USDT余额
  const USDTContract = new ethers.Contract(
    ARBITRUM_USDT_ADDRESS,
    ARBITRUM_USDT_ABI,
    impersonatedSigner
  );
  await USDTContract.balanceOf(EXTERNAL_WHALE_ADDRESS).then((balance) => {
    balanceUsdt = ethers.utils.formatUnits(balance, 6);
    console.log(EXTERNAL_WHALE_ADDRESS + " USDT Balance is: " + balanceUsdt);
  });

  // 给本地账户转账100000个usdt
  const [localAccount] = await ethers.getSigners();
  await USDTContract.balanceOf(localAccount.getAddress()).then((balance) => {
    balanceUsdt = ethers.utils.formatUnits(balance, 6);
    console.log("before transfer USDT Balance is: " + balanceUsdt);
  });

  await USDTContract.transfer(localAccount.getAddress(), amount);

  await USDTContract.balanceOf(localAccount.getAddress()).then((balance) => {
    balanceUsdt = ethers.utils.formatUnits(balance, 6);
    console.log("after transfer USDT Balance is: " + balanceUsdt);
  });
}

async function main() {
  const VaultFactory = await ethers.getContractFactory("Vault");
  console.log("Deploying contract...");
  const vault = await VaultFactory.deploy();
  await vault.deployed();
  console.log(`Deployed contract to: ${vault.address}`);

  const [localAccount] = await ethers.getSigners();
  const localAccountAddress = await localAccount.getAddress();
  //   const vault = await ethers.getContractFactory("Vault");

  console.log("从巨鲸手里搞点USDT");
  const amount = ethers.utils.parseUnits("1000000", 6);
  await getMoney(amount);

  // 给vault授权
  const usdtAmount = ethers.utils.parseUnits("10000", 6);
  const usdtContract = new ethers.Contract(
    ARBITRUM_USDT_ADDRESS,
    ARBITRUM_USDT_ABI,
    localAccount
  );
  await usdtContract.approve(CONTRACT_ADDRESS, usdtAmount);

  const vaultTokenAddress = await vault
    .attach(CONTRACT_ADDRESS)
    .getVaultTokenAddress();
  console.log("VaultToken address：", vaultTokenAddress);

  // 查询当前usdt余额
  await usdtContract.balanceOf(localAccountAddress).then((balance) => {
    console.log("存入前usdt余额为：", ethers.utils.formatUnits(balance, 6));
  });

  console.log("往Vault合约中存入usdt");
  const [owner] = await ethers.getSigners();
  // 往vault存入usdt
  await vault
    .attach(CONTRACT_ADDRESS)
    .deposit(usdtAmount, { gasLimit: 1000000 });

  // 查询vault拥有的资产
  await vault
    .attach(CONTRACT_ADDRESS)
    .totalAssets({ gasLimit: 1000000 })
    .then((balance) => {
      console.log("vault余额为：", ethers.utils.formatUnits(balance, 6));
    });

  // 查询当前usdt余额
  await usdtContract.balanceOf(localAccountAddress).then((balance) => {
    console.log("存入后usdt余额为：", ethers.utils.formatUnits(balance, 6));
  });

  // 查询VT
  const vtContract = new ethers.Contract(
    vaultTokenAddress,
    ARBITRUM_USDT_ABI,
    localAccount
  );
  var vtAmount;
  await vtContract.balanceOf(localAccountAddress).then((balance) => {
    vtAmount = balance;
    console.log("VT余额为：", ethers.utils.formatUnits(balance, 6));
  });

  // 查询vault拥有的资产
  await vault
    .attach(CONTRACT_ADDRESS)
    .totalAssets({ gasLimit: 1000000 })
    .then((balance) => {
      console.log("vault余额为：", ethers.utils.formatUnits(balance, 6));
    });

  // 管理员进行投资
  console.log("管理员进行投资");
  await vault.attach(CONTRACT_ADDRESS).investment({ gasLimit: 1000000 });

  // 时间快进
  console.log("前进288000个区块");
  await mine(288000);

  // 管理员进行harvest
  console.log("管理员进行harvest");
  await vault.attach(CONTRACT_ADDRESS).harvest({ gasLimit: 1000000 });

  // 查询vault拥有的资产
  await vault
    .attach(CONTRACT_ADDRESS)
    .totalAssets({ gasLimit: 1000000 })
    .then((balance) => {
      console.log("vault余额为：", ethers.utils.formatUnits(balance, 6));
    });

  // 用户授权VT给vault
  await vtContract.approve(CONTRACT_ADDRESS, vtAmount);
  // 用户进行redeem
  await vault.attach(CONTRACT_ADDRESS).redeem(vtAmount, { gasLimit: 1000000 });

  // 查询当前usdt余额
  await usdtContract.balanceOf(localAccountAddress).then((balance) => {
    console.log("redeem后usdt余额为：", ethers.utils.formatUnits(balance, 6));
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
