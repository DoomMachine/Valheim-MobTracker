# D-001 - FW-11: a typed star count is added to the row's buttons

- **Date:** 2026-11-02. Recorded the same day, after the answer and before any work on it (this log was started then).
- **Asked by:** the developer's assistant, one of four questions that scoped FW-11 (`docs/open-items.md`; the request
  is D-010).
- **Question (as asked):** "FW-11 (exact star count): when a star count is typed into a row, how should it work with
  that row's buttons?"
- **Options offered** (both proposed by the developer's assistant, which marked the first as recommended):
  1. "Added to the buttons (Recommended)" - "A creature passes if it matches any marked button OR has exactly the typed
     number of stars. With only a count typed and no button marked, only that count passes. Clearing the field removes
     the count; the buttons stay as they were."
  2. "Replaces the buttons while typed" - "While a count is typed, only creatures with exactly that many stars pass, and
     the row's buttons are greyed out. Clearing the field brings the buttons back as they were."
- **Chosen by the developer:** 1, "Added to the buttons (Recommended)".
- **Reason:** no reason given.
- **Status:**
  - 2026-11-02: accepted; to be built in 0.9.0 (D-005).
  - 2026-11-03: refined by D-012 (the field's look) and D-014 (a click on All empties the field too).
  - 2026-11-03: built in 0.9.0 (tag `v0.9.0`), as D-012 and D-014 refined it; in force.
