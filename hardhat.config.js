require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.18",
  networks: {
    hardhat: {
      chainId: 42161,
      forking: {
        url: "https://arb-mainnet.g.alchemy.com/v2/C4Rw08pOrvES9HX9IQyhoEx0luynFiJC",
        blockNumber: 96027528,
      },
    },
  },
};
