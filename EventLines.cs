using System;
using System.Globalization;

namespace MobTracker
{
    /// <summary>
    /// The text of every line VerboseLog adds, and of MobTracker.log's own lines, and the decisions three of them report
    /// (AutoTrackOutcome, TurnedAway, ClosedUnseen) - free of game types, so the tests pin each one, and given plain
    /// values only (tools\preflight.ps1 traces the arguments of the calls around the sites that gather them; a ?: or a
    /// string + object there would hide them). Each line starts with the area it is about,
    /// as the re-track's "Always track nearest watched: " lines do: Track, Guide, Ground path, Alert, Auto-track, Ding,
    /// List, Find area, Map, Setting, Session, Player, Load, Logging. Distances are whole metres, seconds whole seconds.
    /// </summary>
    public static class EventLines
    {
        /// <summary>"Boar * (Boar)": the name as the "Tracking:" label shows it, and the prefab the watchlist uses.</summary>
        public static string Creature(string displayName, string prefab)
        {
            return displayName + " (" + prefab + ")";
        }

        /// <summary>"no star", "1 star", "2 stars" for the game's level 1, 2, 3.</summary>
        public static string Stars(int level)
        {
            int stars = level - 1;
            if (stars <= 0)
                return "no star";
            return stars == 1 ? "1 star" : stars.ToString(CultureInfo.InvariantCulture) + " stars";
        }

        private static string Metres(float distance)
        {
            return ((int)Math.Round(distance)).ToString(CultureInfo.InvariantCulture) + " m";
        }

        private static string Seconds(float seconds)
        {
            return ((int)Math.Round(seconds)).ToString(CultureInfo.InvariantCulture) + " s";
        }

        // ---- Track ----

        /// <param name="distance">From the player; below 0 when there is no player.</param>
        /// <param name="replaces">What was tracked until now, or null.</param>
        public static string TrackStarted(string displayName, string prefab, int level, float distance, bool tamed, bool inside, string replaces)
        {
            return "Track: started - " + Creature(displayName, prefab) + ", " + Stars(level)
                   + (distance >= 0f ? ", " + Metres(distance) + " away" : "")
                   + (tamed ? ", tamed" : "") + (inside ? ", inside a dungeon" : "")
                   + (replaces != null ? "; replaces " + replaces : "");
        }

        public static string TrackStartedArea(string areaName, float distance, string replaces)
        {
            return "Track: started - " + areaName + (distance >= 0f ? ", " + Metres(distance) + " away" : "")
                   + (replaces != null ? "; replaces " + replaces : "");
        }

        public static string TrackStopped(string what, float seconds)
        {
            return "Track: stopped - " + what + " after " + Seconds(seconds);
        }

        /// <param name="killed">Seen dead here (Character.IsDead); otherwise the object is gone.</param>
        /// <param name="retrackOn">Always track nearest watched is on: its own line follows.</param>
        public static string TrackLost(string what, bool killed, bool tamed, bool retrackOn)
        {
            // "seen dead on this client" is reached, for a creature this client runs, only when it has a death
            // animation: for the others the owner's Character.CheckDeath sets m_isDead and destroys the object in one
            // call inside MonoUpdaters.FixedUpdate, and a Destroy issued there is null by that frame's Update and
            // LateUpdate (Unity 6000.0.75f1, the game's engine) - so a kill on this client reads as gone.
            return "Track: lost " + what + " - "
                   + (killed ? "seen dead on this client" : "gone from this client (killed, despawned, or out of range)")
                   + (tamed ? "; it was tamed" : "")
                   + (retrackOn ? "" : "; Always track nearest watched is off");
        }

        public static string TrackNoPlayer(string what)
        {
            return "Track: no local player (dead and removed, or left the world) - ends the tracking of " + what;
        }

        public static string TrackReached(string areaName)
        {
            return "Track: reached " + areaName + " (within 30 m on the flat)";
        }

        /// <summary>A creature tracked wild is tamed now, which ends its tracking as a loss does (0.8.0, Tracker.TamedNow).</summary>
        /// <param name="retrackOn">Always track nearest watched is on: its own line follows.</param>
        public static string TrackTamed(string what, bool retrackOn)
        {
            return "Track: " + what + " is tamed now - the tracking ends, as at a loss"
                   + (retrackOn ? "" : "; Always track nearest watched is off");
        }

