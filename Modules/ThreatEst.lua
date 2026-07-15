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

-- Your (isTanking, status, pct) on `unit` from the client's OWN threat API, or nil
-- when it has no threat relationship to report. pct = % of the pull threshold
-- (100 = you'd pull); status 3/2 = tanking (secure/insecure), 1 = above the tank
-- but not tanking, 0 = below.
--
-- The 2.5.x native API works. We wrongly wrote it off as broken ("reports aggro on
-- everything") and embedded LibThreatClassic2 to replace it — but that library
-- hard-returns on any client that isn't Classic Era (WOW_PROJECT_CLASSIC), so it
-- never loaded here at all, and the amber tier silently ran on the damage estimate
-- for its entire life. Verified in-game on 2.5.6 (2026-07-15): a mob you haven't
-- damaged reads (false, 0, 0, 0, 0), and pct climbs as your threat does.
--
-- NB, and this is what burned us: a live "no threat" reading is a real ZERO, not a
-- nil — and 0 is TRUTHY in Lua, so `if status then` treats every untouched mob as
-- aggro. That is almost certainly the "aggro on everything" we blamed the client
-- for. Only a unit with no threat relationship at all (a friendly, an unengaged
-- mob) returns nil, so `pct == nil` is the one honest "no data" sentinel — never
-- gate on `status`.
function M:Situation(unit)
    if not UnitDetailedThreatSituation then return nil end
    local isTanking, status, pct = UnitDetailedThreatSituation("player", unit)
    if pct == nil then return nil end
    return isTanking, status, pct
end

-- DPS question: am I closing in on pulling this mob off its current holder?
function M:Closing(unit)
    if not Vantage.db.threatAmber then return false end
    -- Prefer real threat: closing = you're not the tank but your threat is at/over
    -- the tank's (status >= 1) or nearing the pull threshold.
    local isTanking, status, pct = self:Situation(unit)
    if status ~= nil then
        if isTanking then return false end
        return status >= 1 or (pct ~= nil and pct >= 80)
    end
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

-- Tank question: is someone else about to pull my mob off me?
function M:RivalClosing(unit)
    if not Vantage.db.threatAmber then return false end
    -- Prefer real threat: you hold it, but only INSECURELY -> a rival is right behind.
    local isTanking, status = self:Situation(unit)
    if status ~= nil then
        return (isTanking and status == 2) or false
    end
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
    -- The amber tier prefers real threat from Situation() above; the damage tally
    -- below is the fallback for units the client reports no threat data for.
    Vantage:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", onCLEU)
    Vantage:RegisterEvent("PLAYER_REGEN_ENABLED", wipeTallies) -- fresh book per combat
    Vantage:RegisterEvent("PLAYER_ENTERING_WORLD", wipeTallies)
end

Vantage.ThreatEst = M
