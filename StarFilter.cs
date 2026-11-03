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
    /// Numbered by star count, not in button order: a category number typed into the cfg is the category with that value
    /// (StarSets.Parse), so "2" is TwoStars and "0" NoStars, as it was when the setting was this enum. A number there is a
    /// category, not a count of stars: exact counts are a row's StarCounts (0.9.0). The buttons' order is
    /// StarFilters.Buttons().
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
    /// All (no bit set) marks no category: on its own it lets everything through, and the All button shows marked; in a
    /// row with star counts (StarRule, 0.9.0) only the counts pass, and the All button does not show marked. Kept as
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
        /// only one) or, when already marked, removed; removing the last one leaves no category marked - the set All,
        /// which in a row with star counts lets only the counts through (StarRule).
        /// </summary>
        public static StarSet Toggle(StarSet set, StarFilter button)
        {
            return Toggle(set, button, false);
        }

        /// <summary>
        /// As <see cref="Toggle(StarSet, StarFilter)"/>, except that with <paramref name="emptyIsNothing"/> removing the
        /// last category gives None rather than All, so only the All button empties the set.
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
        /// category number, 0 = NoStars, 1 = OneStar, 2 = TwoStars, 3 = TwoOrMoreStars, 4 = All - a category, not a count
        /// of stars (those are StarCounts). The categories named combine; any All token makes it All. Unknown tokens are
        /// ignored and named in <paramref name="problem"/>; with no valid token at all the result is All - no category
        /// marked - with a problem. <paramref name="problem"/> is null when the text is clean. "None" is an unknown token
        /// here (<see cref="Parse(string, out string, bool)"/>).
        /// </summary>
        public static StarSet Parse(string text, out string problem)
        {
            return Parse(text, out problem, false);
        }

        /// <summary>
        /// As <see cref="Parse(string, out string)"/>; with <paramref name="allowNone"/> the word None (any case) is
        /// read too, as None when no category and no All is named, and ignored beside them. Without it None is an
        /// unknown token, which alone marks no category.
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
                          ", so no category is marked: the row lets every star level through when it has no star count, " +
                          "and only its counts when it has some. Write All, " + (allowNone ? "None, " : "") +
                          "or one or more of NoStars, OneStar, TwoStars and TwoOrMoreStars separated by commas, or a " +
                          "category number (0 = NoStars, 1 = OneStar, 2 = TwoStars, 3 = TwoOrMoreStars, 4 = All); exact " +
                          "star counts have settings of their own (ListStarCounts, AlertStarCounts).";
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
            // A number is a category number, the category with that value (StarFilter is numbered so), not a count of stars.
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

        // ---- A whole star row: its categories and the counts typed in its field (0.9.0) ----

        /// <summary>
        /// True when a creature of this level passes the row: one of its counts has the creature's stars, or a marked
        /// category accepts it. With no category marked only the counts pass; with no count, as
        /// <see cref="Accepts(StarSet, int)"/> - All everything, None nothing. Allocates nothing.
        /// </summary>
        public static bool Accepts(StarRule rule, int level)
        {
            if (rule.Counts.IsEmpty)
                return Accepts(rule.Set, level);
            if (rule.Counts.Accepts(level))
                return true;
            return (rule.Set & Every) != 0 && Accepts(rule.Set, level);
        }

        /// <summary>No category, no None and no count: every star level passes, and the All button shows marked.</summary>
        public static bool IsAll(StarRule rule)
        {
            return rule.Counts.IsEmpty && (rule.Set & (Every | StarSet.None)) == 0;
        }

        /// <summary>As <see cref="IsMarked(StarSet, StarFilter)"/>, except that All shows marked only while the row has no count either.</summary>
        public static bool IsMarked(StarRule rule, StarFilter button)
        {
            if (Of(button) == StarSet.All)
                return IsAll(rule);
            return IsMarked(rule.Set, button);
        }

        /// <summary>The row's categories after a click on a button, as <see cref="Toggle(StarSet, StarFilter)"/>; its counts are the field's.</summary>
        public static StarSet Toggle(StarRule rule, StarFilter button)
        {
            return Toggle(rule.Set, button, false);
        }

        /// <summary>As <see cref="Toggle(StarSet, StarFilter, bool)"/>, on the row's categories.</summary>
        public static StarSet Toggle(StarRule rule, StarFilter button, bool emptyIsNothing)
        {
            return Toggle(rule.Set, button, emptyIsNothing);
        }

        /// <summary>
        /// The window title's and the log's words for a row: its categories as <see cref="Label(StarSet)"/> gives them, then
        /// "stars" and the counts - "1 star + stars 3-5, 8"; the counts alone with no category marked - "stars 3-5, 8".
        /// </summary>
        public static string Label(StarRule rule)
        {
            if (rule.Counts.IsEmpty)
                return Label(rule.Set);
            string counts = "stars " + rule.Counts.Label();
            return (rule.Set & Every) == 0 ? counts : Label(rule.Set) + " + " + counts;
        }
    }

    /// <summary>
    /// The star counts typed in a star row's field (0.9.0, FW-11): whole numbers from 0 to 100, single or as ranges
    /// ("3-5, 8"), kept as a mask of 101 bits - count n is bit n - so a test, a copy and a comparison allocate nothing:
    /// the alert poll asks it for every loaded creature, and the Alerts: row's settling compares it every frame. Stars
    /// are level minus one, as the list shows them; a level of 1 or less has no star (0), as the No star button reads it.
    /// </summary>
    public struct StarCounts : IEquatable<StarCounts>
    {
        /// <summary>The largest count a field takes (D-004 in the repository's decisions/).</summary>
        public const int Most = 100;

        private readonly ulong _low;   // counts 0 to 63
        private readonly ulong _high;  // counts 64 to 100

        private StarCounts(ulong low, ulong high)
        {
            _low = low;
            _high = high;
        }

        /// <summary>No count: the field is empty (or holds only spaces and commas).</summary>
        public bool IsEmpty
        {
            get { return _low == 0UL && _high == 0UL; }
        }

        /// <summary>True when a creature of this level has one of the counts: its stars are level - 1, and 0 at level 1 or less.</summary>
        public bool Accepts(int level)
        {
            int stars = level <= 1 ? 0 : level - 1;
            return stars <= Most && Has(stars);
        }

        private bool Has(int stars)
        {
            return stars < 64 ? (_low & (1UL << stars)) != 0UL : (_high & (1UL << (stars - 64))) != 0UL;
        }

        private StarCounts With(int from, int to)
        {
            ulong low = _low, high = _high;
            for (int stars = from; stars <= to; stars++)
            {
                if (stars < 64)
                    low |= 1UL << stars;
                else
                    high |= 1UL << (stars - 64);
            }
            return new StarCounts(low, high);
        }

        /// <summary>
        /// Reads a count field's text (D-002 and D-004 in the repository's decisions/; docs/open-items.md, Decided, gives
        /// each case its reason). Entries are separated by commas; each is a whole number from 0 to 100, or two of them
        /// joined by a dash, a range, in either order ("3-5" and "5-3" are the same range), in the digits 0 to 9. Spaces
        /// and tabs around a number, the dash and the commas are ignored, and so is an empty entry ("3,,5", "3,", ",3"),
        /// so an empty text is no count and a comma typed on the way to the next number is never unreadable. Leading zeros
        /// are part of the number ("007" is 7); repeated and overlapping entries add up. Anything else - a sign, a range
        /// left open ("3-", "-3"), another dash, a decimal point, a letter, another space or digit, a number above 100
        /// (also as a range's end), a third number ("3-5-7") - makes the whole text unreadable: false, with no count, and
        /// <paramref name="problem"/> the first entry it could not read, spaces and tabs trimmed. Not int.TryParse: it
        /// takes a sign and spaces of its own. Allocates only for the problem.
        /// </summary>
        public static bool TryParse(string text, out StarCounts counts, out string problem)
        {
            counts = default(StarCounts);
            problem = null;
            string s = text ?? "";
            var read = default(StarCounts);
            int start = 0;
            while (start <= s.Length)
            {
                int end = s.IndexOf(',', start);
                if (end < 0)
                    end = s.Length;
                int i = start;
                SkipBlanks(s, ref i, end);
                if (i < end)
                {
                    int from, to;
                    bool ok = ReadNumber(s, ref i, end, out from);
                    to = from;
                    if (ok)
                    {
                        SkipBlanks(s, ref i, end);
                        if (i < end && s[i] == '-')
                        {
                            i++;
                            SkipBlanks(s, ref i, end);
                            ok = ReadNumber(s, ref i, end, out to);
                            SkipBlanks(s, ref i, end);
                        }
                        ok = ok && i == end;
                    }
                    if (!ok)
                    {
                        problem = s.Substring(start, end - start).Trim(' ', '\t');
                        return false;
                    }
                    read = from <= to ? read.With(from, to) : read.With(to, from);
                }
                start = end + 1;
            }
            counts = read;
            return true;
        }

        /// <summary>As <see cref="TryParse(string, out StarCounts, out string)"/>, without the entry it could not read.</summary>
        public static bool TryParse(string text, out StarCounts counts)
        {
            string problem;
            return TryParse(text, out counts, out problem);
        }

        private static void SkipBlanks(string s, ref int i, int end)
        {
            while (i < end && (s[i] == ' ' || s[i] == '\t'))
                i++;
        }

        /// <summary>
        /// A whole number from 0 to <see cref="Most"/> in the digits 0 to 9 at i, before <paramref name="end"/>; false for
        /// none, or one above Most (it stops there, so it never overflows).
        /// </summary>
        private static bool ReadNumber(string s, ref int i, int end, out int number)
        {
            number = 0;
            int first = i;
            while (i < end && s[i] >= '0' && s[i] <= '9')
            {
                number = number * 10 + (s[i] - '0');
                if (number > Most)
                    return false;
                i++;
            }
            return i > first;
        }

        /// <summary>
        /// The log's words for a count text that cannot be read (ModConfig.ParseCounts): the entry it could not read, and
        /// the counts kept instead - the counts read before it, none at the game's start.
        /// </summary>
        public static string Problem(string entry, StarCounts kept)
        {
            return "'" + entry + "' is not a whole number from 0 to 100, nor two of them joined by a dash, so the text is not applied and "
                   + (kept.IsEmpty ? "the row has no star count" : "the row keeps its star counts (" + kept.Label() + ")")
                   + ". Write whole numbers from 0 to 100, single or as ranges, separated by commas, such as 3-5, 8.";
        }

        /// <summary>The counts in words, for the window's title and the log: runs of two or more as ranges - "3-5, 8"; "" for none.</summary>
        public string Label()
        {
            var text = new StringBuilder();
            int stars = 0;
            while (stars <= Most)
            {
                if (!Has(stars))
                {
                    stars++;
                    continue;
                }
                int last = stars;
                while (last < Most && Has(last + 1))
                    last++;
                if (text.Length > 0)
                    text.Append(", ");
                text.Append(stars.ToString(CultureInfo.InvariantCulture));
                if (last > stars)
                    text.Append('-').Append(last.ToString(CultureInfo.InvariantCulture));
                stars = last + 1;
            }
            return text.ToString();
        }

        public bool Equals(StarCounts other)
        {
            return _low == other._low && _high == other._high;
        }

        public override bool Equals(object obj)
        {
            return obj is StarCounts && Equals((StarCounts)obj);
        }

        public override int GetHashCode()
        {
            return _low.GetHashCode() ^ _high.GetHashCode();
        }

        public static bool operator ==(StarCounts a, StarCounts b)
        {
            return a.Equals(b);
        }

        public static bool operator !=(StarCounts a, StarCounts b)
        {
            return !a.Equals(b);
        }
    }

    /// <summary>
    /// What a star row lets through (0.9.0): the categories its buttons mark and the counts typed in its field, one value
    /// that the list applies, the Alerts: row's settling compares and every alert test reads (StarSets.Accepts). Compared
    /// by its two parts; copied, tested and compared without allocating.
    /// </summary>
    public struct StarRule : IEquatable<StarRule>
    {
        public readonly StarSet Set;
        public readonly StarCounts Counts;

        public StarRule(StarSet set, StarCounts counts)
        {
            Set = set;
            Counts = counts;
        }

        /// <summary>
        /// A row of categories only, no count: for the tests, which build rows from sets. The plugin never converts
        /// (tools\preflight.ps1 checks that it calls this nowhere): a set handed on as a row would drop the counts.
        /// </summary>
        public static implicit operator StarRule(StarSet set)
        {
            return new StarRule(set, default(StarCounts));
        }

        public bool Equals(StarRule other)
        {
            return Set == other.Set && Counts == other.Counts;
        }

        public override bool Equals(object obj)
        {
            return obj is StarRule && Equals((StarRule)obj);
        }

        public override int GetHashCode()
        {
            return ((int)Set * 397) ^ Counts.GetHashCode();
        }

        public static bool operator ==(StarRule a, StarRule b)
        {
            return a.Equals(b);
        }

        public static bool operator !=(StarRule a, StarRule b)
        {
            return !a.Equals(b);
        }
    }

    /// <summary>
    /// A star row's count field in the window (0.9.0): what it shows, and when its text is written to the row's setting.
    /// EntityListWindow holds one per row: OnGUI hands it what was typed (Typed) or empties it (Clear, a click on the
    /// row's All); Update asks Sync once a frame while the list is open; Open shows the setting (Show). Text it can read
    /// is handed back to be written, as typed; text it cannot read is never written, so the counts read before it stay. A
    /// change made elsewhere - ConfigurationManager, the session reset, another plugin - replaces what the field shows.
    /// Free of game types, so the tests link it.
    /// </summary>
    public sealed class CountsField
    {
        private string _text = "";
        private string _seen;          // the setting's text as last shown or handed back here; null until the first Show
        private string _checked = "";  // the text Unreadable was last worked out for

        /// <summary>The text the field shows.</summary>
        public string Text
        {
            get { return _text; }
        }

        /// <summary>The text shown cannot be read: the field shows it as invalid, and it is not applied.</summary>
        public bool Unreadable { get; private set; }

        /// <summary>
        /// After a Sync in which typing changed the text and nothing was written: it cannot be read, or it is the
        /// setting's own text again. The Alerts: row's wait restarts on it (ModConfig.AlertRowChanged).
        /// </summary>
        public bool TypedNotWritten { get; private set; }

        /// <summary>After the Sync in which typing turned the text into one that cannot be read - once per such turn.</summary>
        public bool TurnedUnreadable { get; private set; }

        /// <summary>Shows the setting's text as it is now: what was typed and not applied is dropped.</summary>
        public void Show(string setting)
        {
            _seen = setting ?? "";
            _text = _seen;
            _checked = _text;
            StarCounts counts;
            Unreadable = !StarCounts.TryParse(_text, out counts);
            TypedNotWritten = false;
            TurnedUnreadable = false;
        }

        /// <summary>The text after a keystroke in the field (OnGUI).</summary>
        public void Typed(string text)
        {
            _text = text ?? "";
        }

        /// <summary>Empties the field (OnGUI: a click on the row's All); the next Sync writes the empty text.</summary>
        public void Clear()
        {
            _text = "";
        }

        /// <summary>
        /// Once a frame while the list is open, given the setting's text as it is now: the text to write to the setting -
        /// typed text it can read, which differs from the setting - or null. A setting changed elsewhere since it was last
        /// shown or handed back is shown instead, and nothing is written. Sets TypedNotWritten and TurnedUnreadable for
        /// this frame.
        /// </summary>
        public string Sync(string setting)
        {
            setting = setting ?? "";
            TypedNotWritten = false;
            TurnedUnreadable = false;
            if (_seen == null || setting != _seen)
            {
                Show(setting);
                return null;
            }
            if (_text == _checked)
                return null;
            bool was = Unreadable;
            _checked = _text;
            StarCounts counts;
            Unreadable = !StarCounts.TryParse(_text, out counts);
            if (Unreadable || _text == setting)
            {
                TypedNotWritten = true;
                TurnedUnreadable = Unreadable && !was;
                return null;
            }
            _seen = _text;
            return _text;
        }
    }

    /// <summary>
    /// Follows a changing star row once it holds still: the row the alerts use, which follows the Alerts: row - its
    /// categories and, since 0.9.0, its counts: one settler for both - only after its texts have stayed the same for
    /// <see cref="SettleSeconds"/>. So the states the row passes through while it is clicked - taking off the only marked
    /// category leaves no category, which with no count lets every star level through - or while a value is typed in its
    /// field or in ConfigurationManager, which writes the setting at every keystroke (a text with no word it knows yet
    /// marks no category), never reach the once-a-second alert poll, which alerts each creature once (why a button that
    /// cycles through the choices, which alerts on every choice it passes, is not used). A keystroke in the row's field
    /// that writes nothing restarts the wait too, through the revision (ModConfig.AlertRowChanged). The first row it is
    /// given is taken at once, so nothing waits at the start. Allocates nothing: it is asked every frame.
    /// </summary>
    public sealed class StarSetSettler
    {
        public const float SettleSeconds = 1.5f;

        private bool _started;
        private StarRule _settled;
        private StarRule _pending;
        private int _revision;
        private float _pendingSince;

        /// <summary>
        /// The settled row, given the row as it is <paramref name="now"/> (in seconds) and the <paramref name="revision"/>
        /// of the texts it was read from, which changes at every write of either and at every keystroke in the row's field
        /// that writes nothing (ModConfig.AlertRowChanged). A row that differs from the settled
        /// one is taken once neither it nor the revision has changed for SettleSeconds - so a write that leaves the row as
        /// it was restarts the wait too - and a return to the settled row before then calls the change off.
        /// </summary>
        public StarRule Settled(StarRule current, int revision, float now)
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
        /// category gives None (alert on nothing); only the All button resets it. Nothing waits here, so a value typed in
        /// ConfigurationManager applies at every keystroke, a text with no word it knows yet marking no category.
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
        /// The row the alerts use, given the row as it is <paramref name="now"/> and the revision of its cfg texts: the
        /// settler's under Settle, the row's own otherwise. Asked every frame.
        /// </summary>
        public static StarRule Effective(StarRule row, int revision, StarSetSettler settler, float now, AlertsChange mode)
        {
            return mode == AlertsChange.Settle ? settler.Settled(row, revision, now) : row;
        }
    }
}
