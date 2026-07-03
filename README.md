# Vigil

**Interrupt-smart nameplates for WoW Classic (TBC / Anniversary, 2.5.x).**
Know exactly when to kick — and when *not* to waste it.

Vigil decorates Blizzard's enemy nameplates with a cast bar that tells you, at a
glance, whether the cast in front of you should be interrupted. When a *kickable*
cast appears, **your interrupt is off cooldown, and the target is in range**,
the plate erupts in a gold glow with a sound and an `INTERRUPT` prompt. When a
cast **can't** be interrupted, it gets a red **padlock** so you hold your kick.
And as each flagged cast resolves, the bar flashes the verdict — teal `KICKED`,
or red `MISSED` when it slipped through while your stop sat ready. That's the
whole pitch, and it works the moment you install it — no group required, no
config needed.

And it looks the part: a full custom skin — smooth gradient health bars with a
soft drop shadow, crisp 1px borders, class colors on players, level text, a
slim mana bar on casters, health text, a gold outline + glow on your current
target, a bordered-icon cast bar with a live countdown, and DoT timers with
dispel-colored borders and a draining cooldown swipe. Plates *react*, too:
damage flashes bite out of the bar as mobs lose health, the plate under your
cursor lights up, non-target plates dim so your kill target reads instantly,
and an execute tick lights up at 20%. Four accent themes (Gold / Teal /
Violet / Ice) re-skin the cue in one click. Friendly plates get the same skin
when Blizzard shows them. Every piece is configurable from the options panel
(`/vigil`), and the defaults are tuned to look great with zero setup.

> Dependency-free by design (no libraries), so it loads instantly. Shareable
> "Intel Pack" import strings and the Vigil Parse data layer are the next
> milestones on top of this structure.

## Install

CurseForge / Wago listings come with v1.0. Until then, from GitHub:

