-- Vigil/Modules/Auras.lua
--
-- Your own debuffs/DoTs on each enemy nameplate, with live countdowns — so you
-- know exactly when to refresh Shadow Word: Pain (and friends). It scans with the
-- "PLAYER" aura filter, so it only ever shows auras YOU applied, not the whole
-- debuff soup. Read-only and combat-safe.
--
-- Look: crisp bordered icons (border tinted by dispel type — magic blue, curse
-- purple, …), a radial cooldown swipe draining as the aura expires, countdown
-- text (red inside the 3s refresh window), stack counts. Icon size and the
-- per-plate cap are user-configurable (the cap keeps 25-man raids readable).
local addonName, Vigil = ...
local M = Vigil:NewModule("Auras")

local GAP      = 2
local TEXT_HZ  = 0.1    -- countdown text refresh
local SCAN_HZ  = 0.5    -- backstop rescan (in case a UNIT_AURA is missed)

local rows = {}         -- unit -> row frame
local pool = {}
local scan = {}         -- reused scratch table (avoids garbage each scan)

local function iconSize() return Vigil.db.auraSize or 18 end
local function maxIcons() return Vigil.db.auraMax or 5 end

-- ---------------------------------------------------------------------------
-- Frame construction / styling
-- ---------------------------------------------------------------------------
local function styleButton(b, s)
    b:SetSize(s, s)
    b.time:SetFont(STANDARD_TEXT_FONT, math.max(8, math.floor(s * 0.5)), "OUTLINE")
    b.count:SetFont(STANDARD_TEXT_FONT, math.max(7, math.floor(s * 0.4)), "OUTLINE")
end

local function makeButton(row, i)
    local b = row.buttons[i]
    if b then return b end
    b = CreateFrame("Frame", nil, row)

    -- 1px border: a tintable backdrop extending 1px past the icon
    local bd = b:CreateTexture(nil, "BACKGROUND")
    bd:SetPoint("TOPLEFT", -1, 1)
    bd:SetPoint("BOTTOMRIGHT", 1, -1)
    bd:SetTexture(Vigil.WHITE)
    bd:SetVertexColor(0, 0, 0, 1)
    b.bd = bd

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- radial "draining" swipe (guarded: if the template is missing we just
    -- fall back to text-only countdowns)
    local ok, cd = pcall(CreateFrame, "Cooldown", nil, b, "CooldownFrameTemplate")
    if ok and cd then
        cd:SetAllPoints(b.icon)
        if cd.SetReverse then cd:SetReverse(true) end
        if cd.SetDrawEdge then cd:SetDrawEdge(false) end
        if cd.SetDrawBling then cd:SetDrawBling(false) end
        if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
        if cd.SetSwipeColor then cd:SetSwipeColor(0, 0, 0, 0.65) end
        b.cd = cd
    end

    -- text rides above the swipe on its own frame
    local textF = CreateFrame("Frame", nil, b)
    textF:SetAllPoints(b)
    textF:SetFrameLevel((b.cd and b.cd:GetFrameLevel() or b:GetFrameLevel()) + 1)

    b.time = textF:CreateFontString(nil, "OVERLAY")
    b.time:SetPoint("CENTER", textF, "CENTER", 0, 0)

    b.count = textF:CreateFontString(nil, "OVERLAY")
    b.count:SetPoint("BOTTOMRIGHT", textF, "BOTTOMRIGHT", 2, -1)
    b.count:SetTextColor(1, 1, 1)

    styleButton(b, iconSize())
    row.buttons[i] = b
    return b
end

-- new (or refreshed) aura instances land with a quick settle, like the cue
local auraPop = function(b, elapsed)
    b.t = b.t + elapsed
    local p = b.t / 0.12
    if p >= 1 then
        b:SetScale(1)
        b:SetScript("OnUpdate", nil)
    else
        b:SetScale(1.25 - 0.25 * p)
    end
end

local function acquireRow()
    local row = table.remove(pool)
    if not row then
        row = CreateFrame("Frame", nil, UIParent)
        row:SetFrameStrata("HIGH")
        row.buttons = {}
        row.shown = 0
    end
    row:SetHeight(iconSize())
    return row
end

-- Re-style every live + pooled button (called when the size slider moves).
function M:ApplyStyle()
    local s = iconSize()
    local function styleRow(row)
        row:SetHeight(s)
        for i = 1, #row.buttons do styleButton(row.buttons[i], s) end
    end
    for _, row in pairs(rows) do styleRow(row) end
    for _, row in ipairs(pool) do styleRow(row) end
end

-- ---------------------------------------------------------------------------
-- Countdown text
-- ---------------------------------------------------------------------------
local function setTime(fs, remaining)
    if remaining <= 0 then
        fs:SetText("")
        return
    end
    if remaining >= 60 then
        fs:SetFormattedText("%dm", math.floor(remaining / 60))
    elseif remaining >= 1 then
        fs:SetFormattedText("%d", math.floor(remaining))   -- whole seconds left, like a clock
    else
        fs:SetFormattedText("%.1f", remaining)             -- tenths in the final second
    end
    -- refresh window coloring
    if remaining <= 3 then
        fs:SetTextColor(1, 0.3, 0.3)
    else
        fs:SetTextColor(1, 0.9, 0.4)
    end
