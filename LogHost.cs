using UnityEngine;

namespace MobTracker
{
    /// <summary>
    /// What MobTracker.log reads from the game: the frame number of its lines and the game's version for its header.
    /// A file of its own, so LogFile.cs needs no game type and tools\log-harness can compile it with a stand-in for this one.
    /// </summary>
    internal static class LogHost
    {
        /// <summary>Unity's frame count; asked only on the game's main thread (LogFile.Write).</summary>
        public static int Frame()
        {
            return Time.frameCount;
        }

        public static string GameVersion()
        {
            return global::Version.GetVersionString(false);
        }
    }
}
