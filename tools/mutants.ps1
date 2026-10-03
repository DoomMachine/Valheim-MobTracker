<#
.SYNOPSIS
  Proves tools\preflight.ps1 catches the defects it is there for: plants each one in a copy of the source,
  builds it and expects preflight to FAIL.

.DESCRIPTION
  Works in build\mutants\ (git ignores build\), emptied first, on a copy of the working tree's files - tracked, and
  untracked ones git does not ignore, so a new source file needs no 'git add' first - and of lib\, so the repository
  itself is never edited. Preflight runs in this process (no console window per mutant). Right after the unmutated copy
  passes, the run names the TomTom or Wayfinder DLLs its preflight checked against (or says there are none). When the
  run ends or is stopped (Ctrl+C included), the copy's build\ and obj\ are emptied, so no planted-defect DLL -
  stamped like a real build of the commit - is left behind. Each mutant is one regex replacement that must match exactly once.
  First the unmutated copy is built and must PASS, so a failure below is the mutant's and not the copy's. A mutant
  counts as caught only when preflight exits non-zero with a FAIL line. Exits 1 if -ValheimDir holds no Valheim
  install, an -Only id is not one of its mutants, the clean copy fails, a mutant cannot be planted or built, or any
  mutant passes preflight or makes it stop without a FAIL line.

  The game folder is -ValheimDir, else the VALHEIM environment variable, else the default - as for the build and
  the other tools; it reaches the copy's build and preflight through VALHEIM.

.EXAMPLE
  .\tools\mutants.ps1
  .\tools\mutants.ps1 -Only F1,F2
