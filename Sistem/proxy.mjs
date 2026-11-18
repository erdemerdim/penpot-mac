// Minimal replacement for the nginx config shipped in the penpotapp/frontend image.
// Serves the static frontend and proxies API/websocket/asset requests to the backend.
import http from "node:http";
import https from "node:https";
import fs from "node:fs";
import path from "node:path";
import net from "node:net";

// PP_HOME: penpot.env'in bulunduğu klasör (tek parça uygulamada veri klasörü; bu dosya ise paketin içinde)
const ROOT = process.env.PP_HOME || path.dirname(new URL(import.meta.url).pathname);
const APP_DIR = path.join(ROOT, "frontend");
const ASSETS_DIR = path.join(ROOT, "data", "assets");
const PORT = Number(process.env.PENPOT_PORT || 9001);
const BACKEND = new URL(process.env.PENPOT_BACKEND_URI || "http://127.0.0.1:6060");
const EXPORTER = new URL("http://127.0.0.1:6061");
const MCP_HTTP = new URL("http://127.0.0.1:4401");
const MCP_WS = new URL("http://127.0.0.1:4402");
// Bu dosyanın yanındaki patches/ (geliştirme kurulumu ve DMG paketi); yoksa veri klasöründeki
const CODE_DIR = path.dirname(new URL(import.meta.url).pathname);
const AKICI_ZOOM = [path.join(CODE_DIR, "patches", "akici-zoom.js"), path.join(ROOT, "patches", "akici-zoom.js")].find(f => fs.existsSync(f)) || "";

const MIME = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8",
  ".json": "application/json", ".svg": "image/svg+xml", ".png": "image/png",
  ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".gif": "image/gif", ".webp": "image/webp",
  ".ico": "image/x-icon", ".woff": "font/woff", ".woff2": "font/woff2", ".ttf": "font/ttf",
  ".otf": "font/otf", ".wasm": "application/wasm", ".map": "application/json", ".txt": "text/plain",
};

function sendFile(res, file, headers = {}) {
  fs.stat(file, (err, st) => {
    if (err || !st.isFile()) { res.writeHead(404); return res.end("Not found"); }
    res.writeHead(200, {
      "content-type": MIME[path.extname(file).toLowerCase()] || "application/octet-stream",
      "content-length": st.size,
      ...headers,
    });
    fs.createReadStream(file).pipe(res);
  });
}

// Hızlı açılış: arayüz, Java sunucusu açılmadan yüklenmeye başlar. Sunucu henüz hazır değilse
// API istekleri reddedilmez, sunucu hazır olana kadar (en çok 90 sn) burada bekletilir.
let backendUp = false;
function backendReadyCheck() {
  return new Promise((resolve) => {
    const q = http.get({ hostname: BACKEND.hostname, port: BACKEND.port, path: "/readyz", timeout: 1000 }, (s) => { s.resume(); resolve(s.statusCode === 200); });
    q.on("error", () => resolve(false));
    q.on("timeout", () => { q.destroy(); resolve(false); });
  });
}
let waiting = null;
function waitBackend() {
  if (backendUp) return Promise.resolve(true);
  if (!waiting) waiting = (async () => {
    const t0 = Date.now();
    while (Date.now() - t0 < 90000) {
      if (await backendReadyCheck()) { backendUp = true; break; }
      await new Promise((r) => setTimeout(r, 200));
    }
    waiting = null; return backendUp;
  })();
  return waiting;
}

function proxyBackend(req, res, targetPath) {
  if (!backendUp) { waitBackend().then(() => proxyBackendNow(req, res, targetPath)); return; }
  proxyBackendNow(req, res, targetPath);
}

function proxyBackendNow(req, res, targetPath) {
  const headers = { ...req.headers, host: BACKEND.host, "x-forwarded-proto": "http", "x-real-ip": req.socket.remoteAddress };
  const preq = http.request({ hostname: BACKEND.hostname, port: BACKEND.port, method: req.method, path: targetPath, headers }, (pres) => {
    const accel = pres.headers["x-accel-redirect"];
    if (accel && accel.startsWith("/internal/assets/")) {
      // fs storage backend: serve the file ourselves, like nginx's internal location.
      pres.resume();
      const rel = decodeURIComponent(accel.slice("/internal/assets/".length).split("?")[0]);
      const file = path.join(ASSETS_DIR, rel);
      if (!file.startsWith(ASSETS_DIR)) { res.writeHead(403); return res.end(); }
      // nginx X-Accel-Redirect davranışı: backend'in içerik başlıklarını koru
      const extra = {};
      const ctype = pres.headers["x-mtype"] || pres.headers["content-type"];
      if (ctype) extra["content-type"] = ctype;
      for (const h of ["cache-control", "content-disposition"]) {
        if (pres.headers[h]) extra[h] = pres.headers[h];
      }
      return sendFile(res, file, extra);
    }
    res.writeHead(pres.statusCode, pres.headers);
    pres.pipe(res);
  });
  preq.on("error", (e) => { if (e.code === "ECONNREFUSED") backendUp = false; if (!res.headersSent) res.writeHead(502); res.end("Backend unavailable"); });
  req.pipe(preq);
}

function proxyTo(target, req, res, targetPath) {
  const headers = { ...req.headers, host: target.host };
  const preq = http.request({ hostname: target.hostname, port: target.port, method: req.method, path: targetPath, headers }, (pres) => {
    res.writeHead(pres.statusCode, pres.headers);
    pres.pipe(res);
  });
  preq.on("error", () => { if (!res.headersSent) res.writeHead(502); res.end("Service unavailable"); });
  req.pipe(preq);
}

