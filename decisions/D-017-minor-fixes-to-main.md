# D-017 - The minor fixes go to main, with no release; the version stays 0.9.0

- **Date:** 2026-11-03 (13:51). Recorded the same day, at the answer, while the fixes were being made (D-016).
- **Asked by:** the developer's assistant, before the fixes had finished their checks.
- **Question (as asked):** "Once the minor fixes pass every check, how should they ship? The warning-text fix is
  compiled into MobTracker.dll; the test and docs fixes are not."
- **Options offered** (all three proposed by the developer's assistant, which marked the first as recommended):
  1. "Push to main (Recommended)" - "After a docs-and-tools push audit, the fixes go to GitHub's main, together with the
     two local decision-log commits. The version stays 0.9.0 (text only keeps the version), so main's DLL differs from
     the 0.9.0 release in that one warning. The README gets an 'Unreleased' History line. Your installed 0.9.0 release
     stays as it is. The next release carries the new warning text."
  2. "Release 0.9.1 now" - "A patch release with the whole release cycle: release audit, publish, verify. Then the
     downloaded 0.9.1 zip is installed with the game closed. The new warning reaches players now. The README entry says
     0.9.1 instead of Unreleased."
  3. "Keep it local for now" - "The fixes are committed on a local branch only. Nothing is pushed or released until the
     next feature. The two local decision-log commits stay unpushed too (their copy in your private decisions
     repository is already pushed)."
- **Chosen by the developer:** 1, "Push to main (Recommended)".
- **Reason:** no reason given.
- **Status:**
  - 2026-11-03: accepted.
