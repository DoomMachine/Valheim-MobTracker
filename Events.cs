using System;
using System.Collections.Generic;
using BepInEx.Configuration;
using UnityEngine;

namespace MobTracker
{
    /// <summary>
    /// The verbose log's sites. Each method returns at once with VerboseLog off, so a caller only hands over what it
    /// already holds (a creature, a distance, a count) and nothing is read or put together. With it on, each gathers the
    /// rest itself and writes the line EventLines words - inside a catch of its own, so a verbose line can never stop
    /// what it describes (a failure is said once per method: Failed). Callers pass plain locals and fields only:
    /// tools\preflight.ps1 traces the arguments of the calls round them.
    /// </summary>
    internal static class Events
    {
        private static ConfigFile Config;

        private static readonly Dictionary<string, string> Values = new Dictionary<string, string>();
        private static readonly SettingSettler Settler = new SettingSettler();
        private static readonly HashSet<string> FailedOnce = new HashSet<string>();
        private static readonly HashSet<int> ToldNotAlerting = new HashSet<int>();
        private static int _alertGeneration;
        private static string _lastEmptyLook;

        /// <summary>A verbose line that could not be put together: said once per site, as a warning; the event itself went on.</summary>
        private static void Failed(string where, Exception e)
        {
            if (FailedOnce.Add(where))
                MobTrackerPlugin.Log.LogWarning(EventLines.VerboseFailed(e.GetType().Name, where));
        }

        // ---- Track (Tracker) ----

        public static void TrackStarting(Character character)
        {
            if (!ModLog.Verbose)
                return;
            try
            {
                if (character == null)
                    return;
                Player player = Player.m_localPlayer;
                float distance = player != null ? Vector3.Distance(player.transform.position, character.transform.position) : -1f;
                ModLog.Event(EventLines.TrackStarted(Creature.DisplayName(character), Creature.PrefabName(character), character.GetLevel(),
                    distance, character.IsTamed(), character.InInterior(), Tracker.Tracked));
            }
            catch (Exception e) { Failed("Track", e); }
        }

        public static void TrackStartingArea(Vector3 point, string name)
        {
            if (!ModLog.Verbose)
                return;
            try
            {
                Player player = Player.m_localPlayer;
                float distance = player != null ? Utils.DistanceXZ(player.transform.position, point) : -1f;
                ModLog.Event(EventLines.TrackStartedArea(name, distance, Tracker.Tracked));
            }
            catch (Exception e) { Failed("TrackPoint", e); }
        }

        public static void TrackStopping()
        {
            if (!ModLog.Verbose)
                return;
            try
            {
                if (Tracker.IsTracking)
                    ModLog.Event(EventLines.TrackStopped(Tracker.Tracked, Tracker.TrackedSeconds));
            }
            catch (Exception e) { Failed("Stop", e); }
        }

        /// <summary>
        /// Tracker.LateUpdate, every frame, before its own tests: says why the tracking is about to end - no player, or the
        /// creature lost (the same test as the lost block's, which preflight holds to its exact shape).
        /// </summary>
        public static void TrackEnding(Player player)
        {
            if (!ModLog.Verbose)
                return;
            try
            {
                if (!Tracker.IsTracking)
                    return;
                if (player == null)
                {
                    ModLog.Event(EventLines.TrackNoPlayer(Tracker.Tracked));
                    return;
                }
                if (!Tracker.IsTrackingCreature)
                    return;
                Character target = Tracker.Target;
                if (target == null || target.IsDead())
                {
                    _lastEmptyLook = null; // a wait may begin: its first empty look is written
                    ModLog.Event(EventLines.TrackLost(Tracker.Tracked, target != null, Tracker.TargetTamed, ModConfig.AlwaysTrackNearest.Value));
                }
            }
            catch (Exception e) { Failed("LateUpdate", e); }
        }

        public static void TrackReached()
        {
            if (!ModLog.Verbose)
                return;
            try { ModLog.Event(EventLines.TrackReached(Tracker.Tracked)); }
            catch (Exception e) { Failed("Reached", e); }
        }

