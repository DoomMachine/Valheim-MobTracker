using UnityEngine;

namespace MobTracker
{
    /// <summary>
    /// Tells ModConfig and WatchAlerts when a game session ends or begins, so that the watchlist and the star filters
    /// last one session unless KeepBetweenSessions is on (ModConfig.ResetSession). A session is the life of the world's
    /// Game object: the game makes one when a world loads and destroys it when the start scene is loaded again - a
    /// logout, a lost connection - and Game.OnDestroy sets Game.instance to null. So a session ends or begins whenever Game.instance
    /// is another object than at the last look - at a logout, and when a world is entered, also the first one after
    /// the game starts, and after a crash that never logged out. Dying and respawning keep the Game, and the session;
    /// which character or world plays no part. Compared with ReferenceEquals, not Unity's ==, to which the destroyed
    /// Game of the world just left equals null: a logout would go unseen until the next world is entered.
    ///
    /// Whatever order Unity runs this and the other components in, none of them acts on the state being reset: the
    /// local player is destroyed before the Game at a logout, and is spawned frames after a new Game's Awake, and
    /// every component that uses the watchlist or a star filter waits for a player - except NearestWatched's line for
    /// the end of a wait, which reads the watchlist once the player is gone, so at a logout its reason may say
    /// "nothing is watched" (docs/open-items.md, KL-25).
    /// </summary>
    internal class GameSession : MonoBehaviour
    {
        private Game _game;

        private void Update()
        {
            Game game = Game.instance;
            if (ReferenceEquals(game, _game))
                return;

            _game = game;
            ModConfig.ResetSession();
            WatchAlerts.ResetSession();
        }
    }
}
