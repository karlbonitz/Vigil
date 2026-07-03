-- Vigil/Modules/Options.lua
--
-- A native options panel registered in the game's AddOns settings, opened with
-- /vigil. No external libraries. It reads/writes the exact same VigilDB fields
-- the slash commands use, and the modules read those live, so every change
-- applies immediately — sliders restyle plates as you drag.
--
-- Blizzard changed the options API (old InterfaceOptions -> new Settings); we
-- feature-detect and support whichever the client has.
local addonName, Vigil = ...
local M = Vigil:NewModule("Options")

local PAD  = 16    -- left margin
local COL2 = 300   -- second column x

-- refresh hooks shared by several widgets
local function refreshSkin()
    if Vigil.Skin then Vigil.Skin:RefreshAll() end
end
local function refreshAuras()
    if Vigil.Auras then Vigil.Auras:ApplyStyle(); Vigil.Auras:RefreshAll() end
end
local function applyScale()
    for _, o in pairs(Vigil.plates or {}) do o:SetScale(Vigil.db.scale or 1) end
end

local nWidgets = 0
local function wname()
    nWidgets = nWidgets + 1
    return "VigilOpt" .. nWidgets
end

function M:OnEnable()
    local panel = CreateFrame("Frame")
    panel.name = "Vigil"

    -- everything lives on a scrollable content frame — the option set outgrew
    -- the legacy InterfaceOptions canvas, and scrolling ends that arms race
    local scroll = CreateFrame("ScrollFrame", wname(), panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -27, 4)
    local content = CreateFrame("Frame")
    content:SetSize(590, 740)
    scroll:SetScrollChild(content)

    local checks, sliders = {}, {}
    local healthTextDD, labelDD, accentDD -- forward refs for refresh()

    -- ---- widget factories -------------------------------------------------
    local function header(text, y)
        local h = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        h:SetPoint("TOPLEFT", PAD, y)
        h:SetText(text)
        local line = content:CreateTexture(nil, "ARTWORK")
        line:SetTexture(Vigil.WHITE)
        line:SetVertexColor(1, 0.82, 0.1, 0.25)
        line:SetHeight(1)
        line:SetPoint("TOPLEFT", PAD, y - 15)
        line:SetPoint("TOPRIGHT", -PAD, y - 15)
        return y - 22
    end

    local function check(x, y, key, label, tip, onChange)
        local cb = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", x, y)
        cb:SetSize(22, 22)
        local text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        text:SetPoint("LEFT", cb, "RIGHT", 3, 0)
        text:SetText(label)
        cb.key = key
        cb:SetScript("OnClick", function(self)
            Vigil.db[key] = self:GetChecked() and true or false
            if onChange then onChange() end
        end)
        if tip then
            cb:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(label, 1, 1, 1)
                GameTooltip:AddLine(tip, nil, nil, nil, true)
                GameTooltip:Show()
            end)
            cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        checks[#checks + 1] = cb
        return cb
    end

    local function slider(x, y, key, label, minV, maxV, step, fmt, onChange)
        local name = wname()
        local s = CreateFrame("Slider", name, content, "OptionsSliderTemplate")
        s:SetPoint("TOPLEFT", x + 6, y - 12)
        s:SetWidth(230)
        s:SetMinMaxValues(minV, maxV)
        s:SetValueStep(step)
        if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
        _G[name .. "Low"]:SetText(fmt:format(minV))
        _G[name .. "High"]:SetText(fmt:format(maxV))
        s.key = key
        s.updateText = function(v) _G[name .. "Text"]:SetText(label .. ": " .. fmt:format(v)) end
        s:SetScript("OnValueChanged", function(_, v)
            v = math.floor(v / step + 0.5) * step
            Vigil.db[key] = v
            s.updateText(v)
            if onChange then onChange() end
        end)
        sliders[#sliders + 1] = s
        return s
    end

    -- ---- title row ---------------------------------------------------------
    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", PAD, -16)
    title:SetText("Vigil")

    local sub = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetText("Interrupt-smart nameplates  ·  v" .. Vigil.version)

    local reset = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    reset:SetSize(140, 22)
    reset:SetPoint("TOPRIGHT", -PAD, -16)
    reset:SetText("Reset to defaults")

    local export = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    export:SetSize(110, 22)
    export:SetPoint("RIGHT", reset, "LEFT", -6, 0)
    export:SetText("Export data…")
    export:SetScript("OnClick", function()
        if Vigil.ParseExport then Vigil.ParseExport:Toggle() end
    end)

    -- ---- layout ------------------------------------------------------------
    local y = -60

    y = header("Nameplates", y)
    check(PAD, y, "skin", "Custom nameplate skin",
        "Smooth gradient bar, dark background, crisp border, sharper name font. Mobs keep red/yellow reaction colors.", refreshSkin)
    check(COL2, y, "classColors", "Class colors on players",
        "Players' health bars (and names) use their class color — enemies and friendlies alike.", refreshSkin)
    y = y - 24
    check(PAD, y, "targetGlow", "Glow + gold outline on target",
        "Your current target's plate gets a gold border and a soft glow so you never lose it.", refreshSkin)
    check(COL2, y, "friendly", "Skin friendly plates",
        "Apply the skin to friendly nameplates too (only when Blizzard is showing them), so the whole screen matches.", refreshSkin)
    y = y - 24
    check(PAD, y, "showLevel", "Level on plates",
        "Difficulty-colored level inside the bar's left edge. \"+\" = elite, \"r\" = rare, red ?? = skull/boss.", refreshSkin)
    check(COL2, y, "manaBar", "Mana bar on casters",
        "Slim blue bar under the health bar, shown only for units that actually use mana.", refreshSkin)
    y = y - 24
    check(PAD, y, "bites", "Damage flashes",
        "A bright sliver marks health the mob just lost, then fades — incoming damage reads at a glance.")
    check(COL2, y, "focusDim", "Fade other plates when targeting",
        "While you have a target, everything else — bars, cast bars, DoT rows — fades to the opacity set below, so the selected enemy is unmistakable. A live INTERRUPT cue never fades.", refreshSkin)
    y = y - 24
    check(PAD, y, "executeMark", "Execute mark at 20%",
        "A quiet tick on the health bar that lights up red (with the HP text) once the mob is in execute range.", refreshSkin)

    local accLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    accLabel:SetPoint("TOPLEFT", COL2 + 4, y - 5)
    accLabel:SetText("Accent")
    local ACC_CHOICES = {
        { "gold",   "Gold" },
        { "teal",   "Teal" },
        { "violet", "Violet" },
        { "ice",    "Ice" },
    }
    local function accText(v)
        for _, c in ipairs(ACC_CHOICES) do if c[1] == v then return c[2] end end
        return ACC_CHOICES[1][2]
    end
    accentDD = CreateFrame("Frame", wname(), content, "UIDropDownMenuTemplate")
    accentDD:SetPoint("LEFT", accLabel, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(accentDD, 90)
    UIDropDownMenu_Initialize(accentDD, function()
        for _, c in ipairs(ACC_CHOICES) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = c[2]
            info.checked = (Vigil.db.accent == c[1])
            info.func = function()
                Vigil.db.accent = c[1]
                UIDropDownMenu_SetText(accentDD, c[2])
                refreshSkin() -- target outline re-tints; glow/label follow on next cue
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    y = y - 26

    slider(PAD, y, "focusAlpha", "Non-target fade", 0.2, 0.9, 0.05, "%.2f", refreshSkin)
    y = y - 44

    local ddLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    ddLabel:SetPoint("TOPLEFT", PAD + 4, y - 5)
    ddLabel:SetText("Health text")
    local HT_CHOICES = {
        { "none",    "None" },
        { "percent", "Percent" },
        { "health",  "Health" },
        { "both",    "Health + %" },
    }
    local function htLabel(v)
        for _, c in ipairs(HT_CHOICES) do if c[1] == v then return c[2] end end
        return HT_CHOICES[1][2]
    end
    healthTextDD = CreateFrame("Frame", wname(), content, "UIDropDownMenuTemplate")
    healthTextDD:SetPoint("LEFT", ddLabel, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(healthTextDD, 100)
    UIDropDownMenu_Initialize(healthTextDD, function()
        for _, c in ipairs(HT_CHOICES) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = c[2]
            info.checked = (Vigil.db.healthText == c[1])
            info.func = function()
                Vigil.db.healthText = c[1]
                UIDropDownMenu_SetText(healthTextDD, c[2])
                refreshSkin()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    slider(COL2, y, "nameSize", "Name font size", 8, 14, 1, "%d", refreshSkin)
    y = y - 44

    y = header("Cast bars & interrupts", y)
    check(PAD, y, "showCastbar", "Enemy cast bars",
        "Vigil's styled cast bar under each enemy plate. Replaces Blizzard's plate cast bar (which comes back if you turn this off).", refreshSkin)
    check(COL2, y, "showCastTime", "Cast time remaining",
        "Seconds left on the cast, shown at the right end of the bar.")
    y = y - 24
    check(PAD, y, "interruptCue", "Interrupt cue (glow + label)",
        "The hero feature: gold halo + INTERRUPT/FEAR/STUN label when a kickable cast appears and your stop is ready.")
    check(COL2, y, "sound", "Alert sound")
    y = y - 24
    check(PAD, y, "showPadlock", "Padlock on uninterruptible",
        "Red bar + lock icon: hold your kick, this cast can't be stopped.")
    check(COL2, y, "cueUnknown", "Cue unknown casts",
        "Also treat casts Vigil has no intel on as kickable. Handy while questing; may cause false calls.")
    y = y - 24
    check(PAD, y, "pvp", "PvP: cue enemy player casts",
        "Against enemy players no database is needed — the cue fires whenever your interrupt (hard or soft) is ready.")
    check(COL2, y, "parse", "Log decisions (Vigil Parse)",
        "Records every cast decision + outcome: interrupts landed, casts let through while your kick was ready, reaction time. /vigil parse for a summary, /vigil export to copy the data out.")
    y = y - 24
    check(PAD, y, "rangeCheck", "Range-aware cue",
        "Only shout when the target is actually within your stop's range. Ready-but-too-far casts stay gold without the popup, and the cue fires the moment you close in.")
    check(COL2, y, "outcomeFlash", "Flash the outcome",
        "As a flagged cast ends, the bar flashes the verdict: teal KICKED, red MISSED (it completed while your stop was ready), or WASTED (you kicked an unkickable cast).")
    y = y - 28

    y = header("Your auras", y)
    check(PAD, y, "auras", "My DoT/debuff timers",
        "Only auras YOU applied, as icons above each enemy plate with live countdowns.", refreshAuras)
    check(COL2, y, "auraSwipe", "Cooldown swipe",
        "Radial sweep that drains as the aura runs out.", refreshAuras)
    y = y - 24
    check(PAD, y, "auraDispel", "Color border by dispel type",
        "Magic blue, curse purple, disease brown, poison green.", refreshAuras)
    y = y - 24
    slider(PAD, y, "auraSize", "Icon size", 12, 30, 1, "%d", refreshAuras)
    slider(COL2, y, "auraMax", "Max icons", 1, 8, 1, "%d", refreshAuras)
    y = y - 42

    y = header("Threat & general", y)
    check(PAD, y, "threat", "Threat tint",
        "Aggro state on the plate: colored strip + border — red when a mob is on you or you're about to pull (tank mode: green = safely tanking, red = losing it).")
    check(COL2, y, "tankMode", "Tank mode (invert colors)",
        "Green = securely tanking, red = you lost the mob.")
    y = y - 24
    check(PAD, y, "enabled", "Enable Vigil")
    check(COL2, y, "debug", "Debug messages",
        "Prints the per-cast decision (cast -> tier) to chat.")
    y = y - 24
    slider(PAD, y, "scale", "Overlay scale", 0.7, 1.5, 0.05, "%.2f", applyScale)

    -- cue label position, sharing the slider's row (keeps the panel short)
    local lpLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    lpLabel:SetPoint("TOPLEFT", COL2 + 4, y - 5)
    lpLabel:SetText("Cue label")
    local LP_CHOICES = {
        { "center", "Plate center" },
        { "above",  "Above cast bar" },
    }
    local function lpText(v)
        for _, c in ipairs(LP_CHOICES) do if c[1] == v then return c[2] end end
        return LP_CHOICES[1][2]
    end
    labelDD = CreateFrame("Frame", wname(), content, "UIDropDownMenuTemplate")
    labelDD:SetPoint("LEFT", lpLabel, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(labelDD, 110)
    UIDropDownMenu_Initialize(labelDD, function()
        for _, c in ipairs(LP_CHOICES) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = c[2]
            info.checked = (Vigil.db.labelPos == c[1])
            info.func = function()
                Vigil.db.labelPos = c[1]
                UIDropDownMenu_SetText(labelDD, c[2])
                if Vigil.Nameplates then Vigil.Nameplates:ReanchorKicks() end
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    -- ---- refresh / reset ----------------------------------------------------
    local function refresh()
        for _, cb in ipairs(checks) do
            cb:SetChecked(Vigil.db[cb.key])
        end
        for _, s in ipairs(sliders) do
            local v = Vigil.db[s.key] or select(1, s:GetMinMaxValues())
            s:SetValue(v)
            s.updateText(v)
        end
        UIDropDownMenu_SetText(healthTextDD, htLabel(Vigil.db.healthText))
        UIDropDownMenu_SetText(labelDD, lpText(Vigil.db.labelPos))
        UIDropDownMenu_SetText(accentDD, accText(Vigil.db.accent))
    end

    reset:SetScript("OnClick", function()
        for k, v in pairs(Vigil.defaults) do Vigil.db[k] = v end
        refresh()
        refreshSkin()
        refreshAuras()
        applyScale()
        if Vigil.Nameplates then Vigil.Nameplates:ReanchorKicks() end
        Vigil:Print("Settings reset to defaults.")
    end)

    panel:SetScript("OnShow", refresh)
    panel.refresh = refresh    -- old InterfaceOptions calls panel.refresh if present
    M.panel = panel

    -- Register with whichever options API this client has.
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local cat = Settings.RegisterCanvasLayoutCategory(panel, "Vigil")
        cat.ID = "Vigil"
        Settings.RegisterAddOnCategory(cat)
        M.category = cat
        function Vigil:OpenOptions() Settings.OpenToCategory(cat.ID) end
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
        function Vigil:OpenOptions()
            -- called twice: long-standing Blizzard quirk where the first call
            -- only scrolls to the category and the second actually opens it.
            InterfaceOptionsFrame_OpenToCategory(panel)
            InterfaceOptionsFrame_OpenToCategory(panel)
        end
    else
        function Vigil:OpenOptions() Vigil:ShowHelp() end
    end

    refresh()
end

Vigil.Options = M