        public static void GroundPath(int state, int points, float shortBy)
        {
            if (!ModLog.Verbose)
                return;
            try { ModLog.Event(EventLines.GroundPath(state, points, shortBy)); }
            catch (Exception e) { Failed("UpdatePath", e); }
        }

        /// <summary>LogObserver: the guide was hidden or shown again; the reasons are read now.</summary>
        public static void Guide(bool hidden)
        {
            if (!ModLog.Verbose)
                return;
            try
            {
                Player player = Player.m_localPlayer;
                if (!hidden || player == null)
                {
                    ModLog.Event(EventLines.Guide(hidden, false, false, false, false, false));
                    return;
                }
                bool cutscene;
                try { cutscene = player.InCutscene(); }
                catch (Exception) { cutscene = false; }
                Game game = Game.instance;
                ModLog.Event(EventLines.Guide(true, Hud.IsUserHidden(), cutscene, player.IsDead(), game != null && game.WaitingForRespawn(),
                    player.IsTeleporting()));
            }
            catch (Exception e) { Failed("Guide", e); }
        }

        public static void Tamed()
        {
            if (!ModLog.Verbose)
                return;
            try { ModLog.Event(EventLines.TrackTamed(Tracker.Tracked)); }
            catch (Exception e) { Failed("Tamed", e); }
        }

        // ---- Alerts (WatchAlerts, Ding) ----

        /// <summary>WatchAlerts, no local player: the alert memory is about to be cleared (said only when it held some).</summary>
        public static void AlertMemoryClearing(int creatures)
        {
            if (!ModLog.Verbose)
                return;
            try
            {
                ToldNotAlerting.Clear();
                if (creatures > 0)
                    ModLog.Event(EventLines.AlertMemoryCleared(creatures));
            }
            catch (Exception e) { Failed("AlertMemory", e); }
        }

        public static void Alert(Character nearest, float distance, int count)
        {
            if (!ModLog.Verbose)
                return;
            try
            {
                _alertGeneration = Tracker.Generation;
                ModLog.Event(EventLines.Alert(Creature.DisplayName(nearest), Creature.PrefabName(nearest), nearest.GetLevel(), distance, count));
            }
            catch (Exception e) { Failed("Alert", e); }
        }

        /// <summary>
        /// After Auto-track's test: whether it took the creature Alert named, and if not, why - read after the fact from
        /// what it leaves behind; EventLines.AutoTrackOutcome decides.
        /// </summary>
        public static void AutoTrack(Character nearest)
        {
            if (!ModLog.Verbose)
                return;
            try
            {
                int outcome = EventLines.AutoTrackOutcome(Tracker.Generation, _alertGeneration, Tracker.IsTrackingCreature, Tracker.Target == nearest,
                    ModConfig.AutoTrack.Value, NearestWatched.IsPending);
                ModLog.Event(EventLines.AutoTrack(outcome, Tracker.Tracked));
            }
            catch (Exception e) { Failed("AutoTrack", e); }
        }

        /// <summary>
        /// WatchAlerts.Update, once a second after the poll: each creature of a watched type that does not alert - and has
        /// not had its alert - with the first reason that holds, once per creature until the alert memory clears.
        /// </summary>
        public static void NotAlerting(AlertGate<ZDOID> gate, Vector3 from)
        {
            if (!ModLog.Verbose)
                return;
            try
            {
                NotAlertingEach(gate, from);
            }
            catch (Exception e) { Failed("NotAlerting", e); }
        }

