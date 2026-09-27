using System;
using UnityEngine;

namespace MobTracker
{
    /// <summary>
    /// "Always track nearest watched": when the tracker loses a creature of a watched type - killed, or gone from this
    /// client (out of range, despawned) - wait five seconds, then track the nearest creature of that type that passes a
    /// watch alert's filters (Alerts stars, AlertRadius, never tamed), looking again once a second, without a message,
    /// until there is one. A watch alert for that type leaves the choice to this; tracking anything else (a click, Find
    /// area, an auto-tracked alert for another type), Stop tracking, turning the option off, unwatching the type,
    /// dying or leaving the world ends the wait. Losing a tamed creature starts none. The decisions live in
    /// <see cref="Retrack"/>, which the tests drive; preflight checks what each of its arguments is read from.
    /// </summary>
    internal class NearestWatched : MonoBehaviour
    {
        private static readonly Retrack Pending = new Retrack();

        public static bool IsPending
        {
            get { return Pending.IsPending; }
        }

        public static bool IsPendingFor(string prefab)
        {
            return Pending.IsPendingFor(prefab);
        }

        /// <summary>Tracker calls this when the creature it tracked is lost - never when the player stops tracking.</summary>
        public static void Lost(string prefab, bool tamed)
        {
            // A statement of its own, not a ?? inside the call: preflight traces each argument of the call below.
            if (prefab == null)
                prefab = "";

            Pending.Lost(prefab, ModConfig.AlwaysTrackNearest.Value, ModConfig.Watchlist.Contains(prefab), tamed, Time.time);
        }

        public static void Cancel()
        {
            Pending.Cancel();
        }

        private void Update()
        {
            if (!Pending.IsPending)
                return;

            Player player = Player.m_localPlayer;
            if (player == null || Retrack.EndsWait(player.IsDead(), Tracker.IsTracking, ModConfig.AlwaysTrackNearest.Value,
                    ModConfig.Watchlist.Contains(Pending.Prefab)))
            {
                Pending.Cancel();
                return;
            }

            if (!Pending.ShouldLook(Time.time))
                return;

            Vector3 from = player.transform.position;
            Character nearest = null;
            float nearestDistance = float.MaxValue;
            foreach (Character character in Character.GetAllCharacters())
            {
                if (!Creature.IsListable(character))
                    continue;

                // Every test is worked out for every creature, so that each argument is a plain read preflight can
                // trace: once a second, and only while waiting.
                float distance = Vector3.Distance(from, character.transform.position);
                if (Retrack.IsCandidate(string.Equals(Creature.PrefabName(character), Pending.Prefab, StringComparison.Ordinal),
                        character.GetZDOID() != ZDOID.None, character.IsTamed(),
                        StarFilters.Accepts(ModConfig.AlertStars.Value, character.GetLevel()),
                        Rules.WithinRadius(distance, ModConfig.AlertRadius.Value))
                    && distance < nearestDistance)
                {
                    nearest = character;
                    nearestDistance = distance;
                }
            }

            if (nearest == null)
                return;

            Pending.Cancel();
            Tracker.Track(nearest);
        }
    }
}
