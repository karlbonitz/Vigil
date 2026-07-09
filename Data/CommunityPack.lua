-- Vantage/Data/CommunityPack.lua
--
-- The community intel pack: kickable casts confirmed by Vantage players at large
-- and merged back into the shipped baseline, so everyone's game gets smarter as a
-- group. Players submit self-learned kicks with /vantage contribute (anonymous,
-- evidence-bearing); the collector cross-checks + tallies distinct confirmers;
-- entries that clear the bar are promoted here and ride out on the next release.
--
-- SAFETY INVARIANT — curated always wins:
--   add() only ever fills a key the curated Intel Pack (KickableSpells.lua, loaded
--   just before this file) hasn't already claimed. So a hand-verified padlock can
--   NEVER be overridden by community data — the pool only adds kicks to casts we
--   had no intel on. This mirrors the runtime guarantee in Vantage.GetKickInfo.
--
-- GENERATED SECTION — do not hand-edit the add() calls between the PACK markers.
-- Regenerate from the collector: `node collector/promote.mjs`.
local addonName, Vantage = ...
local K = Vantage.Kickable
if not K then return end

local function add(id, name)
    if type(name) ~= "string" or name == "" then return end
    local key = name:lower()
    local e = {
        name = name, interruptible = true, community = true,
        priority = 2, category = "community", castTime = 0,
    }
    -- never shadow a curated entry (either direction) — gaps only
    if id and K.byID[id] == nil then K.byID[id] = e end
    if K.byName[key] == nil then K.byName[key] = e end
end

-- Exposed so the test harness can exercise the merge mechanism.
Vantage.CommunityPack = { add = add }

-- VANTAGE:PACK-START (generated — see collector/promote.mjs)
-- (no community entries yet — this fills in as players contribute)
-- VANTAGE:PACK-END
