-- Vigil/Core/Core.lua
-- The spine: a tiny event bus, a module registry, SavedVariables, the sound
-- helper, the slash command, and login bootstrapping. No external libraries.
local addonName, Vigil = ...

-- ===========================================================================
-- Event bus  -  Vigil:RegisterEvent("EVENT", function(event, ...) end)
-- Multiple modules can listen to the same event; we only register it once.
-- ===========================================================================
local frame = CreateFrame("Frame")
Vigil.frame = frame
local handlers = {}

function Vigil:RegisterEvent(event, fn)
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
-- Module registry  -  local M = Vigil:NewModule("Name"); function M:OnEnable() end
-- OnEnable() runs once, after the DB is ready, on PLAYER_LOGIN.
-- ===========================================================================
Vigil.modules = {}

function Vigil:NewModule(name)
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
    pvp          = true,   -- cue enemy PLAYER casts vs your ready interrupt (no DB needed)
    rangeCheck   = true,   -- only shout when the target is actually within your stop's range
    outcomeFlash = true,   -- flash the verdict as a flagged cast ends (KICKED/MISSED/WASTED)
    labelPos     = "center", -- cue label position: "center" (on health bar) | "above" (cast bar)
    threat       = true,   -- threat tint (feature-detected; see Modules/Threat.lua)
    tankMode     = false,  -- invert threat colors for tanking
    auras        = true,   -- show your own DoT/debuff timers on enemy plates
    auraSize     = 18,     -- aura icon size (px)
    auraMax      = 5,      -- max aura icons per plate (raid clutter cap)
    auraSwipe    = true,   -- radial cooldown swipe on aura icons
    auraDispel   = true,   -- color aura borders by dispel type (magic/curse/…)
    skin         = true,   -- custom nameplate skin (clean bar + border + target outline)
    bites        = true,   -- "damage bite" flash: a bright sliver marks health just lost
    focusDim     = true,   -- dim non-target plates slightly while you have a target
    executeMark  = true,   -- 20% execute tick on the health bar (+ red HP text below it)
    accent       = "gold", -- accent theme: gold | teal | violet | ice
    friendly     = true,   -- also skin FRIENDLY plates (when Blizzard shows them)
    classColors  = true,   -- class-color PLAYER health bars (enemy + friendly)
    targetGlow   = true,   -- soft gold glow behind your current target's plate
    healthText   = "percent", -- "none" | "percent" | "health" | "both"
    showLevel    = true,   -- level text (difficulty-colored, "+" elite, "??" skull)
    manaBar      = true,   -- slim mana bar under the health bar (mana users only)
    nameSize     = 10,     -- nameplate name font size
    scale        = 1.0,    -- overlay scale
    parse        = true,   -- Vigil Parse: log interrupt decisions + outcomes
    debug        = false,
}
Vigil.defaults = defaults  -- the options panel's "Reset to defaults" reads this

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
function Vigil:PlayInterruptSound()
    if not self.db.sound then return end
    local now = GetTime()
    if now - lastSound < 0.4 then return end
    lastSound = now
    local kit = (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959
    pcall(PlaySound, kit, "Master")
end

-- ===========================================================================
-- Bootstrap
-- ===========================================================================
Vigil:RegisterEvent("ADDON_LOADED", function(_, name)
    if name ~= addonName then return end
    VigilDB = applyDefaults(VigilDB or {}, defaults)
    Vigil.db = VigilDB
end)

Vigil:RegisterEvent("PLAYER_LOGIN", function()
    local _, class = UnitClass("player")
    Vigil.playerClass = class

    for _, m in pairs(Vigil.modules) do
        if m.OnEnable then
            local ok, err = pcall(m.OnEnable, m)
            if not ok then Vigil:Print("module", m.moduleName, "failed:", err) end
        end
    end

    Vigil:Print(("v%s loaded. Class: %s. Type |cffffd100/vigil|r for options, |cffffd100/vigil test|r for a demo.")
        :format(Vigil.version, class or "?"))

    -- first run / upgrade notes (lastVersion is not in defaults, so a settings
    -- reset never re-triggers the welcome)
    local prev = Vigil.db.lastVersion
    Vigil.db.lastVersion = Vigil.version
    if not prev then
        Vigil:Print("First time? Make sure enemy nameplates are ON (default key |cffffd100V|r), then target any enemy and type |cffffd100/vigil test|r to see the interrupt cue fire.")
    elseif prev ~= Vigil.version then
        Vigil:Print(("Updated |cffffd100%s -> %s|r. New: cues are range-aware, cast bars flash their outcome (KICKED / MISSED / WASTED), and the cue label position is configurable in |cffffd100/vigil|r.")
            :format(prev, Vigil.version))
    end
end)

-- ===========================================================================
-- Slash command
-- ===========================================================================
SLASH_VIGIL1 = "/vigil"
SLASH_VIGIL2 = "/vg"

local function toggle(key, label)
    Vigil.db[key] = not Vigil.db[key]
    Vigil:Print(label .. ":", Vigil.db[key] and "|cff44ff44ON|r" or "|cffff4444OFF|r")
end

SlashCmdList["VIGIL"] = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    if cmd == "" or cmd == "config" or cmd == "options" then
        if Vigil.OpenOptions then Vigil:OpenOptions() else Vigil:ShowHelp() end
    elseif cmd == "test" then
        Vigil:RunDemo()
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
        if Vigil.Auras then Vigil.Auras:RefreshAll() end
    elseif cmd == "skin" then
        toggle("skin", "Custom nameplate skin")
        if Vigil.Skin then Vigil.Skin:RefreshAll() end
    elseif cmd == "unknown" then
        toggle("cueUnknown", "Cue unknown casts")
    elseif cmd == "pvp" then
        toggle("pvp", "PvP enemy-player cues")
    elseif cmd == "range" then
        toggle("rangeCheck", "Range-aware cue")
    elseif cmd == "flash" then
        toggle("outcomeFlash", "Outcome flash (KICKED/MISSED/WASTED)")
    elseif cmd == "check" then
        Vigil:CheckInterrupts()
    elseif cmd == "parse" then
        if Vigil.Parse then Vigil.Parse:Summary() end
    elseif cmd == "export" then
        if Vigil.ParseExport then Vigil.ParseExport:Toggle() end
    elseif cmd == "debug" then
        toggle("debug", "Debug")
    elseif cmd == "help" then
        Vigil:ShowHelp()
    else
        Vigil:ShowHelp()
    end
end

function Vigil:ShowHelp()
    Vigil:Print("|cffffd100/vigil|r opens the options panel. Commands:")
    print("  /vigil          - open the options panel")
    print("  /vigil test     - fire a demo interrupt cue on your target")
    print("  /vigil cue      - toggle the interrupt glow/sound")
    print("  /vigil sound    - toggle the alert sound")
    print("  /vigil padlock  - toggle the uninterruptible marker")
    print("  /vigil threat   - toggle threat tint    (tank: /vigil tank)")
    print("  /vigil auras    - toggle your DoT/debuff timer row")
    print("  /vigil skin     - toggle the custom nameplate skin")
    print("  /vigil unknown  - cue casts we have no intel on")
    print("  /vigil pvp      - cue enemy PLAYER casts vs your ready interrupt")
    print("  /vigil range    - only shout when the target is in your stop's range")
    print("  /vigil flash    - outcome flash on the bar (KICKED/MISSED/WASTED)")
    print("  /vigil check    - show your detected interrupts + readiness")
    print("  /vigil parse    - this session's interrupt report (Vigil Parse)")
    print("  /vigil export   - copy session data for the web report")
end

-- Demo: find the nameplate belonging to your current target and fake a kickable
-- cast on it so you can see the cue without hunting for a casting mob.
function Vigil:RunDemo()
    if not UnitExists("target") then
        Vigil:Print("Target an enemy first, then |cffffd100/vigil test|r.")
        return
    end
    for unit, overlay in pairs(Vigil.plates or {}) do
        if UnitIsUnit(unit, "target") then
            overlay:ShowCast("Greater Heal (demo)", 135953, 3.0, false)
            -- Force the FULL cue so you can see it regardless of class/spec.
            local r = Vigil:GetReadyInterrupt("target")
            overlay.castbar:SetStatusBarColor(Vigil:RGB("kick"))
            overlay:ShowKick(r and r.label or "INTERRUPT") -- plays the sound itself
            Vigil:Print("Demo: full cue forced for 3s.")
            if not Vigil:HasInterrupt() then
                Vigil:Print("Heads up: you have no interrupt learned yet, so in REAL combat a kickable cast shows |cffffd100gold|r without this glow/sound. As a Priest you'll gain the |cffffd100FEAR|r cue once Psychic Scream is learned (~level 14).")
            end
            return
        end
    end
    Vigil:Print("No nameplate found for your target — make sure enemy nameplates are on (hold the nameplate key / press V), then retry.")
end

-- Diagnostic: shows what Vigil believes your interrupts are and whether each is
-- known + ready. This is exactly the gate that decides if the "kick now" glow fires.
function Vigil:CheckInterrupts()
    Vigil:Print("Interrupt check — class:", tostring(self.playerClass))
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
        if e.pet then known = (Vigil.GetPetSpellCooldown(e.spell) ~= nil)
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
