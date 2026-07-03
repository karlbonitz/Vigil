# Changelog

## v0.7.0 — the stellar pass
A visual polish round aimed squarely at the best-in-class nameplate addons:
bars that react, plates that respond to you, and a theme system — all still
purely additive decoration on Blizzard's plates (no taint, no replacement).

- **Damage bites**: when a mob loses health, a bright sliver marks the lost
  segment and fades out — incoming damage reads at a glance. Pooled textures
  and one self-stopping animation driver, so idle cost is zero.
- **Focus dim**: while you have a target, other plates drop to 85% opacity so
  your kill target reads instantly. Cast bars and interrupt cues NEVER dim —
  an off-target kick window still gets full volume.
- **Mouseover wash**: the plate under your cursor lights up softly.
- **Execute mark**: a quiet tick at 20% health that lights up red — along
  with the HP text — once the mob is in execute range. Every class knows the
  kill window.
- **Accent themes**: Gold (default), Teal, Violet, or Ice. One dropdown
  re-tints the cue glow, the INTERRUPT label, the kickable-cast color, and
  the target outline together. Padlock red and threat colors are semantic
  and never themed — "go" can never impersonate "stop".
- **Juice**: cast-bar spell icons pop in; new and refreshed DoT icons pop in;
  a 1px glass highlight tops the health and cast bars.
- **The options panel is now scrollable** — the height ceiling is gone for
  good, with three new toggles (damage flashes, focus dim, execute mark) and
  the accent dropdown under Nameplates.

## v0.6.0 — the coach update (range, verdicts, onboarding)
The cue gets more honest, and the addon starts teaching in the moment instead
of only in the after-session report.

