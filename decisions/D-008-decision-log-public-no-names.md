# D-008 - This decision log is public, and names roles rather than people

- **Date:** 2026-11-02. Recorded the same day, after the answer (this entry starts the log).
- **Asked by:** the developer's assistant, one of four questions about the next release.
- **Question (as asked):** "Your global rules ask for a decision log (decisions/, DECISIONS.md) at the repository root,
  recording who proposed each option. MobTracker's repository is public. Where should its log live?"
- **Options offered** (all three proposed by the developer's assistant, which marked the first as recommended). Two
  places in the quotes are replaced in square brackets: a name, as this decision asks, and a local folder path, which is
  never published.
  1. "In the public repo (Recommended)" - "decisions/, decisions/INDEX.md and DECISIONS.md in the repository, published
     with the next push; proposals are attributed to "[the assistant's name]", consistent with the README's Credits.
     Private matters go to a separate log outside the repository."
  2. "In the public repo, no names" - "The same files in the repository, but proposals are attributed by role
     ("proposed by the developer's assistant") rather than by name."
  3. "Private only" - "The whole log outside the repository ([a local folder]); nothing about decisions is published
     beyond docs/open-items.md."
- **Chosen by the developer:** 2, "In the public repo, no names" (not the recommended option).
- **Reason:** no reason given.
- **Status:**
  - 2026-11-02: accepted. `decisions/` holds the full entries and only grows: a status change is a new dated line, never
    an edit of earlier text, and a correction is a dated amendment. `decisions/INDEX.md` lists every decision ever
    recorded; `DECISIONS.md` lists the ones open or in force. Private matters go to a separate log outside the
    repository (option 1's words, which option 2 keeps: "The same files"). First published with 0.9.0 (D-005).
