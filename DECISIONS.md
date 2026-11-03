# MobTracker - decisions open or in force

One line each; the full entries are in [`decisions/`](decisions/), and every decision ever recorded, whatever its
status, is in [`decisions/INDEX.md`](decisions/INDEX.md). The log names roles, not people (D-008).

- D-001 (2026-11-02) FW-11: a typed star count is added to the row's buttons -
  [entry](decisions/D-001-star-count-added-to-buttons.md)
- D-002 (2026-11-02) FW-11: the field takes numbers and ranges, e.g. "3-5, 8" -
  [entry](decisions/D-002-star-count-numbers-and-ranges.md)
- D-003 (2026-11-02) FW-11: both star rows get a field, each with its own setting -
  [entry](decisions/D-003-star-count-both-rows.md)
- D-004 (2026-11-02) FW-11: counts from 0 to 100; anything else is not applied and shown as invalid -
  [entry](decisions/D-004-star-count-0-to-100.md)
- D-006 (2026-11-02) OI-7: copy the old settings file's settings over and warn about an older copy (refined by D-011
  and D-015) - [entry](decisions/D-006-old-settings-file-move-and-warn.md)
- D-008 (2026-11-02) This decision log is public and names roles, not people -
  [entry](decisions/D-008-decision-log-public-no-names.md)
- D-009 (2026-10-12) Plugin id `DoomMachine.MobTracker`, as a text fix with no new version (done on `main`; released in
  0.9.0) - [entry](decisions/D-009-plugin-id-as-a-text-fix.md)
- D-011 (2026-11-03) OI-7: beside an older MobTracker, 0.9.0 renames its assembly and stays off with one warning -
  [entry](decisions/D-011-older-copy-rename-and-stay-off.md)
- D-012 (2026-11-03) FW-11: the count field has a label, "Exactly:" or "Invalid:", and red text while invalid -
  [entry](decisions/D-012-count-field-label-and-red.md)
- D-013 (2026-11-03) FW-11: an open range such as "5-" is not accepted -
  [entry](decisions/D-013-no-open-ranges.md)
- D-014 (2026-11-03) FW-11: a click on All resets the whole row, its count field too -
  [entry](decisions/D-014-all-click-empties-field.md)
- D-015 (2026-11-03) OI-7: the old settings are copied at every start that finds no new settings file -
  [entry](decisions/D-015-copy-whenever-new-file-missing.md)
- D-016 (2026-11-03) The 0.9.0 release audit's minor items are worked through now, not left for the next change -
  [entry](decisions/D-016-minor-items-now.md)
