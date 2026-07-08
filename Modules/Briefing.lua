-- Vantage/Modules/Briefing.lua
--
-- The dungeon briefing: walk into an instance Vantage has intel on, get the
-- kick sheet BEFORE the first pull — what to kick on sight, what to never
-- waste a kick on. Data comes straight from the Intel Pack's zone tags, so
-- every line traces to a verified entry; dungeons without tags stay silent.
-- Auto-briefs once per instance visit; /vantage brief reprints with the why.
local addonName, Vantage = ...
local M = Vantage:NewModule("Briefing")

-- some clients name the Tempest Keep raid "The Eye"
local ALIAS = { ["the eye"] = "tempest keep" }

local lastBriefed -- instance key of the last auto-brief (one per visit)

local function currentInstance()
    if not GetInstanceInfo then return nil end
    local name, itype = GetInstanceInfo()
    if not name or (itype ~= "party" and itype ~= "raid") then return nil end
    local key = name:lower()
    return ALIAS[key] or key, name
end

local function entriesFor(instKey)
    local kicks, locks = {}, {}
    for spell, e in pairs(Vantage.Kickable.byName) do
        if e.zones then
            for _, z in ipairs(e.zones) do
                -- substring both ways: "the botanica" matches "Botanica" etc.
                if instKey:find(z, 1, true) or z:find(instKey, 1, true) then
                    local t = e.interruptible and kicks or locks
                    t[#t + 1] = { spell = spell, e = e }
                    break
                end
            end
        end
    end
    local byPrio = function(a, b)
        if a.e.priority ~= b.e.priority then return a.e.priority > b.e.priority end
        return a.spell < b.spell
    end
    table.sort(kicks, byPrio)
    table.sort(locks, byPrio)
    return kicks, locks
end

local function titleCase(s)
    return (s:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end

local function nameList(list, max)
    local out = {}
    for i = 1, math.min(max or #list, #list) do
        out[#out + 1] = titleCase(list[i].spell)
    end
    return table.concat(out, ", ")
end

-- first sentence of an intel note, clipped so chat stays readable
local function gist(note)
    local first = note and (note:match("^(.-%.)%s") or note) or ""
    if #first > 110 then first = first:sub(1, 107) .. "..." end
    return first
end

function M:Brief(verbose)
    local instKey, instName = currentInstance()
    if not instKey then
        if verbose then Vantage:Print("No briefing - you're not in a dungeon or raid.") end
        return false
    end
    local kicks, locks = entriesFor(instKey)
    if #kicks == 0 and #locks == 0 then
        if verbose then Vantage:Print("No intel tagged for " .. instName .. " yet.") end
        return false
    end
    Vantage:Print("|cffffd100Briefing - " .. instName .. "|r")
    if #kicks > 0 then
        print("  |cff44ff44Kick on sight:|r " .. nameList(kicks, 6))
    end
    if #locks > 0 then
        print("  |cffff4444Never kick:|r " .. nameList(locks, 6))
    end
    if verbose then
        for _, item in ipairs(kicks) do
            print("  |cff44ff44+|r " .. titleCase(item.spell) .. " - " .. gist(item.e.note))
        end
        for _, item in ipairs(locks) do
            print("  |cffff4444x|r " .. titleCase(item.spell) .. " - " .. gist(item.e.note))
        end
    else
        print("  (|cffffd100/vantage brief|r for the why)")
    end
    return true
end

local function onZone()
    if not (Vantage.db and Vantage.db.enabled and Vantage.db.briefing) then return end
    local instKey = currentInstance()
    if not instKey then
        lastBriefed = nil -- left the instance; next visit briefs again
        return
    end
    if instKey == lastBriefed then return end
    if M:Brief(false) then lastBriefed = instKey end
end

function M:OnEnable()
    Vantage:RegisterEvent("ZONE_CHANGED_NEW_AREA", onZone)
    Vantage:RegisterEvent("PLAYER_ENTERING_WORLD", onZone)
end

Vantage.Briefing = M
