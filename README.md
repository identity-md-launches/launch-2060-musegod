# Musegod ($MUSEGOD)

A fixed-supply token and a complete static website for the plush mascot of swarm memes on Robinhood Chain. The deployable contract is `src/MUSEGODToken.sol`; the website source is `site/`, with the finished, identical static export in `dist/`.

## Preview and export

The site is ordinary HTML, CSS and JavaScript. It requires no compilation, bundler, framework, backend or runtime package dependencies. Fonts, the supplied logo, SVG illustrations and all eight PNG meme downloads are local.

With Node.js 20 or later:

```sh
npm run build
npm run preview
```

Open `http://127.0.0.1:4173/preview/`. `build` only copies `site/` to `dist/`; editing `site/` also works with any static file server. Publish the contents of `dist/`. Pages are real exported folders, and asset/navigation URLs are relative, including when served under a gateway subpath.

The preview supplies an empty `/simd-coin.json` object. The publishing service supplies real metadata at that same-origin endpoint. No deployment address is fabricated: the site shows **launching…**, disables contract copying, hides unavailable market data and chart links, and uses the buying guide until live URLs arrive. Market values refresh every 30 seconds while the tab is visible. A failed refresh hides stale stats and offers retry. The `logo` field overrides the hero's local fallback.

Routes: `/`, `/docs/`, `/docs/how-it-works/`, `/docs/tokenomics/`, `/docs/contracts/`, `/docs/faq/`, `/tokenomics/`, `/faq/`, and `/404.html`.

## Install verification tools outside the repository

No `node_modules` directory or package cache is needed in this repository. The manifest and lockfile pin development tools only. To reproduce the checks without adding generated dependency directories to the submission:

```sh
MUSEGOD_TOOLS="$(mktemp -d /tmp/musegod-tools.XXXXXX)"
cp package.json package-lock.json "$MUSEGOD_TOOLS/"
npm ci --prefix "$MUSEGOD_TOOLS" --cache "$MUSEGOD_TOOLS/cache"
export PATH="$MUSEGOD_TOOLS/node_modules/.bin:$PATH"
export IMD_PLAYWRIGHT="$MUSEGOD_TOOLS/node_modules/playwright/index.mjs"
export MUSEGOD_AXE="$MUSEGOD_TOOLS/node_modules/@axe-core/playwright/dist/index.mjs"
export PLAYWRIGHT_BROWSERS_PATH="$MUSEGOD_TOOLS/browsers"
playwright install chromium
npm run build
npm run typecheck
npm run check
npm run test:site
node scripts/budget.mjs
```

`typecheck` performs strict TypeScript checking of the JavaScript source through its JSDoc annotations (`checkJs`, `noEmit`). `check` verifies all local HTML references, required metadata, one H1 per page, export parity, PNG signatures, JavaScript syntax and launch manifest values. `test:site` owns and closes its local preview/browser; it visits every page at 375px and 1440px, runs axe accessibility checks, exercises the primary interactions and tests data states using clearly isolated browser fixtures. It also checks home reflow at 320, 360, 390, 768, 850, 1150, 1440 and 1920px. Its 30-second refresh test uses an accelerated clock, not a real-time wait.

The committed PNGs need no regeneration for normal exports. To re-render them after editing their original SVG compositions:

```sh
MUSEGOD_SHARP="$MUSEGOD_TOOLS/node_modules/sharp/dist/index.mjs" node scripts/render-memes.mjs
npm run build
```

No canvas, 3D library or image-generation service is used by the site. PNG rendering is an optional offline authoring step. The retrieved full brief specified CSS/SVG rendering and a downloadable meme wall, so its chosen technical specification takes precedence over the summary's canvas generator.

## Contract

```sh
forge build
FOUNDRY_FUZZ_SEED=0xcbe78dd7537d113d4c5e2cad22f24bec31dae7b994193050f1ff75527aeddb36 forge test
```

Foundry pins Solidity **0.8.26**, Cancun, optimizer enabled (200 runs), and `bytecode_hash = "none"`. Build/cache output is scoped to `test/scratch/` and is not part of the submission. Every Solidity import resolves to committed source. The token itself is self-contained, with no linked library, application contract, proxy or hook.

