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

        /// <summary>Parsed view of <see cref="WatchlistEntry"/>; rebuilt whenever the entry changes.</summary>
        public static HashSet<string> Watchlist { get; private set; }

        public static void Bind(ConfigFile config)
        {
            ListKey = config.Bind("General", "ListKey", KeyCode.F7, "Opens and closes the creature list.");

            Guide = config.Bind("Tracking", "GuideMode", GuideMode.Arrow,
                "Arrow: a 3D arrow above your head pointing at the target. " +
                "GroundPath: a walkable line on the ground; the arrow also shows while no full path exists.");
            ArrowSize = config.Bind("Tracking", "ArrowSize", 0.6f, "Arrow length in metres.");
            ArrowHeight = config.Bind("Tracking", "ArrowHeight", 2.6f, "Arrow height above the player's feet, in metres.");

            WatchlistEntry = config.Bind("Alerts", "Watchlist", "",
                "Comma-separated creature prefab names to alert on, e.g. Troll,Serpent. " +
                "The Watch button in the list edits this; edit by hand to watch something not currently around.");
            AlertRadius = config.Bind("Alerts", "AlertRadius", 0f,
                "Only alert within this many metres. 0 = as soon as the creature exists on your client.");
            AlertVolume = config.Bind("Alerts", "AlertVolume", 0.8f,
                new ConfigDescription("Ding volume.", new AcceptableValueRange<float>(0f, 1f)));

            AutoTrack = config.Bind("Alerts", "AutoTrack", true,
                "Start tracking a watched creature the moment it alerts. Never replaces a creature you are already tracking.");

            Watchlist = Rules.ParseWatchlist(WatchlistEntry.Value);
            WatchlistEntry.SettingChanged += (sender, args) => Watchlist = Rules.ParseWatchlist(WatchlistEntry.Value);
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
