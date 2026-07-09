// collector/worker.js — Cloudflare Worker for the Vantage community-intel pool.
//
// Deploy: see collector/README.md. Bindings expected (wrangler.toml):
//   - DB       : a D1 database (schema.sql applied)
//   - SEED     : (optional) a KV namespace holding the datamined cross-check seed
//                under key "seed" as JSON; absent -> everything stays 'pending'.
//   - SALT     : (optional secret) salt for hashing contributor IPs.
//
// Routes:
//   POST /submit   -> ingest one /vantage contribute payload
//   GET  /candidates?status=verified -> JSON dump for promote.mjs
//   GET  /health   -> ok
//
// It never trusts the client: the pure gate in lib.mjs validates + cross-checks,
// and the DB schema (confirmation PK) enforces distinct-contributor counting.

import { validateSubmission, crossCheck } from "./lib.mjs";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

const json = (obj, status = 200) =>
  new Response(JSON.stringify(obj), { status, headers: { "Content-Type": "application/json", ...CORS } });

async function sha256Hex(s) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function uniqPush(jsonArr, value) {
  if (value == null) return jsonArr;
  const a = JSON.parse(jsonArr || "[]");
  if (!a.includes(value)) a.push(value);
  return JSON.stringify(a.slice(0, 50)); // cap so a candidate row can't grow unbounded
}

async function loadSeed(env) {
  if (!env.SEED) return null;
  try { return JSON.parse((await env.SEED.get("seed")) || "null"); } catch { return null; }
}

async function handleSubmit(request, env) {
  let body;
  try { body = await request.json(); } catch { return json({ ok: false, error: "bad json" }, 400); }

  const v = validateSubmission(body);
  if (!v.ok) return json({ ok: false, error: v.errors.join(", ") }, 400);

  const seed = await loadSeed(env);
  const now = Math.floor(Date.now() / 1000);
  const ipHash = await sha256Hex((request.headers.get("cf-connecting-ip") || "") + (env.SALT || ""));

  let accepted = 0, rejected = 0, pending = 0;
  for (const s of v.spells) {
    const check = crossCheck(s, seed);
    if (check.verdict === "rejected") { rejected++; continue; }

    // Record this install's confirmation (UPSERT -> a repeat install is idempotent).
    await env.DB.prepare(
      `INSERT INTO confirmation (spell_id, uuid, n, at) VALUES (?1, ?2, ?3, ?4)
       ON CONFLICT(spell_id, uuid) DO UPDATE SET n = n + excluded.n, at = excluded.at`
    ).bind(s.id, v.uuid, s.n, now).run();

    // Distinct-confirmer count comes straight from the ledger — not client-controlled.
    const row = await env.DB.prepare(
      `SELECT COUNT(*) AS c, COALESCE(SUM(n),0) AS r FROM confirmation WHERE spell_id = ?1`
    ).bind(s.id).first();

    const existing = await env.DB.prepare(`SELECT npcs, zones, interrupts FROM candidate WHERE spell_id = ?1`)
      .bind(s.id).first();
    const npcs = uniqPush(existing?.npcs, s.npc);
    const zones = uniqPush(existing?.zones, s.zone);
    const interrupts = uniqPush(existing?.interrupts, s.by);
    // 'pending' is sticky-forward: a no-seed spell never auto-verifies, but a
    // rejected verdict never demotes a spell that a fuller seed later verified.
    const status = check.verdict === "verified" ? "verified" : "pending";

    await env.DB.prepare(
      `INSERT INTO candidate (spell_id, name, status, confirmers, reports, npcs, zones, interrupts, reason, first_seen, last_seen)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?10)
       ON CONFLICT(spell_id) DO UPDATE SET
         confirmers = ?4, reports = ?5, npcs = ?6, zones = ?7, interrupts = ?8,
         last_seen = ?10,
         status = CASE WHEN candidate.status IN ('promoted','rejected') THEN candidate.status ELSE ?3 END`
    ).bind(s.id, s.name, status, row.c, row.r, npcs, zones, interrupts, check.reason, now).run();

    accepted++;
    if (status === "pending") pending++;
  }

  await env.DB.prepare(`INSERT INTO submission (uuid, ip_hash, version, spells, at) VALUES (?1,?2,?3,?4,?5)`)
    .bind(v.uuid, ipHash, v.version, v.spells.length, now).run();

  return json({ ok: true, accepted, rejected, pending });
}

async function handleCandidates(request, env) {
  const url = new URL(request.url);
  const status = url.searchParams.get("status") || "verified";
  const { results } = await env.DB.prepare(
    `SELECT * FROM candidate WHERE status = ?1 ORDER BY spell_id`
  ).bind(status).all();
  return json({ ok: true, candidates: results || [] });
}

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return new Response(null, { headers: CORS });
    const url = new URL(request.url);
    try {
      if (request.method === "POST" && url.pathname === "/submit") return await handleSubmit(request, env);
      if (request.method === "GET" && url.pathname === "/candidates") return await handleCandidates(request, env);
      if (url.pathname === "/health") return json({ ok: true });
    } catch (e) {
      return json({ ok: false, error: String(e && e.message || e) }, 500);
    }
    return json({ ok: false, error: "not found" }, 404);
  },
};
