-- Vantage/Modules/ThreatEst.lua
--
-- The amber tier: "you're CLOSING IN on pulling this mob" — before the red
-- ground truth (the mob turning to you) can exist. The 2.5.5 threat API is
-- garbage (confirmed live), so this estimates from the one thing the combat
-- log states as fact: damage done to each mob by each group-affiliated
-- source (players and their pets).
--
-- The model, stated honestly:
--   * threat ~= damage. Heals, taunts, and talent modifiers are invisible
--     from here and are NOT modeled.
--   * the mob's current holder is assumed to run a 1.3x tank-style threat
--     modifier (Defensive Stance / Bear / Righteous Fury). With the classic
--     1.1x melee pull rule, a pull lands around 1.43x the holder's damage —
--     amber fires at 1.3x, roughly 90% of the way there.
--   * if the holder is actually a cloth DPS, amber fires late, never
--     spammy-early. That's the right way to be wrong.
--
-- Tallies live per combat: PLAYER_REGEN_ENABLED wipes the book.
local addonName, Vantage = ...
local M = Vantage:NewModule("ThreatEst")

local CLOSING = 1.3 -- x the holder's damage

local tallies = {} -- mob GUID -> { [source GUID] = damage }
local myGUID

local AFF_GROUP = (COMBATLOG_OBJECT_AFFILIATION_MINE or 0x1)
    + (COMBATLOG_OBJECT_AFFILIATION_PARTY or 0x2)
    + (COMBATLOG_OBJECT_AFFILIATION_RAID or 0x4)

local function wipeTallies()
    for k in pairs(tallies) do tallies[k] = nil end
end

local function onCLEU()
    local _, sub, _, srcGUID, _, srcFlags, _, dstGUID, _, _, _, a12, _, _, a15 =
        CombatLogGetCurrentEventInfo()

    if sub == "UNIT_DIED" then
        tallies[dstGUID] = nil
        return
    end

    local amount
    if sub == "SWING_DAMAGE" then amount = a12
    elseif sub == "SPELL_DAMAGE" or sub == "SPELL_PERIODIC_DAMAGE"
        or sub == "RANGE_DAMAGE" then amount = a15
    else return end
    if type(amount) ~= "number" or amount <= 0 then return end

    -- only my group's output, and only onto mobs we can see (plate = tracked)
    if not (bit and bit.band and srcFlags) then return end
    if bit.band(srcFlags, AFF_GROUP) == 0 then return end
    if not (dstGUID and Vantage.guidToUnit[dstGUID]) then return end

    local t = tallies[dstGUID]
    if not t then t = {}; tallies[dstGUID] = t end
    t[srcGUID] = (t[srcGUID] or 0) + amount
end

-- DPS question: is MY damage closing in on this mob's current holder?
function M:Closing(unit)
    if not Vantage.db.threatAmber then return false end
    local guid = UnitGUID(unit)
    local t = guid and tallies[guid]
    if not t or not myGUID then return false end
    local mine = t[myGUID]
    if not mine or mine <= 0 then return false end
    local holderGUID = UnitGUID(unit .. "target")
    if not holderGUID or holderGUID == myGUID then return false end
    local holder = t[holderGUID]
    -- a holder with no damage tally holds through taunt/heal aggro we can't
    -- see — claiming "closing" against zero data would be a guess, so don't
    if not holder or holder <= 0 then return false end
    return mine >= holder * CLOSING
end

-- Tank question: is any OTHER tallied source closing in on my mob?
function M:RivalClosing(unit)
    if not Vantage.db.threatAmber then return false end
    local guid = UnitGUID(unit)
    local t = guid and tallies[guid]
    if not t or not myGUID then return false end
    local mine = t[myGUID]
    if not mine or mine <= 0 then return false end
    for src, dmg in pairs(t) do
        if src ~= myGUID and dmg >= mine * CLOSING then return true end
    end
    return false
end

function M:OnEnable()
    myGUID = UnitGUID("player")
    Vantage:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", onCLEU)
    Vantage:RegisterEvent("PLAYER_REGEN_ENABLED", wipeTallies) -- fresh book per combat
    Vantage:RegisterEvent("PLAYER_ENTERING_WORLD", wipeTallies)
end

Vantage.ThreatEst = M
