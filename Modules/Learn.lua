-- Vantage/Modules/Learn.lua
--
-- Self-learning interruptibility. WoW's runtime "notInterruptible" flag is
-- unreliable on 2.5.x, which is why Vantage ships a curated Intel Pack — but no
-- curated pack can cover every cast in every instance. This closes the gap from
-- GROUND TRUTH: whenever Vantage sees ANY cast get interrupted (yours or a
-- groupmate's), that spell is provably interruptible, so it's banked. The next
-- time that cast appears with no curated intel, it's cued as a real kick instead
-- of a neutral "unknown".
--
-- Discipline:
--   * We learn only the CONFIDENT direction — "it was interrupted, so it's
--     interruptible." You can't interrupt an uninterruptible cast, so there are
--     no false positives here. The "don't kick" (padlock) side stays curated.
--   * Curated intel ALWAYS wins (see Vantage.GetKickInfo): a hand-verified padlock
--     is never overridden by a learned entry, even on a name collision. Learning
--     only ever fills the "unknown" gap.
--   * Account-wide + persistent (VantageLearnedDB), and independent of the settings
--     Reset button — earned knowledge shouldn't evaporate. Capped + LRU-pruned so
--     the table stays lean.
local addonName, Vantage = ...
local M = Vantage:NewModule("Learn")

local CAP = 1500 -- generous per-account ceiling; prune the least-recently-seen

local function store()
    if type(VantageLearnedDB) ~= "table" then VantageLearnedDB = {} end
    if type(VantageLearnedDB.spells) ~= "table" then
        VantageLearnedDB.v = 1
        VantageLearnedDB.spells = {}
        VantageLearnedDB.count = 0
    end
    return VantageLearnedDB
end

-- drop the single least-recently-seen entry (called only when we hit the cap)
local function pruneOldest(spells)
    local oldestKey, oldestT
    for k, e in pairs(spells) do
        local t = e.last or 0
        if not oldestT or t < oldestT then oldestKey, oldestT = k, t end
    end
    if oldestKey then spells[oldestKey] = nil; return true end
    return false
end

-- Bank a spell we just watched get interrupted. Cheap; safe to call often.
function M:Note(spellName, spellID, zone)
    if Vantage.db and Vantage.db.learn == false then return end
    if type(spellName) ~= "string" or spellName == "" then return end
    local key = spellName:lower()

    -- Already curated (either direction)? We already know about it — never shadow
    -- a hand-verified entry, and don't clutter the learned table with knowns.
    local K = Vantage.Kickable
    if K and (K.byName[key] or (spellID and K.byID[spellID])) then return end

    local d = store()
    local now = (GetTime and GetTime()) or 0
    local e = d.spells[key]
    if e then
        e.n = (e.n or 0) + 1
        e.last = now
        if zone then e.zone = zone end
        if spellID and not e.id then e.id = spellID end
        return
    end

    if d.count >= CAP and pruneOldest(d.spells) then d.count = d.count - 1 end
    d.spells[key] = {
        name = spellName, id = spellID, n = 1, first = now, last = now, zone = zone,
        -- These make the entry a valid Vantage.GetKickInfo result, so the lookup
        -- just returns it and Evaluate treats the cast as a real kick.
        interruptible = true, learned = true, priority = 2, category = "learned",
        castTime = 0,
    }
    d.count = d.count + 1
    Vantage:Debug("learned interruptible:", spellName, spellID and ("#" .. spellID) or "")
end

function M:OnEnable()
    store() -- make sure the table exists on login, before the first interrupt
end

-- /vantage learned — what has it taught itself?
function M:Report()
    local d = store()
    Vantage:Print(("Learned from live combat: |cffffd100%d|r interruptible cast%s the curated pack didn't have.")
        :format(d.count, d.count == 1 and "" or "s"))
    if d.count == 0 then
        Vantage:Print("  Nothing yet — it fills in as you (or your group) interrupt casts Vantage hasn't been told about.")
        return
    end
    local list = {}
    for _, e in pairs(d.spells) do list[#list + 1] = e end
    table.sort(list, function(a, b) return (a.n or 0) > (b.n or 0) end)
    for i = 1, math.min(12, #list) do
        local e = list[i]
        Vantage:Print(("  %s  |cff808080(%dx%s)|r"):format(
            e.name or "?", e.n or 0, e.zone and (", " .. e.zone) or ""))
    end
end

Vantage.Learn = M
