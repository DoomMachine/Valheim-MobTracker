<#
.SYNOPSIS
  Proves the unit tests catch the defects only they can see: plants each one in a copy of the rules that need no game
  (StarFilter.cs, Rules.cs, and since 0.7.0 LogRules.cs and EventLines.cs), runs tests\ and expects it to FAIL.

.DESCRIPTION
  tools\mutants.ps1 proves tools\preflight.ps1 on the built plugin; the decisions inside StarFilter.cs and Rules.cs -
  which levels a star set lets through, what a click does to it, the cfg text, the Alerts: row's wait - and inside
  LogRules.cs and EventLines.cs - which lines MobTracker.log takes, how they look, the verbose lines' words and the
  decisions they report (Auto-track's outcome, which test turned a creature away) - compile to the same calls whether
  right or wrong, so only the unit tests can tell. This script plants one such defect at a time.

  Works in build\unit-mutants\ of the repository this script is in (git ignores build\), emptied first, on a copy of
  -Source's top-level .cs files and tests\ folder (the test project compiles StarFilter.cs, Rules.cs, LogRules.cs and EventLines.cs from the top
  level), so -Source is only read. The copy's line endings are made LF first, so the needles below match a checkout
  with CRLF (Git for Windows' default) as well as one with LF. Each defect is one literal replacement whose needle must
  occur exactly once. First the unmutated copy must build and pass, so a failure below is the defect's. A defect counts
  as caught only when the tests build and exit non-zero with a FAIL line.

  Exits 1 when -Source holds no tests\MobTracker.Tests.csproj, an -Only id is not one of its defects, the unmutated
  copy does not pass, or any defect is not planted, does not build, or passes the tests; 0 when every defect run is
  planted and caught.

.EXAMPLE
  .\tools\unit-mutants.ps1
  .\tools\unit-mutants.ps1 -Only U12,U13
  .\tools\unit-mutants.ps1 -Source D:\clones\MobTracker
#>
[CmdletBinding(PositionalBinding = $false)]   # every argument named: a stray one is an error
param(
    [string[]]$Only = @(),
    [string]$Source = ""    # default: the repository this script is in
)
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
if (-not $Source) { $Source = $repo }
# Drop a trailing \, and the " that powershell.exe -File leaves when a quoted path ending in \ is the last argument.
$Source = $Source.TrimEnd('\', '"')
if (-not (Test-Path -LiteralPath (Join-Path $Source "tests\MobTracker.Tests.csproj"))) {
    Write-Output "No MobTracker tests at $Source (tests\MobTracker.Tests.csproj not found)."
    exit 1
}
$Source = (Resolve-Path -LiteralPath $Source).ProviderPath.TrimEnd('\')
$Only = @($Only | ForEach-Object { $_ -split "," } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$work = Join-Path $repo "build\unit-mutants"
$enc = New-Object System.Text.UTF8Encoding($false)

# id and what a player would get, file, needle (exactly once, LF line endings), replacement
$mutants = @(
    # The star sets (0.4.0).
    @("U1 IsMarked inverted for the categories", "StarFilter.cs", "return (set & flag) != 0;", "return (set & flag) == 0;"),
    @("U2 the All button marked whatever the set", "StarFilter.cs", "return (set & (Every | StarSet.None)) == 0;", "return true;"),
    @("U3 a number in the cfg read one category off", "StarFilter.cs", "category = known ? (StarFilter)number : StarFilter.All;", "category = known ? (StarFilter)((number + 1) % 5) : StarFilter.All;"),
    @("U4 a number in the cfg read as a flag value, not a star count", "StarFilter.cs", "category = known ? (StarFilter)number : StarFilter.All;", "category = known ? (StarFilter)(number == 1 ? 0 : number) : StarFilter.All;"),
    @("U5 a click never takes a category off", "StarFilter.cs", "(set & flag) != 0 ? set & ~flag : set | flag;", "set | flag;"),
    @("U6 a click on All does not reset the row", "StarFilter.cs", "            if (flag == StarSet.All)`n                return StarSet.All;`n            set &= Every;", "            set &= Every;"),
    @("U7 an All inside a list in the cfg is ignored", "StarFilter.cs", "            if (all)`n                return StarSet.All;`n", ""),
    @("U8 the categories marked intersect instead of combining", "StarFilter.cs", "                   || ((set & StarSet.OneStar) != 0", "                   && ((set & StarSet.OneStar) != 0"),
    @("U9 an unknown word in the cfg not reported", "StarFilter.cs", "problem = unknown + "" ignored: not a star category."";", "problem = null;"),
    @("U10 the cfg text names the categories in another order", "StarFilter.cs", "            foreach (StarFilter category in Categories)`n            {`n                if ((set & Of(category)) == 0)", "            for (int c = Categories.Length - 1; c >= 0; c--)`n            {`n                StarFilter category = Categories[c];`n                if ((set & Of(category)) == 0)"),
    @("U11 the title's labels joined with the cfg's separator", "StarFilter.cs", "return Join(set, "" + "", false);", "return Join(set, "", "", false);"),
    # The Alerts: row's wait (StarSetSettler, AlertsChange.Settle - the shipped mode).
    @("U12 the first set waits too - no alerts for 1.5 s at the start", "StarFilter.cs", "                _started = true;`n                _settled = current;`n", "                _started = true;`n                _settled = StarSet.All;`n                _pendingSince = now;`n"),
    @("U13 a change is taken at once - the row's passing states alert again", "StarFilter.cs", "if (now - _pendingSince >= SettleSeconds)", "if (true)"),
    @("U14 the wait timed from the first click, not the last", "StarFilter.cs", "            if (current != _pending || revision != _revision)`n            {`n                _pending = current;`n                _revision = revision;`n                _pendingSince = now;`n            }", "            if (current != _pending || revision != _revision)`n            {`n                if (_pending == _settled)`n                    _pendingSince = now;`n                _pending = current;`n                _revision = revision;`n            }"),
    @("U15 a return to the set in use does not call the change off", "StarFilter.cs", "            if (current == _settled)`n            {`n                _pending = current;`n                return _settled;`n            }", "            if (current == _settled)`n                return _settled;"),
    @("U16 a wait of 1 s, not 1.5", "StarFilter.cs", "public const float SettleSeconds = 1.5f;", "public const float SettleSeconds = 1f;"),
    @("U17 a change held exactly 1.5 s not taken", "StarFilter.cs", "now - _pendingSince >= SettleSeconds", "now - _pendingSince > SettleSeconds"),
    @("U18 the shipped mode is EmptyAlertsNothing", "StarFilter.cs", "AlertsChangeMode = AlertsChange.Settle;", "AlertsChangeMode = AlertsChange.EmptyAlertsNothing;"),
    @("U19 the alerts use the row's set at once under Settle", "StarFilter.cs", "return mode == AlertsChange.Settle ? settler.Settled(row, revision, now) : row;", "return row;"),
    @("U20 the alerts wait under EmptyAlertsNothing too", "StarFilter.cs", "return mode == AlertsChange.Settle ? settler.Settled(row, revision, now) : row;", "return settler.Settled(row, revision, now);"),
    @("U21 EmptyIsNothing answers for the wrong mode", "StarFilter.cs", "return mode == AlertsChange.EmptyAlertsNothing;", "return mode == AlertsChange.Settle;"),
    @("U32 no wait - the row's passing states alert again", "StarFilter.cs", "public const float SettleSeconds = 1.5f;", "public const float SettleSeconds = 0f;"),
    @("U33 a 15 s wait", "StarFilter.cs", "public const float SettleSeconds = 1.5f;", "public const float SettleSeconds = 15f;"),
    @("U34 Settled answers the row's set - a change taken at once", "StarFilter.cs", "                _settled = current;`n            return _settled;", "                _settled = current;`n            return current;"),
    @("U35 never adopts - the wait counted backwards", "StarFilter.cs", "if (now - _pendingSince >= SettleSeconds)", "if (_pendingSince - now >= SettleSeconds)"),
    @("U36 the wait never restarts - timed from 0", "StarFilter.cs", "                _revision = revision;`n                _pendingSince = now;`n", "                _revision = revision;`n"),
    @("U37 the first set leaves the pending one unset", "StarFilter.cs", "                _settled = current;`n                _pending = current;`n                return _settled;", "                _settled = current;`n                return _settled;"),
    @("U38 _started never set - every set taken at once", "StarFilter.cs", "                _started = true;`n", ""),
    # Every write of the Alerts: text restarts the wait (ConfigurationManager writes at each keystroke, and a text
    # with no word it knows yet reads as All).
    @("U46 a keystroke that keeps the set does not restart the wait - a half-typed word can apply as All", "StarFilter.cs", "if (current != _pending || revision != _revision)", "if (current != _pending)"),
    @("U47 the text's revision never remembered - a change never taken", "StarFilter.cs", "                _revision = revision;`n", ""),
    @("U48 the settler not given the text's revision", "StarFilter.cs", "settler.Settled(row, revision, now)", "settler.Settled(row, 0, now)"),
    @("U49 only the revision restarts the wait - the set itself not compared", "StarFilter.cs", "if (current != _pending || revision != _revision)", "if (revision != _revision)"),
    # None, the Alerts: row's empty selection under AlertsChange.EmptyAlertsNothing (built, not shipped).
    @("U22 None lets everything through, like All", "StarFilter.cs", "return (set & StarSet.None) == 0;", "return true;"),
    @("U23 None marks the All button", "StarFilter.cs", "return (set & (Every | StarSet.None)) == 0;", "return (set & Every) == 0;"),
    @("U24 the last category off gives All even with emptyIsNothing", "StarFilter.cs", "return emptyIsNothing && result == StarSet.All ? StarSet.None : result;", "return result;"),
    @("U25 the last category off gives None without emptyIsNothing - the List: row empties", "StarFilter.cs", "return emptyIsNothing && result == StarSet.All ? StarSet.None : result;", "return !emptyIsNothing && result == StarSet.All ? StarSet.None : result;"),
    @("U26 None written as All", "StarFilter.cs", "            if (IsNone(set))`n                return NoneName;`n", ""),
    @("U27 None beside a category counts as None", "StarFilter.cs", "return (set & Every) == 0 && (set & StarSet.None) != 0;", "return (set & StarSet.None) != 0;"),
    @("U28 the cfg may say None when it is not allowed", "StarFilter.cs", "if (allowNone && string.Equals(token, NoneName, StringComparison.OrdinalIgnoreCase))", "if (string.Equals(token, NoneName, StringComparison.OrdinalIgnoreCase))"),
    @("U29 an allowed None in the cfg read as All", "StarFilter.cs", "return set == StarSet.All && none ? StarSet.None : set;", "return set;"),
    @("U30 an allowed None beside a category wins over it", "StarFilter.cs", "return set == StarSet.All && none ? StarSet.None : set;", "return none ? StarSet.None : set;"),
    @("U39 the shipped warning offers None", "StarFilter.cs", "(allowNone ? ""None, "" : """")", """None, """),
    @("U40 an allowed None alone reads as All, with a warning", "StarFilter.cs", "                    valid = true;`n                    none = true;", "                    none = true;"),
    @("U41 All rejects every level, None accepts every one", "StarFilter.cs", "return (set & StarSet.None) == 0;", "return (set & StarSet.None) != 0;"),
    @("U42 the All button marked for every set but All", "StarFilter.cs", "return (set & (Every | StarSet.None)) == 0;", "return (set & (Every | StarSet.None)) != 0;"),
    @("U43 IsNone true for All - the row writes None", "StarFilter.cs", "return (set & Every) == 0 && (set & StarSet.None) != 0;", "return (set & Every) == 0 || (set & StarSet.None) != 0;"),
    # The list's key (Rules.cs).
    @("U31 ListKey opens the list over the Barber Station", "Rules.cs", "return !gameTyping && !pauseMenu && !buildMenu && !inventory && !barber;", "return !gameTyping && !pauseMenu && !buildMenu && !inventory;"),
    @("U44 MayToggle opens the list only over the barber", "Rules.cs", "&& !inventory && !barber;", "&& !inventory && barber;"),
    # A new game session starts the settler over (0.5.0).
    @("U50 Reset does nothing - a new session's Alerts: row waits 1.5 s", "StarFilter.cs", "            _started = false;`n", ""),
    @("U51 Reset makes All the settled set - a kept Alerts: row waits 1.5 s at the start of a session, with All in use", "StarFilter.cs", "            _started = false;`n", "            _settled = StarSet.All;`n"),
    # The tracking guide's gate (0.5.1).
    @("U52 a teleport no longer hides the guide", "Rules.cs", "return hudHidden || inCutscene || dead || waitingForRespawn || teleporting;", "return hudHidden || inCutscene || dead || waitingForRespawn;"),
    @("U53 the respawn frame no longer hides the guide", "Rules.cs", "|| dead || waitingForRespawn ||", "|| dead ||"),
    @("U54 a cutscene hides the guide only with the HUD hidden too", "Rules.cs", "return hudHidden || inCutscene ||", "return hudHidden && inCutscene ||"),
    @("U55 GuideHidden always true - the guide never shows", "Rules.cs", "return hudHidden || inCutscene || dead || waitingForRespawn || teleporting;", "return true;"),
    @("U56 GuideHidden always false - the guide never hides", "Rules.cs", "return hudHidden || inCutscene || dead || waitingForRespawn || teleporting;", "return false;"),
    @("U57 GuideHidden hides when NOT teleporting", "Rules.cs", "return hudHidden || inCutscene || dead || waitingForRespawn || teleporting;", "return hudHidden || inCutscene || dead || waitingForRespawn || !teleporting;"),
    @("U58 GuideHidden reads dead for the respawn frame", "Rules.cs", "return hudHidden || inCutscene || dead || waitingForRespawn || teleporting;", "return hudHidden || inCutscene || dead || dead || teleporting;"),
    @("U45 the barber stops the list closing", "Rules.cs", "return !(keyTypesText && (searchFocused || gameTyping));", "return !barber && !(keyTypesText && (searchFocused || gameTyping));"),
    # Always track nearest watched since 0.6.0: the nearest creature of any watched type.
    @("U59 the re-track's candidate ignores the watchlist - an unwatched Troll is taken", "Rules.cs", "return watched && networked", "return networked"),
    @("U60 the re-track takes only unwatched types", "Rules.cs", "return watched && networked", "return !watched && networked"),
    @("U61 emptying the watchlist never ends the wait", "Rules.cs", "|| !enabled || watchedTypes <= 0;", "|| !enabled;"),
    @("U62 the wait ends while one type is still watched", "Rules.cs", "watchedTypes <= 0;", "watchedTypes <= 1;"),
    @("U63 the log line's metres unrounded", "Rules.cs", "(int)Math.Round(distance)", "distance"),
    @("U64 the log line drops the name", "Rules.cs", """ + displayName + """, """ + """),
    # The Retrack decisions shipped since 0.3.0, proved by planted defects since 0.6.0.
    @("U65 a loss of an unwatched type starts a wait", "Rules.cs", "if (!enabled || !watched || tamed ||", "if (!enabled || tamed ||"),
    @("U66 no 5 s delay before the first look", "Rules.cs", "_nextLook = now + Delay;", "_nextLook = now;"),
    @("U67 it looks on every frame", "Rules.cs", "_nextLook = now + LookInterval;", "_nextLook = now;"),
    @("U68 the re-track takes tamed creatures", "Rules.cs", "&& !tamed && starsAccepted", "&& starsAccepted"),
    @("U69 the re-track crosses a dungeon entrance", "Rules.cs", "&& withinRadius && sameLayer;", "&& withinRadius;"),
    @("U70 a death does not end the wait", "Rules.cs", "return playerDead || tracking ||", "return tracking ||"),
    @("U71 the re-track ignores the Alerts stars", "Rules.cs", "&& !tamed && starsAccepted && withinRadius", "&& !tamed && withinRadius"),
    @("U72 the re-track ignores AlertRadius", "Rules.cs", "&& starsAccepted && withinRadius && sameLayer", "&& starsAccepted && sameLayer"),
    @("U73 a loss of a tamed creature starts a wait", "Rules.cs", "if (!enabled || !watched || tamed ||", "if (!enabled || !watched ||"),
    @("U74 Cancel leaves the wait on", "Rules.cs", "        public void Cancel()`n        {`n            Prefab = null;", "        public void Cancel()`n        {`n"),
    # The log lines (0.6.0).
    @("U75 the loss line never says a wait started", "Rules.cs", "if (IsPending)`n", "if (!IsPending)`n"),
    @("U76 the loss line written with the option off", "Rules.cs", "if (!enabled)`n                return null;", "if (enabled)`n                return null;"),
    @("U77 a tamed loss logged as one of an unwatched type", "Rules.cs", "if (tamed)`n", "if (false)`n"),
    @("U78 the loss time never recorded", "Rules.cs", "_lostAt = now;", "_lostAt = 0f;"),
    @("U79 the seconds counted from the start of the game", "Rules.cs", "(int)Math.Round(now - _lostAt)", "(int)Math.Round(now)"),
    @("U80 an emptied watchlist read as a death", "Rules.cs", "string.IsNullOrEmpty(watching)", "watching == null"),
    @("U81 the end reason never names the tracking", "Rules.cs", "if (tracking)`n", "if (false)`n"),
    @("U82 the end reason never names the option", "Rules.cs", "if (!enabled)`n                return ""the option", "if (false)`n                return ""the option"),
    @("U83 the took line drops the lost type", "Rules.cs", """ s after losing "" + Prefab", """ s after losing """),
    @("U84 the end reason names the option before the tracking", "Rules.cs", "if (tracking)`n                return ""something else is tracked"";`n            if (!enabled)`n                return ""the option was turned off"";", "if (!enabled)`n                return ""the option was turned off"";`n            if (tracking)`n                return ""something else is tracked"";"),
    @("U85 the end reason names an empty watchlist first", "Rules.cs", "if (tracking)`n                return ""something else is tracked"";`n            if (!enabled)`n                return ""the option was turned off"";`n            if (string.IsNullOrEmpty(watching))`n                return ""nothing is watched"";", "if (string.IsNullOrEmpty(watching))`n                return ""nothing is watched"";`n            if (tracking)`n                return ""something else is tracked"";`n            if (!enabled)`n                return ""the option was turned off"";"),
    # Since 0.6.0, more of Retrack's decisions and lines.
    @("U86 the took line's metres truncated", "Rules.cs", "(int)Math.Round(distance)", "(int)distance"),
    @("U87 the candidate's first && became || - a watched creature passes whatever else holds", "Rules.cs", "return watched && networked && !tamed", "return watched || networked && !tamed"),
    @("U88 EndsWait: watchedTypes < 0 - emptying the watchlist never ends the wait", "Rules.cs", "watchedTypes <= 0;", "watchedTypes < 0;"),
    @("U89 the loss line's (empty) dropped", "Rules.cs", "(watching.Length > 0 ? watching : ""empty"")", "watching"),
    @("U90 the loss time taken as the first look's", "Rules.cs", "_lostAt = now;", "_lostAt = _nextLook;"),
    @("U91 Cancel forgets the loss time - an end line counts from 0", "Rules.cs", "        public void Cancel()`n        {`n            Prefab = null;`n", "        public void Cancel()`n        {`n            Prefab = null;`n            _lostAt = 0f;`n"),
    @("U92 a loss with no type (a spawn area) starts a wait", "Rules.cs", " || string.IsNullOrEmpty(prefab))", ")"),
    @("U93 the first look a frame late (now <= _nextLook)", "Rules.cs", "now < _nextLook)", "now <= _nextLook)"),
    @("U94 the loss line's waiting read from the inputs, not the outcome", "Rules.cs", "if (IsPending)`n                return LogPrefix + ""waiting", "if (enabled && !tamed)`n                return LogPrefix + ""waiting"),
    @("U95 EndsWait ignores tracking", "Rules.cs", "return playerDead || tracking || !enabled", "return playerDead || !enabled"),
    @("U96 EndsWait ignores the option", "Rules.cs", "|| tracking || !enabled ||", "|| tracking ||"),
    @("U97 the candidate ignores the network test - a creature the game is removing is taken", "Rules.cs", "return watched && networked && !tamed", "return watched && !tamed"),
    @("U98 the loss line drops the watchlist", "Rules.cs", " + ""; watching "" + watching;", ";"),
    # Since 0.6.0: the log lines' rounding, and their seconds counted from the loss.
    @("U99 the log lines' seconds truncated, not rounded", "Rules.cs", "(int)Math.Round(now - _lostAt)", "(int)(now - _lostAt)"),
    @("U100 the took line's metres rounded up", "Rules.cs", "(int)Math.Round(distance)", "(int)Math.Ceiling(distance)"),
    @("U101 the seconds counted from the next look less the delay - wrong after the first look", "Rules.cs", "(int)Math.Round(now - _lostAt)", "(int)Math.Round(now - _nextLook + Delay)"),
    # MobTracker.log's rules (LogRules.cs, 0.7.0).
    @("U102 the switches' notes not always written - a switch turned off is not said in the file", "LogRules.cs", "            if ((level & Message) != 0)`n                return true;`n", ""),
    @("U103 VerboseLog on without ErrorLog leaves the warnings and errors out", "LogRules.cs", "return errorLog || verbose;", "return errorLog;"),
    @("U104 ErrorLog takes Info lines too", "LogRules.cs", "            return verbose;`n        }", "            return verbose || errorLog;`n        }"),
    @("U105 another source's lines looked at with both switches off", "LogRules.cs", "            if (!anySwitch)`n                return Skip;`n", ""),
    @("U106 BepInEx's warnings taken after MobTracker's settings were read", "LogRules.cs", "if (binding && sourceName == ""BepInEx"" && (level & Warning) != 0)", "if (sourceName == ""BepInEx"" && (level & Warning) != 0)"),
    @("U107 another plugin's errors looked at", "LogRules.cs", "if ((level & (Fatal | Error)) != 0 && (sourceName == ""Unity Log"" || sourceName == ""BepInEx""))", "if ((level & (Fatal | Error)) != 0)"),
    @("U108 Unity's warnings looked at as errors", "LogRules.cs", "if ((level & (Fatal | Error)) != 0 && (sourceName", "if ((level & (Fatal | Error | Warning)) != 0 && (sourceName"),
    @("U109 an exception's message read as a frame", "LogRules.cs", "            for (int i = 1; i < lines.Length; i++)`n            {`n                if (OurFrame(lines[i]) != null)", "            for (int i = 0; i < lines.Length; i++)`n            {`n                if (OurFrame(lines[i]) != null)"),
    @("U110 Mono's 'at ' not taken off - its frames never MobTracker's", "LogRules.cs", "frame = frame.Substring(3);", "frame = frame.Substring(0);"),
    @("U111 the namespace tested without its dot - MobTrackerExtras is MobTracker", "LogRules.cs", "return frame.StartsWith(""MobTracker."", StringComparison.Ordinal) ? frame : null;", "return frame.StartsWith(""MobTracker"", StringComparison.Ordinal) ? frame : null;"),
    @("U112 the repeat key without its frame - the same throw from two places counted as one", "LogRules.cs", "return lines[0].TrimEnd('\r') + ""|"" + frame;", "return lines[0].TrimEnd('\r');"),
    @("U113 the file line without its date", "LogRules.cs", "now.ToString(""yyyy-MM-dd HH:mm:ss.fff"", CultureInfo.InvariantCulture)", "now.ToString(""HH:mm:ss.fff"", CultureInfo.InvariantCulture)"),
    @("U114 a line off the main thread given frame -1", "LogRules.cs", "(frame >= 0 ? ", "(frame >= -1 ? "),
    @("U115 a stack trace's further lines not indented", "LogRules.cs", ".Replace(""\n"", ""\r\n    "");", ".Replace(""\n"", ""\r\n"");"),
    @("U116 the folders scrubbed only in their own case", "LogRules.cs", "StringComparison.OrdinalIgnoreCase", "StringComparison.Ordinal"),
    @("U117 the shorter folder scrubbed first - a game folder inside the user folder left half written", "LogRules.cs", "bool gameFirst = (gameFolder ?? """").Length >= (userFolder ?? """").Length;", "bool gameFirst = (gameFolder ?? """").Length < (userFolder ?? """").Length;"),
    @("U118 a folder given with a trailing backslash never found", "LogRules.cs", "            folder = folder.TrimEnd('\\', '/');`n", ""),
    @("U119 a line that reaches the cap exactly refused", "LogRules.cs", "return written + lineBytes <= cap;", "return written + lineBytes < cap;"),
    @("U120 an error's inner cause left out - a patch failure says only where", "LogRules.cs", "x != null && depth < 5;", "x != null && depth < 1;"),
    @("U121 a repeated error written every 6 s", "LogRules.cs", "public const double Window = 60.0;", "public const double Window = 6.0;"),
    @("U122 the left-out count never reset - counted twice", "LogRules.cs", "            seen.Left = 0;`n", ""),
    @("U123 every repeat of an error written", "LogRules.cs", "            if (now - seen.WrittenAt < Window)", "            if (false)"),
    @("U124 a dragged slider written at every step", "LogRules.cs", "if (_bursts.TryGetValue(key, out burst) && t - burst.Last < Quiet)", "if (false)"),
    @("U125 a lone setting change written twice", "LogRules.cs", "if (pair.Value.Changes > 1)", "if (pair.Value.Changes > 0)"),
    @("U126 a line not padded as LogOutput.log's", "LogRules.cs", """[{0,-7}:{1,10}] {2}""", """[{0}:{1}] {2}"""),
    @("U127 a line whose text cannot be read written empty", "LogRules.cs", "return ""(the text of this line could not be read: "" + e.GetType().Name + "")"";", "return """";"),
    # The verbose lines' texts (EventLines.cs, 0.7.0).
    @("U128 stars counted from the level - a no-star creature called 1 star", "EventLines.cs", "int stars = level - 1;", "int stars = level;"),
    @("U129 distances cut, not rounded", "EventLines.cs", "return ((int)Math.Round(distance)).ToString(CultureInfo.InvariantCulture) + "" m"";", "return ((int)distance).ToString(CultureInfo.InvariantCulture) + "" m"";"),
    @("U130 the ding's volume written with the system's comma", "EventLines.cs", "volume.ToString(""0.##"", CultureInfo.InvariantCulture)", "volume.ToString(""0.##"")"),
    @("U131 the empty look's line without the re-track's prefix", "EventLines.cs", "return Retrack.LogPrefix + ""look found nothing to take - "" + Count(loaded)", "return ""look found nothing to take - "" + Count(loaded)"),
    @("U132 a refused ListKey never names the inventory", "EventLines.cs", "+ (inventory ? "", the inventory is open"" : """")", ""),
    @("U133 Auto-track off said as taken", "EventLines.cs", "                case AutoOff:`n                    return ""Auto-track: off, so not taken"";", "                case AutoOff:`n                    return ""Auto-track: took it"";"),
    @("U134 the file's notes ignore VerboseLog", "EventLines.cs", "            if (verbose)`n                return ""MobTracker.log gets every MobTracker line, events included"";`n", ""),
    @("U135 the open's failure says this game start, though a switch tries again", "EventLines.cs", "so none is written for now;", "so none is written this game start;"),
    @("U136 a kill said as an unload and an unload as a kill", "EventLines.cs", "(killed ? ""seen dead on this client"" : ", "(!killed ? ""seen dead on this client"" : "),
    @("U137 the guide's cutscene reason never said", "EventLines.cs", "+ (cutscene ? "", in a cutscene"" : """")", ""),
    @("U138 a partial ground path never says how short", "EventLines.cs", "return ""Ground path: partial - ends "" + Metres(shortBy)", "return ""Ground path: partial - ends "" + Metres(0f)"),
    @("U139 the cap said in KB as MB", "EventLines.cs", "(cap / (1024 * 1024))", "(cap / 1024)"),
    # The decisions the verbose lines report, out of Events since 0.7.0 (EventLines.cs).
    @("U140 Auto-track's take read without the generation - a creature tracked before the alert said as taken", "EventLines.cs", "if (generationNow != generationAtAlert && trackingCreature && targetIsAlerted)", "if (trackingCreature && targetIsAlerted)"),
    @("U141 Auto-track's take read without the target - a tracking changed to another creature said as taken", "EventLines.cs", "if (generationNow != generationAtAlert && trackingCreature && targetIsAlerted)", "if (generationNow != generationAtAlert && trackingCreature)"),
    @("U142 Auto-track's take read without a creature tracked - a stale target said as taken", "EventLines.cs", "if (generationNow != generationAtAlert && trackingCreature && targetIsAlerted)", "if (generationNow != generationAtAlert && targetIsAlerted)"),
    @("U143 Auto-track off asked after a creature tracked - off said as tracked", "EventLines.cs", "            if (!autoTrackOn)`n                return AutoOff;`n            if (trackingCreature)`n                return AutoTracking;`n", "            if (trackingCreature)`n                return AutoTracking;`n            if (!autoTrackOn)`n                return AutoOff;`n"),
    @("U144 the dungeon side asked before a creature tracked - a tracked creature said as the other side", "EventLines.cs", "            if (trackingCreature)`n                return AutoTracking;`n            if (!sameSide)`n                return AutoOtherSide;`n", "            if (!sameSide)`n                return AutoOtherSide;`n            if (trackingCreature)`n                return AutoTracking;`n"),
    @("U145 the other side of a dungeon entrance never said - waiting said instead", "EventLines.cs", "            if (!sameSide)`n                return AutoOtherSide;`n            return AutoWaiting;", "            return AutoWaiting;"),
    @("U160 the dungeon side read the wrong way round", "EventLines.cs", "            if (!sameSide)`n                return AutoOtherSide;", "            if (sameSide)`n                return AutoOtherSide;"),
    @("U161 the cfg warning does not say when", "EventLines.cs", "return ""Settings could not be saved to com.mobtracker.plugin.cfg "" + when + "" ("" + exceptionType", "return ""Settings could not be saved to com.mobtracker.plugin.cfg ("" + exceptionType"),
    @("U162 the cfg's 'saved again' line does not say when", "EventLines.cs", "return ""Settings saved to com.mobtracker.plugin.cfg again "" + when + "",", "return ""Settings saved to com.mobtracker.plugin.cfg again,"),
    @("U163 the dungeon side asked before AutoTrack's off - off said as the other side", "EventLines.cs", "            if (!autoTrackOn)`n                return AutoOff;`n            if (trackingCreature)`n                return AutoTracking;`n            if (!sameSide)`n                return AutoOtherSide;`n", "            if (!sameSide)`n                return AutoOtherSide;`n            if (!autoTrackOn)`n                return AutoOff;`n            if (trackingCreature)`n                return AutoTracking;`n"),
    @("U164 the re-track's wait never said - the other side said instead", "EventLines.cs", "                return AutoOtherSide;`n            return AutoWaiting;", "                return AutoOtherSide;`n            return AutoOtherSide;"),
    @("U165 the cfg warning's when and exception type swapped", "EventLines.cs", "return ""Settings could not be saved to com.mobtracker.plugin.cfg "" + when + "" ("" + exceptionType", "return ""Settings could not be saved to com.mobtracker.plugin.cfg "" + exceptionType + "" ("" + when"),
    @("U146 tamed asked before the network - a creature not on the network yet said as tamed", "EventLines.cs", "            if (!networked)`n                return AwayNotNetworked;`n            if (tamed)`n                return AwayTamed;`n", "            if (tamed)`n                return AwayTamed;`n            if (!networked)`n                return AwayNotNetworked;`n"),
    @("U147 the radius asked before the stars", "EventLines.cs", "            if (!starsAccepted)`n                return AwayStars;`n            if (!withinRadius)`n                return AwayRadius;`n", "            if (!withinRadius)`n                return AwayRadius;`n            if (!starsAccepted)`n                return AwayStars;`n"),
    @("U148 the dungeon side never asked - the empty look counts none on the other side", "EventLines.cs", "            if (!sameSide)`n                return AwayOtherSide;`n", ""),
    @("U149 the stars reason without the filter in effect", "EventLines.cs", "why = ""its stars are not in the Alerts: filter ("" + alertStars + "")"";", "why = ""its stars are not in the Alerts: filter"";"),
    @("U150 a creature not on the network yet said as tamed", "EventLines.cs", "why = ""not on the network yet"";", "why = ""tamed"";"),
    @("U151 a close with no player said as not known", "EventLines.cs", "return playerHere ? ""(cause not known)"" : ""no local player"";", "return ""(cause not known)"";"),
    @("U152 the inventory named only while a player is here", "EventLines.cs", "if (inventoryOpen)", "if (inventoryOpen && playerHere)"),
    @("U153 a failed verbose line's warning without its site", "EventLines.cs", """ in "" + site + ""); what it describes", """); what it describes"),
    @("U154 both switches off said as nothing more - the switch notes and the closing line still come", "EventLines.cs", """MobTracker.log gets only these Logging notes and its closing line until ErrorLog or VerboseLog is turned on""", """MobTracker.log gets nothing more until ErrorLog or VerboseLog is turned on"""),
    @("U155 both switches on said as warnings and errors only - the switch note and the header", "EventLines.cs", "            if (verbose)`n", "            if (verbose && !errorLog)`n"),
    @("U156 the not-alerting line's dungeon side said as outside AlertRadius", "EventLines.cs", "why = ""on the other side of a dungeon entrance"";", "why = ""outside AlertRadius"";"),
    @("U157 a creature that passes every test said as outside AlertRadius", "EventLines.cs", "why = ""no test turns it away"";", "why = ""outside AlertRadius"";"),
    @("U158 the radius reason left to the default - outside AlertRadius said as a code not known", "EventLines.cs", "                case AwayRadius:`n                    why = ""outside AlertRadius"";`n                    break;`n", ""),
    # Since 0.7.0: the settings' settler forgets a burst once said.
    @("U159 a burst never forgotten once said - its settled line again on every frame of the settings flush", "LogRules.cs", "                done.Add(pair.Key);`n", "")
)
$ids = @($mutants | ForEach-Object { ($_[0] -split " ")[0] })
$unknown = @($Only | Where-Object { $ids -notcontains $_ })
if ($unknown.Count -gt 0) {
    Write-Output ("Unknown defect id(s): {0}. The ids are: {1}" -f ($unknown -join ", "), ($ids -join ", "))
    exit 1
}

# A fresh copy, with LF line endings, into an emptied folder; a directory link there is refused rather than emptied through.
if (Test-Path -LiteralPath $work) {
    $isLink = (Get-Item -LiteralPath $work -Force).Attributes -band [IO.FileAttributes]::ReparsePoint
    $links = @(Get-ChildItem -LiteralPath $work -Recurse -Force -Attributes ReparsePoint -ErrorAction SilentlyContinue)
    if ($isLink -or $links.Count -gt 0) { Write-Output "$work is or holds a directory link - move it away first."; exit 1 }
    [IO.Directory]::Delete($work, $true)
}
New-Item -ItemType Directory -Force -Path (Join-Path $work "tests") | Out-Null
$files = @(Get-ChildItem -LiteralPath $Source -File -Filter *.cs | ForEach-Object { $_.Name }) +
    @(Get-ChildItem -LiteralPath (Join-Path $Source "tests") -File | ForEach-Object { "tests\" + $_.Name })
foreach ($f in $files) {
    $text = [IO.File]::ReadAllText((Join-Path $Source $f)).Replace("`r`n", "`n")
    [IO.File]::WriteAllText((Join-Path $work $f), $text, $enc)
}
$project = Join-Path $work "tests\MobTracker.Tests.csproj"
$testDll = Join-Path $work "build\tests\MobTracker.Tests.dll"

function Test-Copy {
    # Builds the copy's tests from nothing and runs them: the build's or the run's lines, the exit code ($null if it did
    # not build) and the FAIL lines. Prints nothing itself: whatever a PowerShell function writes is part of its result.
    if (Test-Path -LiteralPath $testDll) { Remove-Item -LiteralPath $testDll }
    # Continue around the child processes: under Stop their error output through 2>&1 would end the run.
    $ErrorActionPreference = "Continue"
    $b = & dotnet build $project -c Release --no-incremental -nologo -v q 2>&1 | Out-String
    if (-not (Test-Path -LiteralPath $testDll)) { return [pscustomobject]@{ Code = $null; Fails = @(); Lines = @("    BUILD FAILED", $b) } }
    $global:LASTEXITCODE = $null   # a run that could not start must not read the build's 0 as a pass
    $out = @(& dotnet $testDll 2>&1 | ForEach-Object { "$_" })
    return [pscustomobject]@{ Code = $global:LASTEXITCODE; Fails = @($out | Where-Object { $_ -match "^\s+FAIL " }); Lines = @($out | Select-Object -Last 3) }
}

Write-Output "=== unmutated copy of $Source"
$r = Test-Copy
if ($r.Code -ne 0 -or $r.Fails.Count -gt 0) { $r.Lines; $r.Fails; Write-Output "    the unmutated copy does not build or pass its tests - fix that first"; exit 1 }
Write-Output ("    PASSED, as it should ({0})" -f ($r.Lines | Where-Object { $_ -match "TESTS PASSED" } | Select-Object -First 1))

$bad = 0; $run = 0
foreach ($m in $mutants) {
    $id = ($m[0] -split " ")[0]
    if ($Only.Count -gt 0 -and $Only -notcontains $id) { continue }
    $run++
    $path = Join-Path $work $m[1]
    $orig = [IO.File]::ReadAllText($path)
    $needle = $m[2].Replace("`r`n", "`n")
    Write-Output ("=== {0}" -f $m[0])
    $n = ([regex]::Matches($orig, [regex]::Escape($needle))).Count
    if ($n -ne 1) { Write-Output ("    NOT PLANTED: the needle occurs {0} times in {1}" -f $n, $m[1]); $bad++; continue }
    [IO.File]::WriteAllText($path, $orig.Replace($needle, $m[3].Replace("`r`n", "`n")), $enc)
    $r = Test-Copy
    [IO.File]::WriteAllText($path, $orig, $enc)
    if ($null -eq $r.Code) { $r.Lines; Write-Output "    NOT BUILT"; $bad++ }
    elseif ($r.Code -ne 0 -and $r.Fails.Count -gt 0) { Write-Output ("    caught ({0} failing test(s), e.g.{1})" -f $r.Fails.Count, ($r.Fails[0] -replace '^\s+FAIL', '')) }
    elseif ($r.Code -ne 0) { Write-Output ("    NOT PROVEN - the tests exited {0} without a FAIL line; their last lines:" -f $r.Code); $r.Lines; $bad++ }
    else { Write-Output "    NOT CAUGHT - every test passed with this defect"; $bad++ }
}

Write-Output ""
if ($bad -eq 0) { Write-Output "UNIT MUTANTS: every one of $run planted defects fails the tests."; exit 0 }
Write-Output "UNIT MUTANTS: $bad of $run defect(s) not planted, not built, not caught or not proven."
exit 1
