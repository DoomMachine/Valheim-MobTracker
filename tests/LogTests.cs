using System;
using System.Collections.Generic;
using System.Globalization;

namespace MobTracker
{
    /// <summary>
    /// MobTracker.log's decisions (LogRules), the text of every line it and VerboseLog write and the decisions three of
    /// those lines report (EventLines), 0.7.0. The
    /// texts are compared in full: README.md and docs\open-items.md quote them, and players search their logs for them.
    /// </summary>
    public static class LogTests
    {
        private static Action<string, bool, string> _check;

        private static void Eq(string label, string got, string want)
        {
            _check(label, got == want, got);
        }

        public static void Run(Action<string, bool, string> check)
        {
            _check = check;
            FileRules();
            Storms();
            Settings();
            TrackLines();
            AlertLines();
            ListLines();
            FindLines();
            FileOwnLines();
        }

        private static void FileRules()
        {
            // Which of MobTracker's own lines reach the file: every level by every switch state.
            int[] levels = { LogRules.Fatal, LogRules.Error, LogRules.Warning, LogRules.Message, LogRules.Info, LogRules.Debug };
            string got = "";
            foreach (bool errorLog in new[] { true, false })
            {
                foreach (bool verbose in new[] { false, true })
                {
                    got += (errorLog ? "E" : "e") + (verbose ? "V" : "v") + ":";
                    foreach (int level in levels)
                        got += LogRules.ToFile(level, errorLog, verbose) ? "1" : "0";
                    got += " ";
                }
            }
            Eq("log: ErrorLog takes Fatal, Error, Warning; VerboseLog everything; Message (the file's notes) always", got,
                "Ev:111100 EV:111111 ev:000100 eV:111111 ");

            // Another source's lines: each level from Unity's log, BepInEx, another plugin; with a switch on or not; while
            // MobTracker's settings are read or not. 0 skip, 1 take, 2 take if it names MobTracker's code.
            got = "";
            foreach (string source in new[] { "Unity Log", "BepInEx", "OtherMod" })
            {
                foreach (bool binding in new[] { false, true })
                {
                    got += source.Substring(0, 1) + (binding ? "b" : "-") + ":";
                    foreach (int level in levels)
                        got += LogRules.Foreign(source, level, true, binding).ToString(CultureInfo.InvariantCulture);
                    got += " ";
                }
            }
            Eq("log: another source - Unity's and BepInEx's errors if MobTracker's, BepInEx's warnings while its cfg is read, nothing else",
                got, "U-:220000 Ub:220000 B-:220000 Bb:221000 O-:000000 Ob:000000 ");
            got = "";
            foreach (int level in levels)
                got += LogRules.Foreign("Unity Log", level, false, true).ToString(CultureInfo.InvariantCulture)
                       + LogRules.Foreign("BepInEx", level, false, true).ToString(CultureInfo.InvariantCulture);
            Eq("log: with both switches off no other source's line is looked at", got, "000000000000");

            // An exception of MobTracker's code, in both stack forms; a message that only names it does not count.
            check("log: a Mono frame of MobTracker's code is found",
                LogRules.NamesMobTracker("NullReferenceException: x\nStack trace:\n  at MobTracker.Tracker.LateUpdate () [0x00012] in <abc>:0"), "");
            check("log: a Unity-style frame of MobTracker's code is found",
                LogRules.NamesMobTracker("IOException: y\nStack trace:\nMobTracker.EntityListWindow:DrawWindow (int)\nUnityEngine.GUI:CallWindowDelegate ()"), "");
            check("log: an exception that only names MobTracker in its message is not MobTracker's",
                !LogRules.NamesMobTracker("Exception: MobTracker.Tracker failed\nStack trace:\n  at OtherMod.Plugin.Update () [0x0] in <a>:0"), "");
            check("log: a message line that starts like a frame is still the message, not a frame",
                !LogRules.NamesMobTracker("MobTracker.Tracker:LateUpdate was patched by OtherMod\n  at OtherMod.Plugin.Update () [0x0] in <a>:0"), "");
            check("log: a frame of another namespace that starts with MobTracker is not MobTracker's",
                !LogRules.NamesMobTracker("E: m\n  at MobTrackerExtras.Thing.Do () [0x0] in <a>:0"), "");
            check("log: no text names nothing", !LogRules.NamesMobTracker(null) && !LogRules.NamesMobTracker(""), "");
            Eq("log: the repeat key is the first line and the first MobTracker frame",
                LogRules.RepeatKey("NRE: a\r\nStack trace:\r\n  at Utils.X () [0x0]\r\n  at MobTracker.Tracker.LateUpdate () [0x1] in <a>:0\r\n"),
                "NRE: a|MobTracker.Tracker.LateUpdate () [0x1] in <a>:0");
            check("log: the same throw from two places counts apart",
                LogRules.RepeatKey("NRE: a\n  at MobTracker.A.B ()") != LogRules.RepeatKey("NRE: a\n  at MobTracker.C.D ()"), "");

            // What BepInEx was given, as text.
            Eq("log: no data is an empty text", LogRules.TextOf(null), "");
            Eq("log: data whose text cannot be read is named so, not thrown", LogRules.TextOf(new Unreadable()),
                "(the text of this line could not be read: InvalidOperationException)");

            // A line as BepInEx writes it, and as the file writes it.
            Eq("log: a line looks like LogOutput.log's", LogRules.Line(LogRules.Info, "MobTracker", "MobTracker 0.7.0 loaded"),
                "[Info   :MobTracker] MobTracker 0.7.0 loaded");
            Eq("log: another source's name is padded as BepInEx pads it", LogRules.Line(LogRules.Error, "Unity Log", "x"),
                "[Error  : Unity Log] x");
            Eq("log: a level with no name of its own is its number", LogRules.Line(LogRules.Error | LogRules.Warning, "BepInEx", "y"),
                "[6      :   BepInEx] y");
            Eq("log: a file line is the date, time to the millisecond, frame and the line",
                LogRules.FileLine(new DateTime(2026, 10, 2, 15, 16, 3, 512), 48211, "[Info   :MobTracker] x"),
                "2026-10-02 15:16:03.512 f48211 [Info   :MobTracker] x");
            Eq("log: an unknown frame is f-", LogRules.FileLine(new DateTime(2026, 10, 2, 0, 0, 0), -1, "y"), "2026-10-02 00:00:00.000 f- y");
            Eq("log: a stack trace's further lines are indented, with CRLF, and the trailing newline goes",
                LogRules.FileLine(new DateTime(2026, 10, 2, 0, 0, 0), 7, "[Error  : Unity Log] E: m\nStack trace:\r\n  at MobTracker.A.B ()\n"),
                "2026-10-02 00:00:00.000 f7 [Error  : Unity Log] E: m\r\n    Stack trace:\r\n      at MobTracker.A.B ()");

            // Folders kept out.
            Eq("log: the game folder and the user folder are written as <game> and <user>, in any case",
                LogRules.Scrub(@"IOException: Sharing violation on path E:\Games\Valheim\BepInEx\config\a.cfg and c:\users\someone\x",
                    @"E:\Games\Valheim", @"C:\Users\someone"),
                @"IOException: Sharing violation on path <game>\BepInEx\config\a.cfg and <user>\x");
            Eq("log: a game folder inside the user folder is replaced first",
                LogRules.Scrub(@"at C:\Users\someone\AppData\r2\Valheim\BepInEx", @"C:\Users\someone\AppData\r2\Valheim", @"C:\Users\someone"),
                @"at <game>\BepInEx");
            Eq("log: a folder given with a trailing backslash is still found",
                LogRules.Scrub(@"in E:\Games\Valheim\BepInEx", @"E:\Games\Valheim\", null), @"in <game>\BepInEx");
            Eq("log: no folder known, or one too short, leaves the text", LogRules.Scrub(@"abc C:\x", null, "C:\\"), @"abc C:\x");

            check("log: a line that reaches the cap exactly fits, one byte more does not",
                LogRules.Fits(10, 5, 15) && !LogRules.Fits(10, 6, 15), "");
            check("log: the cap is 5 MB", LogRules.Cap == 5L * 1024 * 1024, LogRules.Cap.ToString(CultureInfo.InvariantCulture));

            Eq("log: an exception is described with its inner causes, no stack",
                LogRules.Describe(new InvalidOperationException("Patching exception in method X", new ArgumentException("bad"))),
                "InvalidOperationException: Patching exception in method X <- ArgumentException: bad");
            Eq("log: no exception is said so", LogRules.Describe(null), "(no exception)");
        }

        private sealed class Unreadable
        {
            public override string ToString()
            {
                throw new InvalidOperationException("no text");
            }
        }

        private static void Storms()
        {
            // A storm of one error: the first written, the rest within 60 s counted, the next after that written with the count.
            var limiter = new RepeatLimiter();
            int left;
            bool w1 = limiter.Write("k", 0, out left);
            bool w2 = limiter.Write("k", 0.016, out left);
            bool w3 = limiter.Write("k", 59.9, out left);
            bool other = limiter.Write("other", 1, out left);
            bool w4 = limiter.Write("k", 60.1, out left);
            _check("log: a repeated error is written once a minute, with how many were left out",
                w1 && !w2 && !w3 && other && w4 && left == 2, w1 + " " + w2 + " " + w3 + " " + other + " " + w4 + " " + left);
            bool w5 = limiter.Write("k", 61, out left);
            _check("log: the count starts again after it is written", !w5 && limiter.LeftOutInAll() == 1, "");
            _check("log: the closing count forgets every key", limiter.LeftOutInAll() == 0 && limiter.Write("k", 62, out left) && left == 0, "");
            var many = new RepeatLimiter();
            for (int i = 0; i <= RepeatLimiter.MaxKeys; i++)
                many.Write("key" + i, 0, out left);
            _check("log: past 32 keys the oldest is forgotten, and written again; a newer one is still counted", many.Write("key0", 1, out left) && !many.Write("key2", 1, out left), "");
        }

        private static void Settings()
        {
            // A setting dragged: the first change at once, the rest in one line once it has held still for a second.
            var settler = new SettingSettler();
            string first = settler.Changed("Tracking.ArrowSize", "0.6", "0.7", 10);
            string second = settler.Changed("Tracking.ArrowSize", "0.7", "0.8", 10.2);
            string third = settler.Changed("Tracking.ArrowSize", "0.8", "1.2", 10.9);
            List<string> early = settler.Due(11.5);
            List<string> due = settler.Due(12.0);
            Eq("log: a setting's first change is written at once", first, "Setting: Tracking.ArrowSize = '0.7' (was '0.6')");
            _check("log: the rest of a burst wait until the setting holds still for a second, then one line",
                second == null && third == null && early.Count == 0 && due.Count == 1
                && due[0] == "Setting: Tracking.ArrowSize = '1.2' (was '0.6'; 3 changes in 1 s, then held still)", string.Join(" | ", due));
            _check("log: a lone change writes no second line",
                settler.Changed("Alerts.AutoTrack", "true", "false", 20) != null && settler.Due(25).Count == 0 && !settler.Busy, "");

            var pairs = new List<KeyValuePair<string, string>>
            {
                new KeyValuePair<string, string>("General.ListKey", "F7"),
                new KeyValuePair<string, string>("Alerts.Watchlist", "Troll,Boar")
            };
            Eq("log: the settings line names each setting with its cfg text", EventLines.Settings(pairs),
                "Settings: General.ListKey = 'F7', Alerts.Watchlist = 'Troll,Boar'");
            Eq("log: a session that began, KeepBetweenSessions on", EventLines.Session(true, true),
                "Session: began - a world was entered; KeepBetweenSessions is on, nothing is set back");
            Eq("log: a session that ended, KeepBetweenSessions off", EventLines.Session(false, false),
                "Session: ended - back at the main menu; KeepBetweenSessions is off");
            Eq("log: a local player", EventLines.Player(true), "Player: a local player is here");
            Eq("log: no local player", EventLines.Player(false), "Player: no local player (dead and removed, or not in a world)");
            Eq("log: a patch class applied", EventLines.Patched("UiRaycastPatch"), "Load: UiRaycastPatch applied");
            Eq("log: TomTom not installed", EventLines.CompatSkipped("DoomMachine.TomTom", false), "Load: DoomMachine.TomTom is not installed");
            Eq("log: Wayfinder installed but not loaded", EventLines.CompatSkipped("DoomMachine.Wayfinder", true),
                "Load: DoomMachine.Wayfinder is installed but did not load, so its keys are left alone");
        }

        private static void TrackLines()
        {
            Eq("log: stars by level", EventLines.Stars(1) + "|" + EventLines.Stars(2) + "|" + EventLines.Stars(3) + "|" + EventLines.Stars(4),
                "no star|1 star|2 stars|3 stars");
            Eq("log: a creature is its label and its prefab", EventLines.Creature("Greydwarf **", "Greydwarf"), "Greydwarf ** (Greydwarf)");
            Eq("log: a track start names the creature, stars, distance and what it replaces",
                EventLines.TrackStarted("Boar *", "Boar", 2, 33.6f, false, false, "Deer (Deer)"),
                "Track: started - Boar * (Boar), 1 star, 34 m away; replaces Deer (Deer)");
            Eq("log: a track start of a tamed creature inside a dungeon, with no player",
                EventLines.TrackStarted("Wolf", "Wolf", 1, -1f, true, true, null), "Track: started - Wolf (Wolf), no star, tamed, inside a dungeon");
            Eq("log: an area's track start", EventLines.TrackStartedArea("Troll spawn area", 812.4f, "Boar (Boar)"),
                "Track: started - Troll spawn area, 812 m away; replaces Boar (Boar)");
            Eq("log: a stop says how long it was tracked", EventLines.TrackStopped("Boar (Boar)", 12.6f), "Track: stopped - Boar (Boar) after 13 s");
            Eq("log: a creature seen dead, the option on", EventLines.TrackLost("Boar (Boar)", true, false, true),
                "Track: lost Boar (Boar) - seen dead on this client");
            Eq("log: a creature gone, tamed, the option off", EventLines.TrackLost("Wolf (Wolf)", false, true, false),
                "Track: lost Wolf (Wolf) - gone from this client (out of range, despawned, or killed while another player's game ran it); it was tamed; Always track nearest watched is off");
            Eq("log: no local player ends a tracking", EventLines.TrackNoPlayer("Boar (Boar)"),
                "Track: no local player (dead and removed, or left the world) - ends the tracking of Boar (Boar)");
            Eq("log: an area reached", EventLines.TrackReached("Troll spawn area"), "Track: reached Troll spawn area (within 30 m on the flat)");
            Eq("log: a tracked creature tamed", EventLines.TrackTamed("Wolf (Wolf)"),
                "Track: Wolf (Wolf) is tamed now - losing it starts no Always track nearest watched wait");
            Eq("log: the guide line names every reason that holds", EventLines.Guide(true, true, false, false, false, true),
                "Guide: hidden - HUD hidden (Ctrl+F3), teleporting");
            Eq("log: every guide reason", EventLines.Guide(true, true, true, true, true, true),
                "Guide: hidden - HUD hidden (Ctrl+F3), in a cutscene, player dead, waiting to respawn, teleporting");
            Eq("log: the guide hidden for a reason gone by the time it was read", EventLines.Guide(true, false, false, false, false, false),
                "Guide: hidden - reason gone by the time it was looked at");
            Eq("log: the guide shown again", EventLines.Guide(false, true, true, true, true, true), "Guide: shown again");
            string path = "";
            for (int state = 0; state <= 5; state++)
                path += EventLines.GroundPath(state, 40, 7.4f) + "|";
            Eq("log: the six ground-path states", path,
                "Ground path: complete, 40 points|"
                + "Ground path: partial - ends 7 m short of the target, so the arrow shows too (40 points)|"
                + "Ground path: none - the game's pathfinding is not there; the arrow shows|"
                + "Ground path: none - no walkable ground found near you or near the target; the arrow shows|"
                + "Ground path: none - no path found (navigation tiles may still be building); the arrow shows|"
                + "Ground path: none - the path found has no length; the arrow shows|");
            Eq("log: an empty look counts what each test turned away, with the re-track's prefix", EventLines.EmptyLook(5, 0, 2, 0, 1, 2),
                "Always track nearest watched: look found nothing to take - 5 creature(s) of watched types loaded: 2 tamed, 1 outside AlertRadius, 2 on the other side of a dungeon entrance");
            Eq("log: an empty look with every reason", EventLines.EmptyLook(5, 1, 1, 1, 1, 1),
                "Always track nearest watched: look found nothing to take - 5 creature(s) of watched types loaded: 1 not on the network yet, 1 tamed, 1 outside the Alerts: stars, 1 outside AlertRadius, 1 on the other side of a dungeon entrance");
            Eq("log: an empty look with none loaded says so", EventLines.EmptyLook(0, 0, 0, 0, 0, 0),
                "Always track nearest watched: look found nothing to take - no creature of a watched type is loaded");
            Eq("log: an empty look whose creatures all passed (gone during the look)", EventLines.EmptyLook(2, 0, 0, 0, 0, 0),
                "Always track nearest watched: look found nothing to take - 2 creature(s) of watched types loaded: none turned away (gone during the look)");
        }

        private static void AlertLines()
        {
            Eq("log: an alert line counts the others of its check", EventLines.Alert("Troll", "Troll", 1, 120.4f, 3),
                "Alert: Troll (Troll), no star, 120 m away (+2 more in this check)");
            Eq("log: an alert alone", EventLines.Alert("Boar **", "Boar", 3, 9.5f, 1), "Alert: Boar ** (Boar), 2 stars, 10 m away");
            string auto = "";
            for (int outcome = 0; outcome <= 4; outcome++)
                auto += EventLines.AutoTrack(outcome, "Deer (Deer)") + "|";
            Eq("log: the five Auto-track outcomes", auto,
                "Auto-track: took it|Auto-track: off, so not taken|Auto-track: not taken - Deer (Deer) is tracked|"
                + "Auto-track: not taken - Always track nearest watched is waiting and chooses at its next look|"
                + "Auto-track: not taken - it is on the other side of a dungeon entrance|");
            Eq("log: the alert memory cleared", EventLines.AlertMemoryCleared(4),
                "Alert: no local player, so the alert memory of 4 creature(s) is cleared - each watched creature can alert again");
            Eq("log: the Alerts: stars in effect", EventLines.AlertStars("1 star + 2 stars"), "Alert: the star filter in effect is now 1 star + 2 stars");
            Eq("log: a watched creature that does not alert is named once, with the reason",
                EventLines.NotAlerting("Boar *", "Boar", 2, 140.2f, EventLines.AwayRadius, "All"),
                "Alert: none for Boar * (Boar), 1 star, 140 m away - outside AlertRadius (said once for this creature)");
            Eq("log: the not-alerting line's other three reasons, the stars one naming the filter in effect",
                EventLines.NotAlerting("Boar", "Boar", 1, 3f, EventLines.AwayNotNetworked, "All") + "|"
                + EventLines.NotAlerting("Wolf", "Wolf", 1, 4f, EventLines.AwayTamed, "All") + "|"
                + EventLines.NotAlerting("Troll **", "Troll", 3, 50f, EventLines.AwayStars, "No star + 1 star"),
                "Alert: none for Boar (Boar), no star, 3 m away - not on the network yet (said once for this creature)|"
                + "Alert: none for Wolf (Wolf), no star, 4 m away - tamed (said once for this creature)|"
                + "Alert: none for Troll ** (Troll), 2 stars, 50 m away - its stars are not in the Alerts: filter (No star + 1 star) (said once for this creature)");
            // The alert poll never hands these over (it asks no dungeon side, and writes nothing for a creature that
            // passes), but each code still has its own words: none is said as another.
            Eq("log: the not-alerting line's words for the dungeon side, a creature that passes, and a code it does not know",
                EventLines.NotAlerting("Draugr", "Draugr", 1, 60f, EventLines.AwayOtherSide, "All") + "|"
                + EventLines.NotAlerting("Draugr", "Draugr", 1, 60f, EventLines.Passes, "All") + "|"
                + EventLines.NotAlerting("Draugr", "Draugr", 1, 60f, 9, "All"),
                "Alert: none for Draugr (Draugr), no star, 60 m away - on the other side of a dungeon entrance (said once for this creature)|"
                + "Alert: none for Draugr (Draugr), no star, 60 m away - no test turns it away (said once for this creature)|"
                + "Alert: none for Draugr (Draugr), no star, 60 m away - reason 9 not known (said once for this creature)");

            // Which test turns a watched creature away: the first that fails, in the alert's order (network, tamed, stars,
            // radius), then the re-track's dungeon side. Each row fails one test, then each pair whose order matters.
            // (networked, tamed, starsAccepted, withinRadius, sameSide)
            bool[][] cases =
            {
                new[] { true, false, true, true, true },
                new[] { false, false, true, true, true }, new[] { true, true, true, true, true }, new[] { true, false, false, true, true },
                new[] { true, false, true, false, true }, new[] { true, false, true, true, false },
                new[] { false, true, false, false, false }, new[] { true, true, false, false, false }, new[] { true, false, false, false, false },
                new[] { true, false, true, false, false }
            };
            string away = "";
            foreach (bool[] c in cases)
                away += EventLines.TurnedAway(c[0], c[1], c[2], c[3], c[4]).ToString(CultureInfo.InvariantCulture);
            Eq("log: the first test that turns a watched creature away - network, tamed, stars, radius, then the dungeon side",
                away, "0123451234");
            check("log: the reasons are the codes the lines read", EventLines.Passes == 0 && EventLines.AwayNotNetworked == 1 && EventLines.AwayTamed == 2
                && EventLines.AwayStars == 3 && EventLines.AwayRadius == 4 && EventLines.AwayOtherSide == 5, "");

            // What Auto-track did, worked out after its test.
            // (generation now, generation at the alert, tracking a creature, its target is the alerted one, AutoTrack on, the re-track waits)
            object[][] autoCases =
            {
                new object[] { 5, 4, true, true, true, false },     // took it
                new object[] { 4, 4, true, true, true, false },     // tracked before the alert already: not taken, it is tracked
                new object[] { 5, 4, true, false, true, false },    // the tracking changed, but to another creature
                new object[] { 5, 4, false, true, true, false },    // the alerted creature left as Target, no creature tracked now
                new object[] { 4, 4, true, false, false, false },   // off, though a creature is tracked: off is said
                new object[] { 4, 4, false, false, false, true },   // off, though the re-track waits: off is said
                new object[] { 4, 4, true, false, true, true },     // a creature tracked while the re-track waits: tracked is said
                new object[] { 4, 4, false, false, true, true },    // the re-track waits
                new object[] { 4, 4, false, false, true, false }    // none of those: the other side of a dungeon entrance
            };
            string autoGot = "";
            foreach (object[] c in autoCases)
                autoGot += EventLines.AutoTrackOutcome((int)c[0], (int)c[1], (bool)c[2], (bool)c[3], (bool)c[4], (bool)c[5]).ToString(CultureInfo.InvariantCulture);
            Eq("log: Auto-track's outcome - taken only when the tracking changed since the alert to that creature; else off, tracked, waiting, other side, in that order",
                autoGot, "022411234");
            Eq("log: the ding's volume is written with a point", EventLines.DingPlayed(0.8f), "Ding: played at AlertVolume 0.8");
            Eq("log: no ding without its mixer group", EventLines.DingNotPlayed(false),
                "Ding: not played - the game's interface-sound mixer group is not found (yet)");
            Eq("log: no ding without its audio source", EventLines.DingNotPlayed(true), "Ding: not played - it has no audio source");
            Eq("log: the mixer's group search failed", EventLines.DingGroupSearch("ArgumentException"),
                "Ding: the mixer's own group search failed (ArgumentException); looking for the GUI group another way");

            // A comma culture must not reach the file: every number is written with the invariant culture.
            var culture = CultureInfo.CurrentCulture;
            try
            {
                CultureInfo.CurrentCulture = new CultureInfo("de-DE");
                Eq("log: under a comma culture the ding volume still has a point", EventLines.DingPlayed(0.85f), "Ding: played at AlertVolume 0.85");
                Eq("log: under a comma culture the file line's time is unchanged",
                    LogRules.FileLine(new DateTime(2026, 10, 2, 1, 2, 3, 4), 1, "x"), "2026-10-02 01:02:03.004 f1 x");
            }
            finally
            {
                CultureInfo.CurrentCulture = culture;
            }

            // The alert gate's two read-only answers the verbose log asks (0.7.0).
            var gate = new AlertGate<int>();
            gate.ShouldAlert(1, true, false, 5f, 0f);
            gate.ShouldAlert(2, false, false, 5f, 0f);
            _check("log: the alert gate counts and knows the creatures that had their alert",
                gate.Count == 1 && gate.Has(1) && !gate.Has(2), gate.Count.ToString(CultureInfo.InvariantCulture));
            gate.Clear();
            _check("log: after Clear it holds none", gate.Count == 0 && !gate.Has(1), "");
        }

        private static void ListLines()
        {
            Eq("log: the list opened, nearby", EventLines.ListOpened(false, "All"), "List: opened - nearby view, List: All");
            Eq("log: the list opened, all types", EventLines.ListOpened(true, "All"), "List: opened - all types view");
            Eq("log: the list closed by Escape or B", EventLines.ListClosed(EventLines.ClosedByBack), "List: closed - Escape or the gamepad's B");
            Eq("log: the list closed by ListKey", EventLines.ListClosed(EventLines.ClosedByKey), "List: closed - ListKey");
            Eq("log: the list closed by Find area", EventLines.ListClosed(EventLines.ClosedByFind), "List: closed - Find area");
            // A close no caller named: (inventory open, a local player here).
            Eq("log: a close no caller named - the inventory first, then no player, else not known",
                EventLines.ClosedUnseen(true, true) + "|" + EventLines.ClosedUnseen(true, false) + "|" + EventLines.ClosedUnseen(false, false) + "|"
                + EventLines.ClosedUnseen(false, true),
                "the inventory opened over it|the inventory opened over it|no local player|(cause not known)");
            Eq("log: a button clicked", EventLines.Clicked("Stop tracking"), "List: Stop tracking clicked");
            Eq("log: a row's button clicked", EventLines.RowClicked("Track", "Boar * (tamed)", "Boar"), "List: Track clicked on Boar * (tamed) (Boar)");
            Eq("log: the view switched", EventLines.ViewSwitched(true) + "|" + EventLines.ViewSwitched(false),
                "List: view switched to all types|List: view switched to nearby");
            Eq("log: a refused ListKey names every reason that holds", EventLines.ListKeyRefused("F7", false, false, true, false, false, true, false),
                "List: F7 pressed - the list stays shut: you are typing in a game text field (chat, a sign, a map pin's name, the console), the inventory is open");
            Eq("log: a refused ListKey, every reason", EventLines.ListKeyRefused("F7", false, false, false, true, true, false, true),
                "List: F7 pressed - the list stays shut: the pause menu is open, the build menu is open, the Barber Station is open");
            Eq("log: a typing ListKey over the open list's search box", EventLines.ListKeyRefused("L", true, true, false, false, false, false, false),
                "List: L pressed - the list stays open: it types, and a text field has the keyboard");
        }

        private static void FindLines()
        {
            Eq("log: Find area not started", EventLines.FindNotStarted(), "Find area: not started - no player, world generator or zone system yet");
            Eq("log: Find area's HUD answer", EventLines.FindSays("No zone loaded yet - try again in a moment"),
                "Find area: the HUD says 'No zone loaded yet - try again in a moment'");
            Eq("log: a search replaced", EventLines.FindReplaced(), "Find area: the search still running is stopped for the new one");
            Eq("log: a search done", EventLines.FindDone("Troll", 812, 40, 1234, 5),
                "Find area: Troll searched in 812 ms over 40 frame(s) - 1234 candidate zone(s), 5 area(s)");
            Eq("log: area pins removed", EventLines.PinsRemoved(5), "Find area: 5 area pin(s) removed");
            Eq("log: the map's delete took an area pin", EventLines.MapDeleteTookAreaPin("Troll area"),
                "Map: the delete gesture removed the area pin 'Troll area', not a pin of yours");
        }

        private static void FileOwnLines()
        {
            Eq("log: what the file gets, every switch state - with both off still these notes and the closing line",
                EventLines.LoggingNow(true, false) + "|" + EventLines.LoggingNow(false, true) + "|" + EventLines.LoggingNow(false, false) + "|"
                + EventLines.LoggingNow(true, true),
                "MobTracker.log gets MobTracker's warnings and errors|MobTracker.log gets every MobTracker line, events included|"
                + "MobTracker.log gets only these Logging notes and its closing line until ErrorLog or VerboseLog is turned on|"
                + "MobTracker.log gets every MobTracker line, events included");
            Eq("log: a verbose line that could not be put together, said once per site",
                EventLines.VerboseFailed("NullReferenceException", "Alert"),
                "A verbose line could not be written (NullReferenceException in Alert); what it describes was not affected. Said once.");
            Eq("log: a switch note says what the file gets now", EventLines.LoggingSwitch("VerboseLog", false, true, false),
                "Logging: VerboseLog turned off - MobTracker.log gets MobTracker's warnings and errors; LogOutput.log gets every MobTracker line as before");
            Eq("log: the header", EventLines.Header("0.7.0", "0.221.4", "5.4.23.3", "at the game's start"),
                "MobTracker 0.7.0 - MobTracker.log opened at the game's start; Valheim 0.221.4; BepInEx 5.4.23.3");
            Eq("log: the header's switches", EventLines.HeaderSwitches(true, false),
                "Logging: ErrorLog on, VerboseLog off - MobTracker.log gets MobTracker's warnings and errors; LogOutput.log gets every MobTracker line as before");
            Eq("log: the last start kept in MobTracker.log", EventLines.PrevNotWritten("UnauthorizedAccessException"),
                "=== MobTracker-prev.log could not be written (UnauthorizedAccessException), so the last game start's lines are kept above this one ===");
            Eq("log: the cap", EventLines.CapReached(LogRules.Cap),
                "MobTracker.log has reached 5 MB, so nothing more is written to it until the game starts again; LogOutput.log still gets every MobTracker line");
            Eq("log: errors left out", EventLines.LeftOut(59),
                "(the error below came 59 more time(s) since it was last written here; those were left out)");
            Eq("log: the closing line", EventLines.Closing(0), "MobTracker.log closed - the game is quitting");
            Eq("log: the closing line with errors left out", EventLines.Closing(3),
                "MobTracker.log closed - the game is quitting; 3 repeated error(s) were left out since they were last written");
            Eq("log: the file could not be opened - the type only, never the message (it holds a path)", EventLines.OpenFailed("IOException"),
                "MobTracker.log could not be opened (IOException; another running copy of the game may hold it, or it is read-only), so none is written for now; LogOutput.log still gets every MobTracker line.");
            Eq("log: a line could not be written", EventLines.WriteFailed("IOException"),
                "MobTracker.log could not be written (IOException) and is closed until the game starts again; LogOutput.log still gets every MobTracker line.");
        }

        private static void check(string label, bool condition, string detail)
        {
            _check(label, condition, detail);
        }
    }
}
