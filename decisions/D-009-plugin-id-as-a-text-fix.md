# D-009 - The plugin id becomes DoomMachine.MobTracker, as a text fix with no new version

- **Date:** 2026-10-12. Recorded later, on 2026-11-02, when this log was started; the sources are the developer's
  request and the commits named below.
- **Proposed by:** the developer (a request, not a question; no options were offered).
- **The request (quoted in part):** "when previewed in-game via Configuration Manager, the plugin is listed as
  MobTracker 0.8.0 (com.mobtracker.plugin), which lacks the author name. For example, TomTom reads TomTom 1.7.0
  (DoomMachine.TomTom). As such, MobTracker should read (DoomMachine.MobTracker). Treat this as a minor text fix that
  doesn't require a version bump or additional re-auditing, since a simple text string needs updating."
- **Chosen by the developer:** as requested.
- **Reason (the developer's words):** "since a simple text string needs updating".
- **Status:**
  - 2026-10-12: done on `main` in `9ebf3fc`, the version kept at 0.8.0. The developer's assistant then reported that the
    change was more than text: BepInEx names a plugin's settings file after its id, so the file became
    `DoomMachine.MobTracker.cfg`, and the old `com.mobtracker.plugin.cfg` is no longer read. Opened as OI-7.
  - 2026-10-12: after that report the developer asked: "Please run all checks, validations, and mutators, as needed."
    Done in `161e8c3` (the README names the settings file by version) and `bfd3b02` (checks and planted defects for the
    plugin id).
  - 2026-11-02: to be released in 0.9.0 (D-005), with D-006 for the old settings file.
  - 2026-11-03: completed in 0.9.0 (tag `v0.9.0`), with D-006, D-011 and D-015 for the old settings file; the id is in
    force.
