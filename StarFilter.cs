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
    ///
    /// None is the Alerts: row's empty selection under AlertsChange.EmptyAlertsNothing, which is built but not the
    /// shipped mode (AlertsRow): it lets nothing through and marks no button. It counts only while no category is
    /// marked; the List: row never has it.
    /// </summary>
    [Flags]
    public enum StarSet
    {
        All = 0,
        NoStars = 1,
        OneStar = 2,
        TwoStars = 4,
        TwoOrMoreStars = 8,
        None = 16
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
    /// outside the four categories and None are ignored everywhere, so a set holding only such bits behaves, shows and
    /// is written as All. None counts only while no category is marked.
    /// </summary>
    public static class StarSets
    {
        private const StarSet Every = StarSet.NoStars | StarSet.OneStar | StarSet.TwoStars | StarSet.TwoOrMoreStars;

        /// <summary>No category marked and the None marker set: the Alerts: row's "alert on nothing".</summary>
        private static bool IsNone(StarSet set)
        {
            return (set & Every) == 0 && (set & StarSet.None) != 0;
        }

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
        /// True when a creature of this level passes: All lets everything through, None nothing, otherwise any marked
        /// category that accepts the level does. Allocates nothing: the alert poll asks it for every loaded creature.
        /// </summary>
        public static bool Accepts(StarSet set, int level)
        {
            if ((set & Every) == 0)
                return (set & StarSet.None) == 0;
            return ((set & StarSet.NoStars) != 0 && StarFilters.Accepts(StarFilter.NoStars, level))
                   || ((set & StarSet.OneStar) != 0 && StarFilters.Accepts(StarFilter.OneStar, level))
                   || ((set & StarSet.TwoStars) != 0 && StarFilters.Accepts(StarFilter.TwoStars, level))
                   || ((set & StarSet.TwoOrMoreStars) != 0 && StarFilters.Accepts(StarFilter.TwoOrMoreStars, level));
        }

        /// <summary>
        /// Whether a button shows as selected: All only while nothing else is (and not for None, which marks no
        /// button), a category while it is in the set.
        /// </summary>
        public static bool IsMarked(StarSet set, StarFilter button)
        {
            StarSet flag = Of(button);
            if (flag == StarSet.All)
                return (set & (Every | StarSet.None)) == 0;
            return (set & flag) != 0;
        }

        /// <summary>
        /// The set after a click on a button. All resets to All. A category is added (from All or None, it is then the
        /// only one) or, when already marked, removed; removing the last one gives All.
        /// </summary>
        public static StarSet Toggle(StarSet set, StarFilter button)
        {
            return Toggle(set, button, false);
        }

        /// <summary>
        /// As <see cref="Toggle(StarSet, StarFilter)"/>, except that with <paramref name="emptyIsNothing"/> removing the
        /// last category gives None rather than All, so only the All button returns the row to All.
        /// </summary>
        public static StarSet Toggle(StarSet set, StarFilter button, bool emptyIsNothing)
        {
            StarSet flag = Of(button);
            if (flag == StarSet.All)
                return StarSet.All;
            set &= Every;
            StarSet result = (set & flag) != 0 ? set & ~flag : set | flag;
            return emptyIsNothing && result == StarSet.All ? StarSet.None : result;
        }

        /// <summary>
        /// Reads a star filter setting. Tokens are separated by commas (or semicolons), in any case: the names All,
        /// NoStars, OneStar, TwoStars, TwoOrMoreStars; the window's labels All, No star, 1 star, 2 stars, 2+ stars; or a
        /// number of stars, 0 = NoStars, 1 = OneStar, 2 = TwoStars, 3 = TwoOrMoreStars, 4 = All. The categories named
        /// combine; any All token makes it All. Unknown tokens are ignored and named in <paramref name="problem"/>;
        /// with no valid token at all the result is All, with a problem. <paramref name="problem"/> is null when the
        /// text is clean. "None" is an unknown token here (<see cref="Parse(string, out string, bool)"/>).
        /// </summary>
        public static StarSet Parse(string text, out string problem)
        {
            return Parse(text, out problem, false);
        }

        /// <summary>
        /// As <see cref="Parse(string, out string)"/>; with <paramref name="allowNone"/> the word None (any case) is
        /// read too, as None when no category and no All is named, and ignored beside them. Without it None is an
        /// unknown token, which alone works as All.
        /// </summary>
        public static StarSet Parse(string text, out string problem, bool allowNone)
        {
            problem = null;
            StarSet set = StarSet.All;
            bool valid = false, all = false, none = false;
            StringBuilder unknown = null;
            string[] tokens = (text ?? "").Split(',', ';');
            foreach (string raw in tokens)
            {
                string token = raw.Trim();
                if (token.Length == 0)
                    continue;
                if (allowNone && string.Equals(token, NoneName, StringComparison.OrdinalIgnoreCase))
                {
                    valid = true;
                    none = true;
                    continue;
                }
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
                          ", so it works as All. Write All, " + (allowNone ? "None, " : "") + "or one or more of NoStars, " +
                          "OneStar, TwoStars and TwoOrMoreStars separated by commas, or a number of stars (0-3, 3 = two or " +
                          "more, 4 = All).";
                return StarSet.All;
            }
            if (unknown != null)
                problem = unknown + " ignored: not a star category.";
            if (all)
                return StarSet.All;
            return set == StarSet.All && none ? StarSet.None : set;
        }

        /// <summary>None's word in the cfg (read only when Parse is allowed to).</summary>
        private const string NoneName = "None";

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

        /// <summary>
        /// The cfg text for a set: "All", "None", or the names in a fixed order joined by ", " ("NoStars, OneStar").
        /// </summary>
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
            if (IsNone(set))
                return NoneName;
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

    /// <summary>
    /// Follows a changing star set once it holds still: the set the alerts use, which follows the Alerts: filter only
    /// after its text has stayed the same for <see cref="SettleSeconds"/>. So the states the filter passes through while
    /// the row is clicked - taking off the only marked category returns it to All - or while a value is typed in
    /// ConfigurationManager, which writes the setting at every keystroke (a text with no word it knows yet reads as All), never
    /// reach the once-a-second alert poll, which alerts each creature once (why a button that cycles through the choices, which
    /// alerts on every choice it passes, is not used). The first set it is given is taken at once, so nothing waits at the start.
    /// Allocates nothing: it is asked every frame.
    /// </summary>
    public sealed class StarSetSettler
    {
        public const float SettleSeconds = 1.5f;

        private bool _started;
        private StarSet _settled;
        private StarSet _pending;
        private int _revision;
        private float _pendingSince;

        /// <summary>
        /// The settled set, given the set as it is <paramref name="now"/> (in seconds) and the <paramref name="revision"/>
        /// of the text it was read from, which changes at every write of that text. A set that differs from the settled
        /// one is taken once neither it nor the revision has changed for SettleSeconds - so a write that leaves the set as
        /// it was restarts the wait too - and a return to the settled set before then calls the change off.
        /// </summary>
        public StarSet Settled(StarSet current, int revision, float now)
        {
            if (!_started)
            {
                _started = true;
                _settled = current;
                _pending = current;
                return _settled;
            }

            if (current == _settled)
            {
                _pending = current;
                return _settled;
            }

            if (current != _pending || revision != _revision)
            {
                _pending = current;
                _revision = revision;
                _pendingSince = now;
            }

            if (now - _pendingSince >= SettleSeconds)
                _settled = current;
            return _settled;
        }

        /// <summary>
        /// Starts over: the next set it is given is taken at once, as the first one is. For a new game session
        /// (WatchAlerts.ResetSession), whose Alerts: row may just have been set back to All.
        /// </summary>
        public void Reset()
        {
            _started = false;
        }
    }

    /// <summary>
    /// How a change on the Alerts: row reaches the alerts, Auto-track and Always track nearest watched. Not a setting:
    /// <see cref="AlertsRow.AlertsChangeMode"/> is fixed in the code.
    /// </summary>
    internal enum AlertsChange
    {
        /// <summary>The shipped mode: the alerts follow the row once its cfg text has held still for StarSetSettler.SettleSeconds.</summary>
        Settle = 0,

        /// <summary>
        /// Built and tested, not shipped: the alerts follow the row at once, and taking off the Alerts: row's last marked
        /// category gives None (alert on nothing); only the All button returns it to All. Nothing waits here, so a value
        /// typed in ConfigurationManager applies at every keystroke, a word typed so far as All.
        /// </summary>
        EmptyAlertsNothing = 1
    }

    /// <summary>The Alerts: row's rules under an <see cref="AlertsChange"/> mode, free of game objects for the tests.</summary>
    internal static class AlertsRow
    {
        /// <summary>
        /// The mode MobTracker runs with. Static readonly, not const: a const would be copied into each caller as the
        /// literal 0, and tools\preflight.ps1 checks that each caller reads this field, and that the build keeps Settle.
        /// </summary>
        internal static readonly AlertsChange AlertsChangeMode = AlertsChange.Settle;

        /// <summary>Whether taking off the Alerts: row's last category gives None - and so whether its cfg text may say None.</summary>
        public static bool EmptyIsNothing(AlertsChange mode)
        {
            return mode == AlertsChange.EmptyAlertsNothing;
        }

        /// <summary>
        /// The set the alerts use, given the row's set as it is <paramref name="now"/> and the revision of its cfg text:
        /// the settler's under Settle, the row's own otherwise. Asked every frame.
        /// </summary>
        public static StarSet Effective(StarSet row, int revision, StarSetSettler settler, float now, AlertsChange mode)
        {
            return mode == AlertsChange.Settle ? settler.Settled(row, revision, now) : row;
        }
    }
}
