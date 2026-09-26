using System;

namespace MobTracker
{
    /// <summary>
    /// Which star levels a filter lets through. Stars are level minus one, as the list shows them: "Deer" is
    /// level 1, "Deer *" level 2, "Deer **" level 3. Natural spawns stop at two stars; the spawn command and
    /// mods can go higher, which TwoOrMoreStars covers.
    /// </summary>
    public enum StarFilter
    {
        All,
        NoStars,
        OneStar,
        TwoStars,
        TwoOrMoreStars
    }

    /// <summary>The star filter's decisions and labels, free of game objects so the test project can link this file.</summary>
    public static class StarFilters
    {
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

        /// <summary>Every choice's label, in enum order: the window's toolbar segments.</summary>
        public static string[] Labels()
        {
            var labels = new string[Enum.GetValues(typeof(StarFilter)).Length];
            for (int i = 0; i < labels.Length; i++)
                labels[i] = Label((StarFilter)i);
            return labels;
        }

        /// <summary>
        /// The toolbar segment for a choice; a value outside the enum shows as All, which is how it behaves.
        /// A range test, not Enum.IsDefined, which boxes: this runs on every window event.
        /// </summary>
        public static int Index(StarFilter filter)
        {
            int i = (int)filter;
            return i >= (int)StarFilter.All && i <= (int)StarFilter.TwoOrMoreStars ? i : 0;
        }

        public static StarFilter FromIndex(int index)
        {
            return index >= (int)StarFilter.All && index <= (int)StarFilter.TwoOrMoreStars ? (StarFilter)index : StarFilter.All;
        }

        /// <summary>True for the five names; false for a number or a comma list typed into the cfg (see ModConfig).</summary>
        public static bool IsDefined(StarFilter filter)
        {
            return Enum.IsDefined(typeof(StarFilter), filter);
        }
    }
}