        private static void NotAlertingEach(AlertGate<ZDOID> gate, Vector3 from)
        {
            foreach (Character character in Character.GetAllCharacters())
            {
                try
                {
                    if (!Creature.IsListable(character) || ToldNotAlerting.Contains(character.GetInstanceID()))
                        continue;
                    string prefab = Creature.PrefabName(character);
                    if (!ModConfig.Watchlist.Contains(prefab))
                        continue;
                    ZDOID id = character.GetZDOID();
                    if (id != ZDOID.None && gate.Has(id))
                        continue;
                    float distance = Vector3.Distance(from, character.transform.position);
                    // The alert asks nothing of the dungeon side; EventLines.TurnedAway names the first test that fails.
                    int reason = EventLines.TurnedAway(id != ZDOID.None, character.IsTamed(), StarSets.Accepts(WatchAlerts.EffectiveAlertStars, character.GetLevel()),
                        Rules.WithinRadius(distance, ModConfig.AlertRadius.Value), true);
                    if (reason == EventLines.Passes)
                        continue; // it alerts at this poll's end, or did
                    ToldNotAlerting.Add(character.GetInstanceID());
                    ModLog.Event(EventLines.NotAlerting(Creature.DisplayName(character), prefab, character.GetLevel(), distance, reason,
                        StarSets.Label(WatchAlerts.EffectiveAlertStars)));
                }
                catch (Exception e) { Failed("NotAlerting", e); }
            }
        }

        public static void DingPlayed()
        {
            if (!ModLog.Verbose)
                return;
            try { ModLog.Event(EventLines.DingPlayed(ModConfig.AlertVolume.Value)); }
            catch (Exception e) { Failed("Ding", e); }
        }

        public static void DingNotPlayed(bool noSource)
        {
            if (!ModLog.Verbose)
                return;
            try { ModLog.Event(EventLines.DingNotPlayed(noSource)); }
            catch (Exception e) { Failed("Ding", e); }
        }

        public static void DingGroupSearchFailed(Exception failure)
        {
            if (!ModLog.Verbose)
                return;
            try { ModLog.Event(EventLines.DingGroupSearch(failure.GetType().Name)); }
            catch (Exception e) { Failed("DingGroup", e); }
        }

        // ---- Always track nearest watched (NearestWatched) ----

        /// <summary>
        /// NearestWatched.Update, after a look that found nothing to take: the creatures of watched types loaded, and how
        /// many each test of Retrack.IsCandidate turned away - written when that differs from the last look's.
        /// </summary>
        public static void EmptyLook(Vector3 from, bool playerInside)
        {
            if (!ModLog.Verbose)
                return;
            try
            {
                EmptyLookEach(from, playerInside);
            }
            catch (Exception e) { Failed("EmptyLook", e); }
        }

        private static void EmptyLookEach(Vector3 from, bool playerInside)
        {
            int loaded = 0;
            // Counted by EventLines.TurnedAway's answer: [0] passed every test (gone during the look), [1..5] each reason.
            int[] away = new int[6];
            foreach (Character character in Character.GetAllCharacters())
            {
                try
                {
                    if (!Creature.IsListable(character) || !ModConfig.Watchlist.Contains(Creature.PrefabName(character)))
                        continue;
                    loaded++;
                    away[EventLines.TurnedAway(character.GetZDOID() != ZDOID.None, character.IsTamed(),
                        StarSets.Accepts(WatchAlerts.EffectiveAlertStars, character.GetLevel()),
                        Rules.WithinRadius(Vector3.Distance(from, character.transform.position), ModConfig.AlertRadius.Value),
                        Rules.SameLayer(character.InInterior(), playerInside))]++;
                }
                catch (Exception e) { Failed("EmptyLook", e); }
            }
            try
            {
                string line = EventLines.EmptyLook(loaded, away[EventLines.AwayNotNetworked], away[EventLines.AwayTamed], away[EventLines.AwayStars],
                    away[EventLines.AwayRadius], away[EventLines.AwayOtherSide]);
                if (line == _lastEmptyLook)
                    return;
                _lastEmptyLook = line;
                ModLog.Event(line);
            }
            catch (Exception e) { Failed("EmptyLook", e); }
        }

        // ---- The list window (EntityListWindow) ----

        public static void ListOpened(bool allTypes)
        {
            if (!ModLog.Verbose)
                return;
            try { ModLog.Event(EventLines.ListOpened(allTypes, StarSets.Label(ModConfig.ListStars))); }
            catch (Exception e) { Failed("Open", e); }
        }

