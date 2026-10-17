// Runs the supplied probe against a bounded local preview with the deployment endpoint empty.
import { preview } from "./preview.mjs";
import { spawn } from "node:child_process";
const server = await preview("dist", 0);
try {
  const child = spawn(
    process.execPath,
    [
      ".imd/reads/skills/design-critic/scripts/taste.mjs",
      `http://127.0.0.1:${server.address().port}/preview/`,
      "--out",
      "test/scratch/taste-served",
    ],
    { stdio: "inherit", env: process.env },
  );
  const code = await new Promise((resolve, reject) => {
    child.on("exit", resolve);
    child.on("error", reject);
  });
  process.exitCode = code || 0;
} finally {
  server.close();
}
