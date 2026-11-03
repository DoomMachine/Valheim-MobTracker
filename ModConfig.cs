using System.Collections.Generic;
using BepInEx.Configuration;
using UnityEngine;

namespace MobTracker
{
    internal enum GuideMode
    {
        Arrow,
        GroundPath
    }

    internal static class ModConfig
    {
        public static ConfigEntry<KeyCode> ListKey;
        public static ConfigEntry<GuideMode> Guide;
        public static ConfigEntry<float> ArrowSize;
        public static ConfigEntry<float> ArrowHeight;
        public static ConfigEntry<string> WatchlistEntry;
        public static ConfigEntry<float> AlertRadius;
        public static ConfigEntry<float> AlertVolume;
        public static ConfigEntry<bool> AutoTrack;
        public static ConfigEntry<bool> AlwaysTrackNearest;
        // The star filters as the cfg holds them: text, not the StarSet enum, which BepInEx would read with Enum.Parse
        // (a typed 2 would be the flag value 2, one star). The window writes them in StarSets.Format's form.
        public static ConfigEntry<string> ListStarsText;
        public static ConfigEntry<string> AlertStarsText;
        // The star counts typed in each row's field (0.9.0), as text: StarCounts.TryParse reads them.
        public static ConfigEntry<string> ListCountsText;
        public static ConfigEntry<string> AlertCountsText;
        // Whether the watchlist, the two star filters and their counts outlast a game session (ResetSession).
        public static ConfigEntry<bool> KeepBetweenSessions;

        // What each row lets through - its categories and its counts - re-read whenever one of its two entries changes;
        // tools\preflight.ps1 checks who reads and writes each of them. The window's rows show them as they are; the
        // alerts, Auto-track and Always track nearest watched use AlertStars only through WatchAlerts.EffectiveAlertStars,
        // which follows it once it holds still.
        public static StarRule ListStars;
        public static StarRule AlertStars;

        // How many times the Alerts: row has changed since the start - AlertStarsText, AlertCountsText, or its field's text
        // by a keystroke that wrote nothing (AlertRowChanged, the only place it is counted): the settler behind
        // EffectiveAlertStars restarts its wait at every change, also one that leaves AlertStars as it was
        // (ConfigurationManager writes the setting at each keystroke, and a text with no word Parse knows yet marks no
        // category).
        public static int AlertStarsRevision;

        /// <summary>Parsed view of <see cref="WatchlistEntry"/>; rebuilt whenever the entry changes.</summary>
        public static HashSet<string> Watchlist { get; private set; }

