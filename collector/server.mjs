// collector/server.mjs — the Vantage community-intel collector as a plain Node
// HTTP service, for self-hosting on a VPS (Coolify, Docker, bare Node — anything).
// Same gate as the Cloudflare Worker; the only difference is the I/O shell.
//
// Config (all via env; sensible defaults so it runs with none):
//   PORT          listen port                         (default 8080)
//   DB_PATH       SQLite file                          (default /data/intel.db)
//   SEED_PATH     datamined cross-check seed JSON      (optional; none -> all pending)
//   SALT          salt for hashing contributor IPs     (optional but recommended)
//   ADMIN_TOKEN   bearer token gating GET /candidates  (optional; unset -> open)
//   ALLOW_ORIGIN  CORS origin for the report page      (default *)
//   RATE_MAX      submits per IP per minute            (default 30)
//
// Routes: POST /submit · GET /candidates?status=verified · GET /health
import { createServer } from "node:http";
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync, renameSync, existsSync, mkdirSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { openDb } from "./db.mjs";
import { ingest } from "./ingest.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));

const PORT = Number(process.env.PORT || 8080);
const DB_PATH = process.env.DB_PATH || "/data/intel.db";
const SALT = process.env.SALT || "";
const ADMIN_TOKEN = process.env.ADMIN_TOKEN || "";
const ALLOW_ORIGIN = process.env.ALLOW_ORIGIN || "*";
const RATE_MAX = Number(process.env.RATE_MAX || 30);
const MAX_BODY = 512 * 1024;       // 512 KB is plenty for a learned-spell payload
const MAX_SEED = 32 * 1024 * 1024; // the seed (~1 MB today) is admin-only, so allow room

if (DB_PATH !== ":memory:" && !existsSync(dirname(DB_PATH))) mkdirSync(dirname(DB_PATH), { recursive: true });
const db = openDb(DB_PATH);

// Seed can be updated on the volume without a restart: we reload it only when the
// file's mtime changes (it's ~1 MB, so we don't want to parse it every request).
// A missing/broken seed just means "no cross-check" -> everything pends, safely.
let seedCache = { mtime: 0, data: null };
function loadSeed() {
  const path = process.env.SEED_PATH;
  if (!path || !existsSync(path)) return null;
  try {
    const mtime = statSync(path).mtimeMs;
    if (mtime !== seedCache.mtime) seedCache = { mtime, data: JSON.parse(readFileSync(path, "utf8")) };
    return seedCache.data;
  } catch { return null; }
}

// Tiny in-memory per-IP rate limiter (single instance, so a Map is enough).
const hits = new Map();
function rateLimited(ip) {
  const now = Date.now(), win = 60_000;
  const rec = hits.get(ip) || { n: 0, t: now };
  if (now - rec.t > win) { rec.n = 0; rec.t = now; }
  rec.n++; hits.set(ip, rec);
  return rec.n > RATE_MAX;
}
setInterval(() => { const cut = Date.now() - 120_000; for (const [k, v] of hits) if (v.t < cut) hits.delete(k); }, 120_000).unref();

// The admin dashboard is one self-contained HTML file baked into the image.
let adminHtml;
function loadAdminHtml() {
  if (adminHtml === undefined) {
    try { adminHtml = readFileSync(join(HERE, "admin.html"), "utf8"); } catch { adminHtml = ""; }
  }
  return adminHtml;
}

const cors = {
  "Access-Control-Allow-Origin": ALLOW_ORIGIN,
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};
const send = (res, status, obj) =>
  res.writeHead(status, { "Content-Type": "application/json", ...cors }).end(JSON.stringify(obj));

function clientIp(req) {
  return (req.headers["x-forwarded-for"] || "").split(",")[0].trim() || req.socket.remoteAddress || "";
}

function readBody(req, max = MAX_BODY) {
  return new Promise((resolve, reject) => {
    let n = 0, chunks = [];
    req.on("data", (c) => { n += c.length; if (n > max) reject(new Error("body too large")); else chunks.push(c); });
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", reject);
  });
}

