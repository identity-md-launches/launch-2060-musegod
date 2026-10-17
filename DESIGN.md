# Musegod design system

## Overview

Musegod is a meme-token information site for people meeting the plush mascot, checking its fixed rules, buying on the external launchpad, and sharing memes. The retrieved creative specification supplies the visual direction: clean, radiant, self-aware, lightly reverent. The supplied crowned plush photograph anchors the hero; original SVG variations carry the story and meme collection.

The system uses charcoal, white and gold, generous space, large Space Grotesk headings and one filled primary action. The home page is a series of editorial sections, not a grid of interchangeable cards. Documentation uses a quieter sidebar and readable text column. Source of truth: `site/styles.css`, static page markup, and `site/app.js`.

## Colors

CSS primitives and semantic aliases are defined in `site/styles.css:22`.

| Role | Token | Value | Usage |
| --- | --- | --- | --- |
| Page | `--bg` / `--neutral-950` | `#181818` | Whole site |
| Secondary surface | `--surface` / `--neutral-900` | `#202020` | Guide detail, philosophy, inputs, contract scroll |
| Subtle structure | `--line` / `--neutral-800` | `#303030` | Separators, orbit lines |
| Strong outline | `--neutral-600` | `#666` | Input/control outlines and sticker boundary; not body text |
| Primary ink | `--ink` / `--neutral-100` | `#fff` | Titles and important content |
| Secondary ink | `--muted` / `--neutral-400` | `#b0b0b0` | Descriptions and labels |
| Gold | `--accent` / `--gold-500` | `#ffd700` | Main action fill, halo, crown, meaningful art |
| Gold hover | `--accent-hover` / `--gold-300` | `#ffe76b` | Filled action hover |
| Ink on gold | `--on-accent` | `#181818` | Filled action text |
| Focus | `--focus` | `#fff` | 2px keyboard outline on dark surfaces |

This is a single dark theme. Status always includes text rather than relying on the gold dot. The original photograph retains its supplied colors; interface and authored SVGs use neutral tones and gold.

Measured solid pairs: white/page **17.76:1**; muted/page **8.19:1**; muted/surface **7.51:1**; gold/page and dark ink/gold **12.66:1**; white/surface **16.29:1**. These are exact token-pair calculations, supplemented by browser axe contrast checks; they do not certify every pixel of the photograph or translucent art.

## Typography

Three locally hosted Google Fonts families, with OFL notices alongside them:

- **Space Grotesk**, `assets/space-400.woff2`: display, headings, chart numbers, brand. CSS declares variable weights 400–700.
- **Inter**, `assets/inter-400.woff2`: prose and controls. CSS declares variable weights 400–700.
- **IBM Plex Mono**, `assets/mono-400.woff2`: contract addresses and small numbered data, weight 400.

The sans fallback is Arial, then `sans-serif`; code falls back to `monospace`. All fonts use `font-display: swap`. Only 400, 500 and 700 are used. The hero display font is preloaded. Local fonts load successfully in the inspected Chromium export.

| Token | Desktop | Phone ≤620px | Role |
| --- | --- | --- | --- |
| `--text-sm` | 14px | 14px | Navigation, labels, buttons, code |
| `--text-base` | 16px | 16px | Body and inputs |
| `--text-lg` | 20px | 20px | Lead sentences, FAQ questions |
| `--text-title` | 28px | 28px | Small headings and number groups |
| `--text-section` | 48px | 36px | Marketing H2 and inner-page H1 |
| `--text-hero` | 120px | 64px | Home H1 |

At ≤1150px the hero/section tokens become 96/40px. Between 621–850px the hero uses `clamp(48px, 8vw, 72px)` to fit its two columns. Below 360px the hero becomes 56px. Documentation H2 is 28px, below its H1. Main heading line-height is 1.1, body 1.65, and leads 1.6. Display tracking ranges from −0.065em on the hero to −0.025em on small headings. Body tracking is natural. Headings use balanced wrapping; paragraphs use pretty wrapping. Long prose is capped at 80ch, and most home descriptions at 46ch. Addresses wrap anywhere and remain selectable. Changing market numbers use tabular numerals.

## Layout

Spacing tokens `--s1` through `--s8` are 8, 16, 24, 32, 48, 64, 96 and 128px at a 16px root size. Shared margins, padding and gaps consume those tokens; 20/28/40px adjustments and 104px section padding serve the specific composition.

`.container` caps content at 1240px. Gutters are 56px on wide screens, 40px below 1150px, 20px below 620px, and 16px below 360px. The sticky header has its own 1376px cap. `.split` gives a two-column section with 100px gap, reduced to 56px and 40px before stacking at 620px. `.section` uses 104px vertical padding, reduced to 72px below 850px and 64px below 620px.

- **Hero:** text and mascot side by side on desktop; a centered sequence on phones: name, logo/blessing, exact hero line, primary action, contract, fee disclosure. The product and action are within the first 390×844 screen.
- **Meme grid:** four columns, three below 1150px, two below 850px. Images retain a square aspect and scale both dimensions together.
- **Buying guide:** three horizontal buttons on desktop; stacked rows on phones. One shared detail panel sits immediately below.
- **Tokenomics:** large accessible SVG donut with text legend and a decorative balance-beam scene. Mobile retains numeric text and wraps the chart/legend where necessary.
- **Market stats:** three columns on desktop, labeled rows on phones; unavailable values are hidden.
- **Docs:** 240px sticky sidebar and flexible 80ch column; sidebar narrows at intermediate widths and moves above content on phones.
- **Navigation:** mobile disclosure replaces desktop links below 851px. Ordinary links preserve native navigation, with Escape closing the menu and returning focus.

