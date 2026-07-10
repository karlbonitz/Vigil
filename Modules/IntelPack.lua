-- Vantage/Modules/IntelPack.lua
--
-- Shareable Intel Packs. Vantage teaches itself which casts are kickable
-- (Modules/Learn.lua); this lets you hand that knowledge to a friend as a compact
-- copy-paste string and merge theirs into yours — direct player-to-player sharing,
-- no server and no libraries. Curated and community data always win; an import
-- only ever fills the gaps you didn't already have.
--
-- Format (human-inspectable, delimiter-safe — spell names/zones never contain
-- `~` or `;`):  VTGPACK1;<id>~<name>~<zone>;<id>~<name>~<zone>; ...
local addonName, Vantage = ...
local M = Vantage:NewModule("IntelPack")

local HEADER = "VTGPACK1"
local FSEP, RSEP = "~", ";"

-- Serialize your self-learned pack into one shareable string.
function M:BuildString()
    local d = (type(VantageLearnedDB) == "table" and VantageLearnedDB.spells) or nil
    local rows = {}
    if d then
        for _, e in pairs(d) do
            if e.id and e.name and e.name ~= "" then
                rows[#rows + 1] = table.concat({ e.id, e.name, e.zone or "" }, FSEP)
            end
        end
    end
    return HEADER .. RSEP .. table.concat(rows, RSEP)
end

-- How many casts are in your shareable pack.
function M:Count()
    local d = (type(VantageLearnedDB) == "table" and VantageLearnedDB.spells) or nil
    local n = 0
    if d then for _, e in pairs(d) do if e.id and e.name then n = n + 1 end end end
    return n
end

-- Parse + merge a shared string. Returns added, skipped, ok(boolean).
function M:Import(str)
    if type(str) ~= "string" then return 0, 0, false end
    str = str:gsub("[\r\n\t]", "")            -- drop wrap artifacts, keep name spaces
    str = str:match("^%s*(.-)%s*$") or str    -- trim ends
    local body = str:match("^" .. HEADER .. RSEP .. "(.*)$")
    if not body then return 0, 0, false end
    local added, skipped = 0, 0
    for row in (body .. RSEP):gmatch("(.-)" .. RSEP) do
        if row ~= "" then
            local id, name, zone = row:match("^(%d+)" .. FSEP .. "(.-)" .. FSEP .. "(.*)$")
            id = tonumber(id)
            -- a real spell id is a small positive integer; reject 0 and absurd /
            -- overflow ids (a huge digit run becomes a float that would re-serialize
            -- as "1e+26" and be silently dropped on the friend's re-import)
            if id and id > 0 and id < 2 ^ 31 and name and name ~= "" then
                if Vantage.Learn and Vantage.Learn:Import(name, id, zone ~= "" and zone or nil) then
                    added = added + 1
                else
                    skipped = skipped + 1
                end
            end
        end
    end
    return added, skipped, true
end

-- ---------------------------------------------------------------------------
-- Export: reuse the shared copy window (read-only, Ctrl+C).
-- ---------------------------------------------------------------------------
function M:ShowExport()
    local n = self:Count()
    if n == 0 then
        Vantage:Print("Nothing to share yet — Vantage banks self-learned kicks as you (or your group) interrupt casts the pack didn't cover. Play, then try again.")
        return
    end
    local str = self:BuildString()
    if Vantage.ParseExport then
        Vantage.ParseExport:ShowText(str, "Vantage — share your Intel Pack",
            ("Press |cffffd100Ctrl+C|r to copy your %d self-learned kick%s, then a friend runs |cffffd100/vantage import|r and pastes it.")
            :format(n, n == 1 and "" or "s"))
    end
    Vantage:Print(("Intel Pack ready: |cffffd100%d|r self-learned cast%s. Ctrl+C to copy."):format(n, n == 1 and "" or "s"))
end

-- ---------------------------------------------------------------------------
-- Import: a small editable paste dialog with an Import button.
-- ---------------------------------------------------------------------------
local importFrame

local function buildImport()
    local f = CreateFrame("Frame", "VantageImportFrame", UIParent)
    f:SetSize(560, 300)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetColorTexture(0.055, 0.06, 0.075, 0.97)
    f.border = Vantage:CreateBorder(f)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("Vantage — import an Intel Pack")

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    hint:SetText("Paste a shared pack string below, then click Import. Curated data always wins.")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    local scroll = CreateFrame("ScrollFrame", "VantageImportScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -48)
    scroll:SetPoint("BOTTOMRIGHT", -30, 42)

    local eb = CreateFrame("EditBox", nil, scroll)
    eb:SetMultiLine(true)
    eb:SetMaxLetters(0)
    eb:SetAutoFocus(true)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(510)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
    scroll:SetScrollChild(eb)
    f.editBox = eb

    local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btn:SetSize(120, 24)
    btn:SetPoint("BOTTOMRIGHT", -14, 10)
    btn:SetText("Import")
    btn:SetScript("OnClick", function()
        local added, skipped, ok = M:Import(eb:GetText())
        if not ok then
            Vantage:Print("That doesn't look like a Vantage Intel Pack string — nothing imported.")
        else
            Vantage:Print(("Intel Pack imported: |cffffd100%d|r new, %d already known."):format(added, skipped))
            f:Hide()
        end
    end)

    f:Hide()
    importFrame = f
end

function M:ShowImport()
    if not importFrame then buildImport() end
    importFrame.editBox:SetText("")
    importFrame:Show()
    importFrame.editBox:SetFocus()
end

function M:OnEnable() end

Vantage.IntelPack = M
