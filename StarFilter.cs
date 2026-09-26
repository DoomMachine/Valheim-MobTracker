using System;

namespace MobTracker
{
    /// <summary>
    /// Which star levels a filter lets through. Stars are level minus one, as the list shows them: "Deer" is
    /// level 1, "Deer *" level 2, "Deer **" level 3. Natural spawns stop at two stars; the spawn command and
    /// mods can go higher, which TwoOrMoreStars covers.
    ///
    /// Numbered by star count, not in toolbar order: BepInEx reads a number typed into the cfg as the member
    /// with that value, so "2" means two stars and "0" none. The toolbar's order is StarFilters.Order.
    /// </summary>
    public enum StarFilter
    {
        NoStars = 0,
        OneStar = 1,
        TwoStars = 2,
        TwoOrMoreStars = 3,
        All = 4
    }

    /// <summary>The star filter's decisions and labels, free of game objects so the test project can link this file.</summary>
    public static class StarFilters
    {
        /// <summary>The toolbar's segments, left to right.</summary>
        private static readonly StarFilter[] Order =
        {
            StarFilter.All, StarFilter.NoStars, StarFilter.OneStar, StarFilter.TwoStars, StarFilter.TwoOrMoreStars
        };

        /// <summary>True when a creature of this level passes. Anything outside the enum (a number typed into the cfg) passes, like All.</summary>
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

        /// <summary>Every choice's label in toolbar order.</summary>
        public static string[] Labels()
        {
            var labels = new string[Order.Length];
            for (int i = 0; i < Order.Length; i++)
                labels[i] = Label(Order[i]);
            return labels;
        }

        /// <summary>The toolbar segment for a choice; a value outside the enum shows as All, which is how it behaves. Allocates nothing: it runs on every window event.</summary>
        public static int Index(StarFilter filter)
        {
            for (int i = 0; i < Order.Length; i++)
            {
                if (Order[i] == filter)
                    return i;
            }
            return 0;
        }

        public static StarFilter FromIndex(int index)
        {
            return index >= 0 && index < Order.Length ? Order[index] : StarFilter.All;
        }

        /// <summary>True for the five members; false for a number above 4 or a comma list that ORs past them (see ModConfig).</summary>
        public static bool IsDefined(StarFilter filter)
        {
            return Enum.IsDefined(typeof(StarFilter), filter);
        }
    }
}
