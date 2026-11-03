# D-013 - FW-11: an open range such as "5-" is not accepted

- **Date:** 2026-11-03. Recorded the same day, after the answer.
- **Asked by:** the developer's assistant, one of five questions that the design of 0.9.0 left open (D-002, D-004).
- **Question (as asked):** "Should an open range such as '5-' (five stars and up) be accepted in the count field?
  (D-002 offered numbers and ranges like '3-5, 8', not open ranges; D-004 set 0 to 100.)"
- **Options offered** (both proposed by the developer's assistant, which marked the first as recommended):
  1. "Not accepted (Recommended)" - "'5-' and '-5' show as invalid and are not applied. '5-100' gives five stars and up
     to 100. A creature with more than 100 stars passes only '2+ stars' or All, which follows from D-004."
  2. "'5-' means 5 to 100" - "'5-' is accepted and means the same as '5-100'. '-5' stays invalid (it reads as a
     negative number). A creature with more than 100 stars still matches no count, though '5-' may read as 'five and
     up' to a player."
- **Chosen by the developer:** 1, "Not accepted (Recommended)".
- **Reason:** no reason given.
- **Status:**
  - 2026-11-03: accepted; built in 0.9.0 (D-005). The implementation had been started with the recommended option
    before the answer came, so nothing changed with it.
  - 2026-11-03: built in 0.9.0 (tag `v0.9.0`); in force.
