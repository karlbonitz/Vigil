-- Vigil/Modules/Skin.lua
--
-- Custom nameplate skin: restyles Blizzard's health bar IN PLACE — smooth
-- gradient statusbar texture, dark background, soft drop shadow, crisp 1px
-- border, outlined name font, level text, optional health text, a slim mana
-- bar for mana users, class colors on PLAYERS, and a gold outline + soft glow
-- on your current target. Mob bars keep Blizzard's reaction coloring (red =
-- hostile, yellow = neutral, green = friendly) — useful info.
--
-- Unlike the cast-bar overlay (enemies only), the skin also covers FRIENDLY
-- plates when Blizzard shows them (db.friendly), so the whole screen looks
-- consistent. It keeps its own unit->UnitFrame map for that reason.
--
-- Everything here is non-protected on the 2.5.x client (textures/fonts/child
-- regions, HookScript/hooksecurefunc) and we NEVER reparent, move, or rescale
-- the secure plate — same "decorate, don't replace" discipline as the rest of
-- Vigil, so no taint. Forbidden plates (if the client ever marks any) are skipped.
--
-- Frame paths verified for TBC 2.5.x: plate.UnitFrame.healthBar (lowercase h),
-- uf.name. (The retail uf.HealthBarsContainer.healthBar path does NOT exist here.)
local addonName, Vigil = ...
local M = Vigil:NewModule("Skin")

local skinned = {}     -- unit token -> UnitFrame, for every plate we currently skin
local applying = false -- reentrancy guard for the SetStatusBarColor hook

local function active()
    return Vigil.db.enabled and Vigil.db.skin
end

-- Skin everything except the personal resource bar; friendlies only if opted in.
local function shouldSkin(unit)
    if not active() then return false end
    if UnitIsUnit(unit, "player") then return false end
    if UnitCanAttack("player", unit) then return true end
    return Vigil.db.friendly == true
end

-- ---------------------------------------------------------------------------
-- Class colors (players only; mobs keep reaction color)
-- ---------------------------------------------------------------------------
local function classColor(unit)
    if not Vigil.db.classColors then return end
    if not unit or not UnitIsPlayer(unit) then return end
    local _, class = UnitClass(unit)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
end

local function applyBarColor(uf)
    local r, g, b = classColor(uf.unit)
    if not r and uf.unit and UnitExists(uf.unit) and UnitSelectionColor then
        -- not class-colored (NPC, or the option is off): re-assert reaction
        -- color so toggling class colors off reverts live
        r, g, b = UnitSelectionColor(uf.unit)
    end
    if r then
        applying = true
        uf.healthBar:SetStatusBarColor(r, g, b)
        applying = false
    end
end

