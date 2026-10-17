// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {MUSEGODToken} from "../../src/MUSEGODToken.sol";
import {Vm} from "./MUSEGODToken.t.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";

interface TestERC20 {
    function transfer(address, uint256) external returns (bool);
}

/// @dev IMD's transfer behavior only; no network or claim about live chain state.
contract IMDTestToken {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 value) external {
        balanceOf[to] += value;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        return true;
    }
}

/// @dev Isolated test factory/router. Not deployed by launch.json.
contract V4LaunchHarness is IUnlockCallback {
    using BalanceDeltaLibrary for BalanceDelta;
    IPoolManager public immutable manager;
    MUSEGODToken public immutable token;
    PoolKey public key;
    uint256 public seedSpent;
    address public constant DISTRIBUTOR = address(0xD157);

    constructor(IPoolManager manager_, address paired) {
        manager = manager_;
        token = new MUSEGODToken();
        bool token0 = address(token) < paired;
        key = PoolKey(
            Currency.wrap(token0 ? address(token) : paired),
            Currency.wrap(token0 ? paired : address(token)),
            12500,
            60,
            IHooks(address(0))
        );
    }

    function launch() external {
        require(seedSpent == 0, "already seeded");
        uint256 supply = token.totalSupply();
        require(token.balanceOf(address(this)) == supply, "constructor distributed supply");
        token.transfer(DISTRIBUTOR, supply / 10);
        manager.initialize(key, uint160(1 << 96));
        manager.unlock(abi.encode(uint8(0), false, int256(0)));
        uint256 left = token.balanceOf(address(this));
        if (left != 0) token.transfer(address(0xdead), left);
    }

    function swap(bool zeroForOne, int256 amount) external returns (BalanceDelta) {
        return abi.decode(manager.unlock(abi.encode(uint8(1), zeroForOne, amount)), (BalanceDelta));
    }

    function redeem(uint256 amount) external {
        manager.unlock(abi.encode(uint8(3), false, int256(amount)));
    }

    /// @dev Swap whose MUSEGOD leg is settled as ERC-6909 claims (mint/burn) instead of ERC-20 take/settle.
    function swapWithClaims(bool zeroForOne, int256 amount) external returns (BalanceDelta) {
        return abi.decode(manager.unlock(abi.encode(uint8(2), zeroForOne, amount)), (BalanceDelta));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager), "only manager");
        (uint8 mode, bool zeroForOne, int256 amount) = abi.decode(data, (uint8, bool, int256));
        BalanceDelta delta;
        if (mode == 3) {
            manager.burn(address(this), uint256(uint160(address(token))), uint256(amount));
            manager.take(Currency.wrap(address(token)), address(this), uint256(amount));
            return "";
        }
        if (mode == 0) {
            bool token0 = Currency.unwrap(key.currency0) == address(token);
            int24 lower = token0 ? int24(60) : int24(-887220);
            int24 upper = token0 ? int24(887220) : int24(-60);
            uint160 a = TickMath.getSqrtPriceAtTick(lower);
            uint160 b = TickMath.getSqrtPriceAtTick(upper);
            uint256 budget = token.totalSupply() * 9 / 10;
            uint256 liquidity = token0
                ? FullMath.mulDiv(budget, FullMath.mulDiv(a, b, 1 << 96), uint256(b) - a)
                : FullMath.mulDiv(budget, 1 << 96, uint256(b) - a);
            (delta,) =
                manager.modifyLiquidity(key, ModifyLiquidityParams(lower, upper, int256(liquidity), bytes32(0)), "");
            seedSpent = uint256(uint128(-(token0 ? delta.amount0() : delta.amount1())));
        } else {
            uint160 limit = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
            delta = manager.swap(key, SwapParams(zeroForOne, amount, limit), "");
        }
        settle(key.currency0, delta.amount0(), mode == 2);
        settle(key.currency1, delta.amount1(), mode == 2);
        return abi.encode(delta);
    }

    function settle(Currency currency, int128 delta, bool claims) private {
        if (claims && Currency.unwrap(currency) == address(token)) {
            uint256 id = uint256(uint160(address(token)));
            if (delta < 0) manager.burn(address(this), id, uint256(uint128(-delta)));
            else if (delta > 0) manager.mint(address(this), id, uint256(uint128(delta)));
        } else if (delta < 0) {
            manager.sync(currency);
            require(TestERC20(Currency.unwrap(currency)).transfer(address(manager), uint256(uint128(-delta))));
            require(manager.settle() == uint256(uint128(-delta)), "input arrived short");
        } else if (delta > 0) {
            manager.take(currency, address(this), uint256(uint128(delta)));
        }
    }
}

