-- Vantage/Data/KickableSpells.lua
--
-- The "Intel Pack": which enemy casts matter, and whether they can be interrupted.
-- This is the heart of Vantage's accuracy. Interruptibility is classified from THIS
-- table, NOT the client's unreliable `notInterruptible` return.
--
-- v0.2.4: TBC heroics + Karazhan + Gruul/Magtheridon, plus full SERPENTSHRINE CAVERN
-- + TEMPEST KEEP (Tier 5 — the live Anniversary raid tier). Built and adversarially
-- fact-checked against Wowhead TBC / warcraft.wiki / wowpedia / TBC bug trackers.
-- KEY SSC finding: the ONLY genuinely kickable SSC boss-encounter cast is Caribdis's
-- Healing Wave; nearly every other boss "cast" that looks kickable is a padlock, and
-- the high-value SSC/TK kicks are on TRASH healers.
-- Matched by spell NAME (lowercased); verified spellIDs are in `byID` (checked first).
-- `interruptible = false` entries are intentional "do-not-kick" markers (padlock).
--
-- NEEDS-REVIEW entries (low-confidence or interruptible-varies-by-mob) are listed
-- commented-out at the bottom. Uncomment to activate after verifying in-game.
--
-- TODO(content): Zul'Aman, Hyjal, Black Temple, Sunwell; ship as importable Intel
-- Pack strings.
local addonName, Vantage = ...

