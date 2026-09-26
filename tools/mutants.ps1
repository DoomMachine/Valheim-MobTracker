<#
.SYNOPSIS
  Proves tools\preflight.ps1 catches the defects it is there for: plants each one in a copy of the source,
  builds it and expects preflight to FAIL.

.DESCRIPTION
  Works in build\mutants\ (git ignores build\), on a copy of the working tree's tracked files and of lib\, so the
  repository itself is never edited. Each mutant is one regex replacement that must match exactly once. First the
  unmutated copy is built and must PASS, so a failure below is the mutant's and not the copy's. Exits 1 if the
  clean copy fails, a mutant cannot be planted or built, or any mutant passes preflight.

  The game folder is -ValheimDir, else the VALHEIM environment variable, else the default - as for the build and
  the other tools; it reaches the copy's build and preflight through VALHEIM.

.EXAMPLE
  .\tools\mutants.ps1
  .\tools\mutants.ps1 -Only F1,F2
#>
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
    if (-not (Test-Path (Join-Path $ValheimDir "valheim_Data\Managed\assembly_valheim.dll"))) {
        Write-Output "No Valheim install at $ValheimDir (valheim_Data\Managed\assembly_valheim.dll not found)."
        Finish 1
    }
    $env:VALHEIM = (Resolve-Path $ValheimDir).Path
}
$Only = @($Only | ForEach-Object { $_ -split "," } | Where-Object { $_ })
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
    @("F17 the delete patch takes pins not shown on the map", "SpawnFinder.cs", "[ \t]*if \(pin\.m_uiElement == null \|\| !pin\.m_uiElement\.gameObject\.activeInHierarchy\)\r?\n[ \t]*continue;\r?\n", "")
)

function Build-And-Check {
    # Returns the lines to show and preflight's exit code ($null if the copy did not build); it prints nothing
    # itself, since anything a PowerShell function writes becomes part of what it returns.
    # --no-incremental: the copies keep their files' old timestamps, so MSBuild would take the last mutant's
    # compiled output for up to date.
    $dll = Join-Path $work "build\MobTracker.dll"
    if (Test-Path $dll) { Remove-Item $dll }
    $b = & dotnet build (Join-Path $work "MobTracker.csproj") -c Release --no-incremental -nologo -v q 2>&1 | Out-String
    if (-not (Test-Path $dll)) { return [pscustomobject]@{ Code = $null; Lines = @("    BUILD FAILED", $b) } }
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $work "tools\preflight.ps1") -Plugin $dll 2>&1
    $code = $LASTEXITCODE
    $lines = @($out | Where-Object { "$_" -cmatch "FAIL" } | ForEach-Object { "      $_" })
    return [pscustomobject]@{ Code = $code; Lines = $lines }
}

# A fresh copy of the tracked files as they are in the working tree, and of the publicized game assemblies.
New-Item -ItemType Directory -Force -Path $work | Out-Null
foreach ($f in @(& git -C $repo ls-files)) {
    $dest = Join-Path $work $f
    New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
    Copy-Item -Path (Join-Path $repo $f) -Destination $dest -Force
}
if (Test-Path (Join-Path $repo "lib")) {
    New-Item -ItemType Directory -Force -Path (Join-Path $work "lib") | Out-Null
    Copy-Item -Path (Join-Path $repo "lib\*") -Destination (Join-Path $work "lib") -Recurse -Force
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
