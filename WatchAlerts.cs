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
        private readonly AlertGate<ZDOID> _gate = new AlertGate<ZDOID>();
        private float _nextPoll;

        private void Update()
        {
            if (Time.time < _nextPoll)
                return;

            _nextPoll = Time.time + 1f;

            Player player = Player.m_localPlayer;
            if (player == null)
            {
                _gate.Clear();
                return;
            }

            if (ModConfig.Watchlist.Count == 0)
                return;

            Character nearest = null;
            float nearestDistance = float.MaxValue;
            int count = 0;

            foreach (Character character in Character.GetAllCharacters())
            {
                if (!Creature.IsListable(character))
                    continue;

                // No ZDO yet: every such creature would share ZDOID.None and only the first
                // would ever alert. Next poll will have it.
                ZDOID id = character.GetZDOID();
                if (id == ZDOID.None)
                    continue;

                float distance = Vector3.Distance(player.transform.position, character.transform.position);
                // Outside the alert star filter counts as not watched, so the gate does not remember it: it can
                // still alert if the filter changes. The level test goes first; it allocates no name string.
                bool watched = StarFilters.Accepts(ModConfig.AlertStars.Value, character.GetLevel())
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

            if (nearest == null)
                return;

            string text = Creature.DisplayName(nearest) + " detected - " + Mathf.RoundToInt(nearestDistance) + "m";
            if (count > 1)
                text += " (+" + (count - 1) + " more)";

            if (MessageHud.instance != null)
                MessageHud.instance.ShowMessage(MessageHud.MessageType.Center, text);

            Ding.Play();

            // Not while a creature is tracked: a watched type that keeps spawning would otherwise
            // yank the guide off the one being chased every time another appears. A spawn-area
            // guide does give way - the creature turning up is what it was for.
            if (ModConfig.AutoTrack.Value && !Tracker.IsTrackingCreature)
                Tracker.Track(nearest);
        }
    }
}
