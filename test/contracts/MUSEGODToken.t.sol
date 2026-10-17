// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {MUSEGODToken} from "../../src/MUSEGODToken.sol";

interface Vm {
    function prank(address) external;
    function startPrank(address) external;
    function stopPrank() external;
    function expectRevert() external;
    function expectRevert(bytes calldata) external;
    function etch(address, bytes calldata) external;
    function expectEmit(bool, bool, bool, bool) external;
}

contract MUSEGODTokenTest {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    MUSEGODToken token;
    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);
    address constant SPENDER = address(0x5EED);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        token = new MUSEGODToken();
    }

    function eq(uint256 a, uint256 b) internal pure {
        require(a == b, "values differ");
    }

    function test_ConstructorMintsWholeSupplyToDeployer() public view {
        eq(token.totalSupply(), 1e27);
        eq(token.balanceOf(address(this)), 1e27);
        eq(token.balanceOf(token.POOL_MANAGER()), 0);
        eq(token.balanceOf(token.TREASURY()), 0);
        eq(token.decimals(), 18);
        require(keccak256(bytes(token.name())) == keccak256("Musegod"));
        require(keccak256(bytes(token.symbol())) == keccak256("MUSEGOD"));
    }

    function test_FactorySeedAndSwarmClaimsAreUntaxed() public {
        uint256 pool = token.totalSupply() * 90 / 100;
        uint256 swarm = token.totalSupply() / 10;
        token.transfer(token.POOL_MANAGER(), pool);
        token.transfer(ALICE, swarm);
        vm.prank(ALICE);
        token.transfer(BOB, swarm);
        eq(token.balanceOf(token.POOL_MANAGER()), 900_000_000e18);
        eq(token.balanceOf(BOB), 100_000_000e18);
        eq(token.balanceOf(address(this)), 0);
        eq(token.totalFeesCollected(), 0);
    }

    function test_BuyPaysTreasuryAndEmitsNetTransfers() public {
        address manager = token.POOL_MANAGER();
        address treasury = token.TREASURY();
        token.transfer(manager, 100e18);
        vm.expectEmit(true, true, false, true);
        emit Transfer(manager, treasury, 2e18);
        vm.expectEmit(true, true, false, true);
        emit Transfer(manager, ALICE, 98e18);
        vm.prank(manager);
        require(token.transfer(ALICE, 100e18));
        eq(token.balanceOf(ALICE), 98e18);
        eq(token.balanceOf(treasury), 2e18);
        eq(token.balanceOf(manager), 0);
        eq(token.totalFeesCollected(), 2e18);
        vm.prank(ALICE);
        token.transfer(manager, 98e18);
        eq(token.balanceOf(manager), 98e18);
        eq(token.totalFeesCollected(), 2e18);
    }

    function testFuzz_BuyFeeConservationAndRoundDown(uint256 raw) public {
        uint256 amount = raw % (1e27 + 1);
        address manager = token.POOL_MANAGER();
        token.transfer(manager, amount);
        vm.prank(manager);
        token.transfer(ALICE, amount);
        uint256 fee = token.balanceOf(token.TREASURY());
        eq(token.balanceOf(ALICE) + fee, amount);
        eq(fee, amount / 50);
        eq(token.totalFeesCollected(), fee);
        eq(token.totalSupply(), 1e27);
        eq(token.balanceOf(address(this)) + token.balanceOf(ALICE) + fee, 1e27);
    }

    function testFuzz_DelegatedBuyCannotBypassFee(uint256 raw) public {
        uint256 amount = raw % (1e27 + 1);
        address manager = token.POOL_MANAGER();
        token.transfer(manager, amount);
        vm.prank(manager);
        token.approve(SPENDER, amount);
        vm.prank(SPENDER);
        token.transferFrom(manager, ALICE, amount);
        eq(token.balanceOf(ALICE), amount - amount / 50);
        eq(token.allowance(manager, SPENDER), 0);
        eq(token.totalFeesCollected(), amount / 50);
    }

    function testFuzz_WalletTransfersAndSellsRemainWhole(uint256 raw) public {
        uint256 amount = raw % (1e27 + 1);
        token.transfer(ALICE, amount);
        vm.prank(ALICE);
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);
        eq(token.balanceOf(BOB), amount);
        eq(token.allowance(ALICE, SPENDER), type(uint256).max);
        address manager = token.POOL_MANAGER();
        vm.prank(BOB);
        token.transfer(manager, amount);
        eq(token.balanceOf(token.POOL_MANAGER()), amount);
        eq(token.totalFeesCollected(), 0);
    }

    function test_MultipleBuysAccumulateAndDustIsNotCharged() public {
        address manager = token.POOL_MANAGER();
        token.transfer(manager, 10001);
        vm.startPrank(manager);
        token.transfer(ALICE, 49);
        eq(token.totalFeesCollected(), 0);
        token.transfer(ALICE, 50);
        eq(token.totalFeesCollected(), 1);
        token.transfer(ALICE, 9902);
        eq(token.totalFeesCollected(), 199);
        vm.stopPrank();
        eq(token.balanceOf(ALICE), 9802);
    }

    function test_SelfAndTreasuryTransfersConserveSupply() public {
        token.transfer(ALICE, 100e18);
        vm.prank(ALICE);
        token.transfer(ALICE, 100e18);
        eq(token.balanceOf(ALICE), 100e18);
        address manager = token.POOL_MANAGER();
        token.transfer(manager, 100e18);
        vm.prank(manager);
        token.transfer(manager, 100e18);
        eq(token.balanceOf(manager), 98e18);
        eq(token.totalFeesCollected(), 2e18);
        address treasury = token.TREASURY();
        vm.prank(manager);
        token.transfer(treasury, 50e18);
        eq(token.balanceOf(token.TREASURY()), 52e18);
        eq(token.totalFeesCollected(), 3e18);
        eq(token.totalSupply(), 1e27);
    }

    function test_RevertsAreAtomicAndZeroTransfersWork() public {
        token.transfer(ALICE, 20);
        vm.prank(ALICE);
        token.approve(SPENDER, 21);
        vm.expectRevert();
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 21);
        eq(token.allowance(ALICE, SPENDER), 21);
        eq(token.balanceOf(ALICE), 20);
        vm.expectRevert();
        token.transfer(address(0), 1);
        vm.expectRevert();
        token.approve(address(0), 1);
        vm.expectRevert();
        vm.prank(BOB);
        token.transferFrom(ALICE, BOB, 1);
        vm.expectRevert();
        vm.prank(SPENDER);
        token.transferFrom(address(0), BOB, 0);
        vm.prank(BOB);
        require(token.transfer(ALICE, 0));
        eq(token.totalSupply(), 1e27);
    }

    function test_RejectedBuysPreserveBalancesFeesAndAllowance() public {
        address manager = token.POOL_MANAGER();
        address treasury = token.TREASURY();
        token.transfer(manager, 100e18);
        vm.prank(manager);
        token.approve(SPENDER, 101e18);

        vm.expectRevert(abi.encodeWithSelector(MUSEGODToken.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(manager, address(0), 100e18);
        eq(token.allowance(manager, SPENDER), 101e18);

        vm.expectRevert(abi.encodeWithSelector(MUSEGODToken.ERC20InsufficientBalance.selector, manager, 100e18, 101e18));
        vm.prank(SPENDER);
        token.transferFrom(manager, ALICE, 101e18);
        eq(token.allowance(manager, SPENDER), 101e18);

        // Approving only the net receipt must not authorize a larger gross debit.
        vm.prank(manager);
        token.approve(SPENDER, 98e18);
        vm.expectRevert(
            abi.encodeWithSelector(MUSEGODToken.ERC20InsufficientAllowance.selector, SPENDER, 98e18, 100e18)
        );
        vm.prank(SPENDER);
        token.transferFrom(manager, ALICE, 100e18);
        eq(token.allowance(manager, SPENDER), 98e18);
        eq(token.balanceOf(manager), 100e18);
        eq(token.balanceOf(ALICE), 0);
        eq(token.balanceOf(treasury), 0);
        eq(token.totalFeesCollected(), 0);

        // A valid approval still permits the full buy after each rejected attempt.
        vm.prank(manager);
        token.approve(SPENDER, 100e18);
        vm.prank(SPENDER);
        require(token.transferFrom(manager, ALICE, 100e18));
        eq(token.allowance(manager, SPENDER), 0);
        eq(token.balanceOf(manager), 0);
        eq(token.balanceOf(ALICE), 98e18);
        eq(token.balanceOf(treasury), 2e18);
        eq(token.totalFeesCollected(), 2e18);
        eq(token.totalSupply(), 1e27);
    }

    function test_TreasurySpendingDoesNotReduceCumulativeFees() public {
        address manager = token.POOL_MANAGER();
        address treasury = token.TREASURY();
        token.transfer(manager, 150e18);
        vm.prank(manager);
        token.transfer(ALICE, 100e18);

        vm.prank(treasury);
        token.transfer(BOB, 2e18);
        eq(token.balanceOf(treasury), 0);
        eq(token.balanceOf(BOB), 2e18);
        eq(token.totalFeesCollected(), 2e18);

        vm.prank(manager);
        token.transfer(ALICE, 50e18);
        eq(token.balanceOf(treasury), 1e18);
        eq(token.balanceOf(ALICE), 147e18);
        eq(token.totalFeesCollected(), 3e18);
        eq(token.totalSupply(), 1e27);
    }

    function test_NoAdminMintBurnOrUpgradeSurface() public {
        token.transfer(ALICE, 100e18);
        address manager = token.POOL_MANAGER();
        address treasury = token.TREASURY();
        token.transfer(manager, 10e18);
        token.transfer(treasury, 10e18);
        // Encode each signature with its actual arguments. An address supplied as a burn
        // amount would merely test an overdraw and could miss a real burn entry point.
        bytes[26] memory calls = [
            abi.encodeWithSignature("owner()"),
            abi.encodeWithSignature("mint(address,uint256)", ALICE, 1e18),
            abi.encodeWithSignature("mint(uint256)", 1e18),
            abi.encodeWithSignature("mint()"),
            abi.encodeWithSignature("burn(uint256)", 1e18),
            abi.encodeWithSignature("burnFrom(address,uint256)", ALICE, 1e18),
            abi.encodeWithSignature("setFee(uint256)", 1),
            abi.encodeWithSignature("setTreasury(address)", BOB),
            abi.encodeWithSignature("pause()"),
            abi.encodeWithSignature("blacklist(address)", ALICE),
            abi.encodeWithSignature("seize(address)", ALICE),
            abi.encodeWithSignature("transferOwnership(address)", BOB),
            abi.encodeWithSignature("renounceOwnership()"),
            abi.encodeWithSignature("upgradeTo(address)", BOB),
            abi.encodeWithSignature("initialize(address)", BOB),
            abi.encodeWithSignature("setMinter(address)", BOB),
            abi.encodeWithSignature("setOwner(address)", BOB),
            abi.encodeWithSignature("unpause()"),
            abi.encodeWithSignature("setBuyFeeBps(uint256)", 1),
            abi.encodeWithSignature("setPoolManager(address)", BOB),
            abi.encodeWithSignature("grantRole(bytes32,address)", bytes32(0), BOB),
            abi.encodeWithSignature("initialize()"),
            abi.encodeWithSignature("setFeeExempt(address,bool)", ALICE, true),
            abi.encodeWithSignature("mintTo(address,uint256)", ALICE, 1e18),
            abi.encodeWithSignature("burn(address,uint256)", ALICE, 1e18),
            abi.encodeWithSignature("setTransfersEnabled(bool)", false)
        ];
        address[5] memory callers = [address(this), ALICE, BOB, manager, treasury];
        for (uint256 c; c < callers.length; ++c) {
            // A hypothetical burnFrom must not fail just because its allowance was absent.
            vm.prank(ALICE);
            token.approve(callers[c], 1e18);
            for (uint256 i; i < calls.length; ++i) {
                vm.prank(callers[c]);
                (bool ok,) = address(token).call(calls[i]);
                require(!ok, "admin/mint/burn entry point exists");
                eq(token.totalSupply(), 1e27);
                eq(token.balanceOf(ALICE), 100e18);
                eq(token.balanceOf(manager), 10e18);
                eq(token.balanceOf(treasury), 10e18);
            }
        }
        vm.prank(ALICE);
        token.transfer(BOB, 100e18);
        eq(token.balanceOf(BOB), 100e18);
        eq(token.TOTAL_SUPPLY(), 1e27);
        eq(token.BUY_FEE_BPS(), 200);
        eq(token.BPS_DENOMINATOR(), 10_000);
        require(token.POOL_MANAGER() == 0x8366a39CC670B4001A1121B8F6A443A643e40951, "wrong pool manager");
        require(token.TREASURY() == 0x9Cf1A7Cd2a2A423d7Df0D9663E0092423993389A, "wrong treasury");
        eq(token.totalFeesCollected(), 0);
    }

    function testFuzz_PoolManagerAsSpenderDoesNotTaxUserFunds(uint256 raw) public {
        uint256 amount = raw % (1e27 + 1);
        address manager = token.POOL_MANAGER();
        token.transfer(ALICE, amount);
        vm.prank(ALICE);
        token.approve(manager, amount);
        vm.prank(manager);
        require(token.transferFrom(ALICE, BOB, amount));
        eq(token.balanceOf(ALICE), 0);
        eq(token.balanceOf(BOB), amount);
        eq(token.allowance(ALICE, manager), 0);
        eq(token.totalFeesCollected(), 0);
        eq(token.balanceOf(token.TREASURY()), 0);
    }

    function testFuzz_OverdrawnDelegatedBuyRevertsWithoutSpendingAllowance(uint256 raw) public {
        uint256 held = raw % (1e27 + 1);
        address manager = token.POOL_MANAGER();
        token.transfer(manager, held);
        vm.prank(manager);
        token.approve(SPENDER, held + 1);
        vm.expectRevert(abi.encodeWithSelector(MUSEGODToken.ERC20InsufficientBalance.selector, manager, held, held + 1));
        vm.prank(SPENDER);
        token.transferFrom(manager, ALICE, held + 1);
        eq(token.allowance(manager, SPENDER), held + 1);
        eq(token.balanceOf(manager), held);
        eq(token.balanceOf(ALICE), 0);
        eq(token.balanceOf(token.TREASURY()), 0);
        eq(token.totalFeesCollected(), 0);
        eq(token.totalSupply(), 1e27);
    }

    function test_MaximumTransferFailsBeforeFeeMultiplication() public {
        address manager = token.POOL_MANAGER();
        token.transfer(manager, 1e27);
        vm.prank(manager);
        token.approve(SPENDER, type(uint256).max);
        bytes memory expected = abi.encodeWithSelector(
            MUSEGODToken.ERC20InsufficientBalance.selector, manager, uint256(1e27), type(uint256).max
        );
        vm.expectRevert(expected);
        vm.prank(manager);
        token.transfer(ALICE, type(uint256).max);
        vm.expectRevert(expected);
        vm.prank(SPENDER);
        token.transferFrom(manager, ALICE, type(uint256).max);
        eq(token.allowance(manager, SPENDER), type(uint256).max);
        eq(token.balanceOf(manager), 1e27);
        eq(token.balanceOf(ALICE), 0);
        eq(token.balanceOf(token.TREASURY()), 0);
        eq(token.totalFeesCollected(), 0);
    }

    function test_ApprovalOverwriteRevocationAndGrossPartialSpends() public {
        address manager = token.POOL_MANAGER();
        token.transfer(manager, 100e18);
        vm.prank(manager);
        token.approve(SPENDER, type(uint256).max);
        vm.prank(manager);
        token.approve(SPENDER, 60e18);
        vm.prank(SPENDER);
        require(token.transferFrom(manager, ALICE, 40e18));
        eq(token.allowance(manager, SPENDER), 20e18);
        eq(token.balanceOf(ALICE), 392e17);
        vm.prank(manager);
        token.approve(SPENDER, 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                MUSEGODToken.ERC20InsufficientAllowance.selector, SPENDER, uint256(0), uint256(20e18)
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(manager, ALICE, 20e18);
        eq(token.allowance(manager, SPENDER), 0);
        eq(token.balanceOf(manager), 60e18);
        eq(token.totalFeesCollected(), 8e17);
        eq(token.balanceOf(token.TREASURY()), 8e17);
    }

    function test_ZeroBuysAndZeroDelegatedBuysWorkWithoutBalanceOrApproval() public {
        address manager = token.POOL_MANAGER();
        vm.prank(manager);
        require(token.transfer(ALICE, 0));
        vm.prank(SPENDER);
        require(token.transferFrom(manager, ALICE, 0));
        eq(token.balanceOf(manager), 0);
        eq(token.balanceOf(ALICE), 0);
        eq(token.balanceOf(token.TREASURY()), 0);
        eq(token.totalFeesCollected(), 0);
        eq(token.allowance(manager, SPENDER), 0);
        eq(token.totalSupply(), 1e27);
    }

    function test_ZeroAddressFailuresCannotBurnEvenZeroTokens() public {
        address manager = token.POOL_MANAGER();
        token.transfer(manager, 100e18);
        vm.prank(manager);
        token.approve(SPENDER, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(MUSEGODToken.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(manager);
        token.transfer(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(MUSEGODToken.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(manager, address(0), 100e18);
        vm.expectRevert(abi.encodeWithSelector(MUSEGODToken.ERC20InvalidSender.selector, address(0)));
        token.transferFrom(address(0), ALICE, 0);
        vm.expectRevert(abi.encodeWithSelector(MUSEGODToken.ERC20InvalidSpender.selector, address(0)));
        vm.prank(manager);
        token.approve(address(0), 0);
        eq(token.allowance(manager, SPENDER), type(uint256).max);
        eq(token.balanceOf(manager), 100e18);
        eq(token.balanceOf(address(0)), 0);
        eq(token.balanceOf(token.TREASURY()), 0);
        eq(token.totalFeesCollected(), 0);
        eq(token.totalSupply(), 1e27);
    }

    function test_TokenAndRemainderAddressHoldingsDoNotReduceSupply() public {
        token.transfer(address(token), 12e18);
        token.transfer(address(0xdead), 34e18);
        eq(token.balanceOf(address(token)), 12e18);
        eq(token.balanceOf(address(0xdead)), 34e18);
        eq(token.balanceOf(address(this)) + token.balanceOf(address(token)) + token.balanceOf(address(0xdead)), 1e27);
        eq(token.totalSupply(), 1e27);
        eq(token.totalFeesCollected(), 0);
    }

    function test_AnyoneCanReadLifetimeFeesAfterTreasurySpendsThem() public {
        address manager = token.POOL_MANAGER();
        address treasury = token.TREASURY();
        token.transfer(manager, 100e18);
        vm.prank(manager);
        token.transfer(ALICE, 100e18);
        vm.prank(treasury);
        token.transfer(BOB, 2e18);
        address[5] memory readers = [address(this), ALICE, BOB, SPENDER, manager];
        for (uint256 i; i < readers.length; ++i) {
            vm.prank(readers[i]);
            (bool ok, bytes memory result) = address(token).staticcall(abi.encodeWithSignature("totalFeesCollected()"));
            require(ok && abi.decode(result, (uint256)) == 2e18, "fee view not public or not cumulative");
        }
        eq(token.balanceOf(treasury), 0);
    }

    function test_RuntimeContainsNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        for (uint256 i; i < runtime.length; i++) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            require(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden opcode");
        }
    }
}
