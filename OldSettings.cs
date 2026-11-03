using System;
using System.Collections.Generic;
using System.IO;
using BepInEx;
using BepInEx.Configuration;

namespace MobTracker
{
    /// <summary>
    /// The settings file of MobTracker 0.8.0 and earlier (0.9.0, OI-7; D-006, D-011 and D-015 in the repository's
    /// decisions/). BepInEx names a plugin's cfg after its id, and up to 0.8.0 the id was com.mobtracker.plugin, so those
    /// settings are in com.mobtracker.plugin.cfg, which this id never reads. BepInEx reads the cfg in the plugin's
    /// constructor, before Awake; at a start that found no DoomMachine.MobTracker.cfg and finds com.mobtracker.plugin.cfg
    /// beside it, Copy - in Awake, after ConfigSaver.Take and before the first setting is bound - copies the older file
    /// to the new name, never over a file, and has BepInEx read the copy (ConfigFile.Reload, which before any Bind changes
    /// no setting and writes nothing). The older file is left as it was; there is no copy-once marker, so a later start
    /// that again finds no DoomMachine.MobTracker.cfg copies it again. Report says once, after LogFile.Start, what Copy
    /// did. OlderVersion finds an older MobTracker loaded beside this one. Nothing here may stop MobTracker loading: every
    /// failure is caught and said by its type only (an IOException's message holds the full path). Free of game types,
    /// so tools\log-harness compiles this file as it is.
    /// </summary>
    internal static class OldSettings
    {
        /// <summary>The plugin id of 0.8.0 and earlier; its settings file is this id with ".cfg".</summary>
        public const string OldId = "com.mobtracker.plugin";

        private static string _line;   // the line Copy leaves for Report; null when there is nothing to say
        private static bool _warning;

        /// <summary>
        /// In Awake, before any setting is bound: copies com.mobtracker.plugin.cfg to <paramref name="config"/>'s file
        /// when that does not exist and the older one does, then reads the copy into <paramref name="config"/>.
        /// </summary>
        public static void Copy(ConfigFile config)
        {
            _line = null;
            _warning = false;
            try
            {
                string target = config.ConfigFilePath;
                string old = Path.Combine(Path.GetDirectoryName(target), OldId + ".cfg");
                if (File.Exists(target) || !File.Exists(old))
                    return;
                File.Copy(old, target, false);
                // File.Copy gives the copy the older file's attributes, read-only too (.NET Framework 4.8 and the game's
                // Mono): the copy must take MobTracker's saves, so it is made writable. The older file keeps its own.
                FileAttributes attributes = File.GetAttributes(target);
                if ((attributes & FileAttributes.ReadOnly) != 0)
                    File.SetAttributes(target, attributes & ~FileAttributes.ReadOnly);
            }
            catch (Exception e)
            {
                _warning = true;
                _line = EventLines.SettingsNotCopied(e.GetType().Name);
                return;
            }
            try
            {
                config.Reload();
                _line = EventLines.SettingsCopied();
            }
            catch (Exception e)
            {
                _warning = true;
                _line = EventLines.SettingsNotAllRead(e.GetType().Name);
            }
        }

        /// <summary>In Awake, right after LogFile.Start: what Copy did, once - nothing when it had nothing to do.</summary>
        public static void Report()
        {
            string line = _line;
            if (line == null)
                return;
            _line = null;
            if (_warning)
                MobTrackerPlugin.Log.LogWarning(line);
            else
                MobTrackerPlugin.Log.LogInfo(line);
        }

        /// <summary>
        /// The version of an older MobTracker - the plugin id of 0.8.0 and earlier - loaded beside this one, or null.
        /// <paramref name="loaded"/> is Chainloader.PluginInfos: BepInEx creates the plugins in case-insensitive id order
        /// and enters each in it before creating it, so com.mobtracker.plugin is in it before this one's Awake. Seen at all
        /// only because this assembly is named DoomMachine.MobTracker (MobTracker.csproj): with the older copy's assembly
        /// name, Unity would make the older copy's classes in this one's place. Never throws.
        /// </summary>
        public static string OlderVersion(IDictionary<string, PluginInfo> loaded)
        {
            try
            {
                PluginInfo older;
                if (loaded == null || !loaded.TryGetValue(OldId, out older) || older == null)
                    return null;
                return older.Metadata != null && older.Metadata.Version != null ? older.Metadata.Version.ToString() : "version unknown";
            }
            catch (Exception)
            {
                return null;
            }
        }
    }
}
