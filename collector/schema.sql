-- collector/schema.sql — Cloudflare D1 (SQLite) schema for the community pool.
-- Apply with: wrangler d1 execute vantage-intel --file collector/schema.sql
--
-- This is a STAGING area, never the shipped data. Nothing here reaches a player
-- until promote.mjs regenerates Data/CommunityPack.lua and you cut a release.

-- One row per candidate spell. status walks pending -> verified -> promoted,
-- or -> rejected. confirmers is the count of DISTINCT install tokens (see below).
CREATE TABLE IF NOT EXISTS candidate (
  spell_id    INTEGER PRIMARY KEY,
  name        TEXT    NOT NULL,
  status      TEXT    NOT NULL DEFAULT 'pending',  -- pending|verified|rejected|promoted
  confirmers  INTEGER NOT NULL DEFAULT 0,          -- distinct uuids (maintained from `confirmation`)
  reports     INTEGER NOT NULL DEFAULT 0,          -- total sightings across everyone
  npcs        TEXT    NOT NULL DEFAULT '[]',        -- json array of creatureIDs seen casting it
  zones       TEXT    NOT NULL DEFAULT '[]',        -- json array of zones it was seen in
  interrupts  TEXT    NOT NULL DEFAULT '[]',        -- json array of interrupts that stopped it
  reason      TEXT,                                 -- cross-check note / rejection reason
  first_seen  INTEGER,
  last_seen   INTEGER
);

-- The distinct-contributor ledger: one row per (spell, install token). The
-- PRIMARY KEY makes a second submission from the same install an UPSERT, so a
-- single install can never inflate `confirmers`. This is what makes the
-- "N distinct confirmers" gate meaningful.
CREATE TABLE IF NOT EXISTS confirmation (
  spell_id  INTEGER NOT NULL,
  uuid      TEXT    NOT NULL,
  n         INTEGER NOT NULL DEFAULT 1,
  at        INTEGER,
  PRIMARY KEY (spell_id, uuid)
);

-- Raw submission audit — rate-limiting signal + forensics if a token misbehaves.
-- ip_hash is a salted hash, never a raw IP.
CREATE TABLE IF NOT EXISTS submission (
  id       INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid     TEXT,
  ip_hash  TEXT,
  version  TEXT,
  spells   INTEGER,
  at       INTEGER
);

CREATE INDEX IF NOT EXISTS idx_candidate_status ON candidate(status);
CREATE INDEX IF NOT EXISTS idx_submission_uuid  ON submission(uuid);
