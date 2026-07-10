-- Vantage/Modules/Threat.lua
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
local addonName, Vantage = ...
local M = Vantage:NewModule("Threat")

local THROTTLE = 0.2
local accum = 0

local function colorForStatus(unit)
    if not IsInGroup() then return nil end -- solo: aggro info is noise

    local mobTarget = unit .. "target"
    local onMe = UnitExists(mobTarget) and UnitIsUnit(mobTarget, "player")

    if Vantage.db.tankMode then
        if onMe then
            -- it's on you — but is a DPS's damage closing in on losing it?
            if Vantage.ThreatEst and Vantage.ThreatEst:RivalClosing(unit) then
                return "threatWarn"
            end
            return "threatOK"                            -- securely yours
        end
        -- it's actively fighting and beating on someone else: you lost it
        if UnitExists(mobTarget) and UnitAffectingCombat(unit) then
            return "threatBad"
        end
        return nil
    end
    if onMe then return "threatBad" end                  -- it's coming for YOU
    -- not on you (yet): amber when your damage says you're closing in
    if Vantage.ThreatEst and Vantage.ThreatEst:Closing(unit) then
        return "threatWarn"
    end
    return nil
end

local function update()
    for unit, overlay in pairs(Vantage.plates) do
        -- keep running with the toggle off so stale strips/borders CLEAR
        local key = Vantage.db.threat and colorForStatus(unit) or nil
        -- The plate BORDER already carries the threat color on non-target plates
        -- (Skin border order: target accent > threat > black), so showing the strip
        -- there too is the redundant "line under the bar". Keep the strip only where
        -- it adds signal: your CURRENT TARGET (whose border shows the accent instead),
        -- or everywhere when the skin is off and no colored border carries it.
        local stripNeeded = key and (Vantage.db.skin == false or UnitIsUnit(unit, "target"))
        if stripNeeded then
            overlay.threatStrip:SetVertexColor(Vantage:RGB(key))
            overlay.threatStrip:Show()
        else
            overlay.threatStrip:Hide()
        end
        -- the same state colors the plate border (Skin decides precedence —
        -- your target's accent border always wins over threat)
        if Vantage.Skin and Vantage.Skin.SetThreat then
            Vantage.Skin:SetThreat(unit, key)
        end
    end
end

function M:OnEnable()
    -- event-nudged, but coalesced on a light ticker so 25-man stays cheap
    Vantage:RegisterEvent("UNIT_THREAT_LIST_UPDATE", function() accum = THROTTLE end)
    Vantage.frame:HookScript("OnUpdate", function(_, elapsed)
        accum = accum + elapsed
        if accum >= THROTTLE then
            accum = 0
            update()
        end
    end)
end

Vantage.Threat = M
