-- Vantage/Modules/CastWatch.lua
--
-- Detects enemy casts and drives the plate cast bar, then hands off to the
-- InterruptCue module for the kick/padlock decision.
--
-- Two detection paths, because the Classic client is inconsistent about exposing
-- enemy cast info:
--   1) UNIT_SPELLCAST_* on the nameplate unit  -> accurate timing via the API.
--   2) CLEU SPELL_CAST_START (always fires)     -> fallback that animates the bar
--      from our Intel Pack's castTime when the API gives us nothing.
-- Path 1 wins when available; path 2 guarantees we never miss a cast outright.
local addonName, Vantage = ...
local M = Vantage:NewModule("CastWatch")

-- ---------------------------------------------------------------------------
-- Path 1: live unit cast info
-- ---------------------------------------------------------------------------
local function startFromAPI(unit)
    local overlay = Vantage.plates[unit]
    if not overlay or not Vantage.db.showCastbar then return false end

    local name, _, texture, startMS, endMS, _, _, _, spellID = UnitCastingInfo(unit)
    local channeling = false
    if not name then
        name, _, texture, startMS, endMS, _, _, spellID = UnitChannelInfo(unit)
        channeling = name ~= nil
    end
    if not name then return false end

    local duration = (endMS - startMS) / 1000
    -- true seconds left (endMS is GetTime-based ms): equals `duration` at cast start,
    -- but LESS when we pick the cast up mid-flight, so the bar never over-counts.
    local remaining = endMS / 1000 - GetTime()
    overlay:ShowCast(name, texture, duration, channeling, remaining)
    overlay.active = { name = name, spellID = spellID,
                       info = Vantage.GetKickInfo(name, spellID) }
    Vantage.Cue:Evaluate(overlay, unit, name, overlay.active.info)
    return true
end

-- Re-check a unit (called when its plate first appears, to catch in-progress casts).
function M:Refresh(unit)
    startFromAPI(unit)
end

-- ---------------------------------------------------------------------------
-- Path 2: combat-log fallback
-- ---------------------------------------------------------------------------
local myGUID

