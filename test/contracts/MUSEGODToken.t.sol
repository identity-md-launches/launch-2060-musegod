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

    /// forge-config: default.fuzz.runs = 1000
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

    /// forge-config: default.fuzz.runs = 1000
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

    /// forge-config: default.fuzz.runs = 1000
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

    function test_NoAdminMintBurnOrUpgradeSurface() public {
        token.transfer(ALICE, 100e18);
        string[18] memory signatures = [
            "owner()",
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "setFee(uint256)",
            "setTreasury(address)",
            "pause()",
            "blacklist(address)",
            "seize(address)",
            "transferOwnership(address)",
            "renounceOwnership()",
            "upgradeTo(address)",
            "initialize(address)",
            "setMinter(address)",
            "setOwner(address)",
            "unpause()"
        ];
        for (uint256 i; i < signatures.length; i++) {
            (bool ok,) = address(token).call(abi.encodeWithSignature(signatures[i], ALICE, 1e27));
            require(!ok, signatures[i]);
            vm.prank(BOB);
            (ok,) = address(token).call(abi.encodeWithSignature(signatures[i], ALICE, 1e27));
            require(!ok, signatures[i]);
        }
        eq(token.totalSupply(), 1e27);
        eq(token.balanceOf(ALICE), 100e18);
        vm.prank(ALICE);
        token.transfer(BOB, 100e18);
        eq(token.balanceOf(BOB), 100e18);
        eq(token.BUY_FEE_BPS(), 200);
        eq(token.BPS_DENOMINATOR(), 10_000);
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
