using System.Collections.Generic;
using BepInEx;
using BepInEx.Logging;
using HarmonyLib;
using UnityEngine;
using UnityEngine.EventSystems;

namespace MobTracker
{
    [BepInPlugin(PluginId, "MobTracker", Version)]
    public class MobTrackerPlugin : BaseUnityPlugin
    {
        public const string PluginId = "com.mobtracker.plugin";

        /// <summary>Also MobTracker.csproj's Version; tools/preflight.ps1 checks that the two agree.</summary>
        public const string Version = "0.8.0";

        internal static ManualLogSource Log;

        private Harmony _harmony;

        private void Awake()
        {
            Log = Logger;
            ConfigSaver.Take(Config); // before any setting is bound: BepInEx saves nothing from here on, ConfigSaver does
            LogFile.Start(Config, Paths.BepInExRootPath, Paths.GameRootPath); // first: ModConfig.Bind's own warnings go to MobTracker.log too
            ModConfig.Bind(Config);
            LogFile.Bound(Config);
            ConfigSaver.Watch(Config); // after the last setting is bound and its handlers: the cfg saved now, and at each change
            Ding.Init(gameObject);

            gameObject.AddComponent<EntityListWindow>();
            gameObject.AddComponent<Tracker>();
            gameObject.AddComponent<WatchAlerts>();
            gameObject.AddComponent<NearestWatched>();
            gameObject.AddComponent<SpawnFinder>();
            gameObject.AddComponent<GameSession>();
            gameObject.AddComponent<LogObserver>();

            // One class at a time: PatchAll stops at the first target a game update renamed, which would also take
            // down the patches that still fit. tools/preflight.ps1 checks that every patch class is listed here.
            _harmony = new Harmony(PluginId);
            Patch(typeof(TextInputVisiblePatch));
            Patch(typeof(ChatHasFocusPatch));
            Patch(typeof(MouseWheelPatch));
            Patch(typeof(RemoveAreaPinPatch));
            Patch(typeof(UiRaycastPatch));

            Log.LogInfo("MobTracker " + Version + " loaded");
        }

        /// <summary>
        /// TomTom's (or Wayfinder's) keys over the open list (WaypointerCompat). Here, not in Awake: BepInEx creates
        /// every plugin, in GUID order, before Unity calls any Start, and DoomMachine.* sorts after com.mobtracker.
        /// </summary>
        private void Start()
        {
            try
            {
                WaypointerCompat.Apply(_harmony);
            }
            catch (System.Exception e)
            {
                Log.LogError("TomTom and Wayfinder compatibility could not be set up: " + LogRules.Describe(e));
            }
        }

        private void Patch(System.Type patchClass)
        {
            try
            {
                _harmony.PatchAll(patchClass);
                Events.Patched(patchClass.Name);
            }
            catch (System.Exception e)
            {
                Log.LogError(patchClass.Name + " could not be applied, so that part of MobTracker is off: " + LogRules.Describe(e));
            }
        }

        private void OnDestroy()
        {
            ConfigSaver.Stop();
            _harmony?.UnpatchSelf();
            LogFile.Stop();
        }
    }

    /// <summary>
    /// The game already reads "a text input is up" as "free the cursor, stop player input, keep
    /// the pause menu shut" (GameCamera.UpdateMouseCapture, PlayerController.TakeInput,
    /// Menu.Update), which is exactly what the list window needs. Reported while the list is open and
    /// for the rest of the frame in which it closed, so the Escape that closed it cannot also open the
    /// pause menu (Menu.Update reads this flag, not Chat.HasFocus). Only ever adds true. Not while TomTom or
    /// Wayfinder asks whether the player is typing (WaypointerCompat): the list is not a text field their keys must
    /// give way to.
    /// </summary>
    [HarmonyPatch(typeof(TextInput), nameof(TextInput.IsVisible))]
    internal static class TextInputVisiblePatch
    {
        private static void Postfix(ref bool __result)
        {
            if (WaypointerCompat.SuspendDepth == 0)
                __result |= EntityListWindow.BlocksGameInput;
        }
    }

    /// <summary>
    /// The other half of the same signal (TomTom's, MapPatches.cs). InventoryGui.Update (Tab and gamepad Y),
    /// GameCamera.UpdateCamera (the camera zoom, by wheel and gamepad), HotkeyBar.Update (the gamepad hotbar),
    /// Player.UpdatePlacementGhost (Q and E cycling the build snap point), StoreGui.Update and TextInput.Update
    /// (E, Escape and B closing a trader or a sign's box) read Chat.HasFocus, not TextInput.IsVisible.
    /// Last, on the method: Chatter's postfix assigns __result outright at the default priority and loads after
    /// this plugin, so at equal priority it would run later and undo this. Only ever sets true. Stands aside inside
    /// TomTom's typing test, as the TextInput one does (WaypointerCompat).
    /// </summary>
    [HarmonyPatch(typeof(Chat), nameof(Chat.HasFocus))]
    internal static class ChatHasFocusPatch
    {
        [HarmonyPriority(Priority.Last)]
        private static void Postfix(ref bool __result)
        {
            if (WaypointerCompat.SuspendDepth == 0 && EntityListWindow.BlocksGameInput)
                __result = true;
        }
    }

