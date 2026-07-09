// collector/test.mjs — node tests for the collector's pure logic.
// Run: node collector/test.mjs
import { validateSubmission, crossCheck, promotable, selectPromotable } from "./lib.mjs";
import { parseCuratedDeny, renderPackBody, splicePack } from "./promote.mjs";
import { openDb } from "./db.mjs";
import { ingest } from "./ingest.mjs";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

let n = 0, fails = [];
const ok = (c, m) => { n++; if (!c) fails.push(m); };
const eq = (a, b, m) => { n++; if (JSON.stringify(a) !== JSON.stringify(b)) fails.push(`${m} (got ${JSON.stringify(a)})`); };

const HERE = dirname(fileURLToPath(import.meta.url));
const seed = JSON.parse(readFileSync(join(HERE, "seed.example.json"), "utf8"));

// ---- validateSubmission ----------------------------------------------------
ok(!validateSubmission(null).ok, "null body rejected");
ok(!validateSubmission({ kind: "nope", uuid: "abcd1234", spells: [{ id: 1, name: "x" }] }).ok, "wrong kind rejected");
ok(!validateSubmission({ kind: "vantage-intel", uuid: "!!", spells: [{ id: 1, name: "x" }] }).ok, "bad uuid rejected");
ok(!validateSubmission({ kind: "vantage-intel", uuid: "abcd1234", spells: [] }).ok, "empty spells rejected");

const good = validateSubmission({
  kind: "vantage-intel", uuid: "abcd1234-5678-4abc-9def-0123456789ab", version: "0.11.0",
  spells: [
    { id: 9771, name: "Radiation Bolt", zone: "Gnomeregan", by: "Counterspell", npc: 7053, n: 3 },
    { id: 0, name: "bad id" },              // dropped: bad id
    { name: "no id" },                       // dropped: no id
    { id: 9771, name: "dup" },               // dropped: duplicate id
    { id: 500, name: "Some Cast", npc: -1 }, // kept; bad npc nulled
  ],
});
ok(good.ok, "valid submission accepted");
eq(good.spells.length, 2, "id-less / dup / bad-id rows dropped");
eq(good.spells[0].npc, 7053, "npc kept");
eq(good.spells[1].npc, null, "negative npc nulled");

// ---- crossCheck ------------------------------------------------------------
eq(crossCheck({ id: 9771, name: "Radiation Bolt", npc: 7053, zone: "Gnomeregan" }, seed).verdict, "verified", "seed match verifies");
eq(crossCheck({ id: 9771, name: "Radiation Bolt", npc: 99999 }, seed).verdict, "rejected", "wrong caster rejected");
eq(crossCheck({ id: 9771, name: "Totally Wrong", npc: 7053 }, seed).verdict, "rejected", "name mismatch rejected");
eq(crossCheck({ id: 44201, name: "Tranquility" }, seed).verdict, "rejected", "known padlock hard-rejected");
eq(crossCheck({ id: 424242, name: "Unknown Cast" }, seed).verdict, "pending", "unseen spell stays pending");
eq(crossCheck({ id: 9771, name: "Radiation Bolt" }, null).verdict, "pending", "no seed at all -> pending");

// ---- promotable + selectPromotable ----------------------------------------
ok(promotable({ status: "verified", confirmers: 3 }), "3 verified confirmers promotes");
ok(!promotable({ status: "verified", confirmers: 2 }), "2 confirmers does not promote");
ok(!promotable({ status: "pending", confirmers: 9 }), "pending never promotes regardless of count");

const kickableLua = readFileSync(join(HERE, "..", "Data", "KickableSpells.lua"), "utf8");
const deny = parseCuratedDeny(kickableLua);
ok(deny.ids.size > 0 && deny.names.size > 0, "curated denylist parsed from KickableSpells.lua");

const candidates = [
  { spell_id: 9771, name: "Radiation Bolt", status: "verified", confirmers: 5, zones: '["Gnomeregan"]' },
  { spell_id: 500,  name: "New Cast",       status: "verified", confirmers: 4, zones: "[]" },
  { spell_id: 501,  name: "Too Few",        status: "verified", confirmers: 1, zones: "[]" },
  { spell_id: 502,  name: "Still Pending",  status: "pending",  confirmers: 9, zones: "[]" },
];
// inject a curated spell to prove the denylist refuses it even if "verified"
const curatedId = [...deny.ids][0];
candidates.push({ spell_id: curatedId, name: "Curated Thing", status: "verified", confirmers: 9, zones: "[]" });

