import { readFile, readdir, stat } from "node:fs/promises";
import { resolve, dirname, join } from "node:path";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
async function files(dir) {
  return (
    await Promise.all(
      (await readdir(dir)).map(async (f) =>
        (await stat(join(dir, f))).isDirectory()
          ? files(join(dir, f))
          : [join(dir, f)],
      ),
    )
  ).flat();
}
const paths = await files("site");
let references = 0;
for (const path of paths.filter((p) => p.endsWith(".html"))) {
  const html = await readFile(path, "utf8");
  for (const text of [
    "<title>",
    'name="description"',
    'property="og:title"',
    'property="og:image"',
    'name="twitter:card"',
    'rel="icon"',
    'rel="canonical"',
  ])
    assert.ok(html.includes(text), `${path}: ${text}`);
  assert.equal((html.match(/<h1[\s>]/g) || []).length, 1, `${path}: one h1`);
  for (const [, url] of html.matchAll(/(?:href|src)="([^"]+)"/g)) {
    if (/^(?:https?:|data:|mailto:)/.test(url)) continue;
    assert.ok(
      !url.startsWith("/"),
      `${path}: relative asset/navigation ${url}`,
    );
    const [file, fragment] = url.split("#");
    let target = resolve(file ? dirname(path) : ".", file || path);
    const info = await stat(target).catch(() => null);
    assert.ok(info, `${path}: missing ${url}`);
    if (info.isDirectory()) target = join(target, "index.html");
    if (fragment && target.endsWith(".html"))
      assert.ok(
        (await readFile(target, "utf8")).includes(`id="${fragment}"`),
        `${path}: missing anchor ${url}`,
      );
    references++;
  }
  assert.equal(
    await readFile(path, "utf8"),
    await readFile(path.replace(/^site/, "dist"), "utf8"),
    `${path}: export matches source`,
  );
}
for (const path of [
  "site/app.js",
  ...(await files("scripts")).filter((p) => p.endsWith(".mjs")),
]) {
  const result = spawnSync(process.execPath, ["--check", path], {
    encoding: "utf8",
  });
  assert.equal(result.status, 0, result.stderr);
}
const manifest = JSON.parse(await readFile("launch.json", "utf8"));
assert.deepEqual(Object.keys(manifest), [
  "kind",
  "token",
  "contracts",
  "pool",
  "economics",
  "notes",
]);
assert.equal(manifest.token.totalSupply, "1000000000000000000000000000");
assert.deepEqual(manifest.economics, {
  poolBps: 9000,
  initialMarketCapWei: "2500000000000000000000",
  remainderTo: "0x000000000000000000000000000000000000dead",
});
const pngs = paths.filter((p) => p.endsWith(".png"));
assert.equal(pngs.length, 8);
for (const png of pngs)
  assert.equal(
    (await readFile(png)).subarray(0, 8).toString("hex"),
    "89504e470d0a1a0a",
  );
console.log(
  `PASS: ${paths.filter((p) => p.endsWith(".html")).length} HTML pages, ${references} local references, 8 PNG signatures, JavaScript syntax, export parity, and launch manifest.`,
);
