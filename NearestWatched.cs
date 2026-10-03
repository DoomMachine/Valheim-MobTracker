using UnityEngine;

namespace MobTracker
{
    /// <summary>
    /// "Always track nearest watched": when the tracker loses a creature - of any type, tamed or not - killed, gone
    /// from this client (out of range, despawned), or tamed while tracked (Tracker.TamedNow: one tracked wild and tamed
    /// now, since 0.8.0), while something is watched, wait five seconds, then track the
    /// nearest creature of any watched type, whatever was lost, that passes a watch alert's filters (Alerts stars as
    /// the alerts use them, WatchAlerts.EffectiveAlertStars; AlertRadius; never tamed) and is on the player's side of a
    /// dungeon entrance (both inside a dungeon, or both outside), looking again once a second, without a message, until
    /// there is one. Every watch alert during the wait leaves the choice to this (WatchAlerts asks IsPending): each
    /// alerting creature that Auto-track could take is a candidate here too, and taking it there could pass over a
    /// nearer one. Tracking anything else (a click, Find area), Stop tracking, turning the option off, emptying the
    /// watchlist, dying or leaving the world ends the wait. Any tracked creature's loss starts one while something is
    /// watched (0.8.0); Stop tracking and tracking something else never do, as neither calls Lost.
    /// With the option on, each loss, each take and each end of a wait without a take is one Info line in the log
    /// (Retrack.LostLine, TookLine, EndedLine). The decisions and the lines live in <see cref="Retrack"/>, which the
    /// tests drive; preflight checks what each of its arguments is read from.
    /// </summary>
    internal class NearestWatched : MonoBehaviour
    {
        private static readonly Retrack Pending = new Retrack();

        public static bool IsPending
        {
            get { return Pending.IsPending; }
        }

        /// <summary>
        /// Tracker calls this when the creature it tracked is lost - killed, gone, or tamed while tracked - never when the
        /// player stops tracking.
        /// </summary>
        public static void Lost(string prefab, bool tamed)
        {
            // A statement of its own, not a ?? inside the call: preflight traces each argument of the call below.
            if (prefab == null)
                prefab = "";

            // The watchlist's count, not whether it holds the lost type, and not the tameness: since 0.8.0 any loss
            // starts the wait while something is watched (Retrack decides that 0 starts none; a "> 0" here would be a
            // comparison preflight cannot trace). The line is built after the loss is recorded, so it reports the
            // outcome (Pending.IsPending) and works out why there is no wait from it, rather than asking the watchlist
            // again (one Count here: preflight). The tameness only names the lost creature in the line.
            Pending.Lost(prefab, ModConfig.AlwaysTrackNearest.Value, ModConfig.Watchlist.Count, Time.time);
            string line = Pending.LostLine(prefab, tamed, ModConfig.AlwaysTrackNearest.Value,
                Rules.FormatWatchlist(ModConfig.Watchlist));
            if (line != null)
                MobTrackerPlugin.Log.LogInfo(line);
        }

        /// <summary>
        /// Only the window's Stop tracking calls this. When it ends a wait it says so in the log, before the cancel
        /// (preflight checks that the cancel comes last).
        /// </summary>
        public static void Cancel()
        {
            if (Pending.IsPending)
                MobTrackerPlugin.Log.LogInfo(Pending.EndedLine(Time.time, "Stop tracking"));
            Pending.Cancel();
        }

        private void Update()
        {
            if (!Pending.IsPending)
                return;

            Player player = Player.m_localPlayer;
            if (player == null || Retrack.EndsWait(player.IsDead(), Tracker.IsTracking, ModConfig.AlwaysTrackNearest.Value,
                    ModConfig.Watchlist.Count))
            {
                Pending.Cancel();
                // After the cancel: EndsWait's true path goes straight to it (preflight). The reason is the first that
                // holds of something tracked, the option off and nothing watched, else a death or leaving the world;
                // FormatWatchlist rather than a second Watchlist.Count, which preflight allows once here.
                MobTrackerPlugin.Log.LogInfo(Pending.EndedLine(Time.time,
                    Retrack.EndReason(ModConfig.AlwaysTrackNearest.Value, Tracker.IsTracking,
                        Rules.FormatWatchlist(ModConfig.Watchlist))));
                return;
            }

            if (!Pending.ShouldLook(Time.time))
                return;

            Vector3 from = player.transform.position;
            // Which side of a dungeon entrance the player is on, read once (Rules.SameLayer compares the creature's).
            bool playerInside = Character.InInterior(from);
            Character nearest = null;
            float nearestDistance = float.MaxValue;
            foreach (Character character in Character.GetAllCharacters())
            {
                if (!Creature.IsListable(character))
                    continue;

                // Every test is worked out for every creature, so that each argument is a plain read preflight can
                // trace: once a second, and only while waiting. Any watched type, not only the lost one's.
                float distance = Vector3.Distance(from, character.transform.position);
                if (Retrack.IsCandidate(ModConfig.Watchlist.Contains(Creature.PrefabName(character)),
                        character.GetZDOID() != ZDOID.None, character.IsTamed(),
                        StarSets.Accepts(WatchAlerts.EffectiveAlertStars, character.GetLevel()),
                        Rules.WithinRadius(distance, ModConfig.AlertRadius.Value),
                        Rules.SameLayer(character.InInterior(), playerInside))
                    && distance < nearestDistance)
                {
                    nearest = character;
                    nearestDistance = distance;
                }
            }

            // An empty look returns first, so the line below is written once per take - never per look, and never about
            // a creature that is not there.
            if (nearest == null)
            {
                Events.EmptyLook(from, playerInside); // verbose only: why nothing could be taken, when that changes
                return;
            }

            MobTrackerPlugin.Log.LogInfo(Pending.TookLine(Creature.DisplayName(nearest), nearestDistance, Time.time));
            Pending.Cancel();
            Tracker.Track(nearest);
        }
    }
}
