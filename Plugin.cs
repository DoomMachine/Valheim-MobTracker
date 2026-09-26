using BepInEx;
using BepInEx.Logging;
using HarmonyLib;

namespace MobTracker
{
    [BepInPlugin(PluginId, "MobTracker", "0.1.0")]
    public class MobTrackerPlugin : BaseUnityPlugin
    {
        public const string PluginId = "com.mobtracker.plugin";

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

            _harmony = new Harmony(PluginId);
            _harmony.PatchAll();

            Log.LogInfo("MobTracker 0.1.0 loaded");
        }

        private void OnDestroy()
        {
            _harmony?.UnpatchSelf();
        }
    }

    /// <summary>
    /// The plugin's only patch. The game already reads "a text input is up" as "free the cursor,
    /// stop player input, keep the pause menu shut" (GameCamera.UpdateMouseCapture,
    /// PlayerController.TakeInput, Menu.Update), which is exactly what the list window needs.
    /// </summary>
    [HarmonyPatch(typeof(TextInput), nameof(TextInput.IsVisible))]
    internal static class TextInputVisiblePatch
    {
        private static void Postfix(ref bool __result)
        {
            __result |= EntityListWindow.IsOpen;
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
