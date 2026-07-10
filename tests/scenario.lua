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
H.FireEvent("ADDON_LOADED", "Vantage")
ok(Vantage.db ~= nil, "db initialized on ADDON_LOADED")
H.FireEvent("PLAYER_LOGIN")
eq(Vantage.playerClass, cfg.class, "player class detected")
ok(Vantage.Options and Vantage.Options.panel ~= nil, "options panel built without error")

-- 2. A plate appears; catch decisions from a live cast
spawnMob("nameplate1", "Cabal Acolyte")
H.alias.target = "nameplate1"
H.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
local o = Vantage.plates.nameplate1
ok(o ~= nil, "overlay created on plate add")
-- regression: a FRESH overlay must not render its empty cast bar (the
-- "ghost grey bar under every new plate" bug found in-game)
ok(not o.castbar:IsShown(), "fresh overlay's cast bar hidden before any cast")
ok(not o.iconF:IsShown(), "fresh overlay's icon hidden before any cast")
-- regression: the overlay hangs off the HEALTH BAR, not the plate frame —
-- the anniversary template insets the bar asymmetrically (4px L / 21px R),
-- so a plate-center anchor drifts ~9px right of the bar (seen in-game as an
-- "out of place" threat strip / cast bar)
eq(o.__anchors and o.__anchors[1] and o.__anchors[1].rel,
   H.units.nameplate1.plate.UnitFrame.healthBar,
   "overlay anchored to the health bar, not the plate")

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
SlashCmdList["VANTAGE"]("skin") -- off
ok(blizzBorder:IsShown(), "rounded border art restored when skin off")
eq(blizzBorder.__alpha, 1, "rounded border alpha restored when skin off")
eq(blizzUF.LevelFrame.__alpha, 1, "Blizzard level frame restored when skin off")
eq(blizzUF.selectionHighlight.__alpha, 0.25, "selection highlight restored when skin off")
eq(blizzUF.healthBar.background.__alpha, 0.85, "stock bar background restored when skin off")
eq(blizzCB.__unit, "nameplate1", "Blizzard cast bar re-armed when skin off")
SlashCmdList["VANTAGE"]("skin") -- back on
eq(blizzBorder.__alpha, 0, "rounded border re-suppressed when skin back on")
eq(blizzCB.__unit, nil, "Blizzard cast bar re-detached when skin back on")

-- 2d. Style options apply live (v0.8.0): bar heights, fonts, fills, thresholds
eq(Vantage.db.barHeight, 0, "bar height defaults to auto")
Vantage.db.barHeight = 16
Vantage.Skin:RefreshAll()
eq(blizzUF.HealthBarsContainer.__h, 16, "custom bar height applied to the container")
Vantage.db.barHeight = 0
Vantage.Skin:RefreshAll()
eq(blizzUF.HealthBarsContainer.__h, 11, "auto bar height restores the client default")

Vantage.db.font = "arial"; Vantage.db.fontStyle = "clean"; Vantage.db.barTexture = "flat"
Vantage.db.castBarHeight = 16
Vantage.Skin:RefreshAll()
Vantage.Nameplates:ApplyStyle()
ok(blizzUF.name.__font and blizzUF.name.__font[1] == "Fonts\\ARIALN.TTF",
    "font face applies to the plate name")
eq(blizzUF.name.__font and blizzUF.name.__font[3], "", "clean text style drops the outline")
eq(blizzUF.healthBar.__bartex.__tex, "Interface\\Buttons\\WHITE8x8", "flat fill applies to the health bar")
eq(o.__h, 16, "cast bar height applies to the overlay")
eq(o.iconF.__h, 18, "cast icon tracks the cast bar height")
eq(o.castbar.__bartex.__tex, "Interface\\Buttons\\WHITE8x8", "flat fill applies to the cast bar")
eq(o.kickText.__font and o.kickText.__font[3], "THICKOUTLINE", "cue label stays THICK regardless of text style")
-- back to stock for the rest of the session
Vantage.db.font = "friz"; Vantage.db.fontStyle = "outline"; Vantage.db.barTexture = "gradient"
Vantage.db.castBarHeight = 12
Vantage.Skin:RefreshAll()
Vantage.Nameplates:ApplyStyle()