        // ---- Guide and ground path ----

        public static string Guide(bool hidden, bool hudHidden, bool cutscene, bool dead, bool waitingForRespawn, bool teleporting)
        {
            if (!hidden)
                return "Guide: shown again";
            string why = (hudHidden ? ", HUD hidden (Ctrl+F3)" : "") + (cutscene ? ", in a cutscene" : "") + (dead ? ", player dead" : "")
                         + (waitingForRespawn ? ", waiting to respawn" : "") + (teleporting ? ", teleporting" : "");
            return "Guide: hidden - " + (why.Length > 0 ? why.Substring(2) : "reason gone by the time it was looked at");
        }

        public const int PathComplete = 0, PathPartial = 1, PathNoPathfinding = 2, PathNoGround = 3, PathNotFound = 4, PathTooShort = 5;

        public static string GroundPath(int state, int points, float shortBy)
        {
            switch (state)
            {
                case PathComplete:
                    return "Ground path: complete, " + points.ToString(CultureInfo.InvariantCulture) + " points";
                case PathPartial:
                    return "Ground path: partial - ends " + Metres(shortBy) + " short of the target, so the arrow shows too ("
                           + points.ToString(CultureInfo.InvariantCulture) + " points)";
                case PathNoPathfinding:
                    return "Ground path: none - the game's pathfinding is not there; the arrow shows";
                case PathNoGround:
                    return "Ground path: none - no walkable ground found near you or near the target; the arrow shows";
                case PathNotFound:
                    return "Ground path: none - no path found (navigation tiles may still be building); the arrow shows";
                default:
                    return "Ground path: none - the path found has no length; the arrow shows";
            }
        }

        // ---- Alerts ----

        public static string Alert(string displayName, string prefab, int level, float distance, int count)
        {
            return "Alert: " + Creature(displayName, prefab) + ", " + Stars(level) + ", " + Metres(distance) + " away"
                   + (count > 1 ? " (+" + (count - 1).ToString(CultureInfo.InvariantCulture) + " more in this check)" : "");
        }

        public const int AutoTook = 0, AutoOff = 1, AutoTracking = 2, AutoWaiting = 3, AutoOtherSide = 4;

        /// <summary>
        /// What Auto-track did with the creature an alert named, worked out after its test from what it leaves behind:
        /// taken when the tracking changed since the alert (Tracker.Generation then and now) and is now that creature;
        /// else not taken because the setting is off, a creature is tracked, the creature is on the other side of a
        /// dungeon entrance, or - none of those - Always track nearest watched waits: the four tests of Auto-track's own
        /// condition in its order (WatchAlerts.Update).
        /// </summary>
        /// <param name="trackingCreature">Tracker.IsTrackingCreature now.</param>
        /// <param name="targetIsAlerted">Tracker.Target is the creature the alert named.</param>
        /// <param name="sameSide">The dungeon-side answer Auto-track's test read, handed over - not worked out again.</param>
        public static int AutoTrackOutcome(int generationNow, int generationAtAlert, bool trackingCreature, bool targetIsAlerted, bool autoTrackOn,
            bool sameSide)
        {
            if (generationNow != generationAtAlert && trackingCreature && targetIsAlerted)
                return AutoTook;
            if (!autoTrackOn)
                return AutoOff;
            if (trackingCreature)
                return AutoTracking;
            if (!sameSide)
                return AutoOtherSide;
            return AutoWaiting;
        }

        /// <param name="tracked">The creature already tracked, for <see cref="AutoTracking"/>.</param>
        public static string AutoTrack(int outcome, string tracked)
        {
            switch (outcome)
            {
                case AutoTook:
                    return "Auto-track: took it";
                case AutoOff:
                    return "Auto-track: off, so not taken";
                case AutoTracking:
                    return "Auto-track: not taken - " + tracked + " is tracked";
                case AutoWaiting:
                    return "Auto-track: not taken - Always track nearest watched is waiting and chooses at its next look";
                default:
                    return "Auto-track: not taken - it is on the other side of a dungeon entrance";
            }
        }

        public static string AlertMemoryCleared(int creatures)
        {
            return "Alert: no local player, so the alert memory of " + creatures.ToString(CultureInfo.InvariantCulture)
                   + " creature(s) is cleared - each watched creature can alert again";
        }

