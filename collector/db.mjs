// collector/db.mjs — SQLite storage for the Node/Coolify collector.
//
// Wraps better-sqlite3 behind the handful of operations the ingest logic needs,
// so all SQL lives here and the rest of the service stays storage-agnostic.
// Applies the SAME schema.sql the Cloudflare/D1 path uses — one schema source.
//
// The distinct-confirmer gate is enforced in the DB, not in app code: the
// `confirmation` table's (spell_id, uuid) primary key makes a repeat submission
// from the same install an UPSERT, so `confirmers` can't be inflated by one
// attacker replaying the payload.
import Database from "better-sqlite3";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const HERE = dirname(fileURLToPath(import.meta.url));

function uniqPush(jsonArr, value, cap = 50) {
  if (value == null) return jsonArr ?? "[]";
  const a = JSON.parse(jsonArr || "[]");
  if (!a.includes(value)) a.push(value);
  return JSON.stringify(a.slice(0, cap));
}

export function openDb(path = ":memory:") {
  const db = new Database(path);
  db.pragma("journal_mode = WAL"); // safe concurrent reads while promote.mjs pulls
  db.pragma("busy_timeout = 5000");
  db.exec(readFileSync(join(HERE, "schema.sql"), "utf8"));

  const st = {
    confirm: db.prepare(
      `INSERT INTO confirmation (spell_id, uuid, n, at) VALUES (@id, @uuid, @n, @at)
       ON CONFLICT(spell_id, uuid) DO UPDATE SET n = n + excluded.n, at = excluded.at`
    ),
    stats: db.prepare(
      `SELECT COUNT(*) AS c, COALESCE(SUM(n),0) AS r FROM confirmation WHERE spell_id = ?`
    ),
    arrays: db.prepare(`SELECT npcs, zones, interrupts FROM candidate WHERE spell_id = ?`),
    upsert: db.prepare(
      `INSERT INTO candidate (spell_id, name, status, confirmers, reports, npcs, zones, interrupts, reason, first_seen, last_seen)
       VALUES (@id, @name, @status, @confirmers, @reports, @npcs, @zones, @interrupts, @reason, @at, @at)
       ON CONFLICT(spell_id) DO UPDATE SET
         confirmers = @confirmers, reports = @reports, npcs = @npcs, zones = @zones,
         interrupts = @interrupts, last_seen = @at,
         -- a promoted/rejected verdict is sticky; otherwise take the new status
         status = CASE WHEN candidate.status IN ('promoted','rejected') THEN candidate.status ELSE @status END`
    ),
    submission: db.prepare(
      `INSERT INTO submission (uuid, ip_hash, version, spells, at) VALUES (@uuid, @ip, @version, @spells, @at)`
    ),
    byStatus: db.prepare(`SELECT * FROM candidate WHERE status = ? ORDER BY spell_id`),
  };

  return {
    raw: db,
    // Record one confirmed spell; returns the fresh distinct-confirmer count.
    recordSpell(s, verdict, reason, now) {
      st.confirm.run({ id: s.id, uuid: s.uuid, n: s.n, at: now });
      const agg = st.stats.get(s.id);
      const cur = st.arrays.get(s.id);
      st.upsert.run({
        id: s.id, name: s.name,
        status: verdict === "verified" ? "verified" : "pending",
        confirmers: agg.c, reports: agg.r,
        npcs: uniqPush(cur?.npcs, s.npc),
        zones: uniqPush(cur?.zones, s.zone),
        interrupts: uniqPush(cur?.interrupts, s.by),
        reason, at: now,
      });
      return agg.c;
    },
    recordSubmission(row) { st.submission.run(row); },
    candidates(status = "verified") { return st.byStatus.all(status); },
    close() { db.close(); },
  };
}
