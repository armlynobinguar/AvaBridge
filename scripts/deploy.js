// scripts/deploy.js
// Deploy the full bridge system across two chains.
// Run once per chain using --network flag.
//
// Usage:
//   npx hardhat run scripts/deploy.js --network cchain       (source)
//   npx hardhat run scripts/deploy.js --network mysubnet     (destination)

const { ethers } = require("hardhat");

// ── CONFIG ──────────────────────────────────────────────────────────────────
// Teleporter Messenger is pre-deployed by Ava Labs on every Avalanche chain.
// Address is the same on all chains:
const TELEPORTER_ADDRESS = "0x253b2784c75e510dD0fF1da844684a1aC0aa5fcf";

// Your ERC20 on C-Chain (the token users will bridge)
const SOURCE_TOKEN_ADDRESS = "0xYourTokenAddressOnCChain";

// Fill these in after first deployment
const DEPLOYED_SENDER   = ""; // TokenBridgeSender on C-Chain
const DEPLOYED_RECEIVER = ""; // TokenBridgeReceiver on Subnet
const DEPLOYED_BRIDGED  = ""; // BridgedToken on Subnet

// Avalanche C-Chain blockchain ID (bytes32, from `avalanche blockchain describe`)
const SOURCE_CHAIN_ID = "0x7fc93d85c6d62c5b2ac0b519c87010ea5294012d1f087cbfe3e11f3ad06e6c28";
// ────────────────────────────────────────────────────────────────────────────

async function deploySource() {
  console.log("\n=== Deploying to SOURCE chain (C-Chain) ===\n");
  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  const Sender = await ethers.getContractFactory("TokenBridgeSender");
  const sender = await Sender.deploy(TELEPORTER_ADDRESS, SOURCE_TOKEN_ADDRESS);
  await sender.waitForDeployment();

  console.log("✅ TokenBridgeSender deployed:", await sender.getAddress());
  console.log("\nNext steps:");
  console.log("  1. Deploy on destination chain");
  console.log("  2. Call sender.registerDestination(destinationChainID, receiverAddress)");
}

async function deployDestination() {
  console.log("\n=== Deploying to DESTINATION chain (Subnet) ===\n");
  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  // 1. Deploy BridgedToken
  const Token = await ethers.getContractFactory("BridgedToken");
  const token = await Token.deploy("Bridged USDC", "bUSDC");
  await token.waitForDeployment();
  const tokenAddr = await token.getAddress();
  console.log("✅ BridgedToken deployed:", tokenAddr);

  // 2. Deploy BridgeReceiver
  const Receiver = await ethers.getContractFactory("TokenBridgeReceiver");
  const receiver = await Receiver.deploy(TELEPORTER_ADDRESS, tokenAddr);
  await receiver.waitForDeployment();
  const receiverAddr = await receiver.getAddress();
  console.log("✅ TokenBridgeReceiver deployed:", receiverAddr);

  // 3. Grant BridgeReceiver mint/burn rights
  const setBridgeTx = await token.setBridge(receiverAddr);
  await setBridgeTx.wait();
  console.log("✅ BridgedToken.setBridge →", receiverAddr);

  // 4. Link receiver to source chain sender
  if (DEPLOYED_SENDER) {
    const linkTx = await receiver.setSourceBridge(SOURCE_CHAIN_ID, DEPLOYED_SENDER);
    await linkTx.wait();
    console.log("✅ setSourceBridge →", DEPLOYED_SENDER, "on chain", SOURCE_CHAIN_ID);
  } else {
    console.log("⚠️  DEPLOYED_SENDER not set — run setSourceBridge() manually after deploying source.");
  }

  console.log("\n📋 Summary:");
  console.log("   BridgedToken:        ", tokenAddr);
  console.log("   TokenBridgeReceiver: ", receiverAddr);
}

async function linkSource() {
  console.log("\n=== Linking Source Sender to Destination ===\n");
  const sender = await ethers.getContractAt("TokenBridgeSender", DEPLOYED_SENDER);

  // Get destination chainID from `avalanche blockchain describe --blockchain <name>`
  const DEST_CHAIN_ID = "0x"; // <-- fill in your subnet blockchain ID

  const tx = await sender.registerDestination(DEST_CHAIN_ID, DEPLOYED_RECEIVER);
  await tx.wait();
  console.log("✅ Registered destination:", DEPLOYED_RECEIVER, "on", DEST_CHAIN_ID);
}

// ── Entry Point ──────────────────────────────────────────────────────────────
async function main() {
  const args = process.argv.slice(2);
  const mode  = args.find(a => a.startsWith("--mode="))?.split("=")[1] || "source";

  if (mode === "source")      await deploySource();
  else if (mode === "dest")   await deployDestination();
  else if (mode === "link")   await linkSource();
  else console.error("Unknown mode. Use --mode=source | dest | link");
}

main().catch((err) => { console.error(err); process.exit(1); });
