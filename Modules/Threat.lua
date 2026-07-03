-- Vigil/Modules/Threat.lua
--
-- Aggro state on the plate (strip + border, via Skin.SetThreat). Two rules
-- learned the hard way:
--
--   1. SOLO, threat says NOTHING. Everything you fight is on you — painting
--      it red is a tautology. The display only speaks in a group.
--   2. Color comes from GROUND TRUTH only: the mob's actual target
--      (unit.."target" — the standard classic tank-plate technique). The
--      2.5.x native threat table is NOT consulted at all: it returned
--      "you have aggro" for everything in a real 5-man (2026-07-03),
--      exactly the unreliability our research predicted. The predictive
--      amber "about to pull" tier returns when a LibThreatClassic2-style
--      combat-log estimator lands.
local addonName, Vigil = ...
local M = Vigil:NewModule("Threat")

local THROTTLE = 0.2
local accum = 0

local function colorForStatus(unit)
    if not IsInGroup() then return nil end -- solo: aggro info is noise

    local mobTarget = unit .. "target"
    local onMe = UnitExists(mobTarget) and UnitIsUnit(mobTarget, "player")

    if Vigil.db.tankMode then
        if onMe then return "threatOK" end               -- it's on you: good
        -- it's actively fighting and beating on someone else: you lost it
        if UnitExists(mobTarget) and UnitAffectingCombat(unit) then
            return "threatBad"
        end
        return nil
    end
    return onMe and "threatBad" or nil                   -- it's coming for YOU
end

local function update()
    for unit, overlay in pairs(Vigil.plates) do
        -- keep running with the toggle off so stale strips/borders CLEAR
        local key = Vigil.db.threat and colorForStatus(unit) or nil
        if key then
            overlay.threatStrip:SetVertexColor(Vigil:RGB(key))
            overlay.threatStrip:Show()
        else
            overlay.threatStrip:Hide()
        end
        -- the same state colors the plate border (Skin decides precedence —
        -- your target's accent border always wins over threat)
        if Vigil.Skin and Vigil.Skin.SetThreat then
            Vigil.Skin:SetThreat(unit, key)
        end
    end
end

function M:OnEnable()
    -- event-nudged, but coalesced on a light ticker so 25-man stays cheap
    Vigil:RegisterEvent("UNIT_THREAT_LIST_UPDATE", function() accum = THROTTLE end)
    Vigil.frame:HookScript("OnUpdate", function(_, elapsed)
        accum = accum + elapsed
        if accum >= THROTTLE then
            accum = 0
            update()
        end
    end)
end

Vigil.Threat = M
