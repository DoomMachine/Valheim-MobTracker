using System;
using System.Collections.Generic;

namespace MobTracker
{
    public static class TestMain
    {
        private static int _failures;
        private static int _passes;

        public static int Main()
        {
            StarFilterTests();
            StarSetTests();
            NoneTests();
            SettleTests();
            AlertsRowTests();
            RulesTests();
            SpacingTests();
            OpenRuleTests();
            AlertGateTests();
            AlertStarFilterTests();
            RetrackTests();
            RefreshTests();
            PointerTests();
            ListKeyTests();
            Console.WriteLine(_failures == 0
                ? "ALL TESTS PASSED (" + _passes + ")"
                : _failures + " TEST(S) FAILED, " + _passes + " passed");
            return _failures == 0 ? 0 : 1;
        }

        // The five buttons' categories, level by level. Stars are level minus one: 1 = none, 2 = one star, 3 = two stars.
        private static void StarFilterTests()
        {
            var expected = new Dictionary<StarFilter, Func<int, bool>>
            {
                { StarFilter.All, l => true },
                { StarFilter.NoStars, l => l <= 1 },
                { StarFilter.OneStar, l => l == 2 },
                { StarFilter.TwoStars, l => l == 3 },
                { StarFilter.TwoOrMoreStars, l => l >= 3 },
            };
            foreach (var pair in expected)
            {
                var wrong = new List<int>();
                for (int level = -1; level <= 10; level++)
                {
                    if (StarFilters.Accepts(pair.Key, level) != pair.Value(level)) wrong.Add(level);
                }
                Check("stars: " + pair.Key + " accepts exactly its levels", wrong.Count == 0, "wrong at levels " + string.Join(",", wrong));
            }

            // The request's own examples: "Deer", "Deer *" (one star), two stars, and a modded three.
            Check("stars: a plain Deer (level 1) is 'no star', not 1 or 2+ stars",
                StarFilters.Accepts(StarFilter.NoStars, 1) && !StarFilters.Accepts(StarFilter.OneStar, 1) && !StarFilters.Accepts(StarFilter.TwoOrMoreStars, 1), "");
            Check("stars: 'Deer *' (level 2) is '1 star' only",
                StarFilters.Accepts(StarFilter.OneStar, 2) && !StarFilters.Accepts(StarFilter.NoStars, 2)
                && !StarFilters.Accepts(StarFilter.TwoStars, 2) && !StarFilters.Accepts(StarFilter.TwoOrMoreStars, 2), "");
            Check("stars: two stars (level 3) is both '2 stars' and '2+ stars'",
                StarFilters.Accepts(StarFilter.TwoStars, 3) && StarFilters.Accepts(StarFilter.TwoOrMoreStars, 3), "");
            Check("stars: a modded three-star creature (level 4) is '2+ stars' but not '2 stars'",
                StarFilters.Accepts(StarFilter.TwoOrMoreStars, 4) && !StarFilters.Accepts(StarFilter.TwoStars, 4), "");

            Check("stars: labels", StarFilters.Label(StarFilter.All) == "All" && StarFilters.Label(StarFilter.NoStars) == "No star"
                && StarFilters.Label(StarFilter.OneStar) == "1 star" && StarFilters.Label(StarFilter.TwoStars) == "2 stars"
                && StarFilters.Label(StarFilter.TwoOrMoreStars) == "2+ stars", "");

            // A value outside the enum behaves as All.
            StarFilter bogus = (StarFilter)7;
            Check("stars: an out-of-range category accepts everything and reads 'All'",
                StarFilters.Accepts(bogus, 1) && StarFilters.Accepts(bogus, 3) && StarFilters.Label(bogus) == "All", "");

            // The window's buttons: one per category, All first.
            string[] labels = StarFilters.Labels();
            StarFilter[] buttons = StarFilters.Buttons();
            Check("buttons: All, No star, 1 star, 2 stars, 2+ stars, left to right",
                string.Join(",", labels) == "All,No star,1 star,2 stars,2+ stars" && buttons.Length == labels.Length
                && buttons[0] == StarFilter.All && buttons[1] == StarFilter.NoStars && buttons[2] == StarFilter.OneStar
                && buttons[3] == StarFilter.TwoStars && buttons[4] == StarFilter.TwoOrMoreStars, string.Join(",", labels));
            buttons[0] = StarFilter.TwoStars;
            Check("buttons: Buttons() hands out a copy", StarFilters.Buttons()[0] == StarFilter.All, "");
        }

        private static readonly StarSet[] Singles = { StarSet.NoStars, StarSet.OneStar, StarSet.TwoStars, StarSet.TwoOrMoreStars };
        private static readonly StarFilter[] Categories = { StarFilter.NoStars, StarFilter.OneStar, StarFilter.TwoStars, StarFilter.TwoOrMoreStars };

        // Every one of the 16 sets: All (0) and every combination of the four categories.
        private static IEnumerable<StarSet> EverySet()
        {
            for (int bits = 0; bits < 16; bits++)
                yield return (StarSet)bits;
        }

        // The rule written out afresh: which categories take a level.
        private static bool Expected(StarSet set, int level)
        {
            if (set == StarSet.All) return true;
            return ((set & StarSet.NoStars) != 0 && level <= 1) || ((set & StarSet.OneStar) != 0 && level == 2)
                   || ((set & StarSet.TwoStars) != 0 && level == 3) || ((set & StarSet.TwoOrMoreStars) != 0 && level >= 3);
        }

