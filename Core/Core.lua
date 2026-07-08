-- Vantage/Core/Core.lua
-- The spine: a tiny event bus, a module registry, SavedVariables, the sound
-- helper, the slash command, and login bootstrapping. No external libraries.
local addonName, Vantage = ...

-- ===========================================================================
-- Event bus  -  Vantage:RegisterEvent("EVENT", function(event, ...) end)
-- Multiple modules can listen to the same event; we only register it once.
-- ===========================================================================
local frame = CreateFrame("Frame")
Vantage.frame = frame
local handlers = {}

function Vantage:RegisterEvent(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        frame:RegisterEvent(event)
    end
    table.insert(handlers[event], fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        list[i](event, ...)
    end
end)

-- ===========================================================================
-- Module registry  -  local M = Vantage:NewModule("Name"); function M:OnEnable() end
-- OnEnable() runs once, after the DB is ready, on PLAYER_LOGIN.
-- ===========================================================================
Vantage.modules = {}

function Vantage:NewModule(name)
    local m = { moduleName = name }
    self.modules[name] = m
    return m
end

-- ===========================================================================
-- SavedVariables (rolled by hand; AceDB is a drop-in upgrade later)
-- ===========================================================================
local defaults = {
    enabled      = true,   -- master switch
    interruptCue = true,   -- the hero: glow + sound when a kick lands
    showCastbar  = true,   -- draw enemy cast bars on plates
    showCastTime = true,   -- seconds-remaining text on the cast bar
    showPadlock  = true,   -- mark uninterruptible casts
    sound        = true,   -- play a sound on a kickable opportunity
    cueUnknown   = false,  -- also cue casts we have no intel on (off = no false KICKs)
    learn        = true,   -- learn interruptibility from live combat (fills gaps the curated pack misses)
    pvp          = true,   -- cue enemy PLAYER casts vs your ready interrupt (no DB needed)
    rangeCheck   = true,   -- only shout when the target is actually within your stop's range
    outcomeFlash = true,   -- flash the verdict as a flagged cast ends (KICKED/MISSED/WASTED)
    labelPos     = "center", -- cue label position: "center" (on health bar) | "above" (cast bar)
    cueHidesText = true,   -- centered cue label clears the plate's level/HP text while shown
    threat       = true,   -- threat tint (feature-detected; see Modules/Threat.lua)
    threatAmber  = true,   -- amber "closing in" estimate from group damage tallies
    tankMode     = false,  -- invert threat colors for tanking
    auras        = true,   -- show your own DoT/debuff timers on enemy plates
    auraSize     = 18,     -- aura icon size (px)
    auraMax      = 5,      -- max aura icons per plate (raid clutter cap)
    auraSwipe    = true,   -- radial cooldown swipe on aura icons
    auraDispel   = true,   -- color aura borders by dispel type (magic/curse/…)
    skin         = true,   -- custom nameplate skin (clean bar + border + target outline)
    bites        = true,   -- "damage bite" flash: a bright sliver marks health just lost
    focusDim     = true,   -- fade non-target plates while you have a target
    focusAlpha   = 0.5,    -- how far non-targets fade (lower = stronger fade)
    executeMark  = true,   -- execute tick on the health bar (+ red HP text below it)
    execPct      = 20,     -- execute threshold, percent of max health
    accent       = "gold", -- accent theme: gold | teal | violet | ice
    font         = "friz", -- font face: friz | arial | skurri | morpheus
    fontStyle    = "outline", -- text treatment: outline | clean (shadow) | thick
    barTexture   = "gradient", -- statusbar fill: gradient | flat
    barHeight    = 0,      -- health bar height in px; 0 (or <6) = Blizzard's default
    castBarHeight= 12,     -- Vantage cast bar height in px
    cueSound     = "raid", -- alert sound: raid | ready | bell
    friendly     = true,   -- also skin FRIENDLY plates (when Blizzard shows them)
    classColors  = true,   -- class-color PLAYER health bars (enemy + friendly)
    targetGlow   = true,   -- soft gold glow behind your current target's plate
    healthText   = "percent", -- "none" | "percent" | "health" | "both"
    showLevel    = true,   -- level text (difficulty-colored, "+" elite, "??" skull)
    manaBar      = true,   -- slim mana bar under the health bar (mana users only)
    nameSize     = 10,     -- nameplate name font size
    scale        = 1.0,    -- overlay scale
    parse        = true,   -- Vantage Parse: log interrupt decisions + outcomes
    briefing     = true,   -- kick sheet on entering an instance Vantage has intel on
    partyKicks   = true,   -- name a ready groupmate when your own stop is down
    debug        = false,
}
Vantage.defaults = defaults  -- the options panel's "Reset to defaults" reads this

local function applyDefaults(db, src)
    for k, v in pairs(src) do
        if db[k] == nil then db[k] = v end
    end
    return db
end

-- ===========================================================================
-- Interrupt alert sound (throttled so a flurry of casts can't machine-gun it)
-- ===========================================================================
local lastSound = 0
function Vantage:PlayInterruptSound()
    if not self.db.sound then return end
    local now = GetTime()
    if now - lastSound < 0.4 then return end
    lastSound = now
    pcall(PlaySound, Vantage:CueSound(), "Master")
end

-- ===========================================================================
-- Bootstrap
-- ===========================================================================
Vantage:RegisterEvent("ADDON_LOADED", function(_, name)
    if name ~= addonName then return end
    VantageDB = applyDefaults(VantageDB or {}, defaults)
    Vantage.db = VantageDB
end)

Vantage:RegisterEvent("PLAYER_LOGIN", function()
    local _, class = UnitClass("player")
    Vantage.playerClass = class

    for _, m in pairs(Vantage.modules) do
        if m.OnEnable then
            local ok, err = pcall(m.OnEnable, m)
            if not ok then Vantage:Print("module", m.moduleName, "failed:", err) end
        end
    end

    Vantage:Print(("v%s loaded. Class: %s. Type |cffffd100/vantage|r for options, |cffffd100/vantage test|r for a demo.")
        :format(Vantage.version, class or "?"))

    -- first run / upgrade notes (lastVersion is not in defaults, so a settings
    -- reset never re-triggers the welcome)
    local prev = Vantage.db.lastVersion
    Vantage.db.lastVersion = Vantage.version
    if not prev then
        Vantage:Print("First time? Make sure enemy nameplates are ON (default key |cffffd100V|r), then target any enemy and type |cffffd100/vantage test|r to see the interrupt cue fire.")
    elseif prev ~= Vantage.version then
        Vantage:Print(("Updated |cffffd100%s -> %s|r. New: a Style section in |cffffd100/vantage|r — font face & treatment, gradient or flat bars, bar heights, execute threshold, and alert sound.")
            :format(prev, Vantage.version))
    end
end)

-- ===========================================================================
-- Slash command
-- ===========================================================================
SLASH_VANTAGE1 = "/vantage"
SLASH_VANTAGE2 = "/vg"

local function toggle(key, label)
    Vantage.db[key] = not Vantage.db[key]
    Vantage:Print(label .. ":", Vantage.db[key] and "|cff44ff44ON|r" or "|cffff4444OFF|r")
end

SlashCmdList["VANTAGE"] = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    if cmd == "" or cmd == "config" or cmd == "options" then
        if Vantage.OpenOptions then Vantage:OpenOptions() else Vantage:ShowHelp() end
    elseif cmd == "test" then
        Vantage:RunDemo()
    elseif cmd == "sound" then
        toggle("sound", "Interrupt sound")
    elseif cmd == "cue" then
        toggle("interruptCue", "Interrupt cue")
    elseif cmd == "padlock" then
        toggle("showPadlock", "Uninterruptible padlock")
    elseif cmd == "threat" then
        toggle("threat", "Threat tint")
    elseif cmd == "tank" then
        toggle("tankMode", "Tank mode (invert threat)")
    elseif cmd == "auras" then
        toggle("auras", "Aura/DoT timers")
        if Vantage.Auras then Vantage.Auras:RefreshAll() end
    elseif cmd == "skin" then
        toggle("skin", "Custom nameplate skin")
        if Vantage.Skin then Vantage.Skin:RefreshAll() end
    elseif cmd == "unknown" then
        toggle("cueUnknown", "Cue unknown casts")
    elseif cmd == "pvp" then
        toggle("pvp", "PvP enemy-player cues")
    elseif cmd == "range" then
        toggle("rangeCheck", "Range-aware cue")
    elseif cmd == "flash" then
        toggle("outcomeFlash", "Outcome flash (KICKED/MISSED/WASTED)")
    elseif cmd == "check" then
        Vantage:CheckInterrupts()
    elseif cmd == "parse" then
        if Vantage.Parse then Vantage.Parse:Summary() end
    elseif cmd == "roster" or cmd == "crew" then
        if Vantage.Parse then Vantage.Parse:Roster() end
    elseif cmd == "export" then
        if Vantage.ParseExport then Vantage.ParseExport:Toggle() end
    elseif cmd == "brief" then
        if Vantage.Briefing then Vantage.Briefing:Brief(true) end
    elseif cmd == "party" then
        toggle("partyKicks", "Party kick watch")
    elseif cmd == "amber" then
        toggle("threatAmber", "Amber closing-in warning")
    elseif cmd == "learn" then
        toggle("learn", "Learn kicks from live combat")
    elseif cmd == "learned" then
        if Vantage.Learn then Vantage.Learn:Report() end
    elseif cmd == "plate" then
        if Vantage.Inspect then Vantage.Inspect:InspectTarget() end
    elseif cmd == "debug" then
        toggle("debug", "Debug")
    elseif cmd == "help" then
        Vantage:ShowHelp()
    else
        Vantage:ShowHelp()
    end
end

function Vantage:ShowHelp()
    Vantage:Print("|cffffd100/vantage|r opens the options panel. Commands:")
    print("  /vantage          - open the options panel")
    print("  /vantage test     - fire a demo interrupt cue on your target")
    print("  /vantage cue      - toggle the interrupt glow/sound")
    print("  /vantage sound    - toggle the alert sound")
    print("  /vantage padlock  - toggle the uninterruptible marker")
    print("  /vantage threat   - toggle threat tint    (tank: /vantage tank)")
    print("  /vantage amber    - amber warning when you're CLOSE to pulling")
    print("  /vantage auras    - toggle your DoT/debuff timer row")
    print("  /vantage skin     - toggle the custom nameplate skin")
    print("  /vantage unknown  - cue casts we have no intel on")
    print("  /vantage pvp      - cue enemy PLAYER casts vs your ready interrupt")
    print("  /vantage range    - only shout when the target is in your stop's range")
    print("  /vantage flash    - outcome flash on the bar (KICKED/MISSED/WASTED)")
    print("  /vantage check    - show your detected interrupts + readiness")
    print("  /vantage brief    - this dungeon's kick sheet, with the why")
    print("  /vantage party    - name a ready groupmate when your stop is down")
    print("  /vantage parse    - this session's interrupt report (Vantage Parse)")
    print("  /vantage roster   - interrupt profiles of every player Vantage has seen")
    print("  /vantage learn    - toggle learning kicks from live combat")
    print("  /vantage learned  - casts Vantage taught itself are kickable")
    print("  /vantage export   - copy session data for the web report")
end

-- Demo: find the nameplate belonging to your current target and fake a kickable
-- cast on it so you can see the cue without hunting for a casting mob.
function Vantage:RunDemo()
    if not UnitExists("target") then
        Vantage:Print("Target an enemy first, then |cffffd100/vantage test|r.")
        return
    end
    for unit, overlay in pairs(Vantage.plates or {}) do
        if UnitIsUnit(unit, "target") then
            overlay:ShowCast("Greater Heal (demo)", 135953, 3.0, false)
            -- Force the FULL cue so you can see it regardless of class/spec.
            local r = Vantage:GetReadyInterrupt("target")
            overlay.castbar:SetStatusBarColor(Vantage:RGB("kick"))
            overlay:ShowKick(r and r.label or "INTERRUPT") -- plays the sound itself
            Vantage:Print("Demo: full cue forced for 3s.")
            if not Vantage:HasInterrupt() then
                Vantage:Print("Heads up: you have no interrupt learned yet, so in REAL combat a kickable cast shows |cffffd100gold|r without this glow/sound. As a Priest you'll gain the |cffffd100FEAR|r cue once Psychic Scream is learned (~level 14).")
            end
            return
        end
    end
    Vantage:Print("No nameplate found for your target — make sure enemy nameplates are on (hold the nameplate key / press V), then retry.")
end

-- Diagnostic: shows what Vantage believes your interrupts are and whether each is
-- known + ready. This is exactly the gate that decides if the "kick now" glow fires.
function Vantage:CheckInterrupts()
    Vantage:Print("Interrupt check — class:", tostring(self.playerClass))
    local list = self.ClassInterrupts[self.playerClass]
    if not list then
        print("  |cffffd100No interrupt data for this class|r. Cast bars + padlock still work.")
        return
    end
    for i = 1, #list do
        local e = list[i]
        local extra = e.soft and (" |cff888888(soft: %s)|r"):format(e.label or "") or " |cff888888(hard kick)|r"
        if e.requiresType then
            local t = type(e.requiresType) == "table" and table.concat(e.requiresType, "/") or e.requiresType
            extra = extra .. (" |cff888888[vs %s only]|r"):format(t)
        end
        if e.pet then extra = extra .. (" |cff888888[pet: %s]|r"):format(e.petFamily or "?") end
        if e.form or e.forms or e.needsShield then extra = extra .. " |cff888888[stance/form/shield-gated]|r" end
        if e.needsPet then extra = extra .. " |cff888888[needs pet]|r" end
        if e.needsCombo then extra = extra .. " |cff888888[needs combo points]|r" end

        local known
        if e.pet then known = (Vantage.GetPetSpellCooldown(e.spell) ~= nil)
        else known = (GetSpellCooldown(e.spell) ~= nil) end

        if not known then
            print(("  %s: |cffff4444not learned%s|r%s"):format(e.spell, e.pet and " / pet not out" or "", extra))
        elseif self:EntryReady(e, "target") then
            local far = self:EntryInRange(e, "target") == false and " |cffff4444(target out of range)|r" or ""
            print(("  %s: |cff44ff44READY now|r%s%s"):format(e.spell, far, extra))
        else
            print(("  %s: known, |cffffd100not usable now|r (cooldown or wrong stance/form/target)%s"):format(e.spell, extra))
        end
    end
    local r, inRange = self:GetReadyInterrupt("target")
    print("  => ready interrupt:", r and ("|cff44ff44" .. (r.label or r.spell) .. "|r"
        .. (inRange == false and " |cffff4444(out of range)|r" or "")) or "|cffff4444none|r")
end
