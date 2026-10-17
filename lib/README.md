# Test-only protocol dependencies

`v4-core/` contains only the recursive Solidity import closure of `PoolManager.sol` from the npm package `@uniswap/v4-core@1.0.2`, including its pinned Solmate `Owned.sol`. Upstream SPDX notices and license files are retained. These files are used by the offline integration tests. MUSEGODToken has no imports or library links and no dependency code is deployed by the launch.

Source: https://github.com/Uniswap/v4-core/tree/v1.0.2
