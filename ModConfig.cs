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

        // Parsed views of the two texts, re-parsed whenever an entry changes; tools\preflight.ps1 checks who reads and
        // writes each of them. The window's rows show them as they are; the alerts, Auto-track and Always track nearest
        // watched use AlertStars only through WatchAlerts.EffectiveAlertStars, which follows it once it holds still.
        public static StarSet ListStars;
        public static StarSet AlertStars;

        // How many times AlertStarsText has changed since the start: the settler behind EffectiveAlertStars restarts its
        // wait at every change of the text, also one that leaves AlertStars as it was (ConfigurationManager writes the
        // setting at each keystroke, and a word typed so far reads as All until it is one Parse knows).
        public static int AlertStarsRevision;

        /// <summary>Parsed view of <see cref="WatchlistEntry"/>; rebuilt whenever the entry changes.</summary>
        public static HashSet<string> Watchlist { get; private set; }

        public static void Bind(ConfigFile config)
        {
            ListKey = config.Bind("General", "ListKey", KeyCode.F7,
                "Opens and closes the creature list; Escape or the gamepad's B also close it. It does not open the list while " +
                "you type in chat, a sign or a map pin's name, while the console is open, or over the pause menu, the build " +
                "menu, the inventory or the Barber Station. A key that types (a letter, a digit...) does not close the list " +
                "while its search box has the keyboard. A key the game cannot read (WheelUp, F13, Plus...) and the left, right and middle mouse " +
                "buttons do nothing, and the log says so once; keys the game ignores outright - Mouse5, Mouse6, F16 to F24 " +
                "and the numbered-joystick buttons - never fire, with no warning.");
            // A new key is tried afresh, and warned about again if it cannot be used either.
            ListKey.SettingChanged += (sender, args) => Hotkeys.Forget();

            Guide = config.Bind("Tracking", "GuideMode", GuideMode.Arrow,
                "Arrow: a 3D arrow above your head pointing at the target. " +
                "GroundPath: a line along the walkable ground to a target up to 250 m away. The arrow shows instead beyond " +
                "250 m, and as well while the line is missing or ends 5 m or more (measured on the flat) short of the " +
                "target: still being built, a flying or swimming target, a cliff.");
            ArrowSize = config.Bind("Tracking", "ArrowSize", 0.6f, "Arrow length in metres.");
            ArrowHeight = config.Bind("Tracking", "ArrowHeight", 2.6f, "Arrow height above the player's feet, in metres.");

            WatchlistEntry = config.Bind("Alerts", "Watchlist", "",
                "Comma-separated creature prefab names to alert on, e.g. Troll,Serpent. The window's Watch buttons edit " +
                "this, also for a creature not around (the 'View: all types' list). To edit it by hand, close the game " +
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
                "nor the choice AlwaysTrackNearestWatched is waiting to make for that type, nor takes a creature on the other " +
                "side of a dungeon entrance (its alert still shows).");
            AlwaysTrackNearest = config.Bind("Alerts", "AlwaysTrackNearestWatched", false,
                "When a tracked creature of a watched type is lost - killed, or no longer loaded on your client - wait 5 " +
                "seconds, then track the nearest creature of that type that AlertStarFilter accepts (as the alerts use it), " +
                "within AlertRadius, on " +
                "your side of a dungeon entrance and never a tamed one, looking again once a second until there is one. A watch alert that names that type leaves the " +
                "choice to this. Tracking something else (by hand, Find area, or AutoTrack on an alert for another watched " +
                "type), Stop tracking, turning this off, taking the type off the watchlist or dying ends the wait. Losing a " +
                "tamed creature, or stopping the tracking yourself, never starts one. The window's 'Always track nearest " +
                "watched' checkbox sets it.");

            // Two independent filters: browse every star level while being alerted only for, say, two-star creatures.
            ListStarsText = config.Bind("General", "ListStarFilter", "All",
                "Which star levels the creature list's nearby view shows: All, or one or more of NoStars, OneStar, " +
                "TwoStars and TwoOrMoreStars (two stars and above) separated by commas - 'NoStars, OneStar' shows " +
                "creatures with no star or one star. Names in any case; the window's labels (No star, 1 star, 2 stars, " +
                "2+ stars) work too, and a number counts stars: 0 = NoStars, 1 = OneStar, 2 = TwoStars, 3 = TwoOrMoreStars, " +
                "4 = All. All anywhere in the list means All. The window's 'List:' row sets it: a click on a category " +
                "adds or removes it, a click on All resets. The all-types view is not filtered. Anything else is " +
                "ignored with a warning in the log; with nothing valid, it works as All.");
            AlertStarsText = config.Bind("Alerts", "AlertStarFilter", "All",
                "Which star levels of a watched creature type alert, and are auto-tracked or re-tracked: All, or one or " +
                "more of NoStars, OneStar, TwoStars and TwoOrMoreStars (two stars and above) separated by commas - " +
                "'OneStar, TwoStars' alerts only for one- and two-star creatures. Names in any case; the window's labels " +
                "(No star, 1 star, 2 stars, 2+ stars) work too, and a number counts stars: 0 = NoStars, 1 = OneStar, " +
                "2 = TwoStars, 3 = TwoOrMoreStars, 4 = All. All anywhere in the list means All. The window's 'Alerts:' " +
                "row sets it: a click on a category adds or removes it, a click on All resets. A change made in the " +
                "window or in ConfigurationManager takes effect once the filter has stayed the same for 1.5 seconds of " +
                "game time, so what it passes through while you click the row or type in ConfigurationManager - a text " +
                "with no word it knows yet reads as All - never takes effect as long as each click or keystroke comes " +
                "within 1.5 seconds of the one before. To edit it in this file, close the game first: the file is read " +
                "at the start, and while the game runs a setting changed in the window rewrites it. A creature left out now can " +
                "still alert later if the filter changes. Anything else is ignored with a warning in the log; with " +
                "nothing valid, it works as All.");
            // Each parsed view from its own entry, now and whenever that entry changes (the window's rows, or
            // ConfigurationManager, which also raises SettingChanged). The list's never reads None; the alerts' only
            // under AlertsChange.EmptyAlertsNothing, which is not the mode MobTracker runs with (AlertsRow). Each change
            // of the alerts' text is counted after it is parsed (AlertStarsRevision).
            ListStars = ParseStars(ListStarsText, false);
            AlertStars = ParseStars(AlertStarsText, AlertsRow.EmptyIsNothing(AlertsRow.AlertsChangeMode));
            ListStarsText.SettingChanged += (sender, args) => ListStars = ParseStars(ListStarsText, false);
            AlertStarsText.SettingChanged += (sender, args) =>
            {
                AlertStars = ParseStars(AlertStarsText, AlertsRow.EmptyIsNothing(AlertsRow.AlertsChangeMode));
                AlertStarsRevision++;
            };

            Watchlist = Rules.ParseWatchlist(WatchlistEntry.Value);
            WatchlistEntry.SettingChanged += (sender, args) => Watchlist = Rules.ParseWatchlist(WatchlistEntry.Value);
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

        public static void ToggleWatch(string prefabName)
        {
            var set = new HashSet<string>(Watchlist, Watchlist.Comparer);
            if (!set.Remove(prefabName))
                set.Add(prefabName);

            WatchlistEntry.Value = Rules.FormatWatchlist(set);
        }
    }
}
