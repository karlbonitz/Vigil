-- Vantage/Modules/PartyKicks.lua
--
-- The party kick watch: zero-adoption group interrupt awareness. Nobody else
-- needs Vantage — we watch the combat log for groupmates using their interrupts
-- and infer readiness from each tool's base cooldown. When a kickable cast is
-- up and YOUR stop is down, InterruptCue asks us for a groupmate whose
-- interrupt should be ready and quietly names them in the cue's center slot.
--
-- Honesty rules:
--   * Readiness is only claimed for a tool we have WITNESSED that player use
--     this session — class alone proves nothing (talents, specs, pets).
--   * Base cooldowns only: a talent-shortened cooldown makes us say "ready" a
--     beat late, never early.
--   * Their range to the caster is unknowable from here — the hint is
--     advisory, the glow and sound stay reserved for YOUR shout.
local addonName, Vantage = ...
local M = Vantage:NewModule("PartyKicks")

-- hard interrupts + base cooldowns, TBC 2.5.x
local KICK_CD = {
    ["Kick"]         = 10, -- Rogue
    ["Pummel"]       = 10, -- Warrior (Berserker stance)
    ["Shield Bash"]  = 12, -- Warrior (Battle/Defensive + shield)
    ["Counterspell"] = 24, -- Mage
    ["Earth Shock"]  = 6,  -- Shaman
    ["Spell Lock"]   = 24, -- Warlock's Felhunter (attributed via the pet map)
    ["Silence"]      = 45, -- Shadow Priest
}

local TYPE_PLAYER = COMBATLOG_OBJECT_TYPE_PLAYER or 0x00000400
local AFF_PARTY   = COMBATLOG_OBJECT_AFFILIATION_PARTY or 0x2
local AFF_RAID    = COMBATLOG_OBJECT_AFFILIATION_RAID or 0x4

local members  = {} -- name -> { class, spells = { spell -> readyAt } }
local inGroup  = {} -- name -> unit token (current roster, excluding me)
local petOwner = {} -- pet GUID -> owner name (current roster)

local function rebuildRoster()
    for k in pairs(inGroup) do inGroup[k] = nil end
    for k in pairs(petOwner) do petOwner[k] = nil end
    if not (IsInGroup and IsInGroup()) then return end
    local raid = IsInRaid and IsInRaid()
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    local count = raid and n or (n - 1) -- party tokens exclude yourself
    for i = 1, count do
        local unit = (raid and "raid" or "party") .. i
        local name = UnitName(unit)
        if name and not (UnitIsUnit and UnitIsUnit(unit, "player")) then
            inGroup[name] = unit
            local m = members[name]
            if not m then m = { spells = {} }; members[name] = m end
            local _, class = UnitClass(unit)
            m.class = class or m.class
            -- their pet, for owner attribution (Felhunter Spell Lock)
            local pg = UnitGUID((raid and "raidpet" or "partypet") .. i)
            if pg then petOwner[pg] = name end
        end
    end
end

local function onCLEU()
    local _, sub, _, srcGUID, srcName, srcFlags, _, _, _, _, _, _, spellName =
        CombatLogGetCurrentEventInfo()
    -- SUCCESS and MISSED both mean the tool was spent (dodged kicks cool down too)
    if sub ~= "SPELL_CAST_SUCCESS" and sub ~= "SPELL_MISSED" then return end
    if not spellName or not KICK_CD[spellName] then return end

    local owner = petOwner[srcGUID]
    if not owner then
        if not (bit and bit.band and srcFlags) then return end
        if bit.band(srcFlags, TYPE_PLAYER) == 0 then return end
        if bit.band(srcFlags, AFF_PARTY + AFF_RAID) == 0 then return end
        owner = srcName
    end
    if not owner or owner == UnitName("player") then return end

    local m = members[owner]
    if not m then m = { spells = {} }; members[owner] = m end
    if not m.class and GetPlayerInfoByGUID then
        local okc, _, class = pcall(GetPlayerInfoByGUID, srcGUID)
        if okc then m.class = class end
    end
    m.spells[spellName] = GetTime() + KICK_CD[spellName]
end

-- The groupmate whose witnessed interrupt has been off cooldown the longest
-- (most certainly ready). Returns name, classToken, spellName — or nil.
function M:ReadyMate()
    local now = GetTime()
    local bestName, bestClass, bestSpell, bestAt
    for name, m in pairs(members) do
        local unit = inGroup[name]
        local dead = unit and ((UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit))
            or (UnitIsDead and UnitIsDead(unit)))
        if unit and not dead then
            for spell, readyAt in pairs(m.spells) do
                if readyAt <= now and (not bestAt or readyAt < bestAt) then
                    bestName, bestClass, bestSpell, bestAt = name, m.class, spell, readyAt
                end
            end
        end
    end
    return bestName, bestClass, bestSpell
end

-- Formatted for the cue's center slot: "GRIMJAW'S PUMMEL" + class color.
function M:ReadyMateLabel()
    local name, class, spell = self:ReadyMate()
    if not name then return nil end
    local r, g, b = 1, 1, 1
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then r, g, b = c.r, c.g, c.b end
    return name:upper() .. "'S " .. spell:upper(), r, g, b
end

function M:OnEnable()
    Vantage:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", onCLEU)
    Vantage:RegisterEvent("GROUP_ROSTER_UPDATE", rebuildRoster)
    Vantage:RegisterEvent("UNIT_PET", rebuildRoster)
    Vantage:RegisterEvent("PLAYER_ENTERING_WORLD", rebuildRoster)
end

Vantage.PartyKicks = M
