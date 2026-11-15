/**
 * Máy chủ HTTP tĩnh nhẹ phục vụ thư mục Web build (mặc định `build/admin_emulator_web`)
 * trên `http://localhost:5050` cho kiểm thử Admin Web cục bộ.
 */
const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");

const port = Number(process.env.ADMIN_WEB_PORT || 5050);
const host = process.env.ADMIN_WEB_HOST || undefined;
const rootDir = path.resolve(
  process.argv[2] || path.join(process.cwd(), "build", "admin_emulator_web")
);

const MIME_TYPES = {
  ".html": "text/html; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".mjs": "application/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".wasm": "application/wasm",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".ttf": "font/ttf",
  ".otf": "font/otf",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
  ".map": "application/json; charset=utf-8",
};

const server = http.createServer((req, res) => {
  const reqUrl = (req.url || "/").split("?")[0];
  let relPath = decodeURIComponent(reqUrl);
  if (relPath === "/") relPath = "/index.html";

  let filePath = path.normalize(path.join(rootDir, relPath));
  if (!filePath.startsWith(rootDir)) {
    res.writeHead(403, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("Forbidden");
    return;
  }

  if (!fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
    const ext = path.extname(filePath);
    if (!ext) {
      filePath = path.join(rootDir, "index.html");
    } else {
      res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
      res.end("Not Found");
      return;
    }
  }

  const ext = path.extname(filePath).toLowerCase();
  const contentType = MIME_TYPES[ext] || "application/octet-stream";
  res.writeHead(200, {
    "Content-Type": contentType,
    "Cache-Control": "no-store",
  });
  fs.createReadStream(filePath).pipe(res);
});

const onListening = () => {
  console.log(`ADMIN_WEB_STATIC_SERVER listening on http://localhost:${port} (root: ${rootDir})`);
};
if (host) {
  server.listen(port, host, onListening);
} else {
  server.listen(port, onListening);
}
