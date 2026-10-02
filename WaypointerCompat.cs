using System;
using System.Reflection;
using BepInEx;
using BepInEx.Bootstrap;
using HarmonyLib;

namespace MobTracker
{
    /// <summary>
    /// TomTom and Wayfinder (DoomMachine's waypoint plugins, built from one source) read their keys only while their
    /// Plugin.IsTypingElsewhere() is false, and that asks TextInput.IsVisible and Chat.HasFocus - the two flags the
    /// list forces true while it is open. Left alone, their window key (F11) and skip key would do nothing over the
    /// list. While that one method runs, SuspendDepth is above 0 and the list's two postfixes stand aside, so it sees
    /// the chat, a sign, the map's pin box and the console as they really are.
    ///
    /// Applied from MobTrackerPlugin.Start, not Awake: BepInEx creates the plugins in case-insensitive GUID order and
    /// loads each one's assembly only just before creating it (Chainloader.Start), so when com.mobtracker.plugin's
    /// Awake runs DoomMachine.TomTom's assembly is not loaded yet. Every plugin exists by the time Unity calls Start.
    /// </summary>
    internal static class WaypointerCompat
    {
        // The two editions declare each other incompatible, so at most one of them is loaded.
        private static readonly string[] Guids = { "DoomMachine.TomTom", "DoomMachine.Wayfinder" };

        /// <summary>Above 0 while TomTom's (or Wayfinder's) IsTypingElsewhere runs: the list's forced flags stand aside.</summary>
        internal static int SuspendDepth;

        internal static void Apply(Harmony harmony)
        {
            foreach (string guid in Guids)
            {
                PluginInfo info;
                if (!Chainloader.PluginInfos.TryGetValue(guid, out info) || info == null || info.Instance == null)
                {
                    Events.CompatSkipped(guid, info != null); // not installed, or installed but not loaded
                    continue;
                }
                ApplyTo(harmony, info.Instance.GetType(), info.Metadata.Name + " " + info.Metadata.Version);
            }
        }

        internal static bool ApplyTo(Harmony harmony, Type plugin, string who)
        {
            MethodInfo typing = plugin.GetMethod("IsTypingElsewhere", BindingFlags.Public | BindingFlags.Static, null, Type.EmptyTypes, null);
            if (typing == null || typing.ReturnType != typeof(bool))
            {
                MobTrackerPlugin.Log.LogWarning(who + " has no 'public static bool IsTypingElsewhere()' any more, so its keys stay off while the MobTracker list is open.");
                return false;
            }

            try
            {
                harmony.Patch(typing,
                    prefix: new HarmonyMethod(typeof(WaypointerCompat), nameof(Prefix)),
                    finalizer: new HarmonyMethod(typeof(WaypointerCompat), nameof(Finalizer)));
            }
            catch (Exception e)
            {
                MobTrackerPlugin.Log.LogError("Could not patch " + who + "'s IsTypingElsewhere, so its keys stay off while the MobTracker list is open: " + LogRules.Describe(e));
                return false;
            }

            MobTrackerPlugin.Log.LogInfo(who + " found: its keys work while the MobTracker list is open.");
            return true;
        }

        private static void Prefix()
        {
            SuspendDepth++;
        }

        // A void finalizer: it runs however the method ends and lets an exception through unchanged (HarmonyX 2.9).
        private static void Finalizer()
        {
            if (SuspendDepth > 0)
                SuspendDepth--;
        }
    }
}
