import { lstat, readdir, writeFile } from "node:fs/promises";
import { join } from "node:path";
const exclude = new Set([
  ".git",
  ".github",
  ".imd",
  ".agents",
  ".aws",
  ".codex",
]);
const files = [];
async function walk(dir = ".") {
  for (const name of await readdir(dir)) {
    if (exclude.has(name) || name === ".env" || name.startsWith(".env."))
      continue;
    const path = join(dir, name);
    if (path === "test/scratch") continue;
    if (
      ["node_modules", ".npm", ".cache", "__pycache__"].includes(name) ||
      name.endsWith(".tgz")
    )
      throw new Error(`Unnecessary dependency/cache artifact: ${path}`);
    const info = await lstat(path);
    if (info.isSymbolicLink()) throw new Error(`Unexpected symlink: ${path}`);
    if (info.isDirectory()) await walk(path);
    else files.push({ path, bytes: info.size });
  }
}
await walk();
const total = files.reduce((sum, file) => sum + file.bytes, 0);
const report = {
  limitBytes: 8388608,
  fileBytes: total,
  remainingBytes: 8388608 - total,
  files: files.length,
  distBytes: files
    .filter((f) => f.path.startsWith("dist/"))
    .reduce((sum, file) => sum + file.bytes, 0),
  largest: files.sort((a, b) => b.bytes - a.bytes).slice(0, 10),
};
if (total > 8388608)
  throw new Error(`Submission exceeds the 8 MiB budget: ${total}`);
console.log(JSON.stringify(report, null, 2));
if (process.argv.includes("--record"))
  await writeFile(
    "artifacts/budget.json",
    JSON.stringify(report, null, 2) + "\n",
  );