function proxyExternal(req, res, target, extraHeaders = {}) {
  const u = new URL(target);
  const preq = https.request({ hostname: u.hostname, path: u.pathname + u.search, method: "GET",
    // nginx yapılandırmasındaki tarayıcı kimliğinin aynısı: Google Fonts bununla tüm alt kümeleri
    // (Türkçe ğ, ş, İ harflerini içeren latin-ext dahil) unicode-range ile gönderir.
    // Tanınmayan bir kimlikte yalnızca temel Latin harflerini içeren tek bir dosya dönüyordu.
    headers: { "user-agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/113.0.0.0 Safari/537.36", accept: "*/*", ...extraHeaders } }, (pres) => {
    const h = { ...pres.headers };
    for (const k of ["strict-transport-security", "content-security-policy", "content-security-policy-report-only",
      "access-control-allow-origin", "set-cookie", "alt-svc", "link"]) delete h[k];
    if (req.headers.origin) h["access-control-allow-origin"] = req.headers.origin;
    res.writeHead(pres.statusCode, h);
    pres.pipe(res);
  });
  preq.on("error", () => { if (!res.headersSent) res.writeHead(502); res.end(); });
  preq.end();
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, "http://localhost");
  const p = url.pathname;
  const qs = url.search;
  if (p.startsWith("/mcp") || p.startsWith("/plugins/mcp")) console.log(new Date().toISOString(), req.method, p);

  // Akıcı yakınlaştırma betiği (patches/akici-zoom.js): Penpot sayfasına eklenir
  if (p === "/__akici-zoom.js" && AKICI_ZOOM) return sendFile(res, AKICI_ZOOM, { "cache-control": "no-store" });
  if (p === "/" || p === "/index.html") {
    const tags = AKICI_ZOOM ? '<script src="/__akici-zoom.js"></script>' : "";
    const html = fs.readFileSync(path.join(APP_DIR, "index.html"), "utf8").replace("</head>", tags + "</head>");
    res.writeHead(200, { "content-type": "text/html; charset=utf-8", "cache-control": "no-store, no-cache, max-age=0" }); return res.end(html);
  }
  if (p.startsWith("/mcp/stream")) return proxyTo(MCP_HTTP, req, res, "/mcp" + qs);
  if (p.startsWith("/api/export")) return proxyTo(EXPORTER, req, res, req.url);
  if (p.startsWith("/api") || p.startsWith("/assets") || p === "/link-preview" || p === "/readyz") {
    return proxyBackend(req, res, req.url);
  }
  let m;
  if ((m = p.match(/^\/internal\/gfonts\/font\/(.+)$/))) return proxyExternal(req, res, `https://fonts.gstatic.com/s/${m[1]}`);
  if (p.startsWith("/internal/gfonts/css")) return proxyExternal(req, res, `https://fonts.googleapis.com/css${qs}`);
  if ((m = p.match(/^\/github\/penpot-files\/(.+)$/))) return proxyExternal(req, res, `https://raw.githubusercontent.com/penpot/penpot-files/refs/heads/main/${m[1]}`);

  // Static files
  let rel = decodeURIComponent(p);
  // Klasör adresleri (ör. /plugins/mcp/) içindeki index.html'i sunar (nginx gibi)
  if (rel.startsWith("/plugins/") && rel.endsWith("/")) rel += "index.html";
  const file = path.normalize(path.join(APP_DIR, rel));
  if (file.startsWith(APP_DIR) && rel !== "/" && fs.existsSync(file) && fs.statSync(file).isFile()) {
    const cache = rel === "/js/config.js" ? "no-store, no-cache, max-age=0" : "public, max-age=604800";
    return sendFile(res, file, { "cache-control": cache });
  }
  // Geçici yönlendirme: tarayıcı önbelleğe almasın (301 kalıcı olarak önbelleğe alınıyordu)
  if (/^\/[^/]+\/.+$/.test(rel)) { res.writeHead(302, { location: "/404", "cache-control": "no-store" }); return res.end(); }
  return sendFile(res, path.join(APP_DIR, "index.html"), { "cache-control": "no-store, no-cache, max-age=0" });
});

// Websockets: backend bildirimleri ve MCP eklentisi
server.on("upgrade", (req, socket, head) => {
  let target;
  if (req.url.startsWith("/mcp")) console.log(new Date().toISOString(), "WS", req.url.split("?")[0]);
  if (req.url.startsWith("/ws/notifications")) target = BACKEND;
  else if (req.url.startsWith("/mcp/ws")) target = MCP_WS;
  else return socket.destroy();
  const up = net.connect(Number(target.port), target.hostname, () => {
    const lines = [`${req.method} ${req.url} HTTP/1.1`];
    for (let i = 0; i < req.rawHeaders.length; i += 2) {
      const k = req.rawHeaders[i];
      lines.push(k.toLowerCase() === "host" ? `Host: ${target.host}` : `${k}: ${req.rawHeaders[i + 1]}`);
    }
    up.write(lines.join("\r\n") + "\r\n\r\n");
    if (head && head.length) up.write(head);
    up.pipe(socket); socket.pipe(up);
  });
  up.on("error", () => socket.destroy());
  socket.on("error", () => up.destroy());
});

server.listen(PORT, "127.0.0.1", () => console.log(`Penpot frontend: http://localhost:${PORT}`));
