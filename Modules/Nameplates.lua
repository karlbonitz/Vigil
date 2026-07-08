-- Vantage/Modules/Nameplates.lua
--
-- Tracks enemy nameplates and owns the per-plate "overlay" (our own frames that
-- ride on top of Blizzard's plate). We NEVER reparent, move, or touch the secure
-- nameplate frame itself — our overlay is parented to UIParent and merely
-- anchored to the plate, so it follows the plate's movement with zero taint risk.
--
-- The overlay frame stays shown while its plate exists (so the threat strip can
-- render between casts); the cast-bar elements show/hide per cast.
local addonName, Vantage = ...
local M = Vantage:NewModule("Nameplates")

Vantage.plates     = {}  -- unit token ("nameplate3") -> overlay
Vantage.guidToUnit = {}  -- GUID -> unit token (so CLEU can find the right plate)

local pool = {}        -- recycled overlays

local BAR_W, BAR_H = 124, 12
local POP_TIME   = 0.15  -- seconds for the kick label's pop-in shrink
local FLASH_TIME = 0.7   -- seconds the outcome verdict lingers (fades at the end)
local FLASH_FADE = 0.25  -- fade-out portion of FLASH_TIME

-- ---------------------------------------------------------------------------
-- Overlay construction
-- ---------------------------------------------------------------------------
local castOnUpdate = function(cb)
    local o = cb.overlay
    local remaining = cb.endTime - GetTime()
    if cb.channeling then
        cb:SetValue(remaining > 0 and (remaining / cb.duration) or 0)
    else
        local filled = cb.duration > 0 and (1 - remaining / cb.duration) or 1
        cb:SetValue(filled < 1 and filled or 1)
    end
    cb.spark:SetPoint("CENTER", cb, "LEFT", cb:GetValue() * cb:GetWidth(), 0)
    -- 0.05 floor: never render a "0.0" frame (pushback can hover there)
    if Vantage.db.showCastTime and remaining >= 0.05 and not o.padlock:IsShown() then
        o.timeText:SetFormattedText("%.1f", remaining)
    else
        o.timeText:SetText("")
    end
    if remaining <= 0 then
        o:Reset()
    end
end

local kickPop = function(kf, elapsed)
    kf.t = kf.t + elapsed
    local p = kf.t / POP_TIME
    if p >= 1 then
        kf:SetScale(1)
        kf:SetScript("OnUpdate", nil)
    else
        kf:SetScale(1.4 - 0.4 * p)
    end
end

-- the spell icon lands with a quick settle (1.3 -> 1 over 0.12s)
local iconPop = function(fr, elapsed)
    fr.t = fr.t + elapsed
    local p = fr.t / 0.12
    if p >= 1 then
        fr:SetScale(1)
        fr:SetScript("OnUpdate", nil)
    else
        fr:SetScale(1.3 - 0.3 * p)
    end
end

-- The call-to-action defaults to CENTERED ON THE HEALTH BAR — the visual
-- center of the plate, where nothing else lives (aura row is above, mana/cast
-- bar are below). Covering the HP text for the moment you're deciding to kick
-- is the point: the label IS the information right then. `labelPos = "above"`
-- moves it to hover above the cast bar instead (also the fallback when the
-- plate has no reachable health bar).
local function anchorKick(o, hb)
    local kf = o.kickF
    kf:ClearAllPoints()
    if hb and Vantage.db.labelPos ~= "above" then
        kf:SetPoint("CENTER", hb, "CENTER", 0, 0)
    else
        kf:SetPoint("BOTTOM", o, "TOP", 0, 12)
    end
end

-- fade the verdict out over the flash's final stretch, then clear the bar
local flashOnUpdate = function(cb, elapsed)
    local o = cb.overlay
    o.flashT = o.flashT + elapsed
    if o.flashT >= FLASH_TIME then
        o:Reset()
    elseif o.flashT > FLASH_TIME - FLASH_FADE then
        local a = (FLASH_TIME - o.flashT) / FLASH_FADE
        cb:SetAlpha(a)
        o.iconF:SetAlpha(a)
    end
end

-- WASTED rides the big label frame and leaves the bar alone: the locked cast
-- is still in flight after your kick bounced off it, so the bar (and its
-- padlock) must keep showing. Pops in like the cue, self-hides after 0.9s.
local wastedPop = function(kf, elapsed)
    kf.t = kf.t + elapsed
    local p = kf.t / POP_TIME
    kf:SetScale(p >= 1 and 1 or (1.4 - 0.4 * p))
    if kf.t >= 0.9 then
        -- route through HideKick so everything the label borrowed (alpha,
        -- suppressed level/HP text) is handed back
        kf.overlay:HideKick()
    end
end

local function CreateOverlay()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(BAR_W, BAR_H)
    f:SetFrameStrata("HIGH")
    f:Hide()

    local base = f:GetFrameLevel()

    -- spell icon in its own bordered square, hanging off the bar's left edge.
    -- Sized to match the bar + its 1px border exactly (BAR_H + 2).
    local iconF = CreateFrame("Frame", nil, f)
    iconF:SetFrameLevel(base + 3)
    iconF:SetSize(BAR_H + 2, BAR_H + 2)
    iconF:SetPoint("RIGHT", f, "LEFT", -3, 0)
    local iconBG = iconF:CreateTexture(nil, "BACKGROUND")
    iconBG:SetAllPoints(iconF)
    iconBG:SetColorTexture(0, 0, 0, 0.95)
    local icon = iconF:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    iconF:Hide()
    f.iconF, f.icon = iconF, icon

    -- soft radial glow haloing the whole cast row (the "INTERRUPT" pulse).
    -- A Frame (not a Texture) so it can own an AnimationGroup.
    local glow = CreateFrame("Frame", nil, f)
    glow:SetFrameLevel(base + 1)
    glow:SetPoint("TOPLEFT", iconF, "TOPLEFT", -12, 10)
    glow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 12, -10)
    local gtex = glow:CreateTexture(nil, "BACKGROUND")
    gtex:SetAllPoints(glow)
    gtex:SetTexture(Vantage.GLOW)
    gtex:SetBlendMode("ADD")
    gtex:SetVertexColor(Vantage:RGB("kick"))
    glow:Hide()
    local ag = glow:CreateAnimationGroup()
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1.0); a:SetToAlpha(0.25); a:SetDuration(0.5); a:SetSmoothing("IN_OUT")
    ag:SetLooping("BOUNCE")
    f.glow, f.glowAnim, f.glowTex = glow, ag, gtex

    -- cast bar
    local cb = CreateFrame("StatusBar", nil, f)
    cb:SetAllPoints(f)
    cb:SetFrameLevel(base + 3)
    cb:SetStatusBarTexture(Vantage.BAR)
    cb:SetMinMaxValues(0, 1)
    cb.overlay = f
    cb.onUpdate = castOnUpdate
    f.castbar = cb

    local bg = cb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(cb)
    bg:SetColorTexture(0.04, 0.04, 0.05, 0.85)

    cb.border = Vantage:CreateBorder(cb)

    local spark = cb:CreateTexture(nil, "OVERLAY")
    spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    spark:SetBlendMode("ADD")
    spark:SetSize(12, 22)
    cb.spark = spark

    -- 1px glass highlight along the top, matching the health-bar skin
    local glass = cb:CreateTexture(nil, "OVERLAY")
    glass:SetTexture(Vantage.WHITE)
    glass:SetVertexColor(1, 1, 1, 0.10)
    glass:SetPoint("TOPLEFT", cb, 0, 0)
    glass:SetPoint("TOPRIGHT", cb, 0, 0)
    glass:SetHeight(1)

    -- cast time remaining, right-aligned inside the bar
    local timeText = cb:CreateFontString(nil, "OVERLAY")
    timeText:SetFont(STANDARD_TEXT_FONT, 8, "OUTLINE")
    timeText:SetPoint("RIGHT", cb, "RIGHT", -3, 0)
    timeText:SetTextColor(0.95, 0.95, 0.95)
    f.timeText = timeText

    -- spell name, left-aligned, never overlapping the time text
    local name = cb:CreateFontString(nil, "OVERLAY")
    name:SetFont(STANDARD_TEXT_FONT, 8, "OUTLINE")
    name:SetPoint("LEFT", cb, "LEFT", 3, 0)
    name:SetPoint("RIGHT", timeText, "LEFT", -3, 0)
    name:SetJustifyH("LEFT")
    if name.SetWordWrap then name:SetWordWrap(false) end
    f.name = name

    -- big "INTERRUPT / FEAR / STUN" call-to-action, on its own frame so it can
    -- pop in (scale-shrinks to rest around its center anchor). Re-anchored to
    -- each plate's health bar in OnAdded via anchorKick().
    local kickF = CreateFrame("Frame", nil, f)
    kickF:SetFrameLevel(base + 5)
    kickF:SetSize(2, 2)
    kickF:SetPoint("BOTTOM", f, "TOP", 0, 12)
    local kick = kickF:CreateFontString(nil, "OVERLAY")
    kick:SetFont(STANDARD_TEXT_FONT, 15, "THICKOUTLINE")
    kick:SetPoint("CENTER", kickF, "CENTER", 0, 0)
    kick:SetTextColor(Vantage:RGB("kick"))
    kickF:Hide()
    kickF.overlay = f -- wastedPop's route back to HideKick
    f.kickF, f.kickText = kickF, kick

    -- uninterruptible padlock, right side of the bar (replaces the time text)
    local lock = cb:CreateTexture(nil, "OVERLAY")
    lock:SetTexture("Interface\\Buttons\\LockButton-Locked-Up")
    lock:SetTexCoord(0.2, 0.8, 0.2, 0.8)
    lock:SetSize(12, 12)
    lock:SetPoint("RIGHT", cb, "RIGHT", -2, 0)
    lock:Hide()
    f.padlock = lock

    -- thin threat strip along the top edge (managed by Modules/Threat.lua;
    -- visible whenever the overlay exists, not only during casts).
    -- NOTE: Reset() at the bottom of this constructor is load-bearing — a
    -- fresh overlay's cast-bar children are otherwise SHOWN from creation,
    -- and since the overlay frame stays visible between casts (v0.3.0), the
    -- empty bar rendered as a ghost grey bar under every new plate until
    -- the frame was recycled. Pooled frames were clean (Release resets).
    local strip = f:CreateTexture(nil, "OVERLAY")
    strip:SetTexture(Vantage.BAR)
    strip:SetHeight(3)
    strip:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 1)
    strip:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 1)
    strip:Hide()
    f.threatStrip = strip

    -- ---- overlay methods ----
    function f:ShowKick(label)
        if self.kickIsMate then self:HideKick() end -- your shout displaces the hint
        self.kickText:SetText(label or "INTERRUPT")
        self.kickText:SetTextColor(Vantage:RGB("kick")) -- may be red from a WASTED flash
        self.glowTex:SetVertexColor(Vantage:RGB("kick")) -- accent-aware, per show
        self:SetAlpha(1) -- the cue punches through the focus fade, always
        if Vantage.Skin and Vantage.Skin.CueTextSuppress then
            Vantage.Skin:CueTextSuppress(self.unit, true) -- the shout gets the bar to itself
        end
        local kf = self.kickF
        if not kf:IsShown() then
            kf.t = 0
            kf:SetScale(1.4)
            kf:Show()
            kf:SetScript("OnUpdate", kickPop)
            -- sound rides the pop-in: once per cue, not once per re-evaluation
            -- (cooldown updates re-run Evaluate many times during one cast)
            Vantage:PlayInterruptSound()
        end
        self.glow:Show()
        self.glowAnim:Play()
    end

    -- Quiet variant of ShowKick for the party kick watch: the center slot
    -- names a groupmate whose interrupt should be ready. Smaller, class-
    -- colored, no glow/sound/pop — it's their moment, not your shout. Never
    -- displaces a real shout or a WASTED verdict already holding the slot.
    function f:ShowMate(text, r, g, b)
        if self.kickF:IsShown() and not self.kickIsMate then return end
        self.kickIsMate = true
        self.kickText:SetText(text)
        self.kickText:SetTextColor(r or 1, g or 1, b or 1)
        self.kickF:SetScale(0.85)
        self.kickF:Show()
        if Vantage.Skin and Vantage.Skin.CueTextSuppress then
            Vantage.Skin:CueTextSuppress(self.unit, true) -- shares the center slot
        end
    end

    function f:HideKick()
        self.kickIsMate = nil
        self.kickF:Hide()
        self.kickF:SetScript("OnUpdate", nil)
        self.kickF:SetScale(1)
        self.glow:Hide()
        self.glowAnim:Stop()
        if self.unit and Vantage.Skin and Vantage.Skin.CueTextSuppress then
            Vantage.Skin:CueTextSuppress(self.unit, false) -- level/HP text returns
        end
        -- cue gone: fall back into the focus fade (if one is in effect)
        if self.unit and Vantage.Skin and Vantage.Skin.CurrentDim then
            self:SetAlpha(Vantage.Skin.CurrentDim(self.unit))
        end
    end

    -- Brief verdict as a flagged cast resolves: teal KICKED (someone stopped
    -- it), red MISSED (it completed while your stop sat ready), WASTED in
    -- padlock red (you spent a kick on a do-not-kick cast). Visual only, no
    -- sound; the label rides the countdown's right-aligned slot.
    function f:FlashOutcome(color, label)
        if not Vantage.db.outcomeFlash then self:Reset(); return end
        if self.flashing or not self.castbar:IsShown() then return end
        local cb = self.castbar
        self.flashing = color
        self.active = nil              -- decision resolved; a new cast may take over
        self.flashT = 0
        self:HideKick()
        self.padlock:Hide()
        cb:SetValue(1)
        cb:SetStatusBarColor(Vantage:RGB(color))
        self.timeText:SetText(label)
        self.timeText:SetTextColor(1, 1, 1)
        cb:SetScript("OnUpdate", flashOnUpdate)
    end

    -- see wastedPop: label-only verdict, the (still-casting) bar stays intact
    function f:FlashWasted()
        if not Vantage.db.outcomeFlash then return end
        local kf = self.kickF
        self.kickText:SetText("WASTED")
        self.kickText:SetTextColor(Vantage:RGB("locked"))
        kf.t = 0
        kf:SetScale(1.4)
        kf:Show()
        kf:SetScript("OnUpdate", wastedPop)
        if Vantage.Skin and Vantage.Skin.CueTextSuppress then
            Vantage.Skin:CueTextSuppress(self.unit, true) -- WASTED sits center-bar too
        end
    end

    function f:Reset()
        local cb = self.castbar
        cb:SetScript("OnUpdate", nil)
        cb:Hide()
        cb:SetAlpha(1)
        self.iconF:Hide()
        self.iconF:SetAlpha(1)
        self.iconF:SetScale(1)
        self.iconF:SetScript("OnUpdate", nil)
        self:HideKick()
        self.padlock:Hide()
        self.timeText:SetText("")
        self.timeText:SetTextColor(0.95, 0.95, 0.95)
        self.flashing = nil
        self.active = nil
    end

    function f:ShowCast(spellName, iconTex, duration, channeling)
        local cb = self.castbar
        cb.duration   = duration or 2
        cb.endTime    = GetTime() + cb.duration
        cb.channeling = channeling
        cb:SetValue(channeling and 1 or 0)
        cb:SetAlpha(1)
        self.iconF:SetAlpha(1)
        self.flashing = nil
        self.timeText:SetTextColor(0.95, 0.95, 0.95)
        self.icon:SetTexture(iconTex or Vantage.QUESTION_ICON)
        self.name:SetText(spellName or "")
        self.timeText:SetText("")
        cb:SetStatusBarColor(Vantage:RGB(channeling and "channel" or "cast"))
        self.padlock:Hide()
        self:HideKick()
        local ic = self.iconF
        ic:Show()
        ic.t = 0
        ic:SetScale(1.3)
        ic:SetScript("OnUpdate", iconPop)
        cb:Show()
        cb:SetScript("OnUpdate", cb.onUpdate)
    end

    f:Reset() -- see the threat-strip note above: never ship a live cast bar
    return f
