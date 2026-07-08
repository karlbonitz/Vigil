-- Vantage/Modules/Skin.lua
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
-- Vantage, so no taint. Forbidden plates (if the client ever marks any) are skipped.
--
-- Frame paths verified for TBC 2.5.x: plate.UnitFrame.healthBar (lowercase h),
-- uf.name. (The retail uf.HealthBarsContainer.healthBar path does NOT exist here.)
local addonName, Vantage = ...
local M = Vantage:NewModule("Skin")

local skinned = {}     -- unit token -> UnitFrame, for every plate we currently skin
local applying = false -- reentrancy guard for the SetStatusBarColor hook

-- Which unit does this frame show? Prefer OUR field (set from the event's
-- authoritative token in applySkin) over Blizzard's uf.unit — at /reload the
-- Blizzard field isn't populated yet when the initial plate batch fires
-- ADDED, which used to silently skip coloring + cast-bar suppression there.
local function unitOf(uf)
    return uf.__vantageUnit or uf.unit
end

-- Blizzard's plate cast bar, whatever this client calls it. 2.5.4-era put it
-- directly on the UnitFrame (CastBar/castBar); the 2.5.6 retail-style refactor
-- moved it into a CastBarsContainer.
local function blizzCastBar(uf)
    return uf.CastBar or uf.castBar
        or (uf.CastBarsContainer and uf.CastBarsContainer.castBar)
end

local function active()
    return Vantage.db.enabled and Vantage.db.skin
end

-- Skin everything except the personal resource bar; friendlies only if opted in.
local function shouldSkin(unit)
    if not active() then return false end
    if UnitIsUnit(unit, "player") then return false end
    if UnitCanAttack("player", unit) then return true end
    return Vantage.db.friendly == true
end

-- ---------------------------------------------------------------------------
-- Class colors (players only; mobs keep reaction color)
-- ---------------------------------------------------------------------------
local function classColor(unit)
    if not Vantage.db.classColors then return end
    if not unit or not UnitIsPlayer(unit) then return end
    local _, class = UnitClass(unit)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
end

-- What color should this bar be RIGHT NOW?
--   class color (players) > group aggro scheme (NPCs in combat) > reaction.
-- The aggro scheme makes the BAR ITSELF answer "whose problem is this?" in
-- a group: alarm red = it's coming for you, calm brick = the tank has it,
-- green (tank mode) = safely on you. Solo and out of combat, bars keep
-- normal reaction colors — solo, aggro information is a tautology.
local function desiredBarColor(uf)
    local unit = unitOf(uf)
    if not unit or not UnitExists(unit) then return nil end
    local r, g, b = classColor(unit)
    if r then return r, g, b end
    if Vantage.db.threat and IsInGroup() and not UnitIsPlayer(unit)
        and UnitCanAttack("player", unit) and UnitAffectingCombat(unit) then
        local tkey = uf.__vantageThreat
        if tkey == "threatBad" then return Vantage:RGB("aggroAlarm") end
        if tkey == "threatWarn" then return Vantage:RGB("threatWarn") end -- closing in
        if tkey == "threatOK" then return Vantage:RGB("aggroSafe") end
        return Vantage:RGB("aggroCalm")
    end
    if UnitSelectionColor then return UnitSelectionColor(unit) end
    return nil
end

local function applyBarColor(uf)
    local r, g, b = desiredBarColor(uf)
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
            b.uf.__vantageBite = nil
            table.remove(bites, i)
        else
            b.tex:SetAlpha((b.t / BITE_TIME) * 0.7)
        end
    end
    if #bites == 0 then biteDriver:Hide() end
end)

local function positionBite(uf, b)
    local hb = uf.healthBar
    b.tex:ClearAllPoints()
    b.tex:SetPoint("TOPLEFT", hb, "TOPLEFT", b.x1, 0)
    b.tex:SetPoint("BOTTOMLEFT", hb, "BOTTOMLEFT", b.x1, 0)
    b.tex:SetWidth(math.max(1, b.x2 - b.x1))