local byName = {
    -- heal
    ["dark mending"] = { castTime = 2, interruptible = true, priority = 5, category = "heal", zones = { "magtheridon's lair" }, note = "Channeler self/cross-heal (~69-80k), 2s cast - must be kicked every cast or channelers never die. Assign 2 interrupters per channeler (Dark Mending + Shadow Bolt Volley come back-to-back). spellID 30528 verified." },
    ["greater heal"] = { castTime = 3, interruptible = true, priority = 5, category = "heal", zones = { "serpentshrine cavern", "tempest keep", "the botanica" }, note = "Large single-target heal - TOP kick target everywhere it appears (2-3.5s cast, interruptible). SSC/TK casters: Coilfang Priestess (~40-50k heal), Bloodwarder Mender, Sister of Pleasure, Solarium Priest (heals Solarian on spawn - kick+stun or she resets). EXCEPTIONS: Coilfang Priestess keeps healing ~15s in Spirit of Redemption on death; Sister of Pleasure is kick-immune under her Shell of Life (kill/purge first); instant shields/Holy Nova are not cast-interruptible." },
    ["heal"] = { castTime = 2.5, interruptible = true, priority = 5, category = "heal", zones = { "gruul's lair" }, note = "Merged generic single-target Heal across many healer mobs/bosses; all verified interruptible. Cast time varies 1.6-3.5s by mob. CAVEAT: Blindeye becomes interrupt-IMMUNE while his Greater PW:Shield is up (silence-type interrupts still land). Top kick target wherever it appears." },
    ["healing wave"] = { castTime = 1.5, interruptible = true, priority = 5, category = "heal", zones = { "serpentshrine cavern" }, note = "The single most important kick in SSC. ~Every 15s, heals >100k with NO LoS/range limit (heals all 4 bosses anywhere). Dedicated interrupt rotation required; Curse of Tongues / Mind-numbing Poison helps." },
    ["holy light"] = { castTime = 2.5, interruptible = true, priority = 5, category = "heal", zones = { "old hillsbrad foothills" }, note = "Big paladin/healer heal, verified interruptible by kick/Counterspell/Pummel. Note Skarloc cannot be Silenced (use a hard kick)." },
    ["prayer of healing"] = { castTime = 3, interruptible = true, priority = 5, category = "heal", note = "AoE group heal (~5k / tops off a pack). Top interrupt priority. Same healers' Renew is instant and not interruptible." },
    ["repair"] = { castTime = 0, interruptible = true, priority = 5, category = "heal", zones = { "the steamvault" }, note = "CHANNELED repair (~1050/2s on the boss). Breaks on ANY damage to the mechanic (kick, stun, or just hitting it). Adds spawn at 75/50/25%." },
    ["bandage"] = { castTime = 1, interruptible = true, priority = 4, category = "heal", zones = { "the mechanar" }, note = "1s CAST heal-over-time (~1200/8s), NOT a channel - a kick stops the cast. Physician also has Anesthetic (sleep) and Holy Shock (heroic). spellID 38919 verified." },
    ["eternal affection"] = { castTime = 2, interruptible = true, priority = 4, category = "heal", zones = { "karazhan" }, note = "Julianne's ~2s Holy heal (46k-54k) - top interrupt priority. She is immune to Silence but NOT to Kick/Shield Bash/Wind Shear." },
    ["tranquility"] = { castTime = 0, interruptible = false, priority = 4, category = "heal", zones = { "the botanica", "serpentshrine cavern" }, note = "DO NOT KICK - channeled AoE heal, uninterruptible on both known casters: Freywinn (Botanica, Tree Form / damage-immune, stopped only by killing the 3 Frayer Protectors) and Tidewalker Depth-Seer (SSC murloc, chaincasts at low HP - DPS through it). Marker so the addon won't suggest a wasted kick." },
    ["flash of light"] = { castTime = 1.5, interruptible = false, priority = 2, category = "heal", zones = { "tempest keep" }, note = "DO NOT KICK - verified un-interruptible on every known caster; DPS them down. TK: Bloodwarder Vindicator/Squire & Crimson Hand Blood Knights cast a kick-IMMUNE Flash of Light that heals only ~3% HP (their Cleanse / Hammer of Justice are separate instant casts). Marker so the addon won't recommend a wasted kick." },
    ["healing touch"] = { castTime = 3.5, interruptible = true, priority = 4, category = "heal", zones = { "serpentshrine cavern", "karazhan" }, note = "Big single-target heal, interruptible. Casters: Tidewalker Depth-Seer (SSC murloc, ~12k heal - KICK this; only its Tranquility resists) and Spectral Chargers/Stallions (Karazhan). Kick on sight." },

    -- cc
    ["polymorph"] = { castTime = 1.5, interruptible = true, priority = 4, category = "cc", note = "Enemy sheep CC - interrupt to stop it. EXCEPTION: Talon King Ikiss (Sethekk) shows a cast bar but is IMMUNE to interrupt (dispel/damage instead). Defaulting to kickable for the common case; promoted from needs-review." },
    ["cyclone of feathers"] = { castTime = 1.5, interruptible = true, priority = 5, category = "cc", note = "Has a cast bar, verified interruptible. Cyclones a player (invulnerable, no actions) ~6s - kick to keep DPS/healer active." },
    ["domination"] = { castTime = 3, interruptible = true, priority = 5, category = "cc", zones = { "the blood furnace", "the mechanar" }, note = "Mind-control on a party member - a top-tier stop (MC'd player on the healer can wipe). The Maker's is verified interruptible/#1 priority. CAVEATS: Soothsayer cast-bar behavior in 2.5.x unverified; Pathaleon spell 35280, but a single ID can't cover all four mobs so spellID omitted. PvP trinket also breaks the MC." },
    ["fear"] = { castTime = 1.5, interruptible = true, priority = 4, category = "cc", zones = { "sethekk halls" }, note = "Warlock-style trash Fears (Darkcaster, Sethekk Prophet) are verified interruptible 1.5s casts - dangerous because feared players pull extra packs. CAVEAT: boss/AoE-fear variants (O'mrogg, Siren, channeler) are NOT firmly confirmed interruptible and some are treated as instant - verify in-game; keep Fear Ward/Tremor as backup." },
    ["impending coma"] = { castTime = 1.5, interruptible = true, priority = 3, category = "cc", note = "Sleep/slow (often on the tank). Can be interrupted OR cleansed (poison). Greenkeepers come in pairs. Cast time approximate." },
    ["paralyzing screech"] = { castTime = 5, interruptible = false, priority = 1, category = "cc", note = "DO NOT KICK - 5s cast, AoE 6s stun, cannot be interrupted by any means. Marker so players don't waste a kick." },

    -- summon
    ["summon cabal deathsworn"] = { castTime = 2, interruptible = true, priority = 5, category = "summon", zones = { "shadow labyrinth" }, note = "Top interrupt priority on the pull to avoid being overrun by adds. spellID 33506 verified (single source)." },
    ["summon arcane golem"] = { castTime = 2, interruptible = true, priority = 4, category = "summon", zones = { "the botanica" }, note = "Summons add(s); interrupt to prevent the extra mob. Netherbinder also has Arcane Nova/Starfire/Dispel Magic. spellID 35251 verified (single source)." },
    ["summon fiendish hound"] = { castTime = 2, interruptible = true, priority = 4, category = "summon", note = "Summons hounds that then Spell Lock and drain. Interrupt to deny the add. Cast time approximate." },
    ["summon ethereal wraith"] = { castTime = 2, interruptible = true, priority = 3, category = "summon", zones = { "mana-tombs" }, note = "Summon add; interrupt to avoid being overrun. Spellbinder also has Counterspell and Immolate." },
    ["summon felhound manastalker"] = { castTime = 2, interruptible = true, priority = 3, category = "summon", note = "Summons extra adds (also Summon Seductress); interrupt to control add count." },

    -- nuke
    ["lightning bolt"] = { castTime = 2.5, interruptible = true, priority = 3, category = "nuke", note = "Common caster/shaman nuke - interruptible in the overwhelming majority of cases (trash, world mobs near Org, leveling). EXCEPTION: Mennu the Betrayer (Slave Pens) grounds/reflects it. Defaulting to kickable since the common case dominates; promoted from needs-review." },
    ["arcane missiles"] = { castTime = 5, interruptible = true, priority = 5, category = "nuke", zones = { "karazhan" }, note = "THE kick target on Aran - 5s channel, ~6300-7700 arcane. Interrupt until he runs dry. WARNING: his raid-wide Counterspell (10s lockout, all within 10yd) punishes melee positioning." },
    ["blast nova"] = { castTime = 0, interruptible = false, priority = 5, category = "nuke", zones = { "magtheridon's lair" }, note = "DO NOT KICK - raid-wide channel (~10s) every ~50-60s, stopped ONLY by 5 players channeling the Manticron Cubes. Correctly flagged uninterruptible so the addon never prompts a kick. spellID 30616 verified." },
    ["pyroblast"] = { castTime = 4, interruptible = true, priority = 5, category = "nuke", zones = { "tempest keep", "the black morass" }, note = "Massive fire nuke (~50k on Kael, near one-shot). Interruptible EXCEPT while Kael's Shock Barrier is up (burn the barrier, then kick the Pyroblasts). Rift Keeper's version is a slow ~6s cast - easy kick." },
    ["shadow bolt volley"] = { castTime = 2.5, interruptible = true, priority = 5, category = "nuke", zones = { "the blood furnace", "magtheridon's lair" }, note = "Party/raid-wide shadow AoE. Generally interruptible. CAVEAT: Keli'dan's version is poorly documented and some report resists (verify). Conflicting NPC spellIDs exist (channeler 30510 vs others 39175) so spellID omitted on this merge." },
    ["arcane lightning"] = { castTime = 2.5, interruptible = true, priority = 4, category = "nuke", note = "Name corrected from Chain Lightning. Arcs to up to 5 targets and SILENCES for 4s (locks out healers) - priority interrupt." },
    ["shadow bolt"] = { castTime = 2.5, interruptible = true, priority = 4, category = "nuke", note = "Common single-target shadow nuke, verified interruptible everywhere. Cast 2.5-3s. Channelers also apply Mark of Shadow." },
    ["chain lightning"] = { castTime = 2.5, interruptible = true, priority = 3, category = "nuke", zones = { "sethekk halls", "karazhan" }, note = "Multi-target nature nuke, interruptible on Syth and The Crone. CAVEAT: The Black Stalker's (boss, p4) interruptibility is NOT confirmed by any source - do not rely on a kick landing there." },
    ["fireball"] = { castTime = 2.5, interruptible = true, priority = 3, category = "nuke", note = "Hard-cast fire nuke, verified interruptible. CAVEATS: Kael'thas is interrupt-IMMUNE while Shock Barrier is up; Shade of Aran's is deliberately left uninterrupted (mana burn)." },
    ["flamestrike"] = { castTime = 3, interruptible = true, priority = 3, category = "nuke", note = "Ground AoE fire, high interrupt priority on the pull. Cast time approximate." },
    ["frostbolt"] = { castTime = 3, interruptible = true, priority = 3, category = "nuke", note = "Hard-cast frost nuke + slow, verified interruptible. STRATEGY: on Shade of Aran intentionally leave it UNINTERRUPTED so he burns mana; only kick his Arcane Missiles." },
    ["rain of fire"] = { castTime = 0, interruptible = true, priority = 3, category = "nuke", note = "CHANNELED ground AoE (castTime 0 = channel); a kick/stun stops the channel." },
    ["solarburn"] = { castTime = 2, interruptible = true, priority = 3, category = "nuke", zones = { "the mechanar" }, note = "Fire damage + DoT, interruptible. Astromage also has Scorch and Fire Shield." },
    ["arcane bolt"] = { castTime = 2.5, interruptible = true, priority = 2, category = "nuke", zones = { "the black morass" }, note = "Interruptible nuke; reduces incoming damage during portal defense. Also Arcane Explosion in melee." },
    ["arcane flurry"] = { castTime = 0, interruptible = false, priority = 2, category = "nuke", note = "DO NOT KICK - immune to stun/silence/interrupt; damaging arcane aura (~10s). Susceptible to Polymorph/Incapacitate/Disorient - Poly it pre-pull. Marker so the addon won't suggest a kick." },
    ["blizzard"] = { castTime = 0, interruptible = true, priority = 2, category = "nuke", note = "CHANNELED AoE rain (no cast bar); a kick/stun ends the channel. Low priority unless the group is standing in it." },
    ["firebolt"] = { castTime = 1.5, interruptible = true, priority = 2, category = "nuke", note = "Small fire nuke, interruptible but usually AoE'd down rather than kicked - low individual value." },
    ["frostbolt volley"] = { castTime = 3, interruptible = true, priority = 2, category = "nuke", note = "AoE frost nuke, interruptible; worth kicking on hard pulls. Mob also has Blizzard and Cone of Cold." },
    ["greater fireball"] = { castTime = 3, interruptible = true, priority = 2, category = "nuke", zones = { "gruul's lair" }, note = "~9k fire nuke, 3s cast, technically interruptible. In practice Krosh is tanked by a Spellsteal mage who deliberately does NOT kick it - keep priority low. His Blast Wave is instant, not a kick target." },
    ["holy fire"] = { castTime = 2, interruptible = true, priority = 2, category = "nuke", zones = { "karazhan" }, note = "Direct fire damage + DoT, interruptible. On Catriona her Greater Heal is the real priority (kick that first). CAVEAT: Maiden's 1s-cast version is hard to kick and her DoT is usually dispelled rather than interrupted - low value there." },
    ["sonic boom"] = { castTime = 1.5, interruptible = false, priority = 2, category = "nuke", zones = { "shadow labyrinth" }, note = "DO NOT KICK - telegraphed run-out/LoS mechanic, treated as uninterruptible in practice. Marker so players don't burn a kick." },

    -- other
    ["mana burn"] = { castTime = 3, interruptible = true, priority = 4, category = "other", note = "Drains a healer's mana - high priority to stop. EXCEPTION: Skyriss (Arcatraz) Mana Burn is NOT interruptible. Defaulting to kickable for the common case; promoted from needs-review." },
    ["mark of shadow"] = { castTime = 2, interruptible = true, priority = 3, category = "other", note = "Marks a player for +shadow damage taken (~2 min); dispellable. Interrupt if available, else dispel." },
    ["mind flay"] = { castTime = 0, interruptible = true, priority = 2, category = "other", note = "CHANNELED snare + shadow damage; interrupting ends the channel. Its Shadow Word: Pain is instant and not interruptible." },
    ["blade dance"] = { castTime = 0, interruptible = false, priority = 1, category = "other", zones = { "the shattered halls" }, note = "DO NOT KICK - channeled whirlwind/charge AoE, not interruptible. Use defensives/spread. Marker so the addon stays silent." },
    ["evocation"] = { castTime = 20, interruptible = false, priority = 1, category = "other", zones = { "karazhan" }, note = "DO NOT KICK - 20s channel after the 10th Astral Flare; Curator takes triple damage (burn window). Marker so the addon stays silent." },

    -- ── Serpentshrine Cavern / Tempest Keep (Tier 5 — live Anniversary tier) ───────
    -- The high-value SSC/TK kicks are TRASH heals; most boss "casts" are padlocks.
    ["holy smite"]       = { castTime = 2.5, interruptible = true,  priority = 2, category = "nuke", zones = { "tempest keep" }, note = "Solarium Priest (Solarian adds, TK The Eye) filler nuke ~675-1025 Holy, ~2.5s. Interruptible but LOW value vs their Greater Heal - only kick if no heal is up. Name-keyed; other priest casters reuse it." },
    ["scorch"]           = { castTime = 1.5, interruptible = true,  priority = 2, category = "nuke", zones = { "the mechanar" }, note = "Sunseeker Astromage (Mechanar) fire nuke; kick to lock the Fire school and deny the follow-up Solarburn. The mob's Fire Shield is an instant reflect buff on an ally - PURGE it, not a kick target." },
    ["anesthetic"]       = { castTime = 1.5, interruptible = true,  priority = 3, category = "cc",   note = "Bloodwarder Physician (Mechanar) single-target Sleep up to 6s (any damage wakes it). Guides say interrupt OR dispel(Magic) - the cast IS kickable; kick to deny CC on your healer. Heroic adds Bandage (1s channel, also kickable) + Holy Shock." },
    ["recharge"]         = { castTime = 0,   interruptible = false, priority = 1, category = "heal", zones = { "tempest keep" }, note = "DO NOT KICK - Crystalcore Mechanic (TK, Void Reaver's room) channeled heal-bot ~10k HPS/10s, ignores LoS, UNINTERRUPTIBLE. Mechanics are Demons -> BANISH/CC + kill. Marker so players don't waste a kick." },
    ["chaos blast"]      = { castTime = 0,   interruptible = false, priority = 3, category = "nuke", zones = { "serpentshrine cavern" }, note = "DO NOT KICK - Leotheras the Blind, Demon Form (SSC). Binary Fire AoE + stacking fire-taken debuff; beaten with Fire Resistance + a geared demon-form tank, NEVER by kicking. castTime 0 = no kickable bar, not a channel." },
    ["cataclysmic bolt"] = { castTime = 0,   interruptible = false, priority = 2, category = "nuke", zones = { "serpentshrine cavern" }, note = "DO NOT KICK - Fathom-Lord Karathress (SSC). Instant ~50% max-HP shadow hit + brief knockdown on a random mana-user; no cast bar to interrupt; healers spot-heal the victim. castTime 0 = instant. spellID 38441 verified (Karathress-only)." },
    ["tidal wave"]       = { castTime = 2,   interruptible = false, priority = 2, category = "nuke", zones = { "serpentshrine cavern" }, note = "DO NOT KICK - Morogrim Tidewalker (SSC). 2s-cast frontal Frost cone + attack-speed slow; HAS a cast bar so it looks kickable, but it is a positional cleave (face Morogrim into a wall), not an interrupt. No source confirms a kick works." },
    ["tidal surge"]      = { castTime = 0,   interruptible = false, priority = 1, category = "cc",   note = "DO NOT KICK / disambiguation - Fathom-Guard Caribdis (SSC). INSTANT ~every 15-20s: ice-freezes a random player + nearby for 3s (spread). NOT kickable. Critical: do NOT confuse with Caribdis's Healing Wave, which IS the marquee SSC kick." },
    ["bellowing roar"]   = { castTime = 1.5, interruptible = false, priority = 1, category = "cc",   note = "DO NOT KICK - Lord Sanguinar (Kael'thas advisor, TK) 35yd AoE fear; not interruptible/silenceable - counter with Fear Ward / Tremor / Berserker Rage. (Wowhead lists base Bellowing Roar as instant, so it may not even raise a bar.) Dragon AoE-fear variants are likewise not kick-stopped." },
    ["flame strike"]     = { castTime = 3,   interruptible = false, priority = 1, category = "nuke", zones = { "tempest keep" }, note = "DO NOT KICK - Kael'thas (p4, TK) ground-targeted fire patch: move out, don't kick. Save interrupts for his Fireball/Pyroblast (kickable except under Shock Barrier). Distinct key from the kickable mage-trash 'flamestrike' (one word)." },
    ["mind control"]     = { castTime = 0,   interruptible = false, priority = 1, category = "cc",   note = "DO NOT KICK - Kael'thas (p4, TK) charms raiders; effectively instant, no kickable bar. Free MC'd players via the Infinity Blade special, not by kicking. Distinct from SSC 'domination' and Vashj 'persuasion'." },
}

