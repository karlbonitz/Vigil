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
- 🎯 **Kick the right one first.** A caster pack all starts casting at once and
  you have exactly one kick. Vantage shouts for the cast that matters most — a
  heal outranks a nuke — and leaves the rest marked kickable but quiet. The cue
  answers *which* one, not just *whether*.
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
- 🌐 **A database everyone builds together.** What your game learns, you can
  share back: `/vantage contribute` sends an anonymous, evidence-checked blob
  (no character or realm — just the spell IDs you confirmed kickable and the
  interrupt that stopped each one) to a community pool. Once several independent
  players confirm a cast, it ships in the next update's shared pack — so coverage
  grows for the whole community, and new players inherit it on day one. A pooled
  kick stays quiet on your plates until your own game watches one land, so a bad
  entry can never scream a false `INTERRUPT` at you.
- 📨 **Or hand it straight to a friend.** `/vantage share` packs the kicks
  Vantage taught itself into a copy-paste string; your friend drops it into
  `/vantage import` and inherits your dungeon knowledge. No server in the middle,
  and curated data always wins.
- 🤝 **It plays with your group.** Zone into a dungeon Vantage has intel on and
  the **briefing** prints the kick sheet before the first pull. It learns your
  groupmates' interrupts from the combat log — nobody else needs the addon — so
  when a kickable cast is up and *your* kick is down, the cue quietly names who
  *is* ready. `/vantage kicks` reads out the party's available stops on demand,
  and `/vantage announce` (opt-in, throttled) calls your interrupts to party chat
  so nobody doubles up.
- 🛑 **Every class, not just kickers.** No hard interrupt? Vantage offers your
  real answer instead — `FEAR`, `STUN`, `SILENCE`, `SHACKLE` — and it checks
  target immunities *and* diminishing returns first, so it never tells you to
  fear a fear-immune boss or re-stun a target you've already stunned to immune.
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
  shows you, your cue→kick reaction time (as a median *and* a 90th percentile),
  the CC you broke, and the dispels you landed. `/vantage export`, paste into the
  free report page — everything decodes in your browser, nothing is uploaded:
  https://karlbonitz.github.io/Vantage/

**Zero configuration.** Install it and pull a caster pack — the defaults are
tuned. Everything is toggleable via `/vantage` (a native options panel).

**Featherweight.** Zero libraries — pure Blizzard API, decorating the default
plates (plays nice with taint) for a fast load.

Interruptibility starts from a hand-curated, verified spell database — all TBC
heroics, Karazhan, Gruul/Magtheridon, and SSC/Tempest Keep — not the client's
unreliable `notInterruptible` flag. From there it grows on its own: every cast
Vantage watches get interrupted is added automatically, so coverage expands to
whatever *you* run, including low-level and off-meta content.

*Early release: the curated pack keeps growing, Vantage fills the rest in as you
play, and `/vantage contribute` pools what you learn into the shared database.
Found a cast Vantage got wrong? Report it on GitHub:
https://github.com/karlbonitz/Vantage/issues*