local function onCLEU()
    local _, sub, _, srcGUID, _, _, _, dstGUID = CombatLogGetCurrentEventInfo()

    -- Diminishing returns: bank YOUR own soft-CC applications so the cue stops
    -- nagging you to re-apply a category the target is now immune to, and forget a
    -- unit's DR when it dies. See Vantage:NoteDR / :DRImmune in Data/Immunities.lua.
    if srcGUID == myGUID and (sub == "SPELL_AURA_APPLIED" or sub == "SPELL_AURA_REFRESH") then
        local _, sname = select(12, CombatLogGetCurrentEventInfo())
        local mech = sname and Vantage.MyCCMechanic and Vantage:MyCCMechanic(sname)
        if mech and Vantage.NoteDR then Vantage:NoteDR(dstGUID, mech) end
    elseif sub == "UNIT_DIED" and Vantage.ClearDR then
        Vantage:ClearDR(dstGUID)
    end

    -- YOUR interrupt landing on a cast marked do-not-kick: the padlock's lesson,
    -- delivered at the exact moment it was ignored. (Checked before the caster
    -- lookup below — here the source is you, not the mob.)
    if sub == "SPELL_CAST_SUCCESS"
        and (srcGUID == myGUID or (Vantage.PartyKicks and Vantage.PartyKicks:IsMine(srcGUID))) then
        local kickName = select(13, CombatLogGetCurrentEventInfo())
        if Vantage.IsMyInterrupt and Vantage:IsMyInterrupt(kickName) then
            local tUnit = Vantage.guidToUnit[dstGUID]
            local tOverlay = tUnit and Vantage.plates[tUnit]
            if tOverlay and tOverlay.active and tOverlay.active.code == "locked" then
                tOverlay:FlashWasted() -- label only; the locked cast is still going (your pet's kick too)
            end
        end
    end

    -- Self-learning: the cast that just got interrupted is, by definition,
    -- interruptible (you can't kick an uninterruptible cast). Bank it as ground
    -- truth so an "unknown" cast becomes a real kick cue next time. Runs for any
    -- hostile/neutral caster, plated or not; Learn:Note skips anything curated.
    if sub == "SPELL_INTERRUPT" and Vantage.Learn then
        local destFlags = select(10, CombatLogGetCurrentEventInfo())
        local HOSTILE_OR_NEUTRAL = 0x60 -- REACTION_HOSTILE (0x40) | NEUTRAL (0x20)
        if destFlags and bit and bit.band(destFlags, HOSTILE_OR_NEUTRAL) ~= 0 then
            -- src spell (12,13) = the interrupt that landed; extra (15,16) = the
            -- cast it stopped; dstGUID = the caster. All three are the evidence
            -- the community collector cross-checks before trusting a submission.
            local byId, byName = select(12, CombatLogGetCurrentEventInfo())
            local exID, exName = select(15, CombatLogGetCurrentEventInfo())
            Vantage.Learn:Note(exName, exID, GetRealZoneText and GetRealZoneText(),
                byName, byId, Vantage:NpcID(dstGUID))
            -- coordination: call out your OWN kick to the group (opt-in, throttled).
            -- Your pet's interrupt (a Felhunter's Spell Lock) counts as yours here too.
            local mine = Vantage.PartyKicks and Vantage.PartyKicks:IsMine(srcGUID)
            if mine and Vantage.db.announce then
                Vantage.PartyKicks:Announce(exName)
            end
        end
    end

    -- whose cast bar is this about? For SPELL_INTERRUPT the caster is the
    -- DESTINATION (source = whoever kicked it); for everything else, the source.
    local casterGUID = (sub == "SPELL_INTERRUPT") and dstGUID or srcGUID
    local unit = Vantage.guidToUnit[casterGUID]
    if not unit then return end
    local overlay = Vantage.plates[unit]
    if not overlay then return end

    if sub == "SPELL_CAST_START" then
        -- if a bar is already running (live API beat us here), don't double up
        if overlay.active then return end
        if not Vantage.db.showCastbar then return end
        local spellID, spellName = select(12, CombatLogGetCurrentEventInfo())
        local info = Vantage.GetKickInfo(spellName, spellID)
        local castTime = (info and info.castTime and info.castTime > 0) and info.castTime or 2.0
        local _, _, icon = GetSpellInfo(spellID)
        overlay:ShowCast(spellName, icon, castTime, false)
        overlay.active = { name = spellName, spellID = spellID, info = info }
        Vantage.Cue:Evaluate(overlay, unit, spellName, info)

    elseif sub == "SPELL_INTERRUPT" then
        -- somebody stopped it (you or a groupmate): the win flash
        if overlay.active then
            overlay:FlashOutcome("kicked", "KICKED")
        end

    elseif sub == "SPELL_CAST_SUCCESS" then
        if overlay.active and not overlay.castbar.channeling then
            local spellName = select(13, CombatLogGetCurrentEventInfo())
            if spellName == overlay.active.name then
                if overlay.active.code == "ready" then
                    -- it completed while your stop sat ready — the stat this
                    -- addon exists to drive down, called out in the moment
                    overlay:FlashOutcome("missed", "MISSED")
                else
                    overlay:Reset()
                end
            end
            -- a DIFFERENT spell succeeding mid-cast is an instant proc, not this
            -- cast resolving — leave the bar alone (it self-expires on time)
        end

    elseif sub == "SPELL_CAST_FAILED" then
        if overlay.active and not overlay.castbar.channeling then
            overlay:Reset()
        end
    end
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------
local function unitEvent(_, unit)
    if Vantage.plates[unit] then startFromAPI(unit) end
end

local function unitStop(_, unit)
    local overlay = Vantage.plates[unit]
    if overlay and overlay.active then overlay:Reset() end
end

local function unitInterrupted(_, unit)
    local overlay = Vantage.plates[unit]
    if overlay and overlay.active then overlay:FlashOutcome("kicked", "KICKED") end
end

local function unitSucceeded(_, unit, _, spellID)
    local overlay = Vantage.plates[unit]
    local a = overlay and overlay.active
    if not a then return end
    -- SUCCEEDED fires for the mob's instants too; only resolve OUR tracked cast
    if spellID and a.spellID then
        if spellID ~= a.spellID then return end
    elseif spellID and a.name then
        local n = GetSpellInfo(spellID)
        if n and n ~= a.name then return end
    end
    if a.code == "ready" and not overlay.castbar.channeling then
        overlay:FlashOutcome("missed", "MISSED")
    else
        overlay:Reset()
    end
end

function M:OnEnable()
    myGUID = UnitGUID("player")

    -- Path 1 (best-effort; harmless if the client doesn't fire these for plates)
    Vantage:RegisterEvent("UNIT_SPELLCAST_START",         unitEvent)
    Vantage:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START", unitEvent)
    Vantage:RegisterEvent("UNIT_SPELLCAST_STOP",          unitStop)
    Vantage:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP",  unitStop)
    Vantage:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED",   unitInterrupted)
    Vantage:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED",     unitSucceeded)

    -- Path 2 (the reliable backbone)
    Vantage:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED",  onCLEU)
end

Vantage.CastWatch = M
