<#
.SYNOPSIS
  Proves tools\preflight.ps1 catches the defects it is there for: plants each one in a copy of the source,
  builds it and expects preflight to FAIL.

.DESCRIPTION
  Works in build\mutants\ (git ignores build\), on a copy of the working tree's tracked files and of lib\, so the
  repository itself is never edited. Each mutant is one regex replacement that must match exactly once. First the
  unmutated copy is built and must PASS, so a failure below is the mutant's and not the copy's. Exits 1 if
  -ValheimDir holds no Valheim install, an -Only id is not one of its mutants, the clean copy fails, a mutant
  cannot be planted or built, or any mutant passes preflight.

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
    # The star filters (the list's and the alerts' are the same type, so crossing them compiles).
    @("S1 WatchAlerts reads the list's filter", "WatchAlerts.cs", [regex]::Escape("StarFilters.Accepts(ModConfig.AlertStars.Value, character.GetLevel())"), "StarFilters.Accepts(ModConfig.ListStars.Value, character.GetLevel())"),
    @("S2 Refresh reads the alerts' filter", "EntityListWindow.cs", [regex]::Escape("StarFilters.Accepts(_appliedListStars, character.GetLevel())"), "StarFilters.Accepts(ModConfig.AlertStars.Value, character.GetLevel())"),
    @("S3 Update never stores the applied list filter", "EntityListWindow.cs", ("[ \t]*" + [regex]::Escape("_appliedListStars = ModConfig.ListStars.Value;") + "\r?\n"), ""),
    @("S4 the Alerts: row reads and writes the list's filter", "EntityListWindow.cs", "(?s)(GUILayout\.Label\(""Alerts:"", RowLabelWidth\);.*?)ModConfig\.AlertStars\.Value(.*?)ModConfig\.AlertStars\.Value", '${1}ModConfig.ListStars.Value${2}ModConfig.ListStars.Value'),
    @("S5 the List: row writes the alerts' filter", "EntityListWindow.cs", [regex]::Escape("ModConfig.ListStars.Value = StarFilters.FromIndex(pickedList);"), "ModConfig.AlertStars.Value = StarFilters.FromIndex(pickedList);"),
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
    @("N1 the re-track chooses by the list's star filter", "NearestWatched.cs", [regex]::Escape("StarFilters.Accepts(ModConfig.AlertStars.Value"), "StarFilters.Accepts(ModConfig.ListStars.Value"),
    @("N2 the re-track takes tamed creatures", "NearestWatched.cs", [regex]::Escape("character.IsTamed(),"), "false,"),
    @("N3 a loss schedules a re-track with the option off", "NearestWatched.cs", [regex]::Escape("Pending.Lost(prefab, ModConfig.AlwaysTrackNearest.Value,"), "Pending.Lost(prefab, true,"),
    @("N4 the player's own Stop schedules a re-track", "Tracker.cs", "(public static void Stop\(\)\r?\n\s*\{\r?\n)", '${1}            NearestWatched.Lost(_targetPrefab, _targetTamed);' + "`n"),
    @("N5 a lost creature schedules nothing", "Tracker.cs", "[ \t]*NearestWatched\.Lost\(_targetPrefab, _targetTamed\);[^\r\n]*\r?\n", ""),
    @("N6 the wait does not give way to other tracking", "NearestWatched.cs", [regex]::Escape("player.IsDead(), Tracker.IsTracking,"), "player.IsDead(), false,"),
    @("N7 turning the option off does not end the wait", "NearestWatched.cs", [regex]::Escape("Tracker.IsTracking, ModConfig.AlwaysTrackNearest.Value,"), "Tracker.IsTracking, true,"),
    @("N8 the component is never added", "Plugin.cs", "[ \t]*gameObject\.AddComponent<NearestWatched>\(\);\r?\n", ""),
    @("N9 Stop tracking cannot call off the wait", "EntityListWindow.cs", "[ \t]*NearestWatched\.Cancel\(\);\r?\n", ""),
    @("N10 the re-track ignores AlertRadius", "NearestWatched.cs", [regex]::Escape("Rules.WithinRadius(distance, ModConfig.AlertRadius.Value))"), "true)"),
    @("N11 the re-track takes only tamed creatures", "NearestWatched.cs", [regex]::Escape("character.IsTamed(),"), "!character.IsTamed(),"),
    @("N12 the re-track takes only the stars the Alerts filter leaves out", "NearestWatched.cs", [regex]::Escape("StarFilters.Accepts(ModConfig.AlertStars.Value, character.GetLevel()),"), "!StarFilters.Accepts(ModConfig.AlertStars.Value, character.GetLevel()),"),
    @("N13 the re-track takes only creatures outside AlertRadius", "NearestWatched.cs", [regex]::Escape("Rules.WithinRadius(distance, ModConfig.AlertRadius.Value))"), "!Rules.WithinRadius(distance, ModConfig.AlertRadius.Value))"),
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
    @("N48 the star test reads the player's level", "NearestWatched.cs", [regex]::Escape("StarFilters.Accepts(ModConfig.AlertStars.Value, character.GetLevel())"), "StarFilters.Accepts(ModConfig.AlertStars.Value, player.GetLevel())"),
    @("N49 the tamed test reads the player", "NearestWatched.cs", [regex]::Escape("character.IsTamed(),"), "player.IsTamed(),"),
    @("N50 IsPendingFor stands down for every type", "NearestWatched.cs", [regex]::Escape("return Pending.IsPendingFor(prefab);"), "return Pending.IsPending;"),
    @("N51 IsPending always false - Stop tracking hidden during a wait", "NearestWatched.cs", [regex]::Escape("get { return Pending.IsPending; }"), "get { return false; }"),
    @("N52 Cancel emptied - Stop tracking cannot call the wait off", "NearestWatched.cs", "(public static void Cancel\(\)\r?\n\s*\{\r?\n)\s*Pending\.Cancel\(\);\r?\n", '${1}'),
    @("N53 the deferral asks about the player, not the alerting creature", "WatchAlerts.cs", [regex]::Escape("NearestWatched.IsPendingFor(Creature.PrefabName(nearest))"), "NearestWatched.IsPendingFor(Creature.PrefabName(player))"),
    @("N54 Stop tracking starts the wait again", "NearestWatched.cs", "(public static void Cancel\(\)\r?\n\s*\{\r?\n\s*)Pending\.Cancel\(\);", '${1}Pending.Lost(Pending.Prefab, true, true, false, Time.time);'),
    @("N55 Track records tameness inverted", "Tracker.cs", [regex]::Escape("_targetTamed = character.IsTamed();"), "_targetTamed = !character.IsTamed();")
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
    return [pscustomobject]@{ Code = $code; Lines = $lines }
}

# A fresh copy of the tracked files as they are in the working tree, and of the publicized game assemblies.
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
    elseif ($r.Code -ne 0) { Write-Output "    caught" }
    else { Write-Output "    NOT CAUGHT - preflight passed a build with this defect"; $bad++ }
}

Write-Output ""
if ($bad -eq 0) { Write-Output "MUTANTS: every planted defect fails preflight."; Finish 0 }
Write-Output "MUTANTS: $bad mutant(s) not planted, not built or not caught."
Finish 1
