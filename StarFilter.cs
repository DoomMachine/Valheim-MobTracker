using System;
using System.Globalization;
using System.Text;

namespace MobTracker
{
    /// <summary>
    /// One star category - a button in the window's List: and Alerts: rows. Stars are level minus one, as the list
    /// shows them: "Deer" is level 1, "Deer *" level 2, "Deer **" level 3. Natural spawns stop at two stars; the spawn
    /// command and mods can go higher, which TwoOrMoreStars covers.
    ///
    /// Numbered by star count, not in button order: a number typed into the cfg is the category with that value
    /// (StarSets.Parse), so "2" means two stars and "0" none, as it did when the setting was this enum. The buttons'
    /// order is StarFilters.Buttons().
    /// </summary>
    public enum StarFilter
    {
        NoStars = 0,
        OneStar = 1,
        TwoStars = 2,
        TwoOrMoreStars = 3,
        All = 4
    }

    /// <summary>
    /// A star filter's setting: the categories marked, combined - a creature passes when any of them accepts it.
    /// All (no bit set) marks no category - the All button shows marked instead - and lets everything through. Kept as
    /// text in the cfg (StarSets.Parse, Format), not as this enum: BepInEx reads every enum setting with Enum.Parse,
    /// which would take a typed "2" as the flag value 2 (OneStar) rather than two stars.
    /// </summary>
    [Flags]
    public enum StarSet
    {
        All = 0,
        NoStars = 1,
        OneStar = 2,
        TwoStars = 4,
        TwoOrMoreStars = 8
    }

    /// <summary>The star filter's decisions and labels, free of game objects so the test project can link this file.</summary>
    public static class StarFilters
    {
        /// <summary>The window's buttons, left to right.</summary>
        private static readonly StarFilter[] Order =
        {
            StarFilter.All, StarFilter.NoStars, StarFilter.OneStar, StarFilter.TwoStars, StarFilter.TwoOrMoreStars
        };

        /// <summary>True when a creature of this level passes. Anything outside the enum passes, like All.</summary>
        public static bool Accepts(StarFilter filter, int level)
        {
            switch (filter)
            {
                case StarFilter.NoStars: return level <= 1;
                case StarFilter.OneStar: return level == 2;
                case StarFilter.TwoStars: return level == 3;
                case StarFilter.TwoOrMoreStars: return level >= 3;
                default: return true;
            }
        }

        public static string Label(StarFilter filter)
        {
            switch (filter)
            {
                case StarFilter.NoStars: return "No star";
                case StarFilter.OneStar: return "1 star";
                case StarFilter.TwoStars: return "2 stars";
                case StarFilter.TwoOrMoreStars: return "2+ stars";
                default: return "All";
            }
        }

        /// <summary>The window's buttons, left to right (a copy).</summary>
        public static StarFilter[] Buttons()
        {
            return (StarFilter[])Order.Clone();
        }

        /// <summary>Every button's label, left to right.</summary>
        public static string[] Labels()
        {
            var labels = new string[Order.Length];
            for (int i = 0; i < Order.Length; i++)
                labels[i] = Label(Order[i]);
            return labels;
        }
    }

    /// <summary>
    /// Sets of star categories: what a creature passes, what the window's buttons show and do, and the cfg text. Bits
    /// outside the four categories are ignored everywhere, so a set holding only such bits behaves, shows and is
    /// written as All.
    /// </summary>
    public static class StarSets
    {
        private const StarSet Every = StarSet.NoStars | StarSet.OneStar | StarSet.TwoStars | StarSet.TwoOrMoreStars;

        /// <summary>The categories in their fixed order, for Format and Label.</summary>
        private static readonly StarFilter[] Categories =
        {
            StarFilter.NoStars, StarFilter.OneStar, StarFilter.TwoStars, StarFilter.TwoOrMoreStars
        };

        /// <summary>Every word Parse knows, All included.</summary>
        private static readonly StarFilter[] Words =
        {
            StarFilter.All, StarFilter.NoStars, StarFilter.OneStar, StarFilter.TwoStars, StarFilter.TwoOrMoreStars
        };

        /// <summary>The set holding just this category; All (the empty set) for All or a value outside the enum.</summary>
        public static StarSet Of(StarFilter category)
        {
            switch (category)
            {
                case StarFilter.NoStars: return StarSet.NoStars;
                case StarFilter.OneStar: return StarSet.OneStar;
                case StarFilter.TwoStars: return StarSet.TwoStars;
                case StarFilter.TwoOrMoreStars: return StarSet.TwoOrMoreStars;
                default: return StarSet.All;
            }
        }

        /// <summary>
        /// True when a creature of this level passes: All lets everything through, otherwise any marked category that
        /// accepts the level does. Allocates nothing: the alert poll asks it for every loaded creature.
        /// </summary>
        public static bool Accepts(StarSet set, int level)
        {
            if ((set & Every) == 0)
                return true;
            return ((set & StarSet.NoStars) != 0 && StarFilters.Accepts(StarFilter.NoStars, level))
                   || ((set & StarSet.OneStar) != 0 && StarFilters.Accepts(StarFilter.OneStar, level))
                   || ((set & StarSet.TwoStars) != 0 && StarFilters.Accepts(StarFilter.TwoStars, level))
                   || ((set & StarSet.TwoOrMoreStars) != 0 && StarFilters.Accepts(StarFilter.TwoOrMoreStars, level));
        }