        public static void Bind(ConfigFile config)
        {
            ListKey = config.Bind("General", "ListKey", KeyCode.F7,
                "Opens and closes the creature list; Escape or the gamepad's B also close it. It does not open the list while " +
                "you type in chat, a sign or a map pin's name, while the console is open, or over the pause menu, the build " +
                "menu, the inventory or the Barber Station. A key that types (a letter, a digit...) does not close the list " +
                "while its search box or a star-count field has the keyboard. A key the game cannot read (WheelUp, F13, " +
                "Plus...) and the left, right and middle mouse " +
                "buttons do nothing, and the log says so once; keys the game ignores outright - Mouse5, Mouse6, F16 to F24 " +
                "and the numbered-joystick buttons - never fire, with no warning.");
            // A new key is tried afresh, and warned about again if it cannot be used either.
            ListKey.SettingChanged += (sender, args) => Hotkeys.Forget();

            Guide = config.Bind("Tracking", "GuideMode", GuideMode.Arrow,
                "Arrow: a 3D arrow above your head pointing at the target. " +
                "GroundPath: a line along the walkable ground to a target up to 250 m away. The arrow shows instead beyond " +
                "250 m, and as well while the line is missing or ends 5 m or more (measured on the flat) short of the " +
                "target: still being built, a flying or swimming target, a cliff.");
            // Ranges, so the arrow can neither turn round (a negative size) nor vanish (0). BepInEx sets a value outside to
            // the nearest end - also one read from the cfg, when the game starts - and the file is saved with it once
            // every setting is read (ConfigSaver.Watch).
            ArrowSize = config.Bind("Tracking", "ArrowSize", 0.6f,
                new ConfigDescription("Arrow length in metres, from 0.1 to 3. A value outside the range is set to the nearest end.",
                    new AcceptableValueRange<float>(0.1f, 3f)));
            ArrowHeight = config.Bind("Tracking", "ArrowHeight", 2.6f,
                new ConfigDescription("Height of the arrow's middle above the player's feet, in metres, from 0 to 5. A value " +
                    "outside the range is set to the nearest end.", new AcceptableValueRange<float>(0f, 5f)));

            KeepBetweenSessions = config.Bind("General", "KeepBetweenSessions", false,
                "Keep the watched creature types, both star filters and both star counts - Watchlist, ListStarFilter, " +
                "ListStarCounts, AlertStarFilter and AlertStarCounts, which the window's Watch buttons and its List: and " +
                "Alerts: rows set - from one game session to the next. " +
                "Off: whenever you enter a world or go back to the main menu they are set back to nothing watched, All and no count, " +
                "so logging out and in again, or restarting the game, starts afresh; dying does not. Which character or " +
                "world plays no part. Closing the game leaves the last ones in this file until you next enter a world. " +
                "On: they stay as they are, saved in this file.");

            WatchlistEntry = config.Bind("Alerts", "Watchlist", "",
                "Comma-separated creature prefab names to alert on, e.g. Troll,Serpent. The window's Watch buttons edit " +
                "this, also for a creature not around (the 'View: all types' list). Emptied whenever you enter a world " +
                "or go back to the main menu, unless KeepBetweenSessions is on. To edit it by hand with KeepBetweenSessions on, close the game " +
                "first: the file is read at the start, and while the game runs a setting changed in the window rewrites it.");
            AlertRadius = config.Bind("Alerts", "AlertRadius", 0f,
                "Only alert, or re-track (AlwaysTrackNearestWatched), within this many metres; a creature that alerted " +
                "during a re-track's wait and has left the radius by then is taken only once it is back inside. 0 = no " +
                "limit: anywhere the creature is loaded on your client.");
            AlertVolume = config.Bind("Alerts", "AlertVolume", 0.8f,
                new ConfigDescription("Ding volume. The game's Volume and Effect volume settings apply on top of it.",
                    new AcceptableValueRange<float>(0f, 1f)));

            AutoTrack = config.Bind("Alerts", "AutoTrack", true,
                "Start tracking a watched creature the moment it alerts. Never replaces a creature you are already tracking, " +
                "nor takes a creature on the other side of a dungeon entrance, nor acts while AlwaysTrackNearestWatched " +
                "waits after a loss - that wait chooses instead. The alert itself still shows.");
            AlwaysTrackNearest = config.Bind("Alerts", "AlwaysTrackNearestWatched", false,
                "When a tracked creature is lost - killed, no longer loaded on your client, or tamed while tracked (taming a " +
                "creature tracked wild ends its tracking) - while something is watched, " +
                "wait 5 seconds, then track the nearest creature of any watched type that the Alerts: row lets through " +
                "(AlertStarFilter and AlertStarCounts, as the alerts use them), within AlertRadius, on your side of a " +
                "dungeon entrance and never a tamed one, looking again " +
                "once a second until there is one. Any tracked creature's loss starts the wait: one of a type not on the " +
                "watchlist, or a tamed one, too. To hunt one kind only, watch only that kind. A watch alert " +
                "during the wait leaves the choice to this, also with AutoTrack on. Tracking something else (by hand or Find " +
                "area), Stop tracking, turning this off, emptying the watchlist, dying or leaving the world ends the wait. " +
                "Stop tracking, or tracking something else yourself, never starts one. While on, the log has a line at each " +
                "loss of a tracked creature and at the end of each wait. " +
                "The window's 'Always track nearest watched' checkbox sets it.");

            // Two independent filters: browse every star level while being alerted only for, say, two-star creatures.
            ListStarsText = config.Bind("General", "ListStarFilter", "All",
                "Which star categories the creature list's nearby view shows: All, or one or more of NoStars, OneStar, " +
                "TwoStars and TwoOrMoreStars (two stars and above) separated by commas - 'NoStars, OneStar' shows " +
                "creatures with no star or one star. Names in any case; the window's labels (No star, 1 star, 2 stars, " +
                "2+ stars) work too, and so do category numbers: 0 = NoStars, 1 = OneStar, 2 = TwoStars, 3 = TwoOrMoreStars, " +
                "4 = All - a number here is a category, not a count of stars (exact counts go in ListStarCounts). All " +
                "anywhere in the list means All. A creature is shown when a category marked here or a count in " +
                "ListStarCounts lets it through; with no category marked and no count, every star level is. The window's " +
                "'List:' row sets it: a click on a category adds or removes it, a click on All resets the row, its counts " +
                "too. The all-types view is not filtered. Set back to All whenever you enter a world or go back to the main " +
                "menu, unless KeepBetweenSessions is on. Anything else is ignored with a warning in the log; with nothing " +
                "valid, no category is marked.");
            ListCountsText = config.Bind("General", "ListStarCounts", "",
                "Exact star counts the creature list's nearby view shows as well: whole numbers from 0 to 100, single or as " +
                "ranges, separated by commas - '3-5, 8' shows creatures with three, four, five or eight stars; 0 is no star, " +
                "as NoStars. A creature is shown when it has one of these counts or a category of ListStarFilter lets it " +
                "through; with no category marked, only these counts are shown, and with no count here either, every star " +
                "level is. Empty: no count. The field after " +
                "'Exactly:' in the window's 'List:' row sets it. A range written high to low reads as the same range. A " +
                "value that cannot be read - a number above 100, a range left open, a sign, a word - is not applied: the " +
                "counts read before it stay (none at the game's start). The field shows such text as invalid; a value set " +
                "in ConfigurationManager or in this file is also warned about in the log. A creature with more than 100 " +
                "stars has no count; TwoOrMoreStars takes it. Set back to empty whenever you enter a world or go back to the " +
                "main menu, unless KeepBetweenSessions is on.");
            AlertStarsText = config.Bind("Alerts", "AlertStarFilter", "All",
                "Which star categories of a watched creature type alert, and are auto-tracked or re-tracked: All, or one or " +
                "more of NoStars, OneStar, TwoStars and TwoOrMoreStars (two stars and above) separated by commas - " +
                "'OneStar, TwoStars' alerts only for one- and two-star creatures while AlertStarCounts holds no count. Names " +
                "in any case; the window's labels " +
                "(No star, 1 star, 2 stars, 2+ stars) work too, and so do category numbers: 0 = NoStars, 1 = OneStar, " +
                "2 = TwoStars, 3 = TwoOrMoreStars, 4 = All - a number here is a category, not a count of stars (exact counts " +
                "go in AlertStarCounts). All anywhere in the list means All. A creature passes when a category marked here " +
                "or a count in AlertStarCounts lets it through; with no category marked and no count, every star level " +
                "does. The window's 'Alerts:' row sets it: a click on a category adds or removes it, a click on All resets " +
                "the row, its counts too. A change made in the window or in ConfigurationManager - to this filter or to " +
                "AlertStarCounts - takes effect once the row has stayed the same for 1.5 seconds of game time, so what it " +
                "passes through while you click the row or type - a text with no word it knows yet marks no category - " +
                "never takes effect as long as each click or keystroke that changes the row comes within 1.5 seconds of " +
                "the one before. Set back to All whenever you enter a world or go back to the main menu, unless " +
                "KeepBetweenSessions is on. To edit it in this file with KeepBetweenSessions on, close the game first: " +
                "the file is read at the start, and while the game runs a setting changed in the window rewrites it. A " +
                "creature left out now can still alert later if the filter changes. Anything else is ignored with a " +
                "warning in the log; with nothing valid, no category is marked.");
            AlertCountsText = config.Bind("Alerts", "AlertStarCounts", "",
                "Exact star counts of a watched creature type that alert, and are auto-tracked or re-tracked, as well as " +
                "the categories of AlertStarFilter: whole numbers from 0 to 100, single or as ranges, separated by commas - " +
                "with no category marked, '3-5' alerts only for creatures with three to five stars; 0 is no star, as " +
                "NoStars. Empty: no count. The field after 'Exactly:' in the window's 'Alerts:' row sets it. A change " +
                "takes effect once the Alerts: row has stayed the same for 1.5 seconds of game time, as for " +
                "AlertStarFilter; a keystroke that leaves text the field cannot read yet still restarts that wait. A range " +
                "written high to low reads as the same range. A value that cannot be read - a number above 100, a range " +
                "left open, a sign, a word - is not applied: the counts read before it stay (none at the game's start). " +
                "The field shows such text as invalid; a value set in ConfigurationManager or in this file is also warned " +
                "about in the log. A creature with more than 100 stars has no count; TwoOrMoreStars takes it. Set back to " +
                "empty whenever you enter a world or go back to the main menu, unless KeepBetweenSessions is on. To edit " +
                "it in this file with KeepBetweenSessions on, close the game first: the file is read at the start, and " +
                "while the game runs a setting changed in the window rewrites it.");
            // Each row from its own two entries, now and whenever one of them changes (the window's rows, or
            // ConfigurationManager, which also raises SettingChanged); a change of one keeps the other's part as it is. The
            // list's never reads None; the alerts' only under AlertsChange.EmptyAlertsNothing, which is not the mode
            // MobTracker runs with (AlertsRow). Counts that cannot be read leave the counts in effect as they are
            // (ParseCounts). Each change of either alerts' text is counted after it is read (AlertStarsRevision).
            ListStars = new StarRule(ParseStars(ListStarsText, false), ParseCounts(ListCountsText, default(StarCounts)));
            AlertStars = new StarRule(ParseStars(AlertStarsText, AlertsRow.EmptyIsNothing(AlertsRow.AlertsChangeMode)),
                ParseCounts(AlertCountsText, default(StarCounts)));
            ListStarsText.SettingChanged += (sender, args) => ListStars = new StarRule(ParseStars(ListStarsText, false), ListStars.Counts);
            ListCountsText.SettingChanged += (sender, args) => ListStars = new StarRule(ListStars.Set, ParseCounts(ListCountsText, ListStars.Counts));
            AlertStarsText.SettingChanged += (sender, args) =>
            {
                AlertStars = new StarRule(ParseStars(AlertStarsText, AlertsRow.EmptyIsNothing(AlertsRow.AlertsChangeMode)), AlertStars.Counts);
                AlertRowChanged();
            };
            AlertCountsText.SettingChanged += (sender, args) =>
            {
                AlertStars = new StarRule(AlertStars.Set, ParseCounts(AlertCountsText, AlertStars.Counts));
                AlertRowChanged();
            };

            Watchlist = Rules.ParseWatchlist(WatchlistEntry.Value);
            WatchlistEntry.SettingChanged += (sender, args) => Watchlist = Rules.ParseWatchlist(WatchlistEntry.Value);

            // Every setting's change, for the verbose log; added last, so each setting's own handler above has run first.
            Events.Watch(config);
        }

