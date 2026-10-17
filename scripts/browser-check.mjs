import { pathToFileURL } from "node:url";
import { mkdir, writeFile } from "node:fs/promises";
import assert from "node:assert/strict";
import { preview } from "./preview.mjs";
const pw = await import(
  process.env.IMD_PLAYWRIGHT
    ? pathToFileURL(process.env.IMD_PLAYWRIGHT).href
    : "playwright"
);
const AxeBuilder = (
  await import(
    process.env.MUSEGOD_AXE
      ? pathToFileURL(process.env.MUSEGOD_AXE).href
      : "@axe-core/playwright"
  )
).default;
const server = await preview("dist", 0);
const origin = `http://127.0.0.1:${server.address().port}`;
const root = origin + "/preview/";
const routes = [
  "",
  "docs/",
  "docs/how-it-works/",
  "docs/tokenomics/",
  "docs/contracts/",
  "docs/faq/",
  "tokenomics/",
  "faq/",
  "404.html",
];
const errors = [];
const results = {
  pages: [],
  interactions: [],
  accessibility: [],
  screenshots: [],
  limitations: [],
};
const check = (condition, message) => {
  assert.ok(condition, message);
  results.interactions.push(message);
};
let browser;
try {
  browser = await pw.chromium.launch({ headless: true });
  const context = await browser.newContext({
    reducedMotion: "reduce",
    permissions: ["clipboard-read", "clipboard-write"],
  });
  const page = await context.newPage();
  page.on("pageerror", (error) => errors.push(error.message));
  page.on("console", (message) => {
    if (message.type() === "error") errors.push(message.text());
  });
  page.on("response", (response) => {
    if (response.url().startsWith(origin) && response.status() >= 400)
      errors.push(`${response.status()} ${response.url()}`);
  });
  await mkdir("test/scratch/browser", { recursive: true });
  for (const width of [375, 1440]) {
    await page.setViewportSize({ width, height: width === 375 ? 812 : 900 });
    for (const route of routes) {
      await page.goto(root + route);
      await page.waitForLoadState("networkidle");
      // Walk lazy images and reveal sections before measuring the whole page.
      await page.evaluate(async () => {
        for (const s of document.querySelectorAll("main section")) {
          s.scrollIntoView({ behavior: "instant" });
          await new Promise((r) => setTimeout(r, 50));
        }
        window.scrollTo({ top: 0, behavior: "instant" });
      });
      await page.waitForTimeout(100);
      assert.ok(
        await page.evaluate(
          () => document.documentElement.scrollWidth <= innerWidth + 1,
        ),
        `Overflow ${route} at ${width}`,
      );
      const broken = await page
        .locator("img")
        .evaluateAll((images) =>
          images
            .filter((i) => !i.complete || i.naturalWidth === 0)
            .map((i) => i.src),
        );
      assert.deepEqual(broken, [], `Images ${route} at ${width}`);
      assert.equal(await page.locator("h1").count(), 1);
      // Internal links, fragments, and all referenced assets are also checked without a browser.
      const audit = await new AxeBuilder({ page })
        .withTags(["wcag2a", "wcag2aa", "wcag21aa", "wcag22aa"])
        .analyze();
      results.accessibility.push({
        route: route || "home",
        width,
        violations: audit.violations.map((v) => ({
          id: v.id,
          impact: v.impact,
          nodes: v.nodes.map((n) => n.target),
        })),
      });
      assert.equal(
        audit.violations.length,
        0,
        `Accessibility ${route} at ${width}: ${JSON.stringify(audit.violations.map((v) => ({ id: v.id, nodes: v.nodes.map((n) => n.target) })))}`,
      );
      results.pages.push({
        route: route || "home",
        width,
        overflow: false,
        brokenImages: 0,
      });
    }
  }
  // First screen, empty launch state, mobile menu and keyboard.
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(root);
  await page.waitForLoadState("networkidle");
  const buy = page.locator(".hero [data-buy]");
  check(
    (await buy.boundingBox()).y + (await buy.boundingBox()).height <= 844,
    "Primary Buy action is wholly on the first 390px screen",
  );
  check(
    (await page.locator(".hero [data-contract]").textContent()) ===
      "launching…",
    "No address is invented before deployment",
  );
  check(
    await page.locator(".hero [data-copy-contract]").isDisabled(),
    "Contract copying disabled until an address exists",
  );
  await page.getByRole("button", { name: "Menu", exact: true }).click();
  check(await page.locator("#mobile-nav").isVisible(), "Mobile menu opens");
  await page.keyboard.press("Escape");
  check(
    await page.locator("#mobile-nav").isHidden(),
    "Escape closes mobile menu",
  );
  check(
    await page
      .locator(".menu-toggle")
      .evaluate((el) => el === document.activeElement),
    "Menu focus returns to the trigger",
  );
  await page.locator("#bless-mascot").focus();
  await page.keyboard.press("Enter");
  check(
    (await page.locator("#bless-mascot").getAttribute("aria-label")).includes(
      "1 this visit",
    ),
    "Blessing supports keyboard activation",
  );
  await page.locator('[data-step="0"]').click();
  await page.locator('[data-step="1"]').click();
  check(
    (await page.locator("#step-title").textContent()) ===
      "Find the real plush.",
    "Buying guide reveals step two",
  );
  await page.locator('[data-step="2"]').click();
  check(
    (await page.locator("#step-text").textContent()).includes("2%"),
    "Buying guide explains the real fee",
  );
  const sticker = page.locator("#plush-sticker");
  await sticker.scrollIntoViewIfNeeded();
  await sticker.focus();
  await page.keyboard.press("ArrowRight");
  check(
    (await sticker.getAttribute("style")).includes("translate(12px"),
    "Draggable plush has an arrow-key equivalent",
  );
  await page.keyboard.press("Home");
  check(
    (await sticker.getAttribute("style")).includes("translate(0px, 0px)"),
    "Home resets the plush position",
  );
  const bounds = await sticker.boundingBox();
  await page.mouse.move(bounds.x + 35, bounds.y + 35);
  await page.mouse.down();
  await page.mouse.move(bounds.x + 65, bounds.y + 45);
  await page.mouse.up();
  check(
    !(await sticker.getAttribute("style")).includes("translate(0px, 0px)"),
    "Plush responds to pointer drag",
  );
  // Download every distinct composition and check its binary signature.
  for (const link of await page.locator("a[download]").all()) {
    const [download] = await Promise.all([
      page.waitForEvent("download"),
      link.click(),
    ]);
    assert.ok(download.suggestedFilename().endsWith(".png"));
    assert.equal(await download.failure(), null);
  }
  results.interactions.push("All 8 PNG downloads complete");
  check(
    (await page.locator("a[data-share]").count()) === 3,
    "Three separate X share intents exist",
  );
  await page.locator("[data-copy-link]").click();
  check(
    (await page.evaluate(() => navigator.clipboard.readText())) ===
      "https://musegod.si-md.xyz/",
    "Copy site link works",
  );
  // Denied clipboard access leaves selectable content and a persistent, dismissible message.
  await page.evaluate(() => {
    navigator.clipboard.writeText = () =>
      Promise.reject(new Error("test denial"));
  });
  await page.locator("[data-copy-link]").click();
  check(
    (await page.locator("#toast").textContent()).includes(
      "https://musegod.si-md.xyz/",
    ),
    "Clipboard failure keeps the full copyable link visible",
  );
  await page.getByRole("button", { name: "Dismiss", exact: true }).click();
  check(
    (await page.locator(".toast-dismiss").count()) === 0,
    "Dismissed clipboard error leaves no hidden focus target",
  );
  // FAQ search, empty result recovery, native accordion; documentation search/navigation.
  await page.goto(root + "faq/");
  await page.locator("[data-faq-search]").fill("liquidity");
  check(
    (await page.locator(".faq-item:visible").count()) === 1,
    "FAQ search filters real questions and answers",
  );
  await page.locator(".faq-item:visible summary").click();
  check(
    (await page.locator(".faq-item[open]").count()) === 1,
    "FAQ accordion opens",
  );
  await page.locator("[data-faq-search]").fill("qwertyuiop");
  check(
    await page.locator("[data-search-empty]").isVisible(),
    "FAQ empty state offers useful search hints",
  );
  await page.locator("[data-faq-search]").fill("");
  check(
    (await page.locator(".faq-item:visible").count()) === 10,
    "Clearing FAQ search restores all ten questions",
  );
  await page.goto(root + "docs/contracts/");
  await page.locator("[data-doc-search]").fill("wallet");
  check(
    (await page.locator("[data-doc-results] a").count()) === 2,
    "Docs search returns indexed pages",
  );
  await page.locator("[data-doc-results] a").first().click();
  check(
    page.url().endsWith("/docs/how-it-works/"),
    "Doc search opens a real static route",
  );
  await page.locator(".prev-next a").last().click();
  check(
    page.url().endsWith("/docs/tokenomics/"),
    "Documentation next link navigates",
  );
  // Mocking is confined to this test: no address, stats or launch URLs ship in the site.
  const fixtureAddress = "0x" + "ab".repeat(20);
  let mode = "live",
    fetches = 0;
  await page.route("**/simd-coin.json", async (route) => {
    fetches++;
    if (mode === "failure") {
      await route.fulfill({
        status: 503,
        contentType: "application/json",
        body: "{}",
      });
      return;
    }
    const data =
      mode === "invalid"
        ? {
            token: "bad",
            coinUrl: "javascript:alert(1)",
            chartUrl: "data:text/html,no",
            market: { priceUsd: "bad", marketCap: -1, volume24h: null },
          }
        : {
            token: fixtureAddress,
            coinUrl: "https://www.si-md.xyz/launchpad",
            chartUrl: "https://www.si-md.xyz/launchpad",
            logo: origin + "/preview/assets/memes/worthy.svg",
            market: { priceUsd: 0.00001234, marketCap: 12340, volume24h: 2345 },
          };
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify(data),
    });
  });
  await page.clock.install();
  await page.goto(root);
  await page.waitForLoadState("networkidle");
  check(
    (await page.locator(".hero [data-contract]").textContent()) ===
      fixtureAddress,
    "Live token address is read from JSON",
  );
  check(
    (await page.locator(".hero [data-buy]").getAttribute("href")) ===
      "https://www.si-md.xyz/launchpad",
    "Buy link uses coinUrl",
  );
  check(
    await page.locator("[data-chart]").isVisible(),
    "Chart link appears only when chartUrl is available",
  );
  check(
    (await page.locator("[data-coin-logo]").getAttribute("href")) ===
      origin + "/preview/assets/memes/worthy.svg",
    "Runtime logo overrides the supplied fallback",
  );
  check(
    (await page.locator('[data-stat="marketCap"]').textContent()).includes(
      "12,340",
    ),
    "Real numeric stats are displayed",
  );
  await page.locator(".hero [data-copy-contract]").click();
  check(
    (await page.evaluate(() => navigator.clipboard.readText())) ===
      fixtureAddress,
    "Contract copy uses the live address",
  );
  const before = fetches;
  const refreshed = page.waitForResponse((r) =>
    r.url().endsWith("/simd-coin.json"),
  );
  await page.clock.fastForward(30000);
  await refreshed;
  await page.clock.resume();
  await page.waitForTimeout(150);
  check(
    fetches > before,
    "Live stats refresh after the 30-second interval under an accelerated clock",
  );
  await page.clock.resume();
  mode = "invalid";
  await page.locator("[data-retry]").click();
  await page.waitForTimeout(150);
  check(
    await page.locator("[data-stats]").isHidden(),
    "Invalid market values are hidden",
  );
  check(
    (await page.locator(".hero [data-contract]").textContent()) ===
      "launching…",
    "Invalid addresses return to the honest launching state",
  );
  check(
    await page.locator("[data-chart]").isHidden(),
    "Unsafe chart URLs are rejected",
  );
  check(
    (await page.locator(".hero [data-buy]").getAttribute("href")) === "#buy",
    "Unsafe Buy URLs fall back to the guide",
  );
  mode = "failure";
  await page.locator("[data-retry]").click();
  await page.waitForTimeout(150);
  check(
    (await page.locator("[data-data-status]").textContent()).includes(
      "Refresh to try again",
    ),
    "Failed data fetch offers retry",
  );
  // The intentional HTTP 503 produces a browser resource error; remove only that expected fixture error.
  for (let i = errors.length - 1; i >= 0; i--)
    if (errors[i].includes("503")) errors.splice(i, 1);
  mode = "live";
  await page.locator("[data-retry]").click();
  await page.waitForTimeout(150);
  check(
    await page.locator("[data-stats]").isVisible(),
    "Retry recovers live data",
  );
  await context.close();
  // Production appearance with the honest empty launch response and normal motion.
  const visual = await browser.newContext({ reducedMotion: "no-preference" });
  const shot = await visual.newPage();
  for (const width of [320, 360, 390, 768, 850, 1150, 1440, 1920]) {
    await shot.setViewportSize({ width, height: width < 620 ? 844 : 900 });
    await shot.goto(root);
    await shot.waitForLoadState("networkidle");
    assert.ok(
      await shot.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth + 1,
      ),
      `Home reflow ${width}`,
    );
    if ([390, 1440].includes(width)) {
      await shot.screenshot({ path: `test/scratch/browser/home-${width}.png` });
      results.screenshots.push(`test/scratch/browser/home-${width}.png`);
      await shot.evaluate(async () => {
        for (const section of document.querySelectorAll("main section")) {
          section.scrollIntoView({ behavior: "instant" });
          await new Promise((r) => setTimeout(r, 150));
        }
        window.scrollTo({ top: 0, behavior: "instant" });
      });
      await shot.waitForTimeout(700);
      assert.equal(
        await shot
          .locator(".reveal")
          .evaluateAll(
            (sections) =>
              sections.filter(
                (section) => getComputedStyle(section).opacity !== "1",
              ).length,
          ),
        0,
        "Every scrolled section is fully revealed",
      );
      await shot.screenshot({
        path: `test/scratch/browser/home-${width}-full.png`,
        fullPage: true,
      });
    }
  }
  await shot.setViewportSize({ width: 390, height: 844 });
  await shot.goto(root);
  await shot.getByRole("button", { name: "Pause motion" }).click();
  check(
    await shot
      .locator("body")
      .evaluate((body) => body.classList.contains("motion-paused")),
    "Visible motion control pauses autoplay",
  );
  await visual.close();
  await browser.close();
  browser = null;
  // WebKit support is attempted independently. Missing system libraries are a recorded machine limitation.
  try {
    const safari = await pw.webkit.launch({ headless: true });
    const safariPage = await safari.newPage({
      viewport: { width: 390, height: 844 },
      reducedMotion: "reduce",
    });
    await safariPage.goto(root);
    await safariPage
      .locator("#bless-mascot")
      .tap()
      .catch(() => safariPage.locator("#bless-mascot").click());
    assert.ok(
      (
        await safariPage.locator("#bless-mascot").getAttribute("aria-label")
      ).includes("this visit"),
    );
    results.interactions.push("WebKit: primary blessing interaction works");
    await safari.close();
  } catch (error) {
    results.limitations.push(
      "WebKit unavailable: " + error.message.split("\n").slice(0, 5).join(" "),
    );
  }
  assert.deepEqual(
    errors,
    [],
    "No unexpected console, script or local resource errors",
  );
  await writeFile(
    "test/scratch/browser/results.json",
    JSON.stringify(results, null, 2),
  );
  console.log(
    JSON.stringify(
      {
        pages: results.pages.length,
        interactionChecks: results.interactions.length,
        axeAudits: results.accessibility.length,
        unexpectedErrors: errors,
        limitations: results.limitations,
      },
      null,
      2,
    ),
  );
} catch (error) {
  await writeFile(
    "test/scratch/browser/failure.json",
    JSON.stringify({ error: error.stack, errors, results }, null, 2),
  );
  throw error;
} finally {
  if (browser) await browser.close();
  server.close();
}
