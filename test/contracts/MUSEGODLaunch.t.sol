// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {MUSEGODToken} from "src/MUSEGODToken.sol";
import {Vm} from "./MUSEGODToken.t.sol";
import {IMDTestToken, TestERC20} from "./UniswapV4.t.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {SqrtPriceMath} from "v4-core/src/libraries/SqrtPriceMath.sol";

/// @dev The production factory/distributor are not in this repository. This probe performs
/// their token allocations and v4 seed settlement; it does not implement Merkle verification.
contract MusegodEconomicLaunch is IUnlockCallback {
    address public constant IMD = 0x5F7Bb59365ce557C26dbcAa4EE9d39A4b95B7127;
    address public constant DISTRIBUTOR = address(0xD157);
    address public constant REMAINDER_TO = address(0xdead);
    IPoolManager public immutable manager;
    address private immutable controller;
    MUSEGODToken public token;
    PoolKey private key;
    uint256 public mintedToFactory;
    uint256 public seedSpent;
    uint256 public remainder;
    uint256 public liquidityUnitCost;
    uint160 public openingPrice;
    int24 private lower;
    int24 private upper;

    constructor(IPoolManager manager_) {
        manager = manager_;
        controller = msg.sender;
    }

    function poolKey() external view returns (PoolKey memory) {
        return key;
    }

    function deployAndLaunch(bytes32 salt) external {
        require(msg.sender == controller && address(token) == address(0), "launch not authorized");
        token = new MUSEGODToken{salt: salt}();
        mintedToFactory = token.balanceOf(address(this));
        require(mintedToFactory == 1e27 && token.totalSupply() == 1e27, "whole supply not minted to factory");
        bool token0 = address(token) < IMD;
        key = PoolKey(
            Currency.wrap(token0 ? address(token) : IMD),
            Currency.wrap(token0 ? IMD : address(token)),
            12500,
            60,
            IHooks(address(0))
        );
        // Market cap / supply, inverted when MUSEGOD sorts as currency1.
        uint256 ratioX192 =
            token0 ? FullMath.mulDiv(2500 ether, 1 << 192, 1e27) : FullMath.mulDiv(1e27, 1 << 192, 2500 ether);
        openingPrice = uint160(_sqrt(ratioX192));
        int24 tick = manager.initialize(key, openingPrice);
        int24 floorTick = tick / 60 * 60;
        if (tick < 0 && tick % 60 != 0) floorTick -= 60;
        lower = token0 ? floorTick + 60 : int24(-887220);
        upper = token0 ? int24(887220) : floorTick;
        require(token.transfer(DISTRIBUTOR, 1e26), "swarm transfer failed");
        manager.unlock("");
        remainder = token.balanceOf(address(this));
        if (remainder != 0) require(token.transfer(REMAINDER_TO, remainder), "remainder transfer failed");
    }

    function unlockCallback(bytes calldata) external returns (bytes memory) {
        require(msg.sender == address(manager), "only manager");
        bool token0 = Currency.unwrap(key.currency0) == address(token);
        uint160 a = TickMath.getSqrtPriceAtTick(lower);
        uint160 b = TickMath.getSqrtPriceAtTick(upper);
        uint256 budget = 9e26;
        uint256 liquidity = token0
            ? FullMath.mulDiv(budget, FullMath.mulDiv(a, b, 1 << 96), uint256(b) - a)
            : FullMath.mulDiv(budget, 1 << 96, uint256(b) - a);
        liquidityUnitCost =
            token0 ? SqrtPriceMath.getAmount0Delta(a, b, 1, true) : SqrtPriceMath.getAmount1Delta(a, b, 1, true);
        (BalanceDelta delta,) =
            manager.modifyLiquidity(key, ModifyLiquidityParams(lower, upper, int256(liquidity), bytes32(0)), "");
        int128 debt = token0 ? delta.amount0() : delta.amount1();
        require(debt < 0 && (token0 ? delta.amount1() : delta.amount0()) == 0, "seed not single sided");
        seedSpent = uint256(uint128(-debt));
        require(seedSpent <= budget, "over seed budget");
        manager.sync(Currency.wrap(address(token)));
        require(token.transfer(address(manager), seedSpent), "seed transfer failed");
        require(manager.settle() == seedSpent, "seed taxed");
        return "";
    }

    function _sqrt(uint256 n) private pure returns (uint256 result) {
        result = n;
        uint256 next = (n + 1) / 2;
        while (next < result) {
            result = next;
            next = (n / next + next) / 2;
        }
    }
}

