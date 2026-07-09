# Vantage community intel collector

The backend for pooling self-learned kickable spells across every Vantage player.
It is **staging, not truth**: submissions land here, get cross-checked and
tallied, and nothing reaches a player until *you* regenerate
`Data/CommunityPack.lua` and cut a release. That release is the human gate.

```
in-game:  /vantage contribute ──► anonymous, evidence-bearing JSON blob
report page "Contribute" button ──► POST /submit
                                        │  validate → cross-check (seed) → stage
                                        ▼
                                 SQLite (candidate + confirmation ledger)
                                        │  node promote.mjs --url … --dry
                                        ▼
                        Data/CommunityPack.lua ──► CF/Wago release ──► everyone
```

## Why it's poison-resistant

Interruptibility is **one-directional ground truth** — if anyone ever interrupted
a cast, it's provably interruptible, so the pool only ever *adds* kicks; it can
never mark a padlock or override curated data. The only attack is claiming an
uninterruptible cast is kickable. Four gates stop it (see the header of
`lib.mjs`), and the live tests in `test.mjs` exercise each:

1. **Structural** — `promote.mjs` refuses any spell already in the curated pack
   (`Data/KickableSpells.lua`); `GetKickInfo` checks curated first at runtime.
2. **Cross-check** — `crossCheck()` verifies each spell against a datamined seed
   (id↔name, NPC, zone; a known padlock is hard-rejected). No seed match ⇒ the
   spell stays `pending` and cannot auto-promote.
3. **Distinct confirmers** — the `confirmation` table's `(spell_id, uuid)` primary
   key means one install can't inflate the count; promotion needs ≥N *distinct*
   anonymous tokens (default 3).
4. **Human gate** — you run `promote.mjs`, read the diff, and ship only what you
   choose.

Start strict (no seed ⇒ everything `pending` ⇒ you approve by hand), and automate
as trust grows by filling in the seed.

## Deploy on Coolify (self-hosted, recommended)

**Step-by-step runbook with exact values: [`DEPLOY.md`](DEPLOY.md).** The overview:
one container + one SQLite file on a persistent volume, no separate database
service to run.

1. **New Resource → your Git repo** (`github.com/karlbonitz/Vantage`).
2. Build Pack **Dockerfile**, **Base Directory** `/collector`. (Coolify builds
   `collector/Dockerfile`.)
3. **Persistent Storage**: mount a volume at **`/data`** (the SQLite file lives at
   `/data/intel.db` — back it up by copying that one file).
4. **Domain**: set e.g. `intel.yourdomain.com`; Coolify provisions HTTPS. Port
   `8080` is exposed.
5. **Environment variables**:
   | var | purpose |
   |-----|---------|
   | `SALT` | salt for hashing contributor IPs (set to any random string) |
   | `ADMIN_TOKEN` | bearer token that gates `GET /candidates` (set one) |
   | `ALLOW_ORIGIN` | your report-page origin, e.g. `https://karlbonitz.github.io` (or `*`) |
   | `SEED_PATH` | optional — e.g. `/data/seed.json` if you upload a cross-check seed to the volume |
   | `RATE_MAX` | optional — submits per IP per minute (default 30) |
6. Deploy. Check `https://intel.yourdomain.com/health` → `{"ok":true}`.

Then set `COLLECTOR_URL` in `docs/index.html` to `https://intel.yourdomain.com`
so the report page's **Contribute** button posts to `/submit`.

Run it anywhere else the same way: `docker build -t vantage-intel collector/ &&
docker run -p 8080:8080 -v vantage-data:/data -e SALT=… vantage-intel`, or just
`cd collector && npm install && DB_PATH=./intel.db npm start`.

## Operate

```bash
# Review what's verified and ready, without writing anything:
VANTAGE_ADMIN_TOKEN=… node collector/promote.mjs --url https://intel.yourdomain.com --dry

# Regenerate Data/CommunityPack.lua, then eyeball the git diff:
VANTAGE_ADMIN_TOKEN=… node collector/promote.mjs --url https://intel.yourdomain.com
git diff Data/CommunityPack.lua

# Bump the version + CHANGELOG, tag, push -> the release Action ships the pack.
```

