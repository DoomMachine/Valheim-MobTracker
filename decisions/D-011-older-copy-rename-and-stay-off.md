# D-011 - OI-7: beside an older MobTracker, 0.9.0 renames its assembly and stays off with one warning

- **Date:** 2026-11-03. Recorded the same day, after the answer.
- **Asked by:** the developer's assistant, one of five questions that the design of 0.9.0 left open (D-005, D-006).
- **Question (as asked):** "MobTracker 0.9.0: what should it do when an older MobTracker (0.8.0 or earlier, old id
  com.mobtracker.plugin) is still somewhere in BepInEx/plugins? (Builds of main made since the id change are not
  'older' here: BepInEx keeps only the newest copy of one id, so 0.9.0 runs beside them.)"
- **Options offered** (all three proposed by the developer's assistant, which marked the first as recommended):
  1. "Rename, stay off (Recommended)" - "0.9.0's assembly is renamed DoomMachine.MobTracker (the file stays
     MobTracker.dll). With an older copy loaded, 0.9.0 writes one warning to LogOutput.log and does nothing else: no
     window, alerts or tracking, no settings file written, nothing copied. The older copy runs as before with its own
     settings; MobTracker.log, if any, is the older copy's. Nothing shows on screen. Once the older DLL is removed, the
     next start that finds no DoomMachine.MobTracker.cfg copies its settings. An older copy whose own start failed still
     counts, so 0.9.0 stays off then too (read from BepInEx's code and an earlier test)."
  2. "Rename, both run" - "The same rename. Both copies run: F7 opens two windows, every watch alert shows and dings
     twice, and both may track a creature. MobTracker.log is the older copy's; 0.9.0 writes none, and its warning names
     that cause. 0.9.0 copies the old settings at its first start if DoomMachine.MobTracker.cfg does not exist yet."
  3. "No rename, no warning" - "The build stays as it is in this respect. With an older copy present, 0.9.0 does not
     run at all and the older copy runs twice ('MobTracker 0.8.0 loaded' twice, seen in a test; two windows on F7 and
     every alert twice, read from the code, not seen). No settings are copied until the older DLL is removed. D-006's
     warning clause is dropped, recorded as a dated amendment. The README tells players to remove the older DLL first."
- **Chosen by the developer:** 1, "Rename, stay off (Recommended)".
- **Reason:** no reason given.
- **Status:**
  - 2026-11-03: accepted; built in 0.9.0 (D-005). The implementation had been started with the recommended option
    before the answer came, so nothing changed with it.
  - 2026-11-03: built in 0.9.0 (tag `v0.9.0`); in force.