        // Several categories at once: the union of the marked ones; All resets.
        private static void StarSetTests()
        {
            var wrong = new List<string>();
            foreach (StarSet set in EverySet())
            {
                for (int level = 1; level <= 5; level++)
                {
                    if (StarSets.Accepts(set, level) != Expected(set, level)) wrong.Add(StarSets.Format(set) + " @" + level);
                }
            }
            Check("sets: each of the 16 sets accepts exactly the levels 1-5 of its categories", wrong.Count == 0, string.Join("; ", wrong));
            Check("sets: level 0 counts as no star, level 10 as two or more",
                StarSets.Accepts(StarSet.NoStars, 0) && !StarSets.Accepts(StarSet.OneStar, 0)
                && StarSets.Accepts(StarSet.TwoOrMoreStars, 10) && !StarSets.Accepts(StarSet.TwoStars, 10), "");
            // The request's examples.
            StarSet noOrOne = StarSet.NoStars | StarSet.OneStar, oneOrTwo = StarSet.OneStar | StarSet.TwoStars;
            Check("sets: 'no star + 1 star' takes a plain and a one-star creature, not a two-star one",
                StarSets.Accepts(noOrOne, 1) && StarSets.Accepts(noOrOne, 2) && !StarSets.Accepts(noOrOne, 3), "");
            Check("sets: '1 star + 2 stars' takes one- and two-star creatures, not a plain one nor a modded three-star",
                !StarSets.Accepts(oneOrTwo, 1) && StarSets.Accepts(oneOrTwo, 2) && StarSets.Accepts(oneOrTwo, 3) && !StarSets.Accepts(oneOrTwo, 4), "");
            StarSet stray = (StarSet)32;
            Check("sets: bits outside the four categories and None are ignored - alone they behave, show and are written as All",
                StarSets.Accepts(stray, 1) && StarSets.Accepts(stray, 3) && StarSets.IsMarked(stray, StarFilter.All)
                && !StarSets.IsMarked(stray, StarFilter.OneStar) && StarSets.Format(stray) == "All" && StarSets.Label(stray) == "All"
                && StarSets.Format(stray | StarSet.OneStar) == "OneStar" && !StarSets.Accepts(stray | StarSet.OneStar, 1)
                && StarSets.Toggle(stray | StarSet.OneStar, StarFilter.OneStar) == StarSet.All, "");

            // IsMarked: the All button only while nothing else is, a category while it is in the set.
            bool marksRight = true;
            foreach (StarSet set in EverySet())
            {
                marksRight &= StarSets.IsMarked(set, StarFilter.All) == (set == StarSet.All);
                for (int c = 0; c < 4; c++)
                    marksRight &= StarSets.IsMarked(set, Categories[c]) == ((set & Singles[c]) != 0);
            }
            Check("marks: All is marked only for All; each category exactly while it is in the set", marksRight, "");
            Check("marks: with 'No star + 1 star', those two are marked and All is not",
                StarSets.IsMarked(noOrOne, StarFilter.NoStars) && StarSets.IsMarked(noOrOne, StarFilter.OneStar)
                && !StarSets.IsMarked(noOrOne, StarFilter.All) && !StarSets.IsMarked(noOrOne, StarFilter.TwoStars)
                && !StarSets.IsMarked(noOrOne, StarFilter.TwoOrMoreStars), "");

            // Toggle: All -> one -> two -> remove one -> remove the last = All.
            StarSet s0 = StarSet.All;
            StarSet s1 = StarSets.Toggle(s0, StarFilter.NoStars);
            StarSet s2 = StarSets.Toggle(s1, StarFilter.OneStar);
            StarSet s3 = StarSets.Toggle(s2, StarFilter.NoStars);
            StarSet s4 = StarSets.Toggle(s3, StarFilter.OneStar);
            Check("toggle: from All a category is marked alone; a second adds to it; clicking a marked one removes it; the last removed gives All",
                s1 == StarSet.NoStars && s2 == noOrOne && s3 == StarSet.OneStar && s4 == StarSet.All,
                StarSets.Format(s1) + " / " + StarSets.Format(s2) + " / " + StarSets.Format(s3) + " / " + StarSets.Format(s4));
            bool resets = true, fromAll = true;
            foreach (StarSet set in EverySet())
                resets &= StarSets.Toggle(set, StarFilter.All) == StarSet.All;
            for (int c = 0; c < 4; c++)
                fromAll &= StarSets.Toggle(StarSet.All, Categories[c]) == Singles[c];
            Check("toggle: All resets from every set", resets, "");
            Check("toggle: from All, each category gives that category alone", fromAll, "");
            Check("toggle: '2 stars' and '2+ stars' can both be marked",
                StarSets.Toggle(StarSet.TwoStars, StarFilter.TwoOrMoreStars) == (StarSet.TwoStars | StarSet.TwoOrMoreStars), "");
            StarSet everything = StarSet.NoStars | StarSet.OneStar | StarSet.TwoStars | StarSet.TwoOrMoreStars;
            Check("toggle: all four categories marked stay four marks (not All) until one is clicked off",
                StarSets.Toggle(StarSet.NoStars | StarSet.OneStar | StarSet.TwoStars, StarFilter.TwoOrMoreStars) == everything
                && !StarSets.IsMarked(everything, StarFilter.All) && StarSets.Toggle(everything, StarFilter.OneStar) == (everything & ~StarSet.OneStar), "");

            // Parse: what the cfg may hold.
            string names = TryParse("All", StarSet.All) + TryParse("NoStars", StarSet.NoStars) + TryParse("OneStar", StarSet.OneStar)
                           + TryParse("TwoStars", StarSet.TwoStars) + TryParse("TwoOrMoreStars", StarSet.TwoOrMoreStars);
            Check("parse: the five values a 0.3.x cfg holds read as before", names == "", names);
            string anyCase = TryParse("twostars", StarSet.TwoStars) + TryParse("ONESTAR", StarSet.OneStar) + TryParse("all", StarSet.All)
                             + TryParse("  TwoOrMoreStars  ", StarSet.TwoOrMoreStars);
            Check("parse: names in any case, with spaces around", anyCase == "", anyCase);
            string labelText = TryParse("No star", StarSet.NoStars) + TryParse("1 star", StarSet.OneStar) + TryParse("2 stars", StarSet.TwoStars)
                               + TryParse("2+ stars", StarSet.TwoOrMoreStars) + TryParse("2+ STARS", StarSet.TwoOrMoreStars);
            Check("parse: the window's labels", labelText == "", labelText);
            string numbers = TryParse("0", StarSet.NoStars) + TryParse("1", StarSet.OneStar) + TryParse("2", StarSet.TwoStars)
                             + TryParse("3", StarSet.TwoOrMoreStars) + TryParse("4", StarSet.All) + TryParse(" 2 ", StarSet.TwoStars);
            Check("parse: a number counts stars as before - 0 none, 1 one, 2 two, 3 two or more, 4 All", numbers == "", numbers);
            string lists = TryParse("NoStars, OneStar", noOrOne) + TryParse("OneStar;TwoStars", oneOrTwo) + TryParse("no star,1", noOrOne)
                           + TryParse("1 star , 2 stars", oneOrTwo) + TryParse("OneStar, onestar, 1", StarSet.OneStar)
                           + TryParse("NoStars,,OneStar", noOrOne) + TryParse("TwoOrMoreStars, TwoStars, OneStar, NoStars", everything);
            Check("parse: a list separated by commas or semicolons combines its categories; repeats and empty pieces do nothing", lists == "", lists);
            string allInside = TryParse("OneStar, All", StarSet.All) + TryParse("4, NoStars", StarSet.All) + TryParse("2 stars; all", StarSet.All);
            Check("parse: any All in a list makes it All", allInside == "", allInside);

            string problem;
            StarSet junk = StarSets.Parse("Foo", out problem);
            Check("parse: junk alone is All, with a problem that names it", junk == StarSet.All && problem != null && problem.Contains("'Foo'"), problem ?? "no problem");
            StarSet partly = StarSets.Parse("OneStar, Foo, 7", out problem);
            Check("parse: junk inside a list is ignored and named; the rest applies",
                partly == StarSet.OneStar && problem != null && problem.Contains("'Foo'") && problem.Contains("'7'"), problem ?? "no problem");
            bool outOfRange = StarSets.Parse("5", out problem) == StarSet.All && problem != null
                              && StarSets.Parse("-1", out problem) == StarSet.All && problem != null;
            Check("parse: a number outside 0-4 is not a category: alone it is All, with a problem", outOfRange, "");
            bool blanks = true;
            foreach (string blank in new[] { "", "   ", " , ; ", null })
                blanks &= StarSets.Parse(blank, out problem) == StarSet.All && problem != null;
            Check("parse: empty, blank or only separators is All, with a problem", blanks, "");
            Check("parse: a clean value reports no problem", StarSets.Parse("NoStars, OneStar", out problem) == noOrOne && problem == null, problem ?? "");

            // Format: canonical, and read back exactly.
            string trips = "";
            foreach (StarSet set in EverySet())
            {
                StarSet back = StarSets.Parse(StarSets.Format(set), out problem);
                if (back != set || problem != null) trips += StarSets.Format(set) + " -> " + back + "; ";
            }
            Check("format: every one of the 16 sets reads back as itself, with no problem", trips == "", trips);
            Check("format: 'All', or the names in a fixed order joined by ', '",
                StarSets.Format(StarSet.All) == "All" && StarSets.Format(StarSet.OneStar | StarSet.NoStars) == "NoStars, OneStar"
                && StarSets.Format(everything) == "NoStars, OneStar, TwoStars, TwoOrMoreStars", StarSets.Format(everything));

            // Label: the window title's words.
            Check("label: 'All', or the labels joined by ' + ' in the buttons' order",
                StarSets.Label(StarSet.All) == "All" && StarSets.Label(noOrOne) == "No star + 1 star"
                && StarSets.Label(StarSet.TwoStars | StarSet.NoStars) == "No star + 2 stars" && StarSets.Label(StarSet.TwoOrMoreStars) == "2+ stars",
                StarSets.Label(noOrOne));
        }

