using System;
using BepInEx.Configuration;

namespace MobTracker
{
    /// <summary>
    /// Saves com.mobtracker.plugin.cfg (0.7.1); BepInEx no longer does. BepInEx saves a changed setting before it tells
    /// anyone of the change, and nothing catches a save that throws - the file read-only, or held by another program: the
    /// setting kept its new value, but no change handler ran (the parsed watchlist and star filters, the verbose flag, the
    /// refused keys stayed as they were), and the exception left the window's click, ConfigurationManager's control or -
    /// at the game's start - Awake, so MobTracker did not load. So the cfg's SaveOnConfigSet is off from before the first
    /// setting is bound, for the plugin's whole life (BepInEx reads it only in that ConfigFile's Bind and change event),
    /// and the file is saved here instead: once when every setting is bound, then after each change - whoever makes it:
    /// the window, ConfigurationManager, another plugin - by a handler on the whole cfg added last of MobTracker's, so the
    /// setting's own handlers and the verbose log's have run. A save that fails is caught and said once, as a warning,
    /// until a save works again, which is said too; the change takes effect either way, and the next save that works
    /// writes every value. Free of game types, so tools\log-harness compiles this file as it is.
    /// </summary>
    internal static class ConfigSaver
    {
        private static ConfigFile _file;
        private static bool _failing;

        /// <summary>
        /// Whether a change is saved as it happens: ModConfig.ResetSession sets it false while it writes its three
        /// settings, and saves once after them.
        /// </summary>
        public static bool Each = true;

        /// <summary>First in MobTrackerPlugin.Awake, before any setting is bound: BepInEx saves nothing from now on.</summary>
        public static void Take(ConfigFile file)
        {
            _file = file;
            file.SaveOnConfigSet = false;
        }

        /// <summary>
        /// In Awake, once every setting is bound (LogFile.Start, ModConfig.Bind): each change from now on is saved, and the
        /// file is saved now - a missing one made, new settings, descriptions and values moved into their range written,
        /// as BepInEx's own saves at each Bind did. Added after Events.Watch: MobTracker's last handler on the cfg.
        /// </summary>
        public static void Watch(ConfigFile file)
        {
            file.SettingChanged += SettingChanged;
            Save("at the game's start");
        }

        private static void SettingChanged(object sender, SettingChangedEventArgs args)
        {
            if (Each)
                Save("after a change");
        }

        /// <summary>The game quits (MobTrackerPlugin.OnDestroy): changes no save could write get one more try.</summary>
        public static void Stop()
        {
            if (_failing)
                Save("as the game quits");
        }

        /// <summary>
        /// Saves the file, catching any failure: the first is said, by the exception's type only (an IOException's message
        /// holds the file's full path), and then nothing more until a save works again, which is said.
        /// </summary>
        public static void Save(string when)
        {
            try
            {
                _file.Save();
            }
            catch (Exception e)
            {
                if (!_failing)
                {
                    _failing = true;
                    MobTrackerPlugin.Log.LogWarning(EventLines.CfgNotSaved(when, e.GetType().Name));
                }
                return;
            }
            if (_failing)
            {
                _failing = false;
                MobTrackerPlugin.Log.LogInfo(EventLines.CfgSavedAgain(when));
            }
        }
    }
}
