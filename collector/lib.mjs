// collector/lib.mjs
//
// Pure logic for the Vantage community-intel collector — no I/O, no platform
// APIs, so it runs identically in a Cloudflare Worker and under `node test.mjs`.
//
// The whole design rests on one fact: interruptibility is ONE-DIRECTIONAL GROUND
// TRUTH. If anyone ever landed an interrupt on a cast, that cast is provably
// interruptible — a single real observation is proof, no voting needed. So the
// pool only ever ADDS "yes, kickable" facts; it can never mark something a
// padlock, and it can never override the addon's curated data.
//
// Poisoning is the only real risk (claiming an UNinterruptible cast is kickable
// -> a wasted-kick cue). Four gates, strongest first:
//   1. Structural: the addon's curated padlocks filter everything at promote time
//      (promote.mjs) and again at runtime (Vantage.GetKickInfo). Untouchable here.
//   2. Cross-check: every spell is checked against a datamined seed — the id↔name
//      binding, that it's an NPC cast, and (when known) that the caster/zone fit.
//      No seed match -> it stays 'pending' and cannot auto-promote.
//   3. Distinct confirmers: a spell needs N independent install tokens before it
//      is promotable. One attacker minting tokens is slowed; combined with (2)+(4)
//      it's not enough to ship anything.
//   4. Human gate: promotion feeds a release YOU cut. Bad data piles up harmlessly
//      in staging and never reaches a player without passing your eyeball.

export const MAX_SPELLS = 2000;
export const DEFAULT_MIN_CONFIRMERS = 3;

const UUID_RE = /^[0-9a-fA-F-]{8,64}$/;

function isPosInt(v) {
  return typeof v === "number" && Number.isInteger(v) && v > 0;
}

// Validate + normalize a raw submission body. Never throws; returns a report.
export function validateSubmission(body) {
  const errors = [];
  if (!body || typeof body !== "object") return { ok: false, errors: ["not an object"], spells: [] };
  if (body.kind !== "vantage-intel") errors.push("wrong kind");
  if (typeof body.uuid !== "string" || !UUID_RE.test(body.uuid)) errors.push("bad uuid");
  if (!Array.isArray(body.spells)) errors.push("spells not an array");
  else if (body.spells.length === 0) errors.push("no spells");
  else if (body.spells.length > MAX_SPELLS) errors.push("too many spells");
  if (errors.length) return { ok: false, errors, spells: [] };

  const spells = [];
  const seen = new Set();
  for (const s of body.spells) {
    // We key on spellID — a name alone can collide (e.g. two "Mind Blast"s), and
    // can't be cross-checked reliably. Drop id-less rows rather than trust them.
    if (!s || !isPosInt(s.id) || typeof s.name !== "string" || !s.name) continue;
    if (seen.has(s.id)) continue;
    seen.add(s.id);
    spells.push({
      id: s.id,
      name: s.name.slice(0, 80),
      zone: typeof s.zone === "string" ? s.zone.slice(0, 80) : null,
      by: typeof s.by === "string" ? s.by.slice(0, 80) : null,
      npc: isPosInt(s.npc) ? s.npc : null,
      n: isPosInt(s.n) ? Math.min(s.n, 100000) : 1,
    });
  }
  if (!spells.length) return { ok: false, errors: ["no usable spells"], spells: [] };
  return { ok: true, errors: [], uuid: body.uuid, version: String(body.version || ""), spells };
}

// Cross-check one normalized spell against the datamined seed.
//   seed: { [spellId]: { name, npcs?:[ids], zones?:[strings], interruptible?:bool } }
// Verdicts:
//   'rejected' — the seed positively contradicts it (uninterruptible, or name/npc
//                mismatch). This is the strongest signal we have; trust it.
//   'verified' — the seed confirms the id↔name binding (and caster/zone if given).
//   'pending'  — we have no seed row for it. Stage it, but it can't auto-promote;
//                a human (you, at release) or a fuller seed decides later.
export function crossCheck(spell, seed) {
  const ref = seed && seed[spell.id];
  if (!ref) return { verdict: "pending", reason: "no seed entry" };

  if (ref.interruptible === false) return { verdict: "rejected", reason: "seed says uninterruptible" };
  if (ref.name && ref.name.toLowerCase() !== spell.name.toLowerCase())
    return { verdict: "rejected", reason: "name mismatch vs seed" };
  if (spell.npc != null && Array.isArray(ref.npcs) && ref.npcs.length && !ref.npcs.includes(spell.npc))
    return { verdict: "rejected", reason: "caster not a known caster of this spell" };
  if (spell.zone && Array.isArray(ref.zones) && ref.zones.length &&
      !ref.zones.some((z) => z.toLowerCase() === spell.zone.toLowerCase()))
    return { verdict: "rejected", reason: "zone not where this spell is cast" };

  return { verdict: "verified", reason: "seed match" };
}

// Is a staged candidate ready to ship? Verified + enough independent confirmers.
export function promotable(candidate, opts = {}) {
  const min = opts.minConfirmers ?? DEFAULT_MIN_CONFIRMERS;
  return candidate.status === "verified" && (candidate.confirmers || 0) >= min;
}

// Fold a set of confirmed spells into an existing candidate map (used by promote
// and by the test; the Worker does the same thing via SQL). `denylist` is the set
// of curated spellIds/names the community pool must never touch.
export function selectPromotable(candidates, opts = {}) {
  const deny = opts.denyIds instanceof Set ? opts.denyIds : new Set();
  const denyNames = opts.denyNames instanceof Set ? opts.denyNames : new Set();
  return candidates
    .filter((c) => promotable(c, opts))
    .filter((c) => !deny.has(c.spell_id) && !denyNames.has((c.name || "").toLowerCase()))
    .sort((a, b) => a.spell_id - b.spell_id);
}