const chosen = selectPromotable(candidates, { minConfirmers: 3, denyIds: deny.ids, denyNames: deny.names });
ok(chosen.some((c) => c.spell_id === 9771), "well-confirmed gap-fill promoted");
ok(chosen.some((c) => c.spell_id === 500), "second gap-fill promoted");
ok(!chosen.some((c) => c.spell_id === 501), "under-threshold not promoted");
ok(!chosen.some((c) => c.spell_id === 502), "pending not promoted");
ok(!chosen.some((c) => c.spell_id === curatedId), "curated spell refused by denylist (poison-proof)");

// ---- pack rendering + splice ----------------------------------------------
const body = renderPackBody(chosen);
ok(body.includes("add(9771,"), "rendered an add() call");
const packLua = readFileSync(join(HERE, "..", "Data", "CommunityPack.lua"), "utf8");
const spliced = splicePack(packLua, body);
ok(spliced.includes("VANTAGE:PACK-START") && spliced.includes("VANTAGE:PACK-END"), "markers preserved after splice");
ok(spliced.includes("add(9771,"), "spliced body contains the entry");
ok(!spliced.includes("Curated Thing"), "curated spell never written into the pack");

// ---- DB-backed ingest: the distinct-confirmer gate against real SQLite -------
const submit = (uuid, spells) => ({
  kind: "vantage-intel", uuid, version: "0.11.0", spells,
});
{
  const db = openDb(":memory:");
  const S = { id: 424242, name: "Unknown Cast", npc: 555, zone: "Gnomeregan", by: "Kick", n: 1 };

  // No seed -> the cross-check can't verify, so it stays pending regardless of count.
  ingest(db, submit("aaaa1111-0000-4000-8000-000000000001", [S]), { now: 100 });
  ingest(db, submit("aaaa1111-0000-4000-8000-000000000001", [S]), { now: 101 }); // SAME install repeats
  let c = db.candidates("pending");
  eq(c.length, 1, "one pending candidate created");
  eq(c[0].confirmers, 1, "same install submitting twice counts as ONE confirmer (Sybil-safe)");
  eq(c[0].reports, 2, "but total reports still tallies both");

  // A second and third DISTINCT install push it over the confirmer bar — but it's
  // still only promotable once a seed VERIFIES it (pending never promotes).
  ingest(db, submit("bbbb2222-0000-4000-8000-000000000002", [S]), { now: 102 });
  ingest(db, submit("cccc3333-0000-4000-8000-000000000003", [S]), { now: 103 });
  c = db.candidates("pending");
  eq(c[0].confirmers, 3, "three distinct installs -> three confirmers");
  ok(!promotable({ status: c[0].status, confirmers: c[0].confirmers }), "still not promotable without a seed verify");

  // Now the same spell, seen with a seed that verifies it, flips to 'verified'.
  const vseed = { 424242: { name: "Unknown Cast", npcs: [555] } };
  const r = ingest(db, submit("dddd4444-0000-4000-8000-000000000004", [S]), { now: 104, seed: vseed });
  eq(r.accepted, 1, "verified submission accepted");
  eq(r.pending, 0, "not counted as pending when the seed verifies");
  const vc = db.candidates("verified");
  ok(vc.some((x) => x.spell_id === 424242 && x.confirmers === 4), "candidate now verified with 4 confirmers -> promotable");

  // A seed-rejected spell (known padlock) never stages at all.
  const rej = ingest(db, submit("eeee5555-0000-4000-8000-000000000005",
    [{ id: 44201, name: "Tranquility", n: 1 }]), { now: 105, seed });
  eq(rej.rejected, 1, "seed-rejected padlock refused at ingest");
  eq(db.candidates("verified").filter((x) => x.spell_id === 44201).length, 0, "rejected spell never staged");
  db.close();
}

if (fails.length) { console.error(`FAIL ${fails.length}/${n}:\n  - ${fails.join("\n  - ")}`); process.exit(1); }
console.log(`OK  ${n} collector checks passed`);