/// @dev Separate from the factory and distributor. Each swap, take, sync and settle happens
/// inside one unlock transaction. Positive output is taken first to exercise rollback of fees.
contract MusegodIndependentTrader is IUnlockCallback {
    IPoolManager private immutable manager;
    PoolKey private key;

    constructor(IPoolManager manager_, PoolKey memory key_) {
        manager = manager_;
        key = key_;
    }

    function swap(bool zeroForOne, int256 amount, address recipient, uint256 underpay) external returns (BalanceDelta) {
        return abi.decode(manager.unlock(abi.encode(zeroForOne, amount, recipient, underpay)), (BalanceDelta));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager), "only manager");
        (bool zeroForOne, int256 amount, address recipient, uint256 underpay) =
            abi.decode(data, (bool, int256, address, uint256));
        uint160 limit = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        BalanceDelta delta = manager.swap(key, SwapParams(zeroForOne, amount, limit), "");
        if (delta.amount0() > 0) manager.take(key.currency0, recipient, uint128(delta.amount0()));
        if (delta.amount1() > 0) manager.take(key.currency1, recipient, uint128(delta.amount1()));
        if (delta.amount0() < 0) _pay(key.currency0, uint128(-delta.amount0()), underpay);
        if (delta.amount1() < 0) _pay(key.currency1, uint128(-delta.amount1()), underpay);
        if (underpay == 0) {
            // Read during the callback, before transient storage disappears at transaction end.
            require(
                manager.exttload(keccak256(abi.encode(address(this), key.currency0))) == bytes32(0),
                "currency0 unsettled"
            );
            require(
                manager.exttload(keccak256(abi.encode(address(this), key.currency1))) == bytes32(0),
                "currency1 unsettled"
            );
        }
        return abi.encode(delta);
    }

    function _pay(Currency currency, uint256 amount, uint256 underpay) private {
        uint256 paid = amount - underpay;
        manager.sync(currency);
        require(TestERC20(Currency.unwrap(currency)).transfer(address(manager), paid), "payment failed");
        require(manager.settle() == paid, "input taxed");
    }
}