| Fixed rule | Value |
| --- | --- |
| Name / symbol | Musegod / MUSEGOD |
| Supply | 1,000,000,000 tokens, 18 decimals; `1000000000000000000000000000` minor units |
| Initial recipient | The constructor's `msg.sender`, receiving the entire supply |
| Buy fee | `BUY_FEE_BPS = 200`, denominator `10_000` |
| PoolManager | `0x8366a39cc670b4001a1121b8f6a443a643e40951` |
| Fee treasury | `0x9Cf1A7Cd2a2A423d7Df0D9663E0092423993389A` |
| IMD pair | `0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127` |
| Pool fee / tick spacing | 12,500 (1.25%) / 60 |
| Pool seeding budget / swarm | 90% / 10%, distributed by the launch factory |
| Opening market cap | 2,500 IMD (`2500000000000000000000` paired-currency minor units) |
| Factory rounding remainder | `0x000000000000000000000000000000000000dead` |

The token has no constructor arguments. It does not seed liquidity, distribute the swarm allocation, call another contract or move any constructor-minted supply. The factory receives the entire supply, handles the Merkle distributor and pool, and forwards any rounding remainder.

The fee checks **the sender address**, including in `transferFrom`. Every PoolManager outflow incurs `floor(gross / 50)` minor units sent directly to the treasury. This includes liquidity withdrawals, not only swaps. The manager is debited the full gross amount; the recipient gets the remainder. Inputs, including sells and seeding, and ordinary wallet transfers are untaxed. Uniswap's separate 1.25% pool fee is distinct from this token fee. Anyone may read the cumulative `totalFeesCollected()` counter, denominated in MUSEGOD minor units.

Only `approve`, `transfer` and `transferFrom` change state after construction. There is no owner, administrator, privileged deployer power, mint, burn, fee setter, upgrade path or forbidden opcode. Zero-address transfers revert. Infinite allowances follow the usual ERC-20 convention.

`launch.json` carries the exact requested manifest and economics. Its `initialPrice` is the supplied provenance value; the launch service derives the actual opening price using economics and deployed currency order.

## Actual validation

- `forge build`: passed. `forge test` with the specified seed: **13 passed**, including **3,000 ERC-20 fuzz cases** and **256 real Uniswap v4 buy/sell round trips**. The offline tests use the committed v4 PoolManager implementation at the configured address, with an IMD transfer stand-in. Live Robinhood Chain state and the production launch factory were not forked or invoked.
- Production static export, strict JavaScript typecheck and integrity checks: passed.
- Chromium: **9 pages × 2 widths**, **18 axe audits with zero violations**, **38 interaction checks**, and no unexpected console, script or local-resource errors. The first 390px screen shows the product and its primary action.
- Pinned taste probe: **15/16** on the served export. The remaining repetition check is the explicitly requested scrolling ticker; it has a pause control and stops for reduced motion. The direct file-only probe also reports the expected missing deployment metadata endpoint; the supplied preview and actual browser tests exercise it explicitly.
- WebKit was attempted but could not start because this machine lacks its system libraries. Native iOS, screen-reader sessions, browser-native 200% zoom and live-chain fork verification remain unperformed. No full accessibility certification or independent audit is claimed.

Detailed coverage, corrected findings and evidence are in [artifacts/validation.md](artifacts/validation.md). [DESIGN.md](DESIGN.md) documents the final design system. `artifacts/budget.json` records the submission size check. No ignore file was created or changed, and no generated dependencies, registry archives or submodules are included.

## Brief decisions and attribution

The full brief was fetched successfully from `https://www.si-md.xyz/api/chat?op=site-brief&label=musegod` before implementation. Its clean charcoal/white/gold creative spec supersedes the generic maximalist direction. Its two “zero taxes” claims and “100% supply is liquid” line were replaced with the real, fixed 2% buy fee and accurate 90% pool / 10% swarm allocation. No fabricated social feed is shown; X buttons search #MUSEGOD or open three distinct share intents without posting for the visitor.

Design review used the pinned Better Interface guide by Jakub Krehel (MIT), with documentation guidance adapted from Paul Bakaus's Impeccable (Apache-2.0). Testing guidance is adapted from Austin Griffith's ethskills (MIT). Notices and licenses are retained in `artifacts/licenses/`. The locally hosted Space Grotesk, Inter and IBM Plex Mono fonts retain their OFL licenses in `site/assets/`. Test-only Uniswap and Solmate sources retain their original notices and licenses in `lib/`.