        // "" when the text parses to the set with no problem; else what went wrong.
        private static string TryParse(string text, StarSet want)
        {
            string problem;
            StarSet got = StarSets.Parse(text, out problem);
            return got == want && problem == null ? "" : "'" + text + "' -> " + StarSets.Format(got) + (problem != null ? " (" + problem + ")" : "") + "; ";
        }

        // None: the Alerts: row's empty selection under AlertsChange.EmptyAlertsNothing, which is built but not the mode
        // MobTracker runs with. Under the shipped mode nothing produces it, and the cfg cannot name it.
        private static void NoneTests()
        {
            bool nothing = true;
            for (int level = -1; level <= 10; level++)
                nothing &= !StarSets.Accepts(StarSet.None, level);
            Check("none: None lets no level through", nothing, "");
            bool unmarked = true;
            foreach (StarFilter button in StarFilters.Buttons())
                unmarked &= !StarSets.IsMarked(StarSet.None, button);
            Check("none: None marks no button, not even All", unmarked, "");
            StarSet noneAndOne = StarSet.None | StarSet.OneStar;
            Check("none: beside a marked category None counts for nothing - the category decides",
                StarSets.Accepts(noneAndOne, 2) && !StarSets.Accepts(noneAndOne, 1) && StarSets.IsMarked(noneAndOne, StarFilter.OneStar)
                && !StarSets.IsMarked(noneAndOne, StarFilter.All) && StarSets.Format(noneAndOne) == "OneStar", StarSets.Format(noneAndOne));

            // The Alerts: row's clicks under EmptyAlertsNothing: 2 stars -> off -> None -> 1 star -> 1 star alone.
            StarSet off = StarSets.Toggle(StarSet.TwoStars, StarFilter.TwoStars, true);
            StarSet on = StarSets.Toggle(off, StarFilter.OneStar, true);
            Check("none: with emptyIsNothing, taking off the last category gives None; a category clicked then is marked alone",
                off == StarSet.None && on == StarSet.OneStar, StarSets.Format(off) + " / " + StarSets.Format(on));
            Check("none: a click on All resets None, and resets any set with emptyIsNothing too",
                StarSets.Toggle(StarSet.None, StarFilter.All, true) == StarSet.All && StarSets.Toggle(StarSet.None, StarFilter.All) == StarSet.All
                && StarSets.Toggle(StarSet.OneStar | StarSet.TwoStars, StarFilter.All, true) == StarSet.All, "");
            bool fromNone = true;
            for (int c = 0; c < 4; c++)
                fromNone &= StarSets.Toggle(StarSet.None, Categories[c], true) == Singles[c] && StarSets.Toggle(StarSet.None, Categories[c]) == Singles[c];
            Check("none: from None, each category gives that category alone", fromNone, "");
            bool onlyTheLast = true;
            foreach (StarSet set in EverySet())
            {
                foreach (StarFilter button in StarFilters.Buttons())
                {
                    StarSet plain = StarSets.Toggle(set, button), withNone = StarSets.Toggle(set, button, true);
                    onlyTheLast &= plain == StarSet.All && button != StarFilter.All ? withNone == StarSet.None : withNone == plain;
                }
            }
            Check("none: emptyIsNothing changes only the click that takes off the last category (None, not All)", onlyTheLast, "");
            Check("none: without emptyIsNothing - the List: row, and the Alerts: row as shipped - the last one off still gives All",
                StarSets.Toggle(StarSet.TwoStars, StarFilter.TwoStars) == StarSet.All && StarSets.Toggle(StarSet.TwoStars, StarFilter.TwoStars, false) == StarSet.All, "");

            // Its text.
            string problem;
            Check("none: Format and Label write None", StarSets.Format(StarSet.None) == "None" && StarSets.Label(StarSet.None) == "None", StarSets.Format(StarSet.None));
            bool reads = StarSets.Parse("None", out problem, true) == StarSet.None && problem == null
                         && StarSets.Parse(" nONE ", out problem, true) == StarSet.None && problem == null
                         && StarSets.Parse(StarSets.Format(StarSet.None), out problem, true) == StarSet.None && problem == null;
            Check("none: allowed, 'None' in any case reads as None, cleanly, and Format(None) reads back", reads, problem ?? "");
            bool beside = StarSets.Parse("None, OneStar", out problem, true) == StarSet.OneStar && problem == null
                          && StarSets.Parse("All; none", out problem, true) == StarSet.All && problem == null;
            Check("none: allowed, None beside a category gives the category, beside All gives All", beside, problem ?? "");
            StarSet refused = StarSets.Parse("None", out problem);
            Check("none: not allowed (the shipped mode), 'None' alone is an unknown token: All, with a problem naming it",
                refused == StarSet.All && problem != null && problem.Contains("'None'"), problem ?? "no problem");
            refused = StarSets.Parse("None", out problem, false);
            Check("none: ... the same with allowNone false", refused == StarSet.All && problem != null && problem.Contains("'None'"), problem ?? "no problem");
            Check("none: not allowed, None beside a category is ignored, and named",
                StarSets.Parse("OneStar, None", out problem) == StarSet.OneStar && problem != null && problem.Contains("'None'"), problem ?? "no problem");
            string shipped, built;
            StarSets.Parse("Foo", out shipped);
            StarSets.Parse("Foo", out built, true);
            Check("none: the problem text offers None only where it may be written",
                shipped != null && !shipped.Contains("None") && built != null && built.Contains("Write All, None, or one or more"), shipped + " | " + built);
            bool unchanged = true;
            foreach (string text in new[] { "All", "OneStar, TwoStars", "2 stars; 2+ stars", "3", "Foo", "", "OneStar, Foo" })
            {
                string p1, p2;
                unchanged &= StarSets.Parse(text, out p1, true) == StarSets.Parse(text, out p2) && (p1 == null) == (p2 == null);
            }
            Check("none: allowing None changes nothing for text without it", unchanged, "");
        }