-- execute threshold slider: 25% health is quiet at 20%, lit once raised to 30%
blizzUF.healthBar:SetValue(25)
eq(blizzUF.__vantageExec.__w, 1, "25% health: exec tick quiet at default 20% threshold")
Vantage.db.execPct = 30
Vantage.Skin:RefreshAll()
eq(blizzUF.__vantageExec.__w, 2, "25% health: exec tick lit once threshold raised to 30%")
Vantage.db.execPct = 20
blizzUF.healthBar:SetValue(100)
Vantage.Skin:RefreshAll()

-- cue sound choice resolves through the helper the cue actually plays
eq(Vantage:CueSound(), 8959, "default cue sound = raid warning")
Vantage.db.cueSound = "ready"
eq(Vantage:CueSound(), 8960, "cue sound choice resolves")
Vantage.db.cueSound = "raid"

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
ok(not blizzUF.__vantageHP:IsShown(), "cue clears the HP text while shown")
ok(not blizzUF.__vantageLvl:IsShown(), "cue clears the level text while shown")

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
ok(blizzUF.__vantageHP:IsShown(), "HP text returns once the cue clears")
ok(blizzUF.__vantageLvl:IsShown(), "level text returns once the cue clears")
H.Advance(1.0)
ok(not o.castbar:IsShown(), "bar cleared after flash")
ok(o.flashing == nil, "flash state cleared")

-- 6b. The roster: my kick above built MY profile; a party member's interrupt
-- (flags 0x512 = party + friendly + player-controlled + TYPE_PLAYER) builds
-- theirs — even on a mob Vantage isn't tracking.
local myProf = VantageParseDB.roster["Testchar"]
ok(myProf and myProf.kicks == 1, "my own interrupt lands in the roster")
H.SetCLEU(nil, "SPELL_INTERRUPT", nil, "Player-2-KICKER", "Kickbot", 0x512, 0,
    "Creature-0-9999", "Some Mob", 0, 0, 2139, "Counterspell", 0, 133, "Fireball")
H.FireEvent("COMBAT_LOG_EVENT_UNFILTERED")
local prof = VantageParseDB.roster["Kickbot"]
ok(prof ~= nil, "roster profile created for a party member's interrupt")
eq(prof and prof.kicks, 1, "roster kick counted")
eq(prof and prof.tools and prof.tools["Counterspell"], 1, "roster tool tallied")
eq(prof and prof.gkicks, 1, "grouped kick counted from the party flag")
eq(prof and prof.class, "MAGE", "class resolved via GetPlayerInfoByGUID")
-- a HOSTILE player's kick (0x548 = hostile reaction, outsider) builds nothing
H.SetCLEU(nil, "SPELL_INTERRUPT", nil, "Player-3-ENEMY", "Ganker", 0x548, 0,
    "Creature-0-9999", "Some Mob", 0, 0, 2139, "Counterspell", 0, 133, "Fireball")
H.FireEvent("COMBAT_LOG_EVENT_UNFILTERED")
ok(VantageParseDB.roster["Ganker"] == nil, "hostile players stay out of the roster")
SlashCmdList["VANTAGE"]("roster") -- smoke: prints without error

-- 6c. Self-learning: watching a cast get interrupted banks it as kickable.
-- A hostile caster (destFlags 0x40) casts an UNCURATED spell and a groupmate
-- kicks it. NOTE: a deliberately SYNTHETIC spell (id/name that no seed verifies
-- and nobody would ever promote) so this stays valid even after real casts like
-- Radiation Bolt land in Data/CommunityPack.lua — once a spell is in the pack
-- it's "known", so the addon correctly stops re-learning it.
H.SetCLEU(nil, "SPELL_INTERRUPT", nil, "Player-2-KICKER", "Kickbot", 0x512, 0,
    "Creature-0-1-0-0-7053-000023BE71", "Irradiated Pillager", 0x40, 0, 2139,
    "Counterspell", 0, 9990001, "Harness Test Cast")
