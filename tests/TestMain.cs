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
            CaptionTests();
            RulesTests();
            SpacingTests();
            AlertGateTests();
            AlertStarFilterTests();
            Console.WriteLine(_failures == 0
                ? "ALL TESTS PASSED (" + _passes + ")"
                : _failures + " TEST(S) FAILED, " + _passes + " passed");
            return _failures == 0 ? 0 : 1;
        }

        // The five choices, level by level. Stars are level minus one: 1 = none, 2 = one star, 3 = two stars.
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

            // A value outside the enum (a number or a comma list typed into the cfg) behaves as All.
            StarFilter bogus = (StarFilter)7;
            Check("stars: an out-of-range value accepts everything, reads 'All' and is not a known choice",
                StarFilters.Accepts(bogus, 1) && StarFilters.Accepts(bogus, 3) && StarFilters.Label(bogus) == "All" && !StarFilters.IsDefined(bogus)
                && StarFilters.IsDefined(StarFilter.TwoOrMoreStars), "");
        }

        // The window's toolbars: one segment per choice, in enum order, picked directly by index.
        private static void CaptionTests()
        {
            string[] labels = StarFilters.Labels();
            int members = Enum.GetValues(typeof(StarFilter)).Length;
            Check("toolbar: one segment per choice", labels.Length == members, labels.Length + " for " + members);
            bool roundTrip = true;
            foreach (StarFilter f in Enum.GetValues(typeof(StarFilter)))
                roundTrip &= StarFilters.FromIndex(StarFilters.Index(f)) == f && labels[StarFilters.Index(f)] == StarFilters.Label(f);
            Check("toolbar: each choice has its own segment, labelled with it", roundTrip, string.Join(" | ", labels));
            Check("toolbar: an out-of-range value shows as the All segment, and an out-of-range index picks All",
                StarFilters.Index((StarFilter)7) == 0 && StarFilters.Index((StarFilter)(-1)) == 0
                && StarFilters.FromIndex(9) == StarFilter.All && StarFilters.FromIndex(-1) == StarFilter.All, "");
            Check("toolbar: segments read All, No star, 1 star, 2 stars, 2+ stars, left to right",
                string.Join(",", labels) == "All,No star,1 star,2 stars,2+ stars", string.Join(",", labels));

            // BepInEx reads a hand-typed enum with Enum.Parse(type, text, ignoreCase: true), so a number is the member
            // with that value. StarFilter is numbered by star count, so the number typed is the number of stars.
            Check("cfg: a typed 0, 1, 2 or 3 means that many stars (3 = two or more), 4 means All",
                (StarFilter)Enum.Parse(typeof(StarFilter), "0", true) == StarFilter.NoStars
                && (StarFilter)Enum.Parse(typeof(StarFilter), "1", true) == StarFilter.OneStar
                && (StarFilter)Enum.Parse(typeof(StarFilter), "2", true) == StarFilter.TwoStars
                && (StarFilter)Enum.Parse(typeof(StarFilter), "3", true) == StarFilter.TwoOrMoreStars
                && (StarFilter)Enum.Parse(typeof(StarFilter), "4", true) == StarFilter.All, "");
            Check("cfg: names are read case-insensitively; a number above 4 is not a known choice",
                (StarFilter)Enum.Parse(typeof(StarFilter), "twostars", true) == StarFilter.TwoStars
                && !StarFilters.IsDefined((StarFilter)Enum.Parse(typeof(StarFilter), "7", true)), "");
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

        private static void AlertGateTests()
        {
            var gate = new AlertGate<int>();
            Check("gate: an unwatched creature never alerts", !gate.ShouldAlert(1, false, false, 10f, 0f), "");
            Check("gate: a tamed creature never alerts", !gate.ShouldAlert(2, true, true, 10f, 0f), "");
            Check("gate: outside the radius it does not alert", !gate.ShouldAlert(3, true, false, 50f, 20f), "");
            Check("gate: ...and alerts once it comes inside", gate.ShouldAlert(3, true, false, 15f, 20f), "");
            Check("gate: a creature alerts only once", gate.ShouldAlert(4, true, false, 10f, 0f) && !gate.ShouldAlert(4, true, false, 10f, 0f), "");
            Check("gate: a creature first seen unwatched can alert later", gate.ShouldAlert(1, true, false, 10f, 0f), "");
            gate.Clear();
            Check("gate: Clear lets every creature alert again", gate.ShouldAlert(4, true, false, 10f, 0f), "");
        }

        // The same expression WatchAlerts.Update uses (preflight checks that it reads the alert filter, not the
        // list's): watched = the alert star filter accepts the level AND the type is on the watchlist.
        private static bool Decide(AlertGate<int> gate, int id, int level, StarFilter filter, bool onWatchlist)
        {
            bool watched = StarFilters.Accepts(filter, level) && onWatchlist;
            return gate.ShouldAlert(id, watched, false, 10f, 0f);
        }

        private static void AlertStarFilterTests()
        {
            var gate = new AlertGate<int>();
            Check("alert stars: with '2 stars', a two-star Troll alerts", Decide(gate, 10, 3, StarFilter.TwoStars, true), "");
            Check("alert stars: with '2 stars', a plain Troll does not", !Decide(gate, 11, 1, StarFilter.TwoStars, true), "");
            Check("alert stars: with '2 stars', a one-star Troll does not", !Decide(gate, 12, 2, StarFilter.TwoStars, true), "");
            Check("alert stars: a creature left out alerts once the filter lets it through",
                Decide(gate, 11, 1, StarFilter.All, true) && !Decide(gate, 11, 1, StarFilter.All, true), "");
            Check("alert stars: a type not on the watchlist never alerts, whatever its stars", !Decide(gate, 13, 3, StarFilter.TwoStars, false), "");

            // The review's scenario: watching Troll, the player picks "1 star" straight from "2 stars". With a direct
            // pick the poll only ever sees those two values, so the plain Troll never alerts and the one-star Troll's
            // single alert is not used up by a state passed on the way (a cycling button went through All and NoStars).
            var fresh = new AlertGate<int>();
            bool plainBefore = Decide(fresh, 21, 1, StarFilter.TwoStars, true);
            bool plainAfter = Decide(fresh, 21, 1, StarFilter.OneStar, true);
            bool oneStarAfter = Decide(fresh, 22, 2, StarFilter.OneStar, true);
            Check("alert stars: picking 1 star straight from 2 stars alerts the one-star Troll and never the plain one",
                !plainBefore && !plainAfter && oneStarAfter, plainBefore + "/" + plainAfter + "/" + oneStarAfter);
        }

        private static void Check(string label, bool condition, string detail)
        {
            if (condition) { _passes++; Console.WriteLine("  ok   " + label); }
            else { _failures++; Console.WriteLine("  FAIL " + label + "  ->  " + detail); }
        }
    }
}
