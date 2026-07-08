# Vantage — listing copy for CurseForge / Wago

Paste-ready project description. Kept out of the packaged zip via `.pkgmeta`.

---

**Know exactly when to kick — and when not to waste it.**

Vantage is a zero-config interrupt and CC coach built into your nameplates, for
TBC Classic (Anniversary). It reads **your** kit — your class, your cooldowns,
even your pet and stance — and lights up the plate the moment acting matters:

- 🔔 **The interrupt cue.** A kickable enemy cast starts while your interrupt
  is ready **and the target is in its range** → the nameplate erupts: glow,
  sound, and an `INTERRUPT` prompt centered on the plate. On cooldown or too
  far away, no shout — when Vantage lights up, it means *now*.
- ⚖️ **The verdict.** As a flagged cast ends, the bar flashes what happened:
  teal `KICKED`, red `MISSED` (it completed while your stop sat ready), or
  `WASTED` when you spent a kick on an unkickable cast. You learn mid-pull,
  not in a spreadsheet afterwards.
- 🔒 **The padlock.** Casts that must NOT be kicked (uninterruptible boss
  casts, wasted-kick traps) get a padlock instead, so you hold your cooldown.
- 🧠 **It learns your dungeons.** No hand-made list covers every cast in the
  game — so Vantage watches. Any time a cast gets interrupted in front of it,
  yours or a groupmate's, it banks that spell as kickable (you can't interrupt
  an uninterruptible cast, so it's never wrong). Casts it had never heard of
  become real cues the next time they appear. All local, all automatic — no
  setup, no uploads — and it never overrides a verified "do not kick" marker.
- 🛑 **Every class, not just kickers.** No hard interrupt? Vantage offers your
  real answer instead — `FEAR`, `STUN`, `SILENCE`, `SHACKLE` — and it checks
  target immunities first, so it never tells you to fear a fear-immune boss.
  Warrior stances, Druid forms, shields, combo points, and Felhunter/pet
  abilities are all understood.
- ⚔️ **PvP mode.** Against enemy players no spell database is needed — any
  hard cast is fair game, so the cue works in arena, battlegrounds, and world
  PvP at any level.
- ✨ **A full nameplate skin** (toggleable): gradient health bars, crisp 1px
  borders, class colors, level text, a slim mana bar on casters, health text,
  gold target glow, bordered cast-bar icon with a live countdown, and your
  DoT/debuff timers with dispel-colored borders and a cooldown swipe.
- 📊 **Vantage Parse.** The stat Warcraft Logs can't show you: how many casts
  you *let through while your kick sat ready*. Vantage logs every decision it
  shows you, plus your cue→kick reaction time. `/vantage export`, paste into the
  free report page — everything decodes in your browser, nothing is uploaded:
  https://karlbonitz.github.io/Vantage/

**Zero configuration.** Install it and pull a caster pack — the defaults are
tuned. Everything is toggleable via `/vantage` (a native options panel).

**Zero dependencies.** No libraries, decorates the default Blizzard plates
(plays nice with taint), instant load.

Interruptibility starts from a hand-curated, verified spell database — all TBC
heroics, Karazhan, Gruul/Magtheridon, and SSC/Tempest Keep — not the client's
unreliable `notInterruptible` flag. From there it grows on its own: every cast
Vantage watches get interrupted is added automatically, so coverage expands to
whatever *you* run, including low-level and off-meta content.

*Early release: the curated pack keeps growing, and Vantage fills the rest in as
you play. Found a cast Vantage got wrong? Report it on GitHub:
https://github.com/karlbonitz/Vantage/issues*