1. Download the zip from [Releases](https://github.com/karlbonitz/Vigil/releases)
   — or `git clone https://github.com/karlbonitz/Vigil.git` — and put the
   `Vigil` folder into:
   `World of Warcraft/_classic_/Interface/AddOns/Vigil`
   (the folder containing `Vigil.toc` must be named exactly `Vigil`).
2. On the character screen, open **AddOns** and make sure Vigil is enabled.
   If it shows as "out of date", tick **Load out of date AddOns** (the interface
   number in `Vigil.toc` may lag a tiny patch — see *Versioning & releases* below).
3. Log in. You should see: `Vigil v0.6.0 loaded.`
4. Make sure **enemy nameplates are on** (default keybind `V`, or hold the
   nameplate key).

## Try it in 10 seconds

- Target any enemy with a visible nameplate and type **`/vigil test`** — a demo
  "Greater Heal" cast bar runs for 3 seconds. If your class has a ready interrupt,
  you'll see the gold glow + `INTERRUPT` prompt and hear the alert.
- Then go pull a caster pack in a dungeon and watch real casts light up.

## Commands

| Command | Does |
|---|---|
| `/vigil test` | fire the demo cue on your target |
| `/vigil cue` | toggle the interrupt glow/sound |
| `/vigil sound` | toggle the alert sound |
| `/vigil padlock` | toggle the uninterruptible marker |
| `/vigil threat` | toggle the threat tint (`/vigil tank` inverts it for tanks) |
| `/vigil auras` | toggle your DoT/debuff timer row |
| `/vigil skin` | toggle the custom nameplate skin |
| `/vigil unknown` | also cue casts Vigil has no intel on |
| `/vigil pvp` | cue enemy **player** casts when your interrupt is ready (no DB needed) |
| `/vigil range` | only shout when the target is within your stop's actual range |
| `/vigil flash` | outcome flash as a flagged cast ends (KICKED / MISSED / WASTED) |
| `/vigil parse` | chat summary of this session's interrupt stats (Vigil Parse) |
| `/vigil export` | copy-paste window with your session data for the web report |
| `/vigil` | **open the options panel** (`/vigil help` lists chat commands) |

You can also reach the options panel from **Esc → Options → AddOns → Vigil**.

## How it works (and what's deliberately limited in v0.1)

- **Decorates, never replaces.** Our overlay is parented to `UIParent` and merely
  *anchored* to the plate. We never reparent/move the secure nameplate frame, so
  there's no taint risk. A from-scratch plate skin is a later milestone.
- **Interruptibility comes from a data table, not the client.** The 2.5.x client's
  `notInterruptible` flag is unreliable, so Vigil classifies casts from
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
  actually land — Vigil suppresses it on bosses (and specific CC-immune mobs from
  `Data/Immunities.lua`) so it never tells a Paladin to `STUN` a stun-immune boss.
  Enemy players and ordinary trash stay cue-able.
- **PvP needs no database.** Against enemy *players*, Vigil skips the Intel Pack
  entirely — a player's hard cast is interruptible — and lights the cue whenever
  *your* interrupt (hard kick **or** soft Fear/Silence/Shackle/Stun) is ready. So
  the hero feature is useful in arenas, battlegrounds, and world PvP at any level,
  not just in dungeons. Toggle with `/vigil pvp` (on by default).
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
Vigil/
  Vigil.toc                 multi-interface TOC + load order
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
  Modules/
    Nameplates.lua          tracks plates, builds/recycles the overlay frames
    Skin.lua                custom health-bar skin (gradient/border/text/colors)
    CastWatch.lua           detects enemy casts (live API + combat-log fallback)
    InterruptCue.lua        THE hero: glow/sound/padlock decision
    Threat.lua              minimal, feature-detected threat tint
    Auras.lua               your DoT/debuff timer row (swipe + dispel borders)
    Options.lua             native options panel (sections, sliders, reset)
    Parse.lua               Vigil Parse collector: decision rows + CLEU outcomes
    ParseExport.lua         /vigil export JSON copy-paste window
  docs/
    index.html              the Vigil Parse web report (served by GitHub Pages)
  .pkgmeta                  BigWigs packager config (what ships in the zip)
  .github/workflows/        tag-triggered package-and-release Action
  LISTING.md                paste-ready CurseForge/Wago description
```

The **web report** is live at **https://karlbonitz.github.io/Vigil/** — a
single static page (`docs/index.html`) that decodes a `/vigil export` string
entirely in your browser. Nothing is uploaded anywhere.

## Roadmap

- **v0.2** — ✅ aura/DoT timer row (`/vigil auras`), ✅ custom nameplate skin (`/vigil skin`), ✅ options panel (`/vigil`). Still to come: threat fallback lib.
- **v0.3.0** — ✅ visual overhaul: gradient bar media, radial interrupt halo,
  bordered cast-bar icon + cast countdown, health text, class colors, target
  glow, aura swipe + dispel borders, sectioned options with sliders + reset.
- **v0.3** — Ace3 adoption (AceConfig options GUI, AceSerializer+LibDeflate),
  shareable **Intel Pack** import/export strings + an "intel-only consumer" mode
  so Plater users can adopt the kick intelligence without switching nameplates.
- **Phase 2** — **Vigil Parse**: ✅ phase 1 shipped in v0.5.0 — decision/outcome
  collector (`/vigil parse`), JSON export (`/vigil export`), and the in-browser
  report page (`VigilParseWeb/`). Next: reaction-time percentiles, per-dungeon
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

## Versioning & releases

- `## Interface: 20504, 20505` in the TOC targets the 2.5.4/2.5.5 clients; if
  Blizzard ships a tiny client patch before the TOC catches up, **Load out of
  date AddOns** is safe.
- Release flow: bump `## Version` in `Vigil.toc` **and** `Vigil.version` in
  `Core/Util.lua`, write the `CHANGELOG.md` entry, commit, then
  `git tag vX.Y.Z && git push --tags`. The GitHub Action packages the zip per
  `.pkgmeta` and attaches it to a GitHub release — and uploads to
  CurseForge/Wago once those project IDs + API-key secrets are configured.

## License
MIT.
