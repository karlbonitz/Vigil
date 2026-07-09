# Vantage

**Interrupt-smart nameplates for WoW Classic (TBC / Anniversary, 2.5.x).**
Know exactly when to kick — and when *not* to waste it.

Vantage decorates Blizzard's enemy nameplates with a cast bar that tells you, at a
glance, whether the cast in front of you should be interrupted. When a *kickable*
cast appears, **your interrupt is off cooldown, and the target is in range**,
the plate erupts in a gold glow with a sound and an `INTERRUPT` prompt. When a
cast **can't** be interrupted, it gets a red **padlock** so you hold your kick.
And as each flagged cast resolves, the bar flashes the verdict — teal `KICKED`,
or red `MISSED` when it slipped through while your stop sat ready. That's the
whole pitch, and it works the moment you install it — no group required, no
config needed.

In a group, Vantage thinks along with the whole party. Walk into a dungeon it
has intel on and the **briefing** prints the kick sheet before the first pull
(`/vantage brief` for the reasons). The **party kick watch** learns your
groupmates' interrupts from the combat log — nobody else needs the addon —
and when a kickable cast is up while *your* stop is down, the cue quietly
names whose interrupt is ready. And the plates answer "whose problem is
this?": bright red = it's coming for you, cool slate = the tank has it, and
**amber = your damage says you're closing in on pulling it** (estimated from
group damage tallies, because the client's threat API is broken — late,
never spammy).

And Vantage **teaches itself**. The curated pack can't know every cast in every
instance, so any time Vantage watches a cast get interrupted — yours or a
groupmate's — it banks that spell as kickable forever (you can't interrupt an
uninterruptible cast, so there are no false positives). Casts it had never
heard of become real cues the next time they appear, filling in low-level and
off-meta content automatically — all local, no uploads, and it never overrides
a verified "do not kick" marker. `/vantage learned` shows what it has picked up.

And what one player learns, **everyone** inherits. `/vantage contribute` turns your
self-taught kicks into a tiny, anonymous blob — no character, no realm, just the
spell IDs you've confirmed kickable and the interrupt that stopped each one as
proof — which you paste on the report page. A community collector pools these,
cross-checks every submission against datamined spell data, and promotes a cast
only once several *independent* players confirm it; then it ships in the next
release, so the shared **Community Pack** keeps growing for the whole player base.
Curated "do not kick" markers can never be overridden — the pool only ever *adds*
verified kicks.

And it looks the part: a full custom skin — smooth gradient health bars with a
soft drop shadow, crisp 1px borders, class colors on players, level text, a
slim mana bar on casters, health text, a gold outline + glow on your current
target, a bordered-icon cast bar with a live countdown, and DoT timers with
dispel-colored borders and a draining cooldown swipe. Plates *react*, too:
damage flashes bite out of the bar as mobs lose health, the plate under your
cursor lights up, non-target plates dim so your kill target reads instantly,
and an execute tick lights up at your chosen threshold. Four accent themes
(Gold / Teal / Violet / Ice) re-skin the cue in one click, and a **Style**
section tunes the whole look live: font face & treatment, gradient or flat
bar fills, health/cast bar heights, and the alert sound. Friendly plates get
the same skin when Blizzard shows them. Every piece is configurable from the
options panel (`/vantage`), and the defaults are tuned to look great with zero
setup.

> Dependency-free by design (no libraries), so it loads instantly. Shareable
> "Intel Pack" import strings and the Vantage Parse data layer are the next
> milestones on top of this structure.

## Install

Vantage is published on **CurseForge** and **Wago** — search "Vantage" in your
addon manager. Or install straight from GitHub:

1. Download the zip from [Releases](https://github.com/karlbonitz/Vantage/releases)
   — or `git clone https://github.com/karlbonitz/Vantage.git` — and put the
   `Vantage` folder into:
   `World of Warcraft/_classic_/Interface/AddOns/Vantage`
   (the folder containing `Vantage.toc` must be named exactly `Vantage`).
2. On the character screen, open **AddOns** and make sure Vantage is enabled.
   If it shows as "out of date", tick **Load out of date AddOns** (the interface
   number in `Vantage.toc` may lag a tiny patch — see *Versioning & releases* below).
3. Log in. You should see: `Vantage v0.11.0 loaded.`
4. Make sure **enemy nameplates are on** (default keybind `V`, or hold the
   nameplate key).

## Try it in 10 seconds

- Target any enemy with a visible nameplate and type **`/vantage test`** — a demo
  "Greater Heal" cast bar runs for 3 seconds. If your class has a ready interrupt,
  you'll see the gold glow + `INTERRUPT` prompt and hear the alert.
- Then go pull a caster pack in a dungeon and watch real casts light up.

## Commands

| Command | Does |
|---|---|
| `/vantage test` | fire the demo cue on your target |
| `/vantage cue` | toggle the interrupt glow/sound |
| `/vantage sound` | toggle the alert sound |
| `/vantage padlock` | toggle the uninterruptible marker |
| `/vantage threat` | toggle the threat tint (`/vantage tank` inverts it for tanks) |
| `/vantage amber` | amber warning when your damage is closing in on a pull |
| `/vantage brief` | this dungeon's kick sheet, with the why behind each line |
| `/vantage party` | name a ready groupmate when your own stop is down |
| `/vantage auras` | toggle your DoT/debuff timer row |
| `/vantage skin` | toggle the custom nameplate skin |
| `/vantage unknown` | also cue casts Vantage has no intel on |
| `/vantage learn` | toggle learning kicks from live combat (on by default) |
| `/vantage learned` | list the interruptible casts Vantage has taught itself |
| `/vantage contribute` | share your self-taught kicks with the community pool (anonymous) |
| `/vantage pvp` | cue enemy **player** casts when your interrupt is ready (no DB needed) |
| `/vantage range` | only shout when the target is within your stop's actual range |
| `/vantage flash` | outcome flash as a flagged cast ends (KICKED / MISSED / WASTED) |
| `/vantage parse` | chat summary of this session's interrupt stats (Vantage Parse) |
| `/vantage roster` | lifetime interrupt profiles of every friendly player Vantage has witnessed |
| `/vantage export` | copy-paste window with your session data for the web report |
| `/vantage` | **open the options panel** (`/vantage help` lists chat commands) |

You can also reach the options panel from **Esc → Options → AddOns → Vantage**.

## How it works (and what's deliberately limited in v0.1)

- **Decorates, never replaces.** Our overlay is parented to `UIParent` and merely
  *anchored* to the plate. We never reparent/move the secure nameplate frame, so
  there's no taint risk. A from-scratch plate skin is a later milestone.
- **Interruptibility comes from a data table, not the client.** The 2.5.x client's
  `notInterruptible` flag is unreliable, so Vantage classifies casts from
  `Data/KickableSpells.lua` (the seed "Intel Pack"). Unknown casts show a neutral
  bar and *don't* shout `INTERRUPT` (no false alarms) unless you opt in.
- **"Is my kick ready?"** is read from your own spell cooldowns, for **every**
  class (`Data/InterruptSpells.lua`). Hard-kick classes (Rogue/Mage/Shaman/Warrior,
  Warlock *with a Felhunter*, Shadow Priest) get the "kick now" glow; the rest get an
  honest **soft** cue for their stuns/fears/disorients (Paladin `STUN`, Hunter
  `SCATTER`/`STUN`, Druid `BASH`, …). Stance, form, shield, and pet are all checked,
  so the cue never points to a tool you can't currently use (e.g. Pummel only lights
  in Berserker stance, Bash only in Bear form).
- **Soft cues respect immunity.** A stun/fear/disorient cue only fires when it can
  actually land — Vantage suppresses it on bosses (and specific CC-immune mobs from
  `Data/Immunities.lua`) so it never tells a Paladin to `STUN` a stun-immune boss.
  Enemy players and ordinary trash stay cue-able.
- **PvP needs no database.** Against enemy *players*, Vantage skips the Intel Pack
  entirely — a player's hard cast is interruptible — and lights the cue whenever
  *your* interrupt (hard kick **or** soft Fear/Silence/Shackle/Stun) is ready. So
  the hero feature is useful in arenas, battlegrounds, and world PvP at any level,
  not just in dungeons. Toggle with `/vantage pvp` (on by default).
- **Threat tint is minimal and feature-detected.** If the native threat API isn't
  present on your client, the tint disables itself cleanly; a LibThreatClassic2
  fallback is a v0.2 TODO. The interrupt cue does not depend on it.

### Known limitations / TODO
- Cast detection currently leans on the combat log + live cast API; very short
  casts and out-of-range casters may be missed.
- Range awareness uses `IsSpellInRange`, which can't see **pet** abilities —
  a Warlock's Spell Lock cue is never range-suppressed.
- Seed spell data is small and matched by name (locale-specific). Real coverage
  ships as spellID-keyed Intel Packs.

## Project layout