        /// <param name="label">StarSets.Label of the set: "All", "1 star + 2 stars".</param>
        public static string AlertStars(string label)
        {
            return "Alert: the star filter in effect is now " + label;
        }

        public static string DingPlayed(float volume)
        {
            return "Ding: played at AlertVolume " + volume.ToString("0.##", CultureInfo.InvariantCulture);
        }

        public static string DingNotPlayed(bool noSource)
        {
            return noSource ? "Ding: not played - it has no audio source" : "Ding: not played - the game's interface-sound mixer group is not found (yet)";
        }

        public static string DingGroupSearch(string exceptionType)
        {
            return "Ding: the mixer's own group search failed (" + exceptionType + "); looking for the GUI group another way";
        }

        // ---- The list window ----

        public static string ListOpened(bool allTypes, string listStars)
        {
            return "List: opened - " + (allTypes ? "all types view" : "nearby view, List: " + listStars);
        }

        public static string ListClosed(string cause)
        {
            return "List: closed - " + cause;
        }

        public const string ClosedByBack = "Escape or the gamepad's B";
        public const string ClosedByKey = "ListKey";
        public const string ClosedByFind = "Find area";

        /// <summary>The cause of a close no caller named: the inventory opened over the list, else no local player.</summary>
        public static string ClosedUnseen(bool inventoryOpen, bool playerHere)
        {
            if (inventoryOpen)
                return "the inventory opened over it";
            return playerHere ? "(cause not known)" : "no local player";
        }

        public static string Clicked(string button)
        {
            return "List: " + button + " clicked";
        }

        public static string RowClicked(string button, string label, string prefab)
        {
            return "List: " + button + " clicked on " + Creature(label, prefab);
        }

        public static string ViewSwitched(bool allTypes)
        {
            return "List: view switched to " + (allTypes ? "all types" : "nearby");
        }

        // ---- Find area and the map ----

        public static string FindNotStarted()
        {
            return "Find area: not started - no player, world generator or zone system yet";
        }

        public static string FindSays(string hudText)
        {
            return "Find area: the HUD says '" + hudText + "'";
        }

        public static string FindReplaced()
        {
            return "Find area: the search still running is stopped for the new one";
        }

        public static string FindDone(string displayName, long milliseconds, int frames, int candidates, int areas)
        {
            return "Find area: " + displayName + " searched in " + milliseconds.ToString(CultureInfo.InvariantCulture) + " ms over "
                   + frames.ToString(CultureInfo.InvariantCulture) + " frame(s) - " + candidates.ToString(CultureInfo.InvariantCulture)
                   + " candidate zone(s), " + areas.ToString(CultureInfo.InvariantCulture) + " area(s)";
        }

        public static string PinsRemoved(int count)
        {
            return "Find area: " + count.ToString(CultureInfo.InvariantCulture) + " area pin(s) removed";
        }

        public static string MapDeleteTookAreaPin(string pinName)
        {
            return "Map: the delete gesture removed the area pin '" + pinName + "', not a pin of yours";
        }

        // ---- Why not (step 2) ----

        /// <summary>Always track nearest watched's look that took nothing: what it saw.</summary>
        public static string EmptyLook(int loaded, int notNetworked, int tamed, int stars, int radius, int otherSide)
        {
            if (loaded == 0)
                return Retrack.LogPrefix + "look found nothing to take - no creature of a watched type is loaded";
            string why = (notNetworked > 0 ? ", " + Count(notNetworked) + " not on the network yet" : "")
                         + (tamed > 0 ? ", " + Count(tamed) + " tamed" : "")
                         + (stars > 0 ? ", " + Count(stars) + " outside the Alerts: stars" : "")
                         + (radius > 0 ? ", " + Count(radius) + " outside AlertRadius" : "")
                         + (otherSide > 0 ? ", " + Count(otherSide) + " on the other side of a dungeon entrance" : "");
            return Retrack.LogPrefix + "look found nothing to take - " + Count(loaded) + " creature(s) of watched types loaded: "
                   + (why.Length > 0 ? why.Substring(2) : "none turned away (gone during the look)");
        }

        private static string Count(int n)
        {
            return n.ToString(CultureInfo.InvariantCulture);
        }