end

local function updateRow(row)
    local now = GetTime()
    for i = 1, row.shown do
        local b = row.buttons[i]
        if b then setTime(b.time, (b.expiration or 0) - now) end
    end
end

-- ---------------------------------------------------------------------------
-- Scan / refresh
-- ---------------------------------------------------------------------------
function M:Refresh(unit)
    if not Vigil.db.auras then return self:Remove(unit) end
    local overlay = Vigil.plates[unit]
    if not overlay or not overlay.plate then return end

    wipe(scan)
    for i = 1, 40 do
        local name, icon, count, dispel, duration, expiration =
            UnitAura(unit, i, "HARMFUL|PLAYER")
        if not name then break end
        if duration and duration > 0 then
            scan[#scan + 1] = { icon = icon, count = count, dispel = dispel,
                                duration = duration, expiration = expiration }
        end
    end

    if #scan == 0 then return self:Remove(unit) end
    table.sort(scan, function(a, b) return (a.expiration or 0) < (b.expiration or 0) end)

    local row = rows[unit] or acquireRow()
    rows[unit] = row
    row:ClearAllPoints()
    row:SetPoint("BOTTOM", overlay.plate, "TOP", 0, 6) -- sits above the nameplate

    local size = iconSize()
    local n = math.min(#scan, maxIcons())
    row:SetWidth(n * (size + GAP) - GAP)
    for i = 1, n do
        local b = makeButton(row, i)
        local s = scan[i]
        b:ClearAllPoints()
        b:SetPoint("LEFT", row, "LEFT", (i - 1) * (size + GAP), 0)
        b.icon:SetTexture(s.icon)

        -- pop when this slot starts showing a NEW aura instance (a refresh of
        -- the same aura gets a new start time, so it pops too — good feedback)
        local key = tostring(s.icon) .. "|"
            .. tostring(math.floor(((s.expiration or 0) - (s.duration or 0)) * 10))
        if b.__vigilKey ~= key then
            b.__vigilKey = key
            b.t = 0
            b:SetScale(1.25)
            b:SetScript("OnUpdate", auraPop)
        end

        local col = Vigil.db.auraDispel and s.dispel
            and DebuffTypeColor and DebuffTypeColor[s.dispel]
        if col then
            b.bd:SetVertexColor(col.r, col.g, col.b, 1)
        else
            b.bd:SetVertexColor(0, 0, 0, 1)
        end

        if b.cd then
            if Vigil.db.auraSwipe and s.duration and s.duration > 0 then
                local start = s.expiration - s.duration
                if b.cdStart ~= start or b.cdDur ~= s.duration then
                    b.cdStart, b.cdDur = start, s.duration
                    b.cd:SetCooldown(start, s.duration)
                end
                b.cd:Show()
            else
                b.cd:Hide()
                b.cdStart, b.cdDur = nil, nil
            end
        end

        b.count:SetText((s.count and s.count > 1) and s.count or "")
        b.expiration = s.expiration
        b:Show()
    end
    for i = n + 1, #row.buttons do
        local b = row.buttons[i]
        b:Hide()
        b:SetScale(1)
        b:SetScript("OnUpdate", nil)
    end
    row.shown = n
    row:Show()
    updateRow(row)
end

function M:Remove(unit)
    local row = rows[unit]
    if not row then return end
    rows[unit] = nil
    row:Hide()
    row:ClearAllPoints()
    row.shown = 0
    pool[#pool + 1] = row
end

function M:RefreshAll()
    if Vigil.db.auras then
        for unit in pairs(Vigil.plates) do self:Refresh(unit) end
    else
        for unit in pairs(rows) do self:Remove(unit) end
    end
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------
function M:OnEnable()
    Vigil:RegisterEvent("UNIT_AURA", function(_, unit)
        if Vigil.plates[unit] then M:Refresh(unit) end
    end)

    -- One shared ticker: ticks countdown text frequently, rescans occasionally
    -- as a backstop in case a UNIT_AURA event is missed for a nameplate unit.
    local ticker = CreateFrame("Frame")
    local tAccum, sAccum = 0, 0
    ticker:SetScript("OnUpdate", function(_, elapsed)
        tAccum = tAccum + elapsed
        sAccum = sAccum + elapsed
        if tAccum >= TEXT_HZ then
            tAccum = 0
            for _, row in pairs(rows) do
                if row:IsShown() then updateRow(row) end
            end
        end
        if sAccum >= SCAN_HZ then
            sAccum = 0
            for unit in pairs(Vigil.plates) do M:Refresh(unit) end
        end
    end)
    M.ticker = ticker
end

Vigil.Auras = M
