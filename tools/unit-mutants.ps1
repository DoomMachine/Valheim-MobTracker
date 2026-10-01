<#
.SYNOPSIS
  Proves the unit tests catch the defects only they can see: plants each one in a copy of the rules that need no game
  (StarFilter.cs, Rules.cs), runs tests\ and expects it to FAIL.

.DESCRIPTION
  tools\mutants.ps1 proves tools\preflight.ps1 on the built plugin; the decisions inside StarFilter.cs and Rules.cs -
  which levels a star set lets through, what a click does to it, the cfg text, the Alerts: row's wait - compile to the
  same calls whether right or wrong, so only the unit tests can tell. This script plants one such defect at a time.

  Works in build\unit-mutants\ of the repository this script is in (git ignores build\), emptied first, on a copy of
  -Source's top-level .cs files and tests\ folder (the test project compiles StarFilter.cs and Rules.cs from the top
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
    @("U45 the barber stops the list closing", "Rules.cs", "return !(keyTypesText && (searchFocused || gameTyping));", "return !barber && !(keyTypesText && (searchFocused || gameTyping));")
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