-- Verified spellIDs (checked before names; locale-independent).
local byID = {
    [38919] = { name = "Bandage", castTime = 1, interruptible = true, priority = 4, category = "heal", note = "1s CAST heal-over-time (~1200/8s), NOT a channel - a kick stops the cast. Physician also has Anesthetic (sleep) and Holy Shock (heroic). spellID 38919 verified." },
    [33506] = { name = "Summon Cabal Deathsworn", castTime = 2, interruptible = true, priority = 5, category = "summon", note = "Top interrupt priority on the pull to avoid being overrun by adds. spellID 33506 verified (single source)." },
    [35251] = { name = "Summon Arcane Golem", castTime = 2, interruptible = true, priority = 4, category = "summon", note = "Summons add(s); interrupt to prevent the extra mob. Netherbinder also has Arcane Nova/Starfire/Dispel Magic. spellID 35251 verified (single source)." },
    [30616] = { name = "Blast Nova", castTime = 0, interruptible = false, priority = 5, category = "nuke", note = "DO NOT KICK - raid-wide channel (~10s) every ~50-60s, stopped ONLY by 5 players channeling the Manticron Cubes. Correctly flagged uninterruptible so the addon never prompts a kick. spellID 30616 verified." },
    [38441] = { name = "Cataclysmic Bolt", castTime = 0, interruptible = false, priority = 2, category = "nuke", note = "DO NOT KICK - Fathom-Lord Karathress (SSC). Instant ~50% max-HP shadow hit + brief knockdown on a random mana-user; no cast bar to interrupt. spellID 38441 verified (Karathress-only)." },
}

