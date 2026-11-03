# D-002 - FW-11: the field takes numbers and ranges

- **Date:** 2026-11-02. Recorded the same day, after the answer and before any work on it (this log was started then).
- **Asked by:** the developer's assistant, one of four questions that scoped FW-11 (D-001).
- **Question (as asked):** "How many star counts can one field hold?"
- **Options offered** (all three proposed by the developer's assistant, which marked the first as recommended):
  1. "Several, comma-separated (Recommended)" - "e.g. "3, 5" passes three-star and five-star creatures; each entry must
     be a whole number."
  2. "One number" - "Exactly one whole number per field."
  3. "Numbers and ranges" - "e.g. "3-5, 8": single numbers and ranges, comma-separated."
- **Chosen by the developer:** 3, "Numbers and ranges" (not the recommended option).
- **Reason:** no reason given.
- **Status:**
  - 2026-11-02: accepted; to be built in 0.9.0 (D-005). Cases the options did not cover (a range written high to low,
    an open range, a range past the largest count D-004 allows, repeated or overlapping entries, spaces, an empty
    entry) are left to the design; the docs will state each with its reason.
  - 2026-11-03: the open range was put to the developer instead: D-013, not accepted. The design decides the other
    cases, and `docs/open-items.md` is to state each with its reason (checked before the release).
  - 2026-11-03: built in 0.9.0 (tag `v0.9.0`); in force. Checked before the release: `docs/open-items.md` states each
    case the options left to the design with its reason ("How a star-count field reads its text", under "Decided or not
    planned").