-- ---------------------------------------------------------------------------
-- Damage bites: when health drops, a bright sliver marks the lost segment and
-- fades out — incoming damage becomes readable at a glance. Textures are
-- pooled per-frame; ONE shared driver animates them and hides itself when
-- nothing is fading, so the idle cost is zero.
-- ---------------------------------------------------------------------------
local BITE_TIME = 0.4
local bites = {}
local biteDriver = CreateFrame("Frame")
biteDriver:Hide()
biteDriver:SetScript("OnUpdate", function(_, elapsed)
    for i = #bites, 1, -1 do
        local b = bites[i]
        b.t = b.t - elapsed
        if b.t <= 0 then
            b.tex:Hide()
            b.pool[#b.pool + 1] = b.tex
            table.remove(bites, i)
        else
            b.tex:SetAlpha((b.t / BITE_TIME) * 0.7)
        end
    end
    if #bites == 0 then biteDriver:Hide() end
end)

local function spawnBite(uf, fromV, toV, max)
    local hb = uf.healthBar
    local w = hb:GetWidth()
    if not w or w <= 0 or not max or max <= 0 then return end
    local x1 = (toV / max) * w
    local width = ((fromV - toV) / max) * w
    if width < 1 then return end
    local pool = uf.__vigilBitePool
    local tex = table.remove(pool)
    if not tex then
        tex = hb:CreateTexture(nil, "OVERLAY", nil, 2)
        tex:SetTexture(Vigil.WHITE)
    end
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", hb, "TOPLEFT", x1, 0)
    tex:SetPoint("BOTTOMLEFT", hb, "BOTTOMLEFT", x1, 0)
    tex:SetWidth(math.min(width, w - x1))
    tex:SetVertexColor(1, 0.9, 0.75)
    tex:SetAlpha(0.7)
    tex:Show()
    bites[#bites + 1] = { tex = tex, t = BITE_TIME, pool = pool, uf = uf }
    biteDriver:Show()
end

-- retire any in-flight bites on a frame (it's being recycled for a new unit)
local function purgeBites(uf)
    for i = #bites, 1, -1 do
        local b = bites[i]
        if b.uf == uf then
            b.tex:Hide()
            b.pool[#b.pool + 1] = b.tex
            table.remove(bites, i)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Execute marker: a faint tick at 20% that lights up (with red HP text) once
-- the mob is in execute range. Useful for every class; pretty for all of them.
-- ---------------------------------------------------------------------------
local EXEC_PCT = 0.20

local function updateExec(uf)
    local ex = uf.__vigilExec
    if not ex then return end
    if not (active() and Vigil.db.executeMark) then ex:Hide(); return end
    local hb = uf.healthBar
    local v = hb:GetValue() or 0
    local _, max = hb:GetMinMaxValues()
    if not max or max <= 0 then ex:Hide(); return end
    ex:Show()
    if v / max <= EXEC_PCT then
        ex:SetVertexColor(1, 0.35, 0.30, 0.95) -- in execute range: lit
    else
        ex:SetVertexColor(1, 1, 1, 0.22)       -- waiting: a quiet tick
    end
end

-- ---------------------------------------------------------------------------
-- Health text
-- ---------------------------------------------------------------------------
local function fmtNum(n)
    if n >= 1e6 then return ("%.1fm"):format(n / 1e6) end
    if n >= 1e3 then return ("%.1fk"):format(n / 1e3) end
    return tostring(math.floor(n))
end

local function updateHealthText(uf)
    local fs = uf.__vigilHP
    if not fs then return end
    local mode = Vigil.db.healthText
    if not active() or not mode or mode == "none" then fs:SetText(""); return end
    local hb = uf.healthBar
    local v = hb:GetValue() or 0
    local _, max = hb:GetMinMaxValues()
    if not max or max <= 0 then fs:SetText(""); return end
    if mode == "percent" then
        local pct = math.floor(v / max * 100 + 0.5)
        if pct >= 100 then fs:SetText("") else fs:SetFormattedText("%d%%", pct) end
    elseif mode == "health" then
        fs:SetText(fmtNum(v))
    else -- "both"
        fs:SetFormattedText("%s · %d%%", fmtNum(v), math.floor(v / max * 100 + 0.5))
    end
    -- execute-range urgency rides the HP text too
    if Vigil.db.executeMark and v / max <= EXEC_PCT then
        fs:SetTextColor(1, 0.35, 0.30, 1)
    else
        fs:SetTextColor(1, 1, 1, 0.95)
    end
end

-- one handler for everything that reacts to the bar moving
local function onHealthChanged(uf)
    updateHealthText(uf)
    updateExec(uf)
    local hb = uf.healthBar
    local v = hb:GetValue() or 0
    local last = uf.__vigilLastV
    uf.__vigilLastV = v
    if Vigil.db.bites and active() and last and v < last then
        local _, max = hb:GetMinMaxValues()
        spawnBite(uf, last, v, max)
    end
end

-- ---------------------------------------------------------------------------
-- Level text ("70", "71+" elite, "70r" rare, red "??" for skull/boss)
-- ---------------------------------------------------------------------------
local function updateLevel(uf)
    local fs = uf.__vigilLvl
    if not fs then return end
    local unit = uf.unit
    if not (active() and Vigil.db.showLevel and unit and UnitExists(unit)) then
        fs:SetText(""); return
    end
    local lvl = UnitLevel(unit)
    if not lvl or lvl <= 0 then
        fs:SetText("??")
        fs:SetTextColor(1, 0.15, 0.15)
        return
    end
    local cls = UnitClassification and UnitClassification(unit)
    local suffix = ""
    if cls == "elite" or cls == "rareelite" then suffix = "+"
    elseif cls == "rare" then suffix = "r" end
    fs:SetText(lvl .. suffix)
    local c = GetQuestDifficultyColor and GetQuestDifficultyColor(lvl)
    if c then fs:SetTextColor(c.r, c.g, c.b) else fs:SetTextColor(1, 0.82, 0) end
end

-- ---------------------------------------------------------------------------
-- Mana bar (slim, under the health bar; only for units that actually use mana)
-- ---------------------------------------------------------------------------
local function updateMana(uf)
    local m = uf.__vigilMana
    if not m then return end
    local unit = uf.unit
    if not (active() and Vigil.db.manaBar and unit and UnitExists(unit))
        or UnitPowerType(unit) ~= 0 then -- 0 = mana
        m:Hide(); return
    end
    local max = UnitPowerMax(unit, 0)
    if not max or max <= 0 then m:Hide(); return end
    m:SetMinMaxValues(0, max)
    m:SetValue(UnitPower(unit, 0) or 0)
    m:Show()
end

-- ---------------------------------------------------------------------------
-- One-time structural setup per pooled plate (shadow, bg, border, glow, text,
-- hooks, remembered originals). Blizzard pools UnitFrames, so this runs once
-- per physical frame and everything after is cheap re-assertion.
-- ---------------------------------------------------------------------------
local function build(uf)
    local hb = uf.healthBar
    if not hb then return false end
    if hb.SetClipsChildren then hb:SetClipsChildren(false) end -- let edges/glow show past the bar

    -- remember originals so the skin can be toggled off cleanly
    uf.__vigilOrigTex = hb:GetStatusBarTexture()
    if uf.name then uf.__vigilOrigFont = { uf.name:GetFont() } end

    -- soft drop shadow behind the whole bar (radial glow tinted black)
    local sh = hb:CreateTexture(nil, "BACKGROUND", nil, -8)
    sh:SetTexture(Vigil.GLOW)
    sh:SetVertexColor(0, 0, 0, 0.6)
    sh:SetPoint("TOPLEFT", hb, -10, 7)
    sh:SetPoint("BOTTOMRIGHT", hb, 10, -7)
    uf.__vigilShadow = sh

    -- soft gold glow behind your current target's plate
    local tg = hb:CreateTexture(nil, "BACKGROUND", nil, -7)
    tg:SetTexture(Vigil.GLOW)
    tg:SetBlendMode("ADD")
    tg:SetVertexColor(1, 0.82, 0.1, 0.5)
    tg:SetPoint("TOPLEFT", hb, -14, 10)
    tg:SetPoint("BOTTOMRIGHT", hb, 14, -10)
    tg:Hide()
    uf.__vigilTargetGlow = tg

    -- dark background behind the fill
    local bg = hb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(hb)
    bg:SetColorTexture(0.04, 0.04, 0.05, 0.8)
    uf.__vigilBG = bg

    -- crisp 1px border (gold on current target)
    uf.__vigilBorder = Vigil:CreateBorder(hb)

    -- level, left-inside the bar; health text, right-inside
    local lvl = hb:CreateFontString(nil, "OVERLAY")
    lvl:SetFont(STANDARD_TEXT_FONT, 8, "OUTLINE")
    lvl:SetPoint("LEFT", hb, "LEFT", 2, 0)
    uf.__vigilLvl = lvl

    local hp = hb:CreateFontString(nil, "OVERLAY")
    hp:SetFont(STANDARD_TEXT_FONT, 8, "OUTLINE")
    hp:SetPoint("RIGHT", hb, "RIGHT", -2, 0)
    hp:SetTextColor(1, 1, 1, 0.95)
    uf.__vigilHP = hp

    -- slim mana bar riding under the health bar (child of it, so it shares
    -- visibility/scale; we add children, never touch Blizzard's own regions)
    local mana = CreateFrame("StatusBar", nil, hb)
    mana:SetPoint("TOPLEFT", hb, "BOTTOMLEFT", 0, -3)
    mana:SetPoint("TOPRIGHT", hb, "BOTTOMRIGHT", 0, -3)
    mana:SetHeight(4)
    -- flat texture, not the gradient TGA: 32px of gradient squeezed into 4px
    -- averages out to a washed-up near-white; a solid fill stays readably BLUE
    mana:SetStatusBarTexture(Vigil.WHITE)
    mana:SetStatusBarColor(0.18, 0.42, 0.92)
    local mbg = mana:CreateTexture(nil, "BACKGROUND")
    mbg:SetAllPoints(mana)
    mbg:SetColorTexture(0.04, 0.04, 0.05, 0.8)
    mana.border = Vigil:CreateBorder(mana)
    mana:Hide()
    uf.__vigilMana = mana

    -- 1px glass highlight along the bar's top edge (a quiet "lit" look)
    local glass = hb:CreateTexture(nil, "OVERLAY", nil, 1)
    glass:SetTexture(Vigil.WHITE)
    glass:SetVertexColor(1, 1, 1, 0.10)
    glass:SetPoint("TOPLEFT", hb, 0, 0)
    glass:SetPoint("TOPRIGHT", hb, 0, 0)
    glass:SetHeight(1)
    uf.__vigilGlass = glass

    -- execute tick at 20% (positioned in applySkin once the width is known)
    local ex = hb:CreateTexture(nil, "OVERLAY", nil, 1)
    ex:SetTexture(Vigil.WHITE)
    ex:SetVertexColor(1, 1, 1, 0.22)
    ex:SetWidth(1)
    ex:Hide()
    uf.__vigilExec = ex

    -- mouseover wash (shown/hidden by the hover watcher)
    local hov = hb:CreateTexture(nil, "OVERLAY", nil, 3)
    hov:SetTexture(Vigil.WHITE)
    hov:SetBlendMode("ADD")
    hov:SetAllPoints(hb)
    hov:SetVertexColor(1, 1, 1, 0.12)
    hov:Hide()
    uf.__vigilHover = hov

    -- bite-texture pool (see spawnBite)
    uf.__vigilBitePool = {}

    -- keep text/exec/bites live as the bar moves (HookScript = taint-safe)
    hb:HookScript("OnValueChanged", function() onHealthChanged(uf) end)
    hb:HookScript("OnMinMaxChanged", function()
        uf.__vigilLastV = nil -- unit swap: don't bite across different mobs
        onHealthChanged(uf)
    end)

    -- keep class colors in place when Blizzard re-asserts reaction color
    hooksecurefunc(hb, "SetStatusBarColor", function(bar, r, g, b)
        if applying or not active() then return end
        local cr, cg, cb = classColor(uf.unit)
        if cr and (r ~= cr or g ~= cg or b ~= cb) then
            applying = true
            bar:SetStatusBarColor(cr, cg, cb)
            applying = false
        end
    end)

    -- Blizzard's own plate cast bar double-draws under Vigil's styled one (a
    -- flat grey bar during casts). Blizzard re-Shows it on every cast, so a
    -- one-time Hide can't win — hook OnShow and keep it down while the flag
    -- says WE own cast bars on this frame. Hooks can't be removed, so the
    -- per-frame flag (set in applySkin, cleared in removeSkin) is the gate.
    local bcb = uf.CastBar
    if bcb and bcb.HookScript then
        bcb:HookScript("OnShow", function(s)
            if uf.__vigilHideCast then s:Hide() end
        end)
    end

    uf.__vigilSkinned = true
    return true
end

-- Hide Blizzard's own bar decorations while our skin is on (restored on toggle).
local function setBlizzDecor(uf, shown)
    local hb = uf.healthBar
    local bd = hb and hb.border
    if bd then
        if shown then
            if bd.Show then bd:Show() end
        else
            if bd.Hide then bd:Hide() end
        end
    end
    local sel = uf.selectionHighlight
    if sel and sel.SetAlpha then
        sel:SetAlpha(shown and 0.25 or 0) -- 0.25 is Blizzard's default
    end
end

-- Border speaks in this order: your target (accent) > threat state (red =
-- aggro on you / amber = pulling / green = safely tanking in tank mode) >
-- plain black. Threat.lua feeds the state via SetThreat below.
local function updateHighlight(uf)
    if not uf.__vigilBorder then return end
    local isTarget = uf.unit and UnitIsUnit(uf.unit, "target")
    if isTarget then
        uf.__vigilBorder:SetColor(Vigil:RGB("kick"))
    elseif uf.__vigilThreat then
        uf.__vigilBorder:SetColor(Vigil:RGB(uf.__vigilThreat))
    else
        uf.__vigilBorder:SetColor(0, 0, 0, 1)
    end
    local tg = uf.__vigilTargetGlow
    if tg then
        if isTarget and Vigil.db.targetGlow then tg:Show() else tg:Hide() end
    end
end

-- Threat.lua pushes each plate's aggro state here (a palette key, or nil).
function M:SetThreat(unit, key)
    local uf = skinned[unit]
    if not (uf and uf.__vigilSkinned) then return end
    if uf.__vigilThreat ~= key then
        uf.__vigilThreat = key
        updateHighlight(uf)
    end
end

local function applySkin(uf)
    if not uf or not uf.healthBar then return end
    if not uf.__vigilSkinned then
        if not build(uf) then return end
    end
    uf.healthBar:SetStatusBarTexture(Vigil.BAR)   -- texture persists; cheap to re-assert per add
    uf.__vigilShadow:Show()
    uf.__vigilBG:Show()
    uf.__vigilBorder:Show()
    uf.__vigilGlass:Show()
    setBlizzDecor(uf, false)

    -- fresh unit on this frame: no cross-mob bites, no stale threat border
    purgeBites(uf)
    uf.__vigilThreat = nil
    uf.__vigilLastV = uf.healthBar:GetValue()
    local w = uf.healthBar:GetWidth()
    if w and w > 0 then
        local ex = uf.__vigilExec
        ex:ClearAllPoints()
        ex:SetPoint("TOP", uf.healthBar, "TOPLEFT", w * EXEC_PCT, 0)
        ex:SetPoint("BOTTOM", uf.healthBar, "BOTTOMLEFT", w * EXEC_PCT, 0)
    end
    updateExec(uf)
    uf.__vigilHover:Hide()
    if uf.name then
        uf.name:SetFont(STANDARD_TEXT_FONT, Vigil.db.nameSize or 10, "OUTLINE")
        local r, g, b = classColor(uf.unit)
        if r then uf.name:SetTextColor(r, g, b) else uf.name:SetTextColor(1, 1, 1) end
    end
    local small = math.max(7, (Vigil.db.nameSize or 10) - 2)
    uf.__vigilHP:SetFont(STANDARD_TEXT_FONT, small, "OUTLINE")
    uf.__vigilLvl:SetFont(STANDARD_TEXT_FONT, small, "OUTLINE")
    applyBarColor(uf)
    updateHealthText(uf)
    updateLevel(uf)
    updateMana(uf)
    updateHighlight(uf)

    -- suppress Blizzard's plate cast bar only where OUR cast overlay serves:
    -- enemies, with Vigil cast bars enabled. Friendlies keep Blizzard's.
    uf.__vigilHideCast = (Vigil.db.showCastbar and uf.unit
        and UnitCanAttack("player", uf.unit)) or false
    if uf.__vigilHideCast and uf.CastBar and uf.CastBar:IsShown() then
        uf.CastBar:Hide()
    end
end

local function removeSkin(uf)
    if not uf or not uf.__vigilSkinned then return end
    uf.__vigilHideCast = false -- hand the plate cast bar back to Blizzard
    local hb = uf.healthBar
    if uf.__vigilOrigTex then hb:SetStatusBarTexture(uf.__vigilOrigTex) end
    uf.__vigilShadow:Hide()
    uf.__vigilBG:Hide()
    uf.__vigilBorder:Hide()
    uf.__vigilTargetGlow:Hide()
    uf.__vigilGlass:Hide()
    uf.__vigilExec:Hide()
    uf.__vigilHover:Hide()
    purgeBites(uf)
    uf.__vigilThreat = nil
    uf:SetAlpha(1)
    uf.__vigilHP:SetText("")
    uf.__vigilLvl:SetText("")
    uf.__vigilMana:Hide()
    setBlizzDecor(uf, true)
    if uf.name and uf.__vigilOrigFont then uf.name:SetFont(unpack(uf.__vigilOrigFont)) end
    -- hand bar color back to the client's reaction coloring
    if uf.unit and UnitExists(uf.unit) and UnitSelectionColor then
        local r, g, b = UnitSelectionColor(uf.unit)
        if r then
            applying = true
            hb:SetStatusBarColor(r, g, b)
            applying = false
        end
    end
end

-- Focus fade: while a target exists, everything that isn't it fades hard
-- (db.focusAlpha, default 0.5) so the selected enemy is unmistakable. The
-- whole plate family follows — bar, cast overlay, DoT row — with ONE
-- exception: a live kick cue always gets full volume, even off-target.

-- the alpha this unit should wear right now (also used by late spawners)
local function currentDim(unit)
    if not (active() and Vigil.db.focusDim and UnitExists("target")) then return 1 end
    if UnitIsUnit(unit, "target") then return 1 end
    return Vigil.db.focusAlpha or 0.5
end
M.CurrentDim = currentDim

local function applyFocusDim()
    for unit, uf in pairs(skinned) do
        if uf.__vigilSkinned then
            uf:SetAlpha(currentDim(unit))
        end
    end
    for unit, o in pairs(Vigil.plates or {}) do
        local a = currentDim(unit)
        if o.kickF and o.kickF:IsShown() then a = 1 end -- the cue never fades
        o:SetAlpha(a)
        if Vigil.Auras and Vigil.Auras.DimRow then Vigil.Auras:DimRow(unit, a) end
    end
end
M.ApplyFocusDim = applyFocusDim

-- Re-apply or strip the skin across ALL current plates (toggle + option changes).
function M:RefreshAll()
    if not C_NamePlate then return end
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
        if not (plate.IsForbidden and plate:IsForbidden()) then
            local uf = plate.UnitFrame
            local unit = uf and uf.unit
            if unit then
                if shouldSkin(unit) then
                    applySkin(uf)
                    skinned[unit] = uf
                else
                    removeSkin(uf)
                    skinned[unit] = nil
                end
            end
        end
    end
    applyFocusDim()
end

function M:OnEnable()
    if not C_NamePlate then return end

    Vigil:RegisterEvent("NAME_PLATE_UNIT_ADDED", function(_, unit)
        local plate = C_NamePlate.GetNamePlateForUnit(unit)
        if not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
        local uf = plate.UnitFrame
        if not uf then return end
        if shouldSkin(unit) then
            applySkin(uf)
            skinned[unit] = uf
            -- a plate spawning mid-fight inherits the current focus state
            uf:SetAlpha(currentDim(unit))
        elseif uf.__vigilSkinned then
            -- Blizzard recycled a frame we skinned earlier for a unit we must
            -- NOT skin (personal resource bar, or friendlies toggled off) —
            -- scrub it or the old skin bleeds onto the wrong plate.
            removeSkin(uf)
        end
    end)

    Vigil:RegisterEvent("NAME_PLATE_UNIT_REMOVED", function(_, unit)
        skinned[unit] = nil
    end)

    Vigil:RegisterEvent("PLAYER_TARGET_CHANGED", function()
        if not active() then return end
        for _, uf in pairs(skinned) do
            if uf.__vigilSkinned then updateHighlight(uf) end
        end
        applyFocusDim()
    end)

    -- mouseover wash: light up the hovered plate; a light pulse (piggybacking
    -- the shared frame's OnUpdate) retires it once the mouse moves off
    local hovered
    Vigil:RegisterEvent("UPDATE_MOUSEOVER_UNIT", function()
        if hovered then hovered.__vigilHover:Hide(); hovered = nil end
        if not active() then return end
        for unit, uf in pairs(skinned) do
            if uf.__vigilSkinned and UnitIsUnit(unit, "mouseover") then
                uf.__vigilHover:Show()
                hovered = uf
                return
            end
        end
    end)
    local hoverAccum = 0
    Vigil.frame:HookScript("OnUpdate", function(_, elapsed)
        if not hovered then return end
        hoverAccum = hoverAccum + elapsed
        if hoverAccum < 0.15 then return end
        hoverAccum = 0
        local unit = hovered.unit
        if not (unit and UnitExists("mouseover") and UnitIsUnit(unit, "mouseover")) then
            hovered.__vigilHover:Hide()
            hovered = nil
        end
    end)

    -- keep the mana bar live
    local function powerEvent(_, unit)
        local uf = unit and skinned[unit]
        if uf then updateMana(uf) end
    end
    Vigil:RegisterEvent("UNIT_POWER_UPDATE", powerEvent)
    Vigil:RegisterEvent("UNIT_MAXPOWER", powerEvent)
    Vigil:RegisterEvent("UNIT_DISPLAYPOWER", powerEvent)
end

Vigil.Skin = M
