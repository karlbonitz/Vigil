-- tests/scenario.lua
--
-- Drives a full fake session through the loaded addon: login, plate appears,
-- enemy casts, range changes, interrupts land / slip through / get wasted,
-- plate despawns, slash commands, export. Asserts the decisions and the
-- overlay states at each step. Run via tests/run.py, parameterized by class
-- through the CLASS_CONFIG global set by the driver.

local failures = {}
local checks = 0

local function ok(cond, label)
    checks = checks + 1
    if not cond then failures[#failures + 1] = label end
end

local function eq(got, want, label)
    checks = checks + 1
    if got ~= want then
        failures[#failures + 1] = ("%s (got %s, want %s)"):format(label, tostring(got), tostring(want))
    end
end

local cfg = CLASS_CONFIG
local H = Harness

-- ---------------------------------------------------------------------------
-- World setup
-- ---------------------------------------------------------------------------
H.units.player = {
    name = "Testchar", className = cfg.className, class = cfg.class,
    guid = "Player-1-ME", level = 70, isPlayer = true, hostile = false,
}
for spell, cd in pairs(cfg.cooldowns) do H.cooldowns[spell] = cd end

local MOB_GUID = "Creature-0-1111"
local function spawnMob(token, name, opts)
    opts = opts or {}
    local plate = H.MakePlate()
    plate.UnitFrame.unit = token -- Blizzard sets this on real 2.5.x plates
    plate.UnitFrame.castBar:SetUnit(token, false, false) -- Blizzard arms it per add
    H.units[token] = {
        name = name, guid = opts.guid or MOB_GUID, level = opts.level or 70,
        hostile = true, isPlayer = opts.isPlayer or false,
        classification = opts.classification or "normal",
        creatureType = opts.creatureType or "Humanoid",
        plate = plate,
        auras = opts.auras,
    }
end

-- ---------------------------------------------------------------------------
-- 1. Login
-- ---------------------------------------------------------------------------
H.FireEvent("ADDON_LOADED", "Vigil")
ok(Vigil.db ~= nil, "db initialized on ADDON_LOADED")
H.FireEvent("PLAYER_LOGIN")
eq(Vigil.playerClass, cfg.class, "player class detected")
ok(Vigil.Options and Vigil.Options.panel ~= nil, "options panel built without error")

-- 2. A plate appears; catch decisions from a live cast
spawnMob("nameplate1", "Cabal Acolyte")
H.alias.target = "nameplate1"
H.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
local o = Vigil.plates.nameplate1
ok(o ~= nil, "overlay created on plate add")
-- regression: a FRESH overlay must not render its empty cast bar (the
-- "ghost grey bar under every new plate" bug found in-game)
ok(not o.castbar:IsShown(), "fresh overlay's cast bar hidden before any cast")
ok(not o.iconF:IsShown(), "fresh overlay's icon hidden before any cast")

-- 2b. Blizzard's own plate cast bar (lowercase castBar on 2.5.5+) stays
-- suppressed while we own cast bars
local blizzCB = H.units.nameplate1.plate.UnitFrame.castBar
eq(blizzCB.__unit, nil, "Blizzard cast bar detached (SetUnit nil) on skinned enemy")
blizzCB:Hide()
blizzCB:Show() -- Blizzard would Show it when the mob starts casting
ok(not blizzCB:IsShown(), "Blizzard plate cast bar suppressed on skinned enemy")

-- 2c. Stock plate decorations are suppressed while the skin owns the plate
-- (the rounded Nameplate-Border art with its level ring, the level text, the
-- grey bar background — the "still looks like Blizzard plates" bug), and
-- restored when the skin toggles off.
local blizzUF = H.units.nameplate1.plate.UnitFrame
local blizzBorder = blizzUF.HealthBarsContainer.border
ok(not blizzBorder:IsShown(), "rounded border art hidden on skinned plate")
eq(blizzBorder.__alpha, 0, "rounded border art alpha-zeroed on skinned plate")
eq(blizzUF.LevelFrame.__alpha, 0, "Blizzard level frame suppressed on skinned plate")
eq(blizzUF.selectionHighlight.__alpha, 0, "selection highlight suppressed on skinned plate")
eq(blizzUF.healthBar.background.__alpha, 0, "stock grey bar background suppressed")
SlashCmdList["VIGIL"]("skin") -- off
ok(blizzBorder:IsShown(), "rounded border art restored when skin off")
eq(blizzBorder.__alpha, 1, "rounded border alpha restored when skin off")
eq(blizzUF.LevelFrame.__alpha, 1, "Blizzard level frame restored when skin off")
eq(blizzUF.selectionHighlight.__alpha, 0.25, "selection highlight restored when skin off")
eq(blizzUF.healthBar.background.__alpha, 0.85, "stock bar background restored when skin off")
eq(blizzCB.__unit, "nameplate1", "Blizzard cast bar re-armed when skin off")
SlashCmdList["VIGIL"]("skin") -- back on
eq(blizzBorder.__alpha, 0, "rounded border re-suppressed when skin back on")
eq(blizzCB.__unit, nil, "Blizzard cast bar re-detached when skin back on")

-- 2d. Style options apply live (v0.8.0): bar heights, fonts, fills, thresholds
eq(Vigil.db.barHeight, 0, "bar height defaults to auto")
Vigil.db.barHeight = 16
Vigil.Skin:RefreshAll()
eq(blizzUF.HealthBarsContainer.__h, 16, "custom bar height applied to the container")
Vigil.db.barHeight = 0
Vigil.Skin:RefreshAll()
eq(blizzUF.HealthBarsContainer.__h, 11, "auto bar height restores the client default")

Vigil.db.font = "arial"; Vigil.db.fontStyle = "clean"; Vigil.db.barTexture = "flat"
Vigil.db.castBarHeight = 16
Vigil.Skin:RefreshAll()
Vigil.Nameplates:ApplyStyle()
ok(blizzUF.name.__font and blizzUF.name.__font[1] == "Fonts\\ARIALN.TTF",
    "font face applies to the plate name")
eq(blizzUF.name.__font and blizzUF.name.__font[3], "", "clean text style drops the outline")
eq(blizzUF.healthBar.__bartex.__tex, "Interface\\Buttons\\WHITE8x8", "flat fill applies to the health bar")
eq(o.__h, 16, "cast bar height applies to the overlay")
eq(o.iconF.__h, 18, "cast icon tracks the cast bar height")
eq(o.castbar.__bartex.__tex, "Interface\\Buttons\\WHITE8x8", "flat fill applies to the cast bar")
eq(o.kickText.__font and o.kickText.__font[3], "THICKOUTLINE", "cue label stays THICK regardless of text style")
-- back to stock for the rest of the session
Vigil.db.font = "friz"; Vigil.db.fontStyle = "outline"; Vigil.db.barTexture = "gradient"
Vigil.db.castBarHeight = 12
Vigil.Skin:RefreshAll()
Vigil.Nameplates:ApplyStyle()

-- execute threshold slider: 25% health is quiet at 20%, lit once raised to 30%
blizzUF.healthBar:SetValue(25)
eq(blizzUF.__vigilExec.__w, 1, "25% health: exec tick quiet at default 20% threshold")
Vigil.db.execPct = 30
Vigil.Skin:RefreshAll()
eq(blizzUF.__vigilExec.__w, 2, "25% health: exec tick lit once threshold raised to 30%")
Vigil.db.execPct = 20
blizzUF.healthBar:SetValue(100)
Vigil.Skin:RefreshAll()

-- cue sound choice resolves through the helper the cue actually plays
eq(Vigil:CueSound(), 8959, "default cue sound = raid warning")
Vigil.db.cueSound = "ready"
eq(Vigil:CueSound(), 8960, "cue sound choice resolves")
Vigil.db.cueSound = "raid"

-- 3. Kickable cast starts (live API path): Greater Heal is in the Intel Pack
H.units.nameplate1.casting = {
    name = "Greater Heal", spellID = 25314,
    startMS = H.now * 1000, endMS = (H.now + 2.5) * 1000,
}
H.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
ok(o.active ~= nil, "cast tracked")
eq(o.active and o.active.code, "ready", "ready tier: interrupt ready + in range")
ok(o.kickF:IsShown(), "cue label shown")
eq(o.kickText:GetText(), cfg.label, "cue label text matches class tool")
eq(H.sounds, 1, "sound played exactly once")
-- the centered cue clears the plate's inner text (cueHidesText default on)
ok(not blizzUF.__vigilHP:IsShown(), "cue clears the HP text while shown")
ok(not blizzUF.__vigilLvl:IsShown(), "cue clears the level text while shown")

-- 4. Cooldown re-eval doesn't re-fire the sound
H.FireEvent("SPELL_UPDATE_COOLDOWN")
eq(H.sounds, 1, "no sound spam on re-evaluation")

-- 5. Walk out of range -> tier drops to "range", label hides; walk back -> ready
H.range[cfg.spell] = 0
H.Advance(0.3)
eq(o.active and o.active.code, "range", "out of range: range tier")
ok(not o.kickF:IsShown(), "no label while out of range")
H.range[cfg.spell] = 1
H.Advance(0.3)
eq(o.active and o.active.code, "ready", "back in range: ready tier")
eq(H.sounds, 2, "sound fires once more when cue reappears")

-- 6. Someone kicks it: KICKED flash, then reset
-- (srcFlags 0x511 = mine + friendly + player-controlled + TYPE_PLAYER)
H.SetCLEU(nil, "SPELL_INTERRUPT", nil, "Player-1-ME", "Testchar", 0x511, 0, MOB_GUID,
    "Cabal Acolyte", 0, 0, 2139, "Counterspell", 0, 25314, "Greater Heal")
H.FireEvent("COMBAT_LOG_EVENT_UNFILTERED")
eq(o.flashing, "kicked", "KICKED flash started")
eq(o.timeText:GetText(), "KICKED", "verdict label")
ok(o.active == nil, "cast record resolved at flash start")
ok(blizzUF.__vigilHP:IsShown(), "HP text returns once the cue clears")
ok(blizzUF.__vigilLvl:IsShown(), "level text returns once the cue clears")
H.Advance(1.0)
ok(not o.castbar:IsShown(), "bar cleared after flash")
ok(o.flashing == nil, "flash state cleared")

-- 6b. The roster: my kick above built MY profile; a party member's interrupt
-- (flags 0x512 = party + friendly + player-controlled + TYPE_PLAYER) builds
-- theirs — even on a mob Vigil isn't tracking.
local myProf = VigilParseDB.roster["Testchar"]
ok(myProf and myProf.kicks == 1, "my own interrupt lands in the roster")
H.SetCLEU(nil, "SPELL_INTERRUPT", nil, "Player-2-KICKER", "Kickbot", 0x512, 0,
    "Creature-0-9999", "Some Mob", 0, 0, 2139, "Counterspell", 0, 133, "Fireball")
H.FireEvent("COMBAT_LOG_EVENT_UNFILTERED")
local prof = VigilParseDB.roster["Kickbot"]
ok(prof ~= nil, "roster profile created for a party member's interrupt")
eq(prof and prof.kicks, 1, "roster kick counted")
eq(prof and prof.tools and prof.tools["Counterspell"], 1, "roster tool tallied")
eq(prof and prof.gkicks, 1, "grouped kick counted from the party flag")
eq(prof and prof.class, "MAGE", "class resolved via GetPlayerInfoByGUID")
-- a HOSTILE player's kick (0x548 = hostile reaction, outsider) builds nothing
H.SetCLEU(nil, "SPELL_INTERRUPT", nil, "Player-3-ENEMY", "Ganker", 0x548, 0,
    "Creature-0-9999", "Some Mob", 0, 0, 2139, "Counterspell", 0, 133, "Fireball")
H.FireEvent("COMBAT_LOG_EVENT_UNFILTERED")
ok(VigilParseDB.roster["Ganker"] == nil, "hostile players stay out of the roster")
SlashCmdList["VIGIL"]("roster") -- smoke: prints without error

-- 7. CLEU-fallback cast (no live cast info), completes while ready -> MISSED
H.units.nameplate1.casting = nil
ok(not o.castbar:IsShown(), "bar clear before fallback cast starts")
H.SetCLEU(nil, "SPELL_CAST_START", nil, MOB_GUID, "Cabal Acolyte", 0, 0, nil, nil, 0, 0,
    25314, "Greater Heal", 0)
H.FireEvent("COMBAT_LOG_EVENT_UNFILTERED")
ok(o.active ~= nil, "CLEU fallback started a cast")
eq(o.active and o.active.code, "ready", "fallback cast evaluated ready")
H.SetCLEU(nil, "SPELL_CAST_SUCCESS", nil, MOB_GUID, "Cabal Acolyte", 0, 0, nil, nil, 0, 0,
    25314, "Greater Heal", 0)
H.FireEvent("COMBAT_LOG_EVENT_UNFILTERED")
eq(o.flashing, "missed", "MISSED flash on let-through")
H.Advance(1.0)

-- 8. Locked cast + your kick lands on it -> WASTED label, bar untouched
H.SetCLEU(nil, "SPELL_CAST_START", nil, MOB_GUID, "Cabal Acolyte", 0, 0, nil, nil, 0, 0,
    12345, "Mind Control", 0)
H.FireEvent("COMBAT_LOG_EVENT_UNFILTERED")
eq(o.active and o.active.code, "locked", "padlock tier for do-not-kick cast")
ok(o.padlock:IsShown(), "padlock icon shown")
if cfg.hardKick then
    H.SetCLEU(nil, "SPELL_CAST_SUCCESS", nil, "Player-1-ME", "Testchar", 0, 0, MOB_GUID,
        "Cabal Acolyte", 0, 0, 8042, cfg.spell, 0)
    H.FireEvent("COMBAT_LOG_EVENT_UNFILTERED")
    eq(o.kickText:GetText(), "WASTED", "WASTED label on wasted kick")
    ok(o.castbar:IsShown(), "locked cast bar still shown during WASTED")
    ok(o.active ~= nil, "locked cast still tracked during WASTED")
    H.Advance(1.2)
    ok(not o.kickF:IsShown(), "WASTED label self-hides")
end
H.SetCLEU(nil, "SPELL_CAST_SUCCESS", nil, MOB_GUID, "Cabal Acolyte", 0, 0, nil, nil, 0, 0,
    12345, "Mind Control", 0)
H.FireEvent("COMBAT_LOG_EVENT_UNFILTERED")
H.Advance(1.0)

-- 9. Soft-CC immunity: a boss suppresses soft cues (soft classes fall to aware)
spawnMob("nameplate2", "Murmur", { guid = "Creature-0-2222", classification = "worldboss" })
H.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate2")
local o2 = Vigil.plates.nameplate2
H.units.nameplate2.casting = {
    name = "Greater Heal", spellID = 25314,
    startMS = H.now * 1000, endMS = (H.now + 2.5) * 1000,
}
H.FireEvent("UNIT_SPELLCAST_START", "nameplate2")
eq(o2.active and o2.active.code, cfg.bossCode, "boss cast tier for this class")
H.units.nameplate2.casting = nil
H.FireEvent("UNIT_SPELLCAST_STOP", "nameplate2")

-- 10. PvP: enemy player, unknown spell -> cue fires anyway
spawnMob("nameplate3", "Sneakcaster", { guid = "Player-1-ENEMY", isPlayer = true })
H.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate3")
local o3 = Vigil.plates.nameplate3
H.units.nameplate3.casting = {
    name = "Totally Unknown Spell", spellID = 99999,
    startMS = H.now * 1000, endMS = (H.now + 3) * 1000,
}
H.FireEvent("UNIT_SPELLCAST_START", "nameplate3")
eq(o3.active and o3.active.code, "ready", "PvP: unknown player cast still cues")
H.units.nameplate3.casting = nil
H.FireEvent("UNIT_SPELLCAST_STOP", "nameplate3")

-- 11. Auras: our own debuff renders a timer row without error
H.units.nameplate1.auras = { { name = "Shadow Word: Pain", debuffType = "Magic", duration = 18 } }
H.FireEvent("UNIT_AURA", "nameplate1")
H.Advance(0.6) -- backstop rescan + text ticker

-- 11b. Stellar-pass features: bites, execute mark, focus dim, hover wash
local uf1 = H.units.nameplate1.plate.UnitFrame
local uf2 = H.units.nameplate2.plate.UnitFrame
local hb1 = uf1.healthBar

hb1:SetValue(80)              -- health going UP never bites
hb1:SetValue(55)              -- health lost -> a bite spawns
hb1:SetValue(40)              -- rapid second hit -> coalesces into the same bite
ok(uf1.__vigilBite ~= nil and uf1.__vigilBiteTex:IsShown(), "bite live and coalesced")
H.Advance(0.6)
ok(uf1.__vigilBite == nil and not uf1.__vigilBiteTex:IsShown(), "bite faded and retired")

ok(uf1.__vigilExec and uf1.__vigilExec:IsShown(), "execute tick shown")
ok(uf1.__vigilExec.__vg > 0.9, "execute tick quiet above 20%")
hb1:SetValue(15)              -- into execute range
ok(uf1.__vigilExec.__vg < 0.5, "execute tick lit below 20%")

H.FireEvent("PLAYER_TARGET_CHANGED") -- target is nameplate1
eq(uf2.__alpha, 0.5, "non-target plate faded to focusAlpha")
eq(uf1.__alpha, 1, "target plate at full opacity")
eq(o2.__alpha, 0.5, "non-target cast overlay faded too")

-- Aggro display. SOLO: silent even when a mob is on you (it always is).
H.alias.nameplate2target = "player" -- the mob is targeting me
H.FireEvent("UNIT_THREAT_LIST_UPDATE")
H.Advance(0.3)
local b2 = uf2.__vigilBorder.edges[1]
ok(b2.__vr == 0 and b2.__vg == 0, "solo: no aggro border even when targeted")

-- GROUPED: mob targeting me -> red border (ground truth, no threat table)
H.inGroup = true
H.units.nameplate2.inCombat = true
H.FireEvent("UNIT_THREAT_LIST_UPDATE")
H.Advance(0.3)
ok(b2.__vr and b2.__vr > 0.8 and b2.__vg < 0.4, "grouped: mob on ME -> red border")
local bc = uf2.healthBar.__barcolor
ok(bc and bc[1] == 1 and bc[2] < 0.4, "grouped: mob on ME -> alarm-red BAR")

-- the TARGET keeps its accent border even when it's on me
H.alias.nameplate1target = "player"
H.FireEvent("UNIT_THREAT_LIST_UPDATE")
H.Advance(0.3)
local b1 = uf1.__vigilBorder.edges[1]
ok(b1.__vg and b1.__vg > 0.5, "target keeps accent border over threat")

-- mob switches to a groupmate -> red clears (dps mode: not your problem)
H.alias.nameplate2target = nil
H.FireEvent("UNIT_THREAT_LIST_UPDATE")
H.Advance(0.3)
ok(b2.__vr == 0 and b2.__vg == 0, "border clears when the mob leaves you")
bc = uf2.healthBar.__barcolor
ok(bc and bc[3] > bc[1], "tank's mob -> cool slate BAR (calm is never red-family)")
H.units.nameplate2.inCombat = false
H.FireEvent("UNIT_THREAT_LIST_UPDATE")
H.Advance(0.3)
bc = uf2.healthBar.__barcolor
ok(bc and bc[1] == 1 and bc[2] < 0.3, "out of combat -> reaction color returns")

H.inGroup = false
H.FireEvent("UNIT_THREAT_LIST_UPDATE")
H.Advance(0.3)

H.alias.mouseover = "nameplate2"
H.FireEvent("UPDATE_MOUSEOVER_UNIT")
ok(uf2.__vigilHover:IsShown(), "hover wash on mouseover plate")
H.alias.mouseover = nil
H.Advance(0.4)
ok(not uf2.__vigilHover:IsShown(), "hover wash retired when mouse leaves")

-- 12. Plate despawn releases cleanly; slash commands and export run
-- 12a. First: a duplicate ADDED (missed REMOVED) must release the stale
-- overlay instead of leaking it as a ghost bar
local oGhost = Vigil.plates.nameplate1
oGhost:ShowCast("Ghost Cast", nil, 3)
ok(oGhost.castbar:IsShown(), "setup: stale cast showing before duplicate ADDED")
H.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
local oFresh = Vigil.plates.nameplate1
ok(oFresh ~= nil and not oFresh.castbar:IsShown(),
    "duplicate ADDED releases the stale overlay (no ghost cast bar)")

H.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
ok(Vigil.plates.nameplate1 == nil, "overlay released on plate removal")

SlashCmdList["VIGIL"]("check")
SlashCmdList["VIGIL"]("parse")
SlashCmdList["VIGIL"]("test")   -- demo on target (nameplate1 is gone; target alias too)
H.alias.target = "nameplate2"
SlashCmdList["VIGIL"]("test")

local export = Vigil.ParseExport:BuildExport()
ok(type(export) == "string" and export:find('"sessions"', 1, true) ~= nil, "export builds JSON")
ok(export:find('"miss":true', 1, true) ~= nil, "export contains the let-through row")
ok(export:find('"roster"', 1, true) ~= nil and export:find("Kickbot", 1, true) ~= nil,
    "export carries the roster profiles")

-- plate inspector (/vigil plate): dumps the frame tree with parentKeys
local dump = Vigil.Inspect:DumpPlate(H.units.nameplate2.plate)
ok(dump:find("healthBar", 1, true) ~= nil, "inspector dump names the health bar")
ok(dump:find("[border]", 1, true) ~= nil, "inspector dump names the border art")
ok(dump:find("[LevelFrame]", 1, true) ~= nil, "inspector dump names the level frame")

-- 13. Options interactions: toggle every checkbox + run reset
for _, f in ipairs(H.frames) do
    if f.__kind == "CheckButton" and f.__scripts.OnClick then
        f.__checked = not f.__checked
        f:Click()
    end
end
SlashCmdList["VIGIL"]("help")

-- ---------------------------------------------------------------------------
-- Report
-- ---------------------------------------------------------------------------
if #failures > 0 then
    error(("%d/%d checks failed [%s]:\n  - %s"):format(
        #failures, checks, cfg.class, table.concat(failures, "\n  - ")), 0)
end
return ("%d checks passed [%s]"):format(checks, cfg.class)
