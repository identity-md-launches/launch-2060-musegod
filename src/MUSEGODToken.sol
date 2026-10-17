// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title Musegod: fixed supply, no administrator, a fixed fee on PoolManager outflows.
/// @notice Launch allocation is performed by the factory, never by this constructor.
contract MUSEGODToken {
    string public constant name = "Musegod";
    string public constant symbol = "MUSEGOD";
    uint8 public constant decimals = 18;
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** 18;
    uint256 public constant BUY_FEE_BPS = 200;
    uint256 public constant BPS_DENOMINATOR = 10_000;
    address public constant POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address public constant TREASURY = 0x9Cf1A7Cd2a2A423d7Df0D9663E0092423993389A;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    /// @notice Lifetime buy fees in minor units (1 MUSEGOD = 1e18 units).
    /// @dev This counter never decreases when the treasury spends its tokens.
    uint256 public totalFeesCollected;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    error ERC20InvalidSender(address sender);
    error ERC20InvalidReceiver(address receiver);
    error ERC20InvalidSpender(address spender);
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    /// @dev The deployer receives every token; only the launch factory distributes them.
    constructor() {
        balanceOf[msg.sender] = TOTAL_SUPPLY;
        emit Transfer(address(0), msg.sender, TOTAL_SUPPLY);
    }

    function totalSupply() external pure returns (uint256) {
        return TOTAL_SUPPLY;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        if (spender == address(0)) revert ERC20InvalidSpender(spender);
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    /// @notice Transfers a gross amount, deducting the fixed fee when sent by the PoolManager.
    /// @dev Fees round down per transfer and apply to all manager outflows, including withdrawals.
    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    /// @notice Transfers a gross amount against the caller's allowance with the same sender-based fee.
    /// @dev Finite allowances decrease by the gross amount; maximum allowances remain unchanged.
    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 approved = allowance[from][msg.sender];
        if (approved != type(uint256).max) {
            if (approved < value) revert ERC20InsufficientAllowance(msg.sender, approved, value);
            unchecked {
                allowance[from][msg.sender] = approved - value;
            }
        }
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) private {
        if (from == address(0)) revert ERC20InvalidSender(from);
        if (to == address(0)) revert ERC20InvalidReceiver(to);
        uint256 held = balanceOf[from];
        if (held < value) revert ERC20InsufficientBalance(from, held, value);
        // This checks the sender, not the caller: transferFrom cannot bypass the buy fee.
        // Pool inputs (seeding and sells) and distributor claims therefore arrive whole.
        uint256 fee = from == POOL_MANAGER ? value * BUY_FEE_BPS / BPS_DENOMINATOR : 0;
        unchecked {
            balanceOf[from] = held - value;
        }
        if (fee != 0) {
            balanceOf[TREASURY] += fee;
            totalFeesCollected += fee;
            emit Transfer(from, TREASURY, fee);
        }
        uint256 received = value - fee;
        balanceOf[to] += received;
        emit Transfer(from, to, received);
    }
}