        /// <param name="cause">Set by the caller that knows it; null: the inventory opened over the list, or no player.</param>
        public static void ListClosed(string cause)
        {
            if (!ModLog.Verbose)
                return;
            try
            {
                if (cause == null)
                    cause = EventLines.ClosedUnseen(InventoryGui.IsVisible(), Player.m_localPlayer != null);
                ModLog.Event(EventLines.ListClosed(cause));
            }
            catch (Exception e) { Failed("Close", e); }
        }

        /// <summary>
        /// EntityListWindow.HandleKeys, every frame the list did not toggle: with VerboseLog on, when ListKey went down
        /// while the list may not toggle, says what held it. Reads the game's state again, as HandleKeys does.
        /// </summary>
        public static void ListKeyCheck(bool open, bool searchFocused)
        {
            if (!ModLog.Verbose)
                return;
            try
            {
                KeyCode key = ModConfig.ListKey.Value;
                bool typesText = Hotkeys.TypesText(key);
                bool gameTyping = GameTyping.Any(), pause = Menu.IsVisible(), build = Hud.IsPieceSelectionVisible();
                bool inventory = InventoryGui.IsVisible(), barber = PlayerCustomizaton.IsBarberGuiVisible();
                if (ListKeys.MayToggle(open, typesText, searchFocused, gameTyping, pause, build, inventory, barber))
                    return;
                if (!Hotkeys.Pressed(ModConfig.ListKey))
                    return;
                ModLog.Event(EventLines.ListKeyRefused(key.ToString(), open, typesText && (searchFocused || gameTyping), gameTyping, pause,
                    build, inventory, barber));
            }
            catch (Exception e) { Failed("HandleKeys", e); }
        }

        public static void Clicked(string button)
        {
            if (!ModLog.Verbose)
                return;
            try { ModLog.Event(EventLines.Clicked(button)); }
            catch (Exception e) { Failed("Click", e); }
        }

        public static void RowClicked(string button, string label, string prefab)
        {
            if (!ModLog.Verbose)
                return;
            try { ModLog.Event(EventLines.RowClicked(button, label, prefab)); }
            catch (Exception e) { Failed("Click", e); }
        }

        public static void ViewSwitched(bool allTypes)
        {
            if (!ModLog.Verbose)
                return;
            try { ModLog.Event(EventLines.ViewSwitched(allTypes)); }
            catch (Exception e) { Failed("Click", e); }
        }

        // ---- Find area (SpawnFinder) ----

        public static void FindNotStarted()
        {
            if (!ModLog.Verbose)
                return;
            try { ModLog.Event(EventLines.FindNotStarted()); }
            catch (Exception e) { Failed("Find", e); }
        }

        public static void FindSays(string text)
        {
            if (!ModLog.Verbose)
                return;
            try { ModLog.Event(EventLines.FindSays(text)); }
            catch (Exception e) { Failed("Find", e); }
        }

        public static void FindReplaced()
        {
            if (!ModLog.Verbose)
                return;
            try { ModLog.Event(EventLines.FindReplaced()); }
            catch (Exception e) { Failed("Find", e); }
        }

        public static void FindDone(string displayName, long milliseconds, int frames, int candidates, int areas)
        {
            if (!ModLog.Verbose)
                return;
            try { ModLog.Event(EventLines.FindDone(displayName, milliseconds, frames, candidates, areas)); }
            catch (Exception e) { Failed("Find", e); }
        }

        public static void PinsRemoved(int count)
        {
            if (!ModLog.Verbose)
                return;
            try
            {
                if (count > 0)
                    ModLog.Event(EventLines.PinsRemoved(count));
            }
            catch (Exception e) { Failed("Pins", e); }
        }

        public static void MapDeleteTookAreaPin(string pinName)
        {
            if (!ModLog.Verbose)
                return;
            try { ModLog.Event(EventLines.MapDeleteTookAreaPin(pinName)); }
            catch (Exception e) { Failed("Pins", e); }
        }

        // ---- Settings, session, player, load ----