        // The Alerts: row's settling: the set the alerts use follows the filter once its cfg text has held still for
        // 1.5 s. The second value of Settled is the text's revision, which changes at every write of it.
        private static void SettleTests()
        {
            Check("settle: the wait is 1.5 seconds", StarSetSettler.SettleSeconds == 1.5f, StarSetSettler.SettleSeconds.ToString());
            var s = new StarSetSettler();
            Check("settle: the first set is taken at once - nothing waits at the start", s.Settled(StarSet.TwoStars, 0, 0f) == StarSet.TwoStars, "");
            Check("settle: ... whenever the first one comes", new StarSetSettler().Settled(StarSet.OneStar, 7, 5000f) == StarSet.OneStar, "");
            Check("settle: a change is not taken before it has held for 1.5 s",
                s.Settled(StarSet.OneStar, 1, 10f) == StarSet.TwoStars && s.Settled(StarSet.OneStar, 1, 11.49f) == StarSet.TwoStars, "");
            Check("settle: ... and is taken once it has (at exactly 1.5 s)", s.Settled(StarSet.OneStar, 1, 11.5f) == StarSet.OneStar, "");
            Check("settle: ... and then kept", s.Settled(StarSet.OneStar, 1, 100f) == StarSet.OneStar && s.Settled(StarSet.OneStar, 1, 100.1f) == StarSet.OneStar, "");

            // '2 stars' off at 10.0 (the row shows All), '1 star' on at 10.8: timed from the last click.
            var r = new StarSetSettler();
            r.Settled(StarSet.TwoStars, 0, 0f);
            bool allHeld = r.Settled(StarSet.All, 1, 10f) == StarSet.TwoStars && r.Settled(StarSet.All, 1, 10.7f) == StarSet.TwoStars;
            bool oneHeld = r.Settled(StarSet.OneStar, 2, 10.8f) == StarSet.TwoStars && r.Settled(StarSet.OneStar, 2, 11.6f) == StarSet.TwoStars
                           && r.Settled(StarSet.OneStar, 2, 12.29f) == StarSet.TwoStars;
            bool oneTaken = r.Settled(StarSet.OneStar, 2, 12.3f) == StarSet.OneStar;
            Check("settle: '2 stars' off at 10.0, '1 star' on at 10.8 - All is never taken, '1 star' from 12.3 (1.5 s after the last click)",
                allHeld && oneHeld && oneTaken, allHeld + "/" + oneHeld + "/" + oneTaken);

            // A pause of 1.5 s or more between two clicks: what the row shows in between is taken (README, Known limits).
            var p = new StarSetSettler();
            p.Settled(StarSet.TwoStars, 0, 0f);
            p.Settled(StarSet.All, 1, 10f);
            bool allTaken = p.Settled(StarSet.All, 1, 11.5f) == StarSet.All;
            p.Settled(StarSet.OneStar, 2, 12f);
            bool oneLater = p.Settled(StarSet.OneStar, 2, 13.49f) == StarSet.All && p.Settled(StarSet.OneStar, 2, 13.5f) == StarSet.OneStar;
            Check("settle: a pause of 1.5 s between two clicks takes the set in between (Known limits)", allTaken && oneLater, allTaken + "/" + oneLater);

            // Back to the set in use before 1.5 s: the change is off; made again, it is timed afresh.
            var c = new StarSetSettler();
            c.Settled(StarSet.TwoStars, 0, 0f);
            c.Settled(StarSet.All, 1, 10f);
            bool cancelled = c.Settled(StarSet.TwoStars, 2, 11f) == StarSet.TwoStars && c.Settled(StarSet.TwoStars, 2, 12f) == StarSet.TwoStars;
            c.Settled(StarSet.All, 3, 12.5f);
            bool afresh = c.Settled(StarSet.All, 3, 13.9f) == StarSet.TwoStars && c.Settled(StarSet.All, 3, 14f) == StarSet.All;
            Check("settle: a return to the set in use calls the change off; made again, it waits 1.5 s from then", cancelled && afresh, cancelled + "/" + afresh);

            // A change to a third set restarts the wait.
            var t = new StarSetSettler();
            t.Settled(StarSet.All, 0, 0f);
            t.Settled(StarSet.OneStar, 1, 10f);
            bool restarted = t.Settled(StarSet.TwoStars, 2, 11f) == StarSet.All && t.Settled(StarSet.TwoStars, 2, 12.4f) == StarSet.All
                             && t.Settled(StarSet.TwoStars, 2, 12.5f) == StarSet.TwoStars;
            Check("settle: every change restarts the wait", restarted, "");

            // A write that leaves the set as it was restarts the wait too: ConfigurationManager writes the setting at every
            // keystroke, and a word typed so far ('T', 'Tw' ... of 'TwoStars') reads as All. The same write seen again on
            // the next frames does not restart it.
            var w = new StarSetSettler();
            w.Settled(StarSet.OneStar, 0, 0f);
            w.Settled(StarSet.All, 1, 10f);
            bool keptThrough = w.Settled(StarSet.All, 2, 11f) == StarSet.OneStar && w.Settled(StarSet.All, 2, 12.49f) == StarSet.OneStar;
            bool takenAfter = w.Settled(StarSet.All, 2, 12.5f) == StarSet.All;
            Check("settle: a write that leaves the set as it was restarts the wait too (a keystroke); the same write seen again does not",
                keptThrough && takenAfter, keptThrough + "/" + takenAfter);

            // The set is compared as well as the revision: fed one revision throughout, a change of the set alone still
            // restarts the wait, and a return to the set in use still calls a change off (so that change, made again,
            // waits from then, not from the first time).
            var o = new StarSetSettler();
            o.Settled(StarSet.TwoStars, 0, 0f);
            bool firstWaits = o.Settled(StarSet.All, 0, 10f) == StarSet.TwoStars;
            bool calledOff = o.Settled(StarSet.TwoStars, 0, 11f) == StarSet.TwoStars;
            bool againWaits = o.Settled(StarSet.All, 0, 12.5f) == StarSet.TwoStars && o.Settled(StarSet.All, 0, 13.9f) == StarSet.TwoStars;
            bool setRestarts = o.Settled(StarSet.OneStar, 0, 13.95f) == StarSet.TwoStars && o.Settled(StarSet.OneStar, 0, 15.4f) == StarSet.TwoStars
                               && o.Settled(StarSet.OneStar, 0, 15.5f) == StarSet.OneStar;
            Check("settle: fed one revision throughout, a change of the set alone restarts the wait, and a return to the set in use calls it off",
                firstWaits && calledOff && againWaits && setRestarts, firstWaits + "/" + calledOff + "/" + againWaits + "/" + setRestarts);

            // A new game session starts the settler over (WatchAlerts.ResetSession): the next set is taken at once, as
            // at the start - All, after ModConfig.ResetSession, or a row kept with KeepBetweenSessions - even in the
            // middle of a wait; after it, a change waits as before.
            var n = new StarSetSettler();
            n.Settled(StarSet.TwoStars, 0, 0f);
            bool midWait = n.Settled(StarSet.All, 1, 10f) == StarSet.TwoStars;
            n.Reset();
            bool allAtOnce = n.Settled(StarSet.All, 2, 10.1f) == StarSet.All;
            bool thenWaits = n.Settled(StarSet.OneStar, 3, 11f) == StarSet.All && n.Settled(StarSet.OneStar, 3, 12.49f) == StarSet.All
                             && n.Settled(StarSet.OneStar, 3, 12.5f) == StarSet.OneStar;
            n.Reset();
            bool keptAtOnce = n.Settled(StarSet.OneStar | StarSet.TwoStars, 3, 13f) == (StarSet.OneStar | StarSet.TwoStars);
            Check("settle: Reset (a new game session) takes the next set at once - All or a kept one - and a change after it waits 1.5 s",
                midWait && allAtOnce && thenWaits && keptAtOnce, midWait + "/" + allAtOnce + "/" + thenWaits + "/" + keptAtOnce);
        }

        // The mode and what it switches (AlertsRow): the shipped Settle, and EmptyAlertsNothing, built but not shipped.
        private static void AlertsRowTests()
        {
            Check("mode: MobTracker runs with Settle", AlertsRow.AlertsChangeMode == AlertsChange.Settle, AlertsRow.AlertsChangeMode.ToString());
            Check("mode: only EmptyAlertsNothing empties the Alerts: row to None",
                AlertsRow.EmptyIsNothing(AlertsChange.EmptyAlertsNothing) && !AlertsRow.EmptyIsNothing(AlertsChange.Settle), "");
            var settler = new StarSetSettler();
            bool first = AlertsRow.Effective(StarSet.TwoStars, 0, settler, 0f, AlertsChange.Settle) == StarSet.TwoStars;
            bool waits = AlertsRow.Effective(StarSet.All, 1, settler, 10f, AlertsChange.Settle) == StarSet.TwoStars;
            bool follows = AlertsRow.Effective(StarSet.All, 1, settler, 11.5f, AlertsChange.Settle) == StarSet.All;
            Check("mode: under Settle the alerts use the settled set", first && waits && follows, first + "/" + waits + "/" + follows);
            var typed = new StarSetSettler();
            AlertsRow.Effective(StarSet.OneStar, 0, typed, 0f, AlertsChange.Settle);
            AlertsRow.Effective(StarSet.All, 1, typed, 10f, AlertsChange.Settle);
            bool revisionPassed = AlertsRow.Effective(StarSet.All, 2, typed, 11f, AlertsChange.Settle) == StarSet.OneStar
                                  && AlertsRow.Effective(StarSet.All, 2, typed, 12.49f, AlertsChange.Settle) == StarSet.OneStar
                                  && AlertsRow.Effective(StarSet.All, 2, typed, 12.5f, AlertsChange.Settle) == StarSet.All;
            Check("mode: under Settle the text's revision reaches the settler - a keystroke restarts the wait", revisionPassed, "");
            var bypassed = new StarSetSettler();
            bool at0 = AlertsRow.Effective(StarSet.TwoStars, 0, bypassed, 0f, AlertsChange.EmptyAlertsNothing) == StarSet.TwoStars;
            bool atOnce = AlertsRow.Effective(StarSet.None, 1, bypassed, 10f, AlertsChange.EmptyAlertsNothing) == StarSet.None
                          && AlertsRow.Effective(StarSet.OneStar, 2, bypassed, 10.1f, AlertsChange.EmptyAlertsNothing) == StarSet.OneStar;
            Check("mode: under EmptyAlertsNothing the alerts use the row's set at once", at0 && atOnce, at0 + "/" + atOnce);
        }

