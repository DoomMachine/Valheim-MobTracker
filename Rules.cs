using System;
using System.Collections.Generic;

namespace MobTracker
{
    /// <summary>The decisions that need no game objects, so the test project can link this file.</summary>
    public static class Rules
    {
        /// <summary>Empty query matches everything; otherwise a case-insensitive substring of either name.</summary>
        public static bool Matches(string query, string displayName, string prefabName)
        {
            if (string.IsNullOrWhiteSpace(query))
                return true;

            query = query.Trim();
            return Contains(displayName, query) || Contains(prefabName, query);
        }

        private static bool Contains(string text, string query)
        {
            return text != null && text.IndexOf(query, StringComparison.OrdinalIgnoreCase) >= 0;
        }

        /// <summary>
        /// AlertRadius: 0 or less means anywhere; a creature exactly on the radius is inside. Written as the negation of
        /// 0.2.0's "radius > 0 and farther", so a value that compares false both ways (NaN, typed by hand) still means
        /// anywhere, as it did.
        /// </summary>
        public static bool WithinRadius(float distance, float radius)
        {
            return !(radius > 0f && distance > radius);
        }

        /// <summary>
        /// Whether a pointer at (px, py) - screen pixels, y up from the bottom - is on a window whose rect (x, y, width,
        /// height) is in GUI units under GUI.matrix = Scale(scale): y down from the top, each unit scale pixels. The
        /// edges are Rect.Contains's: the left and top edge inside, the right and bottom edge outside. A scale that is
        /// not above 0 counts as 1.
        /// </summary>
        public static bool PointerOverWindow(float x, float y, float width, float height, float scale, int screenHeight, float px, float py)
        {
            if (!(scale > 0f))
                scale = 1f;
            float gx = px / scale;
            float gy = (screenHeight - py) / scale;
            return gx >= x && gx < x + width && gy >= y && gy < y + height;
        }

        /// <summary>
        /// Both on the same side of a dungeon entrance: both inside a dungeon, or both outside. A dungeon's interior is
        /// built about 5000 m above its entrance and loads with it (Character.InInterior: y above 3000), so a creature on
        /// the other side is listed, and measured, about 5 km away, and an arrow to it points straight up or down.
        /// </summary>
        public static bool SameLayer(bool inside, bool playerInside)
        {
            return inside == playerInside;
        }

        /// <summary>
        /// Whether the creature list refreshes its rows now. The player's own change (search, view, list stars, opening
        /// the window) at once; the twice-a-second refresh, which re-sorts the rows by distance, only while the pointer is
        /// off the window and no mouse button is held - an IMGUI button fires for whatever row is in its place when the
        /// mouse comes up - so it runs as soon as the pointer leaves.
        /// </summary>
        public static bool ShouldRefresh(bool playerChanged, bool due, bool pointerOverWindow, bool mouseHeld)
        {
            return playerChanged || (due && !pointerOverWindow && !mouseHeld);
        }

        /// <summary>
        /// Whether the tracking guide - the arrow, the ground-path line and the "Tracking:" label - is hidden this frame:
        /// while the player hides the HUD (Ctrl+F3), in a cutscene (the game's own reason to hide its HUD), while dead
        /// (the body stays the local player for some seconds after death), in the frame the body is removed for the
        /// respawn (dead no longer reads true there), and during a teleport. Hidden only: the tracking itself goes on until
        /// there is no player (Tracker.LateUpdate stops it then - after a death, usually when the body is removed).
        /// </summary>
        public static bool GuideHidden(bool hudHidden, bool inCutscene, bool dead, bool waitingForRespawn, bool teleporting)
        {
            return hudHidden || inCutscene || dead || waitingForRespawn || teleporting;
        }

        /// <summary>"Troll, serpent,," -> {Troll, serpent}, compared case-insensitively.</summary>
        public static HashSet<string> ParseWatchlist(string text)
        {
            var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (string part in (text ?? "").Split(','))
            {
                string name = part.Trim();
                if (name.Length > 0)
                    set.Add(name);
            }
            return set;
        }

