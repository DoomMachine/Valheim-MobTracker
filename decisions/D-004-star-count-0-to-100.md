# D-004 - FW-11: counts from 0 to 100

- **Date:** 2026-11-02. Recorded the same day, after the answer and before any work on it (this log was started then).
- **Asked by:** the developer's assistant, one of four questions that scoped FW-11 (D-001).
- **Question (as asked):** "Which numbers should the field accept? (Stars = creature level minus one, as the list shows
  them.)"
- **Options offered** (all three proposed by the developer's assistant, which marked the first as recommended):
  1. "0 to 100 (Recommended)" - "0 means no star (the same as the No star button). A number outside 0-100, or anything
     that is not a whole number, is not applied, and the field shows that it is invalid."
  2. "Any whole number from 0" - "No upper limit; anything that is not a whole number of 0 or more is not applied, and
     the field shows that it is invalid."
  3. "1 and up only" - "No-star creatures stay with the No star button; 0 or anything that is not a whole number of 1 or
     more is not applied, and the field shows that it is invalid."
- **Chosen by the developer:** 1, "0 to 100 (Recommended)".
- **Reason:** no reason given.
- **Status:**
  - 2026-11-02: accepted; to be built in 0.9.0 (D-005).
  - 2026-11-03: refined by D-012 (how an invalid field shows) and D-013 (no open ranges).
  - 2026-11-03: built in 0.9.0 (tag `v0.9.0`), as D-012 and D-013 refined it; in force.