        // What the search box and the watchlist already did before the star filter.
        private static void RulesTests()
        {
            Check("search: 'Deer' finds a plain Deer and a one-star Deer", Rules.Matches("Deer", "Deer", "Deer") && Rules.Matches("Deer", "Deer *", "Deer"), "");
            Check("search: '*' finds starred creatures only", Rules.Matches("*", "Deer *", "Deer") && !Rules.Matches("*", "Deer", "Deer"), "");
            Check("search: case-insensitive, on the prefab name too", Rules.Matches("greydwarf_e", "Greydwarf Brute", "Greydwarf_Elite"), "");
            Check("search: blank matches everything", Rules.Matches("   ", "Deer", "Deer") && Rules.Matches(null, "Deer", "Deer"), "");

            HashSet<string> w = Rules.ParseWatchlist(" Troll, deer ,,Serpent");
            Check("watchlist: parse trims, drops blanks, ignores case", w.Count == 3 && w.Contains("DEER") && w.Contains("troll"), string.Join("|", w));
            Check("watchlist: format sorts without spaces", Rules.FormatWatchlist(w) == "deer,Serpent,Troll", Rules.FormatWatchlist(w));
        }

        // Find area keeps its pins at least this far apart.
        private static void SpacingTests()
        {
            var taken = new List<float[]> { new[] { 0f, 0f } };
            Check("spacing: a point 400 m away is spaced at 400", Rules.IsSpaced(400f, 0f, taken, 400f, p => p[0], p => p[1]), "");
            Check("spacing: a point 399 m away is not", !Rules.IsSpaced(0f, 399f, taken, 400f, p => p[0], p => p[1]), "");
            Check("spacing: nothing taken yet is always spaced", Rules.IsSpaced(1f, 1f, new List<float[]>(), 400f, p => p[0], p => p[1]), "");
        }

        // A world-spawn rule as Find area sees it: biome, required global key, required persistent event.
        private sealed class SpawnRule
        {
            public string Biome, Key, Event;
            public SpawnRule(string biome, string key, string worldEvent) { Biome = biome; Key = key; Event = worldEvent; }
        }

        private static List<SpawnRule> Open(IEnumerable<SpawnRule> rules, Func<string, bool> worldHasKey, List<string> keys, List<string> events)
        {
            return Rules.OpenRules(rules, r => r.Key, r => r.Event, worldHasKey, keys, events);
        }

        // Which rules Find area searches with: SpawnSystem.UpdateSpawnList's key and event conditions.
        private static void OpenRuleTests()
        {
            // Charred_Archer: a key-gated rule for the other biomes and a plain Ashlands one.
            var archer = new List<SpawnRule> { new SpawnRule("Meadows|BlackForest|...", "defeated_fader", ""), new SpawnRule("AshLands", "", "") };
            var keys = new List<string>(); var events = new List<string>();
            List<SpawnRule> open = Open(archer, k => false, keys, events);
            Check("rules: with the boss key unset, only the unkeyed Ashlands rule is searched",
                open.Count == 1 && open[0].Biome == "AshLands" && keys.Count == 1 && keys[0] == "defeated_fader" && events.Count == 0,
                open.Count + " open, keys " + string.Join(",", keys));
            keys.Clear();
            open = Open(archer, k => k == "defeated_fader", keys, events);
            Check("rules: once the world has the key, both rules are searched", open.Count == 2 && keys.Count == 0, open.Count + " open");

            // The key is looked up only when a rule has one; null and "" both mean no condition.
            var asked = new List<string>();
            open = Open(new[] { new SpawnRule("Swamp", null, null), new SpawnRule("Swamp", "", "") }, k => { asked.Add(k); return false; }, keys, events);
            Check("rules: a rule with no key or event is always open, and no key is looked up for it", open.Count == 2 && asked.Count == 0, asked.Count + " lookups");

            // An event rule is left out even while its key is met; a rule gated both ways reports the key it waits for.
            keys.Clear(); events.Clear();
            var jotun = new List<SpawnRule> { new SpawnRule("DeepNorth", "jotun_killed", ""), new SpawnRule("All", "", "jotun_invasion"), new SpawnRule("All", "jotun_killed", "jotun_invasion") };
            open = Open(jotun, k => false, keys, events);
            Check("rules: event rules are never searched; each key and event is reported once",
                open.Count == 0 && string.Join(",", keys) == "jotun_killed" && string.Join(",", events) == "jotun_invasion",
                "keys " + string.Join(",", keys) + ", events " + string.Join(",", events));
            Check("rules: the message names what the closed rules wait for",
                Rules.NoOpenRule("Jotun Warrior", keys, events) == "Jotun Warrior spawns in the wild only once this world has jotun_killed, or during the jotun_invasion event",
                Rules.NoOpenRule("Jotun Warrior", keys, events));
            Check("rules: with no rule at all, the message says where else it may come from",
                Rules.NoOpenRule("Boar", new List<string>(), new List<string>()).StartsWith("Boar has no rule in the main spawn lists")
                && Rules.NoOpenRule("Boar", new List<string>(), new List<string>()).Contains("breeding"), "");
            keys.Clear(); events.Clear();
            open = Open(new[] { new SpawnRule("All", "", "jotun_invasion"), new SpawnRule("DeepNorth", "jotun_killed", "") }, k => true, keys, events);
            Check("rules: an event rule does not hide an open keyed rule of the same creature",
                open.Count == 1 && open[0].Biome == "DeepNorth" && events.Count == 1 && keys.Count == 0, open.Count + " open");
        }

        private static void AlertGateTests()
        {
            var gate = new AlertGate<int>();
            Check("gate: an unwatched creature never alerts", !gate.ShouldAlert(1, false, false, 10f, 0f), "");
            Check("gate: a tamed creature never alerts", !gate.ShouldAlert(2, true, true, 10f, 0f), "");
            Check("radius: 0 or less means anywhere", Rules.WithinRadius(5000f, 0f) && Rules.WithinRadius(5000f, -1f), "");
            Check("radius: exactly on the radius is inside, a little past it is not",
                Rules.WithinRadius(20f, 20f) && !Rules.WithinRadius(20.01f, 20f), "");
            Check("radius: NaN typed by hand means anywhere, as in 0.2.0", Rules.WithinRadius(5000f, float.NaN), "");
            Check("radius: infinity means anywhere, minus infinity too",
                Rules.WithinRadius(5000f, float.PositiveInfinity) && Rules.WithinRadius(5000f, float.NegativeInfinity), "");
            Check("gate: outside the radius it does not alert", !gate.ShouldAlert(3, true, false, 50f, 20f), "");
            Check("gate: ...and alerts once it comes inside", gate.ShouldAlert(3, true, false, 15f, 20f), "");
            Check("gate: a creature alerts only once", gate.ShouldAlert(4, true, false, 10f, 0f) && !gate.ShouldAlert(4, true, false, 10f, 0f), "");
            Check("gate: a creature first seen unwatched can alert later", gate.ShouldAlert(1, true, false, 10f, 0f), "");
            gate.Clear();
            Check("gate: Clear lets every creature alert again", gate.ShouldAlert(4, true, false, 10f, 0f), "");
        }

