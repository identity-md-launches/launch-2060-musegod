// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {MUSEGODToken} from "src/MUSEGODToken.sol";
import {Vm} from "./MUSEGODToken.t.sol";

/// @dev A closed set of holders makes conservation observable without writing token storage.
/// The oracle uses the requested 1/50 fee, never the implementation's fee getter or balances.
contract MusegodTransferHandler {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address private constant MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address private constant TREASURY = 0x9Cf1A7Cd2a2A423d7Df0D9663E0092423993389A;
    uint256 private constant SUPPLY = 1e27;

    MUSEGODToken public immutable token;
    address[9] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;
    uint256 public expectedFees;

    constructor() {
        token = new MUSEGODToken();
        actors = [
            address(this),
            address(0xA11CE),
            address(0xB0B),
            address(0xCA401),
            MANAGER,
            TREASURY,
            address(0xD157),
            address(token),
            address(0xdead)
        ];
        expectedBalance[address(this)] = SUPPLY;
        _move(address(this), MANAGER, SUPPLY * 9 / 10);
        _move(address(this), actors[6], SUPPLY / 10);
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 raw) external {
        address from = actors[fromSeed % actors.length];
        _move(from, actors[toSeed % actors.length], raw % (expectedBalance[from] + 1));
    }

    function buy(uint256 toSeed, uint256 raw) external {
        _move(MANAGER, actors[toSeed % actors.length], raw % (expectedBalance[MANAGER] + 1));
    }

    function sell(uint256 fromSeed, uint256 raw) external {
        address from = actors[fromSeed % actors.length];
        _move(from, MANAGER, raw % (expectedBalance[from] + 1));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 raw, bool unlimited) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 amount = unlimited ? type(uint256).max : raw % (SUPPLY + 1);
        vm.prank(owner);
        require(token.approve(spender, amount), "approval returned false");
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 raw) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        // Include one unit over the balance, and zero, to mix successes and failures.
        uint256 amount = raw % (expectedBalance[from] + 2);
        uint256 approved = expectedAllowance[from][spender];
        vm.prank(spender);
        (bool ok, bytes memory result) = address(token).call(abi.encodeCall(token.transferFrom, (from, to, amount)));
        if (amount > approved) {
            require(!ok, "unapproved gross transfer succeeded");
            require(
                keccak256(result)
                    == keccak256(
                        abi.encodeWithSelector(
                            MUSEGODToken.ERC20InsufficientAllowance.selector, spender, approved, amount
                        )
                    ),
                "wrong allowance failure"
            );
        } else if (amount > expectedBalance[from]) {
            require(!ok, "overdraw succeeded");
            require(
                keccak256(result)
                    == keccak256(
                        abi.encodeWithSelector(
                            MUSEGODToken.ERC20InsufficientBalance.selector, from, expectedBalance[from], amount
                        )
                    ),
                "wrong balance failure"
            );
        } else {
            require(ok && abi.decode(result, (bool)), "authorized transfer failed");
            if (approved != type(uint256).max) expectedAllowance[from][spender] -= amount;
            _record(from, to, amount);
        }
    }

    function rejectedTransfer(uint256 fromSeed, uint256 raw, bool zeroRecipient) external {
        address from = actors[fromSeed % actors.length];
        address to = zeroRecipient ? address(0) : actors[(fromSeed % actors.length + 1) % actors.length];
        uint256 amount = zeroRecipient ? raw % (expectedBalance[from] + 1) : expectedBalance[from] + 1;
        vm.prank(from);
        (bool ok, bytes memory result) = address(token).call(abi.encodeCall(token.transfer, (to, amount)));
        require(!ok, "invalid transfer succeeded");
        bytes memory expected = zeroRecipient
            ? abi.encodeWithSelector(MUSEGODToken.ERC20InvalidReceiver.selector, address(0))
            : abi.encodeWithSelector(
                MUSEGODToken.ERC20InsufficientBalance.selector, from, expectedBalance[from], amount
            );
        require(keccak256(result) == keccak256(expected), "wrong invalid-transfer failure");
    }

    function attemptSupplyChange(uint256 callerSeed, uint256 raw, bool minting) external {
        address caller = actors[callerSeed % actors.length];
        uint256 amount = raw % (expectedBalance[caller] + 1);
        bytes memory data = minting
            ? abi.encodeWithSignature("mint(address,uint256)", caller, amount)
            : abi.encodeWithSignature("burn(uint256)", amount);
        vm.prank(caller);
        (bool ok,) = address(token).call(data);
        require(!ok, "supply-changing entry point exists");
    }

    function _move(address from, address to, uint256 amount) private {
        vm.prank(from);
        require(token.transfer(to, amount), "bounded transfer returned false");
        _record(from, to, amount);
    }

    function _record(address from, address to, uint256 amount) private {
        uint256 fee = from == MANAGER ? amount / 50 : 0;
        expectedBalance[from] -= amount;
        expectedBalance[TREASURY] += fee;
        expectedBalance[to] += amount - fee;
        expectedFees += fee;
    }
}

/// @dev These two getters are Foundry's StdInvariant targeting ABI, implemented locally so
/// this suite uses only committed dependencies and needs no remapping/configuration changes.
contract MUSEGODInvariantTest {
    struct FuzzSelector {
        address addr;
        bytes4[] selectors;
    }
    MusegodTransferHandler private handler;
    MUSEGODToken private token;

    function setUp() public {
        handler = new MusegodTransferHandler();
        token = handler.token();
    }

    function targetContracts() public view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    function targetSelectors() public view returns (FuzzSelector[] memory targets) {
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.buy.selector;
        selectors[2] = handler.sell.selector;
        selectors[3] = handler.approve.selector;
        selectors[4] = handler.transferFrom.selector;
        selectors[5] = handler.rejectedTransfer.selector;
        selectors[6] = handler.attemptSupplyChange.selector;
        targets = new FuzzSelector[](1);
        targets[0] = FuzzSelector(address(handler), selectors);
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_ConservationFeesAndAuthorizations() public view {
        uint256 sum;
        for (uint256 i; i < 9; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            require(balance == handler.expectedBalance(actor), "balance differs from independent ledger");
            sum += balance;
            for (uint256 j; j < 9; ++j) {
                address spender = handler.actors(j);
                require(
                    token.allowance(actor, spender) == handler.expectedAllowance(actor, spender),
                    "allowance differs from independent ledger"
                );
            }
        }
        require(sum == 1e27 && token.totalSupply() == 1e27, "fixed supply not conserved");
        require(token.balanceOf(address(0)) == 0, "tokens burned to zero");
        require(token.totalFeesCollected() == handler.expectedFees(), "lifetime fees disagree");
        require(token.BUY_FEE_BPS() == 200 && token.BPS_DENOMINATOR() == 10_000, "fee changed");
        require(token.POOL_MANAGER() == 0x8366a39CC670B4001A1121B8F6A443A643e40951, "manager changed");
        require(token.TREASURY() == 0x9Cf1A7Cd2a2A423d7Df0D9663E0092423993389A, "treasury changed");
    }
}
