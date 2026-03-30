// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/ITeleporterMessenger.sol";
import "./BridgedToken.sol";

/**
 * @title TokenBridgeReceiver
 * @notice Deployed on the DESTINATION chain (your Avalanche L1 / subnet).
 *         Listens for Teleporter messages from TokenBridgeSender and mints
 *         BridgedToken to the recipient.
 *
 * Flow (forward — source → destination):
 *   Teleporter relayer → receiveTeleporterMessage(...)
 *                      → mints BridgedToken to recipient
 *                      → emits TokensMintedOnDestination
 *
 * Flow (return — destination → source):
 *   User → approve(receiver, amount)
 *   User → returnTokens(amount)
 *        → burns BridgedToken
 *        → sends Teleporter message back to TokenBridgeSender
 *        → emits ReturnInitiated
 */
contract TokenBridgeReceiver is ITeleporterReceiver {

    // ─── State ───────────────────────────────────────────────────────────────

    ITeleporterMessenger public immutable teleporter;
    BridgedToken         public immutable bridgedToken;

    address public owner;

    /// Source chain ID (e.g. Avalanche C-Chain blockchain ID)
    bytes32 public sourceChainID;

    /// TokenBridgeSender address on the source chain
    address public sourceBridge;

    uint256 public constant RETURN_GAS_LIMIT = 200_000;

    // ─── Events ──────────────────────────────────────────────────────────────

    event TokensMintedOnDestination(
        address indexed recipient,
        uint256         amount,
        bytes32         sourceChainID_
    );

    event ReturnInitiated(
        address indexed burner,
        address indexed sourceRecipient,
        uint256         amount,
        bytes32         teleporterMessageID
    );

    event SourceBridgeSet(bytes32 chainID, address bridge);

    // ─── Errors ──────────────────────────────────────────────────────────────

    error OnlyOwner();
    error OnlyTeleporter();
    error InvalidSourceBridge();
    error ZeroAmount();
    error ZeroAddress();

    // ─── Constructor ─────────────────────────────────────────────────────────

    /// @param _teleporter   Teleporter messenger address on this chain
    /// @param _bridgedToken BridgedToken contract address (set bridge to this after deploy)
    constructor(address _teleporter, address _bridgedToken) {
        if (_teleporter   == address(0)) revert ZeroAddress();
        if (_bridgedToken == address(0)) revert ZeroAddress();
        teleporter   = ITeleporterMessenger(_teleporter);
        bridgedToken = BridgedToken(_bridgedToken);
        owner        = msg.sender;
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

    /// @notice Link this receiver to the source chain sender (called once after deploy)
    function setSourceBridge(
        bytes32 _sourceChainID,
        address _sourceBridge
    ) external onlyOwner {
        if (_sourceBridge == address(0)) revert ZeroAddress();
        sourceChainID = _sourceChainID;
        sourceBridge  = _sourceBridge;
        emit SourceBridgeSet(_sourceChainID, _sourceBridge);
    }

    // ─── Incoming: Teleporter → mint ─────────────────────────────────────────

    /**
     * @notice Called by Teleporter when a bridge message arrives from the source chain.
     *         Mints BridgedToken to the intended recipient.
     */
    function receiveTeleporterMessage(
        bytes32 _sourceChainID,
        address originSenderAddress,
        bytes calldata message
    ) external override onlyTeleporter {
        // Validate the origin
        if (
            _sourceChainID    != sourceChainID ||
            originSenderAddress != sourceBridge
        ) revert InvalidSourceBridge();

        (address recipient, uint256 amount) = abi.decode(message, (address, uint256));

        // Mint wrapped tokens to recipient
        bridgedToken.mint(recipient, amount);

        emit TokensMintedOnDestination(recipient, amount, _sourceChainID);
    }

    // ─── Outgoing: burn → Teleporter → source ────────────────────────────────

    /**
     * @notice Burn BridgedTokens and send a Teleporter message to unlock
     *         the original tokens on the source chain.
     * @param amount          Amount to bridge back.
     * @param sourceRecipient Address on the SOURCE chain to receive unlocked tokens.
     */
    function returnTokens(
        uint256 amount,
        address sourceRecipient
    ) external returns (bytes32 messageID) {
        if (amount == 0)              revert ZeroAmount();
        if (sourceRecipient == address(0)) revert ZeroAddress();

        // Pull & burn the wrapped tokens
        bridgedToken.transferFrom(msg.sender, address(this), amount);
        bridgedToken.burn(address(this), amount);

        // Encode return payload
        bytes memory payload = abi.encode(sourceRecipient, amount);

        // Send back via Teleporter
        messageID = teleporter.sendCrossChainMessage(
            TeleporterMessageInput({
                destinationBlockchainID:  sourceChainID,
                destinationAddress:       sourceBridge,
                feeInfo:                  TeleporterFeeInfo({ feeTokenAddress: address(0), amount: 0 }),
                requiredGasLimit:         RETURN_GAS_LIMIT,
                allowedRelayerAddresses:  new address[](0),
                message:                  payload
            })
        );

        emit ReturnInitiated(msg.sender, sourceRecipient, amount, messageID);
    }

    // ─── View ────────────────────────────────────────────────────────────────

    /// @notice Total bridged supply currently on this chain
    function bridgedSupply() external view returns (uint256) {
        return bridgedToken.totalSupply();
    }
}
