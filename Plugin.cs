using BepInEx;
using BepInEx.Logging;
using HarmonyLib;
using UnityEngine;

namespace MobTracker
{
    [BepInPlugin(PluginId, "MobTracker", Version)]
    public class MobTrackerPlugin : BaseUnityPlugin
    {
        public const string PluginId = "com.mobtracker.plugin";

        /// <summary>Also MobTracker.csproj's Version; tools/preflight.ps1 checks that the two agree.</summary>
        public const string Version = "0.2.0";

        internal static ManualLogSource Log;

        private Harmony _harmony;

        private void Awake()
        {
            Log = Logger;
            ModConfig.Bind(Config);
            Ding.Init(gameObject);

            gameObject.AddComponent<EntityListWindow>();
            gameObject.AddComponent<Tracker>();
            gameObject.AddComponent<WatchAlerts>();
            gameObject.AddComponent<SpawnFinder>();

            // One class at a time: PatchAll stops at the first target a game update renamed, which would also take
            // down the patches that still fit. tools/preflight.ps1 checks that every patch class is listed here.
            _harmony = new Harmony(PluginId);
            Patch(typeof(TextInputVisiblePatch));
            Patch(typeof(RemoveAreaPinPatch));

            Log.LogInfo("MobTracker " + Version + " loaded");
        }

        private void Patch(System.Type patchClass)
        {
            try
            {
                _harmony.PatchAll(patchClass);
            }
            catch (System.Exception e)
            {
                Log.LogError(patchClass.Name + " could not be applied, so that part of MobTracker is off: " + e.Message);
            }
        }

        private void OnDestroy()
        {
            _harmony?.UnpatchSelf();
        }
    }

    /// <summary>
    /// The game already reads "a text input is up" as "free the cursor, stop player input, keep
    /// the pause menu shut" (GameCamera.UpdateMouseCapture, PlayerController.TakeInput,
    /// Menu.Update), which is exactly what the list window needs.
    /// </summary>
    [HarmonyPatch(typeof(TextInput), nameof(TextInput.IsVisible))]
    internal static class TextInputVisiblePatch
    {
        private static void Postfix(ref bool __result)
        {
            __result |= EntityListWindow.IsOpen;
        }
    }

    /// <summary>
    /// The map's delete gesture - right click, touch long-press and the gamepad button all end here -
    /// removes the nearest SAVED pin, and cannot see a Find area pin (save false). Left alone, a right
    /// click on an area pin would delete the player's own pin next to it. So an area pin within reach
    /// is removed instead, even when a pin of the player's is nearer: a deleted pin of theirs cannot be
    /// brought back, an area pin is one Find away.
    ///
    /// Low priority, so that a mod at the default priority with markers of its own (TomTom) has had
    /// its turn: HarmonyX runs every prefix, and a false from one of them arrives here as
    /// __runOriginal, meaning the gesture is taken - one click never removes two pins.
    /// </summary>
    [HarmonyPatch(typeof(Minimap), nameof(Minimap.RemovePin), new[] { typeof(Vector3), typeof(float) })]
    [HarmonyPriority(Priority.Low)]
    internal static class RemoveAreaPinPatch
    {
        private static bool Prefix(Minimap __instance, Vector3 pos, float radius, ref bool __result, bool __runOriginal)
        {
            if (!__runOriginal)
                return false;

            if (!SpawnFinder.RemovePinNear(__instance, pos, radius))
                return true;

            __result = true;
            return false;
        }
    }

    internal static class Creature
    {
        /// <summary>Everything loaded that is not a player. Dead and destroyed entries skipped.</summary>
        public static bool IsListable(Character character)
        {
            return character != null && !character.IsPlayer() && !character.IsDead();
        }

        public static string PrefabName(Character character)
        {
            return Utils.GetPrefabName(character.gameObject);
        }

        /// <summary>"Greydwarf **" - asterisks, because neither the IMGUI font nor the HUD font is sure to have a star glyph.</summary>
        public static string DisplayName(Character character)
        {
            string name = string.IsNullOrEmpty(character.m_name) || Localization.instance == null
                ? PrefabName(character)
                : Localization.instance.Localize(character.m_name);

            int level = character.GetLevel();
            return level > 1 ? name + " " + new string('*', level - 1) : name;
        }
    }
}
