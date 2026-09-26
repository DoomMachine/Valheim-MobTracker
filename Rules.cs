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

            if (radius > 0f && distance > radius)
                return false;

            return _alerted.Add(id);
        }

        public void Clear()
        {
            _alerted.Clear();
        }
    }
}