Browser checks cover all nine pages at 375/1440px, and the home at 320/360/390/768/850/1150/1440/1920px without horizontal overflow. Native zoom and non-English/RTL layouts were not manually tested; this release is English only.

## Elevation & Depth

The UI is deliberately flat: tonal surface changes, spacing and sparse borders carry hierarchy. There are no interface cards with both a border and a shadow. Soft SVG halo glow, the photographic rim light and the sticker's decorative drop shadow belong to the mascot artwork. Hero orbit bounds are capped at 80% of their grid column to prevent transformed decoration causing scroll.

The sticky navigation is layer 30, the transient toast layer 50, and pointer-ignored confetti layer 60. Decorative layers do not swallow input. The fixed copy message is compact and includes selectable fallback content if clipboard access fails.

## Shapes

`--radius` is 8px for buttons, fields, meme images and the contract scroll. `--radius-lg` is 20px for guide details and the bounded sticker area. Circles/ellipses are reserved for halos, supply allocation and ornamental orbs. The story arch provides a distinct illustrated composition. The live-feed fallback has Musegod holding a blank gold parchment; the contract control has a separate mascot-and-scroll composition. Control outlines are 1px; keyboard focus is a separate 2px perimeter with 5px offset (6px around the mascot). A clipboard-error dismiss control uses a dark outline on its white toast surface.

## Components

All components are static markup patterns with CSS classes and `data-*` hooks, rather than framework exports.

| Pattern | Sources | Behavior and states |
| --- | --- | --- |
| Brand/header/nav | Header in each HTML page; `.site-header`, `.brand`, `.mobile-nav`; `app.js` menu handler | Sticky; mobile disclosure; native links; expanded state; Escape/focus return |
| Primary/secondary action | `.button`, `.button-primary`, `.button-outline` | Gold primary; neutral outline secondary; hover, visible focus, 0.96 press scale; Buy URLs from JSON, guide fallback before launch; Chart hidden without a safe URL |
| Contract control | `.contract-control`, `[data-contract]`, `[data-copy-contract]` | Full selectable/wrapping address; honest `launching…`; copy disabled without a valid address; clipboard success or persistent recoverable failure |
| Blessing mascot | `#bless-mascot`, `.halo-ripple`, `.raised-staff`, `app.js` `bless()` | Hover or tap raises the vector staff, sways the robe and emits white/gold rings at the pointer; Enter/Space use the center; local visit count is labeled explicitly |
| Step guide | `.buy-steps`, `[data-step]`, `#step-detail` | Three native buttons expose the matching detail and `aria-expanded`; accurate wallet, IMD/gas and fee guidance |
| Donut/legend/table | `.donut-wrap`, `.donut-pool`, `.chart-legend`, table markup | 90/10 real allocation; SVG accessible description and text values; one-time stroke entrance; detailed static table |
| Market status | `[data-stats]`, `[data-stat]`, `refreshCoin()` | Safe numeric parsing; 30s visible-tab refresh; animated updates between known values; unavailable/invalid/stale values hidden; retry state |
| Meme download | `.meme-card`, local SVG/PNG pairs | Eight different compositions, lazy square images, small hover rotation and native PNG download links |
| FAQ/search | Native `details/summary`, `[data-faq-search]` | Ten real questions; local text filtering, result count, useful empty state; native keyboard disclosure |
| Docs search | `[data-doc-search]`, `.doc-search-results` | Local page index, named result links, no submission or tracking |
| Share | `[data-share]`, `[data-copy-link]` | Three distinct X intent links and site URL copy; nothing posts automatically |
| Plush sticker | `#plush-sticker`, `.sticker-zone` | Bounded pointer drag; arrow keys move, Home resets; position and blessing count stay within the current visit |
| Motion control | `[data-motion]`, `.motion-paused` | Visible pause/play; system reduced motion disables endless motion and magnetic effects; reveals remain readable |

Animation uses explicit properties and `--ease: cubic-bezier(.2,0,0,1)`. Infinite motion is opted in under `prefers-reduced-motion: no-preference`, and can also be paused visibly. Standard high-frequency feedback is 150ms; reveals are 600ms, value interpolation 650ms, and blessing rings about 900ms. No canvas or 3D rendering is used.

## Do's and Don'ts

- Start a page with the same metadata, skip link, header/footer and `.container`. Export a real folder with `index.html` and correctly prefixed relative assets.
- Reuse the existing six type roles and semantic color/spacing tokens. Use gold fill for the page's primary action, and keep explanatory copy neutral.
- Preserve the real 2% PoolManager-outflow fee, the fixed supply and the 90/10 launch allocation. Never repeat the creative draft's inaccurate zero-tax claims.
- Keep addresses complete and selectable. Use the shared JSON flow; never invent deployment addresses, statistics, activity, partners or X accounts.
- Reuse the mascot in a new pose or composition rather than pasting the same photograph into every section.
- Preserve keyboard paths, native disclosures, explicit empty/error states, reduced motion and the pause control when adding interactions.

For another docs page, copy an existing `site/docs/<topic>/index.html`, update its title/canonical/description, keep one H1, use the existing sidebar/text/previous-next patterns, add it to the local docs index, and run the export, typecheck, integrity and browser checks.