        /// <summary>
        /// The last statement of ModConfig.Bind: every setting's change from here on - the window's, ConfigurationManager's,
        /// the session reset's - reaches SettingChanged, after the setting's own handlers (bound earlier) have run.
        /// </summary>
        public static void Watch(ConfigFile config)
        {
            Config = config;
            config.SettingChanged += OnSettingChanged;
            if (ModLog.Verbose)
                Snapshot();
        }

        private static void OnSettingChanged(object sender, SettingChangedEventArgs args)
        {
            SettingChanged(args.ChangedSetting);
        }

        /// <summary>Every setting's value now, for the "was" of the next change; at load with VerboseLog on, and when it is turned on.</summary>
        private static List<KeyValuePair<string, string>> Snapshot()
        {
            List<KeyValuePair<string, string>> pairs = null;
            try
            {
                if (Config == null)
                    return null;
                pairs = LogFile.Settings(Config);
                Values.Clear();
                foreach (KeyValuePair<string, string> pair in pairs)
                    Values[pair.Key] = pair.Value;
            }
            catch (Exception e) { Failed("Snapshot", e); }
            return pairs;
        }

        /// <summary>
        /// A setting changed (Watch). VerboseLog turned on starts the verbose log afresh: what every setting is now, in one
        /// line, and the once-only lines of NotAlerting and EmptyLook may be said again. The two Logging switches are not
        /// Setting lines: LogFile writes its own line for them.
        /// </summary>
        public static void SettingChanged(ConfigEntryBase entry)
        {
            if (!ModLog.Verbose)
                return;
            try
            {
                if (entry == null)
                    return;
                if (entry.Definition.Section == "Logging")
                {
                    if (entry.Definition.Key == "VerboseLog")
                    {
                        ToldNotAlerting.Clear();
                        _lastEmptyLook = null;
                        List<KeyValuePair<string, string>> pairs = Snapshot();
                        if (pairs != null)
                            ModLog.Event(EventLines.Settings(pairs));
                    }
                    return;
                }
                string key = entry.Definition.Section + "." + entry.Definition.Key;
                string now = entry.GetSerializedValue();
                string was;
                if (!Values.TryGetValue(key, out was))
                    was = "?";
                Values[key] = now;
                string line = Settler.Changed(key, was, now, Time.realtimeSinceStartup);
                if (line != null)
                    ModLog.Event(line);
            }
            catch (Exception e) { Failed("SettingChanged", e); }
        }

        /// <summary>LogObserver, every frame with VerboseLog on: the bursts of changes that have held still.</summary>
        public static void FlushSettings()
        {
            if (!ModLog.Verbose)
                return;
            try
            {
                if (!Settler.Busy)
                    return;
                foreach (string line in Settler.Due(Time.realtimeSinceStartup))
                    ModLog.Event(line);
            }
            catch (Exception e) { Failed("SettingChanged", e); }
        }

        public static void Session()
        {
            if (!ModLog.Verbose)
                return;
            try
            {
                bool began = Game.instance != null;
                ModLog.Event(EventLines.Session(began, ModConfig.KeepBetweenSessions.Value));
            }
            catch (Exception e) { Failed("Session", e); }
        }

        public static void PlayerPresence(bool present)
        {
            if (!ModLog.Verbose)
                return;
            try { ModLog.Event(EventLines.Player(present)); }
            catch (Exception e) { Failed("Player", e); }
        }

        public static void AlertStars(StarSet stars)
        {
            if (!ModLog.Verbose)
                return;
            try { ModLog.Event(EventLines.AlertStars(StarSets.Label(stars))); }
            catch (Exception e) { Failed("AlertStars", e); }
        }

        public static void Patched(string patchClass)
        {
            if (!ModLog.Verbose)
                return;
            try { ModLog.Event(EventLines.Patched(patchClass)); }
            catch (Exception e) { Failed("Patch", e); }
        }

        public static void CompatSkipped(string guid, bool installed)
        {
            if (!ModLog.Verbose)
                return;
            try { ModLog.Event(EventLines.CompatSkipped(guid, installed)); }
            catch (Exception e) { Failed("Compat", e); }
        }
    }
}