        // The same expression WatchAlerts.Update uses (preflight checks that it reads the alert filter, not the
        // list's): watched = the alert star filter accepts the level AND the type is on the watchlist.
        private static bool Decide(AlertGate<int> gate, int id, int level, StarSet filter, bool onWatchlist)
        {
            bool watched = StarSets.Accepts(filter, level) && onWatchlist;
            return gate.ShouldAlert(id, watched, false, 10f, 0f);
        }

        private static void AlertStarFilterTests()
        {
            var gate = new AlertGate<int>();
            Check("alert stars: with '2 stars', a two-star Troll alerts", Decide(gate, 10, 3, StarSet.TwoStars, true), "");
            Check("alert stars: with '2 stars', a plain Troll does not", !Decide(gate, 11, 1, StarSet.TwoStars, true), "");
            Check("alert stars: with '2 stars', a one-star Troll does not", !Decide(gate, 12, 2, StarSet.TwoStars, true), "");
            Check("alert stars: a creature left out alerts once the filter lets it through",
                Decide(gate, 11, 1, StarSet.All, true) && !Decide(gate, 11, 1, StarSet.All, true), "");
            Check("alert stars: a type not on the watchlist never alerts, whatever its stars", !Decide(gate, 13, 3, StarSet.TwoStars, false), "");
            var both = new AlertGate<int>();
            StarSet noOrOne = StarSet.NoStars | StarSet.OneStar;
            Check("alert stars: with 'No star + 1 star', a plain and a one-star Troll alert, a two-star one does not",
                Decide(both, 14, 1, noOrOne, true) && Decide(both, 15, 2, noOrOne, true) && !Decide(both, 16, 3, noOrOne, true), "");

            // Why toggles, and not a button that cycles through the choices: every state a click passes through is
            // live for the once-a-second poll, which alerts each creature once. Watching Troll with '2 stars' marked,
            // the player wants '1 star'. Clicking '1 star' first passes only through '1 star + 2 stars' - nothing
            // outside what was and what will be - so the plain Troll never alerts and the one-star Troll alerts once.
            StarSet start = StarSet.TwoStars;
            StarSet added = StarSets.Toggle(start, StarFilter.OneStar);
            StarSet goal = StarSets.Toggle(added, StarFilter.TwoStars);
            var fresh = new AlertGate<int>();
            bool plainBefore = Decide(fresh, 21, 1, start, true);
            bool plainBetween = Decide(fresh, 21, 1, added, true);
            bool plainAfter = Decide(fresh, 21, 1, goal, true);
            bool oneStarAfter = Decide(fresh, 22, 2, goal, true);
            Check("alert stars: '1 star' clicked before '2 stars' is clicked off - the plain Troll never alerts, the one-star one does",
                goal == StarSet.OneStar && !plainBefore && !plainBetween && !plainAfter && oneStarAfter,
                plainBefore + "/" + plainBetween + "/" + plainAfter + "/" + oneStarAfter);

            // The other order: clicking the only marked category off first gives All on the row, where the plain Troll
            // would alert and use up its one alert. So the alerts do not use the row's set as it is (AlertsRow).
            StarSet removed = StarSets.Toggle(start, StarFilter.TwoStars);
            var other = new AlertGate<int>();
            bool plainInAll = Decide(other, 31, 1, removed, true);
            Check("alert stars: '2 stars' clicked off first leaves the row at All, where the plain Troll would alert",
                removed == StarSet.All && plainInAll && StarSets.Toggle(removed, StarFilter.OneStar) == StarSet.OneStar, "");

            // Frame by frame, as WatchAlerts does it: the settled set worked out every frame, the poll once a second.
            // Shipped (Settle): '2 stars' off at 10.2 and '1 star' on at 10.9 - All never reaches the poll, so the plain
            // Troll never alerts, and the one-star Troll alerts at the first poll after 12.4.
            float[] a = Simulate(AlertsChange.Settle, new[] { 0f, 10.2f, 10.9f }, new[] { StarSet.TwoStars, StarSet.All, StarSet.OneStar });
            Check("alert stars: shipped, two quick clicks through All - the plain Troll never alerts, the one-star one once '1 star' has held",
                a[0] < 0f && a[1] >= 12.4f && a[1] < 13.5f, a[0] + " / " + a[1]);
            // A pause of 1.5 s or more between the clicks: All is taken, and the plain Troll alerts (README, Known limits).
            a = Simulate(AlertsChange.Settle, new[] { 0f, 10.2f, 12.2f }, new[] { StarSet.TwoStars, StarSet.All, StarSet.OneStar });
            Check("alert stars: shipped, a 2 s pause at All between the clicks - All is taken and the plain Troll alerts (Known limits)",
                a[0] >= 11.7f && a[0] < 12.8f, a[0] + " / " + a[1]);
            // A change that ends where it began (a category clicked off and on again) changes nothing.
            a = Simulate(AlertsChange.Settle, new[] { 0f, 10.2f, 11.0f }, new[] { StarSet.TwoStars, StarSet.All, StarSet.TwoStars });
            Check("alert stars: shipped, '2 stars' clicked off and on again within 1.5 s - nothing but two stars ever alerts",
                a[0] < 0f && a[1] < 0f, a[0] + " / " + a[1]);
            // EmptyAlertsNothing (built, not shipped): the row goes through None, which alerts on nothing, even slowly.
            StarSet emptied = StarSets.Toggle(start, StarFilter.TwoStars, true);
            a = Simulate(AlertsChange.EmptyAlertsNothing, new[] { 0f, 10.2f, 12.2f }, new[] { StarSet.TwoStars, emptied, StarSets.Toggle(emptied, StarFilter.OneStar, true) });
            Check("alert stars: EmptyAlertsNothing, a 2 s pause at None between the clicks - the plain Troll never alerts, the one-star one at once",
                emptied == StarSet.None && a[0] < 0f && a[1] >= 12.2f && a[1] < 13.3f, a[0] + " / " + a[1]);

            // Typed in ConfigurationManager: 'TwoStars' over a selected 'OneStar' at 4 keys a second. 'T' ... 'TwoStar'
            // each read as All, for 1.75 s together - longer than the wait - yet each keystroke restarts it: the plain
            // Troll never alerts, and two stars apply 1.5 s after the last key (11.75), at the first poll from 13.25.
            float[] at;
            StarSet[] sets;
            Typing(StarSet.OneStar, "TwoStars", 10f, 0.25f, -1, 0f, out at, out sets);
            bool halfTypedAll = sets[sets.Length - 1] == StarSet.TwoStars;
            for (int k = 1; k < sets.Length - 1; k++)
                halfTypedAll &= sets[k] == StarSet.All;
            a = Simulate(AlertsChange.Settle, at, sets);
            Check("alert stars: shipped, 'TwoStars' typed over 'OneStar' at 4 keys a second - the half-typed word (All) never alerts the plain Troll; two stars from 1.5 s after the last key",
                halfTypedAll && a[0] < 0f && a[2] >= 13.25f && a[2] < 14.3f, halfTypedAll + " " + a[0] + " / " + a[2]);
            // Slowly, a key every 1.4 s: still never, and two stars from 1.5 s after the last key (19.8).
            Typing(StarSet.OneStar, "TwoStars", 10f, 1.4f, -1, 0f, out at, out sets);
            a = Simulate(AlertsChange.Settle, at, sets);
            Check("alert stars: shipped, 'TwoStars' typed at a key every 1.4 s - the plain Troll never alerts; two stars from 1.5 s after the last key",
                a[0] < 0f && a[2] >= 21.3f && a[2] < 22.4f, a[0] + " / " + a[2]);
            // A pause of 1.5 s or more while typing: what is typed so far applies - All, for 'Tw' (README, Known limits).
            Typing(StarSet.OneStar, "TwoStars", 10f, 0.25f, 2, 2f, out at, out sets);
            a = Simulate(AlertsChange.Settle, at, sets);
            Check("alert stars: shipped, a 2 s pause after 'Tw' - All is taken and the plain Troll alerts (Known limits)",
                a[0] >= 11.7f && a[0] < 12.8f, a[0] + " / " + a[2]);
        }