        /// <summary>Whether a button shows as selected: All only while nothing else is, a category while it is in the set.</summary>
        public static bool IsMarked(StarSet set, StarFilter button)
        {
            StarSet flag = Of(button);
            if (flag == StarSet.All)
                return (set & Every) == 0;
            return (set & flag) != 0;
        }

        /// <summary>
        /// The set after a click on a button. All resets to All. A category is added (from All, it is then the only
        /// one) or, when already marked, removed; removing the last one gives All.
        /// </summary>
        public static StarSet Toggle(StarSet set, StarFilter button)
        {
            StarSet flag = Of(button);
            if (flag == StarSet.All)
                return StarSet.All;
            set &= Every;
            return (set & flag) != 0 ? set & ~flag : set | flag;
        }

        /// <summary>
        /// Reads a star filter setting. Tokens are separated by commas (or semicolons), in any case: the names All,
        /// NoStars, OneStar, TwoStars, TwoOrMoreStars; the window's labels All, No star, 1 star, 2 stars, 2+ stars; or a
        /// number of stars, 0 = NoStars, 1 = OneStar, 2 = TwoStars, 3 = TwoOrMoreStars, 4 = All. The categories named
        /// combine; any All token makes it All. Unknown tokens are ignored and named in <paramref name="problem"/>;
        /// with no valid token at all the result is All, with a problem. <paramref name="problem"/> is null when the
        /// text is clean.
        /// </summary>
        public static StarSet Parse(string text, out string problem)
        {
            problem = null;
            StarSet set = StarSet.All;
            bool valid = false, all = false;
            StringBuilder unknown = null;
            string[] tokens = (text ?? "").Split(',', ';');
            foreach (string raw in tokens)
            {
                string token = raw.Trim();
                if (token.Length == 0)
                    continue;
                StarFilter category;
                if (!TryCategory(token, out category))
                {
                    if (unknown == null)
                        unknown = new StringBuilder();
                    else
                        unknown.Append(", ");
                    unknown.Append('\'').Append(token).Append('\'');
                    continue;
                }
                valid = true;
                if (category == StarFilter.All)
                    all = true;
                else
                    set |= Of(category);
            }

            if (!valid)
            {
                problem = (unknown == null ? "it names no star category" : "it names no star category (" + unknown + ")") +
                          ", so it works as All. Write All, or one or more of NoStars, OneStar, TwoStars and TwoOrMoreStars " +
                          "separated by commas, or a number of stars (0-3, 3 = two or more, 4 = All).";
                return StarSet.All;
            }
            if (unknown != null)
                problem = unknown + " ignored: not a star category.";
            return all ? StarSet.All : set;
        }

        private static bool TryCategory(string token, out StarFilter category)
        {
            // A number is a star count, the category with that value (StarFilter is numbered so).
            int number;
            if (int.TryParse(token, NumberStyles.Integer, CultureInfo.InvariantCulture, out number))
            {
                bool known = number >= (int)StarFilter.NoStars && number <= (int)StarFilter.All;
                category = known ? (StarFilter)number : StarFilter.All;
                return known;
            }
            foreach (StarFilter candidate in Words)
            {
                if (string.Equals(token, Name(candidate), StringComparison.OrdinalIgnoreCase)
                    || string.Equals(token, StarFilters.Label(candidate), StringComparison.OrdinalIgnoreCase))
                {
                    category = candidate;
                    return true;
                }
            }
            category = StarFilter.All;
            return false;
        }

        /// <summary>A category's name in the cfg; spelt out rather than Enum.ToString, which differs by runtime.</summary>
        private static string Name(StarFilter category)
        {
            switch (category)
            {
                case StarFilter.NoStars: return "NoStars";
                case StarFilter.OneStar: return "OneStar";
                case StarFilter.TwoStars: return "TwoStars";
                case StarFilter.TwoOrMoreStars: return "TwoOrMoreStars";
                default: return "All";
            }
        }

        /// <summary>The cfg text for a set: "All", or the names in a fixed order joined by ", " ("NoStars, OneStar").</summary>
        public static string Format(StarSet set)
        {
            return Join(set, ", ", true);
        }

        /// <summary>The window title's words for a set: "All", or the labels joined by " + " ("No star + 1 star").</summary>
        public static string Label(StarSet set)
        {
            return Join(set, " + ", false);
        }

        private static string Join(StarSet set, string separator, bool names)
        {
            if ((set & Every) == 0)
                return "All";
            var text = new StringBuilder();
            foreach (StarFilter category in Categories)
            {
                if ((set & Of(category)) == 0)
                    continue;
                if (text.Length > 0)
                    text.Append(separator);
                text.Append(names ? Name(category) : StarFilters.Label(category));
            }
            return text.ToString();
        }
    }
}