        /// <summary>
        /// A star filter entry's set; what it could not read is said in the log, naming the setting. None is read only
        /// with <paramref name="allowNone"/>.
        /// </summary>
        private static StarSet ParseStars(ConfigEntry<string> entry, bool allowNone)
        {
            string problem;
            StarSet set = StarSets.Parse(entry.Value, out problem, allowNone);
            if (problem != null)
                MobTrackerPlugin.Log.LogWarning(entry.Definition.Section + "." + entry.Definition.Key + " is '" + entry.Value + "': " + problem);
            return set;
        }

        /// <summary>
        /// The Alerts: row changed - either of its two settings, or its field's text by a keystroke that wrote nothing -
        /// so the settler behind WatchAlerts.EffectiveAlertStars starts its wait over: the one place AlertStarsRevision is
        /// counted.
        /// </summary>
        public static void AlertRowChanged()
        {
            AlertStarsRevision++;
        }

        /// <summary>
        /// A count entry's counts. A text StarCounts cannot read is not applied: <paramref name="kept"/>, the counts read
        /// before it (none at the start), are returned, and the log says so, naming the setting and the entry it could not
        /// read. The window writes only text it can read, so this warns about a value from ConfigurationManager, another
        /// plugin or the file.
        /// </summary>
        private static StarCounts ParseCounts(ConfigEntry<string> entry, StarCounts kept)
        {
            StarCounts counts;
            string problem;
            if (StarCounts.TryParse(entry.Value, out counts, out problem))
                return counts;
            MobTrackerPlugin.Log.LogWarning(entry.Definition.Section + "." + entry.Definition.Key + " is '" + entry.Value + "': "
                                            + StarCounts.Problem(problem, kept));
            return kept;
        }