        /// <summary>True when (x, z) is at least <paramref name="spacing"/> from everything already taken.</summary>
        public static bool IsSpaced<T>(float x, float z, IEnumerable<T> taken, float spacing, Func<T, float> getX, Func<T, float> getZ)
        {
            foreach (T other in taken)
            {
                float dx = getX(other) - x, dz = getZ(other) - z;
                if (dx * dx + dz * dz < spacing * spacing)
                    return false;
            }
            return true;
        }

        /// <summary>Sorted so the config file does not churn when entries are toggled.</summary>
        public static string FormatWatchlist(IEnumerable<string> names)
        {
            var sorted = new List<string>(names);
            sorted.Sort(StringComparer.OrdinalIgnoreCase);
            return string.Join(",", sorted);
        }

        /// <summary>
        /// The world-spawn rules that can fire in this world now, decided as SpawnSystem.UpdateSpawnList does: a rule
        /// with a required global key (mostly "defeated_&lt;boss&gt;") waits until the world has that key, and a rule
        /// tied to a persistent event (jotun_invasion) spawns only inside that event's area while it runs, which
        /// Find area cannot map. What the left-out rules wait for is added to <paramref name="keys"/> and
        /// <paramref name="events"/>, each once.
        /// </summary>
        public static List<T> OpenRules<T>(IEnumerable<T> rules, Func<T, string> requiredKey, Func<T, string> requiredEvent,
            Func<string, bool> worldHasKey, List<string> keys, List<string> events)
        {
            var open = new List<T>();
            foreach (T rule in rules)
            {
                string key = requiredKey(rule);
                if (!string.IsNullOrEmpty(key) && !worldHasKey(key))
                {
                    AddOnce(keys, key);
                    continue;
                }

                string worldEvent = requiredEvent(rule);
                if (!string.IsNullOrEmpty(worldEvent))
                {
                    AddOnce(events, worldEvent);
                    continue;
                }

                open.Add(rule);
            }
            return open;
        }

        private static void AddOnce(List<string> list, string value)
        {
            if (!list.Contains(value))
                list.Add(value);
        }

        /// <summary>What Find area says when no rule is open: what the closed ones wait for, or where the creature comes from.</summary>
        public static string NoOpenRule(string displayName, List<string> keys, List<string> events)
        {
            var waits = new List<string>();
            if (keys.Count > 0)
                waits.Add("once this world has " + string.Join(" or ", keys));
            if (events.Count > 0)
                waits.Add("during the " + string.Join(" or ", events) + " event");

            return waits.Count > 0
                ? displayName + " spawns in the wild only " + string.Join(", or ", waits)
                : displayName + " has no rule in the main spawn lists - it comes from a sub-biome, spawners, raids, summons or breeding";
        }
    }

    /// <summary>
    /// The decisions of "always track nearest watched", free of game types so the tests can drive them: after a
    /// tracked creature of a watched type is lost, nothing happens for <see cref="Delay"/> seconds, then it is time to
    /// look once every <see cref="LookInterval"/> seconds until <see cref="Cancel"/>; <see cref="EndsWait"/> says
    /// when the wait is over and <see cref="IsCandidate"/> which creature it may take - one of any watched type, not
    /// only the lost one's. <see cref="LostLine"/>, <see cref="TookLine"/> and <see cref="EndedLine"/> are the log's
    /// line for a loss, a take and the end of a wait without one.
    /// </summary>
    public class Retrack
    {
        public const float Delay = 5f;
        public const float LookInterval = 1f;
        /// <summary>The start of every line the re-track writes to the log.</summary>
        public const string LogPrefix = "Always track nearest watched: ";

        private float _nextLook;
        // When the wait began, for the log lines' seconds; Cancel leaves it, so an end line can still count from it.
        private float _lostAt;

