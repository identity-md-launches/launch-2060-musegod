import { cp, rm, stat, readdir } from "node:fs/promises";
import { join } from "node:path";
await rm("dist", { recursive: true, force: true });
await cp("site", "dist", { recursive: true });
async function size(path) {
  const s = await stat(path);
  return s.isDirectory()
    ? (
        await Promise.all((await readdir(path)).map((p) => size(join(path, p))))
      ).reduce((a, b) => a + b, 0)
    : s.size;
}
console.log(
  `Static production export copied to dist/ (${await size("dist")} bytes). No bundling or compilation required.`,
);