Endpoints: `POST /submit`, `GET /candidates?status=verified|pending` (bearer-gated
if `ADMIN_TOKEN` is set), `POST /seed` (bearer-gated seed upload — see below),
`GET /health`.

### The cross-check seed

`seed.example.json` shows the shape: `{ spellId: { name, npcs?, zones?,
interruptible? } }`. With no seed, every submission stays `pending` and only your
manual review promotes anything — safe by default. **`build-seed.mjs` generates a
real one** from the game's own data on wago.tools:

```bash
node collector/build-seed.mjs                       # latest wow_anniversary build
node collector/build-seed.mjs --build 2.5.6.68502   # pin a build
# -> writes collector/seed.json (~1 MB, ~28.6k spells, curated padlocks locked)
```

It does two things: (1) the **spellID↔name binding** for every spell — this is
what auto-verifies a submission (real ID + matching name ⇒ `verified`; typo'd
name or made-up ID ⇒ rejected/pending), and (2) folds in Vantage's own curated
padlocks as `interruptible:false`, resolved to every real spellID of that name,
so a known "do not kick" is hard-rejected at ingest.

Then get it onto the collector's volume and point `SEED_PATH` at it:

```bash
scp collector/seed.json youruser@yourvps:/path/to/volume/seed.json   # SEED_PATH=/data/seed.json
```

The server reloads the seed when its mtime changes, so you can refresh it after a
patch (`node build-seed.mjs && scp …`) without a redeploy. `npcs`/`zones` fields
stay optional — hand-add them for a high-value spell to tighten the check
further; leaving them off just means the name binding does the verifying.

**Keep it current automatically.** `.github/workflows/seed.yml` rebuilds the seed
weekly (and on demand) and pushes it to the collector via `POST /seed` — no
commit, no redeploy. Set two repo secrets to enable delivery:

| secret | value |
|--------|-------|
| `COLLECTOR_URL` | `https://intel.yourdomain.com` |
| `COLLECTOR_ADMIN_TOKEN` | the same string as the collector's `ADMIN_TOKEN` |

`POST /seed` **requires** `ADMIN_TOKEN` to be set and matched — an unauthenticated
seed endpoint would itself be a poison vector (a seed marking everything
interruptible), so it refuses otherwise. The upload is written atomically and
picked up on the next `/submit`. Without the secrets the workflow still builds and
validates the seed but skips the upload, so it's safe to enable pre-deploy.

## Files

| file | role |
|------|------|
| `lib.mjs` | pure gate: validate, cross-check, promotion selection (no I/O) |
| `db.mjs` | SQLite storage (better-sqlite3), applies `schema.sql` |
| `ingest.mjs` | one submission → staged rows (shared by server + tests) |
| `server.mjs` | Node HTTP service (the container entrypoint) |
| `Dockerfile` | container image for Coolify / Docker |
| `schema.sql` | the staging schema (SQLite; also used by the D1 path) |
| `promote.mjs` | verified rows → `Data/CommunityPack.lua`, curated denylist applied |
| `build-seed.mjs` | generate the cross-check seed from wago.tools game data |
| `seed.example.json` | starter cross-check seed (shape reference) |
| `DEPLOY.md` | ordered Coolify deploy checklist with exact env values |
| `worker.js` | **alternative** Cloudflare Worker (D1 + KV) if you'd rather not self-host |
| `test.mjs` | `node test.mjs` — validation, cross-check, the distinct-confirmer + denylist gate, and pack rendering, against a real SQLite DB |

## Alternatives

- **Postgres instead of SQLite** — if you'd rather use a Coolify-managed database,
  swap `db.mjs` for a `pg` implementation exposing the same methods
  (`recordSpell`, `recordSubmission`, `candidates`). The schema is standard SQL.
- **Cloudflare** — `worker.js` + `schema.sql` on D1, seed in KV. See its header.
- **Zero-infra** — the same blob works as a GitHub issue: the report page opens a
  pre-filled `issues/new?labels=intel&body=…` when `COLLECTOR_URL` is blank; a
  small Action can parse `intel`-labeled issues with `promote.mjs`'s pure helpers.