    /// <summary>
    /// Keeps the mouse wheel from the game while the list is open - TomTom's patch for its own window. The camera zoom
    /// already stands still (GameCamera.UpdateCamera asks Chat.HasFocus, which ChatHasFocusPatch holds true), but
    /// ZInput's wheel has readers that ask neither flag: the free-fly debug camera and Server Devcommands' wheel binds.
    /// A postfix, not a prefix, so ZInput still runs its input-source switch. The list's own scroll view reads
    /// Event.current, not ZInput, so it still scrolls. Last, on the method, so other mods' postfixes see the real wheel
    /// first (MeasurementTracker records it). Only ever sets 0.
    /// </summary>
    [HarmonyPatch(typeof(ZInput), nameof(ZInput.GetMouseScrollWheel))]
    internal static class MouseWheelPatch
    {
        [HarmonyPriority(Priority.Last)]
        private static void Postfix(ref float __result)
        {
            if (EntityListWindow.BlocksGameInput)
                __result = 0f;
        }
    }

    /// <summary>
    /// The map's delete gesture - right click and the gamepad button end here, and so does a touch
    /// long-press while a saved pin shown on the map is in reach - removes the nearest SAVED pin shown
    /// on the map, and cannot see a Find area pin (save false). Left alone, a right click on an area
    /// pin would delete the player's own pin next to it. So an area pin within reach
    /// is removed instead, even when a pin of the player's is nearer: a deleted pin of theirs cannot be
    /// brought back, an area pin is one Find away.
    ///
    /// Low priority, so that a mod at the default priority with markers of its own (TomTom) has had
    /// its turn: HarmonyX runs every prefix, and a false from one of them arrives here as
    /// __runOriginal, meaning the gesture is taken - one click never removes two pins. The priority
    /// sits on the method: PatchAll(Type) ignores a [HarmonyPriority] on the class, and at the default
    /// priority this plugin's prefix would run first (BepInEx loads com.mobtracker before DoomMachine).
    /// </summary>
    [HarmonyPatch(typeof(Minimap), nameof(Minimap.RemovePin), new[] { typeof(Vector3), typeof(float) })]
    internal static class RemoveAreaPinPatch
    {
        [HarmonyPriority(Priority.Low)]
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

    /// <summary>
    /// Keeps clicks on the list off the game's own UI underneath. The list is IMGUI, which the game's uGUI cannot see,
    /// so without this a click on the list also lands on what is under it: on the large map a right click deletes a pin,
    /// a middle click pings every player and a double click leaves a saved pin a Cartography Table shares; the buttons
    /// of a trader or the map are pressed. Every uGUI pointer event - hover, press, click, drag start, drop, wheel -
    /// goes to what EventSystem.RaycastAll found under the pointer (the game's InputSystemUIInputModule,
    /// PerformRaycast), so finding nothing while the pointer is on the list stops them all.
    ///
    /// Left as it is: a press that began outside the list keeps its release and its drag, which the input module sends
    /// to what was pressed, not to what is under the pointer - a map drag that ends over the list ends; keyboard and
    /// gamepad navigation, which do not raycast; and the list's own controls, which IMGUI feeds from Event.current.
    /// The list handed in is the input module's own cache, so it is emptied, never replaced. Last, so it has the final
    /// word over any other postfix; the priority sits on the method, where PatchAll(Type) reads it.
    /// </summary>
    [HarmonyPatch(typeof(EventSystem), nameof(EventSystem.RaycastAll))]
    internal static class UiRaycastPatch
    {
        [HarmonyPriority(Priority.Last)]
        private static void Postfix(PointerEventData eventData, List<RaycastResult> raycastResults)
        {
            if (eventData != null && EntityListWindow.Covers(eventData.position))
                raycastResults.Clear();
        }
    }

    internal static class Creature
    {
        /// <summary>
        /// Everything loaded that is not a player. Dead and destroyed entries skipped, and so is a creature with no
        /// ZNetView: Character.Awake puts a creature on the game's list before the step that fails without one, so a
        /// broken one stays listed, and each of its network reads (GetZDOID, IsTamed) would throw - ending the alert
        /// poll, list refresh or re-track look it was met in. Tested before anything else is asked of the creature.
        /// </summary>
        public static bool IsListable(Character character)
        {
            return character != null && character.m_nview != null && !character.IsPlayer() && !character.IsDead();
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
