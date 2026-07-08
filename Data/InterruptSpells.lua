-- Vantage/Data/InterruptSpells.lua
--
-- Your interrupts, by class, and the logic that answers: "can I stop this cast
-- RIGHT NOW?" Works for EVERY class, not just the kick classes. Entries can be
-- HARD interrupts (true school-lockout kicks/silences) or SOFT ones (stuns, fears,
-- disorients, sleeps, incapacitates that also stop a cast). Each carries a label
-- shown on the cue, plus optional gates:
--   soft         = not a clean school-lockout kick — still stops the cast.
--   mechanic     = the CC school of a SOFT stop (stun/fear/sleep/incapacitate/disorient/
--                  root) — used to suppress the cue vs targets IMMUNE to it (see
--                  Immunities.lua). Hard kicks carry no mechanic and are never suppressed.
--   requiresType = only offered vs that creature type (UnitCreatureType); a string,
--                  or a list of strings (e.g. {"Undead","Demon"}).
--   form         = only usable in this GetShapeshiftForm() index (Warrior 3 = Berserker,
--                  Druid 1 = Bear). forms = a list of allowed indices (Shield Bash {1,2}).
--   needsShield  = an actual shield must be in the off-hand (Shield Bash).
--   pet+petFamily= a PET ability (Warlock Spell Lock): readiness comes from the pet
--                  action bar, not the player spellbook, and the right pet must be out.
--   needsPet     = a player-cast ability the pet executes (Hunter Intimidation).
--   needsCombo   = requires combo points on your target (Rogue Kidney Shot).
--
-- Readiness for normal entries is GetSpellCooldown(name): nil if the spell isn't in
-- your spellbook, so the cue auto-"turns on" as you learn/spec abilities (e.g. a
-- Priest gains FEAR at ~level 14). Pet abilities are read from the pet bar instead
-- (GetSpellCooldown can't see them). Listed best-first; Vantage uses the first one you
-- know that's ready and gate-valid.
local addonName, Vantage = ...

Vantage.ClassInterrupts = {
    WARRIOR = {
        { spell = "Pummel",          label = "PUMMEL",      soft = false, form = 3 },                          -- Berserker stance only
        { spell = "Shield Bash",     label = "SHIELD BASH", soft = false, forms = { 1, 2 }, needsShield = true }, -- Battle/Defensive + shield
        { spell = "Concussion Blow", label = "STUN",        soft = true,  mechanic = "stun" },                 -- deep Prot talent; auto-skips if untalented
    },
    ROGUE = {
        { spell = "Kick",        label = "KICK",  soft = false },                                              -- baseline school lockout, no talent needed
        { spell = "Gouge",       label = "GOUGE", soft = true, mechanic = "incapacitate" },
        { spell = "Kidney Shot", label = "STUN",  soft = true, mechanic = "stun", needsCombo = true },
    },
    MAGE = {
        { spell = "Counterspell",    label = "COUNTER", soft = false },                                        -- baseline 8s lockout
        { spell = "Dragon's Breath", label = "BREATH",  soft = true, mechanic = "disorient" },                -- Fire talent
    },
    SHAMAN = {
        { spell = "Earth Shock", label = "SHOCK", soft = false },                                              -- the TBC shaman interrupt (NOT Wind Shear)
    },
    WARLOCK = {
        { spell = "Spell Lock", label = "SPELL LOCK", soft = false, pet = true, petFamily = "Felhunter" },     -- Felhunter pet ability (real lockout)
        { spell = "Shadowfury", label = "STUN",       soft = true, mechanic = "stun" },                        -- Destruction talent
        { spell = "Death Coil", label = "HORROR",     soft = true, mechanic = "fear" },                        -- baseline fallback (~2min CD)
    },
    HUNTER = {
        { spell = "Intimidation", label = "STUN",    soft = true, mechanic = "stun",      needsPet = true },   -- Beast Mastery talent (the pet stuns)
        { spell = "Scatter Shot", label = "SCATTER", soft = true, mechanic = "disorient" },                    -- Marksmanship talent
    },
    DRUID = {
        { spell = "Bash",         label = "BASH",   soft = true, mechanic = "stun", form = 1 },                -- Bear form only
        { spell = "Feral Charge", label = "CHARGE", soft = true, mechanic = "root", form = 1 },                -- Bear form only; interrupts (no school lock)
    },
    PALADIN = {
        { spell = "Hammer of Justice", label = "STUN",   soft = true, mechanic = "stun" },                     -- universal, all specs
        { spell = "Repentance",        label = "REPENT", soft = true, mechanic = "incapacitate", requiresType = "Humanoid" }, -- Ret talent; Humanoid-only in TBC
    },
    PRIEST = {
        { spell = "Silence",        label = "SILENCE", soft = false },                                         -- Shadow talent: a true silence
        { spell = "Shackle Undead", label = "SHACKLE", soft = true, mechanic = "incapacitate", requiresType = "Undead" },
        { spell = "Psychic Scream", label = "FEAR",    soft = true, mechanic = "fear" },                       -- fears the caster -> stops the cast
    },
    -- Note: Hunter / Paladin / Druid (and non-Shadow Priest) have NO hard school-lockout
    -- kick in TBC — their cue is honest about being a SOFT stop (stun/fear/disorient).
}

-- Number of pet action-bar slots to scan.
local NUM_PET_SLOTS = NUM_PET_ACTION_SLOTS or 10

-- Pet-bar readiness for pet=true entries (Warlock Spell Lock). GetSpellCooldown by
-- NAME only searches the PLAYER spellbook, so a pet ability reads nil there — we scan
-- the pet action bar instead, which also proves the right pet is summoned and alive.
-- Returns start, duration (start == 0 => ready), or nil if the pet doesn't have it.
local function GetPetSpellCooldown(name)
    if not UnitExists("pet") or UnitIsDead("pet") then return nil end
    for i = 1, NUM_PET_SLOTS do
        local n, _, isToken = GetPetActionInfo(i)
        if isToken and n then n = _G[n] end          -- resolve token -> localized name
        if n == name then
            return GetPetActionCooldown(i)           -- start, duration, enable
        end
    end
    return nil
end
Vantage.GetPetSpellCooldown = GetPetSpellCooldown

-- True only when an actual shield occupies the off-hand (slot 17) — Shield Bash gate.
local function HasShield()
    local link = GetInventoryItemLink("player", 17)
    if not link then return false end
    local _, _, _, _, _, _, _, _, loc = GetItemInfo(link)
    return loc == "INVTYPE_SHIELD"
end

-- requiresType: a single creature type or a list of them.
local function typeOK(e, unit)
    if not e.requiresType then return true end
    if not unit then return false end
    local t = UnitCreatureType(unit)
    if type(e.requiresType) == "table" then
        for _, v in ipairs(e.requiresType) do
            if v == t then return true end
        end
        return false
    end
    return t == e.requiresType
end

-- Is this ONE entry usable right now: known, off cooldown, and all of its gates
-- (creature type / stance / form / shield / pet / combo) satisfied?
function Vantage:EntryReady(e, unit)
    if not typeOK(e, unit) then return false end
    -- soft CC is wasted on an immune target — suppress the cue there (fail-open if the
    -- immunity layer somehow didn't load). Hard kicks carry no mechanic and skip this.
    if e.soft and Vantage.TargetSusceptible and not Vantage:TargetSusceptible(unit, e.mechanic) then
        return false
    end

    -- readiness source: the pet bar for pet abilities, else the player spellbook.
    -- The pet-bar scan is self-gating — Spell Lock only exists on a Felhunter's bar,
    -- so a wrong/absent pet just returns nil (no extra creature-family check needed).
    local start, duration
    if e.pet then
        start, duration = GetPetSpellCooldown(e.spell)
    else
        start, duration = GetSpellCooldown(e.spell)
    end
    if start == nil then return false end            -- not learned / pet lacks it

    duration = duration or 0
    -- interrupts are off the GCD, so a <=1.5s "cooldown" is the GCD bleed, not a real CD
    local ready = (start == 0) or (duration <= 1.5) or ((start + duration - GetTime()) <= 0)
    if not ready then return false end

    -- declared gates (only checked when the entry carries them)
    if e.form and GetShapeshiftForm() ~= e.form then return false end
    if e.forms then
        local f, ok = GetShapeshiftForm(), false
        for _, v in ipairs(e.forms) do if f == v then ok = true; break end end
        if not ok then return false end
    end
    if e.needsShield and not HasShield() then return false end
    if e.needsPet and (not UnitExists("pet") or UnitIsDead("pet")) then return false end
    if e.needsCombo and (GetComboPoints("player", "target") or 0) <= 0 then return false end

    return true
end

-- Range: IsSpellInRange knows each spell's REAL range (melee for Kick/Pummel,
-- 8yd for Psychic Scream, 30yd for Counterspell, ...). Returns true / false, or
-- nil when the API can't answer — pet abilities (Spell Lock) live outside the
-- player spellbook, and some spells just report nil. Callers must treat nil as
-- "don't suppress": we only ever mute the cue on an EXPLICIT out-of-range.
function Vantage:EntryInRange(e, unit)
    if not unit or e.pet or not IsSpellInRange then return nil end
    local r = IsSpellInRange(e.spell, unit)
    if r == 1 then return true elseif r == 0 then return false end
    return nil
end

-- Returns the best ready interrupt ENTRY for `unit`, plus whether it's in range:
--   entry, true   -> usable RIGHT NOW (in range, or range unknowable)
--   entry, false  -> ready, but every ready option is out of range (move closer)
--   nil           -> nothing ready
-- Prefers an in-range entry over an earlier out-of-range one, so a Rogue too far
-- for Kick still gets an in-range alternative when one exists.
function Vantage:GetReadyInterrupt(unit)
    local list = self.ClassInterrupts[self.playerClass]
    if not list then return nil end
    local tooFar
    for i = 1, #list do
        local e = list[i]
        if self:EntryReady(e, unit) then
            if self.db.rangeCheck == false or self:EntryInRange(e, unit) ~= false then
                return e, true
            end
            tooFar = tooFar or e
        end
    end
    if tooFar then return tooFar, false end
    return nil
end

-- Is `name` one of YOUR class's interrupt tools? (CastWatch uses this to spot
-- a kick you just spent on a cast marked do-not-kick.)
function Vantage:IsMyInterrupt(name)
    local list = self.ClassInterrupts[self.playerClass]
    if not list then return false end
    for i = 1, #list do
        if list[i].spell == name then return true end
    end
    return false
end

-- Do we have ANY interrupt that could work on `unit` — learned (or on a summoned pet),
-- type-valid, and the target not immune to its mechanic? Ignores cooldown/stance, so it
-- distinguishes "on cooldown" (muted cue) from "nothing of mine can stop this" (awareness
-- only). `unit` is optional (nil = ignore type/immunity, used by the demo).
function Vantage:HasInterrupt(unit)
    local list = self.ClassInterrupts[self.playerClass]
    if not list then return false end
    for i = 1, #list do
        local e = list[i]
        local ccOK = (not e.soft) or (not Vantage.TargetSusceptible) or Vantage:TargetSusceptible(unit, e.mechanic)
        if typeOK(e, unit) and ccOK then
            local learned
            if e.pet then learned = (GetPetSpellCooldown(e.spell) ~= nil)
            else learned = (GetSpellCooldown(e.spell) ~= nil) end
            if learned then return true end
        end
    end
    return false
end
