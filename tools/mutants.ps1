<#
.SYNOPSIS
  Proves tools\preflight.ps1 catches the defects it is there for: plants each one in a copy of the source,
  builds it and expects preflight to FAIL.

.DESCRIPTION
  Works in build\mutants\ (git ignores build\), emptied first, on a copy of the working tree's tracked files and of
  lib\, so the repository itself is never edited. Each mutant is one regex replacement that must match exactly once.
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
# -ValheimDir reaches the copy's MobTracker.csproj and tools\preflight.ps1 through VALHEIM; the caller's value
# comes back when this script ends, however it ends.
$callersValheim = $env:VALHEIM
function Finish([int]$code) { $env:VALHEIM = $callersValheim; exit $code }
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
    @("N16 the re-track takes the nearest creature of any type", "NearestWatched.cs", [regex]::Escape("string.Equals(Creature.PrefabName(character), Pending.Prefab, StringComparison.Ordinal),"), "true,"),
    @("N17 unwatching the type does not end the wait", "NearestWatched.cs", [regex]::Escape("ModConfig.Watchlist.Contains(Pending.Prefab)))"), "true))"),
    @("N18 Track never records the prefab - the previous target's type, or none, is looked for", "Tracker.cs", "[ \t]*_targetPrefab = Creature\.PrefabName\(character\);\r?\n", ""),
    @("N19 no 5 s wait: the loss is stamped at time 0", "NearestWatched.cs", [regex]::Escape("tamed, Time.time);"), "tamed, 0f);"),
    @("N20 it looks on every frame it is not yet time to", "NearestWatched.cs", [regex]::Escape("if (!Pending.ShouldLook(Time.time))"), "if (Pending.ShouldLook(Time.time))"),
    @("N21 a loss schedules only with the option off", "NearestWatched.cs", [regex]::Escape("Pending.Lost(prefab, ModConfig.AlwaysTrackNearest.Value,"), "Pending.Lost(prefab, !ModConfig.AlwaysTrackNearest.Value,"),
    @("N22 a loss schedules only for unwatched types", "NearestWatched.cs", [regex]::Escape("ModConfig.Watchlist.Contains(prefab), tamed"), "!ModConfig.Watchlist.Contains(prefab), tamed"),
    @("N23 Stop tracking shows only when nothing is pending", "EntityListWindow.cs", [regex]::Escape("(Tracker.IsTracking || NearestWatched.IsPending)"), "(Tracker.IsTracking || !NearestWatched.IsPending)"),
    @("N24 the re-track looks at dead and player entries", "NearestWatched.cs", "[ \t]*if \(!Creature\.IsListable\(character\)\)\r?\n[ \t]*continue;\r?\n", ""),
    @("N25 logging out schedules a re-track", "Tracker.cs", [regex]::Escape("Stop(); // logged out; nobody to tell"), "{ Stop(); NearestWatched.Lost(_targetPrefab, _targetTamed); }"),
    @("N26 the candidate test inverted", "NearestWatched.cs", [regex]::Escape("if (Retrack.IsCandidate("), "if (!Retrack.IsCandidate("),
    @("N27 the end-of-wait test inverted", "NearestWatched.cs", [regex]::Escape("player == null || Retrack.EndsWait("), "player == null || !Retrack.EndsWait("),
    @("N28 a watch alert for the awaited type takes the arrow during the wait", "WatchAlerts.cs", "\r?\n\s*&& !NearestWatched\.IsPendingFor\(Creature\.PrefabName\(nearest\)\)", ""),
    @("N29 no alert of any watched type auto-tracks while a wait is on", "WatchAlerts.cs", [regex]::Escape("NearestWatched.IsPendingFor(Creature.PrefabName(nearest))"), "NearestWatched.IsPending"),
    @("N30 losing a tamed creature starts a hunt", "Tracker.cs", [regex]::Escape("NearestWatched.Lost(_targetPrefab, _targetTamed);"), "NearestWatched.Lost(_targetPrefab, false);"),
    @("N31 the re-track takes a creature the game is removing", "NearestWatched.cs", [regex]::Escape("character.GetZDOID() != ZDOID.None,"), "true,"),
    @("N32 a dead player's wait goes on", "NearestWatched.cs", [regex]::Escape("Retrack.EndsWait(player.IsDead(),"), "Retrack.EndsWait(false,"),
    @("N33 tameness read after the creature left the network", "Tracker.cs", [regex]::Escape("if (!_isPoint && Target.GetZDOID() != ZDOID.None)"), "if (!_isPoint)"),
    @("N34 a loss of a wild creature counts as tamed, and a pet's as wild", "NearestWatched.cs", [regex]::Escape("ModConfig.Watchlist.Contains(prefab), tamed, Time.time"), "ModConfig.Watchlist.Contains(prefab), !tamed, Time.time"),
    @("N35 the tameness refresh inverted - no wait ever starts", "Tracker.cs", [regex]::Escape("_targetTamed = Target.IsTamed();"), "_targetTamed = !Target.IsTamed();"),
    @("N36 the tameness refresh a constant - no wait ever starts", "Tracker.cs", [regex]::Escape("_targetTamed = Target.IsTamed();"), "_targetTamed = true;"),
    @("N37 the refresh guard reads the player - a lost pet counts as wild", "Tracker.cs", [regex]::Escape("Target.GetZDOID() != ZDOID.None"), "player.GetZDOID() != ZDOID.None"),
    @("N38 a loss passes a constant type", "NearestWatched.cs", [regex]::Escape("Pending.Lost(prefab,"), 'Pending.Lost("",'),
    @("N39 a loss passes the type lower-cased - the match never finds it", "NearestWatched.cs", [regex]::Escape("Pending.Lost(prefab,"), "Pending.Lost(prefab.ToLowerInvariant(),"),
    @("N40 a loss asks the watchlist about a constant", "NearestWatched.cs", [regex]::Escape("ModConfig.Watchlist.Contains(prefab), tamed"), 'ModConfig.Watchlist.Contains(""), tamed'),
    @("N41 the end of the wait returns without cancelling - it only pauses", "NearestWatched.cs", "(ModConfig\.Watchlist\.Contains\(Pending\.Prefab\)\)\)\r?\n\s*\{\r?\n)\s*Pending\.Cancel\(\);\r?\n", '${1}'),
    @("N42 no player only pauses the wait - it survives into the next world", "NearestWatched.cs", [regex]::Escape("if (player == null || Retrack.EndsWait("), "if (player == null) return; if (Retrack.EndsWait("),
    @("N43 the nearest comparison inverted - never picks anything", "NearestWatched.cs", [regex]::Escape("&& distance < nearestDistance)"), "&& distance > nearestDistance)"),
    @("N44 the nearest distance never updated - takes the last candidate in list order", "NearestWatched.cs", "[ \t]*nearestDistance = distance;\r?\n", ""),
    @("N45 distance from the player to the player - radius and nearest ignored", "NearestWatched.cs", [regex]::Escape("Vector3.Distance(from, character.transform.position)"), "Vector3.Distance(from, from)"),
    @("N46 Track records the display name as the type - starred types never re-track", "Tracker.cs", [regex]::Escape("_targetPrefab = Creature.PrefabName(character);"), "_targetPrefab = Creature.DisplayName(character);"),
    @("N47 the networked test reads the player", "NearestWatched.cs", [regex]::Escape("character.GetZDOID() != ZDOID.None,"), "player.GetZDOID() != ZDOID.None,"),
    @("N48 the star test reads the player's level", "NearestWatched.cs", [regex]::Escape("StarSets.Accepts(WatchAlerts.EffectiveAlertStars, character.GetLevel())"), "StarSets.Accepts(WatchAlerts.EffectiveAlertStars, player.GetLevel())"),
    @("N49 the tamed test reads the player", "NearestWatched.cs", [regex]::Escape("character.IsTamed(),"), "player.IsTamed(),"),
    @("N50 IsPendingFor stands down for every type", "NearestWatched.cs", [regex]::Escape("return Pending.IsPendingFor(prefab);"), "return Pending.IsPending;"),
    @("N51 IsPending always false - Stop tracking hidden during a wait", "NearestWatched.cs", [regex]::Escape("get { return Pending.IsPending; }"), "get { return false; }"),
    @("N52 Cancel emptied - Stop tracking cannot call the wait off", "NearestWatched.cs", "(public static void Cancel\(\)\r?\n\s*\{\r?\n)\s*Pending\.Cancel\(\);\r?\n", '${1}'),
    @("N53 the deferral asks about the player, not the alerting creature", "WatchAlerts.cs", [regex]::Escape("NearestWatched.IsPendingFor(Creature.PrefabName(nearest))"), "NearestWatched.IsPendingFor(Creature.PrefabName(player))"),
    @("N54 Stop tracking starts the wait again", "NearestWatched.cs", "(public static void Cancel\(\)\r?\n\s*\{\r?\n\s*)Pending\.Cancel\(\);", '${1}Pending.Lost(Pending.Prefab, true, true, false, Time.time);'),
    @("N55 Track records tameness inverted", "Tracker.cs", [regex]::Escape("_targetTamed = character.IsTamed();"), "_targetTamed = !character.IsTamed();"),
    @("N56 the re-track ignores the Alerts stars", "NearestWatched.cs", [regex]::Escape("StarSets.Accepts(WatchAlerts.EffectiveAlertStars, character.GetLevel()),"), "true,"),
    # Neither the re-track nor Auto-track crosses a dungeon entrance (a dungeon's interior is some 5 km up).
    @("L1 the re-track takes a creature across a dungeon entrance", "NearestWatched.cs", [regex]::Escape("Rules.SameLayer(character.InInterior(), playerInside))"), "true)"),
    @("L2 the re-track compares the player's side with itself", "NearestWatched.cs", [regex]::Escape("Rules.SameLayer(character.InInterior(),"), "Rules.SameLayer(player.InInterior(),"),
    @("L3 the re-track reads the creature's side for the player's too", "NearestWatched.cs", [regex]::Escape("Rules.SameLayer(character.InInterior(), playerInside)"), "Rules.SameLayer(character.InInterior(), character.InInterior())"),
    @("L4 the player's side a constant - outside, even in a dungeon", "NearestWatched.cs", [regex]::Escape("bool playerInside = Character.InInterior(from);"), "bool playerInside = false;"),
    @("L5 Auto-track crosses a dungeon entrance", "WatchAlerts.cs", "\r?\n\s*&& Rules\.SameLayer\(nearest\.InInterior\(\), Character\.InInterior\(from\)\)", ""),
    @("L6 Auto-track only across a dungeon entrance", "WatchAlerts.cs", [regex]::Escape("&& Rules.SameLayer("), "&& !Rules.SameLayer("),
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
    @("U16 OnGUI drops the moved window's rect - the test keeps the old place", "EntityListWindow.cs", [regex]::Escape("_rect = GUILayout.Window("), "GUILayout.Window(")
)
$ids = @($mutants | ForEach-Object { ($_[0] -split " ")[0] })
$unknown = @($Only | Where-Object { $ids -notcontains $_ })
if ($unknown.Count -gt 0) {
    Write-Output ("Unknown mutant id(s): {0}. The ids are: {1}" -f ($unknown -join ", "), ($ids -join ", "))
    Finish 1
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
    $global:LASTEXITCODE = $null   # a preflight that could not start must not read dotnet's 0 as a pass
    $console = (Join-Path $PSHOME $(if ($PSVersionTable.PSEdition -eq "Core") { "pwsh.exe" } else { "powershell.exe" }))   # not the host: inside the ISE that is the ISE
    $out = & $console -NoProfile -ExecutionPolicy Bypass -File (Join-Path $work "tools\preflight.ps1") -Plugin $dll 2>&1 | ForEach-Object { "$_" }
    $code = $global:LASTEXITCODE
    $lines = @($out | Where-Object { "$_" -cmatch "FAIL" } | ForEach-Object { "      $_" })
    $tail = @($out | Select-Object -Last 5 | ForEach-Object { "      $_" })
    return [pscustomobject]@{ Code = $code; Lines = $lines; Tail = $tail }
}

# A fresh copy of the tracked files as they are in the working tree, and of the publicized game assemblies - into an
# emptied folder, or a file renamed or deleted since the last run would stay in the copy and be compiled with it. A
# directory link there is refused rather than emptied through.
if (Test-Path -LiteralPath $work) {
    $isLink = (Get-Item -LiteralPath $work -Force).Attributes -band [IO.FileAttributes]::ReparsePoint
    $links = @(Get-ChildItem -LiteralPath $work -Recurse -Force -Attributes ReparsePoint -ErrorAction SilentlyContinue)
    if ($isLink -or $links.Count -gt 0) { Write-Output "$work is or holds a directory link - move it away first."; Finish 1 }
    [IO.Directory]::Delete($work, $true)
}
New-Item -ItemType Directory -Force -Path $work | Out-Null
foreach ($f in @(& git -C $repo ls-files)) {
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
Write-Output "=== unmutated copy"
$r = Build-And-Check
$r.Lines
if ($r.Code -ne 0) { Write-Output "    the unmutated copy does not build or pass preflight - fix that first"; Finish 1 }
Write-Output "    PASSED, as it should"

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
