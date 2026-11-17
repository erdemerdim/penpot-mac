// Penpot MCP sunucusuna komut satırından araç çağrısı yapar.
// Kullanım: node mcp-call.mjs <araç> ['<json argümanlar>' | @dosya.json]
//           node mcp-call.mjs --list
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const URL_ = process.env.PENPOT_MCP_URL || "http://127.0.0.1:4401/mcp";
const SESSION_FILE = path.join(os.tmpdir(), "penpot-mcp-session.txt");
const H = { "Content-Type": "application/json", Accept: "application/json, text/event-stream" };

async function rpc(body, sid) {
  const res = await fetch(URL_, { method: "POST", headers: { ...H, ...(sid ? { "mcp-session-id": sid } : {}) }, body: JSON.stringify(body) });
  const text = await res.text();
  const sidOut = res.headers.get("mcp-session-id") || sid;
  if (!text) return { sid: sidOut, msg: null, status: res.status };
  const lines = text.split("\n").filter((l) => l.startsWith("data: ")).map((l) => l.slice(6));
  const payload = lines.length ? lines[lines.length - 1] : text;
  return { sid: sidOut, msg: JSON.parse(payload), status: res.status };
}

async function session() {
  if (fs.existsSync(SESSION_FILE)) {
    const sid = fs.readFileSync(SESSION_FILE, "utf8").trim();
    const r = await rpc({ jsonrpc: "2.0", id: 0, method: "tools/list", params: {} }, sid);
    if (r.status === 200 && r.msg && !r.msg.error) return sid;
  }
  const init = await rpc({ jsonrpc: "2.0", id: 1, method: "initialize",
    params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "claude-code-cli", version: "1" } } });
  await rpc({ jsonrpc: "2.0", method: "notifications/initialized" }, init.sid);
  fs.writeFileSync(SESSION_FILE, init.sid);
  return init.sid;
}

const [tool, argRaw] = process.argv.slice(2);
const sid = await session();
if (tool === "--list") {
  const r = await rpc({ jsonrpc: "2.0", id: 2, method: "tools/list", params: {} }, sid);
  for (const t of r.msg.result.tools) console.log(`- ${t.name}: ${(t.description || "").split("\n")[0]}\n  args: ${JSON.stringify(t.inputSchema?.properties || {})}`);
  process.exit(0);
}
let args = {};
if (argRaw) args = argRaw.startsWith("@") ? JSON.parse(fs.readFileSync(argRaw.slice(1), "utf8")) : JSON.parse(argRaw);
const r = await rpc({ jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: tool, arguments: args } }, sid);
if (r.msg?.error) { console.error("HATA:", JSON.stringify(r.msg.error)); process.exit(1); }
const content = r.msg?.result?.content || [];
for (const c of content) {
  if (c.type === "text") console.log(c.text);
  else if (c.type === "image") {
    const out = process.env.MCP_IMAGE_OUT || path.join(os.tmpdir(), `penpot-mcp-${Date.now()}.png`);
    fs.writeFileSync(out, Buffer.from(c.data, "base64"));
    console.log(`[görsel kaydedildi: ${out}]`);
  } else console.log(JSON.stringify(c));
}
if (r.msg?.result?.isError) process.exit(1);