contract UniswapV4Test {
    using BalanceDeltaLibrary for BalanceDelta;
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address constant MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address constant IMD = 0x5F7Bb59365ce557C26dbcAa4EE9d39A4b95B7127;
    V4LaunchHarness factory;
    MUSEGODToken token;
    IMDTestToken paired;

    function setUp() public {
        // Run v4's real constructor at its configured address. Etching deployed runtime
        // would violate the manager's immutable original-address check.
        vm.etch(MANAGER, abi.encodePacked(type(PoolManager).creationCode, abi.encode(address(this))));
        (bool ok, bytes memory runtime) = MANAGER.call("");
        require(ok && runtime.length > 0, "manager constructor");
        vm.etch(MANAGER, runtime);
        IMDTestToken implementation = new IMDTestToken();
        vm.etch(IMD, address(implementation).code);
        paired = IMDTestToken(IMD);
        factory = new V4LaunchHarness(IPoolManager(MANAGER), IMD);
        token = factory.token();
        factory.launch();
    }

    function test_RealV4SingleSidedSeedBuyAndSell() public {
        require(token.balanceOf(factory.DISTRIBUTOR()) == 100_000_000e18, "swarm short");
        require(factory.seedSpent() <= 900_000_000e18 && factory.seedSpent() > 899_999_999e18, "90% seed budget");
        require(token.balanceOf(MANAGER) == factory.seedSpent(), "seed arrived short");
        require(token.totalFeesCollected() == 0, "seed taxed");
        (Currency currency0,,,,) = factory.key();
        bool buyZeroForOne = Currency.unwrap(currency0) == IMD;
        paired.mint(address(factory), 10e18);
        BalanceDelta bought = factory.swap(buyZeroForOne, -int256(1e18));
        uint256 gross = uint256(uint128(buyZeroForOne ? bought.amount1() : bought.amount0()));
        uint256 net = token.balanceOf(address(factory));
        require(net == gross - gross / 50 && net > 0, "buy net/fee wrong");
        require(token.balanceOf(token.TREASURY()) == gross / 50, "treasury short");
        uint256 fees = token.totalFeesCollected();
        uint256 beforePair = paired.balanceOf(address(factory));
        factory.swap(!buyZeroForOne, -int256(net));
        require(token.balanceOf(address(factory)) == 0, "sell retained tokens");
        require(paired.balanceOf(address(factory)) > beforePair, "sell paid no IMD");
        require(token.totalFeesCollected() == fees, "sell taxed");
        require(token.totalSupply() == 1e27, "supply changed");
    }

    function testFuzz_RealV4BuySellSettles(uint64 raw) public {
        (Currency currency0,,,,) = factory.key();
        bool buyZeroForOne = Currency.unwrap(currency0) == IMD;
        uint256 amount = uint256(raw) % 10e18 + 1e12;
        paired.mint(address(factory), amount);
        factory.swap(buyZeroForOne, -int256(amount));
        uint256 net = token.balanceOf(address(factory));
        require(net > 0, "buy empty");
        uint256 fees = token.totalFeesCollected();
        factory.swap(!buyZeroForOne, -int256(net));
        require(token.balanceOf(address(factory)) == 0, "sell failed");
        require(token.totalFeesCollected() == fees, "sell taxed");
        require(token.totalSupply() == 1e27, "supply changed");
    }

    /// @dev Documents a known limit: the token only sees ERC-20 transfers, so a buy whose output
    /// is kept as a PoolManager ERC-6909 claim (and a sell paid by burning that claim) pays no fee.
    function test_ClaimSettledSwapsAreUntaxedKnownLimit() public {
        (Currency currency0,,,,) = factory.key();
        bool buyZeroForOne = Currency.unwrap(currency0) == IMD;
        uint256 id = uint256(uint160(address(token)));
        uint256 managerBefore = token.balanceOf(MANAGER);
        paired.mint(address(factory), 1e18);
        BalanceDelta bought = factory.swapWithClaims(buyZeroForOne, -int256(1e18));
        uint256 gross = uint256(uint128(buyZeroForOne ? bought.amount1() : bought.amount0()));
        require(gross > 0, "buy empty");
        require(IPoolManager(MANAGER).balanceOf(address(factory), id) == gross, "claim not minted");
        require(token.balanceOf(address(factory)) == 0, "erc20 delivered");
        require(token.balanceOf(MANAGER) == managerBefore, "manager balance moved");
        require(token.totalFeesCollected() == 0 && token.balanceOf(token.TREASURY()) == 0, "claim buy taxed");
        uint256 beforePair = paired.balanceOf(address(factory));
        factory.swapWithClaims(!buyZeroForOne, -int256(gross));
        require(IPoolManager(MANAGER).balanceOf(address(factory), id) == 0, "claim not burned");
        require(paired.balanceOf(address(factory)) > beforePair, "sell paid no IMD");
        require(token.totalFeesCollected() == 0, "claim sell taxed");
        // Redeeming a claim later is an ERC-20 outflow and does pay the fee.
        paired.mint(address(factory), 1e18);
        bought = factory.swapWithClaims(buyZeroForOne, -int256(1e18));
        gross = uint256(uint128(buyZeroForOne ? bought.amount1() : bought.amount0()));
        factory.redeem(gross);
        require(token.totalFeesCollected() == gross / 50, "redeemed claim untaxed");
        require(token.balanceOf(address(factory)) == gross - gross / 50, "redeem net wrong");
    }
}
