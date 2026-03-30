require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

const accounts = process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [];

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: { enabled: true, runs: 200 },
    },
  },

  networks: {
    // Avalanche C-Chain (Fuji Testnet — source chain)
    cchain: {
      url: "https://api.avax-test.network/ext/bc/C/rpc",
      chainId: 43113,
      accounts,
    },

    // Avalanche C-Chain (Mainnet)
    cchain_mainnet: {
      url: "https://api.avax.network/ext/bc/C/rpc",
      chainId: 43114,
      accounts,
    },

    // Your custom Avalanche L1 / Subnet (update url + chainId)
    mysubnet: {
      url: process.env.SUBNET_RPC_URL || "http://localhost:9650/ext/bc/<blockchainID>/rpc",
      chainId: parseInt(process.env.SUBNET_CHAIN_ID || "99999"),
      accounts,
    },
  },

  etherscan: {
    apiKey: {
      avalancheFujiTestnet: process.env.SNOWTRACE_API_KEY || "",
    },
  },
};
