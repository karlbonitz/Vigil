// collector/build-seed.mjs — build the cross-check seed from wago.tools.
//
// The seed is what turns gate #2 (crossCheck) from "manual review only" into
// "auto-verify from day one". Its core is the spellID↔name binding straight from
// the game's own data: a submission for spell 9771 "Radiation Bolt" verifies
// because the seed confirms 9771 really is named that — which rejects typo'd
// names, made-up IDs, and mismatches without trusting the submitter at all.
// (The submission already proves interruptibility — someone interrupted it — so
// the seed's job is only to confirm the ID is a real spell with that name.)
//
// On top of that it folds in Vantage's OWN curated padlocks as interruptible:false
// so a known "do not kick" is hard-rejected at ingest, not just at promote time.
//
// Usage:
//   node collector/build-seed.mjs                 # latest wow_anniversary build
//   node collector/build-seed.mjs --build 2.5.6.68502 --out seed.json --pretty
//   node collector/build-seed.mjs --product wow_classic_era
//
// Then put the file on your collector's volume and point SEED_PATH at it.
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const HERE = dirname(fileURLToPath(import.meta.url));
const KICKABLE = join(HERE, "..", "Data", "KickableSpells.lua");

function arg(name, def) {
  const i = process.argv.indexOf(name);
  return i !== -1 ? process.argv[i + 1] : def;
}

async function latestBuild(product) {
  const res = await fetch("https://wago.tools/api/builds");
  if (!res.ok) throw new Error(`builds API: HTTP ${res.status}`);
  const data = await res.json();
  const list = data[product];
  if (!list || !list.length) throw new Error(`no builds for product "${product}"`);
  return list[0].version; // newest first
}

// Two-column CSV (ID,Name_lang) with RFC-style quoting. Spell names never contain
// newlines, so a line-at-a-time split is safe; only the name field can be quoted.
function parseSpellNameCsv(csv) {
  const map = new Map();
  const lines = csv.split("\n");
  for (let i = 1; i < lines.length; i++) {
    const line = lines[i].replace(/\r$/, "");
    if (!line) continue;
    const c = line.indexOf(",");
    if (c === -1) continue;
    const id = Number(line.slice(0, c));
    if (!Number.isInteger(id)) continue;
    let name = line.slice(c + 1);
    if (name.startsWith('"') && name.endsWith('"')) name = name.slice(1, -1).replace(/""/g, '"');
    if (name) map.set(id, name);
  }
  return map;
}

// Pull curated padlock NAMES and IDs (interruptible = false) and any byID KICKS
// (interruptible = true) from KickableSpells.lua. Each entry is one line, so line
// parsing is reliable and dodges the nested `zones = { … }` braces.
function parseCurated(lua) {
  const padlockNames = new Set(), padlockIds = new Set(), kickIds = new Set();
  for (const line of lua.split("\n")) {
    const nm = line.match(/^\s*\["([^"]+)"\]\s*=\s*\{/);
    const idm = line.match(/^\s*\[(\d+)\]\s*=\s*\{/);
    const isFalse = /interruptible\s*=\s*false/.test(line);
    const isTrue = /interruptible\s*=\s*true/.test(line);
    if (nm && isFalse) padlockNames.add(nm[1].toLowerCase());
    if (idm && isFalse) padlockIds.add(Number(idm[1]));
    if (idm && isTrue) kickIds.add(Number(idm[1]));
  }
  return { padlockNames, padlockIds, kickIds };
}

async function main() {
  const product = arg("--product", "wow_anniversary");
  const build = arg("--build") || await latestBuild(product);
  const out = arg("--out", join(HERE, "seed.json"));
  const pretty = process.argv.includes("--pretty");

  console.log(`Building seed for ${product} ${build}…`);
  const res = await fetch(`https://wago.tools/db2/SpellName/csv?build=${encodeURIComponent(build)}`);
  if (!res.ok) throw new Error(`SpellName CSV: HTTP ${res.status}`);
  const names = parseSpellNameCsv(await res.text());
  console.log(`  ${names.size} spell names`);

  // 1) id -> { name } for every spell (the auto-verify binding).
  const seed = {};
  for (const [id, name] of names) seed[id] = { name };

  // 2) mark curated padlocks uninterruptible. A byName padlock marks EVERY spell
  //    of that name (mirrors the addon's own byName semantics). A byID curated
  //    KICK then overrides, so a specific kickable ID isn't wrongly locked.
  const { padlockNames, padlockIds, kickIds } = parseCurated(readFileSync(KICKABLE, "utf8"));
  const byNameLower = new Map();
  for (const [id, name] of names) {
    const k = name.toLowerCase();
    (byNameLower.get(k) || byNameLower.set(k, []).get(k)).push(id);
  }
  let locked = 0;
  for (const nm of padlockNames) for (const id of (byNameLower.get(nm) || [])) { seed[id].interruptible = false; locked++; }
  for (const id of padlockIds) if (seed[id]) { seed[id].interruptible = false; locked++; }
  for (const id of kickIds) if (seed[id]) delete seed[id].interruptible; // kick wins over a name-collision lock

  const meta = { _product: product, _build: build, _spells: names.size, _padlocks: locked };
  writeFileSync(out, JSON.stringify(Object.assign(meta, seed), null, pretty ? 2 : 0));
  const kb = (readFileSync(out).length / 1024).toFixed(0);
  console.log(`  ${locked} entries marked uninterruptible (curated padlocks)`);
  console.log(`Wrote ${out} (${kb} KB).`);
  console.log(`Deploy: copy it to your collector volume and set SEED_PATH to it, e.g.`);
  console.log(`  scp ${out} youruser@yourvps:/path/to/volume/seed.json   (then SEED_PATH=/data/seed.json)`);
}

main().catch((e) => { console.error("build-seed failed:", e.message); process.exit(1); });
