# ⚡ Avalanche Teleporter Token Bridge

Cross-chain ERC20 bridge using [Avalanche Teleporter](https://github.com/ava-labs/teleporter).  
Intermediate complexity · Multi-contract · Full event coverage.

---

## Project Structure

```bash
AvaBridge/
├── contracts/
│   ├── interfaces/
│   │   └── ITeleporterMessenger.sol
│   ├── BridgedToken.sol
│   ├── TokenBridgeReceiver.sol
│   └── TokenBridgeSender.sol
├── frontend/
│   ├── index.html
│   └── README.md
├── app.html
├── landing.html
├── scripts/
│   └── deploy.js
├── hardhat.config.js
├── package.json
└── README.md
```

---

## Architecture

```
SOURCE CHAIN (C-Chain / Fuji)          DESTINATION CHAIN (Your L1 Subnet)
─────────────────────────────          ────────────────────────────────────

  [User] ──approve──▶ [ERC20]            [BridgedToken]
    │                                        ▲  mint/burn
    └──bridgeTokens()──▶ [TokenBridgeSender]  │
                              │         [TokenBridgeReceiver]
                              │               │
                         lock tokens     receiveTeleporterMessage()
                              │               │
                              └──Teleporter──▶┘
                                  (relayer)
```

### Contracts

| Contract | Chain | Role |
|---|---|---|
| `ITeleporterMessenger.sol` | Both | Interface to Ava Labs Teleporter |
| `BridgedToken.sol` | Destination | Mintable/burnable wrapped ERC20 |
| `TokenBridgeSender.sol` | Source | Lock tokens, send Teleporter message |
| `TokenBridgeReceiver.sol` | Destination | Receive message, mint/burn wrapped tokens |

---

## Events Reference

### TokenBridgeSender
| Event | Trigger |
|---|---|
| `BridgeInitiated(destinationChainID, sender, recipient, amount, messageID)` | User initiates a bridge |
| `BridgeCompleted(sourceChainID, recipient, amount)` | Return bridge completed, tokens unlocked |
| `DestinationRegistered(chainID, receiverContract)` | Admin registers a new destination |
| `TokensRecovered(to, amount)` | Emergency token recovery |

### TokenBridgeReceiver
| Event | Trigger |
|---|---|
| `TokensMintedOnDestination(recipient, amount, sourceChainID)` | Tokens minted after Teleporter message |
| `ReturnInitiated(burner, sourceRecipient, amount, messageID)` | User bridges tokens back |
| `SourceBridgeSet(chainID, bridge)` | Admin sets source link |

### BridgedToken
| Event | Trigger |
|---|---|
| `TokensMinted(to, amount)` | Bridge mints tokens |
| `TokensBurned(from, amount)` | Bridge burns tokens |
| `Transfer(from, to, amount)` | Standard ERC20 |

---

## Setup & Deployment

### 1. Install dependencies

```bash
npm install
```

### 1.1 Run the frontend locally

```bash
npm run frontend:dev
```

Open:

- `http://localhost:5173/landing.html`
- `http://localhost:5173/app.html`

Notes:

- `npm run dev` runs the same frontend server (see `package.json`).
- The UI lives in `app.html` (single-file app) and `landing.html`.

### 2. Configure environment

```bash
cp .env.example .env
```

Edit `.env`:
```
PRIVATE_KEY=0xYourPrivateKey
SUBNET_RPC_URL=http://your-subnet-rpc:9650/ext/bc/<ID>/rpc
SUBNET_CHAIN_ID=12345
SNOWTRACE_API_KEY=optional
```

### 3. Configure deploy script constants

Update the constants at the top of `scripts/deploy.js`:

- **`SOURCE_TOKEN_ADDRESS`**: the ERC20 on Avalanche C-Chain (Fuji by default) that users will lock/bridge
- **`SOURCE_CHAIN_ID`**: the Avalanche C-Chain blockchain ID (bytes32) used by Teleporter linking
- **`DEPLOYED_SENDER` / `DEPLOYED_RECEIVER`**: fill in after deployment (used for linking)

### 4. Compile contracts

```bash
npm run compile
```

### 5. Deploy to Source Chain (Avalanche Fuji C-Chain)

```bash
npm run deploy:source
# → logs: TokenBridgeSender address
```

After deploying, copy the printed sender address into:

- `scripts/deploy.js` → `DEPLOYED_SENDER`

### 6. Deploy to Destination Chain (your Subnet / L1)

```bash
npm run deploy:dest
# → logs: BridgedToken + TokenBridgeReceiver addresses
```

After deploying, copy the printed destination addresses into:

- `scripts/deploy.js` → `DEPLOYED_BRIDGED`
- `scripts/deploy.js` → `DEPLOYED_RECEIVER`

### 7. Link the two sides (register destination)

In `scripts/deploy.js`, set the destination chain’s blockchain ID (bytes32):

- `linkSource()` → `DEST_CHAIN_ID`

Then run:

```bash
npm run link
```

What linking does:

- On **source**: `TokenBridgeSender.registerDestination(DEST_CHAIN_ID, DEPLOYED_RECEIVER)`
- On **destination**: `TokenBridgeReceiver.setSourceBridge(SOURCE_CHAIN_ID, DEPLOYED_SENDER)` is attempted during `deploy:dest` if `DEPLOYED_SENDER` is already set

---

## Usage (after deployment)

### Bridge tokens: Source → Destination

```js
// 1. Approve the sender to spend your tokens
await token.approve(senderAddress, amount);

// 2. Initiate bridge
await sender.bridgeTokens(destinationChainID, recipientAddress, amount);
// → Teleporter relayer picks this up automatically
// → BridgedToken minted on destination within ~5-15 seconds
```

### Bridge back: Destination → Source

```js
// 1. Approve the receiver to burn your wrapped tokens
await bridgedToken.approve(receiverAddress, amount);

// 2. Return bridge
await receiver.returnTokens(amount, sourceChainRecipient);
// → BridgedToken burned on destination
// → Original tokens unlocked on source
```

---

## Getting Your Subnet Blockchain ID

```bash
# Using Avalanche CLI
avalanche blockchain describe <yourBlockchainName>
# Look for "Blockchain ID" in hex (bytes32 format)
```

---

## Troubleshooting

### MetaMask error: `eth_requestAccounts` already pending

If you see an error like:

- `Connection failed: Request of type eth_requestAccounts already pending ...`

It means a wallet connection prompt is already open/pending in MetaMask.

Fix:

- Open MetaMask and approve/reject the pending connection request
- Then reload `app.html` and click **Connect Wallet** once

This repo also includes a guard in the UI to prevent multiple concurrent connect requests from rapid clicks.

## Resources

- [Teleporter GitHub](https://github.com/ava-labs/teleporter)
- [public-avalanche-sdks](https://github.com/ava-labs/public-avalanche-sdks)
- [Avalanche Docs — Teleporter](https://docs.avax.network/build/cross-chain/teleporter/overview)
- [Fuji Faucet](https://faucet.avax.network/)
- [Snowtrace (Fuji Explorer)](https://testnet.snowtrace.io/)