const server = createServer(async (req, res) => {
  const url = new URL(req.url, "http://x");
  try {
    if (req.method === "OPTIONS") return res.writeHead(204, cors).end();
    if (url.pathname === "/health") return send(res, 200, { ok: true });

    if (req.method === "POST" && url.pathname === "/submit") {
      const ip = clientIp(req);
      if (rateLimited(ip)) return send(res, 429, { ok: false, error: "slow down" });
      let body;
      try { body = JSON.parse(await readBody(req)); } catch { return send(res, 400, { ok: false, error: "bad json" }); }
      const ipHash = SALT ? createHash("sha256").update(ip + SALT).digest("hex") : "";
      const result = ingest(db, body, { seed: loadSeed(), now: Math.floor(Date.now() / 1000), ip: ipHash });
      return send(res, result.ok ? 200 : 400, result);
    }

    if (req.method === "GET" && url.pathname === "/candidates") {
      if (ADMIN_TOKEN && req.headers.authorization !== `Bearer ${ADMIN_TOKEN}`)
        return send(res, 401, { ok: false, error: "unauthorized" });
      return send(res, 200, { ok: true, candidates: db.candidates(url.searchParams.get("status") || "verified") });
    }

    // Admin dashboard: the HTML shell is public (inert without a token); its data
    // endpoint is gated exactly like /candidates.
    if (req.method === "GET" && url.pathname === "/admin") {
      const html = loadAdminHtml();
      if (!html) return send(res, 404, { ok: false, error: "admin page not bundled" });
      return res.writeHead(200, { "Content-Type": "text/html; charset=utf-8", ...cors }).end(html);
    }

    if (req.method === "GET" && url.pathname === "/admin/data") {
      if (ADMIN_TOKEN && req.headers.authorization !== `Bearer ${ADMIN_TOKEN}`)
        return send(res, 401, { ok: false, error: "unauthorized" });
      const since = Math.floor(Date.now() / 1000) - 30 * 86400;
      return send(res, 200, {
        ok: true,
        stats: db.stats(),
        candidates: db.allCandidates(),
        recentSubmissions: db.recentSubmissions(100),
        versions: db.versionBreakdown(),
        activity: db.dailyActivity(since),
      });
    }

    // Push a freshly-built cross-check seed (from the GitHub Action / build-seed.mjs).
    // Admin-only by construction: a seed that marks everything interruptible would
    // be a poison vector, so this REFUSES unless ADMIN_TOKEN is set and matches.
    if (req.method === "POST" && url.pathname === "/seed") {
      if (!ADMIN_TOKEN || req.headers.authorization !== `Bearer ${ADMIN_TOKEN}`)
        return send(res, 401, { ok: false, error: "unauthorized" });
      if (!process.env.SEED_PATH) return send(res, 400, { ok: false, error: "SEED_PATH not configured" });
      let seed;
      try { seed = JSON.parse(await readBody(req, MAX_SEED)); } catch { return send(res, 400, { ok: false, error: "bad json" }); }
      if (!seed || typeof seed !== "object" || Array.isArray(seed)) return send(res, 400, { ok: false, error: "seed must be an object" });
      // atomic replace so a concurrent /submit never reads a half-written file
      const tmp = process.env.SEED_PATH + ".tmp";
      writeFileSync(tmp, JSON.stringify(seed));
      renameSync(tmp, process.env.SEED_PATH);
      seedCache = { mtime: 0, data: null }; // force reload on next /submit
      const spells = Object.keys(seed).filter((k) => k[0] !== "_").length;
      return send(res, 200, { ok: true, spells });
    }

    return send(res, 404, { ok: false, error: "not found" });
  } catch (e) {
    return send(res, 500, { ok: false, error: String((e && e.message) || e) });
  }
});

server.listen(PORT, () => console.log(`Vantage intel collector on :${PORT} (db ${DB_PATH})`));