        /// <summary>ListKey went down while the list may not toggle: what held it.</summary>
        public static string ListKeyRefused(string key, bool open, bool typingInField, bool gameTyping, bool pauseMenu, bool buildMenu,
            bool inventory, bool barber)
        {
            if (open)
                return "List: " + key + " pressed - the list stays open: it types, and a text field has the keyboard";
            string why = (gameTyping ? ", you are typing in a game text field (chat, a sign, a map pin's name, the console)" : "")
                         + (pauseMenu ? ", the pause menu is open" : "") + (buildMenu ? ", the build menu is open" : "")
                         + (inventory ? ", the inventory is open" : "") + (barber ? ", the Barber Station is open" : "");
            return "List: " + key + " pressed - the list stays shut: " + (why.Length > 0 ? why.Substring(2) : "(reason gone)");
        }

        public const int Passes = 0, AwayNotNetworked = 1, AwayTamed = 2, AwayStars = 3, AwayRadius = 4, AwayOtherSide = 5;

        /// <summary>
        /// The first test that turns a creature of a watched type away from the watch alert - not on the network yet,
        /// tamed, its stars not in the Alerts: filter, outside AlertRadius - and, for Always track nearest watched, then
        /// the dungeon side; <see cref="Passes"/> when none does. The not-alerting line names this one reason, the empty
        /// look counts each.
        /// </summary>
        public static int TurnedAway(bool networked, bool tamed, bool starsAccepted, bool withinRadius, bool sameSide)
        {
            if (!networked)
                return AwayNotNetworked;
            if (tamed)
                return AwayTamed;
            if (!starsAccepted)
                return AwayStars;
            if (!withinRadius)
                return AwayRadius;
            if (!sameSide)
                return AwayOtherSide;
            return Passes;
        }

        /// <param name="reason">
        /// From <see cref="TurnedAway"/>; each code has its own words. The alert poll (Events.NotAlertingEach) asks no
        /// dungeon side and writes nothing for <see cref="Passes"/>, so only the first four reach the log today.
        /// </param>
        /// <param name="alertStars">StarSets.Label of the Alerts: stars in effect, named with the stars reason.</param>
        public static string NotAlerting(string displayName, string prefab, int level, float distance, int reason, string alertStars)
        {
            string why;
            switch (reason)
            {
                case AwayNotNetworked:
                    why = "not on the network yet";
                    break;
                case AwayTamed:
                    why = "tamed";
                    break;
                case AwayStars:
                    why = "its stars are not in the Alerts: filter (" + alertStars + ")";
                    break;
                case AwayRadius:
                    why = "outside AlertRadius";
                    break;
                case AwayOtherSide:
                    why = "on the other side of a dungeon entrance";
                    break;
                case Passes:
                    why = "no test turns it away";
                    break;
                default:
                    why = "reason " + Count(reason) + " not known";
                    break;
            }
            return "Alert: none for " + Creature(displayName, prefab) + ", " + Stars(level) + ", " + Metres(distance) + " away - " + why
                   + " (said once for this creature)";
        }

        /// <summary>A verbose line that could not be put together, said once per site as a warning.</summary>
        public static string VerboseFailed(string exceptionType, string site)
        {
            return "A verbose line could not be written (" + exceptionType + " in " + site + "); what it describes was not affected. Said once.";
        }

        // ---- Settings, session, player, load ----

        public static string Setting(string key, string now, string was)
        {
            return "Setting: " + key + " = '" + now + "' (was '" + was + "')";
        }

        public static string SettingSettled(string key, string now, string was, int changes, double seconds)
        {
            return "Setting: " + key + " = '" + now + "' (was '" + was + "'; " + changes.ToString(CultureInfo.InvariantCulture)
                   + " changes in " + ((int)Math.Round(seconds)).ToString(CultureInfo.InvariantCulture) + " s, then held still)";
        }

        public static string Session(bool began, bool keep)
        {
            return "Session: " + (began ? "began - a world was entered" : "ended - back at the main menu")
                   + (keep ? "; KeepBetweenSessions is on, nothing is set back" : "; KeepBetweenSessions is off");
        }

        public static string Player(bool present)
        {
            return present ? "Player: a local player is here" : "Player: no local player (dead and removed, or not in a world)";
        }

        public static string Patched(string patchClass)
        {
            return "Load: " + patchClass + " applied";
        }

        public static string CompatSkipped(string guid, bool installed)
        {
            return "Load: " + guid + (installed ? " is installed but did not load, so its keys are left alone" : " is not installed");
        }

        // ---- MobTracker.log's own lines ----

