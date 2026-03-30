// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/ITeleporterMessenger.sol";

/**
 * @title TokenBridgeSender
 * @notice Deployed on the SOURCE chain (e.g. Avalanche C-Chain).
 *         Users deposit an ERC20 here; it locks the tokens and sends a
 *         Teleporter message to BridgeReceiver on the destination subnet.
 *
 * Flow:
 *   User → approve(sender, amount)
 *   User → bridgeTokens(destinationChainID, recipient, amount)
 *        → locks tokens in this contract
 *        → emits BridgeInitiated
 *        → sends Teleporter cross-chain message
 *
 * On return bridge (destination → source):
 *   BridgeReceiver calls back via Teleporter
 *        → this contract releases locked tokens
 *        → emits BridgeCompleted
 */
contract TokenBridgeSender is ITeleporterReceiver {

    // ─── State ───────────────────────────────────────────────────────────────

    ITeleporterMessenger public immutable teleporter;
    address              public immutable sourceToken;   // ERC20 on this chain
    address              public           owner;

    /// Receiver contract address on each registered destination chain
    mapping(bytes32 => address) public destinationBridge;

    /// Total tokens currently locked in this contract
    uint256 public totalLocked;

    /// Required gas on destination for receiveTeleporterMessage
    uint256 public constant DESTINATION_GAS_LIMIT = 250_000;

    // ─── Events ──────────────────────────────────────────────────────────────

    event BridgeInitiated(
        bytes32 indexed destinationChainID,
        address indexed sender,
        address indexed recipient,
        uint256         amount,
        bytes32         teleporterMessageID
    );

    event BridgeCompleted(
        bytes32 indexed sourceChainID,
        address indexed recipient,
        uint256         amount
    );

    event DestinationRegistered(
        bytes32 indexed chainID,
        address         receiverContract
    );

    event TokensRecovered(address indexed to, uint256 amount);

    // ─── Errors ──────────────────────────────────────────────────────────────

    error OnlyOwner();
    error OnlyTeleporter();
    error DestinationNotRegistered(bytes32 chainID);
    error ZeroAmount();
    error ZeroAddress();
    error TransferFailed();

    // ─── Constructor ─────────────────────────────────────────────────────────

    /// @param _teleporter  Teleporter messenger address on this chain
    /// @param _sourceToken ERC20 token address to bridge
    constructor(address _teleporter, address _sourceToken) {
        if (_teleporter  == address(0)) revert ZeroAddress();
        if (_sourceToken == address(0)) revert ZeroAddress();
        teleporter  = ITeleporterMessenger(_teleporter);
        sourceToken = _sourceToken;
        owner       = msg.sender;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    modifier onlyTeleporter() {
        if (msg.sender != address(teleporter)) revert OnlyTeleporter();
        _;
    }

    // ─── Admin ───────────────────────────────────────────────────────────────

    /// @notice Register a BridgeReceiver address for a destination chain
    function registerDestination(
        bytes32 destinationChainID,
        address receiverContract
    ) external onlyOwner {
        if (receiverContract == address(0)) revert ZeroAddress();
        destinationBridge[destinationChainID] = receiverContract;
        emit DestinationRegistered(destinationChainID, receiverContract);
    }

    // ─── Core Bridge Logic ───────────────────────────────────────────────────

    /**
     * @notice Lock tokens on this chain and initiate a cross-chain transfer.
     * @param destinationChainID  Avalanche blockchain ID of the destination (bytes32).
     * @param recipient           Address that will receive tokens on destination.
     * @param amount              Token amount (in wei).
     */
    function bridgeTokens(
        bytes32 destinationChainID,
        address recipient,
        uint256 amount
    ) external returns (bytes32 messageID) {
        if (amount == 0)    revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAddress();

        address receiver = destinationBridge[destinationChainID];
        if (receiver == address(0)) revert DestinationNotRegistered(destinationChainID);

        // Lock tokens in this contract
        bool ok = _transferFrom(msg.sender, address(this), amount);
        if (!ok) revert TransferFailed();
        totalLocked += amount;

        // Encode payload: (recipient, amount)
        bytes memory payload = abi.encode(recipient, amount);

        // Send Teleporter message (no fee for simplicity; relayers can be open)
        messageID = teleporter.sendCrossChainMessage(
            TeleporterMessageInput({
                destinationBlockchainID:  destinationChainID,
                destinationAddress:       receiver,
                feeInfo:                  TeleporterFeeInfo({ feeTokenAddress: address(0), amount: 0 }),
                requiredGasLimit:         DESTINATION_GAS_LIMIT,
                allowedRelayerAddresses:  new address[](0), // any relayer
                message:                  payload
            })
        );

        emit BridgeInitiated(
            destinationChainID,
            msg.sender,
            recipient,
            amount,
            messageID
        );
    }

    /**
     * @notice Called by Teleporter when tokens are bridged BACK from destination.
     *         Releases locked tokens to the recipient on this (source) chain.
     */
    function receiveTeleporterMessage(
        bytes32 sourceBlockchainID,
        address originSenderAddress,
        bytes calldata message
    ) external override onlyTeleporter {
        // Validate: only accept messages from our registered receiver
        require(
            destinationBridge[sourceBlockchainID] == originSenderAddress,
            "TokenBridgeSender: unknown origin"
        );

        (address recipient, uint256 amount) = abi.decode(message, (address, uint256));

        totalLocked -= amount;
        bool ok = _transfer(recipient, amount);
        if (!ok) revert TransferFailed();

        emit BridgeCompleted(sourceBlockchainID, recipient, amount);
    }

    // ─── Internal helpers ────────────────────────────────────────────────────

    function _transferFrom(address from, address to, uint256 amount) internal returns (bool) {
        (bool success, bytes memory data) = sourceToken.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, amount)
        );
        return success && (data.length == 0 || abi.decode(data, (bool)));
    }

    function _transfer(address to, uint256 amount) internal returns (bool) {
        (bool success, bytes memory data) = sourceToken.call(
            abi.encodeWithSignature("transfer(address,uint256)", to, amount)
        );
        return success && (data.length == 0 || abi.decode(data, (bool)));
    }

    // ─── Emergency ───────────────────────────────────────────────────────────

    /// @notice Owner can recover stuck tokens (emergency use only)
    function recoverTokens(address to, uint256 amount) external onlyOwner {
        bool ok = _transfer(to, amount);
        if (!ok) revert TransferFailed();
        totalLocked -= amount;
        emit TokensRecovered(to, amount);
    }
}
