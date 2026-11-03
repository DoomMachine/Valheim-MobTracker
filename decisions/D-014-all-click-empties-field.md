# D-014 - FW-11: a click on All resets the whole row, its count field too

- **Date:** 2026-11-03. Recorded the same day, after the answer.
- **Asked by:** the developer's assistant, one of five questions that the design of 0.9.0 left open (D-001).
- **Question (as asked):** "With a count typed in a row, what should a click on that row's All button do to the count
  field? (The rule so far: 'a click on All resets a row'. D-001: clearing the field removes the count and leaves the
  buttons as they were.)"
- **Options offered** (both proposed by the developer's assistant, which marked the first as recommended):
  1. "Empties the field (Recommended)" - "A click on All resets the whole row: no category marked and the field
     emptied, so the row passes every creature and All shows as selected. The typed counts are gone; type them again to
     use them."
  2. "Keeps the field" - "A click on All takes off the marked categories only, and the field keeps its counts. With
     counts left and no category marked, the row passes only those counts, so All does not show as selected. To pass
     every creature, the player also empties the field."
- **Chosen by the developer:** 1, "Empties the field (Recommended)".
- **Reason:** no reason given.
- **Status:**
  - 2026-11-03: accepted; built in 0.9.0 (D-005). The implementation had been started with the recommended option
    before the answer came, so nothing changed with it.
  - 2026-11-03: built in 0.9.0 (tag `v0.9.0`); in force.