#>
[CmdletBinding(PositionalBinding = $false)]   # every argument named: a stray one is an error
param(
    [string[]]$Only = @(),
    [string]$ValheimDir = ""
)
$ErrorActionPreference = "Stop"
# Set here, before anything can call Finish: Remove-MutantBuilds reads this script's $work only, never a caller's.
$work = $null
# -ValheimDir reaches the copy's MobTracker.csproj and tools\preflight.ps1 through VALHEIM; the caller's value
# comes back when this script ends, however it ends.
$callersValheim = $env:VALHEIM
# No planted-defect build is left behind: its DLL carries the same version stamp as a real build of the commit. Nothing
# is emptied through a directory link, whichever exit calls this: not when $work itself is one, nor build\ or obj\.
function Remove-MutantBuilds {
    if (-not $script:work -or -not (Test-Path -LiteralPath $script:work)) { return }
    if ((Get-Item -LiteralPath $script:work -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { return }
    foreach ($d in @("build", "obj")) {
        $p = Join-Path $script:work $d
        if ((Test-Path -LiteralPath $p) -and -not ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            [IO.Directory]::Delete($p, $true)
        }
    }
}
function Finish([int]$code) {
    $env:VALHEIM = $callersValheim
    Remove-MutantBuilds
    exit $code
}
trap { $env:VALHEIM = $callersValheim; break }
if ($ValheimDir) {
    # Resolved here, so a relative path means the same to the copy's build as to this shell.
    # Drop a trailing \, and the " that powershell.exe -File leaves when a quoted path ending in
    # \ is the last argument (anywhere earlier it swallows the arguments after it: leave the \ off).
    $ValheimDir = $ValheimDir.TrimEnd('\', '"')
    if (-not (Test-Path -LiteralPath (Join-Path $ValheimDir "valheim_Data\Managed\assembly_valheim.dll"))) {
        Write-Output "No Valheim install at $ValheimDir (valheim_Data\Managed\assembly_valheim.dll not found)."
        Finish 1
    }
    $env:VALHEIM = (Resolve-Path -LiteralPath $ValheimDir).ProviderPath.TrimEnd('\')
}
$Only = @($Only | ForEach-Object { $_ -split "," } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$repo = Split-Path $PSScriptRoot -Parent
$work = Join-Path $repo "build\mutants"
$enc = New-Object System.Text.UTF8Encoding($false)

# id, file, regex (must match exactly once), replacement
$mutants = @(
    # The star filters (the list's and the alerts' are the same types, text entry and parsed set, so crossing them
    # compiles): who reads each, which entry each is parsed from, what each window row shows and writes, and which way
    # the code branches on the answers.
    @("S1 WatchAlerts reads the list's filter", "WatchAlerts.cs", [regex]::Escape("StarSets.Accepts(EffectiveAlertStars, character.GetLevel())"), "StarSets.Accepts(ModConfig.ListStars, character.GetLevel())"),
    @("S2 Refresh reads the alerts' filter", "EntityListWindow.cs", [regex]::Escape("StarSets.Accepts(_appliedListStars, character.GetLevel())"), "StarSets.Accepts(ModConfig.AlertStars, character.GetLevel())"),
    @("S3 Update never stores the applied list filter", "EntityListWindow.cs", ("[ \t]*" + [regex]::Escape("_appliedListStars = ModConfig.ListStars;") + "\r?\n"), ""),
    @("S4 the Alerts: row reads and writes the list's filter", "EntityListWindow.cs", "(?s)(GUILayout\.Label\(""Alerts:"", RowLabelWidth\);.*?)ModConfig\.AlertStars;(.*?)ModConfig\.AlertStarsText\.Value", '${1}ModConfig.ListStars;${2}ModConfig.ListStarsText.Value'),
    @("S5 the List: row writes the alerts' entry", "EntityListWindow.cs", [regex]::Escape("ModConfig.ListStarsText.Value = StarSets.Format(StarSets.Toggle(listStars,"), "ModConfig.AlertStarsText.Value = StarSets.Format(StarSets.Toggle(listStars,"),
    @("S6 the Alerts: row writes the list's entry", "EntityListWindow.cs", [regex]::Escape("ModConfig.AlertStarsText.Value = StarSets.Format(StarSets.Toggle(alertStars,"), "ModConfig.ListStarsText.Value = StarSets.Format(StarSets.Toggle(alertStars,"),
    @("S7 the list's entry feeds the alerts' filter at the start", "ModConfig.cs", "(?m)^([ \t]*)AlertStars = ParseStars\(AlertStarsText,([^\r\n]*\r?\n[ \t]*ListStarsText\.SettingChanged)", '${1}AlertStars = ParseStars(ListStarsText,${2}'),
    @("S8 the alerts' entry feeds the list's filter when it changes", "ModConfig.cs", [regex]::Escape("=> ListStars = ParseStars(ListStarsText,"), "=> ListStars = ParseStars(AlertStarsText,"),
    @("S9 a change to the alerts' entry re-parses the list's filter", "ModConfig.cs", ([regex]::Escape("AlertStarsText.SettingChanged += (sender, args) =>") + "(\r?\n[ \t]*\{\r?\n[ \t]*)AlertStars = ParseStars\(AlertStarsText,"), 'AlertStarsText.SettingChanged += (sender, args) =>${1}ListStars = ParseStars(ListStarsText,'),
    @("S10 the alerts' re-parse hangs on the list's entry", "ModConfig.cs", ([regex]::Escape("AlertStarsText.SettingChanged += (sender, args) =>") + "(\r?\n[ \t]*\{\r?\n[ \t]*AlertStars = )"), 'ListStarsText.SettingChanged += (sender, args) =>${1}'),
    @("S11 the list's filter never re-parsed - its row stops working", "ModConfig.cs", "[ \t]*ListStarsText\.SettingChanged \+= [^\r\n]*\r?\n", ""),
    @("S12 the Alerts: row writes a raw ToString, not Format", "EntityListWindow.cs", [regex]::Escape("StarSets.Format(StarSets.Toggle(alertStars, StarButtons[i], emptyIsNothing))"), "StarSets.Toggle(alertStars, StarButtons[i], emptyIsNothing).ToString()"),
    @("S13 the List: row drops Toggle - one category at a time again", "EntityListWindow.cs", [regex]::Escape("StarSets.Format(StarSets.Toggle(listStars, StarButtons[i]))"), "StarSets.Format(StarSets.Of(StarButtons[i]))"),
    @("S14 the rows swapped under their labels", "EntityListWindow.cs", "(?s)GUILayout\.Label\(""List:"", RowLabelWidth\);(.*?)GUILayout\.Label\(""Alerts:"", RowLabelWidth\);", 'GUILayout.Label("Alerts:", RowLabelWidth);${1}GUILayout.Label("List:", RowLabelWidth);'),
    @("S15 the List: row shows the alerts' marks", "EntityListWindow.cs", [regex]::Escape("StarSets.IsMarked(listStars,"), "StarSets.IsMarked(ModConfig.AlertStars,"),
    @("S16 the alert poll takes only the categories NOT marked", "WatchAlerts.cs", [regex]::Escape("bool watched = StarSets.Accepts(EffectiveAlertStars,"), "bool watched = !StarSets.Accepts(EffectiveAlertStars,"),
    @("S17 the list shows only the categories NOT marked", "EntityListWindow.cs", [regex]::Escape("!StarSets.Accepts(_appliedListStars, character.GetLevel())"), "StarSets.Accepts(_appliedListStars, character.GetLevel())"),
    @("S18 the List: row writes on every event for every button not clicked", "EntityListWindow.cs", "(?s)(GUILayout\.Label\(""List:"", RowLabelWidth\);.*?)GUI\.skin\.button\) != marked\)", '${1}GUI.skin.button) == marked)'),
    @("S19 the Alerts: row toggles the All button whatever is clicked", "EntityListWindow.cs", [regex]::Escape("StarSets.Toggle(alertStars, StarButtons[i],"), "StarSets.Toggle(alertStars, StarButtons[0],"),
    @("S20 the List: row stays clickable in the all-types view", "EntityListWindow.cs", [regex]::Escape("GUI.enabled = enabled && !_allTypes;"), "GUI.enabled = enabled;"),
    @("S21 ParseStars warns on clean text and never on bad text", "ModConfig.cs", [regex]::Escape("if (problem != null)"), "if (problem == null)"),
    @("S22 the title names the alerts' categories", "EntityListWindow.cs", [regex]::Escape("StarSets.Label(_appliedListStars)"), "StarSets.Label(ModConfig.AlertStars)"),
    @("S23 the List: row shows every button as the All button", "EntityListWindow.cs", [regex]::Escape("StarSets.IsMarked(listStars, StarButtons[i])"), "StarSets.IsMarked(listStars, StarFilter.All)"),
    @("S24 ParseStars drops what it parsed - the filters never apply", "ModConfig.cs", [regex]::Escape("StarSet set = StarSets.Parse(entry.Value, out problem, allowNone);"), "StarSet set = StarSets.Parse(entry.Value, out problem, allowNone); set = StarSet.All;"),
    @("S25 ParseStars parses the default, not the value", "ModConfig.cs", [regex]::Escape("StarSets.Parse(entry.Value, out problem, allowNone)"), "StarSets.Parse((string)entry.DefaultValue, out problem, allowNone)"),
    @("S26 the Alerts: row writes on every event for every button not clicked", "EntityListWindow.cs", "(?s)(GUILayout\.Label\(""Alerts:"", RowLabelWidth\);.*?)GUI\.skin\.button\) != marked\)", '${1}GUI.skin.button) == marked)'),
    @("S27 the Alerts: row shows the list's marks", "EntityListWindow.cs", [regex]::Escape("StarSets.IsMarked(alertStars,"), "StarSets.IsMarked(ModConfig.ListStars,"),
    @("S28 the alert star test reads one level up", "WatchAlerts.cs", [regex]::Escape("StarSets.Accepts(EffectiveAlertStars, character.GetLevel())"), "StarSets.Accepts(EffectiveAlertStars, character.GetLevel() + 1)"),
    @("S29 PlayerChanged compares the alerts' filter", "EntityListWindow.cs", [regex]::Escape("|| ModConfig.ListStars != _appliedListStars;"), "|| ModConfig.AlertStars != _appliedListStars;"),
    @("S30 the List: row toggles from All, not from its own set", "EntityListWindow.cs", [regex]::Escape("StarSets.Format(StarSets.Toggle(listStars, StarButtons[i]))"), "StarSets.Format(StarSets.Toggle(StarSet.All, StarButtons[i]))"),
    @("S31 the List: row stays clickable in the all-types view (|| for &&)", "EntityListWindow.cs", [regex]::Escape("GUI.enabled = enabled && !_allTypes;"), "GUI.enabled = enabled || !_allTypes;"),
    @("S32 the title names no category while one is marked", "EntityListWindow.cs", [regex]::Escape(": _appliedListStars == StarSet.All ? "" creatures loaded"""), ": _appliedListStars != StarSet.All ? "" creatures loaded"""),
    @("S33 the Alerts: row loses its All button", "EntityListWindow.cs", "(?s)(GUILayout\.Label\(""Alerts:"", RowLabelWidth\);.*?)for \(int i = 0;", '${1}for (int i = 1;'),
    @("S34 the List: row loses its 2+ stars button", "EntityListWindow.cs", "(?s)(GUILayout\.Label\(""List:"", RowLabelWidth\);.*?)i < StarButtons\.Length;", '${1}i < StarButtons.Length - 1;'),
    @("S35 the List: row writes whenever a button reads marked", "EntityListWindow.cs", "(?s)(GUILayout\.Label\(""List:"", RowLabelWidth\);.*?)if \(GUILayout\.Toggle\(marked, StarChoices\[i\], GUI\.skin\.button\) != marked\)", '${1}if (GUILayout.Toggle(marked, StarChoices[i], GUI.skin.button))'),
    @("S36 ParseStars returns All whatever it parsed", "ModConfig.cs", [regex]::Escape("            return set;"), "            return StarSet.All;"),
    @("S37 every Alerts: button labelled All", "EntityListWindow.cs", "(?s)(GUILayout\.Label\(""Alerts:"", RowLabelWidth\);.*?)GUILayout\.Toggle\(marked, StarChoices\[i\]", '${1}GUILayout.Toggle(marked, StarChoices[0]'),
    # The Alerts: row's changes reach the alerts once the row has held still (AlertsChange.Settle, the shipped mode):
    # worked out on every frame from the row's own set and the game's clock, read by the alert poll and the re-track;
    # the mode, and its rule that the Alerts: row empties to All and the cfg cannot say None, kept as shipped.
    @("A1 the alert poll reads the row's set as it is, not the settled one", "WatchAlerts.cs", [regex]::Escape("bool watched = StarSets.Accepts(EffectiveAlertStars,"), "bool watched = StarSets.Accepts(ModConfig.AlertStars,"),
    @("A2 the re-track reads the row's set as it is, not the settled one", "NearestWatched.cs", [regex]::Escape("StarSets.Accepts(WatchAlerts.EffectiveAlertStars,"), "StarSets.Accepts(ModConfig.AlertStars,"),
    @("A3 the settled set worked out only at the poll - the wait counted in polls", "WatchAlerts.cs", "(?s)(\r?\n[ \t]*EffectiveAlertStars = AlertsRow\.Effective\([^\r\n]*)(.*?_nextPoll = Time\.time \+ 1f;)", '${2}${1}'),
    @("A4 the settled set never stored", "WatchAlerts.cs", [regex]::Escape("EffectiveAlertStars = AlertsRow.Effective("), "AlertsRow.Effective("),
    @("A5 a new settler every frame - nothing ever waits", "WatchAlerts.cs", [regex]::Escape("ModConfig.AlertStarsRevision, AlertStarsSettler, Time.time,"), "ModConfig.AlertStarsRevision, new StarSetSettler(), Time.time,"),
    @("A6 the settled set follows the List: row", "WatchAlerts.cs", [regex]::Escape("AlertsRow.Effective(ModConfig.AlertStars,"), "AlertsRow.Effective(ModConfig.ListStars,"),
    @("A7 the settler's clock stands still - a change is never taken", "WatchAlerts.cs", [regex]::Escape("AlertStarsSettler, Time.time,"), "AlertStarsSettler, 0f,"),
    @("A8 the build runs with EmptyAlertsNothing", "StarFilter.cs", [regex]::Escape("AlertsChangeMode = AlertsChange.Settle;"), "AlertsChangeMode = AlertsChange.EmptyAlertsNothing;"),
    @("A9 the alerts' set worked out as under EmptyAlertsNothing - no wait", "WatchAlerts.cs", [regex]::Escape("Time.time, AlertsRow.AlertsChangeMode);"), "Time.time, AlertsChange.EmptyAlertsNothing);"),
    @("A10 the Alerts: row empties to None under the shipped mode", "EntityListWindow.cs", [regex]::Escape("bool emptyIsNothing = AlertsRow.EmptyIsNothing(AlertsRow.AlertsChangeMode);"), "bool emptyIsNothing = true;"),
    @("A11 the List: row empties as the Alerts: row's mode says", "EntityListWindow.cs", [regex]::Escape("StarSets.Toggle(listStars, StarButtons[i])"), "StarSets.Toggle(listStars, StarButtons[i], AlertsRow.EmptyIsNothing(AlertsRow.AlertsChangeMode))"),
    @("A12 the alerts' entry may say None under the shipped mode", "ModConfig.cs", "(?m)^([ \t]*)AlertStars = ParseStars\(AlertStarsText, [^\r\n]*(\r?\n[ \t]*ListStarsText\.SettingChanged)", '${1}AlertStars = ParseStars(AlertStarsText, true);${2}'),
    @("A13 the list's entry may say None", "ModConfig.cs", [regex]::Escape("=> ListStars = ParseStars(ListStarsText, false);"), "=> ListStars = ParseStars(ListStarsText, true);"),
    # Where the alert poll's answers go: the star-and-watchlist answer into the gate, the gate's answer into the alert.
    @("A14 the alert poll ignores its star and watchlist answer - every creature in range alerts", "WatchAlerts.cs", [regex]::Escape("_gate.ShouldAlert(id, watched,"), "_gate.ShouldAlert(id, true,"),
    @("A15 the alert poll alerts for what it does not watch", "WatchAlerts.cs", [regex]::Escape("_gate.ShouldAlert(id, watched,"), "_gate.ShouldAlert(id, !watched,"),
    @("A16 the gate's refusals alert", "WatchAlerts.cs", [regex]::Escape("if (!_gate.ShouldAlert("), "if (_gate.ShouldAlert("),
    # The mode and the settled set, in more forms.
    @("A17 the mode a const - folded into each caller as 0", "StarFilter.cs", [regex]::Escape("internal static readonly AlertsChange AlertsChangeMode"), "internal const AlertsChange AlertsChangeMode"),
    @("A18 the mode static but writable", "StarFilter.cs", [regex]::Escape("internal static readonly AlertsChange AlertsChangeMode"), "internal static AlertsChange AlertsChangeMode"),
    @("A19 the settler timed by Time.deltaTime - a change never taken", "WatchAlerts.cs", [regex]::Escape("AlertStarsSettler, Time.time,"), "AlertStarsSettler, Time.deltaTime,"),
    @("A20 the settler on unscaled time - it runs on through a pause", "WatchAlerts.cs", [regex]::Escape("AlertStarsSettler, Time.time,"), "AlertStarsSettler, Time.unscaledTime,"),
    @("A21 the settler fed its own answer - the alerts keep the first set", "WatchAlerts.cs", [regex]::Escape("AlertsRow.Effective(ModConfig.AlertStars,"), "AlertsRow.Effective(EffectiveAlertStars,"),
    @("A22 the poll overwrites the settled set with the row's", "WatchAlerts.cs", [regex]::Escape("_nextPoll = Time.time + 1f;"), "_nextPoll = Time.time + 1f; EffectiveAlertStars = ModConfig.AlertStars;"),
    @("A23 the Alerts: row shows and toggles the settled set - its marks lag", "EntityListWindow.cs", [regex]::Escape("StarSet alertStars = ModConfig.AlertStars;"), "StarSet alertStars = WatchAlerts.EffectiveAlertStars;"),
    @("A24 the list's filter may read None at the start", "ModConfig.cs", "(?m)^([ \t]*)ListStars = ParseStars\(ListStarsText, false\);", '${1}ListStars = ParseStars(ListStarsText, true);'),
    @("A25 the alerts' re-parse allows None under Settle", "ModConfig.cs", "(\{\r?\n[ \t]*AlertStars = ParseStars\(AlertStarsText, )AlertsRow\.EmptyIsNothing\(", '${1}!AlertsRow.EmptyIsNothing('),
    @("A26 ParseStars inverts the leave to read None", "ModConfig.cs", [regex]::Escape("StarSets.Parse(entry.Value, out problem, allowNone)"), "StarSets.Parse(entry.Value, out problem, !allowNone)"),
    @("A27 the Alerts: row empties to None under Settle", "EntityListWindow.cs", [regex]::Escape("bool emptyIsNothing = AlertsRow.EmptyIsNothing("), "bool emptyIsNothing = !AlertsRow.EmptyIsNothing("),
    # Every change of the Alerts: text restarts the wait (ConfigurationManager writes at each keystroke, and a text
    # with no word it knows yet reads as All).
    @("A28 a change of the Alerts: text never counted - a word half-typed in ConfigurationManager can apply as All", "ModConfig.cs", "[ \t]*AlertStarsRevision\+\+;\r?\n", ""),
    @("A29 the settled set not given the text's revision", "WatchAlerts.cs", [regex]::Escape("ModConfig.AlertStars, ModConfig.AlertStarsRevision,"), "ModConfig.AlertStars, 0,"),
    @("A30 the revision also counted every frame - a change never taken", "WatchAlerts.cs", "(\r?\n)([ \t]*)(EffectiveAlertStars = AlertsRow\.Effective\()", '${1}${2}ModConfig.AlertStarsRevision++;${1}${2}${3}'),
    @("A31 the list's text counted instead of the alerts'", "ModConfig.cs", "(?s)(ListStarsText\.SettingChanged \+= \(sender, args\) => )(ListStars = ParseStars\(ListStarsText, false\);)(.*?)[ \t]*AlertStarsRevision\+\+;\r?\n", '${1}{ ${2} AlertStarsRevision++; };${3}'),
    # Find area.
    @("F1 area pins saved", "SpawnFinder.cs", [regex]::Escape("displayName + "" area"", false, false)"), "displayName + "" area"", true, false)"),
    @("F2 area pins owned by someone", "SpawnFinder.cs", [regex]::Escape("displayName + "" area"", false, false)"), "displayName + "" area"", false, false, 1L)"),
    @("F3 area pin marked saved after AddPin", "SpawnFinder.cs", ("(" + [regex]::Escape("_pins.Add(map.AddPin(position, Minimap.PinType.Icon3, displayName + "" area"", false, false));") + ")"), '{ ${1} _pins[_pins.Count - 1].m_save = true; }'),
    @("F4 a second AddPin", "SpawnFinder.cs", ("(" + [regex]::Escape("Tracker.TrackPoint(new Vector3(areas[0].x, WaterLevel, areas[0].y), displayName + "" spawn area"");") + ")"), '${1} if (map != null) map.AddPin(Vector3.zero, Minimap.PinType.Icon3, "", false, false);'),
    @("F5 no key or event conditions", "SpawnFinder.cs", "(?s)Rules\.OpenRules\(named,.*?keys, events\);", "named;"),
    @("F6 the event condition not read", "SpawnFinder.cs", [regex]::Escape("rule => rule.m_requiredPersistentEvent"), "rule => null"),
    @("F7 every key taken as held", "SpawnFinder.cs", [regex]::Escape("key => zones.GetGlobalKey(key)"), "key => zones != null"),
    @("F8 the delete patch on the wrong overload", "Plugin.cs", [regex]::Escape("new[] { typeof(Vector3), typeof(float) }"), "new[] { typeof(Vector3), typeof(int) }"),
    @("F9 a misspelt Harmony injection", "Plugin.cs", "(?s)bool __runOriginal\)(.*?)!__runOriginal", 'bool __runOrignal)${1}!__runOrignal'),
    @("F12 a patch parameter the target does not have", "Plugin.cs", "(?s)float radius, (.*?)RemovePinNear\(__instance, pos, radius\)", 'float range, ${1}RemovePinNear(__instance, pos, range)'),
    @("F10 the delete patch never applied", "Plugin.cs", ("[ \t]*" + [regex]::Escape("Patch(typeof(RemoveAreaPinPatch));") + "\r?\n"), ""),
    @("F11 the delete patch ignores area pins", "Plugin.cs", [regex]::Escape("!SpawnFinder.RemovePinNear(__instance, pos, radius)"), "__instance != null"),
    @("F13 the delete patch's priority on the class, where Harmony ignores it", "Plugin.cs", "(?s)(internal static class RemoveAreaPinPatch)(\s*\{\s*)\[HarmonyPriority\(Priority\.Low\)\]", '[HarmonyPriority(Priority.Low)] ${1}${2}'),
    @("F14 the delete patch at the default priority", "Plugin.cs", [regex]::Escape("[HarmonyPriority(Priority.Low)]"), "[HarmonyPriority(Priority.Normal)]"),
    @("F15 the delete patch acts after another prefix took the gesture", "Plugin.cs", "[ \t]*if \(!__runOriginal\)\r?\n[ \t]*return false;\r?\n", ""),
    @("F16 a saved pin through Minimap.DiscoverLocation", "SpawnFinder.cs", ("(" + [regex]::Escape("Tracker.TrackPoint(new Vector3(areas[0].x, WaterLevel, areas[0].y), displayName + "" spawn area"");") + ")"), '${1} if (map != null) map.DiscoverLocation(Vector3.zero, Minimap.PinType.Icon3, "", false);'),
    @("F17 the delete patch takes pins not shown on the map", "SpawnFinder.cs", "[ \t]*if \(pin\.m_uiElement == null \|\| !pin\.m_uiElement\.gameObject\.activeInHierarchy\)\r?\n[ \t]*continue;\r?\n", ""),
    # Always track nearest watched: every value its decisions are given, which way the code branches on them, and
    # what may start, end or take over a wait.
    @("N1 the re-track chooses by the list's star filter", "NearestWatched.cs", [regex]::Escape("StarSets.Accepts(WatchAlerts.EffectiveAlertStars"), "StarSets.Accepts(ModConfig.ListStars"),
    @("N2 the re-track takes tamed creatures", "NearestWatched.cs", [regex]::Escape("character.IsTamed(),"), "false,"),
    @("N3 a loss schedules a re-track with the option off", "NearestWatched.cs", [regex]::Escape("Pending.Lost(prefab, ModConfig.AlwaysTrackNearest.Value,"), "Pending.Lost(prefab, true,"),
    @("N4 the player's own Stop schedules a re-track", "Tracker.cs", "(public static void Stop\(\)\r?\n\s*\{\r?\n)", '${1}            NearestWatched.Lost(_targetPrefab, _targetTamed);' + "`n"),
    @("N5 a lost creature schedules nothing", "Tracker.cs", "[ \t]*NearestWatched\.Lost\(_targetPrefab, _targetTamed\);[^\r\n]*\r?\n", ""),
    @("N6 the wait does not give way to other tracking", "NearestWatched.cs", [regex]::Escape("player.IsDead(), Tracker.IsTracking,"), "player.IsDead(), false,"),
    @("N7 turning the option off does not end the wait", "NearestWatched.cs", [regex]::Escape("Tracker.IsTracking, ModConfig.AlwaysTrackNearest.Value,"), "Tracker.IsTracking, true,"),
    @("N8 the component is never added", "Plugin.cs", "[ \t]*gameObject\.AddComponent<NearestWatched>\(\);\r?\n", ""),
    @("N9 Stop tracking cannot call off the wait", "EntityListWindow.cs", "[ \t]*NearestWatched\.Cancel\(\);\r?\n", ""),
    @("N10 the re-track ignores AlertRadius", "NearestWatched.cs", [regex]::Escape("Rules.WithinRadius(distance, ModConfig.AlertRadius.Value),"), "true,"),
    @("N11 the re-track takes only tamed creatures", "NearestWatched.cs", [regex]::Escape("character.IsTamed(),"), "!character.IsTamed(),"),
    @("N12 the re-track takes only the stars the Alerts filter leaves out", "NearestWatched.cs", [regex]::Escape("StarSets.Accepts(WatchAlerts.EffectiveAlertStars, character.GetLevel()),"), "!StarSets.Accepts(WatchAlerts.EffectiveAlertStars, character.GetLevel()),"),
    @("N13 the re-track takes only creatures outside AlertRadius", "NearestWatched.cs", [regex]::Escape("Rules.WithinRadius(distance, ModConfig.AlertRadius.Value),"), "!Rules.WithinRadius(distance, ModConfig.AlertRadius.Value),"),
    @("N14 the wait ends whenever nothing is tracked - it never re-tracks", "NearestWatched.cs", [regex]::Escape("player.IsDead(), Tracker.IsTracking,"), "player.IsDead(), !Tracker.IsTracking,"),
    @("N15 the wait ends while the option is on", "NearestWatched.cs", [regex]::Escape("Tracker.IsTracking, ModConfig.AlwaysTrackNearest.Value,"), "Tracker.IsTracking, !ModConfig.AlwaysTrackNearest.Value,"),
    @("N17 emptying the watchlist does not end the wait", "NearestWatched.cs", [regex]::Escape("ModConfig.Watchlist.Count))"), "1))"),
    @("N18 Track never records the prefab - a loss named after the previous target, and after a Find area no wait at all", "Tracker.cs", "[ \t]*_targetPrefab = Creature\.PrefabName\(character\);\r?\n", ""),
    @("N19 no 5 s wait: the loss is stamped at time 0", "NearestWatched.cs", [regex]::Escape("ModConfig.Watchlist.Count, Time.time);"), "ModConfig.Watchlist.Count, 0f);"),
    @("N20 it looks on every frame it is not yet time to", "NearestWatched.cs", [regex]::Escape("if (!Pending.ShouldLook(Time.time))"), "if (Pending.ShouldLook(Time.time))"),
    @("N21 a loss schedules only with the option off", "NearestWatched.cs", [regex]::Escape("Pending.Lost(prefab, ModConfig.AlwaysTrackNearest.Value,"), "Pending.Lost(prefab, !ModConfig.AlwaysTrackNearest.Value,"),
    @("N23 Stop tracking shows only when nothing is pending", "EntityListWindow.cs", [regex]::Escape("(Tracker.IsTracking || NearestWatched.IsPending)"), "(Tracker.IsTracking || !NearestWatched.IsPending)"),
    @("N24 the re-track looks at dead and player entries", "NearestWatched.cs", "[ \t]*if \(!Creature\.IsListable\(character\)\)\r?\n[ \t]*continue;\r?\n", ""),
    @("N25 logging out schedules a re-track", "Tracker.cs", [regex]::Escape("Stop(); // logged out; nobody to tell"), "{ Stop(); NearestWatched.Lost(_targetPrefab, _targetTamed); }"),
    @("N26 the candidate test inverted", "NearestWatched.cs", [regex]::Escape("if (Retrack.IsCandidate("), "if (!Retrack.IsCandidate("),
    @("N27 the end-of-wait test inverted", "NearestWatched.cs", [regex]::Escape("player == null || Retrack.EndsWait("), "player == null || !Retrack.EndsWait("),
    @("N28 a watch alert takes the arrow during the wait", "WatchAlerts.cs", [regex]::Escape("sameSide && !NearestWatched.IsPending)"), "sameSide)"),
    @("N30 a tamed creature's loss handed over as wild - its loss line drops 'tamed'", "Tracker.cs", [regex]::Escape("NearestWatched.Lost(_targetPrefab, _targetTamed);"), "NearestWatched.Lost(_targetPrefab, false);"),
    @("N31 the re-track takes a creature the game is removing", "NearestWatched.cs", [regex]::Escape("character.GetZDOID() != ZDOID.None,"), "true,"),
    @("N32 a dead player's wait goes on", "NearestWatched.cs", [regex]::Escape("Retrack.EndsWait(player.IsDead(),"), "Retrack.EndsWait(false,"),
    @("N33 TamedNow without its network guard - the tameness read in the frame the game removes the creature", "Tracker.cs", [regex]::Escape("if (_targetTamed || Target.GetZDOID() == ZDOID.None)"), "if (_targetTamed)"),
    @("N35 the tameness read inverted - a creature tracked wild counts as tamed at once, its tracking ended in its first frame", "Tracker.cs", [regex]::Escape("_targetTamed = Target.IsTamed();"), "_targetTamed = !Target.IsTamed();"),
    @("N36 the tameness read a constant - every creature tracked wild 'tamed' in its first frame", "Tracker.cs", [regex]::Escape("_targetTamed = Target.IsTamed();"), "_targetTamed = true;"),
    @("N37 the network guard reads the local player, not the tracked creature", "Tracker.cs", [regex]::Escape("Target.GetZDOID() == ZDOID.None"), "Player.m_localPlayer.GetZDOID() == ZDOID.None"),
    @("N38 a loss passes a constant type", "NearestWatched.cs", [regex]::Escape("Pending.Lost(prefab,"), 'Pending.Lost("",'),
    @("N39 a loss passes the type lower-cased - the took line names it wrongly", "NearestWatched.cs", [regex]::Escape("Pending.Lost(prefab,"), "Pending.Lost(prefab.ToLowerInvariant(),"),
    @("N41 the end of the wait returns without cancelling - it only pauses", "NearestWatched.cs", "(ModConfig\.Watchlist\.Count\)\)\r?\n\s*\{\r?\n)\s*Pending\.Cancel\(\);\r?\n", '${1}'),
    @("N42 no player only pauses the wait - it survives into the next world", "NearestWatched.cs", [regex]::Escape("if (player == null || Retrack.EndsWait("), "if (player == null) return; if (Retrack.EndsWait("),
    @("N43 the nearest comparison inverted - never picks anything", "NearestWatched.cs", [regex]::Escape("&& distance < nearestDistance)"), "&& distance > nearestDistance)"),
    @("N44 the nearest distance never updated - takes the last candidate in list order", "NearestWatched.cs", "[ \t]*nearestDistance = distance;\r?\n", ""),
    @("N45 distance from the player to the player - radius and nearest ignored", "NearestWatched.cs", [regex]::Escape("Vector3.Distance(from, character.transform.position)"), "Vector3.Distance(from, from)"),
    @("N46 Track records the display name as the type - a starred creature's loss named by its stars ('lost Boar *')", "Tracker.cs", [regex]::Escape("_targetPrefab = Creature.PrefabName(character);"), "_targetPrefab = Creature.DisplayName(character);"),
    @("N47 the networked test reads the player", "NearestWatched.cs", [regex]::Escape("character.GetZDOID() != ZDOID.None,"), "player.GetZDOID() != ZDOID.None,"),
    @("N48 the star test reads the player's level", "NearestWatched.cs", [regex]::Escape("StarSets.Accepts(WatchAlerts.EffectiveAlertStars, character.GetLevel())"), "StarSets.Accepts(WatchAlerts.EffectiveAlertStars, player.GetLevel())"),
    @("N49 the tamed test reads the player", "NearestWatched.cs", [regex]::Escape("character.IsTamed(),"), "player.IsTamed(),"),
    @("N51 IsPending always false - Stop tracking hidden during a wait", "NearestWatched.cs", [regex]::Escape("get { return Pending.IsPending; }"), "get { return false; }"),
    @("N52 Cancel emptied - Stop tracking cannot call the wait off", "NearestWatched.cs", "(MobTrackerPlugin\.Log\.LogInfo\(Pending\.EndedLine\(Time\.time, ""Stop tracking""\)\);\r?\n)\s*Pending\.Cancel\(\);\r?\n", '${1}'),
    @("N54 Stop tracking starts the wait again", "NearestWatched.cs", "(MobTrackerPlugin\.Log\.LogInfo\(Pending\.EndedLine\(Time\.time, ""Stop tracking""\)\);\r?\n\s*)Pending\.Cancel\(\);", '${1}Pending.Lost(Pending.Prefab, true, ModConfig.Watchlist.Count, Time.time);'),
    @("N55 Track records tameness inverted", "Tracker.cs", [regex]::Escape("_targetTamed = character.IsTamed();"), "_targetTamed = !character.IsTamed();"),
    @("N56 the re-track ignores the Alerts stars", "NearestWatched.cs", [regex]::Escape("StarSets.Accepts(WatchAlerts.EffectiveAlertStars, character.GetLevel()),"), "true,"),
    # Since 0.6.0: the nearest creature of any watched type.
    @("N57 the re-track takes unwatched creatures too", "NearestWatched.cs", [regex]::Escape("ModConfig.Watchlist.Contains(Creature.PrefabName(character)),"), "true,"),
    @("N58 the re-track takes only the lost type again (0.5.1)", "NearestWatched.cs", [regex]::Escape("ModConfig.Watchlist.Contains(Creature.PrefabName(character)),"), "string.Equals(Creature.PrefabName(character), Pending.Prefab, System.StringComparison.Ordinal),"),
    @("N59 the watchlist asked about the lost type, not the creature - every creature a candidate", "NearestWatched.cs", [regex]::Escape("ModConfig.Watchlist.Contains(Creature.PrefabName(character))"), "ModConfig.Watchlist.Contains(Pending.Prefab)"),
    @("N60 a watched type and the lost one - the lost type only", "NearestWatched.cs", [regex]::Escape("ModConfig.Watchlist.Contains(Creature.PrefabName(character)),"), "ModConfig.Watchlist.Contains(Creature.PrefabName(character)) && Creature.PrefabName(character) == Pending.Prefab,"),
    @("N61 the first candidate in list order wins (break)", "NearestWatched.cs", "([ \t]*nearestDistance = distance;\r?\n)", ('${1}                    break;' + "`r`n")),
    @("N62 the first candidate in list order wins (continue once one is kept)", "NearestWatched.cs", "(if \(!Creature\.IsListable\(character\)\)\r?\n[ \t]*continue;\r?\n)", ('${1}                if (nearest != null) continue;' + "`r`n")),
    @("N63 unwatching the lost type ends the wait again", "NearestWatched.cs", [regex]::Escape("ModConfig.Watchlist.Count))"), "(ModConfig.Watchlist.Contains(Pending.Prefab) ? 1 : 0)))"),
    @("N64 the wait counts the loaded creatures, not the watched types", "NearestWatched.cs", [regex]::Escape("ModConfig.Watchlist.Count))"), "Character.GetAllCharacters().Count))"),
    @("N65 the deferral inverted - auto-track only during a wait", "WatchAlerts.cs", [regex]::Escape("&& !NearestWatched.IsPending)"), "&& NearestWatched.IsPending)"),
    @("N66 the took line given no distance", "NearestWatched.cs", [regex]::Escape("Pending.TookLine(Creature.DisplayName(nearest), nearestDistance, Time.time)"), "Pending.TookLine(Creature.DisplayName(nearest), 0f, Time.time)"),
    @("N67 the took line names the player", "NearestWatched.cs", [regex]::Escape("Creature.DisplayName(nearest)"), "Creature.DisplayName(player)"),
    @("N68 the took line before the empty-look return - written on every look, about a null creature", "NearestWatched.cs", "(?s)([ \t]*if \(nearest == null\)\r?\n[ \t]*\{\r?\n[^\r\n]*\r?\n[ \t]*return;\r?\n[ \t]*\}\r?\n\r?\n)([ \t]*MobTrackerPlugin\.Log\.LogInfo\([^\r\n]*\r?\n)", '${2}${1}'),
    @("N69 the nearest test is <= - the last of equally near candidates wins", "NearestWatched.cs", [regex]::Escape("&& distance < nearestDistance)"), "&& distance <= nearestDistance)"),
    # The log lines (0.6.0).
    @("N70 the loss line built before the loss is recorded - a wait logs 'no wait'", "NearestWatched.cs", "([ \t]*Pending\.Lost\(prefab,[^\r\n]*\r?\n)([ \t]*string line = Pending\.LostLine\([^;]*;\r?\n)", '${2}${1}'),
    @("N71 the loss line never written", "NearestWatched.cs", [regex]::Escape("MobTrackerPlugin.Log.LogInfo(line);"), "{ }"),
    @("N72 the loss line told the option is off - no 'no wait' line", "NearestWatched.cs", [regex]::Escape("Pending.LostLine(prefab, tamed, ModConfig.AlwaysTrackNearest.Value,"), "Pending.LostLine(prefab, tamed, false,"),
    @("N73 every loss called tamed in its line", "NearestWatched.cs", [regex]::Escape("Pending.LostLine(prefab, tamed,"), "Pending.LostLine(prefab, true,"),
    @("N74 Stop tracking's line written when no wait is on", "NearestWatched.cs", "[ \t]*if \(Pending\.IsPending\)\r?\n", ""),
    @("N75 the end reason never sees the tracking", "NearestWatched.cs", [regex]::Escape("Retrack.EndReason(ModConfig.AlwaysTrackNearest.Value, Tracker.IsTracking,"), "Retrack.EndReason(ModConfig.AlwaysTrackNearest.Value, false,"),
    @("N76 the end reason told the option is on", "NearestWatched.cs", [regex]::Escape("Retrack.EndReason(ModConfig.AlwaysTrackNearest.Value,"), "Retrack.EndReason(true,"),
    @("N77 the end reason given an empty watchlist", "NearestWatched.cs", [regex]::Escape("Rules.FormatWatchlist(ModConfig.Watchlist))));"), '"")));'),
    @("N78 the took line's seconds counted from the start of the game", "NearestWatched.cs", [regex]::Escape("nearestDistance, Time.time));"), "nearestDistance, 0f));"),
    @("N79 the took line names the prefab, not what the label shows", "NearestWatched.cs", [regex]::Escape("Creature.DisplayName(nearest)"), "Creature.PrefabName(nearest)"),
    @("N80 Stop tracking's line after the cancel - never written", "NearestWatched.cs", "([ \t]*if \(Pending\.IsPending\)\r?\n[^\r\n]*\r?\n)([ \t]*Pending\.Cancel\(\);\r?\n)", '${2}${1}'),
    @("N81 the loss line given an empty watchlist - every waiting line says it watches nothing", "NearestWatched.cs", "(Rules\.FormatWatchlist\()ModConfig\.Watchlist(\)\);\r?\n[ \t]*if \(line != null\))", '${1}new string[0]${2}'),
    @("N82 the end line's seconds counted from the start of the game", "NearestWatched.cs", "(Pending\.EndedLine\()Time\.time(,\r?\n)", '${1}0f${2}'),
    # Since 0.6.0, more spellings: the same-type rule, the nearest test, the loop from the last element, a line per empty
    # look, EndsWait's count, the deferral moved above the alert, the log lines.
    @("N83 the same-type rule back: a local holding Pending.Prefab and a != guard in the loop", "NearestWatched.cs", '(?s)([ \t]*)(Character nearest = null;\r?\n.*?if \(!Creature\.IsListable\(character\)\)\r?\n[ \t]*continue;\r?\n)', ('${1}string lost = Pending.Prefab;' + "`r`n" + '${1}${2}                if (Creature.PrefabName(character) != lost) continue;' + "`r`n")),
    @("N84 the same-type rule back: string.CompareOrdinal as the candidate's watched value", "NearestWatched.cs", [regex]::Escape("ModConfig.Watchlist.Contains(Creature.PrefabName(character)),"), 'string.CompareOrdinal(Creature.PrefabName(character), Pending.Prefab) == 0,'),
    @("N85 the same-type rule back: ToLower() on both sides as the candidate's watched value", "NearestWatched.cs", [regex]::Escape("ModConfig.Watchlist.Contains(Creature.PrefabName(character)),"), 'string.Equals(Creature.PrefabName(character).ToLower(), Pending.Prefab.ToLower()),'),
    @("N86 the same-type rule back through a helper given as the candidate's watched value", "NearestWatched.cs", '(?s)([ \t]*private void Update\(\)\r?\n.*?)ModConfig\.Watchlist\.Contains\(Creature\.PrefabName\(character\)\),', ('        private static bool Wanted(Character c) { return ModConfig.Watchlist.Contains(Creature.PrefabName(c)) && Creature.PrefabName(c) == Pending.Prefab; }' + "`r`n" + '${1}Wanted(character),')),
    @("N87 the nearest test <= spelled !(distance > nearestDistance)", "NearestWatched.cs", [regex]::Escape("&& distance < nearestDistance)"), '&& !(distance > nearestDistance))'),
    @("N88 the nearest test <= spelled nearestDistance >= distance", "NearestWatched.cs", [regex]::Escape("&& distance < nearestDistance)"), '&& nearestDistance >= distance)'),
    @("N89 the creature loop from the last element (a for loop)", "NearestWatched.cs", '([ \t]*)foreach \(Character character in Character\.GetAllCharacters\(\)\)\r?\n[ \t]*\{\r?\n', ('${1}var all = Character.GetAllCharacters();' + "`r`n" + '${1}for (int i = all.Count - 1; i >= 0; i--)' + "`r`n" + '${1}{' + "`r`n" + '${1}    Character character = all[i];' + "`r`n")),
    @("N90 a line on every empty look", "NearestWatched.cs", '([ \t]*Events\.EmptyLook\(from, playerInside\);[^\r\n]*\r?\n)', ('${1}                MobTrackerPlugin.Log.LogInfo(Retrack.LogPrefix + "nothing to take yet");' + "`r`n")),
    @("N91 EndsWait given the watchlist's count less one - one watched type left ends the wait", "NearestWatched.cs", [regex]::Escape("ModConfig.Watchlist.Count))"), 'ModConfig.Watchlist.Count - 1))'),
    @("N92 the deferral moved above the alert - no alert and no ding during a wait", "WatchAlerts.cs", '(?s)([ \t]*string text = Creature\.DisplayName\(nearest\).*?if \(sameSide) && !NearestWatched\.IsPending\)', ('            if (NearestWatched.IsPending) return;' + "`r`n" + '${1})')),
    @("N93 the end reason asks IsTrackingCreature - a wait ended by Find area logged as a death", "NearestWatched.cs", [regex]::Escape("Retrack.EndReason(ModConfig.AlwaysTrackNearest.Value, Tracker.IsTracking,"), 'Retrack.EndReason(ModConfig.AlwaysTrackNearest.Value, Tracker.IsTrackingCreature,'),
    @("N94 the loss line told the option is on - a line with it off", "NearestWatched.cs", [regex]::Escape("Pending.LostLine(prefab, tamed, ModConfig.AlwaysTrackNearest.Value,"), 'Pending.LostLine(prefab, tamed, true,'),
    @("N95 the loss line's null test inverted", "NearestWatched.cs", [regex]::Escape("if (line != null)"), 'if (line == null)'),
    @("N96 Stop tracking's line only when no wait is on", "NearestWatched.cs", 'if \(Pending\.IsPending\)(\r?\n[ \t]*MobTrackerPlugin\.Log\.LogInfo\(Pending\.EndedLine\(Time\.time, "Stop tracking"\)\);)', 'if (!Pending.IsPending)${1}'),
    @("N97 the alert poll's catch writes + e - a null test before the traced Track call", "WatchAlerts.cs", [regex]::Escape(" + e.ToString());"), ' + e);'),
    # Since 0.6.0: Update's opening guard, the creature loop's branches, what it enumerates and what IsListable is given,
    # a line at any level, and the start of Lost.
    @("N98 Update's opening 'if (!Pending.IsPending) return;' deleted - an end line every frame without a wait", "NearestWatched.cs", '(private void Update\(\)\r?\n[ \t]*\{\r?\n)[ \t]*if \(!Pending\.IsPending\)\r?\n[ \t]*return;\r?\n\r?\n', '${1}'),
    @("N99 Update's opening guard inverted - the wait never looks, and an end line every frame without one", "NearestWatched.cs", [regex]::Escape("if (!Pending.IsPending)"), 'if (Pending.IsPending)'),
    @("N100 the same-type rule back through a private helper and a continue (0.5.1's choice)", "NearestWatched.cs", '(?s)([ \t]*private void Update\(\)\r?\n.*?if \(!Creature\.IsListable\(character\)\)\r?\n[ \t]*continue;\r?\n)', ('        private static bool OfLostType(Character c) { return string.Equals(Creature.PrefabName(c), Pending.Prefab, System.StringComparison.Ordinal); }' + "`r`n" + '${1}                if (!OfLostType(character)) continue;' + "`r`n")),
    @("N101 the game's creature list reversed in place before the loop - the last of equally near ones wins", "NearestWatched.cs", '([ \t]*)foreach \(Character character in Character\.GetAllCharacters\(\)\)', ('${1}var all = Character.GetAllCharacters();' + "`r`n" + '${1}all.Reverse();' + "`r`n" + '${1}foreach (Character character in all)')),
    @("N102 a Message line on every look", "NearestWatched.cs", '(if \(!Pending\.ShouldLook\(Time\.time\)\)\r?\n[ \t]*return;\r?\n)', ('${1}            MobTrackerPlugin.Log.LogMessage(Retrack.LogPrefix + "looking");' + "`r`n")),
    @("N103 a Debug line on every look", "NearestWatched.cs", '(if \(!Pending\.ShouldLook\(Time\.time\)\)\r?\n[ \t]*return;\r?\n)', ('${1}            MobTrackerPlugin.Log.LogDebug(Retrack.LogPrefix + "looking");' + "`r`n")),
    @("N104 a line at the start of Lost - also with the option off", "NearestWatched.cs", '(public static void Lost\(string prefab, bool tamed\)\r?\n[ \t]*\{\r?\n)', ('${1}            MobTrackerPlugin.Log.LogInfo(Retrack.LogPrefix + "lost " + prefab);' + "`r`n")),
    @("N105 the old tamed gate back as an early return in Lost - a tamed loss starts no wait and writes no line", "NearestWatched.cs", '(public static void Lost\(string prefab, bool tamed\)\r?\n[ \t]*\{\r?\n)', ('${1}            if (tamed) return;' + "`r`n")),
    @("N106 the same-type rule back with no extra branch: a helper hands IsListable null for any other type", "NearestWatched.cs", '(?s)([ \t]*private void Update\(\)\r?\n.*?)if \(!Creature\.IsListable\(character\)\)', ('        private static Character OfLostTypeOrNull(Character c) { return Creature.IsListable(c) && string.Equals(Creature.PrefabName(c), Pending.Prefab, System.StringComparison.Ordinal) ? c : null; }' + "`r`n" + '${1}if (!Creature.IsListable(OfLostTypeOrNull(character)))')),
    @("N107 Stop tracking's line counts from the start of the game", "NearestWatched.cs", [regex]::Escape('Pending.EndedLine(Time.time, "Stop tracking")'), 'Pending.EndedLine(0f, "Stop tracking")'),
    # Since 0.6.0: a statement added between the checked stretches of Update - a return, a second cancel, a line by
    # another route.
    @("N108 the wait pauses while something is tracked instead of ending - Untrack brings the old wait back", "NearestWatched.cs", '(if \(!Pending\.IsPending\)\r?\n[ \t]*return;\r?\n)', ('${1}            if (Tracker.IsTracking) return;' + "`r`n")),
    @("N109 the re-track takes nothing with Auto-track off - a return after ShouldLook", "NearestWatched.cs", '(if \(!Pending\.ShouldLook\(Time\.time\)\)\r?\n[ \t]*return;\r?\n)', ('${1}            if (!ModConfig.AutoTrack.Value) return;' + "`r`n")),
    @("N110 with Auto-track off the wait neither ends nor looks - a return after the opening guard", "NearestWatched.cs", '(if \(!Pending\.IsPending\)\r?\n[ \t]*return;\r?\n)', ('${1}            if (!ModConfig.AutoTrack.Value) return;' + "`r`n")),
    @("N111 a line on every look, through a private helper", "NearestWatched.cs", '(?s)([ \t]*private void Update\(\)\r?\n.*?if \(!Pending\.ShouldLook\(Time\.time\)\)\r?\n[ \t]*return;\r?\n)', ('        private static void Say(string s) { MobTrackerPlugin.Log.LogInfo(s); }' + "`r`n" + '${1}            Say(Retrack.LogPrefix + "looking");' + "`r`n")),
    @("N112 a line on every look, through UnityEngine.Debug.Log", "NearestWatched.cs", '(if \(!Pending\.ShouldLook\(Time\.time\)\)\r?\n[ \t]*return;\r?\n)', ('${1}            Debug.Log(Retrack.LogPrefix + "looking");' + "`r`n")),
    @("N114 a verbose line on every look, through ModLog.Event", "NearestWatched.cs", '(if \(!Pending\.ShouldLook\(Time\.time\)\)\r?\n[ \t]*return;\r?\n)', ('${1}            ModLog.Event(Retrack.LogPrefix + "looking");' + "`r`n")),
    @("N115 the empty look's verbose line on every look, before the loop", "NearestWatched.cs", '(if \(!Pending\.ShouldLook\(Time\.time\)\)\r?\n[ \t]*return;\r?\n\r?\n[ \t]*Vector3 from = player\.transform\.position;\r?\n[^\r\n]*\r?\n[ \t]*bool playerInside = Character\.InInterior\(from\);\r?\n)', ('${1}            Events.EmptyLook(from, playerInside);' + "`r`n")),
    @("N113 each look cancels the wait before the loop - after one empty look it gives up, with no line", "NearestWatched.cs", '([ \t]*)(foreach \(Character character in Character\.GetAllCharacters\(\)\))', ('${1}Pending.Cancel();' + "`r`n" + '${1}${2}')),
    # Since 0.8.0: any tracked creature's loss starts the wait while something is watched - Retrack.Lost is handed the
    # watchlist's count, never whether it holds the lost type, nor the tameness. The old gates put back by another route,
    # a count that is not the watchlist's, and a wait started by what must never start one. (N22, N34 and N40 went with
    # the old gates' code.)
    @("N116 the old watched-type gate back - a loss of a type not watched starts no wait", "NearestWatched.cs", [regex]::Escape("ModConfig.Watchlist.Count, Time.time);"), "(ModConfig.Watchlist.Contains(prefab) ? ModConfig.Watchlist.Count : 0), Time.time);"),
    @("N117 the old tamed gate back - the count zeroed for a tamed loss", "NearestWatched.cs", [regex]::Escape("ModConfig.Watchlist.Count, Time.time);"), "(tamed ? 0 : ModConfig.Watchlist.Count), Time.time);"),
    @("N118 the old tamed gate back through Tracker - a tamed loss hands over no type", "Tracker.cs", [regex]::Escape("NearestWatched.Lost(_targetPrefab, _targetTamed);"), 'NearestWatched.Lost(_targetTamed ? "" : _targetPrefab, _targetTamed);'),
    @("N119 a loss given a constant count - a wait starts with nothing watched", "NearestWatched.cs", [regex]::Escape("ModConfig.Watchlist.Count, Time.time);"), "1, Time.time);"),
    @("N120 a loss given the loaded creatures' count - a wait starts with nothing watched", "NearestWatched.cs", [regex]::Escape("ModConfig.Watchlist.Count, Time.time);"), "Character.GetAllCharacters().Count, Time.time);"),
    @("N121 the old watched-type gate back as an early return in Lost - no wait and no line for a type not watched", "NearestWatched.cs", '(public static void Lost\(string prefab, bool tamed\)\r?\n[ \t]*\{\r?\n)', ('${1}            if (!ModConfig.Watchlist.Contains(prefab ?? "")) return;' + "`r`n")),
    @("N122 the old watched-type gate back after the prologue - no wait for a type not watched, and its line blames the empty watchlist", "NearestWatched.cs", '([ \t]*)(Pending\.Lost\(prefab, ModConfig\.AlwaysTrackNearest\.Value,)', ('${1}if (ModConfig.Watchlist.Contains(prefab))' + "`r`n" + '${1}    ${2}')),
    @("N123 Stop tracking in the window starts a wait", "EntityListWindow.cs", "([ \t]*NearestWatched\.Cancel\(\);)", '${1} NearestWatched.Lost("Boar", false);'),
    @("N124 tracking a creature by hand starts a wait for the one it replaces", "Tracker.cs", [regex]::Escape("Events.TrackStarting(character);"), "Events.TrackStarting(character); NearestWatched.Lost(_targetPrefab, _targetTamed);"),
    @("N125 Find area starts a wait for the creature it replaces", "Tracker.cs", [regex]::Escape("Events.TrackStartingArea(point, name);"), "Events.TrackStartingArea(point, name); NearestWatched.Lost(_targetPrefab, _targetTamed);"),
    # Since 0.8.0: what a loss hands on is written only where a tracking starts (Track, TrackPoint) and in the taming test
    # (TamedNow) - a second write in Track, or a clear on every frame in LateUpdate, would bring the dropped gates back.
    @("N126 Track records no type for a creature not watched - the watched-type gate back through Track (its loss logs 'type is not known', no wait)", "Tracker.cs", [regex]::Escape("_targetPrefab = Creature.PrefabName(character);"), "_targetPrefab = Creature.PrefabName(character); if (!ModConfig.Watchlist.Contains(_targetPrefab)) _targetPrefab = null;"),
    @("N127 Track records no type for a tamed creature - the tamed gate back through Track", "Tracker.cs", [regex]::Escape("_targetTamed = character.IsTamed();"), "_targetTamed = character.IsTamed(); if (_targetTamed) _targetPrefab = null;"),
    @("N128 LateUpdate clears the recorded type of a tamed creature every frame, before the lost test - the tamed gate back", "Tracker.cs", [regex]::Escape("Stop(); // logged out; nobody to tell"), ("Stop(); // logged out; nobody to tell" + "`r`n" + "            if (_targetTamed) _targetPrefab = null;")),
    @("N129 LateUpdate clears the recorded type of a creature not watched every frame, before the lost test - the watched-type gate back", "Tracker.cs", [regex]::Escape("Stop(); // logged out; nobody to tell"), ("Stop(); // logged out; nobody to tell" + "`r`n" + "            if (_targetPrefab != null && !ModConfig.Watchlist.Contains(_targetPrefab)) _targetPrefab = null;")),
    # Since 0.8.0: a creature tracked wild and tamed now is lost to the tracking (Tracker.TamedNow, the lost test's last
    # question) - its message says so, Stop, and NearestWatched.Lost decides the wait; one tamed when its tracking began is
    # not asked. (E50 went with the tamed refresh it moved.)
    @("TM1 taming never ends the tracking - TamedNow keeps the tameness but answers false", "Tracker.cs", '(Events\.Tamed\(\);[^\r\n]*\r?\n[ \t]*)return _targetTamed;', '${1}return false;'),
    @("TM2 the taming test dropped from the lost block - a creature tamed while tracked stays tracked", "Tracker.cs", [regex]::Escape(" || (tamedNow = TamedNow())"), ""),
    @("TM3 taming ends the tracking without the wait - TamedNow stops it itself and answers false", "Tracker.cs", '([ \t]*)Events\.Tamed\(\);[^\r\n]*', '${1}{ Events.Tamed(); Stop(); return false; }'),
    @("TM4 taming ends the tracking without the wait - the lost block skips NearestWatched.Lost for a taming", "Tracker.cs", [regex]::Escape("NearestWatched.Lost(_targetPrefab, _targetTamed);"), "if (!tamedNow) NearestWatched.Lost(_targetPrefab, _targetTamed);"),
    @("TM5 a creature tamed before its tracking began is lost at once - TamedNow asks it too", "Tracker.cs", [regex]::Escape("if (_targetTamed || Target.GetZDOID() == ZDOID.None)"), "if (Target.GetZDOID() == ZDOID.None)"),
    @("TM6 the taming's message says nothing of it - 'Lost track of' as for a death", "Tracker.cs", [regex]::Escape("Rules.LostTrackMessage(_targetName, tamedNow)"), "Rules.LostTrackMessage(_targetName, false)"),
    @("TM7 no message at a taming", "Tracker.cs", '(if \(MessageHud\.instance != null)(\)\r?\n[ \t]*MessageHud\.instance\.ShowMessage\(MessageHud\.MessageType\.TopLeft, Rules\.LostTrackMessage)', '${1} && !tamedNow${2}'),
    @("TM8 the taming's verbose line dropped", "Tracker.cs", '[ \t]*if \(_targetTamed\)\r?\n[ \t]*Events\.Tamed\(\);[^\r\n]*\r?\n', ''),
    @("TM9 the message's local starts true - every loss's message says it was tamed", "Tracker.cs", [regex]::Escape("bool tamedNow = false;"), "bool tamedNow = true;"),
    @("TM10 the taming test reads the local player's tameness", "Tracker.cs", [regex]::Escape("_targetTamed = Target.IsTamed();"), "_targetTamed = Player.m_localPlayer.IsTamed();"),
    @("TM11 the taming line told the option is on - 'Always track nearest watched is off' never said", "Events.cs", [regex]::Escape("EventLines.TrackTamed(Tracker.Tracked, ModConfig.AlwaysTrackNearest.Value)"), "EventLines.TrackTamed(Tracker.Tracked, true)"),
    @("TM12 the taming line keeps the empty-look memory - a wait after a taming may not write its first empty look", "Events.cs", '[ \t]*_lastEmptyLook = null;[^\r\n]*\r?\n([ \t]*ModLog\.Event\(EventLines\.TrackTamed)', '${1}'),
    @("TM13 OnGUI asks TamedNow too - a taming it reads first is kept and never ends the tracking", "Tracker.cs", [regex]::Escape("if (!IsTracking || _guideHidden)"), "if (!IsTracking || _guideHidden || (!_isPoint && TamedNow()))"),
    @("TM14 the taming's verbose line on every frame a creature tracked wild stays wild", "Tracker.cs", '(if \()_targetTamed(\)\r?\n[ \t]*Events\.Tamed\(\);)', '${1}true${2}'),
    # Since 0.8.0: what the lost block's own shape does not reach - Stop, which runs between the lost test and
    # NearestWatched.Lost, and LateUpdate's every frame, writing the type through an out argument (its address taken,
    # not a store); the getter the loss line's tameness comes from; a cancel or a Stop just after the block, the
    # logged-out test moved below it, and a cancel in the alert poll.
    @("N134 Stop spells the type as the watchlist does, through an out argument - a type not watched handed over as none (the watched-type gate back)", "Tracker.cs", '(?s)(public static void Stop\(\).*?Generation\+\+;)', ('${1}' + "`r`n" + '            ModConfig.Watchlist.TryGetValue(_targetPrefab ?? "", out _targetPrefab);')),
    @("N135 LateUpdate spells the type as the watchlist does on every frame, through an out argument - the watched-type gate back", "Tracker.cs", [regex]::Escape("Stop(); // logged out; nobody to tell"), ("Stop(); // logged out; nobody to tell" + "`r`n" + '            if (IsTracking && !_isPoint && _targetPrefab != null) ModConfig.Watchlist.TryGetValue(_targetPrefab, out _targetPrefab);')),
    @("TM16 TargetTamed always false - the verbose loss line never says the creature was tamed", "Tracker.cs", [regex]::Escape("get { return _targetTamed; }"), "get { return false; }"),
    @("TM17 TargetTamed inverted - the verbose loss line calls a wild creature tamed and a tamed one wild", "Tracker.cs", [regex]::Escape("get { return _targetTamed; }"), "get { return !_targetTamed; }"),
    @("N137 the old tamed gate back as a cancel just after the lost block - a tamed creature's wait starts and ends at once", "Tracker.cs", '(NearestWatched\.Lost\(_targetPrefab, _targetTamed\);[^\r\n]*\r?\n[ \t]*\})', ('${1}' + "`r`n" + '            if (_targetTamed && NearestWatched.IsPending) NearestWatched.Cancel();')),
    @("N138 the old watched-type gate back as a cancel just after the lost block - a wait for a type not watched ends at once", "Tracker.cs", '(NearestWatched\.Lost\(_targetPrefab, _targetTamed\);[^\r\n]*\r?\n[ \t]*\})', ('${1}' + "`r`n" + '            if (NearestWatched.IsPending && _targetPrefab != null && !ModConfig.Watchlist.Contains(_targetPrefab)) NearestWatched.Cancel();')),
    @("TM20 taming ends the tracking without the wait - a cancel just after the lost block", "Tracker.cs", '(NearestWatched\.Lost\(_targetPrefab, _targetTamed\);[^\r\n]*\r?\n[ \t]*\})', ('${1}' + "`r`n" + '            if (tamedNow) NearestWatched.Cancel();')),
    @("N139 the old tamed gate back in the alert poll - a tamed creature's wait cancelled at the next poll", "WatchAlerts.cs", [regex]::Escape("_nextPoll = Time.time + 1f;"), ("_nextPoll = Time.time + 1f;" + "`r`n" + '            if (Tracker.TargetTamed) NearestWatched.Cancel();')),
    @("TM21 a creature tamed when its tracking began is dropped at once - a Stop just after the lost block", "Tracker.cs", '(NearestWatched\.Lost\(_targetPrefab, _targetTamed\);[^\r\n]*\r?\n[ \t]*\})', ('${1}' + "`r`n" + '            if (IsTracking && !_isPoint && _targetTamed) Stop();')),
    @("N140 the logged-out test moved below the lost block - leaving the world loses the creature and starts a wait", "Tracker.cs", '(?s)([ \t]*if \(IsTracking && player == null\)\r?\n[ \t]*Stop\(\); // logged out; nobody to tell\r?\n)(.*?NearestWatched\.Lost\(_targetPrefab, _targetTamed\);[^\r\n]*\r?\n[ \t]*\}\r?\n)', '${2}${1}'),
    # Neither the re-track nor Auto-track crosses a dungeon entrance (a dungeon's interior is some 5 km up).
    @("L1 the re-track takes a creature across a dungeon entrance", "NearestWatched.cs", [regex]::Escape("Rules.SameLayer(character.InInterior(), playerInside))"), "true)"),
    @("L2 the re-track compares the player's side with itself", "NearestWatched.cs", [regex]::Escape("Rules.SameLayer(character.InInterior(),"), "Rules.SameLayer(player.InInterior(),"),
    @("L3 the re-track reads the creature's side for the player's too", "NearestWatched.cs", [regex]::Escape("Rules.SameLayer(character.InInterior(), playerInside)"), "Rules.SameLayer(character.InInterior(), character.InInterior())"),
    @("L4 the player's side a constant - outside, even in a dungeon", "NearestWatched.cs", [regex]::Escape("bool playerInside = Character.InInterior(from);"), "bool playerInside = false;"),
    @("L5 Auto-track crosses a dungeon entrance", "WatchAlerts.cs", [regex]::Escape("if (sameSide && !NearestWatched.IsPending)"), "if (!NearestWatched.IsPending)"),
    @("L6 Auto-track only across a dungeon entrance", "WatchAlerts.cs", [regex]::Escape("if (sameSide &&"), "if (!sameSide &&"),
    @("L7 Auto-track's test compares the player's side with itself", "WatchAlerts.cs", [regex]::Escape("Rules.SameLayer(nearest.InInterior(),"), "Rules.SameLayer(player.InInterior(),"),
    @("L8 Auto-track's test reads the creature's side for the player's too", "WatchAlerts.cs", [regex]::Escape("Character.InInterior(from))"), "Character.InInterior(nearest.transform.position))"),
    # Failure isolation: a creature with no ZNetView, and one that throws.
    @("I1 a creature with no ZNetView is listed", "Plugin.cs", [regex]::Escape("character.m_nview != null && "), ""),
    @("I2 only creatures with no ZNetView are listed", "Plugin.cs", [regex]::Escape("character.m_nview != null"), "character.m_nview == null"),
    @("I3 IsPlayer and IsDead asked before the ZNetView test", "Plugin.cs", [regex]::Escape("character != null && character.m_nview != null && !character.IsPlayer() && !character.IsDead()"), "character != null && !character.IsPlayer() && !character.IsDead() && character.m_nview != null"),
    @("I4 the alert poll's catch narrowed - a throw ends the poll again", "WatchAlerts.cs", [regex]::Escape("catch (System.Exception e)"), "catch (System.InvalidOperationException e)"),
    @("I5 no per-creature try - a throw ends the poll again", "WatchAlerts.cs", "(?s)try(\r?\n\s*\{.*?)catch \(System\.Exception e\)(\r?\n\s*\{)", 'if (true)${1}else if (false)${2} System.Exception e = null;'),
    @("I6 the failure logged on every poll", "WatchAlerts.cs", "[ \t]*_failureLogged = true;\r?\n", ""),
    @("I7 the alert poll takes only the creatures IsListable refuses", "WatchAlerts.cs", [regex]::Escape("if (!Creature.IsListable(character))"), "if (Creature.IsListable(character))"),
    @("I8 the list shows only the creatures IsListable refuses", "EntityListWindow.cs", [regex]::Escape("if (!Creature.IsListable(character) ||"), "if (Creature.IsListable(character) ||"),
    @("I9 the list never asks IsListable", "EntityListWindow.cs", [regex]::Escape("!Creature.IsListable(character) || "), ""),
    # The window (G: the sibling TomTom carve-out design uses W): no re-sorting under the pointer, a corner always on screen, GUI.matrix put back.
    @("G1 the pointer over the window no longer pauses the refresh", "EntityListWindow.cs", [regex]::Escape("Time.time >= _nextRefresh, Covers(ZInput.pointerPosition),"), "Time.time >= _nextRefresh, false,"),
    @("G2 a held mouse button no longer pauses the refresh", "EntityListWindow.cs", [regex]::Escape("GUIUtility.hotControl != 0))"), "false))"),
    @("G3 the player's own change waits for the pointer too", "EntityListWindow.cs", [regex]::Escape("Rules.ShouldRefresh(PlayerChanged(),"), "Rules.ShouldRefresh(false,"),
    @("G9 the refresh runs on every frame again", "EntityListWindow.cs", [regex]::Escape("Rules.ShouldRefresh(PlayerChanged(), Time.time >= _nextRefresh,"), "Rules.ShouldRefresh(PlayerChanged(), true,"),
    @("G10 a refresh the gate refused goes ahead", "EntityListWindow.cs", [regex]::Escape("if (!Rules.ShouldRefresh("), "if (Rules.ShouldRefresh("),
    @("G11 opening the window waits for the pointer to leave", "EntityListWindow.cs", [regex]::Escape("return _refreshNow || _query"), "return _query"),
    @("G5 the window can open off-screen again", "EntityListWindow.cs", "[ \t]*_rect\.x = Mathf\.Clamp\([^\r\n]*\r?\n[ \t]*_rect\.y = Mathf\.Clamp\([^\r\n]*\r?\n", ""),
    @("G6 the window leaves its scale on GUI.matrix", "EntityListWindow.cs", "(finally\r?\n\s*\{\r?\n)\s*GUI\.matrix = matrix;\r?\n", '${1}'),
    @("G7 the window puts back the identity, not the matrix it found", "EntityListWindow.cs", [regex]::Escape("GUI.matrix = matrix;"), "GUI.matrix = Matrix4x4.identity;"),
    @("G8 the HUD label leaves its scale on GUI.matrix", "Tracker.cs", "[ \t]*GUI\.matrix = matrix;\r?\n", ""),
    @("G12 the clamp's right bound in pixels, not GUI units - off-screen above 1080p", "EntityListWindow.cs", [regex]::Escape("Screen.width / scale - 60f"), "Screen.width - 60f"),
    @("G13 the clamp's lower bound in pixels, not GUI units - off-screen above 1080p", "EntityListWindow.cs", [regex]::Escape("Screen.height / scale - 40f"), "Screen.height - 40f"),
    @("G14 the vertical clamp reads the window's x - it cannot be dragged up or down", "EntityListWindow.cs", [regex]::Escape("_rect.y = Mathf.Clamp(_rect.y,"), "_rect.y = Mathf.Clamp(_rect.x,"),
    @("G15 the clamp's right bound multiplied by the scale", "EntityListWindow.cs", [regex]::Escape("Screen.width / scale - 60f"), "Screen.width * scale - 60f"),
    # The ding: only through the game's GUI mixer group, so the game's volume settings apply.
    @("D1 the ding bypasses the game's volume again", "Ding.cs", [regex]::Escape("if (_source == null || !Routed())"), "if (_source == null)"),
    @("D2 the ding plays only when it is not routed", "Ding.cs", [regex]::Escape("|| !Routed())"), "|| Routed())"),
    @("D3 the ding routed to the SFX group", "Ding.cs", '(?s)(FindMatchingGroups\("Master"\)\).*?)group\.name == "GUI"', '${1}group.name == "SFX"'),
    @("D4 the group taken from AudioMan.m_guiMixer (null in the game)", "Ding.cs", [regex]::Escape("AudioMixerGroup gui = FindGuiGroup();"), "AudioMixerGroup gui = AudioMan.instance != null ? AudioMan.instance.m_guiMixer : null;"),
    @("D5 the routing never set", "Ding.cs", "[ \t]*_source\.outputAudioMixerGroup = gui;\r?\n", ""),
    @("D6 a second, unrouted way to play", "Ding.cs", [regex]::Escape("_source.PlayOneShot(_clip, ModConfig.AlertVolume.Value);"), "_source.PlayOneShot(_clip, ModConfig.AlertVolume.Value); _source.Play();"),
    @("D7 the fallback takes a GUI group of any mixer", "Ding.cs", [regex]::Escape("group.name == ""GUI"" && group.audioMixer == mixer"), "group.name == ""GUI"""),
    @("D8 the ding's fallback takes a GUI group of any mixer, or any group of the game's", "Ding.cs", [regex]::Escape("group.name == ""GUI"" && group.audioMixer == mixer"), "group.name == ""GUI"" || group.audioMixer == mixer"),
    # The list's keys and what it blocks: Tab, Escape and B, ListKey.
    @("K1 the HasFocus postfix at the default priority - Chatter's postfix undoes it", "Plugin.cs", "(?s)(internal static class ChatHasFocusPatch\s*\{\s*)\[HarmonyPriority\(Priority\.Last\)\]", '${1}[HarmonyPriority(Priority.Normal)]'),
    @("K2 the HasFocus priority on the class, where Harmony ignores it", "Plugin.cs", "(?s)(internal static class ChatHasFocusPatch)(\s*\{\s*)\[HarmonyPriority\(Priority\.Last\)\]", '[HarmonyPriority(Priority.Last)] ${1}${2}'),
    @("K3 the HasFocus patch never applied - Tab opens the inventory", "Plugin.cs", ("[ \t]*" + [regex]::Escape("Patch(typeof(ChatHasFocusPatch));") + "\r?\n"), ""),
    @("K4 HasFocus reports IsOpen - the closing Escape or B reaches a trader", "Plugin.cs", "(?s)(internal static class ChatHasFocusPatch.*?)EntityListWindow\.BlocksGameInput", '${1}EntityListWindow.IsOpen'),
    @("K5 TextInput.IsVisible reports IsOpen - the closing Escape can open the pause menu", "Plugin.cs", [regex]::Escape("__result |= EntityListWindow.BlocksGameInput;"), "__result |= EntityListWindow.IsOpen;"),
    @("K6 the HasFocus postfix clears real chat focus while the list is closed", "Plugin.cs", "if \(WaypointerCompat\.SuspendDepth == 0 && EntityListWindow\.BlocksGameInput\)\r?\n\s*__result = true;", "__result = WaypointerCompat.SuspendDepth == 0 && EntityListWindow.BlocksGameInput;"),
    @("K7 the TextInput postfix assigns - it clears a sign's or another window's true", "Plugin.cs", [regex]::Escape("__result |= EntityListWindow.BlocksGameInput;"), "__result = EntityListWindow.BlocksGameInput;"),
    @("K8 Close records no frame", "EntityListWindow.cs", "[ \t]*_closedFrame = Time\.frameCount;\r?\n", ""),
    @("K9 BlocksGameInput ignores the closing frame", "EntityListWindow.cs", [regex]::Escape("get { return IsOpen || _closedFrame == Time.frameCount; }"), "get { return IsOpen; }"),
    @("K10 the inventory safety net closes without Close()", "EntityListWindow.cs", "(if \(IsOpen && InventoryGui\.IsVisible\(\)\)\r?\n\s*)Close\(\);", '${1}IsOpen = false;'),
    @("K11 the dead OnGUI Escape test is back", "EntityListWindow.cs", "(\r?\n)([ \t]*)GUI\.matrix = Matrix4x4\.Scale", '${1}${2}if (Event.current.type == EventType.KeyDown && Event.current.keyCode == KeyCode.Escape) { Close(); return; }${1}${2}GUI.matrix = Matrix4x4.Scale'),
    @("K12 Escape closes the list as well when the console closed itself first", "EntityListWindow.cs", [regex]::Escape("ListKeys.ClosesOnBack(IsOpen, consoleVisible, consoleWasVisible,"), "ListKeys.ClosesOnBack(IsOpen, consoleVisible, false,"),
    @("K13 the console's own Escape also closes the list", "EntityListWindow.cs", [regex]::Escape("ListKeys.ClosesOnBack(IsOpen, consoleVisible,"), "ListKeys.ClosesOnBack(IsOpen, false,"),
    @("K14 last frame's console never kept", "EntityListWindow.cs", "[ \t]*_consoleWasVisible = consoleVisible;\r?\n", ""),
    @("K15 last frame's console kept as false", "EntityListWindow.cs", [regex]::Escape("_consoleWasVisible = consoleVisible;"), "_consoleWasVisible = false;"),
    @("K16 B not consumed - a map or trader under the list closes with it", "EntityListWindow.cs", "[ \t]*ZInput\.ResetButtonStatus\(""JoyButtonB""\);\r?\n", ""),
    @("K17 Escape read as another key", "EntityListWindow.cs", [regex]::Escape("ZInput.GetKeyDown(KeyCode.Escape, false)"), "ZInput.GetKeyDown(KeyCode.Backspace, false)"),
    @("K18 the gamepad's B read as another button", "EntityListWindow.cs", [regex]::Escape("ZInput.GetButtonDown(""JoyButtonB"")"), "ZInput.GetButtonDown(""JoyButtonA"")"),
    @("K19 ListKey opens the list while the player types in chat", "EntityListWindow.cs", [regex]::Escape("_searchFocused, GameTyping.Any(),"), "_searchFocused, false,"),
    @("K20 ListKey opens the list over the pause menu", "EntityListWindow.cs", [regex]::Escape("Menu.IsVisible(), Hud.IsPieceSelectionVisible(),"), "false, Hud.IsPieceSelectionVisible(),"),
    @("K21 a letter ListKey closes the list mid-word", "EntityListWindow.cs", [regex]::Escape("_searchFocused, GameTyping.Any(),"), "false, GameTyping.Any(),"),
    @("K22 the search box's focus never sampled", "EntityListWindow.cs", "[ \t]*if \(Event\.current\.type == EventType\.Repaint\)\r?\n[ \t]*_searchFocused = GUIUtility\.keyboardControl != 0;\r?\n", ""),
    @("K23 ListKey read directly - an unmapped key throws every frame", "EntityListWindow.cs", [regex]::Escape("&& Hotkeys.Pressed(ModConfig.ListKey))"), "&& ZInput.GetKeyDown(ModConfig.ListKey.Value))"),
    @("K24 Hotkeys logs a Unity warning on every read", "Hotkeys.cs", [regex]::Escape("ZInput.GetKeyDown(key, false)"), "ZInput.GetKeyDown(key, true)"),
    @("K25 Hotkeys lets the throw out", "Hotkeys.cs", "(?s)catch \(Exception e\)\s*\{\s*Refuse\(setting, key, ""Valheim cannot read this key.*?return false;\s*\}", 'catch (Exception e) { throw new InvalidOperationException("ListKey", e); }'),
    @("K26 a changed ListKey stays refused", "ModConfig.cs", "[ \t]*ListKey\.SettingChanged \+= \(sender, args\) => Hotkeys\.Forget\(\);\r?\n", ""),
    @("K27 a left-click ListKey is read", "Hotkeys.cs", [regex]::Escape("if (ListKeys.IsClickButton((int)key))"), "if (!ListKeys.IsClickButton((int)key))"),
    @("K28 typing read from Chat.HasFocus, which the list forces", "Hotkeys.cs", [regex]::Escape("if (chat != null && chat.m_wasFocused)"), "if (chat != null && chat.HasFocus())"),
    @("K29 typing read from TextInput.IsVisible, which the list forces", "Hotkeys.cs", [regex]::Escape("if (text != null && text.m_panel != null && text.m_panel.activeSelf)"), "if (TextInput.IsVisible())"),
    @("K30 Find area's close bypasses Close()", "EntityListWindow.cs", [regex]::Escape("Close(); // the answer arrives"), "IsOpen = false; // the answer arrives"),
    @("K31 the inventory safety net removed", "EntityListWindow.cs", "[ \t]*if \(IsOpen && InventoryGui\.IsVisible\(\)\)\r?\n[ \t]*Close\(\);\r?\n", ""),
    @("K32 no input pause after B on a gamepad", "EntityListWindow.cs", "[ \t]*if \(ZInput\.IsGamepadActive\(\)\)\r?\n[ \t]*PlayerController\.SetTakeInputDelay\(0\.1f\);\r?\n", ""),
    @("K33 ListKey opens the list over the build menu - a right click on the list closes it", "EntityListWindow.cs", [regex]::Escape("Hud.IsPieceSelectionVisible(), InventoryGui.IsVisible(),"), "false, InventoryGui.IsVisible(),"),
    @("K34 ListKey opens the list over the inventory", "EntityListWindow.cs", [regex]::Escape("Hud.IsPieceSelectionVisible(), InventoryGui.IsVisible(),"), "Hud.IsPieceSelectionVisible(), false,"),
    @("K35 a sign's text box is not typing - F7 opens the list over it", "Hotkeys.cs", [regex]::Escape("text.m_panel.activeSelf)"), "false)"),
    @("K36 a refused key is not remembered - a warning on every frame", "Hotkeys.cs", [regex]::Escape("Refused.Add((int)key);"), ""),
    @("K37 ListKey opens the list over the Barber Station - its Escape also cancels the barber", "EntityListWindow.cs", [regex]::Escape("InventoryGui.IsVisible(), PlayerCustomizaton.IsBarberGuiVisible())"), "InventoryGui.IsVisible(), false)"),
    @("K38 a sign's open text box answers false - F7 opens over it", "Hotkeys.cs", "(text\.m_panel\.activeSelf\)\r?\n[ \t]*)return true;", '${1}return false;'),
    @("K39 Pressed never finds a refused key - a warning and a throw on every frame", "Hotkeys.cs", [regex]::Escape("if (Refused.Count > 0 &&"), "if (Refused.Count < 0 &&"),
    @("K40 Pressed asks Refused about KeyCode.None", "Hotkeys.cs", [regex]::Escape("Refused.Contains((int)key)"), "Refused.Contains(0)"),
    @("K41 a mouse-button ListKey is refused but still read", "Hotkeys.cs", "(Refuse\(setting, key, ""the left, right and middle mouse buttons[^\r\n]*\r?\n)[ \t]*return false;\r?\n", '${1}'),
    @("K42 ListKey opens the list only over the Barber Station", "EntityListWindow.cs", [regex]::Escape("InventoryGui.IsVisible(), PlayerCustomizaton.IsBarberGuiVisible())"), "InventoryGui.IsVisible(), !PlayerCustomizaton.IsBarberGuiVisible())"),
    @("K43 the barber folded into the inventory value (||)", "EntityListWindow.cs", [regex]::Escape("InventoryGui.IsVisible(), PlayerCustomizaton.IsBarberGuiVisible())"), "InventoryGui.IsVisible() || PlayerCustomizaton.IsBarberGuiVisible(), false)"),
    @("K44 the barber folded into the inventory value (|)", "EntityListWindow.cs", [regex]::Escape("InventoryGui.IsVisible(), PlayerCustomizaton.IsBarberGuiVisible())"), "InventoryGui.IsVisible() | PlayerCustomizaton.IsBarberGuiVisible(), false)"),
    @("K45 the eighth value reads the inventory - F7 opens over the barber", "EntityListWindow.cs", [regex]::Escape("InventoryGui.IsVisible(), PlayerCustomizaton.IsBarberGuiVisible())"), "InventoryGui.IsVisible(), InventoryGui.IsVisible())"),
    @("K46 a sign's text box counts as typing only while it is closed", "Hotkeys.cs", [regex]::Escape("text.m_panel.activeSelf)"), "!text.m_panel.activeSelf)"),
    # The mouse wheel while the list is open.
    @("Z1 the wheel patch never applied", "Plugin.cs", ("[ \t]*" + [regex]::Escape("Patch(typeof(MouseWheelPatch));") + "\r?\n"), ""),
    @("Z2 the wheel patch on a method the game does not have", "Plugin.cs", [regex]::Escape("nameof(ZInput.GetMouseScrollWheel)"), '"GetMouseScrollWheelRaw"'),
    @("Z3 the wheel postfix at the default priority - other mods see a wheel of 0", "Plugin.cs", "(?s)(internal static class MouseWheelPatch\s*\{\s*)\[HarmonyPriority\(Priority\.Last\)\]", '${1}[HarmonyPriority(Priority.Normal)]'),
    @("Z4 the wheel priority on the class, where Harmony ignores it", "Plugin.cs", "(?s)(internal static class MouseWheelPatch)(\s*\{\s*)\[HarmonyPriority\(Priority\.Last\)\]", '[HarmonyPriority(Priority.Last)] ${1}${2}'),
    @("Z5 the wheel zeroed only while the list is closed", "Plugin.cs", "(?s)(internal static class MouseWheelPatch.*?)if \(EntityListWindow\.BlocksGameInput\)", '${1}if (!EntityListWindow.BlocksGameInput)'),
    @("Z6 the wheel patch reads IsOpen - the closing frame is lost", "Plugin.cs", "(?s)(internal static class MouseWheelPatch.*?)EntityListWindow\.BlocksGameInput", '${1}EntityListWindow.IsOpen'),
    @("Z7 the wheel halved, not stopped", "Plugin.cs", [regex]::Escape("__result = 0f;"), "__result *= 0.5f;"),
    # TomTom and Wayfinder: their keys over the open list (WaypointerCompat).
    @("W1 the TextInput forcing ignores TomTom's question", "Plugin.cs", "(?s)(class TextInputVisiblePatch.*?)if \(WaypointerCompat\.SuspendDepth == 0\)\r?\n\s*", '${1}'),
    @("W2 the Chat forcing ignores TomTom's question", "Plugin.cs", "(?s)(class ChatHasFocusPatch.*?)WaypointerCompat\.SuspendDepth == 0 && ", '${1}'),
    @("W3 the TextInput forcing only while TomTom asks", "Plugin.cs", "(?s)(class TextInputVisiblePatch.*?)SuspendDepth == 0", '${1}SuspendDepth != 0'),
    @("W4 the reset as a postfix - skipped when the method throws", "WaypointerCompat.cs", [regex]::Escape("finalizer: new HarmonyMethod(typeof(WaypointerCompat), nameof(Finalizer))"), "postfix: new HarmonyMethod(typeof(WaypointerCompat), nameof(Finalizer))"),
    @("W5 no reset at all", "WaypointerCompat.cs", ",\s*finalizer: new HarmonyMethod\(typeof\(WaypointerCompat\), nameof\(Finalizer\)\)", ""),
    @("W6 prefix and finalizer swapped", "WaypointerCompat.cs", "nameof\(Prefix\)\),(\s*)finalizer: new HarmonyMethod\(typeof\(WaypointerCompat\), nameof\(Finalizer\)\)", 'nameof(Finalizer)),${1}finalizer: new HarmonyMethod(typeof(WaypointerCompat), nameof(Prefix))'),
    @("W7 the prefix does not count", "WaypointerCompat.cs", "[ \t]*SuspendDepth\+\+;\r?\n", ""),
    @("W8 the finalizer raises instead of lowering - the list stops blocking the game", "WaypointerCompat.cs", [regex]::Escape("SuspendDepth--;"), "SuspendDepth++;"),
    @("W9 no '> 0' guard in the finalizer", "WaypointerCompat.cs", "if \(SuspendDepth > 0\)\r?\n\s*SuspendDepth--;", "SuspendDepth--;"),
    @("W10 applied in Awake, before TomTom's assembly is loaded", "Plugin.cs", "(?s)(Patch\(typeof\(ChatHasFocusPatch\)\);)(.*?)WaypointerCompat\.Apply\(_harmony\);", '${1} WaypointerCompat.Apply(_harmony);${2}'),
    @("W11 Wayfinder's GUID misspelt", "WaypointerCompat.cs", [regex]::Escape('"DoomMachine.Wayfinder"'), '"DoomMachine.WayFinder"'),
    @("W12 the wrong method name", "WaypointerCompat.cs", [regex]::Escape('GetMethod("IsTypingElsewhere"'), 'GetMethod("IsTypingElseWhere"'),
    @("W13 instance methods asked for", "WaypointerCompat.cs", [regex]::Escape("BindingFlags.Public | BindingFlags.Static, null, Type.EmptyTypes"), "BindingFlags.Public | BindingFlags.Instance, null, Type.EmptyTypes"),
    @("W14 never applied", "Plugin.cs", "[ \t]*WaypointerCompat\.Apply\(_harmony\);\r?\n", ""),
    # Clicks on the list stay on the list: the uGUI raycast postfix and the pointer test it asks.
    @("U1 the raycast patch never applied", "Plugin.cs", ("[ \t]*" + [regex]::Escape("Patch(typeof(UiRaycastPatch));") + "\r?\n"), ""),
    @("U2 the raycast patch on a method the game does not have", "Plugin.cs", [regex]::Escape("nameof(EventSystem.RaycastAll)"), '"RaycastAllResults"'),
    @("U3 a postfix parameter the target does not have", "Plugin.cs", "(?s)List<RaycastResult> raycastResults\)(.*?)raycastResults\.Clear\(\)", 'List<RaycastResult> results)${1}results.Clear()'),
    @("U4 the raycast postfix at the default priority", "Plugin.cs", "(?s)(internal static class UiRaycastPatch\s*\{\s*)\[HarmonyPriority\(Priority\.Last\)\]", '${1}[HarmonyPriority(Priority.Normal)]'),
    @("U5 the raycast postfix's priority on the class, where Harmony ignores it", "Plugin.cs", "(?s)(internal static class UiRaycastPatch)(\s*\{\s*)\[HarmonyPriority\(Priority\.Last\)\]", '[HarmonyPriority(Priority.Last)] ${1}${2}'),
    @("U6 clears only when the pointer is off the list", "Plugin.cs", [regex]::Escape("&& EntityListWindow.Covers(eventData.position))"), "&& !EntityListWindow.Covers(eventData.position))"),
    @("U7 decides from ZInput's pointer, not the raycast's", "Plugin.cs", [regex]::Escape("EntityListWindow.Covers(eventData.position)"), "EntityListWindow.Covers(ZInput.pointerPosition)"),
    @("U8 clears a copy, not the input module's list", "Plugin.cs", [regex]::Escape("raycastResults.Clear();"), "new List<RaycastResult>(raycastResults).Clear();"),
    @("U9 blocks the whole screen while the list is open - the map beside it stops working", "Plugin.cs", [regex]::Escape("&& EntityListWindow.Covers(eventData.position))"), "&& EntityListWindow.IsOpen)"),
    @("U10 the pointer test unscaled - TomTom's copied", "EntityListWindow.cs", [regex]::Escape("_rect.height, GuiScale,"), "_rect.height, 1f,"),
    @("U11 the window's x and y swapped", "EntityListWindow.cs", [regex]::Escape("Rules.PointerOverWindow(_rect.x, _rect.y,"), "Rules.PointerOverWindow(_rect.y, _rect.x,"),
    @("U12 the window's width and height swapped", "EntityListWindow.cs", [regex]::Escape("_rect.width, _rect.height, GuiScale"), "_rect.height, _rect.width, GuiScale"),
    @("U13 the screen's width for its height", "EntityListWindow.cs", [regex]::Escape("Screen.height, screenPoint.x, screenPoint.y)"), "Screen.width, screenPoint.x, screenPoint.y)"),
    @("U14 the point's x and y swapped", "EntityListWindow.cs", [regex]::Escape("Screen.height, screenPoint.x, screenPoint.y)"), "Screen.height, screenPoint.y, screenPoint.x)"),
    @("U15 blocks while the list is closed", "EntityListWindow.cs", [regex]::Escape("return IsOpen && Rules.PointerOverWindow("), "return Rules.PointerOverWindow("),
    @("U16 OnGUI drops the moved window's rect - the test keeps the old place", "EntityListWindow.cs", [regex]::Escape("_rect = GUILayout.Window("), "GUILayout.Window("),
    # The game session (0.5.0): with KeepBetweenSessions off, the watchlist and the star filters last one session.
    @("E1 GameSession never added - every choice outlasts the session", "Plugin.cs", "[ \t]*gameObject\.AddComponent<GameSession>\(\);\r?\n", ""),
    @("E2 Unity's == - a logout goes unseen until the next world", "GameSession.cs", [regex]::Escape("if (ReferenceEquals(game, _game))"), "if (game == _game)"),
    @("E3 the Game never remembered - the choices emptied on every frame", "GameSession.cs", "[ \t]*_game = game;\r?\n", ""),
    @("E4 GameSession's Update renamed update - Unity never calls it, nothing resets", "GameSession.cs", [regex]::Escape("private void Update()"), "private void update()"),
    @("E5 the choices never reset", "GameSession.cs", "[ \t]*ModConfig\.ResetSession\(\);\r?\n", ""),
    @("E6 the settler never started over", "GameSession.cs", "[ \t]*WatchAlerts\.ResetSession\(\);\r?\n", ""),
    @("E7 the local player compared, not the Game - a death empties the choices", "GameSession.cs", [regex]::Escape("ReferenceEquals(game, _game)"), "ReferenceEquals(Player.m_localPlayer, _game)"),
    @("E8 the stored Game compared with itself - never a new session", "GameSession.cs", [regex]::Escape("ReferenceEquals(game, _game)"), "ReferenceEquals(_game, _game)"),
    @("E9 KeepBetweenSessions ignored - the choices always reset", "ModConfig.cs", "[ \t]*if \(KeepBetweenSessions\.Value\)\r?\n[ \t]*return;\r?\n", ""),
    @("E10 KeepBetweenSessions inverted - reset only when kept", "ModConfig.cs", [regex]::Escape("if (KeepBetweenSessions.Value)"), "if (!KeepBetweenSessions.Value)"),
    @("E11 the reset asks AutoTrack, not KeepBetweenSessions", "ModConfig.cs", [regex]::Escape("if (KeepBetweenSessions.Value)"), "if (AutoTrack.Value)"),
    @("E12 the watchlist never emptied", "ModConfig.cs", "[ \t]*WatchlistEntry\.Value = \(string\)WatchlistEntry\.DefaultValue;\r?\n", ""),
    @("E13 the List: row never reset", "ModConfig.cs", "[ \t]*ListStarsText\.Value = \(string\)ListStarsText\.DefaultValue;\r?\n", ""),
    @("E14 the Alerts: row never reset", "ModConfig.cs", "[ \t]*AlertStarsText\.Value = \(string\)AlertStarsText\.DefaultValue;\r?\n", ""),
    @("E15 the List: row reset to the watchlist's default", "ModConfig.cs", [regex]::Escape("ListStarsText.Value = (string)ListStarsText.DefaultValue;"), "ListStarsText.Value = (string)WatchlistEntry.DefaultValue;"),
    @("E16 KeepBetweenSessions on by default - nothing resets", "ModConfig.cs", [regex]::Escape("""KeepBetweenSessions"", false,"), """KeepBetweenSessions"", true,"),
    @("E17 WatchAlerts.Update starts the settler over on every frame - the Alerts: row never waits", "WatchAlerts.cs", "(private void Update\(\)\r?\n[ \t]*\{\r?\n)", '${1}            ResetSession();' + "`r`n"),
    @("E18 a new settler started over, not the alerts' own", "WatchAlerts.cs", [regex]::Escape("AlertStarsSettler.Reset();"), "new StarSetSettler().Reset();"),
    @("E19 a Watch click still waiting when the list closes is applied at the next opening, also in another session", "EntityListWindow.cs", "(private void Close\(\)\r?\n[ \t]*\{\r?\n)[ \t]*_pendingWatchToggle = null;\r?\n", '${1}'),
    @("E29 a Find area click still waiting when the list closes runs at the next opening, also in another world", "EntityListWindow.cs", "(private void Close\(\)\r?\n[ \t]*\{\r?\n[^\r\n]*\r?\n)[ \t]*_pendingFind = null;\r?\n", '${1}'),
    @("E30 no player no longer closes the list - a click waits for the next session", "EntityListWindow.cs", "[ \t]*Close\(\); // also drops a click not yet applied[^\r\n]*\r?\n", ""),
    # Which branch starts the re-track, and Auto-track's test (0.5.1).
    @("E31 the re-track started on logout, not on a lost creature - Always track nearest watched never starts", "Tracker.cs", "(?s)Stop\(\); // logged out; nobody to tell(.*?)NearestWatched\.Lost\(_targetPrefab, _targetTamed\);[^\r\n]*", '{ NearestWatched.Lost(_targetPrefab, _targetTamed); Stop(); }${1}'),
    @("E32 a tracked spawn area counts as lost at once - 'Lost track of' on every Find area", "Tracker.cs", [regex]::Escape("if (IsTracking && !_isPoint && (Target == null"), "if (IsTracking && (Target == null"),
    @("E33 Auto-track waits for any tracking - an alert no longer takes over a Find area arrow", "WatchAlerts.cs", [regex]::Escape("!Tracker.IsTrackingCreature"), "!Tracker.IsTracking"),
    @("E34 Auto-track only while a creature is tracked", "WatchAlerts.cs", [regex]::Escape("!Tracker.IsTrackingCreature"), "Tracker.IsTrackingCreature"),
    # The session reset's decisions (0.5.1, SC-5).
    @("E35 the reset's gate inverted - nothing is ever reset", "ModConfig.cs", [regex]::Escape("if (held.Length == 0)"), "if (held.Length != 0)"),
    @("E36 Held inverted - only entries already at their default count as held", "ModConfig.cs", [regex]::Escape("if (entry.Value == (string)entry.DefaultValue)"), "if (entry.Value != (string)entry.DefaultValue)"),
    @("E37 Held compares the default with itself - nothing is ever reset", "ModConfig.cs", [regex]::Escape("if (entry.Value == (string)entry.DefaultValue)"), "if ((string)entry.DefaultValue == (string)entry.DefaultValue)"),
    @("E38 ConfigSaver.Each put back as false - no change is saved again until the game restarts", "ModConfig.cs", [regex]::Escape("bool saveEach = ConfigSaver.Each;"), "bool saveEach = false;"),
    # The tracking guide hides with the game's HUD, in cutscenes, while dead or teleporting (0.5.1); the arrow's ranges.
    @("E39 the guide never hidden - the arrow shows over a hidden HUD, a cutscene and a death again", "Tracker.cs", [regex]::Escape("if (_guideHidden)"), "if (false)"),
    @("E40 dead read from the tracked creature, not the player", "Tracker.cs", [regex]::Escape("player.IsDead(), WaitingForRespawn()"), "Target.IsDead(), WaitingForRespawn()"),
    @("E41 teleporting read from the tracked creature, not the player", "Tracker.cs", [regex]::Escape("player.IsTeleporting());"), "Target.IsTeleporting());"),
    @("E42 the label ignores the gate - 'Tracking:' over a hidden HUD and the death fade", "Tracker.cs", [regex]::Escape("if (!IsTracking || _guideHidden)"), "if (!IsTracking)"),
    @("E43 the hidden guide still draws the ground-path line", "Tracker.cs", "(if \(_guideHidden\)\r?\n[ \t]*\{\r?\n[ \t]*_arrow\.SetActive\(false\);\r?\n)[ \t]*_line\.enabled = false;\r?\n", '${1}'),
    @("E44 a failed cutscene test hides the guide for good", "Tracker.cs", "(catch \(System\.Exception\)\r?\n[ \t]*\{\r?\n[ \t]*return )false;", '${1}true;'),
    @("E45 the cutscene test unguarded - a missing video player throws in LateUpdate", "Tracker.cs", "(?s)try\r?\n[ \t]*\{\r?\n[ \t]*return player\.InCutscene\(\);\r?\n[ \t]*\}\r?\n[ \t]*catch \(System\.Exception\)\r?\n[ \t]*\{\r?\n[ \t]*return false;\r?\n[ \t]*\}", "return player.InCutscene();"),
    @("E46 the respawn frame not counted - the guide shows from the removed body for a frame", "Tracker.cs", [regex]::Escape("return game != null && game.WaitingForRespawn();"), "return false;"),
    @("E47 ArrowSize unranged - a negative size turns the arrow round, 0 hides it", "ModConfig.cs", [regex]::Escape("new AcceptableValueRange<float>(0.1f, 3f)"), "null"),
    @("E48 ArrowSize may be 0 - the arrow vanishes", "ModConfig.cs", [regex]::Escape("new AcceptableValueRange<float>(0.1f, 3f)"), "new AcceptableValueRange<float>(0f, 3f)"),
    # More ways the 0.5.1 code could be wrong and still compile.
    @("E49 the gate moved below 'if (!showArrow) return;' - in GroundPath mode with a complete path the line stays up while dead or with the HUD hidden", "Tracker.cs",
        '(?s)([ \t]*_guideHidden = Rules\.GuideHidden\(Hud\.IsUserHidden\(\).*?_line\.enabled = false;\r?\n[ \t]*return;\r?\n[ \t]*\}\r?\n)(.*?if \(!showArrow\)\r?\n[ \t]*return;\r?\n)', '${2}${1}'),
    @("E51 the gate's return dropped - the code below turns the arrow and the line back on", "Tracker.cs",
        '(_line\.enabled = false;\r?\n)[ \t]*return;\r?\n([ \t]*\}\r?\n\r?\n[ \t]*Vector3 from = player)', '${1}${2}'),
    @("E52 the gate leaves the arrow up", "Tracker.cs", '(if \(_guideHidden\)\r?\n[ \t]*\{\r?\n)[ \t]*_arrow\.SetActive\(false\);\r?\n', '${1}'),
    @("E53 the gate inverted - the guide shows only while it should hide", "Tracker.cs", [regex]::Escape("if (_guideHidden)"), 'if (!_guideHidden)'),
    @("E54 the cutscene test called unguarded (wrapper bypassed)", "Tracker.cs", [regex]::Escape("InCutscene(player), player.IsDead()"), 'player.InCutscene(), player.IsDead()'),
    @("E55 the label's gate back to 0.5.0's HUD test only - the label shows while dead, in a cutscene, teleporting", "Tracker.cs", [regex]::Escape("if (!IsTracking || _guideHidden)"), 'if (!IsTracking || Hud.IsUserHidden())'),
    @("E56 the label's gate with && - the label shows while hidden", "Tracker.cs", [regex]::Escape("if (!IsTracking || _guideHidden)"), 'if (!IsTracking && _guideHidden)'),
    @("E57 the cutscene catch narrowed to NullReferenceException", "Tracker.cs", 'catch \(System\.Exception\)(\r?\n[ \t]*\{\r?\n[ \t]*return false;)', 'catch (System.NullReferenceException)${1}'),
    @("E58 the cutscene catch rethrows", "Tracker.cs", '(catch \(System\.Exception\)\r?\n[ \t]*\{\r?\n[ \t]*)return false;', '${1}throw;'),
    @("E59 WaitingForRespawn true without a Game", "Tracker.cs", [regex]::Escape("return game != null && game.WaitingForRespawn();"), 'return game == null || game.WaitingForRespawn();'),
    @("E60 the lost-creature branch reads the player's death, not the creature's", "Tracker.cs", [regex]::Escape("(Target == null || Target.IsDead() ||"), '(Target == null || player.IsDead() ||'),
    @("E61 the re-track scheduled before Stop", "Tracker.cs", '([ \t]*)Stop\(\);\r?\n([ \t]*NearestWatched\.Lost\(_targetPrefab, _targetTamed\);[^\r\n]*\r?\n)', ('${2}${1}Stop();' + "`r`n")),
    @("E62 a creature dead but not yet removed is not lost", "Tracker.cs", [regex]::Escape("(Target == null || Target.IsDead() ||"), '(Target == null ||'),
    @("E63 IsTrackingCreature is IsTracking - a Find area arrow no longer gives way to an alert", "Tracker.cs", [regex]::Escape("get { return IsTracking && !_isPoint; }"), 'get { return IsTracking; }'),
    @("E64 IsTrackingCreature inverted to 'tracking a point'", "Tracker.cs", [regex]::Escape("get { return IsTracking && !_isPoint; }"), 'get { return IsTracking && _isPoint; }'),
    @("E65 IsTrackingCreature ignores IsTracking - true with nothing tracked, so Auto-track never starts", "Tracker.cs", [regex]::Escape("get { return IsTracking && !_isPoint; }"), 'get { return !_isPoint; }'),
    @("E66 Auto-track's && became || - with AutoTrack on an alert replaces a tracked creature; off, it still auto-tracks", "WatchAlerts.cs", [regex]::Escape("if (ModConfig.AutoTrack.Value && !Tracker.IsTrackingCreature"), 'if (ModConfig.AutoTrack.Value || !Tracker.IsTrackingCreature'),
    @("E67 Auto-track ignores the AutoTrack setting", "WatchAlerts.cs", [regex]::Escape("if (ModConfig.AutoTrack.Value && !Tracker.IsTrackingCreature"), 'if (!Tracker.IsTrackingCreature'),
    @("E68 ArrowSize's range passed as a ConfigDescription tag, not its AcceptableValues - unranged", "ModConfig.cs", [regex]::Escape("new AcceptableValueRange<float>(0.1f, 3f)"), 'null, new AcceptableValueRange<float>(0.1f, 3f)'),
    @("E69 ArrowHeight's range passed as a ConfigDescription tag - unranged", "ModConfig.cs", [regex]::Escape("new AcceptableValueRange<float>(0f, 5f)"), 'null, new AcceptableValueRange<float>(0f, 5f)'),
    @("E70 ArrowSize bound to the key ArrowHeight - both fields share one entry: ArrowHeight ranges 0.1-3, default 0.6", "ModConfig.cs", [regex]::Escape('config.Bind("Tracking", "ArrowSize", 0.6f,'), 'config.Bind("Tracking", "ArrowHeight", 0.6f,'),
    @("E71 the two ranges swapped between the entries", "ModConfig.cs", '(?s)new AcceptableValueRange<float>\(0\.1f, 3f\)(.*?)new AcceptableValueRange<float>\(0f, 5f\)', 'new AcceptableValueRange<float>(0f, 5f)${1}new AcceptableValueRange<float>(0.1f, 3f)'),
    @("E72 the arrow's length read from ArrowHeight (0 allowed: the arrow vanishes)", "Tracker.cs", [regex]::Escape("_arrow.transform.localScale = Vector3.one * ModConfig.ArrowSize.Value;"), '_arrow.transform.localScale = Vector3.one * ModConfig.ArrowHeight.Value;'),
    @("E73 Close drops the waiting clicks only when the list is open", "EntityListWindow.cs", '([ \t]*_pendingWatchToggle = null;\r?\n[ \t]*_pendingFind = null;\r?\n)([ \t]*if \(!IsOpen\)\r?\n[ \t]*return;\r?\n)', '${2}${1}'),
    @("E74 the no-player branch closes only an open list", "EntityListWindow.cs", [regex]::Escape("Close(); // also drops a click not yet applied"), 'if (IsOpen) Close(); // also drops a click not yet applied'),
    @("E75 the no-player branch goes on after Close - the list key can open it with no player", "EntityListWindow.cs", '(Close\(\); // also drops a click not yet applied[^\r\n]*\r?\n)[ \t]*return;\r?\n', '${1}'),
    @("E76 the no-player test moved after HandleKeys - the list key opens the list (closed again at once) with no player", "EntityListWindow.cs",
        '(?s)([ \t]*Player player = Player\.m_localPlayer;\r?\n[ \t]*if \(player == null\)\r?\n[ \t]*\{\r?\n[^\r\n]*\r?\n[ \t]*return;\r?\n[ \t]*\}\r?\n\r?\n)([ \t]*HandleKeys\(consoleVisible, consoleWasVisible\);\r?\n)', '${2}${1}'),
    @("E77 ConfigSaver.Each read after it is set false - put back as false (E38 respelled)", "ModConfig.cs", '([ \t]*bool saveEach = ConfigSaver\.Each;\r?\n)([ \t]*ConfigSaver\.Each = false;\r?\n)', '${2}${1}'),
    @("E78 the restore taken out of the finally - a throwing write leaves every later change unsaved", "ModConfig.cs", 'finally\r?\n[ \t]*\{\r?\n[ \t]*ConfigSaver\.Each = saveEach;\r?\n[ \t]*\}', ('catch (System.Exception) { throw; }' + "`r`n" + '            ConfigSaver.Each = saveEach;')),
    @("E79 the reset's gate asks only the watchlist - star filters held alone are never reset", "ModConfig.cs", [regex]::Escape("string held = Held(WatchlistEntry) + Held(ListStarsText) + Held(AlertStarsText);"), 'string held = Held(WatchlistEntry);'),
    @("E20 the reset saves the cfg at each of its writes - three saves more, a failing cfg's warning at the first", "ModConfig.cs", "[ \t]*ConfigSaver\.Each = false;\r?\n", ""),
    @("E21 ConfigSaver.Each never put back - no change is saved again until the game restarts", "ModConfig.cs", "[ \t]*ConfigSaver\.Each = saveEach;\r?\n", ""),
    @("E22 the reset's save gone - its defaults reach the file only at the next change", "ModConfig.cs", "[ \t]*ConfigSaver\.Save\(""after the session reset""\);\r?\n", ""),
    @("E23 the watchlist entry's handler gone - the reset empties the cfg, not the watchlist the alerts read", "ModConfig.cs", "[ \t]*WatchlistEntry\.SettingChanged \+= [^\r\n]*\r?\n", ""),
    @("E24 GameSession on an object of the scene - it goes with the first logout", "Plugin.cs", [regex]::Escape("gameObject.AddComponent<GameSession>();"), "new GameObject(""MobTracker session"").AddComponent<GameSession>();"),
    @("E25 the plugin's Awake renamed awake - Unity never calls it, nothing loads", "Plugin.cs", [regex]::Escape("private void Awake()"), "private void awake()"),
    @("E27 the wheel postfix's __result spelt __Result - HarmonyX refuses the patch at the game's start", "Plugin.cs", "(?s)(internal static class MouseWheelPatch.*?ref float )__result\)(.*?)__result = 0f;", '${1}__Result)${2}__Result = 0f;'),
    @("E28 the delete-gesture prefix's pos spelt Pos - HarmonyX refuses the patch at the game's start", "Plugin.cs", "(?s)(Prefix\(Minimap __instance, Vector3 )pos(, float radius.*?RemovePinNear\(__instance, )pos,", '${1}Pos${2}Pos,'),
    @("E26 the wheel patch's Postfix renamed postfix - Harmony applies nothing, and the wheel reaches the free-fly camera and Server Devcommands' wheel binds again", "Plugin.cs", "(internal static class MouseWheelPatch\s*\{\s*\[HarmonyPriority\(Priority\.Last\)\]\s*private static void )Postfix\(", '${1}postfix('),
    # The log (0.7.0): MobTracker.log's switches, its file, its listener, the verbose lines' route, sites and guards.
    @("X1 ErrorLog defaults to false - no MobTracker.log for whoever never opens the settings", "LogFile.cs", [regex]::Escape('ErrorLog = config.Bind("Logging", "ErrorLog", true,'), 'ErrorLog = config.Bind("Logging", "ErrorLog", false,'),
    @("X2 VerboseLog defaults to true - every event in both logs for everyone", "LogFile.cs", [regex]::Escape('VerboseLog = config.Bind("Logging", "VerboseLog", false,'), 'VerboseLog = config.Bind("Logging", "VerboseLog", true,'),
    @("X3 no source filter - every plugin's and Unity's lines copied in as MobTracker's", "LogFile.cs", [regex]::Escape('if (ReferenceEquals(eventArgs.Source, MobTrackerPlugin.Log))'), 'if (true)'),
    @("X4 MobTracker.log opened with FileMode.Create - the last start's lines gone before they are copied", "LogFile.cs", [regex]::Escape('FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.Read)'), 'FileMode.Create, FileAccess.ReadWrite, FileShare.Read)'),
    @("X5 the open catches IOException only - a read-only file throws out of Awake and the plugin is dropped", "LogFile.cs", '(catch \()Exception( e\)\r?\n[ \t]*\{\r?\n[ \t]*// Whatever holds the file)', '${1}IOException${2}'),
    @("X6 a verbose method without its VerboseLog test - the line put together and written with VerboseLog off", "Events.cs", '(public static void Alert\(Character nearest, float distance, int count\)\r?\n[ \t]*\{\r?\n)[ \t]*if \(!ModLog\.Verbose\)\r?\n[ \t]*return;\r?\n', '${1}'),
    @("X7 a verbose line before the alert poll's once-a-second return - every frame", "WatchAlerts.cs", '([ \t]*EffectiveAlertStars = AlertsRow\.Effective\([^\r\n]*\r?\n)', ('${1}            Events.AlertStars(EffectiveAlertStars);' + "`r`n")),
    @("X8 the listener's catch rethrows - a line it cannot write throws into whichever plugin logged", "LogFile.cs", '(\n[ \t]*)Broke\(e\);', '${1}Broke(e); throw;'),
    @("X9 the file opened again after the settings are read - this start's own lines moved to MobTracker-prev.log", "LogFile.cs", '(_binding = false;\r?\n)', ('${1}            Open("again");' + "`r`n")),
    @("X10 LogFile.Start after ModConfig.Bind - the star filters' warnings at the start never reach the file", "Plugin.cs", '([ \t]*LogFile\.Start\([^\r\n]*\r?\n)([ \t]*ModConfig\.Bind\(Config\);\r?\n)', '${2}${1}'),
    @("X11 a line through a second log source - missed by MobTracker.log's filter", "SpawnFinder.cs", [regex]::Escape('MobTrackerPlugin.Log.LogInfo(displayName + " world spawn, nearest area by: " + matched);'), 'BepInEx.Logging.Logger.CreateLogSource("MobTracker").LogInfo(displayName + " world spawn, nearest area by: " + matched);'),
    @("X12 the alert line names the player", "Events.cs", [regex]::Escape('ModLog.Event(EventLines.Alert(Creature.DisplayName(nearest),'), 'ModLog.Event(EventLines.Alert(Creature.DisplayName(nearest) + " near " + Player.m_localPlayer.GetPlayerName(),'),
    @("X13 the verbose flag follows ErrorLog - VerboseLog turned on does nothing", "LogFile.cs", '(ModLog\.Verbose = )VerboseLog(\.Value;\r?\n[ \t]*Switched\("VerboseLog")', '${1}ErrorLog${2}'),
    @("X14 no LogFile.Stop at quit - no closing line, the listener left on BepInEx's log", "Plugin.cs", '[ \t]*LogFile\.Stop\(\);\r?\n', ''),
    @("X15 no flush per line - a crash loses the lines before it", "LogFile.cs", [regex]::Escape('writer.AutoFlush = true;'), 'writer.AutoFlush = false;'),
    @("X16 no copy to MobTracker-prev.log - the last start's lines emptied away", "LogFile.cs", '[ \t]*file\.CopyTo\(prev\);\r?\n', ''),
    @("X17 the open's failure gives the exception's message - the file's full path, the Windows account folder in it", "LogFile.cs", [regex]::Escape('EventLines.OpenFailed(e.GetType().Name)'), 'EventLines.OpenFailed(e.Message)'),
    @("X18 the switches' test inverted - Info lines without VerboseLog, no errors with ErrorLog", "LogFile.cs", [regex]::Escape('if (LogRules.ToFile(level, ErrorLog.Value, ModLog.Verbose))'), 'if (!LogRules.ToFile(level, ErrorLog.Value, ModLog.Verbose))'),
    @("X19 the listener's catch logs - it re-enters itself", "LogFile.cs", '(\n[ \t]*)Broke\(e\);', '${1}MobTrackerPlugin.Log.LogWarning("MobTracker.log: " + e.GetType().Name);'),
    @("X20 the verbose lines at Debug - never in LogOutput.log at BepInEx's default levels", "LogFile.cs", [regex]::Escape('MobTrackerPlugin.Log.LogInfo(line);'), 'MobTrackerPlugin.Log.LogDebug(line);'),
    @("X21 the listener added before the file is ready", "LogFile.cs", '(?s)([ \t]*tee = new LogFile\(\);\r?\n)(.*?)([ \t]*Logger\.Listeners\.Add\(tee\);\r?\n)', '${1}${3}${2}'),
    @("X22 every line of MobTracker's own written, whatever the switches", "LogFile.cs", [regex]::Escape('if (LogRules.ToFile(level, ErrorLog.Value, ModLog.Verbose))'), 'if (true)'),
    @("X23 a verbose method's catch rethrows - a broken alert line ends the alert poll", "Events.cs", [regex]::Escape('catch (Exception e) { Failed("Alert", e); }'), 'catch (Exception e) { Failed("Alert", e); throw; }'),
    @("X24 the loss line after the lost block - never written, the tracking is already over", "Tracker.cs", '(?s)([ \t]*Events\.TrackEnding\(player\);[^\r\n]*\r?\n)(.*?)([ \t]*if \(IsTracking && _isPoint && Utils\.DistanceXZ)', '${2}${1}${3}'),
    @("X25 the guide's line on every frame", "LogObserver.cs", [regex]::Escape('if (Tracker.GuideHiddenNow != _guideHidden)'), 'if (true)'),
    @("X26 MobTracker.log emptied before the copy - a failed copy loses the last start", "LogFile.cs", '(?s)([ \t]*using \(var prev = .*?\r?\n[ \t]*\}\r?\n)([ \t]*file\.SetLength\(0\);\r?\n)', '${2}${1}'),
    @("X27 MobTracker.log shared ReadWrite - a second copy of the game writes into it", "LogFile.cs", [regex]::Escape('FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.Read)'), 'FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.ReadWrite)'),
    @("X28 the folders not scrubbed - the game's and the Windows user folder in the file", "LogFile.cs", [regex]::Escape('LogRules.Scrub(line, _gameFolder, _userFolder)'), 'line'),
    @("X29 no size cap - an error storm fills the disk", "LogFile.cs", [regex]::Escape('if (!LogRules.Fits(_written, bytes, LogRules.Cap))'), 'if (false)'),
    @("X30 every Unity and BepInEx error copied in, not only MobTracker's", "LogFile.cs", '[ \t]*if \(!LogRules\.NamesMobTracker\(text\)\)\r?\n[ \t]*return false;\r?\n', ''),
    @("X31 the frame read on any thread - Unity throws off its main thread", "LogFile.cs", '[ \t]*if \(Thread\.CurrentThread\.ManagedThreadId == _mainThread\)\r?\n[ \t]*(frame = LogHost\.Frame\(\);)', '                ${1}'),
    @("X33 the creature pass of the not-alerting line without its catch - a broken creature ends the alert poll", "Events.cs", '(?s)try\r?\n[ \t]*\{\r?\n[ \t]*NotAlertingEach\(gate, from\);\r?\n[ \t]*\}\r?\n[ \t]*catch \(Exception e\) \{ Failed\("NotAlerting", e\); \}', 'NotAlertingEach(gate, from);'),
    @("X34 a verbose line in a Harmony patch - at every uGUI raycast", "Plugin.cs", [regex]::Escape('raycastResults.Clear();'), 'raycastResults.Clear(); Events.Clicked("raycast");'),
    @("X36 the not-alerting line asks the alert gate - verbose uses up the alerts", "Events.cs", [regex]::Escape('if (id != ZDOID.None && gate.Has(id))'), 'if (id != ZDOID.None && !gate.ShouldAlert(id, true, false, 0f, 0f))'),
    @("X37 the loss line without the dead test - a kill seen here never said", "Events.cs", [regex]::Escape('if (target == null || target.IsDead())'), 'if (target == null)'),
    @("X38 the Stop tracking line outside its button's branch - written at every GUI event", "EntityListWindow.cs", '([ \t]*if \(\(Tracker\.IsTracking \|\| NearestWatched\.IsPending\) && GUILayout\.Button[^\r\n]*\r?\n[ \t]*\{\r?\n)([ \t]*Events\.Clicked\("Stop tracking"\);\r?\n)', '${2}${1}'),
    @("X39 LogRules' Debug is not BepInEx's - a level the switches' test reads wrongly", "LogRules.cs", [regex]::Escape('public const int Debug = 32;'), 'public const int Debug = 64;'),
    @("X40 a Unity log callback of MobTracker's own - a second capture route", "LogHost.cs", [regex]::Escape('return Time.frameCount;'), 'Application.logMessageReceived += null; return Time.frameCount;'),
    @("X41 a line through System.Console - past every count", "Events.cs", [regex]::Escape('if (FailedOnce.Add(where))'), 'System.Console.WriteLine(where); if (FailedOnce.Add(where))'),
    @("X42 Write without its lock - two threads' lines interleaved and the cap miscounted", "LogFile.cs", '(?s)lock \(_gate\)\r?\n([ \t]*\{\r?\n[ \t]*StreamWriter writer = _writer;)', '${1}'),
    @("X45 Events.Watch never called - no setting's change in the verbose log", "ModConfig.cs", '[ \t]*Events\.Watch\(config\);\r?\n', ''),
    @("X46 Events.Watch first in ModConfig.Bind - its handler before the settings' own, reading parsed views not yet updated", "ModConfig.cs", '(?s)(public static void Bind\(ConfigFile config\)\r?\n[ \t]*\{\r?\n)(.*?)([ \t]*Events\.Watch\(config\);\r?\n)', '${1}${3}${2}'),
    @("X47 the ground path's line every second, changed or not", "Tracker.cs", [regex]::Escape('if (!ModLog.Verbose || (_pathState == _loggedPathState && Generation == _loggedGeneration))'), 'if (!ModLog.Verbose)'),
    @("X48 LogPath outside the once-a-second branch - the state checked every frame", "Tracker.cs", '([ \t]*UpdatePath\(from, to\);\r?\n)[ \t]*LogPath\(\);\r?\n([ \t]*\}\r?\n)', ('${1}${2}            LogPath();' + "`r`n")),
    @("X49 the ding's played line before PlayOneShot", "Ding.cs", '([ \t]*_source\.PlayOneShot\(_clip, ModConfig\.AlertVolume\.Value\);\r?\n)([ \t]*Events\.DingPlayed\(\);\r?\n)', '${2}${1}'),
    @("X50 the mixer search's catch returns - the fallback search never runs", "Ding.cs", [regex]::Escape('Events.DingGroupSearchFailed(e);'), 'Events.DingGroupSearchFailed(e); return null;'),
    @("X51 the switch note at Info - with ErrorLog alone the file never says a switch changed", "LogFile.cs", [regex]::Escape('MobTrackerPlugin.Log.LogMessage(EventLines.LoggingSwitch('), 'MobTrackerPlugin.Log.LogInfo(EventLines.LoggingSwitch('),
    @("X52 a stopped file said only with VerboseLog on", "LogObserver.cs", '(?s)([ \t]*)LogFile\.ReportNotice\(\);\r?\n(.*?_generation = -1;\r?\n[ \t]*return;\r?\n[ \t]*\}\r?\n)', ('${2}${1}LogFile.ReportNotice();' + "`r`n")),
    @("X53 the cap at 50 MB", "LogRules.cs", [regex]::Escape('public const long Cap = 5L * 1024 * 1024;'), 'public const long Cap = 50L * 1024 * 1024;'),
    @("X55 BepInEx's warnings taken as MobTracker's all game long", "LogFile.cs", [regex]::Escape('ErrorLog.Value || ModLog.Verbose, _binding)'), 'ErrorLog.Value || ModLog.Verbose, true)'),
    @("X56 Stop leaves the listener on BepInEx's log", "LogFile.cs", '[ \t]*Logger\.Listeners\.Remove\(tee\);\r?\n', ''),
    @("X57 a failed open counted as opened - never tried again when a switch is turned on", "LogFile.cs", '([ \t]*file = new FileStream\(Path\.Combine\(_folder, FileName\)[^\r\n]*\r?\n)([ \t]*_opened = true;\r?\n)', '${2}${1}'),
    @("X59 ModLog.Event without its own VerboseLog test", "LogFile.cs", '[ \t]*if \(Verbose\)\r?\n([ \t]*MobTrackerPlugin\.Log\.LogInfo\(line\);)', '${1}'),
    @("X61 the track line names a tamed creature by the name its owner gave it", "Events.cs", [regex]::Escape('ModLog.Event(EventLines.TrackStarted(Creature.DisplayName(character),'), 'ModLog.Event(EventLines.TrackStarted(character.GetHoverName(),'),
    @("X62 a verbose site joins text - built with VerboseLog off too", "SpawnFinder.cs", [regex]::Escape('Events.FindSays(text);'), 'Events.FindSays("HUD: " + text);'),
    @("X63 the refused-key line reads ListKey itself, past Hotkeys", "Events.cs", [regex]::Escape('if (!Hotkeys.Pressed(ModConfig.ListKey))'), 'if (!ZInput.GetKeyDown(key, false))'),
    @("X65 a verbose method changes a setting's state - the Alerts: row's wait restarted", "Events.cs", [regex]::Escape('if (creatures > 0)'), 'ModConfig.AlertStarsRevision++; if (creatures > 0)'),
    @("X66 the repeat limit dropped - an Update that throws writes every frame", "LogFile.cs", [regex]::Escape('write = _repeats.Write(LogRules.RepeatKey(text), Clock.Elapsed.TotalSeconds, out leftOut);'), '{ _repeats.Write(LogRules.RepeatKey(text), Clock.Elapsed.TotalSeconds, out leftOut); write = true; }'),
    @("X69 the track line names the creature's network ID", "Events.cs", [regex]::Escape('character.IsTamed(), character.InInterior(), Tracker.Tracked)'), 'character.IsTamed(), character.InInterior(), Tracker.Tracked + " " + character.GetZDOID().UserID)'),
    @("X70 a verbose line straight through ModLog, past Events' guard and catch", "Tracker.cs", [regex]::Escape('Events.TrackReached();'), 'ModLog.Event("Track: reached");'),
    @("X71 ErrorLog's handler always says on", "LogFile.cs", [regex]::Escape('Switched("ErrorLog", ErrorLog.Value);'), 'Switched("ErrorLog", true);'),
    @("X72 a switch turned on opens the file again - this start's lines moved to MobTracker-prev.log", "LogFile.cs", [regex]::Escape('if (on && !_opened)'), 'if (on)'),
    @("X73 a verbose failure written to a file of its own", "Events.cs", [regex]::Escape('if (FailedOnce.Add(where))'), 'System.IO.File.AppendAllText("MobTracker-verbose.txt", where); if (FailedOnce.Add(where))'),
    @("X74 Events.Watch adds no handler - no setting's change in the verbose log", "Events.cs", '[ \t]*config\.SettingChanged \+= OnSettingChanged;\r?\n', ''),
    @("X76 a method the listener reaches throws - BepInEx hands it to whichever plugin logged", "LogFile.cs", '(_writer = null;\r?\n[ \t]*if \(writer == null\)\r?\n[ \t]*)return;', '${1}throw new System.InvalidOperationException("MobTracker.log shut twice");'),
    @("X75 the empty look's line told the player is outside", "NearestWatched.cs", [regex]::Escape('Events.EmptyLook(from, playerInside);'), 'Events.EmptyLook(from, false);'),
    # Since 0.7.0: the rate guards inside Events (each a once-only line turned into one per frame, second, look
    # or keystroke), LogFile.Bound's catch, a switch turned off, and what Events hands to EventLines' decisions.
    @("X77 the refused-key line without its press test - a line every frame while the list may not toggle", "Events.cs", '[ \t]*if \(!Hotkeys\.Pressed\(ModConfig\.ListKey\)\)\r?\n[ \t]*return;\r?\n', ''),
    @("X78 the not-alerting line not remembered - one per creature that does not alert, every second", "Events.cs", '[ \t]*ToldNotAlerting\.Add\(character\.GetInstanceID\(\)\);\r?\n', ''),
    @("X79 the empty look's line not compared with the last - one at every look of a wait with no time limit", "Events.cs", '[ \t]*if \(line == _lastEmptyLook\)\r?\n[ \t]*return;\r?\n', ''),
    @("X80 a setting's change written past the settler - one line per slider step or keystroke", "Events.cs", [regex]::Escape('Settler.Changed(key, was, now, Time.realtimeSinceStartup)'), 'EventLines.Setting(key, now, was)'),
    @("X81 the cleared alert memory said when it held none - every second through the main menu", "Events.cs", '[ \t]*if \(creatures > 0\)\r?\n', ''),
    @("X82 Bound's settings line not caught - a failed write throws out of Awake and the plugin is dropped", "LogFile.cs", '(?s)try\r?\n[ \t]*\{\r?\n([ \t]*tee\.WriteFile\(EventLines\.Settings\(Settings\(config\)\)\);\r?\n)[ \t]*\}\r?\n[ \t]*catch \(Exception e\)\r?\n[ \t]*\{\r?\n[ \t]*tee\.Broke\(e\);\r?\n[ \t]*\}\r?\n', '${1}'),
    @("X83 a switch turned off tries a failed open again - the header names it as turned on", "LogFile.cs", [regex]::Escape('if (on && !_opened)'), 'if (!_opened && (ErrorLog.Value || ModLog.Verbose))'),
    @("X84 Auto-track's outcome told the tracking never changed - a take said as not taken", "Events.cs", [regex]::Escape('EventLines.AutoTrackOutcome(Tracker.Generation, _alertGeneration,'), 'EventLines.AutoTrackOutcome(_alertGeneration, _alertGeneration,'),
    @("X85 the not-alerting pass asks the dungeon side - a creature that alerts said as one that does not", "Events.cs", [regex]::Escape('Rules.WithinRadius(distance, ModConfig.AlertRadius.Value), true);'), 'Rules.WithinRadius(distance, ModConfig.AlertRadius.Value), false);'),
    @("X86 a close with no local player said as of no known cause", "Events.cs", [regex]::Escape('EventLines.ClosedUnseen(InventoryGui.IsVisible(), Player.m_localPlayer != null)'), 'EventLines.ClosedUnseen(InventoryGui.IsVisible(), true)'),
    @("X87 the empty look's counts crossed - the tamed said as not on the network", "Events.cs", [regex]::Escape('away[EventLines.AwayNotNetworked], away[EventLines.AwayTamed]'), 'away[EventLines.AwayTamed], away[EventLines.AwayNotNetworked]'),
    @("X88 a verbose line's failure warned every time - a creature that breaks the not-alerting pass warns every second", "Events.cs", '(if \()FailedOnce\.Add\(where\)(\))', '${1}FailedOnce.Add(where) || true${2}'),
    # Since 0.7.0: the two guards at a caller (the list's close, the reached block) and the file's failure paths
    # outside the listener's walk (Shut, Stop, the stop notice).
    @("X89 the list's close line outside its IsOpen guard - 'List: closed' every frame with no local player", "EntityListWindow.cs", 'if \(!IsOpen\)\r?\n[ \t]*return;\r?\n([ \t]*)IsOpen = false;\r?\n[ \t]*_closedFrame = Time\.frameCount;\r?\n[ \t]*_focusSearch = false;\r?\n[ \t]*_searchFocused = false;\r?\n', "if (IsOpen)`r`n`${1}{`r`n`${1}    IsOpen = false;`r`n`${1}    _closedFrame = Time.frameCount;`r`n`${1}    _focusSearch = false;`r`n`${1}    _searchFocused = false;`r`n`${1}}`r`n"),
    @("X90 Shut without its catch - a header that cannot be written throws out of Open's catch and Awake drops the plugin", "LogFile.cs", 'try\r?\n[ \t]*\{\r?\n[ \t]*writer\.Dispose\(\);\r?\n[ \t]*\}\r?\n[ \t]*catch \(Exception\)\r?\n[ \t]*\{\r?\n[ \t]*// Nothing more can be written to it either way\.\r?\n[ \t]*\}', 'writer.Dispose();'),
    @("X91 Stop without its catch - a closing line that cannot be written throws out of OnDestroy", "LogFile.cs", 'try\r?\n[ \t]*\{\r?\n([ \t]*Logger\.Listeners\.Remove\(tee\);\r?\n[ \t]*tee\.WriteFile\(EventLines\.Closing\(tee\.LeftOutInAll\(\)\)\);\r?\n)[ \t]*\}\r?\n[ \t]*catch \(Exception\)\r?\n[ \t]*\{\r?\n[ \t]*// Closing anyway\.\r?\n[ \t]*\}\r?\n', '${1}'),
    @("X92 the stop notice never cleared - its warning in LogOutput.log every frame once the file stops", "LogFile.cs", '_notice = null;\r?\n[ \t]*(MobTrackerPlugin\.Log\.LogWarning\(notice\);)', '${1}'),
    @("X93 the reached line out of the reached block - 'Track: reached' every frame", "Tracker.cs", '([ \t]*)Events\.TrackReached\(\);\r?\n([ \t]*Stop\(\);\r?\n[ \t]*\}\r?\n)', "`${2}`${1}Events.TrackReached();`r`n"),
    # Since 0.7.0: the alert poll's guards round its verbose lines, and the settings' snapshot.
    @("X94 the alert memory's line above the poll's no-player test - with a player, 'memory cleared' and the not-alerting lines again every second", "WatchAlerts.cs", '([ \t]*)if \(player == null\)\r?\n([ \t]*)\{\r?\n[ \t]*Events\.AlertMemoryClearing\(_gate\.Count\);\r?\n', "`${1}Events.AlertMemoryClearing(_gate.Count);`r`n`${1}if (player == null)`r`n`${2}{`r`n"),
    @("X95 the Auto-track line above the nothing-alerted return - one every second when nothing alerts", "WatchAlerts.cs", '(?s)(Events\.NotAlerting\(_gate, from\);[^\r\n]*\r?\n\r?\n)([ \t]*)(if \(nearest == null\)\r?\n.*?Tracker\.Track\(nearest\);\r?\n[ \t]*\}\r?\n)[ \t]*Events\.AutoTrack\(nearest, sameSide\);\r?\n', "`${1}`${2}Events.AutoTrack(nearest, true);`r`n`${2}`${3}"),
    # 0.7.1: a log line's place against the decision it reports - after Auto-track's test, handed the side it read; and
    # each tracking change's line before the fields it reads change.
    @("X97 the Auto-track line above Auto-track's test - a take said as not taken", "WatchAlerts.cs", '(?s)([ \t]*if \(ModConfig\.AutoTrack\.Value && !Tracker\.IsTrackingCreature\).*?Tracker\.Track\(nearest\);\r?\n[ \t]*\}\r?\n)([ \t]*Events\.AutoTrack\(nearest, sameSide\);\r?\n)', '${2}${1}'),
    @("X98 the Auto-track line handed the other side - an entrance named where there is none", "WatchAlerts.cs", [regex]::Escape("Events.AutoTrack(nearest, sameSide);"), "Events.AutoTrack(nearest, !sameSide);"),
    @("X99 the track line after the fields change - 'replaces' names the new creature itself", "Tracker.cs", '(?s)(Events\.TrackStarting\(character\);[^\r\n]*)(.*?)(Generation\+\+;)', '${2}${3} Events.TrackStarting(character);'),
    @("X100 the area's track line after the fields change - 'replaces' names the new area itself", "Tracker.cs", '(?s)(Events\.TrackStartingArea\(point, name\);[^\r\n]*)(.*?)(Generation\+\+;)', '${2}${3} Events.TrackStartingArea(point, name);'),
    @("X101 the stop line after the tracking is cleared - never written", "Tracker.cs", '(?s)(Events\.TrackStopping\(\);[^\r\n]*)(.*?)(Generation\+\+;)', '${2}${3} Events.TrackStopping();'),
    # 0.7.1: also what those lines are handed - the side Auto-track's test read, Auto-track's own setting, the
    # creature or area being tracked - and where the Auto-track line sits against the test.
    @("X102 the Auto-track line inside Auto-track's outer test - 'off' and 'tracked' never said", "WatchAlerts.cs", '([ \t]*if \(sameSide && !NearestWatched\.IsPending\)\r?\n[ \t]*Tracker\.Track\(nearest\);\r?\n)([ \t]*\}\r?\n)([ \t]*Events\.AutoTrack\(nearest, sameSide\);\r?\n)', '${1}${3}${2}'),
    @("X103 the side's answer discarded, sameSide true - Auto-track crosses dungeon entrances", "WatchAlerts.cs", [regex]::Escape("bool sameSide = Rules.SameLayer(nearest.InInterior(), Character.InInterior(from));"), "Rules.SameLayer(nearest.InInterior(), Character.InInterior(from)); bool sameSide = true;"),
    @("X104 the Auto-track line asks the side again rather than take the test's answer", "WatchAlerts.cs", [regex]::Escape("Events.AutoTrack(nearest, sameSide);"), "Events.AutoTrack(nearest, Rules.SameLayer(nearest.InInterior(), Character.InInterior(from)));"),
    @("X105 Events.AutoTrack tells AutoTrackOutcome that AutoTrack is on - 'off' never said", "Events.cs", [regex]::Escape("ModConfig.AutoTrack.Value, sameSide);"), "true, sameSide);"),
    @("X106 Events.AutoTrack hands AutoTrackOutcome the side inverted", "Events.cs", [regex]::Escape("ModConfig.AutoTrack.Value, sameSide);"), "ModConfig.AutoTrack.Value, !sameSide);"),
    @("X107 the track line handed the creature already tracked, not the new one", "Tracker.cs", [regex]::Escape("Events.TrackStarting(character);"), "Events.TrackStarting(Target);"),
    @("X108 the area's track line handed no name", "Tracker.cs", [regex]::Escape("Events.TrackStartingArea(point, name);"), "Events.TrackStartingArea(point, null);"),
    @("F18 Find area's frame count from 0 again - a search with no pause says over 1 frame(s)", "SpawnFinder.cs", [regex]::Escape("int frames = 1;"), "int frames = 0;"),
    @("F19 the sort's pause not counted - Find area says one frame fewer", "SpawnFinder.cs", '(// The sort gets a frame of its own[^\r\n]*\r?\n)[ \t]*frames\+\+;\r?\n', '${1}'),
    @("F20 a count up with no pause after the sort - Find area says one frame more", "SpawnFinder.cs", '(candidates\.Sort\([^\r\n]*\r?\n)', "`${1}            frames++;`r`n"),
    # 0.7.1: the frame count's other stores, and the count Find area's done line is handed.
    @("F21 pass 2 counts a frame per candidate, not per pause", "SpawnFinder.cs", '(areas\.Add\(centre\);\r?\n[ \t]*\}\r?\n[ \t]*\}\r?\n\r?\n)([ \t]*if \(clock\.ElapsedMilliseconds > FrameBudgetMs\)\r?\n[ \t]*\{\r?\n)[ \t]*frames\+\+;\r?\n', ('${1}                frames++;' + "`r`n" + '${2}')),
    @("F22 the sort's pause counted twice", "SpawnFinder.cs", '(// The sort gets a frame of its own[^\r\n]*\r?\n)([ \t]*)frames\+\+;', '${1}${2}frames += 2;'),
    @("F23 Find area's done line handed frames - 1 - the 0.7.0 under-count back at the call site", "SpawnFinder.cs", [regex]::Escape("Events.FindDone(displayName, total.ElapsedMilliseconds, frames, candidates.Count, areas.Count);"), "Events.FindDone(displayName, total.ElapsedMilliseconds, frames - 1, candidates.Count, areas.Count);"),
    @("F24 Find area's done line handed the candidates as the frames and the frames as the candidates", "SpawnFinder.cs", [regex]::Escape("Events.FindDone(displayName, total.ElapsedMilliseconds, frames, candidates.Count, areas.Count);"), "Events.FindDone(displayName, total.ElapsedMilliseconds, candidates.Count, frames, areas.Count);"),
    @("F25 Find area's done line handed a constant 1 frame", "SpawnFinder.cs", [regex]::Escape("Events.FindDone(displayName, total.ElapsedMilliseconds, frames, candidates.Count, areas.Count);"), "Events.FindDone(displayName, total.ElapsedMilliseconds, 1, candidates.Count, areas.Count);"),
    # 0.7.1: the cfg is saved by ConfigSaver alone - BepInEx's own saving off before the first Bind, one save after the
    # last Bind and after every change from the last handler on the whole cfg, every failure caught and said once.
    @("C1 BepInEx's saving never turned off - a read-only cfg throws out of the first Bind, and out of every click", "Plugin.cs", "[ \t]*ConfigSaver\.Take\(Config\);[^\r\n]*\r?\n", ""),
    @("C2 BepInEx's saving turned off after LogFile.Start - a read-only cfg still throws out of its first Bind", "Plugin.cs", '([ \t]*ConfigSaver\.Take\(Config\);[^\r\n]*\r?\n)([ \t]*LogFile\.Start\([^\r\n]*\r?\n)', '${2}${1}'),
    @("C3 SaveOnConfigSet left on - BepInEx saves before the handlers again", "ConfigSaver.cs", [regex]::Escape("file.SaveOnConfigSet = false;"), "file.SaveOnConfigSet = true;"),
    @("C4 the saver watched before ModConfig.Bind - every Bind of a default saves, and the saver runs before the settings' own handlers", "Plugin.cs", '([ \t]*ModConfig\.Bind\(Config\);\r?\n[ \t]*LogFile\.Bound\(Config\);\r?\n)([ \t]*ConfigSaver\.Watch\(Config\);[^\r\n]*\r?\n)', '${2}${1}'),
    @("C5 the saver never watched - no change is saved, nor the file at the start", "Plugin.cs", "[ \t]*ConfigSaver\.Watch\(Config\);[^\r\n]*\r?\n", ""),
    @("C6 the saver's handler never added - no change is saved", "ConfigSaver.cs", "[ \t]*file\.SettingChanged \+= SettingChanged;\r?\n", ""),
    @("C7 no save at the start - a missing cfg is never made, new settings never written to it", "ConfigSaver.cs", "[ \t]*Save\(""at the game's start""\);\r?\n", ""),
    @("C8 the save's catch gone - a read-only cfg throws out of Awake, and BepInEx logs every change as an error", "ConfigSaver.cs", '(?s)try\r?\n[ \t]*\{\r?\n[ \t]*_file\.Save\(\);\r?\n[ \t]*\}\r?\n[ \t]*catch \(Exception e\)\r?\n[ \t]*\{.*?return;\r?\n[ \t]*\}', '_file.Save();'),
    @("C9 the failure said at every save - a warning per ConfigurationManager keystroke", "ConfigSaver.cs", 'if \(!_failing\)(\r?\n[ \t]*\{\r?\n[ \t]*_failing = true;)', 'if (true)${1}'),
    @("C10 a save that works again never said", "ConfigSaver.cs", "[ \t]*MobTrackerPlugin\.Log\.LogInfo\(EventLines\.CfgSavedAgain\(when\)\);\r?\n", ""),
    @("C11 the failure named by its message - the cfg's full path, the Windows account folder in it, in LogOutput.log", "ConfigSaver.cs", [regex]::Escape("EventLines.CfgNotSaved(when, e.GetType().Name)"), "EventLines.CfgNotSaved(when, e.Message)"),
    @("C12 the saver ignores ConfigSaver.Each - the session reset saves four times", "ConfigSaver.cs", 'if \(Each\)\r?\n[ \t]*(Save\("after a change"\);)', '${1}'),
    @("C13 a window click saves the cfg itself - BepInEx's uncaught save inside OnGUI again", "EntityListWindow.cs", [regex]::Escape("ModConfig.Guide.Value = path ? GuideMode.Arrow : GuideMode.GroundPath;"), "{ ModConfig.Guide.Value = path ? GuideMode.Arrow : GuideMode.GroundPath; ModConfig.Guide.ConfigFile.Save(); }"),
    @("C14 the session reset turns BepInEx's saving back on - its writes save before their handlers again", "ModConfig.cs", "([ \t]*ConfigSaver\.Each = false;\r?\n)", '${1}            WatchlistEntry.ConfigFile.SaveOnConfigSet = true;' + "`r`n"),
    @("C15 no last try at quit - a change made while the cfg was read-only is lost although it is writable again", "Plugin.cs", "[ \t]*ConfigSaver\.Stop\(\);\r?\n", ""),
    @("C16 the last try after LogFile.Stop - its line never reaches MobTracker.log", "Plugin.cs", '([ \t]*ConfigSaver\.Stop\(\);\r?\n)([ \t]*_harmony\?\.UnpatchSelf\(\);\r?\n[ \t]*LogFile\.Stop\(\);\r?\n)', '${2}${1}'),
    @("C17 a save at every quit, failed or not", "ConfigSaver.cs", 'if \(_failing\)(\r?\n[ \t]*Save\("as the game quits"\);)', 'if (true)${1}'),
    # 0.7.1: ConfigSaver's own body - each of these fails its exact shape.
    @("C18 _failing never reset once a save works - 'saved again' at every later save", "ConfigSaver.cs", "[ \t]*_failing = false;\r?\n", ""),
    @("C19 the catch's return gone - a failure falls through to the recovery branch", "ConfigSaver.cs", '([ \t]*MobTrackerPlugin\.Log\.LogWarning\(EventLines\.CfgNotSaved\(when, e\.GetType\(\)\.Name\)\);\r?\n[ \t]*\}\r?\n)[ \t]*return;\r?\n', '${1}'),
    @("C20 _failing set before its guard - no failure is ever said", "ConfigSaver.cs", '([ \t]*)if \(!_failing\)(\r?\n[ \t]*\{)\r?\n[ \t]*_failing = true;', ('${1}_failing = true;' + "`r`n" + '${1}if (!_failing)${2}')),
    @("C21 the save's catch narrowed to IOException - a read-only cfg's UnauthorizedAccessException escapes", "ConfigSaver.cs", [regex]::Escape("catch (Exception e)"), "catch (System.IO.IOException e)"),
    @("C22 the last try at quit inverted - a save at every quit that did not fail, none after one that did", "ConfigSaver.cs", 'if \(_failing\)(\r?\n[ \t]*Save\("as the game quits"\);)', 'if (!_failing)${1}'),
    @("C23 the start's save before the handler is added", "ConfigSaver.cs", '([ \t]*file\.SettingChanged \+= SettingChanged;\r?\n)([ \t]*Save\("at the game''s start"\);\r?\n)', '${2}${1}'),
    @("C24 Take keeps no file - every save throws (NullReferenceException) and is said as a failure", "ConfigSaver.cs", "[ \t]*_file = file;\r?\n", ""),
    @("C25 the saver's handler inverted - saves only while the session reset writes", "ConfigSaver.cs", [regex]::Escape("if (Each)"), "if (!Each)"),
    @("C26 no save after a change while failing - a writable cfg again waits for the quit", "ConfigSaver.cs", [regex]::Escape("if (Each)"), "if (Each && !_failing)"),
    # 0.7.1: the session reset's single save, said as such, and ConfigSaver.Each - off only around the reset's writes.
    @("C27 the session reset saves through Stop - only when the last save failed", "ModConfig.cs", [regex]::Escape("ConfigSaver.Save(""after the session reset"");"), "ConfigSaver.Stop();"),
    @("C28 the session reset's save inside the finally, before Each is put back", "ModConfig.cs", '(?s)(finally\r?\n[ \t]*\{\r?\n)([ \t]*ConfigSaver\.Each = saveEach;\r?\n.*?)[ \t]*ConfigSaver\.Save\("after the session reset"\);\r?\n', ('${1}                ConfigSaver.Save("after the session reset");' + "`r`n" + '${2}')),
    @("C29 ConfigSaver.Each put back as a constant true, not the value read before", "ModConfig.cs", [regex]::Escape("ConfigSaver.Each = saveEach;"), "ConfigSaver.Each = true;"),
    @("C30 ConfigSaver.Each turned off after the first write - the watchlist's default saved on its own", "ModConfig.cs", '([ \t]*ConfigSaver\.Each = false;\r?\n)([ \t]*try\r?\n[ \t]*\{\r?\n[ \t]*WatchlistEntry\.Value = \(string\)WatchlistEntry\.DefaultValue;\r?\n)', '${2}${1}'),
    @("C31 the session reset saves before its writes - the file keeps the session's values", "ModConfig.cs", '(?s)([ \t]*ConfigSaver\.Each = false;\r?\n)(.*?)[ \t]*ConfigSaver\.Save\("after the session reset"\);\r?\n', ('${1}            ConfigSaver.Save("after the session reset");' + "`r`n" + '${2}')),
    @("C38 the session reset's save says 'after a change' - its warning and its 'saved again' line name the wrong moment", "ModConfig.cs", [regex]::Escape("ConfigSaver.Save(""after the session reset"");"), "ConfigSaver.Save(""after a change"");"),
    @("C39 a window toggle turns ConfigSaver.Each off and never back - no change saved again", "ModConfig.cs", [regex]::Escape("WatchlistEntry.Value = Rules.FormatWatchlist(set);"), "ConfigSaver.Each = false; WatchlistEntry.Value = Rules.FormatWatchlist(set);"),
    @("C40 ConfigSaver.Each starts false - no change is saved until a session reset", "ConfigSaver.cs", [regex]::Escape("public static bool Each = true;"), "public static bool Each = false;"),
    # 0.7.1: the plugin's start and quit, and who else may touch the cfg.
    @("C32 OnDestroy saves once more after Stop, failed or not", "Plugin.cs", [regex]::Escape("ConfigSaver.Stop();"), "ConfigSaver.Stop(); ConfigSaver.Save(""as the game quits"");"),
    @("C33 OnDestroy's last try after UnpatchSelf", "Plugin.cs", '([ \t]*ConfigSaver\.Stop\(\);\r?\n)([ \t]*_harmony\?\.UnpatchSelf\(\);\r?\n)', '${2}${1}'),
    @("C34 the saver watched after Ding.Init", "Plugin.cs", '([ \t]*ConfigSaver\.Watch\(Config\);[^\r\n]*\r?\n)([ \t]*Ding\.Init\(gameObject\);\r?\n)', '${2}${1}'),
    @("C35 a setting bound after the saver is watched", "Plugin.cs", '([ \t]*ConfigSaver\.Watch\(Config\);[^\r\n]*\r?\n)', ('${1}            Config.Bind("General", "Extra", false, "a late setting");' + "`r`n")),
    @("C36 Events' cfg handler saves the cfg itself", "Events.cs", [regex]::Escape("SettingChanged(args.ChangedSetting);"), "SettingChanged(args.ChangedSetting); ConfigSaver.Save(""after a change"");"),
    @("C37 Events.Watch turns BepInEx's saving back on", "Events.cs", [regex]::Escape("config.SettingChanged += OnSettingChanged;"), "config.SettingChanged += OnSettingChanged; config.SaveOnConfigSet = true;"),
    @("X96 Events.Snapshot without its catch - a setting's value that cannot be read leaves ModConfig.Bind, in Awake", "Events.cs", '[ \t]*try\r?\n[ \t]*\{\r?\n([ \t]*if \(Config == null\)\r?\n[ \t]*return null;\r?\n[ \t]*pairs = LogFile\.Settings\(Config\);\r?\n[ \t]*Values\.Clear\(\);\r?\n[ \t]*foreach \(KeyValuePair<string, string> pair in pairs\)\r?\n[ \t]*Values\[pair\.Key\] = pair\.Value;\r?\n)[ \t]*\}\r?\n[ \t]*catch \(Exception e\) \{ Failed\("Snapshot", e\); \}\r?\n', '${1}')
)
$ids = @($mutants | ForEach-Object { ($_[0] -split " ")[0] })
$unknown = @($Only | Where-Object { $ids -notcontains $_ })
if ($unknown.Count -gt 0) {
    Write-Output ("Unknown mutant id(s): {0}. The ids are: {1}" -f ($unknown -join ", "), ($ids -join ", "))
    Finish 1
}

# Runs tools\preflight.ps1 in this process - no console window opens for it - and returns its output lines and exit
# code. Its 'exit' ends only the script and sets $LASTEXITCODE (cleared first, so a run that never reached its end
# counts as failed, 2); a preflight that throws is caught and counts as failed too.
function Invoke-Preflight([string]$script, [hashtable]$arguments) {
    $global:LASTEXITCODE = $null
    # Each line is kept as it comes, so a preflight that throws part-way still shows what it printed before.
    $lines = New-Object System.Collections.Generic.List[string]
    $code = $null
    try {
        & $script @arguments 2>&1 | ForEach-Object { $lines.Add("$_") }
        $code = $global:LASTEXITCODE
    } catch {
        $lines.Add("preflight stopped: " + $_.Exception.Message)
        $code = 2
    }
    if ($null -eq $code) { $code = 2 }
    return [pscustomobject]@{ Code = $code; Lines = @($lines) }
}
function Build-And-Check {
    # Returns the lines to show and preflight's exit code ($null if the copy did not build); it prints nothing
    # itself, since anything a PowerShell function writes becomes part of what it returns.
    # --no-incremental: the copies keep their files' old timestamps, so MSBuild would take the last mutant's
    # compiled output for up to date.
    $dll = Join-Path $work "build\MobTracker.dll"
    if (Test-Path -LiteralPath $dll) { Remove-Item -LiteralPath $dll }
    # Continue around the child processes: under Stop, their error output through 2>&1 would end the run with a
    # NativeCommandError rather than count as a failed build or a caught mutant.
    $ErrorActionPreference = "Continue"
    $b = & dotnet build (Join-Path $work "MobTracker.csproj") -c Release --no-incremental -nologo -v q 2>&1 | Out-String
    if (-not (Test-Path -LiteralPath $dll)) { return [pscustomobject]@{ Code = $null; Lines = @("    BUILD FAILED", $b) } }
    $pre = Invoke-Preflight (Join-Path $work "tools\preflight.ps1") @{ Plugin = $dll }
    $code = $pre.Code
    $lines = @($pre.Lines | Where-Object { "$_" -cmatch "FAIL" } | ForEach-Object { "      $_" })
    $tail = @($pre.Lines | Select-Object -Last 5 | ForEach-Object { "      $_" })
    # What the TomTom/Wayfinder half was checked against: preflight's line per DLL, or its note that there is none.
    $waypointer = @($pre.Lines | Where-Object { "$_" -cmatch "(TomTom|Wayfinder)\.dll \(|neither TomTom nor Wayfinder" })
    return [pscustomobject]@{ Code = $code; Lines = $lines; Tail = $tail; Waypointer = $waypointer }
}

# A fresh copy of the tracked files as they are in the working tree, and of the publicized game assemblies - into an
# emptied folder, or a file renamed or deleted since the last run would stay in the copy and be compiled with it. A
# directory link there is refused rather than emptied through.
if (Test-Path -LiteralPath $work) {
    $isLink = (Get-Item -LiteralPath $work -Force).Attributes -band [IO.FileAttributes]::ReparsePoint
    $links = @(Get-ChildItem -LiteralPath $work -Recurse -Force -Attributes ReparsePoint -ErrorAction SilentlyContinue)
    if ($isLink -or $links.Count -gt 0) {
        Write-Output "$work is or holds a directory link - move it away first."
        # Also forgotten here, so the run leaves the link it refused, and anything inside build\mutants, as it found them.
        $work = $null
        Finish 1
    }
    [IO.Directory]::Delete($work, $true)
}
New-Item -ItemType Directory -Force -Path $work | Out-Null
foreach ($f in @(& git -C $repo ls-files --cached --others --exclude-standard)) {
    if (-not (Test-Path -LiteralPath (Join-Path $repo $f) -PathType Leaf)) { continue }   # tracked, but deleted in the working tree
    $dest = Join-Path $work $f
    New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo $f) -Destination $dest -Force
}
if (Test-Path -LiteralPath (Join-Path $repo "lib")) {
    New-Item -ItemType Directory -Force -Path (Join-Path $work "lib") | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath (Join-Path $repo "lib")) {
        Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $work "lib") -Recurse -Force
    }
}

$bad = 0
# The builds are removed however the run ends - its verdict, an error, or Ctrl+C (which runs finally, not trap).
try {
Write-Output "=== unmutated copy"
$r = Build-And-Check
$r.Lines
if ($r.Code -ne 0) { Write-Output "    the unmutated copy does not build or pass preflight - fix that first"; Finish 1 }
Write-Output "    PASSED, as it should"
foreach ($line in @($r.Waypointer)) { Write-Output ("    checked against: " + $line.Trim()) }

foreach ($m in $mutants) {
    $id = ($m[0] -split " ")[0]
    if ($Only.Count -gt 0 -and $Only -notcontains $id) { continue }
    $path = Join-Path $work $m[1]
    $orig = [IO.File]::ReadAllText($path)
    Write-Output ("=== {0}" -f $m[0])
    $n = ([regex]::Matches($orig, $m[2])).Count
    if ($n -ne 1) { Write-Output ("    NOT PLANTED: the pattern matches {0} times in {1}" -f $n, $m[1]); $bad++; continue }
    [IO.File]::WriteAllText($path, ([regex]$m[2]).Replace($orig, $m[3], 1), $enc)
    $r = Build-And-Check
    [IO.File]::WriteAllText($path, $orig, $enc)
    $r.Lines
    if ($null -eq $r.Code) { $bad++ }
    elseif ($r.Code -ne 0 -and $r.Lines.Count -gt 0) { Write-Output "    caught" }
    elseif ($r.Code -ne 0) { Write-Output ("    NOT PROVEN - preflight exited {0} without a FAIL line; its last lines:" -f $r.Code); $r.Tail; $bad++ }
    else { Write-Output "    NOT CAUGHT - preflight passed a build with this defect"; $bad++ }
}

Write-Output ""
if ($bad -eq 0) { Write-Output "MUTANTS: every planted defect fails preflight."; Finish 0 }
Write-Output "MUTANTS: $bad mutant(s) not planted, not built, not caught or not proven."
Finish 1
} finally { Remove-MutantBuilds }