        // ConfigurationManager (F1) writes a text setting at every keystroke that changes it. The Alerts: filter is
        // 'before' from 0 s; from 'start' 'word' is typed over it, one key every 'perKey' seconds, with 'pause' seconds
        // more before key number 'pauseBefore' (0 = the first; -1 = no pause). Each keystroke is one write: the text so
        // far, read as ModConfig reads it in the shipped mode.
        private static void Typing(StarSet before, string word, float start, float perKey, int pauseBefore, float pause,
            out float[] at, out StarSet[] sets)
        {
            at = new float[word.Length + 1];
            sets = new StarSet[word.Length + 1];
            sets[0] = before;
            float time = start;
            for (int k = 1; k <= word.Length; k++)
            {
                if (k - 1 == pauseBefore)
                    time += pause;
                string problem;
                at[k] = time;
                sets[k] = StarSets.Parse(word.Substring(0, k), out problem, AlertsRow.EmptyIsNothing(AlertsRow.AlertsChangeMode));
                time += perKey;
            }
        }

        // 60 frames a second from 0 to 40 s. The Alerts: filter's set is sets[k] from at[k] on (at[0] = 0), each one a
        // write of its text, so its revision is k; each frame the alerts' set is worked out as WatchAlerts.Update does,
        // and once a second the poll decides for a plain (level 1), a one-star (level 2) and a two-star (level 3) watched
        // Troll. The time of each one's alert, or -1.
        private static float[] Simulate(AlertsChange mode, float[] at, StarSet[] sets)
        {
            var settler = new StarSetSettler();
            var gate = new AlertGate<int>();
            float[] alertAt = { -1f, -1f, -1f };
            float nextPoll = 0f;
            for (int frame = 0; frame <= 40 * 60; frame++)
            {
                float now = frame / 60f;
                StarSet row = sets[0];
                int revision = 0;
                for (int k = 0; k < at.Length; k++)
                {
                    if (now >= at[k])
                    {
                        row = sets[k];
                        revision = k;
                    }
                }
                StarSet effective = AlertsRow.Effective(row, revision, settler, now, mode);
                if (now < nextPoll)
                    continue;
                nextPoll = now + 1f;
                for (int level = 1; level <= 3; level++)
                {
                    if (alertAt[level - 1] < 0f && Decide(gate, level, level, effective, true))
                        alertAt[level - 1] = now;
                }
            }
            return alertAt;
        }

        // "Always track nearest watched": the waiting and cancelling that NearestWatched does around the game's objects.
        private static void RetrackTests()
        {
            var r = new Retrack();
            r.Lost("Troll", false, true, false, 100f);
            Check("retrack: with the option off, a lost Troll schedules nothing", !r.IsPending && !r.ShouldLook(200f), "");
            r.Lost("Deer", true, false, false, 100f);
            Check("retrack: a lost creature whose type is not watched schedules nothing", !r.IsPending, "");
            r.Lost("", true, true, false, 100f);
            Check("retrack: no type (a spawn area was tracked) schedules nothing", !r.IsPending, "");
            r.Lost("Wolf", true, true, true, 100f);
            Check("retrack: losing a tamed Wolf starts no hunt for a wild one", !r.IsPending && !r.ShouldLook(200f), "");

            r.Lost("Troll", true, true, false, 100f);
            Check("retrack: a lost watched Troll is pending, for Trolls", r.IsPending && r.Prefab == "Troll", r.Prefab ?? "null");
            Check("retrack: a Troll's watch alert waits for it; a Serpent's, a lower-case troll's or no type's does not",
                r.IsPendingFor("Troll") && !r.IsPendingFor("Serpent") && !r.IsPendingFor("troll") && !r.IsPendingFor(null), "");
            Check("retrack: nothing is looked for during the first 5 seconds", !r.ShouldLook(100f) && !r.ShouldLook(104.99f), "");
            Check("retrack: at 5 seconds it is time to look", r.ShouldLook(105f), "");
            Check("retrack: then once a second, not every frame", !r.ShouldLook(105.5f) && !r.ShouldLook(105.99f) && r.ShouldLook(106f), "");
            Check("retrack: it keeps looking while nothing is found", r.ShouldLook(107f) && r.ShouldLook(108.2f) && r.IsPending, "");

            r.Lost("Troll", true, true, false, 200f);
            Check("retrack: another loss starts the 5 seconds again", !r.ShouldLook(204f) && r.ShouldLook(205f), "");
            r.Lost("Troll", false, true, false, 210f);
            Check("retrack: a loss with the option turned off clears what was pending", !r.IsPending && !r.ShouldLook(300f), "");

            r.Lost("Serpent", true, true, false, 300f);
            r.Cancel();
            Check("retrack: Cancel ends the wait (Stop tracking, tracking something else, leaving the world)",
                !r.IsPending && !r.ShouldLook(400f) && !r.IsPendingFor("Serpent"), "");

            // EndsWait(playerDead, tracking, enabled, watched): alive, nothing tracked, option on, type watched = wait on.
            Check("retrack: the wait goes on while nothing ends it", !Retrack.EndsWait(false, false, true, true), "");
            Check("retrack: the player dying ends the wait", Retrack.EndsWait(true, false, true, true), "");
            Check("retrack: anything being tracked ends the wait", Retrack.EndsWait(false, true, true, true), "");
            Check("retrack: turning the option off ends the wait", Retrack.EndsWait(false, false, false, true), "");
            Check("retrack: unwatching the type ends the wait", Retrack.EndsWait(false, false, true, false), "");

            // IsCandidate(sameType, networked, tamed, starsAccepted, withinRadius, sameLayer).
            Check("retrack: a wild creature of the type, on the network, accepted stars, in range, on the player's side is taken",
                Retrack.IsCandidate(true, true, false, true, true, true), "");
            Check("retrack: another type is not", !Retrack.IsCandidate(false, true, false, true, true, true), "");
            Check("retrack: one the game is removing this frame is not", !Retrack.IsCandidate(true, false, false, true, true, true), "");
            Check("retrack: a tamed one is not", !Retrack.IsCandidate(true, true, true, true, true, true), "");
            Check("retrack: one the Alerts star filter leaves out is not", !Retrack.IsCandidate(true, true, false, false, true, true), "");
            Check("retrack: one outside AlertRadius is not", !Retrack.IsCandidate(true, true, false, true, false, true), "");
            Check("retrack: one on the other side of a dungeon entrance is not", !Retrack.IsCandidate(true, true, false, true, true, false), "");

            // A Skeleton inside a Burial Chamber, some 5 km up, while the player is outside -
            // and the mirror image from inside.
            Check("layer: outside and outside, inside and inside are the same side",
                Rules.SameLayer(false, false) && Rules.SameLayer(true, true), "");
            Check("layer: a creature inside a dungeon while the player is outside is not, nor the other way round",
                !Rules.SameLayer(true, false) && !Rules.SameLayer(false, true), "");
            Check("retrack: with the player outside, the one inside the dungeon is never taken, the one outside is",
                !Retrack.IsCandidate(true, true, false, true, true, Rules.SameLayer(true, false))
                && Retrack.IsCandidate(true, true, false, true, true, Rules.SameLayer(false, false)), "");
            Check("retrack: with the player inside, the one outside is never taken, the one inside is",
                !Retrack.IsCandidate(true, true, false, true, true, Rules.SameLayer(false, true))
                && Retrack.IsCandidate(true, true, false, true, true, Rules.SameLayer(true, true)), "");
        }

