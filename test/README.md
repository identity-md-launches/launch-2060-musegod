# MUSEGOD tests

Run from the repository root:

```sh
forge build
FOUNDRY_FUZZ_SEED=0xcbe78dd7537d113d4c5e2cad22f24bec31dae7b994193050f1ff75527aeddb36 forge test
```

All imports resolve to files already in the repository. Tests need no network, RPC,
environment changes, or additional packages. Fuzz tests use Foundry's default run
count. The invariant test uses 64 sequences of 64 calls, with unexpected handler
reverts treated as failures.

| File | Coverage |
| --- | --- |
| `contracts/MUSEGODToken.t.sol` | Whole constructor supply and metadata; exact 2% buy fees and events; rounding; untaxed sells and wallet transfers; sender-based delegated fees; finite/infinite allowances and revocation; atomic failures; public cumulative fee accounting after treasury spending; correctly encoded admin/mint/burn attempts; forbidden runtime opcodes. |
| `contracts/MUSEGODInvariant.t.sol` | Independent balance, allowance and fee ledger over random buys, sells, transfers, self-transfers, approvals, delegated transfers and rejected calls. Checks conservation of all 1e27 units, immutable parameters, and lifetime fees, including treasury spending and contract-held balances. |
| `contracts/UniswapV4.t.sol` | Existing real-v4 seed/buy/sell smoke tests and fuzz round trips, plus the documented limit that swaps settled as PoolManager ERC-6909 claims pay no fee until the claim is redeemed as an ERC-20 transfer (which is taxed). |
| `contracts/MUSEGODLaunch.t.sol` | Single-sided 90% factory seed, 10% distributor allocation and claim transfer, rounding remainder, 2500 IMD opening capitalization, both currency orders, separate trader, exact-input and gross exact-output buys, untaxed sells, and rollback after failed settlement. |

The integration tests execute the committed Uniswap v4 PoolManager implementation
at the specified PoolManager address. Its constructor runs in place to preserve
the original-address check. Swap accounting and settlement occur inside one
unlock callback, including checks of currency deltas before transient storage is
cleared. Fees apply to the gross token output; recipients receive that output less
the token fee.

The production ProjectFactory and Merkle distributor are not present here. Test
helpers reproduce their allocation and ERC-20 transfer flows; they do not verify
the production factory's orchestration or Merkle proofs. Liquidity is integral, so
the 90% budget is checked as actual seed plus a remainder bounded by the cost of
one liquidity unit. The remainder is sent to the specified remainder address.

IMD is represented by an ordinary local ERC-20 transfer probe at the specified
address. Live Robinhood Chain bytecode/state and swaps against the deployed IMD,
PoolManager, factory and distributor remain unverified by this offline suite.
