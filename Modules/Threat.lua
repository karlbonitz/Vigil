-- Vigil/Modules/Threat.lua
--
-- Threat tint on the overlay's top strip. Deliberately MINIMAL in v0.1 and
-- behind a capability check, because the native threat API is the one piece of
-- the 2.5.x client our research found contradictory. We never assume it exists:
-- if UnitDetailedThreatSituation is missing, the module disables itself cleanly.
--
-- TODO(v0.2): when native threat is absent/garbage, fall back to a
-- LibThreatClassic2-style combat-log estimator instead of going dark. Until then
-- the strip simply hides, and the rest of Vigil is unaffected.
local addonName, Vigil = ...
local M = Vigil:NewModule("Threat")

local THROTTLE = 0.2
local accum = 0
local hasNative = false

local function colorForStatus(unit)
    -- status: 0/1 = low, 2 = high (about to pull), 3 = tanking
    local _, status, pct = UnitDetailedThreatSituation("player", unit)
    if not status then return nil end
    if Vigil.db.tankMode then
        if status == 3 then return "threatOK"   -- securely tanking
        elseif status == 2 then return "threatWarn"
        else return "threatBad" end             -- you lost the mob
    else
        if status >= 2 then return "threatBad"  -- you (dps) are pulling/pulled
        elseif (pct or 0) >= 80 then return "threatWarn"
        else return nil end                     -- safe: don't clutter
    end
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
    hasNative = (type(UnitDetailedThreatSituation) == "function")
    if not hasNative then
        Vigil:Debug("native threat API not found — threat tint disabled (LibThreatClassic2 fallback is a v0.2 TODO).")
        return
    end
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