        // The creature list's rows: ShouldRefresh(playerChanged, due, pointerOverWindow, mouseHeld). The case it is for:
        // the rows re-sorted by distance between aiming at a row's Track and releasing the button.
        private static void RefreshTests()
        {
            Check("list: a due refresh runs while the pointer is off the window and no button is held",
                Rules.ShouldRefresh(false, true, false, false), "");
            Check("list: a due refresh waits while the pointer is over the window", !Rules.ShouldRefresh(false, true, true, false), "");
            Check("list: a due refresh waits while a mouse button is held, even off the window (a drag)",
                !Rules.ShouldRefresh(false, true, false, true), "");
            Check("list: nothing is refreshed before it is due", !Rules.ShouldRefresh(false, false, false, false), "");
            Check("list: the player's own change (search, view, list stars, opening) refreshes at once, pointer or button",
                Rules.ShouldRefresh(true, false, true, true) && Rules.ShouldRefresh(true, false, false, false), "");

            // Frame by frame: due at 0.5 s, the pointer over the window from 0.3 s to 2.0 s, then off it.
            var refreshedAt = new List<float>();
            float next = 0.5f;
            for (int frame = 1; frame <= 150; frame++)
            {
                float now = frame / 60f;
                bool over = now >= 0.3f && now < 2.0f;
                if (Rules.ShouldRefresh(false, now >= next, over, false))
                {
                    refreshedAt.Add(now);
                    next = now + 0.5f;
                }
            }
            Check("list: rows held still while the pointer rests on them, refreshed in the first frame after it leaves",
                refreshedAt.Count >= 2 && Math.Abs(refreshedAt[0] - 2.0f) < 0.02f && Math.Abs(refreshedAt[1] - 2.5f) < 0.02f,
                string.Join(", ", refreshedAt.ConvertAll(t => t.ToString("0.000"))));
        }

        // The list's pointer test: a screen point (pixels, y up) against the window's rect in GUI units (y down), drawn
        // under GUI.matrix = Scale(GuiScale). The default window (60, 60, 480, 560) covers, at 1080p, x 60..540 and
        // 60..620 px from the top = 460..1020 px from the bottom; at 2160p (scale 2), x 120..1080.
        private static void PointerTests()
        {
            Func<float, int, float, float, bool> over = (scale, height, px, py) => Rules.PointerOverWindow(60f, 60f, 480f, 560f, scale, height, px, py);
            Check("pointer: on the window at 1080p", over(1f, 1080, 300f, 700f), "");
            Check("pointer: the top-left corner is on it, the right and bottom edges are not (Rect.Contains)",
                over(1f, 1080, 60f, 1020f) && !over(1f, 1080, 540f, 700f) && !over(1f, 1080, 300f, 460f), "");
            Check("pointer: left of it and above it is off", !over(1f, 1080, 59f, 700f) && !over(1f, 1080, 300f, 1021f), "");
            Check("pointer: y counts up from the bottom - 400 px up is 680 px down, below the window", !over(1f, 1080, 300f, 400f), "");
            Check("pointer: at 2160p the window is twice as large and starts at 120 px",
                over(2f, 2160, 1000f, 1160f) && over(2f, 2160, 1079f, 1160f) && !over(2f, 2160, 1081f, 1160f) && !over(2f, 2160, 100f, 1160f), "");
            Check("pointer: at 1440p (scale 4/3) a point TomTom's unscaled test would miss is on it", over(1440f / 1080f, 1440, 700f, 740f), "");
            Check("pointer: a window dragged partly off the left edge", Rules.PointerOverWindow(-100f, 60f, 480f, 560f, 1f, 1080, 10f, 700f), "");
            Check("pointer: a scale not above 0 counts as 1", over(0f, 1080, 300f, 700f) && over(float.NaN, 1080, 300f, 700f), "");
        }

        // ClosesOnBack(open, consoleVisible, consoleWasVisible, escape, back);
        // MayToggle(open, keyTypesText, searchFocused, gameTyping, pauseMenu, buildMenu, inventory, barber).
        private static void ListKeyTests()
        {
            Check("keys: Escape closes the open list", ListKeys.ClosesOnBack(true, false, false, true, false), "");
            Check("keys: the gamepad's B closes the open list", ListKeys.ClosesOnBack(true, false, false, false, true), "");
            Check("keys: nothing pressed closes nothing", !ListKeys.ClosesOnBack(true, false, false, false, false), "");
            Check("keys: Escape does nothing to a closed list", !ListKeys.ClosesOnBack(false, false, false, true, true), "");
            Check("keys: not while the console is open (Escape is closing it)", !ListKeys.ClosesOnBack(true, true, false, true, true), "");
            Check("keys: not while the console was open last frame (it closed itself first)", !ListKeys.ClosesOnBack(true, false, true, true, true), "");

            Check("keys: ListKey opens the list", ListKeys.MayToggle(false, false, false, false, false, false, false, false), "");
            Check("keys: ListKey closes the list, even while the search box has the keyboard", ListKeys.MayToggle(true, false, true, false, false, false, false, false), "");
            Check("keys: ListKey does not open the list while the player types in a game text field", !ListKeys.MayToggle(false, false, false, true, false, false, false, false), "");
            Check("keys: ... whatever the key", !ListKeys.MayToggle(false, true, false, true, false, false, false, false), "");
            Check("keys: ListKey does not open the list over the pause menu", !ListKeys.MayToggle(false, false, false, false, true, false, false, false), "");
            Check("keys: ListKey does not open the list over the build menu (its right click would reach it)", !ListKeys.MayToggle(false, false, false, false, false, true, false, false), "");
            Check("keys: ListKey does not open the list over the inventory", !ListKeys.MayToggle(false, false, false, false, false, false, true, false), "");
            Check("keys: ListKey does not open the list over the Barber Station (the Escape that closes the list would cancel it)", !ListKeys.MayToggle(false, false, false, false, false, false, false, true), "");
            Check("keys: a ListKey that types does not close the list while its search box has the keyboard", !ListKeys.MayToggle(true, true, true, false, false, false, false, false), "");
            Check("keys: ... nor while a game text field has it", !ListKeys.MayToggle(true, true, false, true, false, false, false, false), "");
            Check("keys: a ListKey that types closes the list when no text field has the keyboard", ListKeys.MayToggle(true, true, false, false, false, false, false, false), "");
            Check("keys: a ListKey that does not type closes the list while a game text field has the keyboard", ListKeys.MayToggle(true, false, false, true, false, false, false, false), "");
            Check("keys: the pause menu, the build menu, the inventory and the Barber Station do not stop ListKey closing the list", ListKeys.MayToggle(true, false, false, false, true, true, true, true), "");

            // UnityEngine.KeyCode: Mouse0 = 323 ... Mouse6 = 329 (preflight checks the three against Unity).
            Check("keys: the left, right and middle mouse buttons are refused",
                ListKeys.IsClickButton(323) && ListKeys.IsClickButton(324) && ListKeys.IsClickButton(325), "");
            Check("keys: the side buttons, F7, None and the keys around them are not",
                !ListKeys.IsClickButton(322) && !ListKeys.IsClickButton(326) && !ListKeys.IsClickButton(327)
                && !ListKeys.IsClickButton(288) && !ListKeys.IsClickButton(0), "");
        }

        private static void Check(string label, bool condition, string detail)
        {
            if (condition) { _passes++; Console.WriteLine("  ok   " + label); }
            else { _failures++; Console.WriteLine("  FAIL " + label + "  ->  " + detail); }
        }
    }
}