end

-- ONE bite per bar: rapid hits extend the live sliver instead of stacking
-- overlapping flashes (which read as graphical glitches during a burn phase)
local function spawnBite(uf, fromV, toV, max)
    local hb = uf.healthBar
    local w = hb:GetWidth()
    if not w or w <= 0 or not max or max <= 0 then return end
    local x1 = math.max(0, (toV / max) * w)
    local x2 = math.min(w, (fromV / max) * w)
    if x2 - x1 < 1 then return end

    local b = uf.__vantageBite
    if b then
        b.x1 = math.min(b.x1, x1)
        b.x2 = math.max(b.x2, x2)
        b.t = BITE_TIME
    else
        local tex = uf.__vantageBiteTex
        if not tex then
            tex = hb:CreateTexture(nil, "OVERLAY", nil, 2)
            tex:SetTexture(Vantage.WHITE)
            tex:SetVertexColor(1, 0.9, 0.75)
            uf.__vantageBiteTex = tex
        end
        b = { uf = uf, tex = tex, x1 = x1, x2 = x2, t = BITE_TIME }
        uf.__vantageBite = b
        bites[#bites + 1] = b
    end
    b.tex:SetAlpha(0.7)
    positionBite(uf, b)
    b.tex:Show()
    biteDriver:Show()
end

-- retire the in-flight bite on a frame (it's being recycled for a new unit)
local function purgeBites(uf)
    local b = uf.__vantageBite
    if not b then return end
    b.tex:Hide()
    uf.__vantageBite = nil
    for i = #bites, 1, -1 do
        if bites[i] == b then table.remove(bites, i); break end
    end
end

-- ---------------------------------------------------------------------------
-- Execute marker: a faint tick at 20% that lights up (with red HP text) once
-- the mob is in execute range. Useful for every class; pretty for all of them.
-- ---------------------------------------------------------------------------
local function execPct() return (Vantage.db.execPct or 20) / 100 end

local function updateExec(uf)
    local ex = uf.__vantageExec
    if not ex then return end
    if not (active() and Vantage.db.executeMark) then ex:Hide(); return end
    local hb = uf.healthBar
    local v = hb:GetValue() or 0
    local _, max = hb:GetMinMaxValues()
    if not max or max <= 0 then ex:Hide(); return end
    ex:Show()
    if v / max <= execPct() then
        ex:SetWidth(2)
        ex:SetVertexColor(1, 0.35, 0.30, 0.95) -- in execute range: a lit marker
    else
        ex:SetWidth(1)
        ex:SetVertexColor(1, 1, 1, 0.14)       -- waiting: barely-there
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
    local fs = uf.__vantageHP
    if not fs then return end
    local mode = Vantage.db.healthText
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
    if Vantage.db.executeMark and v / max <= execPct() then
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
    local last = uf.__vantageLastV
    uf.__vantageLastV = v
    if Vantage.db.bites and active() and last and v < last then
        local _, max = hb:GetMinMaxValues()
        spawnBite(uf, last, v, max)
    end
end

-- ---------------------------------------------------------------------------
-- Level text ("70", "71+" elite, "70r" rare, red "??" for skull/boss)
-- ---------------------------------------------------------------------------
local function updateLevel(uf)
    local fs = uf.__vantageLvl
    if not fs then return end
    local unit = unitOf(uf)
    if not (active() and Vantage.db.showLevel and unit and UnitExists(unit)) then
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
    local m = uf.__vantageMana
    if not m then return end
    local unit = unitOf(uf)
    if not (active() and Vantage.db.manaBar and unit and UnitExists(unit))
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
    uf.__vantageOrigTex = hb:GetStatusBarTexture()
    if uf.name then uf.__vantageOrigFont = { uf.name:GetFont() } end

    -- soft drop shadow behind the whole bar (radial glow tinted black)
    local sh = hb:CreateTexture(nil, "BACKGROUND", nil, -8)
    sh:SetTexture(Vantage.GLOW)
    sh:SetVertexColor(0, 0, 0, 0.6)
    sh:SetPoint("TOPLEFT", hb, -10, 7)
    sh:SetPoint("BOTTOMRIGHT", hb, 10, -7)
    uf.__vantageShadow = sh

    -- soft gold glow behind your current target's plate
    local tg = hb:CreateTexture(nil, "BACKGROUND", nil, -7)
    tg:SetTexture(Vantage.GLOW)
    tg:SetBlendMode("ADD")
    tg:SetVertexColor(1, 0.82, 0.1, 0.5)
    tg:SetPoint("TOPLEFT", hb, -14, 10)
    tg:SetPoint("BOTTOMRIGHT", hb, 14, -10)
    tg:Hide()
    uf.__vantageTargetGlow = tg

    -- dark background behind the fill
    local bg = hb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(hb)
    bg:SetColorTexture(0.04, 0.04, 0.05, 0.8)
    uf.__vantageBG = bg

    -- crisp 1px border (gold on current target)
    uf.__vantageBorder = Vantage:CreateBorder(hb)

    -- level, left-inside the bar; health text, right-inside
    local lvl = hb:CreateFontString(nil, "OVERLAY")
    lvl:SetFont(STANDARD_TEXT_FONT, 8, "OUTLINE")
    lvl:SetPoint("LEFT", hb, "LEFT", 2, 0)
    uf.__vantageLvl = lvl

    local hp = hb:CreateFontString(nil, "OVERLAY")
    hp:SetFont(STANDARD_TEXT_FONT, 8, "OUTLINE")
    hp:SetPoint("RIGHT", hb, "RIGHT", -2, 0)
    hp:SetTextColor(1, 1, 1, 0.95)
    uf.__vantageHP = hp

    -- slim mana bar riding under the health bar (child of it, so it shares
    -- visibility/scale; we add children, never touch Blizzard's own regions)
    local mana = CreateFrame("StatusBar", nil, hb)
    mana:SetPoint("TOPLEFT", hb, "BOTTOMLEFT", 0, -3)
    mana:SetPoint("TOPRIGHT", hb, "BOTTOMRIGHT", 0, -3)
    mana:SetHeight(4)
    -- flat texture, not the gradient TGA: 32px of gradient squeezed into 4px
    -- averages out to a washed-up near-white; a solid fill stays readably BLUE
    mana:SetStatusBarTexture(Vantage.WHITE)
    mana:SetStatusBarColor(0.18, 0.42, 0.92)
    local mbg = mana:CreateTexture(nil, "BACKGROUND")
    mbg:SetAllPoints(mana)
    mbg:SetColorTexture(0.04, 0.04, 0.05, 0.8)
    mana.border = Vantage:CreateBorder(mana)
    mana:Hide()
    uf.__vantageMana = mana

    -- 1px glass highlight along the bar's top edge (a quiet "lit" look)
    local glass = hb:CreateTexture(nil, "OVERLAY", nil, 1)
    glass:SetTexture(Vantage.WHITE)
    glass:SetVertexColor(1, 1, 1, 0.10)
    glass:SetPoint("TOPLEFT", hb, 0, 0)
    glass:SetPoint("TOPRIGHT", hb, 0, 0)
    glass:SetHeight(1)
    uf.__vantageGlass = glass

    -- execute tick at 20% (positioned in applySkin once the width is known)
    local ex = hb:CreateTexture(nil, "OVERLAY", nil, 1)
    ex:SetTexture(Vantage.WHITE)
    ex:SetVertexColor(1, 1, 1, 0.22)
    ex:SetWidth(1)
    ex:Hide()
    uf.__vantageExec = ex

    -- mouseover wash (shown/hidden by the hover watcher)
    local hov = hb:CreateTexture(nil, "OVERLAY", nil, 3)
    hov:SetTexture(Vantage.WHITE)
    hov:SetBlendMode("ADD")
    hov:SetAllPoints(hb)
    hov:SetVertexColor(1, 1, 1, 0.12)
    hov:Hide()
    uf.__vantageHover = hov

    -- keep text/exec/bites live as the bar moves (HookScript = taint-safe)
    hb:HookScript("OnValueChanged", function() onHealthChanged(uf) end)
    hb:HookScript("OnMinMaxChanged", function()
        uf.__vantageLastV = nil -- unit swap: don't bite across different mobs
        onHealthChanged(uf)
    end)

    -- keep class colors in place when Blizzard re-asserts reaction color
    -- when Blizzard re-asserts its own coloring, put OUR desired color back
    -- (class colors, or the group aggro scheme)
    hooksecurefunc(hb, "SetStatusBarColor", function(bar, r, g, b)
        if applying or not active() then return end
        local cr, cg, cb = desiredBarColor(uf)
        if cr and (r ~= cr or g ~= cg or b ~= cb) then
            applying = true
            bar:SetStatusBarColor(cr, cg, cb)
            applying = false
        end
    end)

    -- Blizzard's own plate cast bar double-draws under Vantage's styled one (a
    -- flat grey bar during casts). Blizzard re-Shows it on every cast, so a
    -- one-time Hide can't win — hook OnShow and keep it down while the flag
    -- says WE own cast bars on this frame. Hooks can't be removed, so the
    -- per-frame flag (set in applySkin, cleared in removeSkin) is the gate.
    local bcb = blizzCastBar(uf)
    if bcb and bcb.HookScript then
        bcb:HookScript("OnShow", function(s)
            if uf.__vantageHideCast then s:Hide() end
        end)
    end

    uf.__vantageSkinned = true
    return true
end

-- Hide Blizzard's own plate decorations while our skin is on (restored on
-- toggle). The classic-line client draws far more than retail: a border
-- around the health bar, a LEVEL text right of the bar, an elite/skull
-- classification frame, and a rounded aggro-glow outline. Blizzard's
-- CompactUnitFrame code re-Shows several of these on its own events, so a
-- one-time Hide() doesn't stick — SetAlpha(0) does (Blizzard doesn't drive
-- their alpha), and applySkin re-runs this on every plate acquisition anyway.
-- Every path is existence-guarded: paths that don't exist on this client
-- build are simply skipped.
local function setBlizzDecor(uf, shown)
    local function setA(obj, a)
        if obj and obj.SetAlpha then obj:SetAlpha(a) end
    end
    local hb = uf.healthBar
    -- The rounded gold Nameplate-Border art (level ring baked into its right
    -- end): at healthBar.border on 2.5.4-era clients, but the 2.5.5+
    -- Anniversary client moved it to UnitFrame.HealthBarsContainer.border
    -- (frameStrata HIGH, so it out-draws everything until suppressed).
    local bd = (hb and hb.border)
        or (uf.HealthBarsContainer and uf.HealthBarsContainer.border)
    if bd then
        if shown then
            if bd.Show then bd:Show() end
        else
            if bd.Hide then bd:Hide() end
        end
        setA(bd, shown and 1 or 0)
    end
    -- the health bar's stock grey background texture (ours is darker).
    -- 2.5.4-era: hb.background; the 2.5.6 Anniversary refactor renamed it
    -- bgTexture and draws it ABOVE the fill, so an unsuppressed one reads as
    -- "Blizzard's frame came back." Suppress whichever this client has.
    setA(hb and hb.background, shown and 0.85 or 0)
    setA(hb and hb.bgTexture, shown and 1 or 0)
    -- 2.5.6 moved the retail-style selection/aggro atlas art ONTO the health
    -- bar (selectedBorder/deselectedOverlay/selectionHighlight/aggroFlash);
    -- Vantage draws its own target border + aggro coloring, so keep these dark.
    setA(hb and hb.selectedBorder, shown and 1 or 0)
    setA(hb and hb.deselectedOverlay, shown and 1 or 0)
    setA(hb and hb.selectionHighlight, shown and 1 or 0)
    setA(hb and hb.aggroFlash, shown and 1 or 0)
    -- 0.25 is Blizzard's default selection alpha (2.5.4-era, on the UnitFrame)
    setA(uf.selectionHighlight, shown and 0.25 or 0)
    -- rounded gold/red threat glow around the bar (classic plates, plus the
    -- atlas-flare base/additive variants that returned with the 2.5.6 refactor)
    setA(uf.aggroHighlight, shown and 1 or 0)
    setA(uf.aggroHighlightBase, shown and 1 or 0)
    setA(uf.aggroHighlightAdditive, shown and 1 or 0)
    -- level number + skull texture right of the bar (we draw our own, inside)
    setA(uf.LevelFrame, shown and 1 or 0)
    -- elite dragon / classification art
    setA(uf.ClassificationFrame, shown and 1 or 0)
    setA(uf.classificationIndicator, shown and 1 or 0)
end

-- Border speaks in this order: your target (accent) > threat state (red =
-- aggro on you / amber = pulling / green = safely tanking in tank mode) >
-- plain black. Threat.lua feeds the state via SetThreat below.
local function updateHighlight(uf)
    if not uf.__vantageBorder then return end
    local u = unitOf(uf)
    local isTarget = u and UnitIsUnit(u, "target")
    if isTarget then
        uf.__vantageBorder:SetColor(Vantage:RGB("kick"))
    elseif uf.__vantageThreat then
        uf.__vantageBorder:SetColor(Vantage:RGB(uf.__vantageThreat))
    else
        uf.__vantageBorder:SetColor(0, 0, 0, 1)
    end
    local tg = uf.__vantageTargetGlow
    if tg then
        if isTarget and Vantage.db.targetGlow then tg:Show() else tg:Hide() end
    end
end

-- While the cue label owns the bar center (db.cueHidesText, "center" label
-- position), the plate's level/HP text yields to it — the shout stands alone.
-- Restored the moment the cue clears; applySkin re-asserts visibility so a
-- pooled frame can never come back with its text stuck hidden.
function M:CueTextSuppress(unit, suppressed)
    local uf = unit and skinned[unit]
    if not (uf and uf.__vantageSkinned) then return end
    local hide = suppressed and active() and Vantage.db.cueHidesText
        and Vantage.db.labelPos ~= "above"
    if uf.__vantageHP then uf.__vantageHP:SetShown(not hide) end
    if uf.__vantageLvl then uf.__vantageLvl:SetShown(not hide) end
end

-- Threat.lua pushes each plate's aggro state here (a palette key, or nil).
function M:SetThreat(unit, key)
    local uf = skinned[unit]
    if not (uf and uf.__vantageSkinned) then return end
    if uf.__vantageThreat ~= key then
        uf.__vantageThreat = key
        updateHighlight(uf)
    end
    -- bar color re-checks every push, not just on key change: combat
    -- engagement flips calm<->reaction without the threat key moving
    applyBarColor(uf)
end

local function applySkin(uf, unit)
    if not uf or not uf.healthBar then return end
    if unit then uf.__vantageUnit = unit end -- the event's token is the truth
    if not uf.__vantageSkinned then
        if not build(uf) then return end
    end
    uf.healthBar:SetStatusBarTexture(Vantage:BarTex()) -- persists; cheap to re-assert per add
    uf.__vantageShadow:Show()
    uf.__vantageBG:Show()
    uf.__vantageBorder:Show()
    uf.__vantageGlass:Show()
    setBlizzDecor(uf, false)

    -- custom bar height (db.barHeight >= 6; below that = Blizzard's default).
    -- The container carries the height on 2.5.5+ (the bar fills it); the bar
    -- itself does on 2.5.4-era clients. Original height remembered per pooled
    -- frame the first time we see it, for restore.
    local hbHost = uf.HealthBarsContainer or uf.healthBar
    if not uf.__vantageOrigBarH then
        local h0 = hbHost:GetHeight()
        if h0 and h0 > 0 then uf.__vantageOrigBarH = h0 end
    end
    local bh = Vantage.db.barHeight or 0
    if bh >= 6 then
        hbHost:SetHeight(bh)
    elseif uf.__vantageOrigBarH then
        hbHost:SetHeight(uf.__vantageOrigBarH)
    end

    -- fresh unit on this frame: no cross-mob bites, no stale threat border
    purgeBites(uf)
    uf.__vantageThreat = nil
    uf.__vantageLastV = uf.healthBar:GetValue()
    local w = uf.healthBar:GetWidth()
    if w and w > 0 then
        local ex = uf.__vantageExec
        ex:ClearAllPoints()
        ex:SetPoint("TOP", uf.healthBar, "TOPLEFT", w * execPct(), 0)
        ex:SetPoint("BOTTOM", uf.healthBar, "BOTTOMLEFT", w * execPct(), 0)
    end
    updateExec(uf)
    uf.__vantageHover:Hide()
    if uf.name then
        Vantage:SetFont(uf.name, Vantage.db.nameSize or 10)
        local r, g, b = classColor(unitOf(uf))
        if r then uf.name:SetTextColor(r, g, b) else uf.name:SetTextColor(1, 1, 1) end
    end
    local small = math.max(7, (Vantage.db.nameSize or 10) - 2)
    Vantage:SetFont(uf.__vantageHP, small)
    Vantage:SetFont(uf.__vantageLvl, small)
    uf.__vantageHP:Show()  -- never inherit a stale cue-suppression from a
    uf.__vantageLvl:Show() -- pooled frame (see CueTextSuppress)
    applyBarColor(uf)
    updateHealthText(uf)
    updateLevel(uf)
    updateMana(uf)
    updateHighlight(uf)

    -- suppress Blizzard's plate cast bar only where OUR cast overlay serves:
    -- enemies, with Vantage cast bars enabled. Friendlies keep Blizzard's.
    local u = unitOf(uf)
    uf.__vantageHideCast = (Vantage.db.showCastbar and u
        and UnitCanAttack("player", u)) or false
    local bcb = blizzCastBar(uf)
    if uf.__vantageHideCast and bcb then
        -- Blizzard's own suppression idiom on 2.5.5+: detach the unit, which
        -- unregisters the cast bar's events AND hides it. Blizzard re-arms it
        -- on every plate add, so this runs per applySkin. The OnShow hook in
        -- build() stays as the fallback for clients without SetUnit.
        if bcb.SetUnit then bcb:SetUnit(nil, nil, nil) end
        if bcb:IsShown() then bcb:Hide() end
    end
end

local function removeSkin(uf)
    if not uf or not uf.__vantageSkinned then return end
    uf.__vantageHideCast = false -- hand the plate cast bar back to Blizzard
    -- re-arm what applySkin detached; Blizzard's own uf.unit is the
    -- authority here (on a recycled frame our stored token is the OLD unit)
    local bcb = blizzCastBar(uf)
    local u0 = uf.unit or uf.__vantageUnit
    if bcb and bcb.SetUnit and u0 and UnitExists(u0) then
        bcb:SetUnit(u0, false, false)
    end
    local hb = uf.healthBar
    if uf.__vantageOrigTex then hb:SetStatusBarTexture(uf.__vantageOrigTex) end
    if uf.__vantageOrigBarH then
        local hbHost = uf.HealthBarsContainer or hb
        hbHost:SetHeight(uf.__vantageOrigBarH)
    end
    uf.__vantageShadow:Hide()
    uf.__vantageBG:Hide()
    uf.__vantageBorder:Hide()
    uf.__vantageTargetGlow:Hide()
    uf.__vantageGlass:Hide()
    uf.__vantageExec:Hide()
    uf.__vantageHover:Hide()
    purgeBites(uf)
    uf.__vantageThreat = nil
    uf:SetAlpha(1)
    uf.__vantageHP:SetText("")
    uf.__vantageLvl:SetText("")
    uf.__vantageMana:Hide()
    setBlizzDecor(uf, true)
    if uf.name and uf.__vantageOrigFont then uf.name:SetFont(unpack(uf.__vantageOrigFont)) end
    -- hand bar color back to the client's reaction coloring
    local u = unitOf(uf)
    if u and UnitExists(u) and UnitSelectionColor then
        local r, g, b = UnitSelectionColor(u)
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
    if not (active() and Vantage.db.focusDim and UnitExists("target")) then return 1 end
    if UnitIsUnit(unit, "target") then return 1 end
    return Vantage.db.focusAlpha or 0.5
end
M.CurrentDim = currentDim

local function applyFocusDim()
    for unit, uf in pairs(skinned) do
        if uf.__vantageSkinned then
            uf:SetAlpha(currentDim(unit))
        end
    end
    for unit, o in pairs(Vantage.plates or {}) do
        local a = currentDim(unit)
        if o.kickF and o.kickF:IsShown() then a = 1 end -- the cue never fades
        o:SetAlpha(a)
        if Vantage.Auras and Vantage.Auras.DimRow then Vantage.Auras:DimRow(unit, a) end
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

    Vantage:RegisterEvent("NAME_PLATE_UNIT_ADDED", function(_, unit)
        local plate = C_NamePlate.GetNamePlateForUnit(unit)
        if not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
        local uf = plate.UnitFrame
        if not uf then return end
        if shouldSkin(unit) then
            applySkin(uf)
            skinned[unit] = uf
            -- a plate spawning mid-fight inherits the current focus state
            uf:SetAlpha(currentDim(unit))
        elseif uf.__vantageSkinned then
            -- Blizzard recycled a frame we skinned earlier for a unit we must
            -- NOT skin (personal resource bar, or friendlies toggled off) —
            -- scrub it or the old skin bleeds onto the wrong plate.
            removeSkin(uf)
        end
    end)

    Vantage:RegisterEvent("NAME_PLATE_UNIT_REMOVED", function(_, unit)
        skinned[unit] = nil
    end)

    Vantage:RegisterEvent("PLAYER_TARGET_CHANGED", function()
        if not active() then return end
        for _, uf in pairs(skinned) do
            if uf.__vantageSkinned then updateHighlight(uf) end
        end
        applyFocusDim()
    end)

    -- mouseover wash: light up the hovered plate; a light pulse (piggybacking
    -- the shared frame's OnUpdate) retires it once the mouse moves off
    local hovered
    Vantage:RegisterEvent("UPDATE_MOUSEOVER_UNIT", function()
        if hovered then hovered.__vantageHover:Hide(); hovered = nil end
        if not active() then return end
        for unit, uf in pairs(skinned) do
            if uf.__vantageSkinned and UnitIsUnit(unit, "mouseover") then
                uf.__vantageHover:Show()
                hovered = uf
                return
            end
        end
    end)
    local hoverAccum = 0
    Vantage.frame:HookScript("OnUpdate", function(_, elapsed)
        if not hovered then return end
        hoverAccum = hoverAccum + elapsed
        if hoverAccum < 0.15 then return end
        hoverAccum = 0
        local unit = hovered.unit
        if not (unit and UnitExists("mouseover") and UnitIsUnit(unit, "mouseover")) then
            hovered.__vantageHover:Hide()
            hovered = nil
        end
    end)

    -- keep the mana bar live
    local function powerEvent(_, unit)
        local uf = unit and skinned[unit]
        if uf then updateMana(uf) end
    end
    Vantage:RegisterEvent("UNIT_POWER_UPDATE", powerEvent)
    Vantage:RegisterEvent("UNIT_MAXPOWER", powerEvent)
    Vantage:RegisterEvent("UNIT_DISPLAYPOWER", powerEvent)
end

Vantage.Skin = M
