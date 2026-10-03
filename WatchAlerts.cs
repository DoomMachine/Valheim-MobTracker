using UnityEngine;

namespace MobTracker
{
    /// <summary>
    /// Polls the loaded creatures once a second for watched types. Polling instead of patching
    /// Character.Awake: spawners set the level after Awake, so a patch there would announce the
    /// wrong stars, and on a client "spawned" and "came into range" are the same thing anyway -
    /// the creature started existing here.
    /// </summary>
    internal class WatchAlerts : MonoBehaviour
    {
        private static readonly StarSetSettler AlertStarsSettler = new StarSetSettler();

        private readonly AlertGate<ZDOID> _gate = new AlertGate<ZDOID>();
        private float _nextPoll;
        private bool _failureLogged;

        /// <summary>
        /// The Alerts: row's set as the alerts, Auto-track and Always track nearest watched use it: under the shipped
        /// AlertsChange.Settle, ModConfig.AlertStars once its cfg text has stayed the same for
        /// StarSetSettler.SettleSeconds (the first value at once; ModConfig.AlertStarsRevision counts the writes), so
        /// the states the row passes through while it is clicked, and a value half-typed in ConfigurationManager, never
        /// alert.
        /// </summary>
        internal static StarSet EffectiveAlertStars { get; private set; }

        /// <summary>
        /// A game session ended or began (GameSession): the Alerts: row as it then stands is taken at once, not 1.5 s
        /// later - with KeepBetweenSessions off, ModConfig.ResetSession has just set it back to All.
        /// </summary>
        internal static void ResetSession()
        {
            AlertStarsSettler.Reset();
            Events.Session();
        }

        private void Update()
        {
            // Every frame, before the once-a-second return: the wait is timed from the text's last change, not from a poll.
            EffectiveAlertStars = AlertsRow.Effective(ModConfig.AlertStars, ModConfig.AlertStarsRevision, AlertStarsSettler, Time.time, AlertsRow.AlertsChangeMode);

            if (Time.time < _nextPoll)
                return;

            _nextPoll = Time.time + 1f;

            Player player = Player.m_localPlayer;
            if (player == null)
            {
                Events.AlertMemoryClearing(_gate.Count);
                _gate.Clear();
                return;
            }

            if (ModConfig.Watchlist.Count == 0)
                return;

            Vector3 from = player.transform.position;
            Character nearest = null;
            float nearestDistance = float.MaxValue;
            int count = 0;

            foreach (Character character in Character.GetAllCharacters())
            {
                // One creature at a time: a creature that throws (another mod's, say) is skipped, and said once in the
                // log, rather than ending the poll - which would also use up, unannounced, the alerts the gate had
                // recorded before it.
                try
                {
                    if (!Creature.IsListable(character))
                        continue;

                    // No ZDO yet: every such creature would share ZDOID.None and only the first
                    // would ever alert. Next poll will have it.
                    ZDOID id = character.GetZDOID();
                    if (id == ZDOID.None)
                        continue;

                    float distance = Vector3.Distance(from, character.transform.position);
                    // Outside the alert star filter counts as not watched, so the gate does not remember it: it can
                    // still alert if the filter changes. The level test goes first; it allocates no name string.
                    bool watched = StarSets.Accepts(EffectiveAlertStars, character.GetLevel())
                                   && ModConfig.Watchlist.Contains(Creature.PrefabName(character));
                    if (!_gate.ShouldAlert(id, watched, character.IsTamed(), distance, ModConfig.AlertRadius.Value))
                        continue;

                    count++;
                    if (distance < nearestDistance)
                    {
                        nearest = character;
                        nearestDistance = distance;
                    }
                }
                catch (System.Exception e)
                {
                    // e.ToString(), not "+ e": that compiles to a null test, a branch that tools\preflight.ps1's argument
                    // tracing cannot follow, and the Track call below is traced.
                    if (!_failureLogged)
                    {
                        _failureLogged = true;
                        MobTrackerPlugin.Log.LogWarning("A creature could not be checked for a watch alert and is skipped (said once): " + e.ToString());
                    }
                }
            }

            Events.NotAlerting(_gate, from); // verbose only: each watched creature that does not alert, and why, once

            if (nearest == null)
                return;

            string text = Creature.DisplayName(nearest) + " detected - " + Mathf.RoundToInt(nearestDistance) + "m";
            if (count > 1)
                text += " (+" + (count - 1) + " more)";

            if (MessageHud.instance != null)
                MessageHud.instance.ShowMessage(MessageHud.MessageType.Center, text);

            Events.Alert(nearest, nearestDistance, count);
            Ding.Play();

            // Not while a creature is tracked: a watched type that keeps spawning would otherwise
            // yank the guide off the one being chased every time another appears. A spawn-area
            // guide does give way - the creature turning up is what it was for. Not across a dungeon entrance: the
            // alert above still shows, but the arrow would point some 5 km up or down. (Whenever any alert of this poll
            // is on the player's side, the nearest is: the other side is thousands of metres away, loaded creatures a
            // few hundred.) Nor while "always track nearest watched" waits after a loss: every watched creature it
            // could take, alerting or not, is its to choose from, and it takes the nearest at its next look (5 s after
            // the loss, then once a second); taking the alerting one here could pass over a nearer one.
            // The side is asked first, into a local, so the Auto-track line is handed the answer this test used. Two ifs, not
            // one && chain: the compiler would join the local to the test before it with an 'and', not a branch, and
            // tools\preflight.ps1 reads each test as a branch to the same skip.
            bool sameSide = Rules.SameLayer(nearest.InInterior(), Character.InInterior(from));
            if (ModConfig.AutoTrack.Value && !Tracker.IsTrackingCreature)
            {
                if (sameSide && !NearestWatched.IsPending)
                    Tracker.Track(nearest);
            }
            Events.AutoTrack(nearest, sameSide);
        }
    }
}