        /// <summary>
        /// The lost creature's type while a wait is on - it marks the wait and is named in <see cref="TookLine"/>, and
        /// does not limit the choice; null when nothing is pending.
        /// </summary>
        public string Prefab { get; private set; }

        public bool IsPending
        {
            get { return Prefab != null; }
        }

        /// <param name="enabled">The option is on.</param>
        /// <param name="watched">The lost creature's type is on the watchlist.</param>
        /// <param name="tamed">The lost creature was tamed: losing a pet starts no hunt for a wild one.</param>
        public void Lost(string prefab, bool enabled, bool watched, bool tamed, float now)
        {
            if (!enabled || !watched || tamed || string.IsNullOrEmpty(prefab))
            {
                Prefab = null;
                return;
            }

            Prefab = prefab;
            _nextLook = now + Delay;
            _lostAt = now;
        }

        /// <summary>True when it is time to look; each true pushes the next look one interval on.</summary>
        public bool ShouldLook(float now)
        {
            if (Prefab == null || now < _nextLook)
                return false;

            _nextLook = now + LookInterval;
            return true;
        }

        public void Cancel()
        {
            Prefab = null;
        }

        /// <summary>
        /// The wait is over when the player is dead, anything is tracked (by hand or Find area; no watch alert is
        /// auto-tracked while it is on), the option is off, or nothing is watched any more (watchedTypes: the
        /// watchlist's count - unwatching the lost type while another stays watched does not end it). (No player at
        /// all ends it too; that test comes first, as there is nobody to ask whether they are dead.)
        /// </summary>
        public static bool EndsWait(bool playerDead, bool tracking, bool enabled, int watchedTypes)
        {
            return playerDead || tracking || !enabled || watchedTypes <= 0;
        }

        /// <summary>
        /// A creature the re-track may take: of a watched type - any of them, not only the lost one's - still on the
        /// network (the game drops a creature's network data first and the creature itself at the end of that frame),
        /// what a watch alert takes - not tamed, stars the Alerts filter accepts, within AlertRadius - and on the
        /// player's side of a dungeon entrance (<see cref="Rules.SameLayer"/>): seen from outside, the nearest one
        /// inside a dungeon is some 5 km straight up.
        /// </summary>
        public static bool IsCandidate(bool watched, bool networked, bool tamed, bool starsAccepted, bool withinRadius, bool sameLayer)
        {
            return watched && networked && !tamed && starsAccepted && withinRadius && sameLayer;
        }

        /// <summary>
        /// The log line after <see cref="Lost"/>: null with the option off; otherwise whether a wait started - read from
        /// <see cref="IsPending"/>, the outcome - and, if not, why. watching: the watchlist as the cfg spells it.
        /// </summary>
        public string LostLine(string prefab, bool tamed, bool enabled, string watching)
        {
            if (IsPending)
                return LogPrefix + "waiting - lost " + prefab + "; watching " + watching;
            if (!enabled)
                return null;
            if (tamed)
                return LogPrefix + "no wait - lost tamed " + prefab;
            return LogPrefix + "no wait - lost " + prefab + ", not on the watchlist (" + (watching.Length > 0 ? watching : "empty") + ")";
        }

        /// <summary>
        /// The log line when the re-track takes a creature, built before the cancel: its name as the "Tracking:" label
        /// shows it, whole metres, whole seconds since the loss, and the lost type.
        /// </summary>
        public string TookLine(string displayName, float distance, float now)
        {
            return LogPrefix + "took " + displayName + " at " + (int)Math.Round(distance) + " m, " + SecondsSinceLoss(now)
                + " s after losing " + Prefab;
        }

        /// <summary>The log line when a wait ends with nothing taken; why: <see cref="EndReason"/>, or Stop tracking.</summary>
        public string EndedLine(float now, string why)
        {
            return LogPrefix + "wait ended after " + SecondsSinceLoss(now) + " s, nothing taken - " + why;
        }

