-- Vantage/Modules/Inspect.lua
--
-- /vantage plate — developer tool. Walks your TARGET's nameplate frame tree and
-- dumps every child frame and region (parentKey, type, size, shown, texture
-- path/atlas, colors, text) into a copy-paste window. This is how we learn
-- what the real 2.5.x client actually draws on a plate, instead of guessing
-- from retail docs — paste the dump back to the developer.
local addonName, Vantage = ...
local M = Vantage:NewModule("Inspect")

-- Find the string key(s) this object hangs off: check its direct parent's
-- table, then the UnitFrame root (Vantage keys its own additions there).
local function keysFor(obj, parentTbl, rootTbl)
    local found, dup = {}, {}
    for _, tbl in ipairs({ parentTbl, rootTbl }) do
        if type(tbl) == "table" and not dup[tbl] then
            dup[tbl] = true
            for k, v in pairs(tbl) do
                if v == obj and type(k) == "string" and not dup[k] then
                    dup[k] = true
                    found[#found + 1] = k
                end
            end
        end
    end
    if #found == 0 then return "-" end
    table.sort(found)
    return table.concat(found, ",")
end

local function fmtColor(r, g, b, a)
    if not r then return "" end
    return string.format(" rgba=%.2f,%.2f,%.2f,%.2f", r, g, b, a or 1)
end

local function describe(obj, key, depth, out)
    local pad = string.rep("  ", depth)
    local ok, otype = pcall(obj.GetObjectType, obj)
    otype = ok and otype or "?"
    local w = obj.GetWidth and math.floor((obj:GetWidth() or 0) + 0.5) or 0
    local h = obj.GetHeight and math.floor((obj:GetHeight() or 0) + 0.5) or 0
    local shown = obj.IsShown and (obj:IsShown() and "SHOWN" or "hidden") or "?"
    local alpha = obj.GetAlpha and string.format(" a=%.2f", obj:GetAlpha() or 1) or ""
    local line = string.format("%s[%s] %s %dx%d %s%s", pad, key, otype, w, h, shown, alpha)

    if otype == "Texture" then
        local tex = obj.GetTexture and obj:GetTexture()
        if tex then line = line .. " tex=" .. tostring(tex) end
        if obj.GetAtlas then
            local okA, atlas = pcall(obj.GetAtlas, obj)
            if okA and atlas then line = line .. " atlas=" .. tostring(atlas) end
        end
        if obj.GetVertexColor then line = line .. fmtColor(obj:GetVertexColor()) end
        if obj.GetBlendMode then line = line .. " blend=" .. tostring(obj:GetBlendMode()) end
        if obj.GetDrawLayer then
            local layer, sub = obj:GetDrawLayer()
            line = line .. " layer=" .. tostring(layer) .. (sub and ("/" .. sub) or "")
        end
    elseif otype == "FontString" then
        local txt = obj.GetText and obj:GetText()
        if txt and txt ~= "" then line = line .. ' text="' .. tostring(txt) .. '"' end
        if obj.GetFont then
            local _, size, flags = obj:GetFont()
            if size then
                line = line .. string.format(" font=%.0f/%s", size, tostring(flags or ""))
            end
        end
        if obj.GetTextColor then line = line .. fmtColor(obj:GetTextColor()) end
    elseif otype == "StatusBar" then
        local tex = obj.GetStatusBarTexture and obj:GetStatusBarTexture()
        if tex and tex.GetTexture then line = line .. " fill=" .. tostring(tex:GetTexture()) end
        if obj.GetStatusBarColor then line = line .. fmtColor(obj:GetStatusBarColor()) end
    end
    out[#out + 1] = line
end

local function walk(frameObj, key, depth, out, seen, rootTbl)
    if depth > 6 or seen[frameObj] then return end
    seen[frameObj] = true
    describe(frameObj, key, depth, out)

    if frameObj.GetRegions then
        local regions = { frameObj:GetRegions() }
        for i = 1, #regions do
            local r = regions[i]
            if not seen[r] then
                seen[r] = true
                describe(r, keysFor(r, frameObj, rootTbl), depth + 1, out)
            end
        end
    end
    if frameObj.GetChildren then
        local kids = { frameObj:GetChildren() }
        for i = 1, #kids do
            local c = kids[i]
            walk(c, keysFor(c, frameObj, rootTbl), depth + 1, out, seen, rootTbl)
        end
    end
end

-- Build the dump for one plate frame (exposed for the test harness).
function M:DumpPlate(plate)
    local out = {}
    out[#out + 1] = ("Vantage plate dump — v%s, client %s"):format(
        Vantage.version or "?",
        (GetBuildInfo and select(4, GetBuildInfo())) or "?")
    local uf = plate.UnitFrame
    walk(plate, "NamePlate", 0, out, {}, uf)
    return table.concat(out, "\n")
end

function M:InspectTarget()
    if not (C_NamePlate and UnitExists("target")) then
        Vantage:Print("Target something with a nameplate first, then |cffffd100/vantage plate|r.")
        return
    end
    local plate = C_NamePlate.GetNamePlateForUnit("target")
    if not (plate and plate.UnitFrame) then
        Vantage:Print("No nameplate found for your target (is its plate on screen?).")
        return
    end
    local dump = self:DumpPlate(plate)
    Vantage.ParseExport:ShowText(dump, "Vantage — nameplate inspector",
        "Press |cffffd100Ctrl+C|r to copy, then paste the dump back to the developer.")
end

function M:OnEnable() end

Vantage.Inspect = M
