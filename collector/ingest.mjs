// collector/ingest.mjs — turn one raw submission into staged rows.
//
// Pure of HTTP: takes a db handle (db.mjs) + the parsed body, runs the same
// validate + cross-check gate as the Cloudflare path (lib.mjs), and returns a
// summary. Shared by server.mjs and the tests.
import { validateSubmission, crossCheck } from "./lib.mjs";

export function ingest(db, body, { seed = null, now = 0, ip = "" } = {}) {
  const v = validateSubmission(body);
  if (!v.ok) return { ok: false, error: v.errors.join(", ") };

  let accepted = 0, rejected = 0, pending = 0;
  for (const s of v.spells) {
    const check = crossCheck(s, seed);
    if (check.verdict === "rejected") { rejected++; continue; }
    db.recordSpell({ ...s, uuid: v.uuid }, check.verdict, check.reason, now);
    accepted++;
    if (check.verdict !== "verified") pending++;
  }
  db.recordSubmission({ uuid: v.uuid, ip, version: v.version, spells: v.spells.length, at: now });
  return { ok: true, accepted, rejected, pending };
}
