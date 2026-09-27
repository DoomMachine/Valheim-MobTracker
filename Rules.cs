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
    /// when the wait is over and <see cref="IsCandidate"/> which creature it may take.
    /// </summary>
    public class Retrack
    {
        public const float Delay = 5f;
        public const float LookInterval = 1f;

        private float _nextLook;

        /// <summary>The prefab to look for; null when nothing is pending.</summary>
        public string Prefab { get; private set; }

        public bool IsPending
        {
            get { return Prefab != null; }
        }

        /// <summary>Waiting for this type - a watch alert for it leaves the choice to the re-track.</summary>
        public bool IsPendingFor(string prefab)
        {
            return Prefab != null && string.Equals(Prefab, prefab, StringComparison.Ordinal);
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
        /// The wait is over when the player is dead, anything is tracked (by hand, Find area, or an auto-tracked
        /// alert), the option is off, or the type is no longer watched. (No player at all ends it too; that test
        /// comes first, as there is nobody to ask whether they are dead.)
        /// </summary>
        public static bool EndsWait(bool playerDead, bool tracking, bool enabled, bool watched)
        {
            return playerDead || tracking || !enabled || !watched;
        }

        /// <summary>
        /// A creature the re-track may take: the lost one's type, still on the network (the game drops a creature's
        /// network data first and the creature itself at the end of that frame), and what a watch alert takes - not
        /// tamed, stars the Alerts filter accepts, within AlertRadius.
        /// </summary>
        public static bool IsCandidate(bool sameType, bool networked, bool tamed, bool starsAccepted, bool withinRadius)
        {
            return sameType && networked && !tamed && starsAccepted && withinRadius;
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

        public void Clear()
        {
            _alerted.Clear();
        }
    }
}
