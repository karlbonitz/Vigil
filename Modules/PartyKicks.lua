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
local petOwner = {} -- pet GUID -> { name, guid, mine } of the owning player (you + group)
local myGUID         -- cached in OnEnable; the owner your own pet maps to

local function rebuildRoster()
    for k in pairs(inGroup) do inGroup[k] = nil end
    for k in pairs(petOwner) do petOwner[k] = nil end
    -- Your OWN pet always maps to you (even solo), so a Felhunter's Spell Lock is
    -- credited to you exactly like a kick from your own hand.
    local myPet = UnitGUID and UnitGUID("pet")
    if myPet then
        petOwner[myPet] = { name = UnitName("player"), guid = myGUID, mine = true }
    end
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
            if pg then petOwner[pg] = { name = name, guid = UnitGUID(unit), mine = false } end
        end
    end
end

local function onCLEU()
    local _, sub, _, srcGUID, srcName, srcFlags, _, _, _, _, _, _, spellName =
        CombatLogGetCurrentEventInfo()
    -- SUCCESS and MISSED both mean the tool was spent (dodged kicks cool down too)
    if sub ~= "SPELL_CAST_SUCCESS" and sub ~= "SPELL_MISSED" then return end
    if not spellName or not KICK_CD[spellName] then return end

    local po = petOwner[srcGUID]
    local owner = po and po.name
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
        -- resolve from the OWNER's guid for a pet (a pet GUID won't resolve a class)
        local okc, _, class = pcall(GetPlayerInfoByGUID, (po and po.guid) or srcGUID)
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

-- Resolve a combat-log source GUID to the PLAYER responsible for it. Returns nil
-- for a player's own GUID (the source already IS the player — callers handle that
-- case directly) and for pets we can't map; otherwise the owner's name, the
-- owner's GUID, and whether the pet is YOURS. This is how a Felhunter's Spell Lock
-- gets credited to its warlock in Parse's roster and outcome rows.
function M:OwnerOf(guid)
    local po = guid and petOwner[guid]
    if not po then return nil end
    return po.name, po.guid, po.mine
end

-- Is this combat-log source YOU — either your own GUID, or your own pet (a
-- Felhunter's Spell Lock)? Lets Parse/CastWatch count a pet kick as your own.
function M:IsMine(guid)
    if not guid then return false end
    if guid == myGUID then return true end
    local po = petOwner[guid]
    return (po and po.mine) or false
end

-- ---------------------------------------------------------------------------
-- Coordination: optional interrupt call-outs + a party-readiness readout.
-- ---------------------------------------------------------------------------
local lastAnnounce = 0

-- Call out YOUR interrupt to the group (opt-in via db.announce, and throttled so a
-- flurry of kicks never spams chat). Only in a group; solo it stays silent.
function M:Announce(spellStopped)
    if not (IsInGroup and IsInGroup()) then return end
    local now = (GetTime and GetTime()) or 0
    if now - lastAnnounce < 2 then return end
    lastAnnounce = now
    local chan = (IsInRaid and IsInRaid()) and "RAID" or "PARTY"
    if SendChatMessage then
        SendChatMessage("Interrupted " .. (spellStopped or "a cast") .. "!", chan)
    end
end

-- /vantage kicks: who in the group has an interrupt, and is it ready right now?
function M:Readout()
    local now = (GetTime and GetTime()) or 0
    Vantage:Print("Party interrupts Vantage has witnessed:")
    local any = false
    for name, m in pairs(members) do
        if inGroup[name] then
            for spell, readyAt in pairs(m.spells) do
                any = true
                local left = readyAt - now
                local state = (left <= 0) and "|cff2fa385ready|r"
                    or ("|cffe25b4e" .. string.format("%.0fs", left) .. "|r")
                Vantage:Print(("  %s — %s (%s)"):format(name, spell, state))
            end
        end
    end
    if not any then
        Vantage:Print("  (none yet — Vantage learns them as your groupmates use their kicks)")
    end
end

function M:OnEnable()
    myGUID = UnitGUID("player")
    Vantage:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", onCLEU)
    Vantage:RegisterEvent("GROUP_ROSTER_UPDATE", rebuildRoster)
    Vantage:RegisterEvent("UNIT_PET", rebuildRoster)
    Vantage:RegisterEvent("PLAYER_ENTERING_WORLD", rebuildRoster)
    rebuildRoster() -- map any pet / group that already exists at login
end

Vantage.PartyKicks = M
