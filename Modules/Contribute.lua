-- Vantage/Modules/Contribute.lua
--
-- The community intel bridge. Vantage already teaches ITSELF which casts are
-- interruptible (Modules/Learn.lua) — this lets that hard-won, ground-truth
-- knowledge flow back into the shared curated pack, so everyone's game gets
-- smarter as a group. WoW addons have no network access, so the bridge is the
-- same copy-paste path Parse uses: /vantage contribute -> Ctrl+C -> the report
-- page's "Contribute" button submits it.
--
-- Two disciplines make this safe to pool from strangers:
--   * ANONYMOUS. The payload carries a random install token (Vantage:InstallID),
--     never your character or realm. Its only purpose is to let the collector
--     count DISTINCT contributors, so a spell needs several independent
--     confirmers before it's trusted.
--   * EVIDENCE, not claims. Each spell rides with the interrupt that stopped it
--     (`by`) and the caster's creatureID (`npc`). You can't fake "it was
--     interrupted" without actually interrupting it, and the collector can
--     cross-check the spell against the NPC and zone before promoting it. A
--     curated padlock can never be overridden — the pool only ever ADDS kicks.
local addonName, Vantage = ...
local M = Vantage:NewModule("Contribute")

-- Build the submission as a Lua table (BuildString encodes it; tests read it).
function M:BuildPayload()
    local d = (type(VantageLearnedDB) == "table" and VantageLearnedDB) or {}
    local spells = {}
    for _, e in pairs(d.spells or {}) do
        -- Only the minimum the collector needs to verify + merge. No PII.
        spells[#spells + 1] = {
            id   = e.id,
            name = e.name,
            zone = e.zone,
            n    = e.n,     -- how often this install saw it kicked (confidence)
            by   = e.by,    -- the interrupt that landed (evidence it's real)
            npc  = e.npc,   -- caster creatureID (cross-check anchor)
        }
    end
    local iface = 0
    if GetBuildInfo then iface = select(4, GetBuildInfo()) or 0 end
    return {
        v       = 1,
        kind    = "vantage-intel",     -- lets the collector reject stray blobs
        uuid    = Vantage:InstallID(),  -- anonymous, for distinct-contributor counts
        version = Vantage.version,
        client  = iface,
        at      = (time and time()) or 0,
        count   = #spells,
        spells  = spells,
    }
end

function M:BuildString()
    return Vantage.ParseExport.Encode(self:BuildPayload())
end

-- URL the report page hosts the "Contribute" button on.
local REPORT_URL = "karlbonitz.github.io/Vantage"

function M:Toggle()
    local payload = self:BuildPayload()
    if payload.count == 0 then
        Vantage:Print("Nothing to contribute yet — Vantage banks a cast once you (or your group) interrupt something the curated pack didn't cover. Play a dungeon, then try again.")
        return
    end
    local str = Vantage.ParseExport.Encode(payload)
    Vantage.ParseExport:ShowText(str, "Vantage — contribute community intel",
        ("Press |cffffd100Ctrl+C|r to copy, then hit |cffffd100Contribute|r on the report page: |cffffd100%s|r. Anonymous — no character or realm, just the %d cast%s you've confirmed kickable.")
        :format(REPORT_URL, payload.count, payload.count == 1 and "" or "s"))
    Vantage:Print(("Ready to share |cffffd100%d|r self-learned cast%s (anonymous). Ctrl+C, then Contribute on %s")
        :format(payload.count, payload.count == 1 and "" or "s", REPORT_URL))
end

function M:OnEnable() end

Vantage.Contribute = M