H.FireEvent("COMBAT_LOG_EVENT_UNFILTERED")
local learned = VantageLearnedDB and VantageLearnedDB.spells
ok(learned and learned["harness test cast"] ~= nil, "learned an uncurated interrupted cast")
local li = Vantage.GetKickInfo("Harness Test Cast", 9990001)
ok(li and li.interruptible == true and li.learned, "learned cast now looks up as kickable")
-- the learned entry banks EVIDENCE for crowdsourced verification: the interrupt
-- that landed, and the caster's creatureID pulled from the GUID.
eq(learned["harness test cast"].by, "Counterspell", "learned entry records the interrupt that landed")
eq(learned["harness test cast"].npc, 7053, "learned entry records the caster's creatureID")

-- the /vantage contribute payload: anonymous, evidence-bearing, stable install id
local pay = Vantage.Contribute:BuildPayload()
eq(pay.kind, "vantage-intel", "contribute payload is tagged")
ok(type(pay.uuid) == "string" and #pay.uuid >= 8, "contribute payload carries an install id")
eq(pay.uuid, Vantage:InstallID(), "install id is stable across calls")
eq(pay.count, #pay.spells, "payload count matches the spell list")
local shared
for _, s in ipairs(pay.spells) do if s.id == 9990001 then shared = s end end
ok(shared ~= nil, "learned spell rides along in the contribute payload")
eq(shared and shared.by, "Counterspell", "payload carries the interrupt evidence")
eq(shared and shared.npc, 7053, "payload carries the caster creatureID")
ok(shared.name == nil or shared.name == "Harness Test Cast", "payload keeps the spell name")
local blob = Vantage.Contribute:BuildString()
ok(type(blob) == "string" and blob:find("vantage-intel", 1, true), "payload encodes to a JSON string")
SlashCmdList["VANTAGE"]("contribute") -- smoke: opens the copy window without error

-- 6d. Community pack (redistribution): promoted entries fill gaps, but the
-- curated pack always wins — a community add() can never override a padlock.
ok(Vantage.CommunityPack and Vantage.CommunityPack.add, "community pack exposes add()")
Vantage.CommunityPack.add(88888, "Fake Community Cast")
local cc = Vantage.GetKickInfo("Fake Community Cast", 88888)
ok(cc and cc.interruptible == true and cc.community, "community entry fills an unknown gap as kickable")
Vantage.CommunityPack.add(nil, "Tranquility") -- try to override a curated padlock
local tq = Vantage.GetKickInfo("Tranquility")
ok(tq and tq.interruptible == false and not tq.community, "curated padlock is never overridden by the community pack")
-- A curated padlock is NEVER shadowed or overridden, even if it gets 'interrupted'
-- (e.g. a same-named spell on a different mob that IS kickable).
H.SetCLEU(nil, "SPELL_INTERRUPT", nil, "Player-2-KICKER", "Kickbot", 0x512, 0,
    "Creature-0-8888", "Some Healer", 0x40, 0, 2139, "Counterspell", 0,
    44201, "Tranquility")
H.FireEvent("COMBAT_LOG_EVENT_UNFILTERED")
ok(not (learned and learned["tranquility"]), "curated spells aren't shadowed into the learned table")
local ci = Vantage.GetKickInfo("Tranquility")
ok(ci and ci.interruptible == false, "curated padlock still wins over any learning")
SlashCmdList["VANTAGE"]("learned") -- smoke: prints without error

-- 6e. Community-pack TRUST GRADIENT: a community cast this install has never seen
-- kicked cues QUIET — glow + a tentative "?" label, but NO alert sound — so a rare
-- bad pooled entry can't scream a false INTERRUPT. Witnessing one kick graduates it
-- to the full cue. (Needs a ready, in-range interrupt, same as the step-3 setup.)
Vantage.CommunityPack.add(77777, "Fake Community Nuke")
ok(not Vantage.Learn:IsConfirmed(77777, "Fake Community Nuke"), "a fresh community cast starts unconfirmed")
H.range[cfg.spell] = 1
local sBefore = H.sounds
H.units.nameplate1.casting = { name = "Fake Community Nuke", spellID = 77777,
    startMS = H.now * 1000, endMS = (H.now + 2.5) * 1000 }
H.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
eq(o.active and o.active.code, "ready", "community cast reaches the ready tier")
ok(o.kickF:IsShown(), "unconfirmed community cue shows a label")
eq(o.kickText:GetText(), cfg.label .. "?", "unconfirmed community cue is tentative ('?')")
eq(H.sounds, sBefore, "unconfirmed community cue stays SILENT (no alert)")

-- witness a kick on it (hostile caster, destFlags 0x40) -> locally confirmed
H.SetCLEU(nil, "SPELL_INTERRUPT", nil, "Player-1-ME", "Testchar", 0x511, 0, MOB_GUID,
    "Some Caster", 0x40, 0, 2139, "Counterspell", 0, 77777, "Fake Community Nuke")
H.FireEvent("COMBAT_LOG_EVENT_UNFILTERED")
ok(Vantage.Learn:IsConfirmed(77777, "Fake Community Nuke"), "witnessing a kick confirms it locally")
H.Advance(1.0) -- clear the KICKED flash

-- next cast now earns the full cue: plain label + the alert sound
local sBefore2 = H.sounds
H.units.nameplate1.casting = { name = "Fake Community Nuke", spellID = 77777,
    startMS = H.now * 1000, endMS = (H.now + 2.5) * 1000 }
H.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
eq(o.kickText:GetText(), cfg.label, "confirmed community cue shows the full label (no '?')")
eq(H.sounds, sBefore2 + 1, "confirmed community cue fires the alert")

-- 6f. Diminishing returns: repeated CC of one category makes the next application
-- immune, and TargetSusceptible (so the cue) suppresses that soft stop. Below the
-- immune bar the CC still lands (reduced), so the cue stays.
local DGUID = "Creature-0-DR-TEST-1"
ok(not Vantage:DRImmune(DGUID, "fear"), "no DR before any CC lands")
Vantage:NoteDR(DGUID, "fear"); Vantage:NoteDR(DGUID, "fear")
ok(not Vantage:DRImmune(DGUID, "fear"), "2 applications still land (reduced) -> cue stays")
Vantage:NoteDR(DGUID, "fear")
ok(Vantage:DRImmune(DGUID, "fear"), "3 applications -> next is immune, cue suppressed")
ok(not Vantage:DRImmune(DGUID, "stun"), "DR is per-category: stun unaffected by fear stacks")
Vantage:ClearDR(DGUID)
ok(not Vantage:DRImmune(DGUID, "fear"), "ClearDR (target died / plate gone) resets it")
ok(Vantage:MyCCMechanic("Counterspell") == nil, "a hard kick maps to no DR category")
if Vantage.playerClass == "PRIEST" then
    eq(Vantage:MyCCMechanic("Psychic Scream"), "fear", "your Fear maps to the fear DR category")
elseif Vantage.playerClass == "SHAMAN" then
    ok(Vantage:MyCCMechanic("Earth Shock") == nil, "a hard-kick class exposes no soft DR category")
end

-- 6g. Truthful mid-flight timing + reaction threshold: a cast picked up already
-- deep into its cast shows the REAL remaining time (not the full duration), and —
-- being un-kickable within the reaction window — fires the glow but HOLDS the alert.
H.range[cfg.spell] = 1
local sPre = H.sounds
H.units.nameplate1.casting = { name = "Greater Heal", spellID = 25314,
    startMS = (H.now - 2.4) * 1000, endMS = (H.now + 0.1) * 1000 }  -- 2.5s cast, ~0.1s left
H.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
ok(o.castbar.endTime - H.now < 0.5, "in-progress cast shows true remaining, not full duration")
ok(o.kickF:IsShown(), "late kickable cast still shows the glow")
eq(H.sounds, sPre, "late cast holds the alert (un-kickable in the reaction window)")

-- 6h. Real threat via the embedded LibThreatClassic2 (stubbed here): the amber
-- "about to pull" tier uses actual threat % instead of the damage-tally estimate.
local TE = Vantage.ThreatEst
Vantage.db.threatAmber = true
local mob = H.units.nameplate1
mob.threat = nil
ok(TE:Situation("nameplate1") == nil, "no library data -> Situation nil (damage estimate takes over)")
mob.threat = { isTanking = false, status = 0, pct = 85 }
ok(TE:Closing("nameplate1"), "DPS at 85% of the pull threshold -> closing (amber)")
mob.threat = { isTanking = false, status = 0, pct = 40 }
ok(not TE:Closing("nameplate1"), "DPS at 40% -> not closing yet")
mob.threat = { isTanking = false, status = 1, pct = 60 }
ok(TE:Closing("nameplate1"), "DPS above the tank (status 1) -> closing even under 80%")
mob.threat = { isTanking = true, status = 3, pct = 100 }
ok(not TE:Closing("nameplate1"), "you're already tanking -> not 'closing to pull'")
ok(not TE:RivalClosing("nameplate1"), "tank securely tanking -> no rival warning")
mob.threat = { isTanking = true, status = 2, pct = 100 }
ok(TE:RivalClosing("nameplate1"), "tank INSECURELY tanking (status 2) -> rival closing (amber)")
mob.threat = nil

-- 6i. Threat-strip de-dup: the border already carries the threat color on non-target
-- plates, so the strip (the "line under the bar") shows ONLY on your current target
-- (border = accent there) — unless the skin is off, when the strip carries it.
local prevGroup, prevTarget, prevN1T = H.inGroup, H.alias["target"], H.alias["nameplate1target"]
H.inGroup = true
Vantage.db.threat = true
Vantage.db.skin = true
H.alias["nameplate1target"] = "player"  -- the mob is on YOU -> threatBad color
H.alias["target"] = "nameplate1"         -- ...and it IS your current target
H.Advance(0.3)
ok(o.threatStrip:IsShown(), "strip shows on your current target (border there is the accent)")
H.alias["target"] = "player"             -- no longer your target -> border carries threat
H.Advance(0.3)
ok(not o.threatStrip:IsShown(), "strip hidden on a non-target plate (border carries it)")
Vantage.db.skin = false                  -- no skin -> no colored border, strip must carry it
H.Advance(0.3)
ok(o.threatStrip:IsShown(), "with the skin off, the strip carries threat on non-target plates")
Vantage.db.skin = true
H.alias["nameplate1target"] = prevN1T; H.alias["target"] = prevTarget; H.inGroup = prevGroup
H.Advance(0.3)

-- 6c. Dungeon briefing: zone-in to a tagged instance prints the kick sheet once
local before = #H.printed
H.FireEvent("ZONE_CHANGED_NEW_AREA") -- stub instance = Shadow Labyrinth, party
local briefed, kickLine, lockLine = false, false, false
for i = before + 1, #H.printed do
    local line = H.printed[i]
    if line:find("Briefing") then briefed = true end
    if line:find("Summon Cabal Deathsworn") then kickLine = true end
    if line:find("Sonic Boom") then lockLine = true end
end
ok(briefed, "briefing printed on zone-in")
ok(kickLine, "briefing lists the zone's kick (Summon Cabal Deathsworn)")
ok(lockLine, "briefing lists the zone's padlock (Sonic Boom)")
before = #H.printed
H.FireEvent("ZONE_CHANGED_NEW_AREA")
local rebriefed = false
for i = before + 1, #H.printed do
    if H.printed[i]:find("Briefing") then rebriefed = true end
end
ok(not rebriefed, "same instance visit doesn't re-brief")
SlashCmdList["VANTAGE"]("brief") -- verbose reprint: prints without error
ok(H.printed[#H.printed]:find("%- "), "verbose brief carries note gists")

-- 6d. Party kick watch: a groupmate's witnessed interrupt feeds the cd tier
H.inGroup = true
H.groupSize = 3 -- me + 2 (party tokens exclude yourself)
H.units.party1 = { name = "Grimjaw", className = "Warrior", class = "WARRIOR",
                   guid = "Player-1-GRIM", isPlayer = true, hostile = false }
H.units.party2 = { name = "Luna", className = "Mage", class = "MAGE",
                   guid = "Player-1-LUNA", isPlayer = true, hostile = false }
H.FireEvent("GROUP_ROSTER_UPDATE")
-- witness Grimjaw's Pummel land (0x412 = player + party affiliation + friendly)
H.SetCLEU(nil, "SPELL_CAST_SUCCESS", nil, "Player-1-GRIM", "Grimjaw", 0x412, 0,
    MOB_GUID, "Cabal Acolyte", 0x10a48, 0, 6552, "Pummel", 0)
H.FireEvent("COMBAT_LOG_EVENT_UNFILTERED")
-- your stop goes on cooldown; a kickable cast starts while his Pummel is down too
for spell in pairs(cfg.cooldowns) do H.cooldowns[spell] = { H.now, 60 } end
H.units.nameplate1.casting = {
    name = "Greater Heal", spellID = 25314,
    startMS = H.now * 1000, endMS = (H.now + 30) * 1000,
}
H.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
eq(o.active and o.active.code, "cd", "your stop down -> cd tier")
ok(not o.kickF:IsShown(), "no mate hint while his Pummel is also down")
local soundsBefore = H.sounds
-- 11s later his Pummel is back (the range ticker re-evaluates the live cast)
H.Advance(11)
ok(o.kickF:IsShown(), "mate hint appears once his Pummel is ready")
ok(o.kickIsMate, "hint flagged as a mate hint, not a shout")
eq(o.kickText:GetText(), "GRIMJAW'S PUMMEL", "hint names the player and the tool")
eq(H.sounds, soundsBefore, "mate hint is silent")
-- your stop comes back: the real shout displaces the hint (pop + sound)
for spell in pairs(cfg.cooldowns) do H.cooldowns[spell] = { 0, 0 } end
H.FireEvent("SPELL_UPDATE_COOLDOWN")
ok(o.kickF:IsShown() and not o.kickIsMate, "your ready shout displaces the mate hint")
eq(o.kickText:GetText(), cfg.label, "shout label restored")
eq(H.sounds, soundsBefore + 1, "the shout brings its sound")
-- Grimjaw leaves the group: he can never be hinted again
H.groupSize = 0
H.inGroup = false
H.FireEvent("GROUP_ROSTER_UPDATE")
ok(Vantage.PartyKicks:ReadyMate() == nil, "ex-groupmates are never hinted")
-- wind the cast down cleanly so later sections start from a quiet plate
H.units.nameplate1.casting = nil
H.FireEvent("UNIT_SPELLCAST_STOP", "nameplate1")

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
local o2 = Vantage.plates.nameplate2
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
local o3 = Vantage.plates.nameplate3
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
ok(uf1.__vantageBite ~= nil and uf1.__vantageBiteTex:IsShown(), "bite live and coalesced")
H.Advance(0.6)
ok(uf1.__vantageBite == nil and not uf1.__vantageBiteTex:IsShown(), "bite faded and retired")

ok(uf1.__vantageExec and uf1.__vantageExec:IsShown(), "execute tick shown")
ok(uf1.__vantageExec.__vg > 0.9, "execute tick quiet above 20%")
hb1:SetValue(15)              -- into execute range
ok(uf1.__vantageExec.__vg < 0.5, "execute tick lit below 20%")

H.FireEvent("PLAYER_TARGET_CHANGED") -- target is nameplate1
eq(uf2.__alpha, 0.5, "non-target plate faded to focusAlpha")
eq(uf1.__alpha, 1, "target plate at full opacity")
eq(o2.__alpha, 0.5, "non-target cast overlay faded too")

-- Aggro display. SOLO: silent even when a mob is on you (it always is).
H.alias.nameplate2target = "player" -- the mob is targeting me
H.FireEvent("UNIT_THREAT_LIST_UPDATE")
H.Advance(0.3)
local b2 = uf2.__vantageBorder.edges[1]
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
local b1 = uf1.__vantageBorder.edges[1]
ok(b1.__vg and b1.__vg > 0.5, "target keeps accent border over threat")

-- mob switches to a groupmate -> red clears (dps mode: not your problem)
H.alias.nameplate2target = nil
H.FireEvent("UNIT_THREAT_LIST_UPDATE")
H.Advance(0.3)
ok(b2.__vr == 0 and b2.__vg == 0, "border clears when the mob leaves you")
bc = uf2.healthBar.__barcolor
ok(bc and bc[3] > bc[1], "tank's mob -> cool slate BAR (calm is never red-family)")

-- amber tier: my damage closes in on the holder's modeled 1.3x threshold
H.alias.nameplate2target = "party1" -- Grimjaw holds the mob
H.SetCLEU(nil, "SPELL_DAMAGE", nil, "Player-1-GRIM", "Grimjaw", 0x412, 0,
    "Creature-0-2222", "Murmur", 0x10a48, 0, 7386, "Sunder Armor", 1, 1000)
H.FireEvent("COMBAT_LOG_EVENT_UNFILTERED")
H.SetCLEU(nil, "SPELL_DAMAGE", nil, "Player-1-ME", "Testchar", 0x511, 0,
    "Creature-0-2222", "Murmur", 0x10a48, 0, 25457, "Big Nuke", 8, 1200)
H.FireEvent("COMBAT_LOG_EVENT_UNFILTERED")
H.Advance(0.3)
bc = uf2.healthBar.__barcolor
ok(bc and bc[3] > bc[1], "1.2x the holder's damage: still calm (under 1.3x)")
H.SetCLEU(nil, "SPELL_DAMAGE", nil, "Player-1-ME", "Testchar", 0x511, 0,
    "Creature-0-2222", "Murmur", 0x10a48, 0, 25457, "Big Nuke", 8, 200)
H.FireEvent("COMBAT_LOG_EVENT_UNFILTERED")
H.Advance(0.3)
bc = uf2.healthBar.__barcolor
ok(bc and bc[1] > 0.9 and bc[2] > 0.5 and bc[2] < 0.9,
   "1.4x the holder's damage: AMBER bar (closing in, not yet red)")
ok(not o2.threatStrip:IsShown(), "amber strip de-duped on the non-target plate (the bar/border carries it)")
-- the red ground truth always outranks the estimate
H.alias.nameplate2target = "player"
H.FireEvent("UNIT_THREAT_LIST_UPDATE")
H.Advance(0.3)
bc = uf2.healthBar.__barcolor
ok(bc and bc[1] == 1 and bc[2] < 0.4, "mob turns to me: alarm red wins over amber")
-- combat ends: the tally book wipes, no stale amber next pull
H.FireEvent("PLAYER_REGEN_ENABLED")
H.alias.nameplate2target = "party1"
H.FireEvent("UNIT_THREAT_LIST_UPDATE")
H.Advance(0.3)
bc = uf2.healthBar.__barcolor
ok(bc and bc[3] > bc[1], "fresh combat: tallies wiped, calm again")

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
ok(uf2.__vantageHover:IsShown(), "hover wash on mouseover plate")
H.alias.mouseover = nil
H.Advance(0.4)
ok(not uf2.__vantageHover:IsShown(), "hover wash retired when mouse leaves")

-- 12. Plate despawn releases cleanly; slash commands and export run
-- 12a. First: a duplicate ADDED (missed REMOVED) must release the stale
-- overlay instead of leaking it as a ghost bar
local oGhost = Vantage.plates.nameplate1
oGhost:ShowCast("Ghost Cast", nil, 3)
ok(oGhost.castbar:IsShown(), "setup: stale cast showing before duplicate ADDED")
H.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
local oFresh = Vantage.plates.nameplate1
ok(oFresh ~= nil and not oFresh.castbar:IsShown(),
    "duplicate ADDED releases the stale overlay (no ghost cast bar)")

H.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
ok(Vantage.plates.nameplate1 == nil, "overlay released on plate removal")

SlashCmdList["VANTAGE"]("check")
SlashCmdList["VANTAGE"]("parse")
SlashCmdList["VANTAGE"]("test")   -- demo on target (nameplate1 is gone; target alias too)
H.alias.target = "nameplate2"
SlashCmdList["VANTAGE"]("test")

local export = Vantage.ParseExport:BuildExport()
ok(type(export) == "string" and export:find('"sessions"', 1, true) ~= nil, "export builds JSON")
ok(export:find('"miss":true', 1, true) ~= nil, "export contains the let-through row")
ok(export:find('"roster"', 1, true) ~= nil and export:find("Kickbot", 1, true) ~= nil,
    "export carries the roster profiles")

-- plate inspector (/vantage plate): dumps the frame tree with parentKeys
local dump = Vantage.Inspect:DumpPlate(H.units.nameplate2.plate)
ok(dump:find("healthBar", 1, true) ~= nil, "inspector dump names the health bar")
ok(dump:find("[border]", 1, true) ~= nil, "inspector dump names the border art")
ok(dump:find("[LevelFrame]", 1, true) ~= nil, "inspector dump names the level frame")

-- 12b. Smarter multi-cast cue: two casters casting kickable spells at once — you
-- can only stop one, so only the HIGHER-priority cast keeps the full shout; the
-- lower one stays kickable-colored but quiet, pointing you at the right kick.
Vantage.Kickable.byID[770001] = { name = "Weak Kickable", interruptible = true, priority = 2 }
Vantage.Kickable.byID[770002] = { name = "Vital Kickable", interruptible = true, priority = 9 }
spawnMob("nameplate3", "Caster A", { guid = "Creature-0-3333" })
spawnMob("nameplate4", "Caster B", { guid = "Creature-0-4444" })
H.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate3")
H.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate4")
local oA, oB = Vantage.plates.nameplate3, Vantage.plates.nameplate4
H.range[cfg.spell] = 1
H.units.nameplate3.casting = { name = "Weak Kickable", spellID = 770001,
    startMS = H.now * 1000, endMS = (H.now + 3) * 1000 }
H.FireEvent("UNIT_SPELLCAST_START", "nameplate3")
ok(oA.kickF:IsShown(), "a lone kickable cast shouts (top priority so far)")
H.units.nameplate4.casting = { name = "Vital Kickable", spellID = 770002,
    startMS = H.now * 1000, endMS = (H.now + 3) * 1000 }
H.FireEvent("UNIT_SPELLCAST_START", "nameplate4")
ok(oB.kickF:IsShown(), "the higher-priority cast shouts")
H.Advance(0.3) -- the range ticker re-evaluates the now-outranked cast
ok(not oA.kickF:IsShown(), "the lower-priority cast goes quiet — kick the vital one first")
Vantage.db.kickPriority = false -- opt out -> every kickable cast shouts again
H.Advance(0.3)
ok(oA.kickF:IsShown(), "with prioritization off, every kickable cast shouts")
Vantage.db.kickPriority = true

-- 12c. Shareable Intel Packs: export self-learned kicks to a string; import merges
-- (curated/community always win; garbage is rejected).
Vantage.db.learn = true
Vantage.Learn:Import("Shared Test Cast", 990002, "Auchindoun")  -- seed a learned entry
local packStr = Vantage.IntelPack:BuildString()
ok(packStr:find("^VTGPACK1"), "pack string carries the header")
ok(packStr:find("Shared Test Cast", 1, true) ~= nil, "pack string includes a learned cast")
VantageLearnedDB.spells["shared test cast"] = nil   -- forget it locally
VantageLearnedDB.count = VantageLearnedDB.count - 1
ok(Vantage.GetKickInfo("Shared Test Cast", 990002) == nil, "cast is unknown before import")
local added, skipped, okFlag = Vantage.IntelPack:Import(packStr)
ok(okFlag and added >= 1, "import parsed the header and added at least one cast")
local gi = Vantage.GetKickInfo("Shared Test Cast", 990002)
ok(gi and gi.interruptible == true, "imported cast now resolves as kickable")
local a2 = Vantage.IntelPack:Import(packStr)
eq(a2, 0, "re-importing an already-known pack adds nothing (idempotent)")
Vantage.IntelPack:Import("VTGPACK1;44201~Tranquility~Karazhan")  -- try to import a curated padlock
local tq = Vantage.GetKickInfo("Tranquility")
ok(tq and tq.interruptible == false, "import never overrides a curated padlock")
local _, _, badok = Vantage.IntelPack:Import("not a pack string")
ok(badok == false, "garbage input is rejected, not merged")

-- 13. Options interactions: toggle every checkbox + run reset
for _, f in ipairs(H.frames) do
    if f.__kind == "CheckButton" and f.__scripts.OnClick then
        f.__checked = not f.__checked
        f:Click()
    end
end
SlashCmdList["VANTAGE"]("help")

-- ---------------------------------------------------------------------------
-- Report
-- ---------------------------------------------------------------------------
if #failures > 0 then
    error(("%d/%d checks failed [%s]:\n  - %s"):format(
        #failures, checks, cfg.class, table.concat(failures, "\n  - ")), 0)
end
return ("%d checks passed [%s]"):format(checks, cfg.class)
