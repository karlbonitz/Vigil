# Deploy the collector on Coolify — checklist

Follow top to bottom once. ~20 minutes. Placeholders: `intel.yourdomain.com` (pick
a subdomain) and the two secrets you generate in step 0. Anything not listed here
has a safe default. Background + how it all fits together: `README.md`.

---

## 0. Before you start

- [ ] A VPS running Coolify, and your repo pushed to `github.com/karlbonitz/Vantage`.
- [ ] Generate the two secrets and **save them somewhere** — you'll paste each twice:

  ```bash
  openssl rand -hex 32      # -> SALT            (IP hashing)
  openssl rand -hex 32      # -> ADMIN_TOKEN     (gates /candidates and /seed)
  ```

## 1. DNS

- [ ] Add a DNS **A record**: `intel.yourdomain.com` → your VPS's public IP.
      (Coolify can't issue an HTTPS cert until this resolves.)

## 2. Create the app in Coolify

- [ ] **Project → New Resource → Public Repository**, URL `https://github.com/karlbonitz/Vantage`, branch `main`.
- [ ] **Build Pack: Dockerfile.**
- [ ] **Base Directory: `/collector`** (so Coolify builds `collector/Dockerfile`).
- [ ] **Ports Exposes: `8080`** (matches the Dockerfile's `EXPOSE`).

## 3. Persistent storage (the database + seed live here)

- [ ] **Storages → Add** a persistent volume, **Destination Path `/data`**.
      The SQLite DB (`/data/intel.db`) and seed (`/data/seed.json`) survive redeploys.
      Back up = copy those two files.

## 4. Domain + HTTPS

- [ ] **Domains**: `https://intel.yourdomain.com`. Coolify provisions the Let's Encrypt
      cert automatically once DNS (step 1) resolves.

## 5. Environment variables

Add these under **Environment Variables** (runtime). `PORT` and `DB_PATH` are already
baked into the image, so you only need:

| Name | Value |
|------|-------|
| `SALT` | *(the first `openssl` value from step 0)* |
| `ADMIN_TOKEN` | *(the second `openssl` value from step 0)* |
| `SEED_PATH` | `/data/seed.json` |
| `ALLOW_ORIGIN` | `https://karlbonitz.github.io` |

*(Optional: `RATE_MAX` submits/IP/min, default 30. `DB_PATH` default `/data/intel.db`.)*

## 6. Deploy + verify

- [ ] Click **Deploy**. Wait for green.
- [ ] Check it's live:

  ```bash
  curl https://intel.yourdomain.com/health      # -> {"ok":true}
  ```

## 7. Seed it (turns on auto-verify)

From your machine, in the repo:

- [ ] Build the seed and push it to the collector (`ADMIN_TOKEN` = your step-0 value):

  ```bash
  node collector/build-seed.mjs
  curl -fsS -X POST https://intel.yourdomain.com/seed \
    -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
    --data-binary @collector/seed.json
  # -> {"ok":true,"spells":28650}
  ```

  (After this the weekly Action in step 8 keeps it fresh — you won't do this by hand again.)

## 8. GitHub Actions secrets (auto seed-refresh + one-click promote)

In the repo: **Settings → Secrets and variables → Actions → New repository secret**:

- [ ] `COLLECTOR_URL` = `https://intel.yourdomain.com`
- [ ] `COLLECTOR_ADMIN_TOKEN` = *(same as `ADMIN_TOKEN`)*

Now `seed.yml` refreshes the seed weekly, and `promote.yml` (manual) can pull the pool.

## 9. Wire the report page

- [ ] In `docs/index.html`, set the constant:

  ```js
  const COLLECTOR_URL = "https://intel.yourdomain.com";
  ```

  Commit + push (GitHub Pages redeploys the page). **Ping me to re-sync the published
  report-page artifact** so the hosted copy matches. (Until this is set, the Contribute
  button falls back to opening a GitHub issue — still works, just more friction.)

## 10. In-game smoke test

- [ ] Interrupt an uncurated cast in a dungeon, `/vantage learned` lists it, then
      `/vantage contribute` → **Ctrl+C** → paste on the report page → **Contribute** →
      you get a "thank you, N confirmed / M pending" response.
- [ ] Confirm it landed: `curl -s "https://intel.yourdomain.com/candidates?status=pending" -H "Authorization: Bearer YOUR_ADMIN_TOKEN"`

## 11. First promotion → release

Once a few players have contributed (a spell needs ≥3 distinct confirmers + a seed match):

- [ ] **Actions → Promote community intel → Run workflow** (or `--min` of your choice).
- [ ] Review the PR it opens (`Data/CommunityPack.lua` diff), merge it.
- [ ] Bump `Vantage.version` (Util.lua) + TOC `## Version` + CHANGELOG, then
      `git tag v0.11.0 && git push --tags` → the release Action ships it.

---

## Ongoing

- **Seed** refreshes itself weekly (Tue 20:00 UTC). After a big patch you can force it:
  **Actions → Refresh cross-check seed → Run workflow** (optionally pin `--build`).
- **Promote** whenever you want to ship what the pool has verified — it's always a PR you review.
- **Backups**: periodically copy `/data/intel.db` off the VPS.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `/health` fails | DNS not resolved yet, or the deploy is still building. Check Coolify logs. |
| Contribute button says "couldn't reach the collector" | `COLLECTOR_URL` in `docs/index.html` wrong, or `ALLOW_ORIGIN` doesn't match `https://karlbonitz.github.io`. |
| Every submission is `pending` | No seed yet — run step 7 (or the seed Action). Safe by default; nothing false-promotes. |
| `/seed` returns 401 | `ADMIN_TOKEN` not set on the collector, or the bearer token doesn't match. |
| Promote workflow errors on the guard | `COLLECTOR_URL` / `COLLECTOR_ADMIN_TOKEN` repo secrets missing (step 8). |
| A wrong spell got promoted | Edit `Data/CommunityPack.lua` (or re-run promote after fixing the pool), ship a correction — worst case is one wasted-kick cue, self-correcting. |
