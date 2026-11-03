# D-012 - FW-11: the count field has a label, "Exactly:" or "Invalid:", and red text while invalid

- **Date:** 2026-11-03. Recorded the same day, after the answer.
- **Asked by:** the developer's assistant, one of five questions that the design of 0.9.0 left open (D-004).
- **Question (as asked):** "How should each star row's typed-count field look? (D-004: the field shows when its text
  cannot be read.)"
- **Options offered** (both proposed by the developer's assistant, which marked the first as recommended):
  1. "Label + field (Recommended)" - "A label before the field: 'Exactly:' while its text can be read, 'Invalid:' while
     it cannot, with the field's text in red then. The field is 64 GUI units wide at the end of each row; each row grows
     by about 120 units, and the window (480 wide by default) widens to fit, by an amount not known until seen. Invalid
     text shows in words and in colour."
  2. "Field alone" - "The field alone at the end of each row, 64 units, no label. The window widens less, or not at
     all. Nothing on screen names the field; the README and the setting's description do. Invalid text shows only by
     its red colour, which a player who cannot tell red from the normal text colour may miss."
- **Chosen by the developer:** 1, "Label + field (Recommended)".
- **Reason:** no reason given.
- **Status:**
  - 2026-11-03: accepted; built in 0.9.0 (D-005). The implementation had been started with the recommended option
    before the answer came, so nothing changed with it.
  - 2026-11-03: built in 0.9.0 (tag `v0.9.0`); in force.