end

-- Style knobs that can change at runtime (cast bar height, bar fill, fonts).
-- Runs per Acquire and live via M:ApplyStyle when an option moves.
local function styleOverlay(o)
    local h = Vantage.db.castBarHeight or BAR_H
    o:SetHeight(h)
    o.iconF:SetSize(h + 2, h + 2)
    o.castbar:SetStatusBarTexture(Vantage:BarTex())
    Vantage:SetFont(o.timeText, 8)
    Vantage:SetFont(o.name, 8)
    Vantage:SetFont(o.kickText, 15, "THICKOUTLINE") -- the shout stays THICK by design
end

function M:ApplyStyle()
    for _, o in pairs(Vantage.plates or {}) do styleOverlay(o) end
end

local function Acquire()
    local o = table.remove(pool) or CreateOverlay()
    o:SetScale(Vantage.db.scale or 1)
    styleOverlay(o)
    return o
end

local function Release(o)
    o:Reset()
    o.threatStrip:Hide()
    o:Hide()
    o:SetAlpha(1)
    o.unit = nil
    o:ClearAllPoints()
    anchorKick(o, nil) -- never leave the label anchored to a recycled plate's bar
    pool[#pool + 1] = o
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
function M:OnEnable()
    if not C_NamePlate then
        Vantage:Print("This client has no nameplate API (C_NamePlate) — Vantage can't run here.")
        return
    end
    Vantage:RegisterEvent("NAME_PLATE_UNIT_ADDED",   function(_, unit) M:OnAdded(unit) end)
    Vantage:RegisterEvent("NAME_PLATE_UNIT_REMOVED", function(_, unit) M:OnRemoved(unit) end)
end

function M:OnAdded(unit)
    if not Vantage.db.enabled then return end

    -- a re-ADD for a token we still hold means we missed the REMOVED event —
    -- release the old overlay or it leaks, haunting the screen with a stale
    -- bar anchored to a plate it no longer owns
    local stale = Vantage.plates[unit]
    if stale then
        Vantage.plates[unit] = nil
        if stale.guid then Vantage.guidToUnit[stale.guid] = nil end
        Release(stale)
    end

    if not UnitCanAttack("player", unit) or UnitIsDead(unit) then return end

    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then return end

    local o = Acquire()
    o:ClearAllPoints()
    o.plate = plate

    -- anchor to the health bar, not the plate: the anniversary template insets
    -- the bar asymmetrically in the plate rect (4px left / 21px right), so the
    -- plate's center sits ~9px right of the bar's center — everything hung off
    -- the plate drifts right of the bar it's supposed to underline
    local hb = plate.UnitFrame and plate.UnitFrame.healthBar
    if hb then
        o:SetPoint("TOP", hb, "BOTTOM", 0, -6) -- same height the plate anchor gave
    else
        o:SetPoint("TOP", plate, "BOTTOM", 0, -2)
    end

    -- match the health bar's width so the cast bar aligns edge-to-edge with it
    -- (the icon hangs off the left, Plater-style)
    local w = hb and hb:GetWidth()
    o:SetWidth((w and w > 60) and w or BAR_W)
    anchorKick(o, hb)

    o:Show()
    o.unit = unit
    -- spawning mid-fight inherits the current focus fade
    if Vantage.Skin and Vantage.Skin.CurrentDim then
        o:SetAlpha(Vantage.Skin.CurrentDim(unit))
    end
    Vantage.plates[unit] = o

    local guid = UnitGUID(unit)
    if guid then Vantage.guidToUnit[guid] = unit end
    o.guid = guid

    -- catch a cast already in progress when the plate appears
    if Vantage.CastWatch then Vantage.CastWatch:Refresh(unit) end
    if Vantage.Auras then Vantage.Auras:Refresh(unit) end
end

-- Re-apply the label-position setting to every live plate (options dropdown).
function M:ReanchorKicks()
    for _, o in pairs(Vantage.plates) do
        local hb = o.plate and o.plate.UnitFrame and o.plate.UnitFrame.healthBar
        anchorKick(o, hb)
    end
end

function M:OnRemoved(unit)
    local o = Vantage.plates[unit]
    if not o then return end
    if o.guid then Vantage.guidToUnit[o.guid] = nil end
    if Vantage.Auras then Vantage.Auras:Remove(unit) end
    o.plate = nil
    Vantage.plates[unit] = nil
    Release(o)
end

Vantage.Nameplates = M
