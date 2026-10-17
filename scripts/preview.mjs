import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { resolve, extname, sep } from "node:path";
export function preview(root = "dist", port = 4173) {
  const base = resolve(root);
  const mime = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".svg": "image/svg+xml",
    ".jpg": "image/jpeg",
    ".png": "image/png",
    ".woff2": "font/woff2",
    ".json": "application/json",
  };
  const server = createServer(async (req, res) => {
    const pathname = decodeURIComponent(
      new URL(req.url || "/", "http://localhost").pathname,
    );
    if (pathname === "/simd-coin.json") {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end("{}");
      return;
    }
    const route = pathname.replace(/^\/preview(?=\/|$)/, "");
    let file = resolve(base, "." + (route || "/"));
    if (file !== base && !file.startsWith(base + sep)) {
      res.writeHead(403);
      res.end();
      return;
    }
    try {
      if ((await stat(file)).isDirectory()) file = resolve(file, "index.html");
      const bytes = await readFile(file);
      res.writeHead(200, {
        "Content-Type": mime[extname(file)] || "application/octet-stream",
      });
      res.end(bytes);
    } catch {
      res.writeHead(404, { "Content-Type": "text/html; charset=utf-8" });
      res.end(await readFile(resolve(base, "404.html")));
    }
  });
  return new Promise((resolveServer) =>
    server.listen(port, "127.0.0.1", () => resolveServer(server)),
  );
}
if (import.meta.url === new URL(process.argv[1], "file:").href) {
  const server = await preview("dist", Number(process.argv[2]) || 4173);
  console.log(
    `Musegod preview: http://127.0.0.1:${server.address().port}/preview/`,
  );
}