        /// <summary>
        /// What MobTracker.log gets with these switches. With both off it still gets the switches' notes (Message,
        /// LogRules.ToFile) and, at quit, its closing line (LogFile.Stop).
        /// </summary>
        public static string LoggingNow(bool errorLog, bool verbose)
        {
            if (verbose)
                return "MobTracker.log gets every MobTracker line, events included";
            return errorLog ? "MobTracker.log gets MobTracker's warnings and errors"
                : "MobTracker.log gets only these Logging notes and its closing line until ErrorLog or VerboseLog is turned on";
        }

        /// <summary>A Message line (always written to the file): a switch turned on or off while the game runs.</summary>
        public static string LoggingSwitch(string key, bool on, bool errorLog, bool verbose)
        {
            return "Logging: " + key + " turned " + (on ? "on" : "off") + " - " + LoggingNow(errorLog, verbose)
                   + "; LogOutput.log gets every MobTracker line as before";
        }

        /// <param name="opened">When it opened: "at the game's start", or "when VerboseLog was turned on".</param>
        public static string Header(string version, string game, string bepinex, string opened)
        {
            return "MobTracker " + version + " - MobTracker.log opened " + opened + "; Valheim " + game + "; BepInEx " + bepinex;
        }

        public static string HeaderSwitches(bool errorLog, bool verbose)
        {
            return "Logging: ErrorLog " + (errorLog ? "on" : "off") + ", VerboseLog " + (verbose ? "on" : "off") + " - "
                   + LoggingNow(errorLog, verbose) + "; LogOutput.log gets every MobTracker line as before";
        }

        public static string PrevNotWritten(string exceptionType)
        {
            return "=== MobTracker-prev.log could not be written (" + exceptionType + "), so the last game start's lines are kept above this one ===";
        }

        public static string CapReached(long cap)
        {
            return "MobTracker.log has reached " + (cap / (1024 * 1024)).ToString(CultureInfo.InvariantCulture)
                   + " MB, so nothing more is written to it until the game starts again; LogOutput.log still gets every MobTracker line";
        }

        public static string LeftOut(int count)
        {
            return "(the error below came " + count.ToString(CultureInfo.InvariantCulture)
                   + " more time(s) since it was last written here; those were left out)";
        }

        /// <summary>"Settings: Alerts.AlertRadius = '0', ..." - every setting as the game start read it.</summary>
        public static string Settings(System.Collections.Generic.List<System.Collections.Generic.KeyValuePair<string, string>> pairs)
        {
            var text = new System.Text.StringBuilder("Settings: ");
            for (int i = 0; i < pairs.Count; i++)
            {
                if (i > 0)
                    text.Append(", ");
                text.Append(pairs[i].Key).Append(" = '").Append(pairs[i].Value).Append('\'');
            }
            return text.ToString();
        }

        public static string Closing(int leftOut)
        {
            return "MobTracker.log closed - the game is quitting"
                   + (leftOut > 0 ? "; " + leftOut.ToString(CultureInfo.InvariantCulture) + " repeated error(s) were left out since they were last written" : "");
        }

        public static string OpenFailed(string exceptionType)
        {
            return "MobTracker.log could not be opened (" + exceptionType + "; another running copy of the game may hold it, or it is"
                   + " read-only), so none is written for now; LogOutput.log still gets every MobTracker line.";
        }

        // ---- The cfg (0.7.1, ConfigSaver) ----

        /// <param name="when">"at the game's start", "after a change", "after the session reset".</param>
        public static string CfgNotSaved(string when, string exceptionType)
        {
            return "Settings could not be saved to com.mobtracker.plugin.cfg " + when + " (" + exceptionType + "; it may be read-only, or held"
                   + " by another program). Changes still take effect in the game; the next save that works - at a later change, or when"
                   + " the game quits - writes them all, and if none does they last only until the game closes. Said once until a save"
                   + " works again.";
        }

        /// <param name="when">"after a change", "after the session reset", "as the game quits".</param>
        public static string CfgSavedAgain(string when)
        {
            return "Settings saved to com.mobtracker.plugin.cfg again " + when + ", with every change made while it could not be written.";
        }

        public static string WriteFailed(string exceptionType)
        {
            return "MobTracker.log could not be written (" + exceptionType + ") and is closed until the game starts again; LogOutput.log"
                   + " still gets every MobTracker line.";
        }
    }
}