        /// <summary>
        /// A game session ended or began (GameSession). Unless KeepBetweenSessions is on, the watchlist, both star
        /// filters and both rows' counts go back to their defaults - nothing watched, All, no count - each written to its
        /// own entry, so the rows and the Alerts: row's revision follow as they do for any change (an entry already at its
        /// default is not written, nor counted). The log says what was set back, if anything.
        ///
        /// The cfg is saved once, after the five writes, not at each (ConfigSaver.Each); a save that fails is caught and
        /// said by ConfigSaver, and the next save that works writes the defaults.
        /// </summary>
        public static void ResetSession()
        {
            if (KeepBetweenSessions.Value)
                return;

            string held = Held(WatchlistEntry) + Held(ListStarsText) + Held(ListCountsText) + Held(AlertStarsText) + Held(AlertCountsText);
            if (held.Length == 0)
                return;

            bool saveEach = ConfigSaver.Each;
            ConfigSaver.Each = false;
            try
            {
                WatchlistEntry.Value = (string)WatchlistEntry.DefaultValue;
                ListStarsText.Value = (string)ListStarsText.DefaultValue;
                ListCountsText.Value = (string)ListCountsText.DefaultValue;
                AlertStarsText.Value = (string)AlertStarsText.DefaultValue;
                AlertCountsText.Value = (string)AlertCountsText.DefaultValue;
            }
            finally
            {
                ConfigSaver.Each = saveEach;
            }

            MobTrackerPlugin.Log.LogInfo("Game session changed and KeepBetweenSessions is off, so these are back to their defaults:" + held);
            ConfigSaver.Save("after the session reset");
        }

        /// <summary>" Section.Key was 'value'." for an entry away from its default, else "".</summary>
        private static string Held(ConfigEntry<string> entry)
        {
            if (entry.Value == (string)entry.DefaultValue)
                return "";
            return " " + entry.Definition.Section + "." + entry.Definition.Key + " was '" + entry.Value + "'.";
        }

        public static void ToggleWatch(string prefabName)
        {
            var set = new HashSet<string>(Watchlist, Watchlist.Comparer);
            if (!set.Remove(prefabName))
                set.Add(prefabName);

            WatchlistEntry.Value = Rules.FormatWatchlist(set);
        }
    }
}
