// Servidor estático mínimo com suporte a HEAD e HTTP Range (como o GitHub Pages), para os testes
// E2E e para conferir o DuckDB-Wasm localmente. Sem dependências.
// Uso: node tests/e2e/server.mjs <diretório> [porta]

import http from "node:http";
import fs from "node:fs";
import path from "node:path";

const root = path.resolve(process.argv[2] || "web/_site");
const port = Number(process.argv[3] || process.env.PORT || 4173);

const TYPES = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".mjs": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8", ".json": "application/json; charset=utf-8", ".svg": "image/svg+xml",
  ".parquet": "application/vnd.apache.parquet", ".png": "image/png", ".txt": "text/plain; charset=utf-8",
  ".xml": "application/xml", ".woff2": "font/woff2", ".map": "application/json",
};

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://localhost:${port}`);
  let file = path.normalize(path.join(root, decodeURIComponent(url.pathname)));
  if (!file.startsWith(root)) { res.writeHead(403).end(); return; }
  if (fs.existsSync(file) && fs.statSync(file).isDirectory()) file = path.join(file, "index.html");
  if (!fs.existsSync(file)) { res.writeHead(404, { "content-type": "text/plain" }).end("not found"); return; }
  const size = fs.statSync(file).size;
  const headers = {
    "content-type": TYPES[path.extname(file)] || "application/octet-stream",
    "accept-ranges": "bytes",
    "access-control-allow-origin": "*",
    "access-control-expose-headers": "Content-Length, Content-Range, Accept-Ranges",
    "cache-control": "no-cache",
  };
  const range = req.headers.range && /^bytes=(\d*)-(\d*)$/.exec(req.headers.range);
  if (range) {
    let start = range[1] === "" ? size - Number(range[2]) : Number(range[1]);
    let end = range[1] !== "" && range[2] !== "" ? Number(range[2]) : size - 1;
    if (range[1] === "") end = size - 1;
    start = Math.max(0, start); end = Math.min(end, size - 1);
    if (start > end) { res.writeHead(416, { "content-range": `bytes */${size}` }).end(); return; }
    res.writeHead(206, { ...headers, "content-range": `bytes ${start}-${end}/${size}`, "content-length": end - start + 1 });
    if (req.method === "HEAD") { res.end(); return; }
    fs.createReadStream(file, { start, end }).pipe(res);
    return;
  }
  res.writeHead(200, { ...headers, "content-length": size });
  if (req.method === "HEAD") { res.end(); return; }
  fs.createReadStream(file).pipe(res);
});

server.listen(port, () => console.log(`servindo ${root} em http://localhost:${port}/`));