contract MUSEGODLaunchTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address private constant MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address private constant IMD = 0x5F7Bb59365ce557C26dbcAa4EE9d39A4b95B7127;
    address private constant TREASURY = 0x9Cf1A7Cd2a2A423d7Df0D9663E0092423993389A;
    address private constant CLAIMANT = address(0xC1A1);
    MUSEGODToken private token;
    MusegodEconomicLaunch private factory;
    MusegodIndependentTrader private trader;
    IMDTestToken private pair;
    bool private buyZeroForOne;

    function test_LaunchAllocationAndSwarmClaimInBothCurrencyOrders() public {
        // Each call builds and seeds a distinct pool. The second deployment sees the same
        // manager's persistent state, just as two launches on the chain would.
        _installManager();
        _launch(true);
        _checkAllocationAndClaim();
        _launch(false);
        _checkAllocationAndClaim();
    }

    function testFuzz_IndependentTraderBuyAndSellAtLaunchPrice(uint96 raw, bool token0) public {
        _installManager();
        _launch(token0);
        uint256 input = uint256(raw) % 10 ether + 1e12;
        pair.mint(address(trader), input);
        uint256 poolBefore = token.balanceOf(MANAGER);
        BalanceDelta bought = trader.swap(buyZeroForOne, -int256(input), address(trader), 0);
        uint256 gross = _tokenOutput(bought);
        uint256 net = gross - gross / 50;
        require(gross > 0 && token.balanceOf(address(trader)) == net, "buy receipt wrong");
        require(token.balanceOf(TREASURY) == gross / 50, "buy fee not delivered");
        require(token.totalFeesCollected() == gross / 50, "buy fee not counted");
        require(token.balanceOf(MANAGER) == poolBefore - gross, "pool did not debit gross");
        require(pair.balanceOf(address(trader)) == 0 && pair.balanceOf(MANAGER) == input, "IMD input mismatch");

        BalanceDelta sold = trader.swap(!buyZeroForOne, -int256(net), address(trader), 0);
        int128 tokenDebt = buyZeroForOne ? sold.amount1() : sold.amount0();
        int128 pairOut = buyZeroForOne ? sold.amount0() : sold.amount1();
        require(tokenDebt == -int256(net) && pairOut > 0, "sell did not execute completely");
        require(token.balanceOf(address(trader)) == 0, "sell retained tokens");
        require(token.balanceOf(MANAGER) == poolBefore - gross / 50, "sell input arrived short");
        require(token.totalFeesCollected() == gross / 50, "sell charged a fee");
        require(pair.balanceOf(address(trader)) == uint128(pairOut), "sell proceeds wrong");
        require(token.totalSupply() == 1e27, "swap changed supply");
    }

    function test_ExactOutputBuyUsesGrossOutputAndFeesAccumulateForDifferentRecipients() public {
        _installManager();
        _launch(true);
        pair.mint(address(trader), 10 ether);
        uint256 gross = 1234 ether + 49;
        BalanceDelta first = trader.swap(buyZeroForOne, int256(gross), CLAIMANT, 0);
        require(_tokenOutput(first) == gross, "gross exact output wrong");
        require(token.balanceOf(CLAIMANT) == gross - gross / 50, "net exact output wrong");
        BalanceDelta second = trader.swap(buyZeroForOne, int256(gross + 1), address(trader), 0);
        require(_tokenOutput(second) == gross + 1, "second exact output wrong");
        require(token.balanceOf(address(trader)) == gross + 1 - (gross + 1) / 50, "second net wrong");
        uint256 fees = gross / 50 + (gross + 1) / 50;
        require(token.totalFeesCollected() == fees && token.balanceOf(TREASURY) == fees, "cumulative fees wrong");
        require(token.balanceOf(address(factory)) == 0, "factory received trader output");
    }

    function test_UnderpaidSwapRevertsFeeAndAllTransfersThenValidSwapStillWorks() public {
        _installManager();
        _launch(false);
        pair.mint(address(trader), 2 ether);
        // Nonzero preexisting fees ensure rollback does not just reset the counter to zero.
        trader.swap(buyZeroForOne, -int256(1 ether), address(trader), 0);
        uint256 poolBefore = token.balanceOf(MANAGER);
        uint256 traderBefore = token.balanceOf(address(trader));
        uint256 feesBefore = token.totalFeesCollected();
        require(feesBefore > 0, "setup charged no fee");
        vm.expectRevert(abi.encodeWithSelector(IPoolManager.CurrencyNotSettled.selector));
        trader.swap(buyZeroForOne, -int256(1 ether), address(trader), 1);
        require(
            token.balanceOf(MANAGER) == poolBefore && token.balanceOf(address(trader)) == traderBefore,
            "failed swap moved MUSEGOD"
        );
        require(
            token.totalFeesCollected() == feesBefore && token.balanceOf(TREASURY) == feesBefore,
            "failed swap retained fee"
        );
        require(
            pair.balanceOf(MANAGER) == 1 ether && pair.balanceOf(address(trader)) == 1 ether, "failed swap moved IMD"
        );
        trader.swap(buyZeroForOne, -int256(1 ether), address(trader), 0);
        require(token.totalFeesCollected() > feesBefore, "manager unusable after failed swap");
    }

    function test_ZeroSwapAndUnfundedSellFailWithoutChangingFees() public {
        _installManager();
        _launch(true);
        vm.expectRevert(abi.encodeWithSelector(IPoolManager.SwapAmountCannotBeZero.selector));
        trader.swap(buyZeroForOne, 0, address(trader), 0);
        pair.mint(address(trader), 1 ether);
        trader.swap(buyZeroForOne, -int256(1 ether), CLAIMANT, 0);
        uint256 feesBefore = token.totalFeesCollected();
        uint256 poolBefore = token.balanceOf(MANAGER);
        vm.expectRevert(
            abi.encodeWithSelector(
                MUSEGODToken.ERC20InsufficientBalance.selector, address(trader), uint256(0), uint256(1 ether)
            )
        );
        trader.swap(!buyZeroForOne, -int256(1 ether), address(trader), 0);
        require(
            token.totalFeesCollected() == feesBefore && token.balanceOf(MANAGER) == poolBefore,
            "unfunded sell changed fee or reserve"
        );
        require(pair.balanceOf(address(trader)) == 0, "failed sell kept its output");
    }

    function _installManager() private {
        // Execute creation code in place so NoDelegateCall's immutable original address is correct.
        vm.etch(MANAGER, abi.encodePacked(type(PoolManager).creationCode, abi.encode(address(this))));
        (bool ok, bytes memory runtime) = MANAGER.call("");
        require(ok && runtime.length > 0, "manager construction failed");
        vm.etch(MANAGER, runtime);
        vm.etch(IMD, address(new IMDTestToken()).code);
        pair = IMDTestToken(IMD);
    }

    function _launch(bool token0) private {
        factory = new MusegodEconomicLaunch(IPoolManager(MANAGER));
        bytes32 codeHash = keccak256(type(MUSEGODToken).creationCode);
        bool deployed;
        for (uint256 i; i < 1000; ++i) {
            bytes32 salt = bytes32(i);
            address predicted =
                address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(factory), salt, codeHash)))));
            if ((predicted < IMD) == token0) {
                factory.deployAndLaunch(salt);
                deployed = true;
                break;
            }
        }
        require(deployed, "could not select currency order");
        token = factory.token();
        PoolKey memory key = factory.poolKey();
        buyZeroForOne = Currency.unwrap(key.currency0) == IMD;
        require(buyZeroForOne != token0, "wrong test currency order");
        trader = new MusegodIndependentTrader(IPoolManager(MANAGER), key);
    }

    function _checkAllocationAndClaim() private {
        require(factory.mintedToFactory() == 1e27, "constructor pre-distributed supply");
        require(token.balanceOf(factory.DISTRIBUTOR()) == 1e26, "swarm arrived short");
        require(token.balanceOf(MANAGER) == factory.seedSpent(), "seed arrived short");
        require(factory.seedSpent() + factory.remainder() == 9e26, "90% allocation not accounted for");
        require(factory.remainder() <= factory.liquidityUnitCost(), "excess seed rounding remainder");
        require(token.balanceOf(factory.REMAINDER_TO()) == factory.remainder(), "remainder not forwarded");
        require(token.balanceOf(address(factory)) == 0, "factory retained allocation");
        require(token.totalFeesCollected() == 0 && token.balanceOf(TREASURY) == 0, "launch charged a fee");
        if (!buyZeroForOne) require(factory.openingPrice() == 125270724187523965593206900, "opening price mismatch");
        vm.prank(factory.DISTRIBUTOR());
        require(token.transfer(CLAIMANT, 1e26), "claim failed");
        require(token.balanceOf(CLAIMANT) == 1e26 && token.balanceOf(factory.DISTRIBUTOR()) == 0, "claim arrived short");
        require(token.totalSupply() == 1e27 && token.totalFeesCollected() == 0, "claim changed supply or fees");
    }

    function _tokenOutput(BalanceDelta delta) private view returns (uint256) {
        int128 output = buyZeroForOne ? delta.amount1() : delta.amount0();
        require(output > 0, "no token output");
        return uint128(output);
    }
}
