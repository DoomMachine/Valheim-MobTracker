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
        public static ConfigEntry<StarFilter> ListStars;
        public static ConfigEntry<StarFilter> AlertStars;

        /// <summary>Parsed view of <see cref="WatchlistEntry"/>; rebuilt whenever the entry changes.</summary>
        public static HashSet<string> Watchlist { get; private set; }

        public static void Bind(ConfigFile config)
        {
            ListKey = config.Bind("General", "ListKey", KeyCode.F7,
                "Opens and closes the creature list; Escape or the gamepad's B also close it. It does not open the list while " +
                "you type in chat, a sign or a map pin's name, while the console is open, or over the pause menu, the build " +
                "menu or the inventory. A key that types (a letter, a digit...) does not close the list while its search box " +
                "has the keyboard. A key the game cannot read (WheelUp, F13, Plus...) and the left, right and middle mouse " +
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
                "seconds, then track the nearest creature of that type that AlertStarFilter accepts, within AlertRadius, on " +
                "your side of a dungeon entrance and never a tamed one, looking again once a second until there is one. A watch alert that names that type leaves the " +
                "choice to this. Tracking something else (by hand, Find area, or AutoTrack on an alert for another watched " +
                "type), Stop tracking, turning this off, taking the type off the watchlist or dying ends the wait. Losing a " +
                "tamed creature, or stopping the tracking yourself, never starts one. The window's 'Always track nearest " +
                "watched' checkbox sets it.");

            // Two independent filters: browse every star level while being alerted only for, say, two-star creatures.
            ListStars = config.Bind("General", "ListStarFilter", StarFilter.All,
                "Which star levels the creature list's nearby view shows: All, NoStars, OneStar, TwoStars, or TwoOrMoreStars " +
                "(two stars and above). The window's 'List:' row sets it; the all-types view is not filtered. " +
                "A number typed here counts stars: 0 = NoStars, 1 = OneStar, 2 = TwoStars, 3 = TwoOrMoreStars, 4 = All.");
            AlertStars = config.Bind("Alerts", "AlertStarFilter", StarFilter.All,
                "Which star levels of a watched creature type alert, and are auto-tracked or re-tracked: All, NoStars, " +
                "OneStar, TwoStars, or TwoOrMoreStars (two stars and above). The window's 'Alerts:' row sets it. A creature " +
                "left out now can still alert later if the filter changes. A number typed here counts stars: 0 = NoStars, " +
                "1 = OneStar, 2 = TwoStars, 3 = TwoOrMoreStars, 4 = All.");
            WarnIfUnknown(ListStars);
            WarnIfUnknown(AlertStars);
            ListStars.SettingChanged += (sender, args) => WarnIfUnknown(ListStars);
            AlertStars.SettingChanged += (sender, args) => WarnIfUnknown(AlertStars);

            Watchlist = Rules.ParseWatchlist(WatchlistEntry.Value);
            WatchlistEntry.SettingChanged += (sender, args) => Watchlist = Rules.ParseWatchlist(WatchlistEntry.Value);
        }

        /// <summary>
        /// BepInEx parses an enum leniently: a number is the member with that value (StarFilter is numbered by star
        /// count, so "2" is TwoStars), and "OneStar, TwoStars" is the two ORed together. Anything that lands outside
        /// the five members works as All; say so once, in the log.
        /// </summary>
        private static void WarnIfUnknown(ConfigEntry<StarFilter> entry)
        {
            if (!StarFilters.IsDefined(entry.Value))
                MobTrackerPlugin.Log.LogWarning(entry.Definition.Key + " is set to " + (int)entry.Value +
                    ", which is not one of NoStars (0), OneStar (1), TwoStars (2), TwoOrMoreStars (3), All (4); it works as All.");
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
