# MobTracker decisions - index

Every decision ever recorded in this log, whatever its status, one line each; the full entries are the files beside
this one. The log only grows: a status change is a new dated line in the entry, never an edit of earlier text (D-008).
The decisions open or in force are also listed in [`DECISIONS.md`](../DECISIONS.md).

The log was started on 2026-11-02. Decisions taken before it (behaviour choices since 0.2.0) are recorded in
[`docs/open-items.md`](../docs/open-items.md), under "Decided or not planned - reopen only with a new reason" and
"Open questions for future releases", and in the README's History; they have not been copied here.

- [D-001](D-001-star-count-added-to-buttons.md) (2026-11-02; accepted): FW-11, a typed star count is added to the
  row's buttons.
- [D-002](D-002-star-count-numbers-and-ranges.md) (2026-11-02; accepted): FW-11, the field takes numbers and ranges
  ("3-5, 8").
- [D-003](D-003-star-count-both-rows.md) (2026-11-02; accepted): FW-11, both star rows (List and Alerts) get a field.
- [D-004](D-004-star-count-0-to-100.md) (2026-11-02; accepted): FW-11, counts from 0 to 100; anything else is not
  applied.
- [D-005](D-005-one-release-0.9.0.md) (2026-11-02; accepted): one release, 0.9.0, with the plugin id and the
  star-count field.
- [D-006](D-006-old-settings-file-move-and-warn.md) (2026-11-02; accepted): OI-7, move the old settings over and warn
  once about an older copy.
- [D-007](D-007-release-and-deploy.md) (2026-11-02; accepted): after every check, release on GitHub, then install the
  release.
- [D-008](D-008-decision-log-public-no-names.md) (2026-11-02; accepted): this log is public and names roles, not
  people.
- [D-009](D-009-plugin-id-as-a-text-fix.md) (2026-10-12; done on `main`, to be released in 0.9.0): plugin id
  `DoomMachine.MobTracker`, a text fix with no new version.
- [D-010](D-010-star-count-requested.md) (2026-10-12; accepted): FW-11 requested, logged first; every check once it is
  built.
- [D-011](D-011-older-copy-rename-and-stay-off.md) (2026-11-03; accepted): OI-7, beside an older MobTracker, 0.9.0
  renames its assembly and stays off with one warning.
- [D-012](D-012-count-field-label-and-red.md) (2026-11-03; accepted): FW-11, the count field has a label, "Exactly:"
  or "Invalid:", and red text while invalid.
- [D-013](D-013-no-open-ranges.md) (2026-11-03; accepted): FW-11, an open range such as "5-" is not accepted.
- [D-014](D-014-all-click-empties-field.md) (2026-11-03; accepted): FW-11, a click on All resets the whole row, its
  count field too.
- [D-015](D-015-copy-whenever-new-file-missing.md) (2026-11-03; accepted): OI-7, the old settings are copied at every
  start that finds no new settings file.
