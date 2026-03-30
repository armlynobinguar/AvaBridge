// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title BridgedToken
 * @notice Wrapped ERC20 that only the BridgeReceiver can mint/burn.
 *         Deployed on the DESTINATION chain (e.g. your custom L1 / subnet).
 */
contract BridgedToken {
    // ─── State ───────────────────────────────────────────────────────────────

    string  public name;
    string  public symbol;
    uint8   public constant decimals = 18;
    uint256 public totalSupply;

    address public bridge;   // the BridgeReceiver contract
    address public owner;

    mapping(address => uint256)                     public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // ─── Events ──────────────────────────────────────────────────────────────

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner_, address indexed spender, uint256 amount);
    event BridgeUpdated(address indexed oldBridge, address indexed newBridge);
    event TokensMinted(address indexed to, uint256 amount);
    event TokensBurned(address indexed from, uint256 amount);

    // ─── Errors ──────────────────────────────────────────────────────────────

    error OnlyBridge();
    error OnlyOwner();
    error InsufficientBalance();
    error InsufficientAllowance();
    error ZeroAddress();

    // ─── Constructor ─────────────────────────────────────────────────────────

    constructor(string memory _name, string memory _symbol) {
        name   = _name;
        symbol = _symbol;
        owner  = msg.sender;
    }

    // ─── Modifiers ───────────────────────────────────────────────────────────

    modifier onlyBridge() {
        if (msg.sender != bridge) revert OnlyBridge();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    // ─── Admin ───────────────────────────────────────────────────────────────

    /// @notice Set the bridge receiver address (called once after deploying BridgeReceiver)
    function setBridge(address _bridge) external onlyOwner {
        if (_bridge == address(0)) revert ZeroAddress();
        emit BridgeUpdated(bridge, _bridge);
        bridge = _bridge;
    }

    // ─── Bridge-only mint/burn ────────────────────────────────────────────────

    function mint(address to, uint256 amount) external onlyBridge {
        totalSupply     += amount;
        balanceOf[to]   += amount;
        emit TokensMinted(to, amount);
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external onlyBridge {
        if (balanceOf[from] < amount) revert InsufficientBalance();
        balanceOf[from] -= amount;
        totalSupply     -= amount;
        emit TokensBurned(from, amount);
        emit Transfer(from, address(0), amount);
    }

    // ─── ERC20 ───────────────────────────────────────────────────────────────

    function transfer(address to, uint256 amount) external returns (bool) {
        if (balanceOf[msg.sender] < amount) revert InsufficientBalance();
        balanceOf[msg.sender] -= amount;
        balanceOf[to]         += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (allowance[from][msg.sender] < amount) revert InsufficientAllowance();
        if (balanceOf[from] < amount)             revert InsufficientBalance();
        allowance[from][msg.sender] -= amount;
        balanceOf[from]             -= amount;
        balanceOf[to]               += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}