- **Range-aware cues** (`/vigil range`, on by default): the shout now fires
  only when the target is actually within your stop's range — melee for
  Kick/Pummel/Bash, 8 yd for Psychic Scream, 30 yd for Counterspell (the
  client API knows each spell's true range). Ready-but-too-far casts show the
  gold awareness bar instead, and a light quarter-second re-check upgrades
  them to the full glow + sound the moment you close the distance. Suppression
  happens only on an EXPLICIT out-of-range answer — pet abilities (Spell Lock)
  can't be range-checked and are never suppressed. `/vigil check` now says when
  your ready stop is out of range, and Vigil Parse logs the new decision tier.
- **Outcome flash** (`/vigil flash`, on by default): as a flagged cast
  resolves, the bar flashes its verdict — teal **KICKED** (you or a groupmate
  stopped it) or red **MISSED** (it completed while your stop sat ready — the
  stat Vigil exists to drive down). And when your kick lands on a do-not-kick
  cast, the plate pops a red **WASTED** label while the cast — unaffected —
  rolls on. Visual only, no extra sound.
- **Cue label position** (options panel): "Plate center" (default) or
  "Above cast bar", applied live.
- **First-run onboarding**: a fresh install gets one extra pointer (turn enemy
  nameplates on with `V`, then `/vigil test`); version upgrades print a
  one-line what's-new. Neither ever repeats.
- Fix: an instant spell succeeding mid-cast no longer clears the cast bar of
  the real cast still in flight — both detection paths now match the resolving
  spell against the one being tracked.
- Fix (pre-0.6.0 bug): on the combat-log fallback path, an interrupted cast's
  bar never cleared — `SPELL_INTERRUPT` was looked up by the interrupter's
  GUID instead of the caster's. Found by the new headless test harness
  (`tests/`), which loads the whole addon under a stubbed WoW API and drives
  a full fake session per class.
- Fix (in-game test pass): the mana bar rendered as a washed-out grey-white
  strip — 32px of gradient texture squeezed into 4px averages to near-white.
  Now a solid, readable blue. (Mobs like Durotar's crabs carry a token mana
  pool they never use, so the strip was showing on non-casters too — toggle
  "Mana bar on casters" off if you'd rather not see those.)
- Fix: Blizzard's own nameplate cast bar no longer double-draws its flat grey
  bar under Vigil's styled one — suppressed on skinned enemy plates while
  Vigil's cast bars are enabled, restored the moment you disable either.

## v0.5.0 — Vigil Parse, phase 1 (the collector)
The data layer begins: "the utility parse Warcraft Logs forgot," starting with
the closed loop that works today — collector → chat summary → export string →
in-browser report. No server, no upload; WoW addons have no network access, so
the bridge is copy-paste into a static page that decodes locally.

- **Decision logging** (`parse`, on by default): every enemy cast Vigil
  evaluates becomes a row — spell, caster, zone, decision tier, which of your
  interrupts was offered — and combat-log outcomes attach to it: interrupted
  (by you or someone else), completed, **completed while your stop was READY**
  (the headline stat WCL can't show), your cue→interrupt reaction time in ms,
  and kicks you spent on casts marked uninterruptible.
- **`/vigil parse`** — instant chat summary of the current session: casts
  logged, kick windows shown, interrupts by you vs others, let-throughs,
  average reaction, wasted kicks.
- **`/vigil export`** (also a button in the options panel) — a copy-paste
  window with the session data as JSON, pre-selected for Ctrl+C. Paste it into
  the Vigil Parse report page (static HTML, decodes entirely in your browser).
- Storage: new `VigilParseDB` SavedVariable; one session per login, last 8
  sessions kept, 4000 rows/session cap (then it stops and says so). Rows exist
  only for casts already evaluated on visible plates, so overhead is minimal.
- Dependency-free JSON encoder (~40 lines); compression (LibDeflate) only if
  exports outgrow the edit box in practice.
- **The report page** (`docs/index.html`, live at
  https://karlbonitz.github.io/Vigil/): paste the export, get the dashboard —
  headline "let through while
  ready" count, kick windows / conversion rate / median cue→kick reaction /
  wasted kicks, a by-spell table with outcome bars (kicked vs let-through,
  do-not-kick and PvP casts flagged), and a per-session table. One static
  file, no dependencies, decodes entirely in the browser.

## v0.4.1 — the label takes the plate (+ two review fixes)
- The `INTERRUPT` / `FEAR` / `STUN` call-to-action now sits **centered on the
  health bar** — the plate's visual center — instead of hovering in the thin
  strip between the cast bar and the plate (which the new mana bar also
  occupies). Nothing collides: auras live above, mana + cast bar below, and
  covering the HP text for the second you're deciding to kick is the point —
  the label *is* the information right then. The pop-in now shrinks into the
  plate's center, and pooled overlays always detach the label from a recycled
  plate's bar (falls back to hovering above the cast bar if a plate has no
  reachable health bar).
- **Fix: skin no longer bleeds onto recycled plates.** Blizzard pools nameplate
  frames; a frame we skinned for an enemy could be reused for the personal
  resource bar (or a friendly with friendly-skinning off) and keep the dark
  background/border/font. Such frames are now scrubbed on reuse.
- **Fix: one ding per cue.** The alert sound now plays only when the cue newly
  appears, instead of re-firing on every cooldown update during a single cast.

## v0.4.0 — full-plate polish
Feedback round on v0.3.0: tighter alignment and the missing pieces other
nameplate addons have.

- **Friendly nameplates** are now skinned too (`friendly`, on by default) —
  gradient bar, border, shadow, name font, health text, class colors on
  friendly players — so the whole screen matches whenever Blizzard is showing
  friendly plates. Cast bars/cues stay enemy-only (that's Vigil's job), and the
  personal resource bar is never touched. Forbidden plates are skipped.
- **Level on plates** (`showLevel`, on): difficulty-colored level inside the
  bar's left edge, `+` for elite, `r` for rare, red `??` for skull/boss.
- **Mana bar** (`manaBar`, on): a slim blue bar under the health bar, shown
  only for units that actually use mana — casters at a glance, and a drained
  caster is a disarmed one. Live via power events.
- **Tighter cast bar:** the overlay now matches each plate's actual health-bar
  width, so the cast bar aligns edge-to-edge under the health bar (icon hangs
  off the left, Plater-style) instead of using one fixed width.
- **HP numbers:** already there — set *Health text* to `Health` or
  `Health + %` in the options dropdown.
- Options: new toggles live under *Nameplates*; *Threat* merged into
  *Threat & general* so the panel stays one screen.

## v0.3.0 — the beautiful release
A full visual overhaul, with everything user-configurable and pretty defaults
that need zero setup.

- **New texture media** (shipped TGAs in `Media/`): a smooth vertical-gradient
  statusbar fill and a soft radial glow. Health bars, cast bars, and the threat
  strip all use the gradient — the single biggest "looks like a real nameplate
  addon" upgrade over Blizzard's glossy default texture.
- **Nameplate skin, redesigned:** soft drop shadow under the bar, dark inset
  background, crisp 1px border, **health text** (percent by default; hides at
  full health to stay clean — or raw health / both / none), **class colors on
  enemy players** (bar + name, kept in place even when Blizzard re-asserts
  reaction color), and your current target now gets a **gold outline + soft
  gold glow** (Blizzard's white selection highlight is hidden while the skin
  owns the look). Name font size is now a slider.
- **Cast bar, redesigned:** the spell icon sits in its own bordered square
  flush with the bar, a **cast-time countdown** ("1.4") rides the right edge,
  the spell name never overlaps it, and the whole bar wears the same 1px
  border + gradient as the health bar. The uninterruptible **padlock** moved
  into the bar's right edge (replacing the countdown) so the spell name stays
  readable.
- **Interrupt cue, redesigned:** the flat rectangle pulse is gone — the cue is
  now a **soft radial halo** that breathes around the whole cast row, and the
  `INTERRUPT` / `FEAR` / `STUN` label **pops in** with a quick scale-shrink.
  Same honest tiers as before, just prettier.
- **Aura row, redesigned:** icons get crisp borders **tinted by dispel type**
  (magic blue, curse purple, disease brown, poison green) and a **radial
  cooldown swipe** that drains as the DoT runs out. Icon size and the max
  icons per plate (raid-clutter cap) are sliders.
- **Options panel, rebuilt:** sectioned layout (Nameplates / Cast bars &
  interrupts / Your auras / Threat / General) with gold headers, tooltips on
  the non-obvious toggles, four live sliders, a health-text dropdown, and a
  **Reset to defaults** button. Everything applies instantly as you drag.
- **Fixes:** the target outline was tinted on a black base texture, which
  multiplies to black — the gold target border now actually renders gold.
  The threat strip is visible whenever a plate exists (it used to render only
  while a cast bar was up).

## v0.2.6 — soft cues respect crowd-control immunity
- Soft interrupts (stun / fear / disorient / sleep / …) now cue **only when they can
  actually land**. A Priest won't see `FEAR` on a fear-immune boss; a Paladin won't
  see `STUN` on a stun-immune one — the cast instead shows as plain awareness, with no
  misleading nag. Enemy **players** (PvP) and ordinary trash stay fully cue-able.
- New `Data/Immunities.lua`: a per-NPC crowd-control immunity table (name-keyed,
  researched + verified for TBC dungeon/raid bosses) **plus** a boss heuristic
  (world-boss / "skull"-level targets are treated as CC-immune). Hard kicks
  (Kick/Counterspell/Pummel/Spell Lock/…) are **never** suppressed — their "will it
  land" is the cast's own interruptibility, not the caster's CC immunity.
- Diminishing returns on repeated CC is not modeled yet (noted for later).

## v0.2.5 — interrupts for every class (not just Priest)
- Rebuilt the per-class interrupt table for all 9 TBC classes, researched + verified:
  - **Fixed: Warlock Spell Lock never cued.** It's a Felhunter *pet* ability, which
    `GetSpellCooldown` can't see, so warlocks got no glow at all. Readiness is now
    read from the pet action bar — and only when the Felhunter is actually out.
  - **Added Hunter** (was empty): Intimidation / Scatter Shot soft stops.
  - **Stance / form / shield aware.** Pummel only cues in Berserker stance, Shield
    Bash only with a shield in Battle/Defensive, Bash & Feral Charge only in Bear
    form — so the glow never tells you to use a tool you can't currently use.
  - Filled out every class (Rogue Gouge/Kidney Shot, Mage Dragon's Breath, Warlock
    Shadowfury/Death Coil, Paladin Repentance vs Humanoids, Warrior Concussion Blow).
    Feral Charge corrected to a *soft* stop. No post-TBC abilities (Wind Shear /
    Silencing Shot / Skull Bash) leak in.
- `/vigil check` now reports pet/stance/form gating and pet-ability readiness honestly.

## v0.2.4 — PvP cues + Serpentshrine/Tempest Keep intel
- **PvP enemy-player cues** (`/vigil pvp`, on by default): against enemy *players*,
  Vigil skips the mob database entirely — a player's hard cast is interruptible —
  and fires the cue whenever your interrupt is ready, hard kick **or** soft
  (Fear/Silence/Shackle/Stun). The hero feature now works in arenas, battlegrounds,
  and world PvP **at any level**, with no spell data required. PvE do-not-kick
  padlock markers never apply to a player target.
- **Intel Pack: Serpentshrine Cavern + Tempest Keep** coverage filled out (the live
  Tier 5 raid tier), researched and adversarially fact-checked.

## v0.2.3 — custom nameplate skin
- **Custom skin** for enemy nameplates: clean statusbar texture, dark background,
  crisp 1px border, sharper outlined name font, and a **gold outline on your
  current target**. Restyles Blizzard's health bar in place (taint-free; keeps
  Blizzard's red/yellow reaction coloring). Toggle with `/vigil skin`.
  (Disabling reverts the bar/font live; the skin verifies the 2.5.x frame paths.)

## v0.2.2 — timer accuracy
- Aura/DoT timers now show whole **seconds remaining** (floored, like a countdown
  clock) instead of rounding up — fixes the ~1s overcount. Sub-second tenths show
  in the final second so it never flashes "0".

## v0.2.1 — options panel
- Native **options panel** in Esc → Options → AddOns → Vigil (feature-detects the
  modern Settings API vs legacy InterfaceOptions). Checkboxes for every toggle plus
  an overlay-scale slider; changes apply live. Bare `/vigil` now opens the panel;
  `/vigil help` lists the chat commands.

## v0.2.0 — aura/DoT timer row
- **Personal aura/DoT timers**: your own debuffs on each enemy nameplate, shown as
  a row of icons above the plate with live countdowns (red in the last 3s) and
  stack counts. Uses the PLAYER aura filter, so it only shows auras YOU applied —
  great for timing Shadow Word: Pain refreshes. Toggle with `/vigil auras`.

## v0.1.1 — real database + class-aware cues
- Verified TBC kickable-spell database (~49 active entries across all heroics +
  Karazhan + Gruul/Mag, partial SSC/TK), built and adversarially fact-checked.
- Class-aware cue tiers: kick-class-ready = glow+sound+label; on cooldown = muted;
  no interrupt = gold awareness bar. **Soft interrupts** so non-kick classes get a
  cue too — Priest `FEAR` (Psychic Scream) / `SILENCE` / `SHACKLE`, Paladin `STUN`.
- Diagnostics: `/vigil check` (interrupt readiness) and `/vigil debug` (per-cast
  decision log). `/vigil test` forces the full cue regardless of class.

## v0.1.0 — scaffold (unreleased)
The hero feature, end to end, dependency-free.

- Enemy nameplate decoration that rides on Blizzard's plates with zero taint risk
  (overlay anchored, never reparenting the secure frame).
- **Interrupt cue**: gold glow + sound + `INTERRUPT` prompt when a kickable cast
  appears and your interrupt is off cooldown.
- **Uninterruptible padlock**: red bar + lock icon so you don't waste a kick.
- Interruptibility classified from a seed Intel Pack (`Data/KickableSpells.lua`),
  not the unreliable client flag. Unknown casts stay neutral (no false alarms).
- Per-class "is my kick ready?" detection (`Data/InterruptSpells.lua`).
- Enemy cast bars via live cast API with a combat-log fallback.
- Minimal, feature-detected threat tint (disables itself if the native threat API
  is absent; LibThreatClassic2 fallback is a TODO).
- Slash commands (`/vigil`, `/vg`) incl. `/vigil test` demo, and SavedVariables
  for settings.

### Next
- v0.2: custom plate skin, aura/DoT/CC timer row, threat fallback.
- v0.3: Ace3 + shareable Intel Pack import/export strings + intel-only consumer mode.
- Phase 2: Vigil Parse data layer.
