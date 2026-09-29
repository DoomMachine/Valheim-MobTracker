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
            // The review's case, Charred_Archer: a key-gated rule for the other biomes and a plain Ashlands one.
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

            // The review's case (P1): a Skeleton inside a Burial Chamber, some 5 km up, while the player is outside -
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

        // The creature list's rows: ShouldRefresh(playerChanged, due, pointerOverWindow, mouseHeld). The review's case (P3):
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
        // MayToggle(open, keyTypesText, searchFocused, gameTyping, pauseMenu, buildMenu, inventory).
        private static void ListKeyTests()
        {
            Check("keys: Escape closes the open list", ListKeys.ClosesOnBack(true, false, false, true, false), "");
            Check("keys: the gamepad's B closes the open list", ListKeys.ClosesOnBack(true, false, false, false, true), "");
            Check("keys: nothing pressed closes nothing", !ListKeys.ClosesOnBack(true, false, false, false, false), "");
            Check("keys: Escape does nothing to a closed list", !ListKeys.ClosesOnBack(false, false, false, true, true), "");
            Check("keys: not while the console is open (Escape is closing it)", !ListKeys.ClosesOnBack(true, true, false, true, true), "");
            Check("keys: not while the console was open last frame (it closed itself first)", !ListKeys.ClosesOnBack(true, false, true, true, true), "");

            Check("keys: ListKey opens the list", ListKeys.MayToggle(false, false, false, false, false, false, false), "");
            Check("keys: ListKey closes the list, even while the search box has the keyboard", ListKeys.MayToggle(true, false, true, false, false, false, false), "");
            Check("keys: ListKey does not open the list while the player types in a game text field", !ListKeys.MayToggle(false, false, false, true, false, false, false), "");
            Check("keys: ... whatever the key", !ListKeys.MayToggle(false, true, false, true, false, false, false), "");
            Check("keys: ListKey does not open the list over the pause menu", !ListKeys.MayToggle(false, false, false, false, true, false, false), "");
            Check("keys: ListKey does not open the list over the build menu (its right click would reach it)", !ListKeys.MayToggle(false, false, false, false, false, true, false), "");
            Check("keys: ListKey does not open the list over the inventory", !ListKeys.MayToggle(false, false, false, false, false, false, true), "");
            Check("keys: a ListKey that types does not close the list while its search box has the keyboard", !ListKeys.MayToggle(true, true, true, false, false, false, false), "");
            Check("keys: ... nor while a game text field has it", !ListKeys.MayToggle(true, true, false, true, false, false, false), "");
            Check("keys: a ListKey that types closes the list when no text field has the keyboard", ListKeys.MayToggle(true, true, false, false, false, false, false), "");
            Check("keys: a ListKey that does not type closes the list while a game text field has the keyboard", ListKeys.MayToggle(true, false, false, true, false, false, false), "");
            Check("keys: the pause menu, the build menu and the inventory do not stop ListKey closing the list", ListKeys.MayToggle(true, false, false, false, true, true, true), "");

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
