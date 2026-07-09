// collector/promote.mjs — regenerate Data/CommunityPack.lua from the pool.
//
// Usage:
//   node collector/promote.mjs candidates.json        # from a saved dump
//   node collector/promote.mjs --url https://<worker>  # fetch verified candidates
//   node collector/promote.mjs --url <worker> --min 3 --dry
//
// It applies the SAFETY INVARIANT that makes poisoning a non-event: the curated
// Intel Pack (Data/KickableSpells.lua) is parsed into a denylist, and anything on
// it — every hand-verified padlock and kick — is refused here, so the community
// pool can only ever fill genuine gaps. Then it rewrites only the region between
// the PACK markers, leaving the file's add() mechanism and comments intact.
//
// This is your human gate: run it, read the diff it produces, and only the
// entries you ship in the next release reach players.

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { selectPromotable } from "./lib.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const KICKABLE = join(HERE, "..", "Data", "KickableSpells.lua");
const PACK = join(HERE, "..", "Data", "CommunityPack.lua");
const START = "-- VANTAGE:PACK-START (generated — see collector/promote.mjs)";
const END = "-- VANTAGE:PACK-END";

// Build the denylist of everything the curated pack already speaks for: every
// numeric spellID and every lowercased spell name that appears in KickableSpells.
export function parseCuratedDeny(luaText) {
  const ids = new Set();
  const names = new Set();
  for (const m of luaText.matchAll(/\[(\d+)\]/g)) ids.add(Number(m[1]));
  for (const m of luaText.matchAll(/\["([^"]+)"\]/g)) names.add(m[1].toLowerCase());
  return { ids, names };
}

function luaStr(s) {
  return '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
}

// Render the generated body (the add() calls) for a list of promotable rows.
export function renderPackBody(spells) {
  if (!spells.length) return "-- (no community entries yet — this fills in as players contribute)";
  return spells
    .map((s) => `add(${s.spell_id}, ${luaStr(s.name)})  -- ${s.confirmers} confirmers` +
      (s.zones && s.zones !== "[]" ? `, ${s.zones}` : ""))
    .join("\n");
}

// Splice a fresh body between the PACK markers of the current file.
export function splicePack(fileText, body) {
  const i = fileText.indexOf(START);
  const j = fileText.indexOf(END);
  if (i === -1 || j === -1 || j < i) throw new Error("PACK markers not found in CommunityPack.lua");
  return fileText.slice(0, i + START.length) + "\n" + body + "\n" + fileText.slice(j);
}

async function loadCandidates(arg) {
  const urlIdx = process.argv.indexOf("--url");
  if (urlIdx !== -1) {
    const base = process.argv[urlIdx + 1].replace(/\/$/, "");
    // If the collector gates /candidates, pass VANTAGE_ADMIN_TOKEN as a bearer.
    const headers = process.env.VANTAGE_ADMIN_TOKEN
      ? { Authorization: `Bearer ${process.env.VANTAGE_ADMIN_TOKEN}` } : {};
    const res = await fetch(`${base}/candidates?status=verified`, { headers });
    const data = await res.json();
    if (!data.ok && data.error) throw new Error(`collector: ${data.error}`);
    return data.candidates || [];
  }
  return JSON.parse(readFileSync(arg, "utf8")).candidates ?? JSON.parse(readFileSync(arg, "utf8"));
}

async function main() {
  const minIdx = process.argv.indexOf("--min");
  const min = minIdx !== -1 ? Number(process.argv[minIdx + 1]) : 3;
  const dry = process.argv.includes("--dry");
  const fileArg = process.argv.slice(2).find((a) => a.endsWith(".json"));

  const candidates = await loadCandidates(fileArg);
  const deny = parseCuratedDeny(readFileSync(KICKABLE, "utf8"));
  const chosen = selectPromotable(candidates, { minConfirmers: min, denyIds: deny.ids, denyNames: deny.names });

  const skipped = candidates.filter((c) => deny.ids.has(c.spell_id) || deny.names.has((c.name || "").toLowerCase()));
  console.log(`${candidates.length} verified candidates -> ${chosen.length} promoted (min ${min} confirmers)` +
    (skipped.length ? `; ${skipped.length} refused (already curated)` : ""));
  for (const s of chosen) console.log(`  + ${s.spell_id}  ${s.name}  (${s.confirmers} confirmers)`);

  const next = splicePack(readFileSync(PACK, "utf8"), renderPackBody(chosen));
  if (dry) { console.log("\n--dry: not written. Review the entries above."); return; }
  writeFileSync(PACK, next);
  console.log(`\nWrote ${PACK}. Review the diff, bump the version, and cut a release.`);
}

// Only run main() when invoked directly (so test.mjs can import the helpers).
if (process.argv[1] && process.argv[1].endsWith("promote.mjs")) {
  main().catch((e) => { console.error(e); process.exit(1); });
}