        /// <summary>
        /// Why a wait ended, from what can still be read once it has: the first that holds of something tracked, the
        /// option off and nothing watched (watching: the watchlist as the cfg spells it); otherwise the player died or
        /// left the world.
        /// </summary>
        public static string EndReason(bool enabled, bool tracking, string watching)
        {
            if (tracking)
                return "something else is tracked";
            if (!enabled)
                return "the option was turned off";
            if (string.IsNullOrEmpty(watching))
                return "nothing is watched";
            return "the player died or left the world";
        }

        private int SecondsSinceLoss(float now)
        {
            return (int)Math.Round(now - _lostAt);
        }
    }

    /// <summary>
    /// Alert once per individual creature. A creature outside the radius is deliberately not
    /// remembered, so it still alerts when it later comes near.
    /// </summary>
    public class AlertGate<TId>
    {
        // ponytail: grows by one id per alerted creature until Clear(); prune against the live
        // set if a single session ever alerts on enough creatures for this to matter.
        private readonly HashSet<TId> _alerted = new HashSet<TId>();

        /// <param name="radius">0 or less means anywhere.</param>
        public bool ShouldAlert(TId id, bool watched, bool tamed, float distance, float radius)
        {
            if (!watched || tamed)
                return false;

            if (!Rules.WithinRadius(distance, radius))
                return false;

            return _alerted.Add(id);
        }

        /// <summary>How many creatures have had their alert since the last Clear (the verbose log's line when it clears).</summary>
        public int Count
        {
            get { return _alerted.Count; }
        }

        /// <summary>Whether this creature has had its alert (the verbose log's not-alerting line skips it).</summary>
        public bool Has(TId id)
        {
            return _alerted.Contains(id);
        }

        public void Clear()
        {
            _alerted.Clear();
        }
    }

    /// <summary>
    /// When the list's keys act - TomTom's rules (Plugin.Update), given the game's state by EntityListWindow.HandleKeys.
    /// </summary>
    public static class ListKeys
    {
        // UnityEngine.KeyCode's values of the left, right and middle mouse buttons (tools/preflight.ps1 checks them).
        public const int Mouse0 = 323;
        public const int Mouse2 = 325;

        /// <summary>
        /// Escape or the gamepad's B closes the open list - unless the console is open, or was last frame:
        /// Console.Update closes itself on the same press, and Unity does not order the two Updates.
        /// </summary>
        public static bool ClosesOnBack(bool open, bool consoleVisible, bool consoleWasVisible, bool escape, bool back)
        {
            return open && !consoleVisible && !consoleWasVisible && (escape || back);
        }

        /// <summary>
        /// Whether a press of ListKey toggles the list. Opening: never while the player types in one of the game's text
        /// fields (whatever the key); not over the pause menu (Menu.Update closes it on the Escape that closes the list,
        /// with no text-input test, so one press would close both and unpause); not over the build menu (BuildUi closes
        /// it on a right click, Escape or B, whatever has the pointer or the keyboard, so a right click on the list would
        /// close it); not over the inventory (the list would close again at once); not over the Barber Station
        /// (PlayerCustomizaton.Update cancels it on a raw Escape, so the Escape that closes the list would also put back
        /// the hair and beard the player had). Closing: always, except with a key that types while a text field - the
        /// search box or one of the game's - has the keyboard, so a letter ListKey never closes the list mid-word.
        /// </summary>
        public static bool MayToggle(bool open, bool keyTypesText, bool searchFocused, bool gameTyping, bool pauseMenu,
            bool buildMenu, bool inventory, bool barber)
        {
            if (open)
                return !(keyTypesText && (searchFocused || gameTyping));
            return !gameTyping && !pauseMenu && !buildMenu && !inventory && !barber;
        }

        /// <summary>The left, right or middle mouse button, which ListKey may not be (Hotkeys).</summary>
        public static bool IsClickButton(int keyCode)
        {
            return keyCode >= Mouse0 && keyCode <= Mouse2;
        }
    }
}
