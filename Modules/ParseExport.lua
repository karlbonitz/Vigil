-- Vantage/Modules/ParseExport.lua
--
-- Exports Vantage Parse data as a JSON string in a copy-paste window
-- (/vantage export). WoW addons have no network access, so the v0.1 bridge is:
-- Ctrl+A, Ctrl+C here -> paste into the Vantage Parse web report (a static page
-- that decodes everything in your browser; nothing is uploaded anywhere).
--
-- The encoder is hand-rolled (~40 lines) to keep Vantage dependency-free.
-- Compression (LibDeflate) becomes worthwhile only if strings outgrow the
-- edit box in practice.
local addonName, Vantage = ...
local M = Vantage:NewModule("ParseExport")

-- ---------------------------------------------------------------------------
-- Minimal JSON encoder (strings, numbers, booleans, arrays, string-key maps)
-- ---------------------------------------------------------------------------
local function esc(s)
    return (s:gsub('[%z\1-\31\\"]', function(c)
        if c == '\\' then return '\\\\'
        elseif c == '"' then return '\\"'
        elseif c == '\n' then return '\\n'
        elseif c == '\r' then return '\\r'
        elseif c == '\t' then return '\\t'
        else return string.format('\\u%04x', c:byte()) end
    end))
end

local function enc(v, out)
    local t = type(v)
    if t == "string" then
        out[#out + 1] = '"' .. esc(v) .. '"'
    elseif t == "number" then
        out[#out + 1] = (v % 1 == 0) and string.format("%d", v) or string.format("%.3f", v)
    elseif t == "boolean" then
        out[#out + 1] = v and "true" or "false"
    elseif t == "table" then
        if #v > 0 or next(v) == nil then -- array (or empty -> [])
            out[#out + 1] = "["
            for i = 1, #v do
                if i > 1 then out[#out + 1] = "," end
                enc(v[i], out)
            end
            out[#out + 1] = "]"
        else                             -- string-keyed object
            out[#out + 1] = "{"
            local first = true
            for k, val in pairs(v) do
                if not first then out[#out + 1] = "," end
                first = false
                out[#out + 1] = '"' .. esc(tostring(k)) .. '":'
                enc(val, out)
            end
            out[#out + 1] = "}"
        end
    else
        out[#out + 1] = "null"
    end
end

-- Encode any Lua value to a JSON string. Shared with Modules/Contribute.lua so
-- the addon has exactly one JSON encoder. (Dot-call: Vantage.ParseExport.Encode.)
function M.Encode(payload)
    local out = {}
    enc(payload, out)
    return table.concat(out)
end

function M:BuildExport()
    return M.Encode({
        v        = 1,
        exported = time(),
        sessions = (VantageParseDB and VantageParseDB.sessions) or {},
        roster   = (VantageParseDB and VantageParseDB.roster) or {},
    })
end

-- ---------------------------------------------------------------------------
-- Export window (built lazily; styled like the rest of Vantage)
-- ---------------------------------------------------------------------------
local frame

local function build()
    frame = CreateFrame("Frame", "VantageExportFrame", UIParent)
    frame:SetSize(560, 320)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetColorTexture(0.055, 0.06, 0.075, 0.97)
    frame.border = Vantage:CreateBorder(frame)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("Vantage Parse — session export")

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    frame.title = title
    frame.hint = hint

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    local scroll = CreateFrame("ScrollFrame", "VantageExportScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -48)
    scroll:SetPoint("BOTTOMRIGHT", -30, 12)

    local eb = CreateFrame("EditBox", nil, scroll)
    eb:SetMultiLine(true)
    eb:SetMaxLetters(0)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(510)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); frame:Hide() end)
    -- keep the whole blob selected so Ctrl+C always grabs everything
    eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    eb:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    -- read-only: any typing is immediately reverted
    eb:SetScript("OnChar", function(self) self:SetText(self.payload or ""); self:HighlightText() end)
    scroll:SetScrollChild(eb)
    frame.editBox = eb

    frame:Hide()
end

-- Generic copy-paste window: any module can surface a blob of text for the
-- user to Ctrl+C (the plate inspector uses this too).
function M:ShowText(payload, title, hint)
    if not frame then build() end
    frame.title:SetText(title or "Vantage")
    frame.hint:SetText(hint or "Press |cffffd100Ctrl+C|r to copy (text is pre-selected).")
    local eb = frame.editBox
    eb.payload = payload
    eb:SetText(payload)
    frame:Show()
    eb:SetFocus()
    eb:HighlightText()
end

function M:Toggle()
    if frame and frame:IsShown() then
        frame:Hide()
        return
    end
    local payload = self:BuildExport()
    self:ShowText(payload, "Vantage Parse — session export",
        "Press |cffffd100Ctrl+C|r to copy (text is pre-selected), then paste it into the report page: |cffffd100karlbonitz.github.io/Vantage|r")
    Vantage:Print(("Export ready: %.1f KB. Ctrl+C, then paste into the report page: karlbonitz.github.io/Vantage")
        :format(#payload / 1024))
end

function M:OnEnable() end

Vantage.ParseExport = M
