using UnityEngine;

namespace MobTracker
{
    /// <summary>
    /// The verbose events no one calls about - states other code works out every frame - written when they change, never
    /// per frame: the local player there or not, the Alerts: star filter in effect, the guide hidden or shown, the tracked
    /// creature tamed. Read once a frame in Update, so a change is written up to a frame after it happened. After a
    /// tracking starts or ends (Tracker.Generation), the guide and tamed state are taken as they are two frames later,
    /// not reported: Tracker works the guide out in its LateUpdate; the state found when VerboseLog is turned on is taken
    /// the same way, unreported. Also says, with VerboseLog off too, that
    /// MobTracker.log stopped and why (LogFile.ReportNotice).
    /// </summary>
    internal class LogObserver : MonoBehaviour
    {
        private bool _known;
        private bool _player;
        private StarSet _stars;
        private int _generation = -1;
        private int _wait;
        private bool _guideHidden;
        private bool _tamed;

        private void Update()
        {
            LogFile.ReportNotice();
            if (!ModLog.Verbose)
            {
                _known = false;
                _generation = -1;
                return;
            }

            Events.FlushSettings();

            bool player = Player.m_localPlayer != null;
            StarSet stars = WatchAlerts.EffectiveAlertStars;
            if (_known && player != _player)
                Events.PlayerPresence(player);
            if (_known && stars != _stars)
                Events.AlertStars(stars);
            _player = player;
            _stars = stars;
            _known = true;

            if (!Tracker.IsTracking)
            {
                _generation = -1;
                return;
            }
            if (Tracker.Generation != _generation)
            {
                _generation = Tracker.Generation;
                _wait = 2;
                return;
            }
            if (_wait > 0)
            {
                _wait--;
                if (_wait == 0)
                {
                    _guideHidden = Tracker.GuideHiddenNow;
                    _tamed = Tracker.TargetTamed;
                }
                return;
            }

            if (Tracker.GuideHiddenNow != _guideHidden)
            {
                _guideHidden = Tracker.GuideHiddenNow;
                Events.Guide(_guideHidden);
            }
            if (Tracker.IsTrackingCreature && Tracker.TargetTamed != _tamed)
            {
                _tamed = Tracker.TargetTamed;
                if (_tamed)
                    Events.Tamed();
            }
        }
    }
}