```
Vantage/
  Vantage.toc                 multi-interface TOC + load order
  Core/
    Util.lua                namespace, colors, media paths, border helper
    Core.lua                event bus, module registry, SavedVariables, slash cmds
  Media/
    bar.tga                 smooth gradient statusbar fill (all bars use it)
    glow.tga                soft radial glow (interrupt halo / target glow / shadow)
  Data/
    KickableSpells.lua      seed Intel Pack: which casts to kick (+interruptible)
    Immunities.lua          per-NPC CC-immunity table + boss heuristic
    InterruptSpells.lua     your interrupts by class + "is my kick ready?"
    CommunityPack.lua       crowdsourced kicks, regenerated from the pool at release
  Modules/
    Nameplates.lua          tracks plates, builds/recycles the overlay frames
    Skin.lua                custom health-bar skin (gradient/border/text/colors)
    CastWatch.lua           detects enemy casts (live API + combat-log fallback)
    InterruptCue.lua        THE hero: glow/sound/padlock decision
    PartyKicks.lua          groupmates' interrupt cooldowns, inferred from CLEU
    ThreatEst.lua           amber "closing in" estimate from group damage tallies
    Threat.lua              aggro state from ground truth (mob target) + amber
    Auras.lua               your DoT/debuff timer row (swipe + dispel borders)
    Options.lua             native options panel (sections, sliders, reset)
    Parse.lua               Vantage Parse collector: decision rows + CLEU outcomes
    ParseExport.lua         /vantage export JSON copy-paste window
    Contribute.lua          /vantage contribute — anonymous community-intel export
    Briefing.lua            the dungeon kick sheet, printed on zone-in
  docs/
    index.html              the Vantage Parse web report (served by GitHub Pages)
  collector/                self-hosted community-intel backend (Node + SQLite + admin dashboard)
  .pkgmeta                  BigWigs packager config (what ships in the zip)
  .github/workflows/        tag-triggered package-and-release Action
  LISTING.md                paste-ready CurseForge/Wago description
```

The **web report** is live at **https://karlbonitz.github.io/Vantage/** — a
single static page (`docs/index.html`) that decodes a `/vantage export` string
entirely in your browser: interrupt efficiency tiles, by-spell and by-dungeon
breakdowns, reaction-time percentiles, and **your crew** (the account-wide
roster of everyone Vantage has watched land a kick). One click packs the whole
report into a **share link** — the data rides the URL fragment, gzipped, which
no server ever sees. Nothing is uploaded anywhere.

## Roadmap

- **v0.2** — ✅ aura/DoT timer row (`/vantage auras`), ✅ custom nameplate skin (`/vantage skin`), ✅ options panel (`/vantage`). Still to come: threat fallback lib.
- **v0.3.0** — ✅ visual overhaul: gradient bar media, radial interrupt halo,
  bordered cast-bar icon + cast countdown, health text, class colors, target
  glow, aura swipe + dispel borders, sectioned options with sliders + reset.
- **v0.3** — Ace3 adoption (AceConfig options GUI, AceSerializer+LibDeflate),
  shareable **Intel Pack** import/export strings + an "intel-only consumer" mode
  so Plater users can adopt the kick intelligence without switching nameplates.
- **v0.11 — the community update** — ✅ crowdsourced kickable-spell database:
  `/vantage contribute` feeds an anonymous, evidence-checked collector; once
  several independent players confirm a cast it's promoted into a shared
  **Community Pack** that ships with each release, so everyone's discoveries pool
  together and new players inherit the lot on day one.
- **Phase 2** — **Vantage Parse**: ✅ phase 1 shipped in v0.5.0 — decision/outcome
  collector (`/vantage parse`), JSON export (`/vantage export`), and the in-browser
  report page (`VantageParseWeb/`). Next: reaction-time percentiles, per-dungeon
  breakdowns, CC-break/dispel tracking, then the hosted backend ("the utility
  parse Warcraft Logs forgot").

## Development

`tests/` holds a headless smoke test: a stubbed WoW 2.5.x API (real Lua 5.1
via [lupa](https://pypi.org/project/lupa/)) that loads the whole addon and
drives a fake session — casts, range changes, interrupts, flashes, slash
commands, export — with assertions, once per class archetype. It is not a
substitute for in-game testing, but it catches load errors and event-logic
bugs before they reach a player.

```
pip install lupa && python3 tests/run.py
```

In-game, `/vantage plate` dumps your target's nameplate frame tree (children,
regions, textures, parent keys) into a copy-paste window — the ground-truth
way to see what the live client actually draws on a plate.

## Versioning & releases

- `## Interface: 20504, 20505` in the TOC targets the 2.5.4/2.5.5 clients; if
  Blizzard ships a tiny client patch before the TOC catches up, **Load out of
  date AddOns** is safe.
- Release flow: bump `## Version` in `Vantage.toc` **and** `Vantage.version` in
  `Core/Util.lua`, write the `CHANGELOG.md` entry, commit, then
  `git tag vX.Y.Z && git push --tags`. The GitHub Action packages the zip per
  `.pkgmeta` and attaches it to a GitHub release — and uploads to
  CurseForge/Wago once those project IDs + API-key secrets are configured.

## License
MIT.