-- ── NEEDS REVIEW ────────────────────────────────────────────────────────────
-- Flagged by the verification pass: low confidence, or interruptibility varies by
-- mob (a name-keyed table can't safely represent both states). Verify, then move
-- a corrected copy up into byName/byID to activate.
--[[
    -- ["psychic scream"] = { castTime = 1.5, interruptible = true, priority = 4, category = "cc", note = "AoE fear, dangerous (pulls extra packs). The mob's cast time and interruptibility are UNCONFIRMED (player version is instant). Verify in-game before trusting a kick prompt." },    -- ["mind rend"] = { castTime = 0, interruptible = true, priority = 3, category = "nuke", note = "Uncertain: appears to be a CHANNELED shadow spell (~3s) that also STUNS the target, not a clean nuke. A kick may stop the channel but it also behaves like a stun (trinket/stun-break removable). Mechanic details unconfirmed." },
    -- ["netherbomb"] = { castTime = 0, interruptible = false, priority = 3, category = "nuke", note = "INSTANT cast - cannot be kicked. The real danger is the AoE suicide-charge 'Nether Explosion'; spread 6+ yds. Flagged uninterruptible but low confidence on the overall mechanic." },
    -- ["arcane blast"] = { castTime = 0, interruptible = false, priority = 2, category = "nuke", note = "INSTANT point-blank arcane pulse with knockback, NOT a kickable cast bar. Strategy is to burn the boss and brace for knockback. Flagged uninterruptible; low confidence." },
    -- ["overcharge"] = { castTime = 2, interruptible = false, priority = 2, category = "nuke", note = "~14-15k arcane to the tank, 2s cast - NOT interruptible, only deflectable/reflectable (earlier 'likely interruptible' was wrong). Flagged false; verify before treating as a marker. Mob also casts Charged Arcane Explosion (run out)." },
    -- ["persuasion"] = { castTime = 0, interruptible = false, priority = 3, category = "cc", note = "DO NOT KICK (verify per realm) - Lady Vashj MC (spell 38511), INSTANT / no cast bar, handled by taunting the MC'd player. Buggy/removed across patches; distinct from 'domination' and Kael 'mind control'." },
    -- ["mind blast"] = { castTime = 1.5, interruptible = false, priority = 1, category = "nuke", note = "DO NOT ACTIVATE BLINDLY - Coilfang Strider (Vashj p2) Mind Blast is trivial and never kicked (its real danger is instant Panic), BUT a generic ranked Mind Blast IS normally interruptible. A name-keyed false here would wrongly padlock OTHER priest mobs' Mind Blast. Needs per-mob handling before shipping." },
    -- ["summon fathom lurker"] = { castTime = 2, interruptible = false, priority = 1, category = "summon", note = "Fathom-Guard Sharkkis (SSC) pet summon; never kicked in practice (weak pets, kill-order fight). Whether the summon is technically interruptible is UNCONFIRMED. castTime estimated." },--]]

Vantage.Kickable = { byName = byName, byID = byID }

-- Look up intel for a cast. Returns the entry table, or nil if we have no intel.
function Vantage.GetKickInfo(spellName, spellID)
    if spellID and byID[spellID] then return byID[spellID] end
    if spellName then
        local hit = byName[spellName:lower()]
        if hit then return hit end
    end
    -- Curated intel missed. Fall back to what Vantage LEARNED from live combat
    -- (casts it watched get interrupted — see Modules/Learn.lua). Curated always
    -- wins above, so a hand-verified padlock is never overridden by a learned
    -- entry; learning only ever fills the "unknown" gap.
    if (not Vantage.db) or Vantage.db.learn ~= false then
        local L = VantageLearnedDB and VantageLearnedDB.spells
        if L and spellName then
            local e = L[spellName:lower()]
            if e then return e end
        end
    end
    return nil
end
