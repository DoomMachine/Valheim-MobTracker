# D-015 - OI-7: the old settings are copied at every start that finds no new settings file

- **Date:** 2026-11-03. Recorded the same day, after the answer.
- **Asked by:** the developer's assistant, one of five questions that the design of 0.9.0 left open (D-006).
- **Question (as asked):** "When should 0.9.0 copy the old settings file (com.mobtracker.plugin.cfg) to the new one
  (DoomMachine.MobTracker.cfg)? (D-006 chose: at the first start, if DoomMachine.MobTracker.cfg does not exist yet and
  the old file does, copy it and leave the old file in place.)"
- **Options offered** (both proposed by the developer's assistant, which marked the first as recommended):
  1. "Whenever new is missing (Recommended)" - "At every start that finds no DoomMachine.MobTracker.cfg and finds
     com.mobtracker.plugin.cfg, the old file is copied, and the old file is left in place. A player who later deletes
     DoomMachine.MobTracker.cfg to get the defaults gets the old settings back at the next start; to get the defaults,
     delete both files with the game closed. The README says so."
  2. "Only once, old renamed" - "The same copy, after which the old file is renamed to com.mobtracker.plugin.cfg.copied
     (renamed, not deleted). Deleting DoomMachine.MobTracker.cfg later gives the defaults. This changes D-006's 'leaves
     the old file in place', recorded as a dated amendment, and needs extra code and checks for the rename."
- **Chosen by the developer:** 1, "Whenever new is missing (Recommended)".
- **Reason:** no reason given.
- **Status:**
  - 2026-11-03: accepted; built in 0.9.0 (D-005). The implementation had been started with the recommended option
    before the answer came, so nothing changed with it.
