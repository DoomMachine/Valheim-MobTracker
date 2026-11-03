# D-006 - OI-7: move the old settings file's settings over, and warn about an older copy

- **Date:** 2026-11-02. Recorded the same day, after the answer and before any work on it (this log was started then).
- **Asked by:** the developer's assistant, one of four questions about the next release (OI-7 in
  `docs/open-items.md`, opened by D-009).
- **Question (as asked):** "OI-7: what should the release do about players' old settings file
  com.mobtracker.plugin.cfg, and about an older MobTracker copy left in BepInEx/plugins?"
- **Options offered** (all three proposed by the developer's assistant, which marked the first as recommended):
  1. "Move it over + warn (Recommended)" - "At the first start, if DoomMachine.MobTracker.cfg does not exist yet and the
     old file does, MobTracker copies the old settings to the new name before reading any setting, says so once in the
     log, and leaves the old file in place. It also warns once when an older MobTracker (old id) is loaded beside it."
  2. "Move it over only" - "The same automatic copy of the old settings, with no warning about a leftover older copy
     (the README already says to remove it)."
  3. "No code: notes only" - "The README and release notes tell players to rename the old file with the game closed;
     MobTracker does nothing itself."
- **Chosen by the developer:** 1, "Move it over + warn (Recommended)".
- **Reason:** no reason given.
- **Status:**
  - 2026-11-02: accepted; to be built in 0.9.0 (D-005).
  - 2026-11-03: refined by D-011 (with an older copy loaded, 0.9.0 warns once and stays off) and D-015 (the copy runs at
    every start that finds no DoomMachine.MobTracker.cfg, and the old file is left in place).
