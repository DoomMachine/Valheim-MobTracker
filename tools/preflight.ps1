<#
.SYNOPSIS
  Checks a compiled MobTracker.dll against the shipped game, without launching it.

.DESCRIPTION
  1. identity: BepInPlugin GUID com.mobtracker.plugin, name MobTracker, the expected version
  2. every [HarmonyPatch] target type and method (the overload, when one is named) still exists in the game,
     every patch parameter is a target parameter or a Harmony injection, Awake applies every patch class, and
     a patch priority sits on the method (Harmony ignores one on the class)
  3. every type and member the plugin uses in the game, Unity, BepInEx and Harmony resolves with its exact
     signature - including the private members it reaches (the ground-path guide's Pathfinding internals,
     Find area's SpawnSystem.m_instances), which it lists - and a deliberately
     wrong member fails to resolve, so the check cannot pass vacuously
  4. the star filters read the right settings: each is parsed from its own cfg entry (the list's never allowing None, the
     alerts' only as the Alerts: row's mode says), at the start and when that entry changes, and a bad value is warned
     about; the list reads its own; the alerts, Auto-track and Always track nearest watched read the alerts' through
     the settled set WatchAlerts works out every frame, whose wait restarts at every change of the alerts' entry (a
     count kept only by that entry's change handler), and the build keeps the shipped mode (Settle); the alert poll
     hands the alert gate its own star-and-watchlist answer and skips what the gate refuses; each window row shows
     and writes its own entry, button by button and every button, through StarSets.IsMarked, Toggle and Format, and
     writes only on a click; the List: row is greyed out in the all-types view (enabled && !all-types), and the title
     names the list's categories exactly when one is marked; always-track-nearest-watched gives its tested decisions
     (Retrack)
     the right values and branches on them the right way, and is started only from Tracker.LateUpdate; its log lines are
     built from what it decided, where the IL shapes say; neither it
     nor Auto-track takes a creature on the other side of a dungeon entrance; Find area honours the spawn rules' key
     and event conditions, takes the map's delete gesture for its own pins after other mods' prefixes, and adds them
     local-only (save false, ownerID 0, and no Minimap method that adds pins of its own)
  5. a creature with no ZNetView is skipped by every creature loop, and one that throws cannot end the alert poll;
     the window pauses its re-sorting under the pointer, stays on screen (each coordinate clamped by its own bounds,
     in GUI units) and puts GUI.matrix back, as the HUD label does; the alert ding plays only through the game's GUI
     mixer group, of the game's mixer (its fallback requiring both)
  6. the list's input: the TextInput.IsVisible and Chat.HasFocus postfixes report the list open or closed this
     frame and only ever add true, the HasFocus one last; Escape and the gamepad's B are read in Update, not OnGUI,
     and B is consumed; ListKey is read only through Hotkeys (caught, a refused key remembered and then not read, mouse
     buttons refused before they are read) and never opens the list while the player types (a sign's open box
     included), over the pause menu, the build menu,
     the inventory or the Barber Station; the wheel
     is zeroed last; TomTom's and Wayfinder's typing test sees the real state (and the installed TomTom/Wayfinder,
     or the -Waypointer DLLs, still read the two flags only there); clicks on the list reach no uGUI element under it
  7. the game session: GameSession, a component of the plugin's own object, starts a session whenever Game.instance
     is another object (by reference) and resets through ModConfig.ResetSession and WatchAlerts.ResetSession, called
     from nowhere else; unless KeepBetweenSessions (General, default false) is on, the reset writes each of the
     watchlist and the two star filters back to its own default, the cfg saved once afterwards; the watchlist
     entry's own change handler re-parses it; closing the list (also on every frame with no player) drops a Watch or
     Find area click still waiting
  8. every assembly the plugin references is in the game folder
  9. the log (0.7.0): Logging.ErrorLog (default true) and Logging.VerboseLog (default false) are bound first in Awake,
     before ModConfig.Bind, and MobTracker.log is opened then only when one is on, else when one is first turned on,
     once per game start; it is taken first (sharing Read only), copied to MobTracker-prev.log and only then emptied,
     UTF-8 without a BOM, flushed per line, every failure of the open caught and named by type only, and the file's
     failure paths (Shut, Dispose, Broke, Stop, the stop notice, CloseQuietly) held to their exact IL shapes, each with
     its catch; the listener copies
     MobTracker's own source (by reference) as LogRules.ToFile says and another source's line only as LogRules.Foreign
     and the repeat limit say, and neither throws nor logs; LogRules' levels are BepInEx's; every log line, by method
     and level, is a 0.6.0 line, a warning of the log's own, a switch note or a verbose line (Info, through ModLog.Event,
     which writes nothing while VerboseLog is off); the verbose lines come from a fixed list of sites, each returning
     first while VerboseLog is off and catching its own failure, none changing what it describes; Events' once-only,
     on-change and on-press guards and what it hands to EventLines' decisions are held to their exact IL shapes, as are
     the catch round the settings line LogFile.Bound writes in Awake, the list's close line past Close's IsOpen test and
     the reached line inside the reached block; and nothing reads a player's, character's or
     world's name, an ID or a save path
 10. the cfg (0.7.1): BepInEx never saves it - Awake turns its SaveOnConfigSet off (ConfigSaver.Take) before the first
     setting is bound, nothing turns it on again, and every Bind is in LogFile.Start or ModConfig.Bind; ConfigSaver
     saves it once after the last Bind and after every change, from a handler on the whole cfg added last (after
     Events.Watch), except while the session reset writes (ConfigSaver.Each), which saves once after; ConfigSaver.Save
     is the only ConfigFile.Save, catches every failure, says the first by type only and then nothing until a save
     works again, which it says; OnDestroy tries once more, first, if the last save failed
  Run it after every Valheim update. Exits 1 on any failure. The number of checks depends on how many TomTom or
  Wayfinder DLLs it reads (one check each).

.EXAMPLE
  .\tools\preflight.ps1                                  # the installed BepInEx\plugins\MobTracker.dll
  .\tools\preflight.ps1 -Plugin build\MobTracker.dll
  .\tools\preflight.ps1 -Plugin build\MobTracker.dll -Waypointer "<TomTom.dll>,<Wayfinder.dll>"
#>
[CmdletBinding(PositionalBinding = $false)]   # every argument named: a stray one is an error
param(
    [string]$Plugin = "",
    [string]$ExpectedVersion = "0.7.1",
    [string]$ValheimDir = $(if ($env:VALHEIM) { $env:VALHEIM } else { "E:\SteamLibrary\steamapps\common\Valheim" }),
    [string[]]$Waypointer = @()   # TomTom / Wayfinder DLLs to check the carve-out against; default: the installed ones
)
$ErrorActionPreference = "Stop"
# Close what Cecil holds - the game's modules and the resolver's cache of every assembly it resolved, whose files stay
# open (read from disk, not into memory), and the plugin (read into memory) - at the end and when anything throws (the
# trap; defined before any line that can throw, so a failure shows its own error), so tools\mutants.ps1 (once per
# planted defect) and tools\deploy.ps1, which run this script in their own PowerShell process rather than starting a
# second one, do not keep the game's DLLs locked.
$gameModules = @{}
$plug = $null
$resolver = $null
function Close-Cecil {
    foreach ($gm in @($script:gameModules.Values)) { try { $gm.Dispose() } catch { } }
    if ($script:plug) { try { $script:plug.Dispose() } catch { } }
    if ($script:resolver) { try { $script:resolver.Dispose() } catch { } }
}
trap { Close-Cecil; break }
# Drop a trailing \, and the " that powershell.exe -File leaves when a quoted path ending in
# \ is the last argument (anywhere earlier it swallows the arguments after it: leave the \ off).
$ValheimDir = $ValheimDir.TrimEnd('\', '"')
$managed = Join-Path $ValheimDir "valheim_Data\Managed"
$core = Join-Path $ValheimDir "BepInEx\core"
if ($Plugin -eq "") { $Plugin = Join-Path $ValheimDir "BepInEx\plugins\MobTracker.dll" }
if (-not (Test-Path -LiteralPath $Plugin)) { Write-Output "FAIL  plugin not found: $Plugin"; exit 1 }
Add-Type -LiteralPath (Join-Path $core "Mono.Cecil.dll")

$resolver = New-Object Mono.Cecil.DefaultAssemblyResolver
$resolver.AddSearchDirectory($managed)
$resolver.AddSearchDirectory($core)
$rp = New-Object Mono.Cecil.ReaderParameters
$rp.AssemblyResolver = $resolver
$rp.InMemory = $true
$plug = [Mono.Cecil.ModuleDefinition]::ReadModule((Resolve-Path -LiteralPath $Plugin).Path, $rp)
$checks = 0; $failures = 0
function Ok($m) { Write-Output "  ok    $m" }
function Fail($m) { Write-Output "  FAIL  $m"; $script:failures++ }
Write-Output ("Checking {0}" -f $Plugin)

Write-Output "== identity =="
$checks++
$bep = $null
foreach ($t in $plug.Types) { foreach ($ca in $t.CustomAttributes) { if ($ca.AttributeType.Name -eq "BepInPlugin") { $bep = @($ca.ConstructorArguments | ForEach-Object { "$($_.Value)" }) } } }
if ($bep -and $bep[0] -ceq "com.mobtracker.plugin" -and $bep[1] -ceq "MobTracker" -and $bep[2] -ceq $ExpectedVersion) { Ok ("BepInPlugin {0} / {1} / {2}" -f $bep[0], $bep[1], $bep[2]) }
else { Fail ("BepInPlugin is '{0}', expected 'com.mobtracker.plugin / MobTracker / {1}'" -f ($bep -join " / "), $ExpectedVersion) }
# The version is written in two places (Plugin.cs's Version constant, the csproj's <Version>); both must agree.
$checks++
$asmVersion = "$($plug.Assembly.Name.Version)"
$fileVersion = ""
foreach ($ca in $plug.Assembly.CustomAttributes) { if ($ca.AttributeType.Name -eq "AssemblyFileVersionAttribute") { $fileVersion = "$($ca.ConstructorArguments[0].Value)" } }
if ($asmVersion -eq "$ExpectedVersion.0" -and $fileVersion -eq "$ExpectedVersion.0") { Ok "assembly and file version $asmVersion (MobTracker.csproj)" }
else { Fail ("assembly version {0}, file version {1}, expected {2}.0 - MobTracker.csproj's <Version> is out of step" -f $asmVersion, $fileVersion, $ExpectedVersion) }
$checks++
$loadedLine = "MobTracker $ExpectedVersion loaded"
$awake = $null
# Case-sensitive, as Unity calls its messages: a method renamed awake is never called.
foreach ($t in $plug.Types) { if ($t.Name -ceq "MobTrackerPlugin") { $awake = $t.Methods | Where-Object { $_.Name -ceq "Awake" -and $_.HasBody } | Select-Object -First 1 } }
$hasLine = $awake -and @($awake.Body.Instructions | Where-Object { $_.OpCode.Name -eq "ldstr" -and "$($_.Operand)" -ceq $loadedLine }).Count -gt 0
if ($hasLine) { Ok "Awake logs '$loadedLine'" } else { Fail "MobTrackerPlugin.Awake does not log '$loadedLine'" }

Write-Output "== Harmony patch targets =="
$gameModules = @{}
foreach ($f in @(Get-ChildItem -LiteralPath $managed -Filter *.dll) + @(Get-ChildItem -LiteralPath $core -Filter *.dll)) { try { $gameModules[$f.Name] = [Mono.Cecil.ModuleDefinition]::ReadModule($f.FullName) } catch { } }
# Names Harmony fills in itself; any other patch parameter must be named (and typed) like a parameter of the target,
# or Harmony refuses the patch when the game starts - after every build check has passed.
$injected = @("__instance", "__result", "__state", "__runOriginal", "__originalMethod", "__args", "__exception")
$patchClasses = @()
foreach ($t in $plug.GetTypes()) {
    foreach ($ca in $t.CustomAttributes) {
        if ($ca.AttributeType.Name -ne "HarmonyPatch" -or $ca.ConstructorArguments.Count -lt 2) { continue }
        $patchClasses += $t; $checks++
        $typeName = "$($ca.ConstructorArguments[0].Value)"; $method = "$($ca.ConstructorArguments[1].Value)"
        $want = $null   # the argument types, when the attribute names an overload
        if ($ca.ConstructorArguments.Count -ge 3) { $want = @($ca.ConstructorArguments[2].Value | ForEach-Object { $_.Value.FullName }) }
        $target = $null
        foreach ($m in $gameModules.Values) {
            $gt = $m.GetType($typeName)
            if (-not $gt) { continue }
            foreach ($gm in $gt.Methods) {
                if ($gm.Name -cne $method) { continue }
                if ($null -ne $want -and (@($gm.Parameters | ForEach-Object { $_.ParameterType.FullName }) -join ",") -ne ($want -join ",")) { continue }
                $target = $gm; break
            }
            if ($target) { break }
        }
        $shown = "{0}.{1}" -f $typeName, $method
        if ($null -ne $want) { $shown += "(" + ($want -join ", ") + ")" }
        if (-not $target) { Fail ("{0}: {1} not found in the game" -f $t.Name, $shown); continue }
        $badParams = @()
        foreach ($pm in $t.Methods | Where-Object { @("Prefix", "Postfix", "Finalizer") -ccontains $_.Name }) {
            foreach ($p in $pm.Parameters) {
                # By exact case, as HarmonyX matches them: __Result is no injection, and Pos no parameter of RemovePin(pos, ...).
                if ($injected -ccontains $p.Name -or $p.Name -clike "___*") { continue }
                $tp = $target.Parameters | Where-Object { $_.Name -ceq $p.Name } | Select-Object -First 1
                $pType = $p.ParameterType.FullName.TrimEnd('&')
                if (-not $tp -or $tp.ParameterType.FullName -cne $pType) { $badParams += ("{0}({1} {2})" -f $pm.Name, $pType, $p.Name) }
            }
        }
        if ($badParams.Count -eq 0) { Ok ("{0} -> {1}, its parameters match" -f $t.Name, $shown) }
        else { Fail ("{0} -> {1}: no such target parameter or injection: {2}" -f $t.Name, $shown, ($badParams -join ", ")) }
    }
}
$checks++
if ($patchClasses.Count -ge 1) { Ok "$($patchClasses.Count) Harmony patch class(es) found" } else { Fail "no [HarmonyPatch] found - the scan would be vacuous" }
# Awake patches one class at a time, so a patch class it does not name is never applied.
$checks++
$registered = @{}
if ($awake) { foreach ($i in $awake.Body.Instructions) { if ($i.OpCode.Name -eq "ldtoken" -and $i.Operand -is [Mono.Cecil.TypeReference]) { $registered[$i.Operand.FullName] = $true } } }
$unregistered = @($patchClasses | Where-Object { -not $registered.ContainsKey($_.FullName) } | ForEach-Object { $_.Name })
if ($unregistered.Count -eq 0 -and $patchClasses.Count -ge 1) { Ok "MobTrackerPlugin.Awake applies every patch class" }
else { Fail ("MobTrackerPlugin.Awake never applies: {0}" -f ($unregistered -join ", ")) }
# HarmonyX 2.9's PatchAll(Type) drops a [HarmonyPriority] written on the class (HarmonyMethodExtensions.Merge keeps
# the method's -1), so the patch runs at the default priority; it has to sit on the patch method.
function Get-Priority($provider) {
    foreach ($ca in $provider.CustomAttributes) { if ($ca.AttributeType.Name -eq "HarmonyPriority") { return [int]$ca.ConstructorArguments[0].Value } }
    return $null
}
$checks++
$classLevel = @($patchClasses | Where-Object { $null -ne (Get-Priority $_) } | ForEach-Object { $_.Name })
if ($classLevel.Count -eq 0) { Ok "no [HarmonyPriority] on a patch class, where Harmony would ignore it" }
else { Fail ("[HarmonyPriority] on the class, which PatchAll(Type) ignores - put it on the patch method: {0}" -f ($classLevel -join ", ")) }
# The delete-gesture prefix must run after a default-priority co-patcher's (TomTom's), or one click removes two pins.
$checks++
$rpPrefix = $null
foreach ($t in $patchClasses) { if ($t.Name -ceq "RemoveAreaPinPatch") { $rpPrefix = $t.Methods | Where-Object { $_.Name -ceq "Prefix" } | Select-Object -First 1 } }
$rpPriority = if ($rpPrefix) { Get-Priority $rpPrefix } else { $null }
if ($null -ne $rpPriority -and $rpPriority -lt 400) { Ok "RemoveAreaPinPatch.Prefix runs at priority $rpPriority, after default-priority prefixes" }
else { Fail ("RemoveAreaPinPatch.Prefix priority is {0}; it must be below 400 (Normal), set on the method" -f $(if ($null -eq $rpPriority) { "unset" } else { $rpPriority })) }

Write-Output "== game types and members the plugin uses =="
$scopes = @("assembly_valheim", "assembly_utils", "assembly_guiutils", "BepInEx", "0Harmony")
$resolved = 0; $bad = @(); $nonPublic = @()
$refs = @()
foreach ($tr in $plug.GetTypeReferences()) { $refs += ,@($tr, $tr) }
foreach ($mr in $plug.GetMemberReferences()) { $refs += ,@($mr, $mr.DeclaringType) }
foreach ($pair in $refs) {
    $dt = $pair[1]
    while ($dt.IsNested) { $dt = $dt.DeclaringType }
    $scope = $dt.Scope.Name
    if (-not ($scopes -contains $scope -or $scope -like "UnityEngine*")) { continue }
    $r = $null
    try { $r = $pair[0].Resolve() } catch { }
    if ($null -eq $r) { $bad += ("{0} ({1})" -f $pair[0].FullName, $scope); continue }
    $resolved++
    if ($scope -eq "assembly_valheim") {
        $isPublic = $true
        if ($r -is [Mono.Cecil.TypeDefinition]) { $isPublic = $r.IsPublic -or $r.IsNestedPublic }
        elseif ($r -is [Mono.Cecil.MethodDefinition] -or $r -is [Mono.Cecil.FieldDefinition]) { $isPublic = $r.IsPublic -and ($r.DeclaringType.IsPublic -or $r.DeclaringType.IsNestedPublic) }
        if (-not $isPublic) { $nonPublic += $pair[0].FullName }
    }
}
$checks++
if ($bad.Count -eq 0) { Ok "all $resolved type and member references into the game, Unity, BepInEx and Harmony resolve" }
else { foreach ($b in $bad) { Fail "does not resolve: $b" } }
foreach ($n in @($nonPublic | Sort-Object -Unique)) { Write-Output "  note  non-public, reached through IgnoresAccessChecksTo: $n" }

# Negative control: a member that does not exist must fail to resolve, or the check above proves nothing.
$checks++
$probe = $plug.GetMemberReferences() | Where-Object { $_.DeclaringType.Scope.Name -eq "assembly_valheim" -and $_ -is [Mono.Cecil.MethodReference] } | Select-Object -First 1
$fake = $null
if ($probe) {
    $fake = New-Object Mono.Cecil.MethodReference(($probe.Name + "_DoesNotExist"), $probe.ReturnType, $probe.DeclaringType)
    $fake.HasThis = $probe.HasThis
    foreach ($p in $probe.Parameters) { $fake.Parameters.Add((New-Object Mono.Cecil.ParameterDefinition($p.ParameterType))) }
}
$fr = $null
if ($fake) { try { $fr = $fake.Resolve() } catch { } }
if ($fake -and $null -eq $fr) { Ok "a deliberately wrong member ($($fake.Name)) fails to resolve - the check is not vacuous" }
else { Fail "the negative control did not fail to resolve (or no game method was found to build it from)" }

Write-Output "== the star filters read the right setting =="
# The list's filter and the alerts' filter are the same types - a text entry (ListStarsText, AlertStarsText) parsed
# into a StarSet field (ListStars, AlertStars) - so crossing them compiles, passes the unit tests (which cannot run
# the game-side code) and would still ship. Read the IL instead: the list refreshes from the list's filter only, the
# alerts from the alerts' filter only, and both ask StarSets.Accepts. (Each field parsed from its own entry, and each
# window row writing its own entry through StarSets.Format and Toggle: under "the star filters' entries" below.)
function Get-Method($typeName, $methodName) {
    # Names compared case-sensitively, as the runtime and Unity do: a method renamed update is not Update to them.
    foreach ($t in $plug.GetTypes()) { if ($t.FullName -ceq $typeName) { return $t.Methods | Where-Object { $_.Name -ceq $methodName -and $_.HasBody } | Select-Object -First 1 } }
    return $null
}
function Get-Touches($m) {
    # Every field and method a method refers to; a field it writes is also recorded as "set <field>", so a check
    # can tell storing the applied filter from merely reading it.
    $out = @{}
    foreach ($i in $m.Body.Instructions) {
        $op = $i.Operand
        if ($op -is [Mono.Cecil.FieldReference]) {
            $key = $op.DeclaringType.Name + "::" + $op.Name
            $out[$key] = $true
            if ($i.OpCode.Name -eq "stfld" -or $i.OpCode.Name -eq "stsfld") { $out["set " + $key] = $true }
        }
        if ($op -is [Mono.Cecil.MethodReference]) {
            $key = $op.DeclaringType.Name + "::" + $op.Name
            $out[$key] = $true
            $out[$key + "(" + (@($op.Parameters | ForEach-Object { $_.ParameterType.FullName }) -join ",") + ")"] = $true   # which overload
        }
    }
    return $out
}
function Get-TouchesWithLambdas($typeName, $methodName) {
    # A method's touches plus those of the lambdas written inside it, which the compiler moves into nested
    # classes as methods named <methodName>b__...
    $out = @{}
    $m = Get-Method $typeName $methodName
    if (-not $m) { return $null }
    $bodies = @($m)
    foreach ($t in $plug.GetTypes()) {
        if ($t.FullName -like "$typeName/*") { $bodies += @($t.Methods | Where-Object { $_.HasBody -and $_.Name -like "<$methodName>*" }) }
    }
    foreach ($b in $bodies) { foreach ($k in (Get-Touches $b).Keys) { $out[$k] = $true } }
    return $out
}
$wiring = @(
    @("MobTracker.WatchAlerts", "Update", @("ModConfig::AlertStars", "ModConfig::AlertStarsRevision", "AlertsRow::Effective", "WatchAlerts::get_EffectiveAlertStars", "StarSets::Accepts", "Character::GetLevel"),
        @("ModConfig::ListStars", "ModConfig::ListStarsText", "ModConfig::AlertStarsText", "EntityListWindow::_appliedListStars")),
    @("MobTracker.EntityListWindow", "Refresh", @("EntityListWindow::_appliedListStars", "StarSets::Accepts", "Character::GetLevel"),
        @("ModConfig::AlertStars", "ModConfig::AlertStarsText", "ModConfig::ListStarsText")),
    @("MobTracker.EntityListWindow", "Update", @("ModConfig::ListStars", "EntityListWindow::_appliedListStars", "set EntityListWindow::_appliedListStars"),
        @("ModConfig::AlertStars", "ModConfig::AlertStarsText"))
)
function Test-Wiring($table) {
    # Each row: type, method, what it must touch, what it must not touch.
    foreach ($w in $table) {
        $script:checks++
        $m = Get-Method $w[0] $w[1]
        if (-not $m) { Fail ("{0}.{1} not found" -f $w[0], $w[1]); continue }
        $touches = Get-Touches $m
        $missing = @($w[2] | Where-Object { -not $touches.ContainsKey($_) })
        $wrong = @($w[3] | Where-Object { $touches.ContainsKey($_) })
        if ($missing.Count -eq 0 -and $wrong.Count -eq 0) {
            $what = if ($w[2].Count) { "uses " + ($w[2] -join ", ") } else { "does not use " + ($w[3] -join ", ") }
            Ok ("{0}.{1} {2}" -f $w[0].Split('.')[-1], $w[1], $what)
        } else {
            $why = @($(if ($missing.Count) { "missing " + ($missing -join ", ") }), $(if ($wrong.Count) { "must not use " + ($wrong -join ", ") })) | Where-Object { $_ }
            Fail ("{0}.{1}: {2}" -f $w[0].Split('.')[-1], $w[1], ($why -join "; "))
        }
    }
}
Test-Wiring $wiring
# The two rows of star buttons: from the "List:" label to the "Alerts:" label only the list's filter and entry may be
# touched, from there to the end of DrawWindow only the alerts'. Swapping the rows compiles and passes everything else.
$checks++
$dw = Get-Method "MobTracker.EntityListWindow" "DrawWindow"
$iList = -1; $iAlerts = -1; $dwIns = @()
if ($dw) {
    $dwIns = @($dw.Body.Instructions)
    for ($k = 0; $k -lt $dwIns.Count; $k++) {
        if ($dwIns[$k].OpCode.Name -ne "ldstr") { continue }
        if ("$($dwIns[$k].Operand)" -eq "List:") { $iList = $k } elseif ("$($dwIns[$k].Operand)" -eq "Alerts:") { $iAlerts = $k }
    }
}
function Get-StarSettings($from, $to) {
    # Which filter the ModConfig star fields touched in a range belong to: ListStars and ListStarsText are "ListStars".
    $o = @{}
    for ($k = $from; $k -lt $to; $k++) {
        $op = $dwIns[$k].Operand
        if ($op -is [Mono.Cecil.FieldReference] -and $op.DeclaringType.Name -eq "ModConfig" -and $op.Name -like "*Stars*") { $o[($op.Name -replace 'Text$', '')] = $true }
    }
    return $o
}
if ($iList -ge 0 -and $iAlerts -gt $iList) {
    $listRow = Get-StarSettings $iList $iAlerts
    $alertRow = Get-StarSettings $iAlerts $dwIns.Count
    if ($listRow.ContainsKey("ListStars") -and -not $listRow.ContainsKey("AlertStars") -and $alertRow.ContainsKey("AlertStars") -and -not $alertRow.ContainsKey("ListStars")) {
        Ok "EntityListWindow.DrawWindow: the List: row uses ModConfig::ListStars(Text) only, the Alerts: row ModConfig::AlertStars(Text) only"
    } else {
        Fail ("EntityListWindow.DrawWindow: the List: row uses {0}; the Alerts: row uses {1}" -f (($listRow.Keys | Sort-Object) -join ", "), (($alertRow.Keys | Sort-Object) -join ", "))
    }
} else { Fail "EntityListWindow.DrawWindow: the 'List:' and 'Alerts:' row labels were not found in that order" }

Write-Output "== Find area =="
# Which rules it searches: without the key and event conditions it pins a boss-locked rule's biome, often right
# around the player. The lambdas that read the conditions are compiled into nested classes, so they are included.
$checks++
$sf = Get-TouchesWithLambdas "MobTracker.SpawnFinder" "StartFind"
$needed = @("Rules::OpenRules", "SpawnData::m_requiredGlobalKey", "SpawnData::m_requiredPersistentEvent", "ZoneSystem::GetGlobalKey(System.String)")
if ($null -eq $sf) { Fail "SpawnFinder.StartFind not found" }
else {
    $missing = @($needed | Where-Object { -not $sf.ContainsKey($_) })
    if ($missing.Count -eq 0) { Ok ("SpawnFinder.StartFind uses {0}" -f ($needed -join ", ")) }
    else { Fail ("SpawnFinder.StartFind (with its lambdas) does not use {0}" -f ($missing -join ", ")) }
}
# The delete gesture: the prefix first stands aside when another prefix has taken the gesture (reads __runOriginal
# and returns false), and only then hands it to RemovePinNear, which picks a pin the way Minimap.GetClosestPin does.
$checks++
$rpm = Get-Method "MobTracker.RemoveAreaPinPatch" "Prefix"
$guarded = $false; $calls = $false
if ($rpm) {
    $ins = @($rpm.Body.Instructions)
    $callAt = -1
    for ($k = 0; $k -lt $ins.Count; $k++) { if ($ins[$k].Operand -is [Mono.Cecil.MethodReference] -and $ins[$k].Operand.Name -eq "RemovePinNear") { $callAt = $k; break } }
    $calls = $callAt -ge 0
    for ($k = 0; $k -lt $callAt - 3; $k++) {
        $p = $null
        if ($ins[$k].Operand -is [Mono.Cecil.ParameterDefinition]) { $p = $ins[$k].Operand }
        elseif ($ins[$k].OpCode.Name -match "^ldarg\.([0-3])$") { $p = $rpm.Parameters[[int]$Matches[1]] }
        if (-not $p -or $p.Name -cne "__runOriginal" -or $ins[$k].OpCode.Name -notlike "ldarg*") { continue }
        if ($ins[$k + 1].OpCode.Name -like "brtrue*" -and $ins[$k + 2].OpCode.Name -eq "ldc.i4.0" -and $ins[$k + 3].OpCode.Name -eq "ret") { $guarded = $true }
    }
}
if ($calls -and $guarded) { Ok "RemoveAreaPinPatch.Prefix returns false when __runOriginal is already false, then calls SpawnFinder::RemovePinNear" }
else { Fail ("RemoveAreaPinPatch.Prefix: {0}" -f (@($(if (-not $guarded) { "no 'if (!__runOriginal) return false;' before the RemovePinNear call" }), $(if (-not $calls) { "never calls SpawnFinder::RemovePinNear" })) | Where-Object { $_ }) -join "; ") }
$checks++
$near = Get-Touches (Get-Method "MobTracker.SpawnFinder" "RemovePinNear")
$needed = @("PinData::m_uiElement", "GameObject::get_activeInHierarchy", "Utils::DistanceXZ", "SpawnFinder::_pinsMap", "Minimap::RemovePin(Minimap/PinData)")
$missing = @($needed | Where-Object { -not $near.ContainsKey($_) })
if ($missing.Count -eq 0) { Ok "SpawnFinder.RemovePinNear picks like GetClosestPin (shown on the map, DistanceXZ) among its own map's pins" }
else { Fail ("SpawnFinder.RemovePinNear does not use {0}" -f ($missing -join ", ")) }

# The pins are the player's alone: never written to the map data, never shared at a cartography table. That is
# AddPin's save argument false and ownerID 0 - read from the IL, finding both parameters by name in the game's
# own AddPin, so a new parameter in a game update cannot shift the check onto the wrong argument.
function Test-LiteralZero($ins, [int]$at) {
    # True when $ins[$at] pushes a literal 0 (false, 0, 0L), looking through a conv.i8.
    if ($at -lt 0) { return $false }
    $p = $ins[$at]
    if ($p.OpCode.Name -eq "conv.i8") { if ($at -lt 1) { return $false }; $p = $ins[$at - 1] }
    $n = $p.OpCode.Name
    if ($n -eq "ldc.i4.0") { return $true }
    if ($n -eq "ldc.i4.s" -or $n -eq "ldc.i4" -or $n -eq "ldc.i8") { return ([long]"$($p.Operand)" -eq 0) }
    return $false
}
function Get-ArgumentSources($ins, [int]$callAt, $handlers = $null, [int]$from = 0) {
    # Replays the evaluation stack over the code before a call and returns, for each value the call consumes (the
    # instance first), the index of the instruction that pushed it; $null if it does not add up. A branch or return
    # starts a new statement (compiled C# has an empty stack there); a branch INSIDE the argument list (a ?:
    # operand) leaves too few values, so it returns $null and the check fails. A catch or filter handler starts
    # with the exception object on an otherwise empty stack, which the straight replay never pushed. $from starts the
    # replay at a later instruction, which must start a statement: a ?: in an earlier statement's argument list
    # (GuideMode's toggle in DrawWindow, a cached lambda in Bind) leaves too few values for the rest of the method.
    $stack = New-Object System.Collections.ArrayList
    for ($k = $from; $k -lt $callAt; $k++) {
        $i = $ins[$k]
        if ($handlers) {
            foreach ($h in $handlers) {
                $ht = "$($h.HandlerType)"
                if ((($ht -eq "Catch" -or $ht -eq "Filter") -and $h.HandlerStart -eq $i) -or ($ht -eq "Filter" -and $h.FilterStart -eq $i)) { $stack.Clear(); [void]$stack.Add($k) }
                elseif (($ht -eq "Finally" -or $ht -eq "Fault") -and $h.HandlerStart -eq $i) { $stack.Clear() }
            }
        }
        $pop = "$($i.OpCode.StackBehaviourPop)"; $push = "$($i.OpCode.StackBehaviourPush)"
        $flow = "$($i.OpCode.FlowControl)"
        if ($flow -eq "Branch" -or $flow -eq "Cond_Branch" -or $flow -eq "Return" -or $flow -eq "Throw") { $stack.Clear(); continue }
        $nPop = 0
        if ($pop -eq "Varpop") { $nPop = $i.Operand.Parameters.Count; if ($i.Operand.HasThis -and $i.OpCode.Name -ne "newobj") { $nPop++ } }
        elseif ($pop -ne "Pop0") { $nPop = @($pop -split "_").Count }
        if ($nPop -gt $stack.Count) { return $null }
        $src = $k
        if ($i.OpCode.Name -eq "conv.i8") { $src = $stack[$stack.Count - 1] }     # a widened literal is still that literal
        if ($nPop -gt 0) { $stack.RemoveRange($stack.Count - $nPop, $nPop) }
        $nPush = 1
        if ($push -eq "Push0") { $nPush = 0 }
        elseif ($push -eq "Push1_push1") { $nPush = 2 }
        elseif ($push -eq "Varpush" -and $i.Operand.ReturnType.FullName -eq "System.Void") { $nPush = 0 }
        for ($j = 0; $j -lt $nPush; $j++) { [void]$stack.Add($src) }
    }
    $c = $ins[$callAt].Operand; $n = $c.Parameters.Count; if ($c.HasThis) { $n++ }
    if ($stack.Count -lt $n) { return $null }
    return ,@($stack.GetRange($stack.Count - $n, $n))
}
$addPins = @(); $pinWrites = @()
foreach ($t in $plug.GetTypes()) {
    foreach ($m in $t.Methods) {
        if (-not $m.HasBody) { continue }
        $ins = @($m.Body.Instructions)
        for ($k = 0; $k -lt $ins.Count; $k++) {
            $op = $ins[$k].Operand
            if ($op -is [Mono.Cecil.MethodReference] -and $op.Name -eq "AddPin" -and $op.DeclaringType.Name -eq "Minimap") { $addPins += ,@($m, $ins, $k) }
            if ($op -is [Mono.Cecil.FieldReference] -and $op.DeclaringType.Name -eq "PinData" -and ($op.Name -eq "m_save" -or $op.Name -eq "m_ownerID") -and $ins[$k].OpCode.Name -ne "ldfld") {
                $pinWrites += ("{0}.{1}: {2} {3}" -f $t.Name, $m.Name, $ins[$k].OpCode.Name, $op.Name)
            }
        }
    }
}
$checks++
if ($addPins.Count -ne 1) { Fail ("expected exactly one reference to Minimap.AddPin, found {0}" -f $addPins.Count) }
else {
    $m = $addPins[0][0]; $ins = $addPins[0][1]; $k = $addPins[0][2]
    $def = $null
    try { $def = $ins[$k].Operand.Resolve() } catch { }
    $saveAt = -1; $ownerAt = -1
    if ($def) { for ($p = 0; $p -lt $def.Parameters.Count; $p++) { if ($def.Parameters[$p].Name -eq "save") { $saveAt = $p }; if ($def.Parameters[$p].Name -eq "ownerID") { $ownerAt = $p } } }
    $argSrc = $null
    if ($ins[$k].OpCode.Name -eq "call" -or $ins[$k].OpCode.Name -eq "callvirt") { $argSrc = Get-ArgumentSources $ins $k $m.Body.ExceptionHandlers }
    if ($saveAt -lt 0 -or $ownerAt -lt 0) { Fail "Minimap.AddPin has no 'save' or 'ownerID' parameter any more - read the game's AddPin again" }
    elseif ($null -eq $argSrc) { Fail ("{0}.{1}: the AddPin call's arguments could not be traced (a delegate, or a branch inside the argument list)" -f $m.DeclaringType.Name, $m.Name) }
    elseif ((Test-LiteralZero $ins $argSrc[$saveAt + 1]) -and (Test-LiteralZero $ins $argSrc[$ownerAt + 1])) { Ok ("{0}.{1}: AddPin with save false and ownerID 0 - the pins stay local" -f $m.DeclaringType.Name, $m.Name) }
    else { Fail ("{0}.{1}: AddPin's save and ownerID are not both a literal 0 - the pins could be saved or shared" -f $m.DeclaringType.Name, $m.Name) }
}
$checks++
if ($pinWrites.Count -eq 0) { Ok "nothing writes a pin's m_save or m_ownerID" } else { foreach ($w in $pinWrites) { Fail "a pin's save or owner is changed after AddPin: $w" } }
# Minimap methods that add pins of their own, with their own save flag (DiscoverLocation adds a saved one): worked
# out from the game's IL - every Minimap method that reaches AddPin through other Minimap methods - so a new one in
# a game update is covered. The plugin may call none of them; AddPin itself is checked above.
$checks++
$mmType = $null
foreach ($m in $gameModules.Values) { $gt = $m.GetType("Minimap"); if ($gt) { $mmType = $gt; break } }
$addsPins = @{}
if ($mmType) {
    $changed = $true
    while ($changed) {
        $changed = $false
        foreach ($gm in $mmType.Methods) {
            if (-not $gm.HasBody -or $gm.Name -eq "AddPin" -or $addsPins.ContainsKey($gm.FullName)) { continue }
            foreach ($i in $gm.Body.Instructions) {
                $op = $i.Operand
                if ($op -isnot [Mono.Cecil.MethodReference] -or $op.DeclaringType.Name -ne "Minimap") { continue }
                $callee = $null; try { $callee = $op.Resolve() } catch { }
                if ($op.Name -eq "AddPin" -or ($callee -and $addsPins.ContainsKey($callee.FullName))) { $addsPins[$gm.FullName] = $true; $changed = $true; break }
            }
        }
    }
}
$viaGame = @()
foreach ($mr in $plug.GetMemberReferences()) {
    if ($mr -isnot [Mono.Cecil.MethodReference] -or $mr.DeclaringType.Name -ne "Minimap") { continue }
    $r = $null; try { $r = $mr.Resolve() } catch { }
    if ($r -and $addsPins.ContainsKey($r.FullName)) { $viaGame += $mr.Name }
}
if (-not $mmType -or $addsPins.Count -eq 0) { Fail "Minimap or its pin-adding methods not found in the game - the check would be vacuous" }
elseif ($viaGame.Count -eq 0) { Ok ("no call to any of the {0} Minimap methods that add pins of their own (DiscoverLocation and the like)" -f $addsPins.Count) }
else { Fail ("calls Minimap methods that add pins with their own save flag: {0}" -f (($viaGame | Sort-Object -Unique) -join ", ")) }

Write-Output "== always track nearest watched =="
# The decisions are Retrack's - when a loss starts a wait, when the wait ends, which creature it may take - and the
# unit tests give each of them in full. What is checked here is the wiring the tests cannot see: that each value a
# decision is given is read from the right place (a !x or a constant is another instruction than the read), and that
# the code branches on the answer the right way.
function Get-SourceKey($m, $ins, $at) {
    # What pushed a value: "Type::Member" for a call, "Type::field.Value" for a config entry's Value (the ldsfld just
    # before get_Value), "Type::field" for a field read, "arg name" for a parameter, else the opcode.
    if ($null -eq $at -or $at -lt 0) { return "?" }
    $i = $ins[$at]; $op = $i.Operand; $n = $i.OpCode.Name
    if (($n -eq "call" -or $n -eq "callvirt") -and $op -is [Mono.Cecil.MethodReference]) {
        if ($op.Name -eq "get_Value" -and $at -ge 1 -and $ins[$at - 1].OpCode.Name -eq "ldsfld") {
            $f = $ins[$at - 1].Operand
            return ("{0}::{1}.Value" -f $f.DeclaringType.Name, $f.Name)
        }
        return ("{0}::{1}" -f $op.DeclaringType.Name, $op.Name)
    }
    if (($n -eq "ldsfld" -or $n -eq "ldfld") -and $op -is [Mono.Cecil.FieldReference]) { return ("{0}::{1}" -f $op.DeclaringType.Name, $op.Name) }
    if ($op -is [Mono.Cecil.ParameterDefinition]) { return ("arg " + $op.Name) }
    if ($n -match '^ldarg\.(\d)$') {
        $p = [int]$Matches[1]
        if ($m.HasThis) { $p-- }
        if ($p -ge 0 -and $p -lt $m.Parameters.Count) { return ("arg " + $m.Parameters[$p].Name) }
    }
    if ($n -match '^ldloc(\.s|\.\d)?$') {
        $var = Get-VarIndex $i
        for ($s = $at - 1; $s -ge 0; $s--) {
            if ($ins[$s].OpCode.Name -match '^stloc' -and (Get-VarIndex $ins[$s]) -eq $var) { return ("loc <- " + (Get-SourceKey $m $ins ($s - 1))) }
        }
        return "loc (not stored before)"
    }
    return $n
}
function Get-VarIndex($i) {
    if ($i.Operand -is [Mono.Cecil.Cil.VariableDefinition]) { return $i.Operand.Index }
    if ($i.OpCode.Name -match '^(ld|st)loc\.(\d)$') { return [int]$Matches[2] }
    return -1
}
# A method's instructions as text, for the exact IL shapes below: branch targets as indexes, locals by number, members
# as Type::Name, the short forms of opcodes as the long ones.
function Get-Shape($m) {
    $ins = @($m.Body.Instructions)
    @(for ($k = 0; $k -lt $ins.Count; $k++) {
        $i = $ins[$k]; $o = $i.Operand; $n = $i.OpCode.Name -replace '\.s$', ''
        if ($n -match '^(st|ld)loc(\.\d)?$') { "{0}loc V{1}" -f $Matches[1], (Get-VarIndex $i) }
        elseif ($o -is [Mono.Cecil.Cil.Instruction]) { "{0} ->{1}" -f $n, [array]::IndexOf($ins, $o) }
        elseif ($o -is [Mono.Cecil.MethodReference] -or $o -is [Mono.Cecil.FieldReference]) { "{0} {1}::{2}" -f $n, $o.DeclaringType.Name, $o.Name }
        elseif ($o -is [Mono.Cecil.TypeReference]) { "{0} {1}" -f $n, $o.FullName }
        elseif ($null -ne $o) { "{0} {1}" -f $n, $o }
        else { $n }
    })
}
function Test-Calls($table) {
    # Each row: type, method, the call ("Type::Member", exactly one in the method; "Type::Member(ParamType,...)" names
    # one overload, "Type::Member()" the one without parameters), where each value it consumes must come from (the
    # instance first; $null = anything; @() = not checked), and the branches that may follow it ($null = not checked).
    foreach ($c in $table) {
        $script:checks++
        $where = "{0}.{1}" -f $c[0].Split('.')[-1], $c[1]
        $m = Get-Method $c[0] $c[1]
        if (-not $m) { Fail ("{0} not found" -f $where); continue }
        $ins = @($m.Body.Instructions)
        $withTypes = "$($c[2])".Contains("(")
        $at = @(for ($k = 0; $k -lt $ins.Count; $k++) {
            $op = $ins[$k].Operand
            if (($ins[$k].OpCode.Name -eq "call" -or $ins[$k].OpCode.Name -eq "callvirt") -and $op -is [Mono.Cecil.MethodReference]) {
                $key = $op.DeclaringType.Name + "::" + $op.Name
                if ($withTypes) { $key += "(" + (@($op.Parameters | ForEach-Object { $_.ParameterType.FullName }) -join ",") + ")" }
                if ($key -eq $c[2]) { $k }
            }
        })
        if ($at.Count -ne 1) { Fail ("{0}: expected one call of {1}, found {2}" -f $where, $c[2], $at.Count); continue }
        $k = $at[0]
        $want = @($c[3])
        $problems = @()
        if ($want.Count -gt 0) {
            $src = Get-ArgumentSources $ins $k $m.Body.ExceptionHandlers
            if ($null -eq $src) { $problems += "its values could not be traced" }
            elseif ($src.Count -ne $want.Count) { $problems += ("it takes {0} values, the check names {1}" -f $src.Count, $want.Count) }
            else {
                for ($a = 0; $a -lt $want.Count; $a++) {
                    if ($null -eq $want[$a]) { continue }
                    $got = Get-SourceKey $m $ins $src[$a]
                    if ($got -ne $want[$a]) { $problems += ("value {0} comes from {1}, not {2}" -f ($a + 1), $got, $want[$a]) }
                }
            }
        }
        $branch = ""
        if ($null -ne $c[4]) {
            $next = if ($k + 1 -lt $ins.Count) { $ins[$k + 1].OpCode.Name } else { "(end)" }
            if (@($c[4]) -notcontains $next) { $problems += ("followed by {0}, not {1}" -f $next, (@($c[4]) -join " or ")) }
            $branch = ", then " + $next
        }
        if ($problems.Count -eq 0) {
            $shown = if ($want.Count) { "(" + (@($want | ForEach-Object { if ($null -eq $_) { "_" } else { $_ } }) -join ", ") + ")" } else { "" }
            Ok ("{0}: {1}{2}{3}" -f $where, $c[2], $shown, $branch)
        } else { Fail ("{0}: {1} - {2}" -f $where, $c[2], ($problems -join "; ")) }
    }
}
$brfalse = @("brfalse", "brfalse.s"); $brtrue = @("brtrue", "brtrue.s")
Test-Calls @(
    # A loss starts a wait only with the option on, for a watched type, not for a tamed creature, from now.
    @("MobTracker.NearestWatched", "Lost", "Retrack::Lost",
        @("NearestWatched::Pending", "arg prefab", "ModConfig::AlwaysTrackNearest.Value", 'HashSet`1::Contains', "arg tamed", "Time::get_time"), $null),
    @("MobTracker.NearestWatched", "Lost", 'HashSet`1::Contains', @("ModConfig::get_Watchlist", "arg prefab"), $null),
    @("MobTracker.Tracker", "LateUpdate", "NearestWatched::Lost", @("Tracker::_targetPrefab", "Tracker::_targetTamed"), $null),
    # The wait ends (a true answer skips no code: the cancel follows) on death, any tracking, the option off, an empty
    # watchlist (its count; Retrack decides that 0 ends it, as a > 0 here would be a cgt the tracing cannot follow).
    @("MobTracker.NearestWatched", "Update", "Retrack::EndsWait",
        @("Character::IsDead", "Tracker::get_IsTracking", "ModConfig::AlwaysTrackNearest.Value", 'HashSet`1::get_Count'), $brfalse),
    @("MobTracker.NearestWatched", "Update", 'HashSet`1::get_Count', @("ModConfig::get_Watchlist"), $null),
    @("MobTracker.NearestWatched", "Update", 'HashSet`1::Contains', @("ModConfig::get_Watchlist", "Creature::PrefabName"), $null),
    @("MobTracker.NearestWatched", "Update", "Retrack::ShouldLook", @("NearestWatched::Pending", "Time::get_time"), $brtrue),
    # Which creature: listable first (the null and dead check), then the candidate test, a false answer skipping it.
    @("MobTracker.NearestWatched", "Update", "Creature::IsListable", @("loc <- Enumerator::get_Current"), $brfalse),
    @("MobTracker.NearestWatched", "Update", "Retrack::IsCandidate",
        @('HashSet`1::Contains', "ZDOID::op_Inequality", "Character::IsTamed", "StarSets::Accepts", "Rules::WithinRadius", "Rules::SameLayer"), $brfalse),
    # The same side of a dungeon entrance: the loop's creature (the overload without parameters) against the player's
    # side, read once before the loop from the player's position (the Vector3 overload).
    @("MobTracker.NearestWatched", "Update", "Rules::SameLayer", @("Character::InInterior", "loc <- Character::InInterior"), $null),
    @("MobTracker.NearestWatched", "Update", "Character::InInterior()", @("loc <- Enumerator::get_Current"), $null),
    @("MobTracker.NearestWatched", "Update", "Character::InInterior(UnityEngine.Vector3)", @("loc <- Transform::get_position"), $null),
    # Auto-track never crosses a dungeon entrance either: the alerting creature kept as the nearest, against the player's
    # position read before the loop, into a local (0.7.1) that Auto-track's test branches on and the Auto-track line is
    # handed - the exact shape below. Which local the creature is: the deferral check.
    @("MobTracker.WatchAlerts", "Update", "Rules::SameLayer", @("Character::InInterior", "Character::InInterior"), @("stloc", "stloc.s")),
    @("MobTracker.WatchAlerts", "Update", "Character::InInterior()", @("loc <- loc <- Enumerator::get_Current"), $null),
    @("MobTracker.WatchAlerts", "Update", "Character::InInterior(UnityEngine.Vector3)", @("loc <- Transform::get_position"), $null),
    # Every creature loop asks IsListable first (it skips a creature with no ZNetView, below), a false answer skipping
    # the creature: in WatchAlerts a true answer jumps over the leave out of its per-creature try.
    @("MobTracker.WatchAlerts", "Update", "Creature::IsListable", @("loc <- Enumerator::get_Current"), $brtrue),
    @("MobTracker.EntityListWindow", "Refresh", "Creature::IsListable", @("loc <- Enumerator::get_Current"), $brfalse),
    @("MobTracker.NearestWatched", "Update", "ZDOID::op_Inequality", @("Character::GetZDOID", "ZDOID::None"), $null),
    @("MobTracker.NearestWatched", "Update", "StarSets::Accepts", @("WatchAlerts::get_EffectiveAlertStars", "Character::GetLevel"), $null),
    @("MobTracker.NearestWatched", "Update", "Rules::WithinRadius", @("loc <- Vector3::Distance", "ModConfig::AlertRadius.Value"), $null),
    # Every watch alert during a wait leaves the choice to the re-track (true skips the auto-track); the
    # window shows Stop tracking while a wait is on (false skips the button only when nothing is tracked either).
    @("MobTracker.WatchAlerts", "Update", "NearestWatched::get_IsPending", @(), $brtrue),
    @("MobTracker.EntityListWindow", "DrawWindow", "NearestWatched::get_IsPending", @(), $brfalse),
    # Whose members the code reads (the creature's, not the player's), and what the wrappers forward.
    @("MobTracker.NearestWatched", "Update", "Character::GetZDOID", @("loc <- Enumerator::get_Current"), $null),
    @("MobTracker.NearestWatched", "Update", "Character::IsTamed", @("loc <- Enumerator::get_Current"), $null),
    @("MobTracker.NearestWatched", "Update", "Character::GetLevel", @("loc <- Enumerator::get_Current"), $null),
    @("MobTracker.NearestWatched", "Update", "Creature::PrefabName", @("loc <- Enumerator::get_Current"), $null),
    @("MobTracker.NearestWatched", "Update", "Vector3::Distance", @("loc <- Transform::get_position", "Transform::get_position"), $null),
    # The creature loop enumerates Character.GetAllCharacters() itself, not a list filtered or reordered first.
    @("MobTracker.NearestWatched", "Update", 'List`1::GetEnumerator', @("Character::GetAllCharacters"), $null),
    @("MobTracker.NearestWatched", "get_IsPending", "Retrack::get_IsPending", @("NearestWatched::Pending"), @("ret")),
    @("MobTracker.NearestWatched", "Cancel", "Retrack::Cancel", @("NearestWatched::Pending"), @("ret")),
    @("MobTracker.NearestWatched", "Update", "Retrack::TookLine", @("NearestWatched::Pending", "Creature::DisplayName", "loc <- loc <- Vector3::Distance", "Time::get_time"), $null),
    @("MobTracker.NearestWatched", "Update", "Creature::DisplayName", @("loc <- loc <- Enumerator::get_Current"), $null),
    # The empty look's verbose line (0.7.0) is given the player's position and side, read once before the loop, and
    # the return follows it.
    @("MobTracker.NearestWatched", "Update", "Events::EmptyLook", @("loc <- Transform::get_position", "loc <- Character::InInterior"), @("ret")),
    # The log lines (0.6.0): the end line's reason from what can still be read when a wait ends, the loss line built
    # from the outcome of Retrack.Lost, and Stop tracking's line only while a wait is on (where each sits: the shapes).
    @("MobTracker.NearestWatched", "Update", "Retrack::EndedLine", @("NearestWatched::Pending", "Time::get_time", "Retrack::EndReason"), $null),
    @("MobTracker.NearestWatched", "Update", "Retrack::EndReason", @("ModConfig::AlwaysTrackNearest.Value", "Tracker::get_IsTracking", "Rules::FormatWatchlist"), $null),
    @("MobTracker.NearestWatched", "Update", "Rules::FormatWatchlist", @("ModConfig::get_Watchlist"), $null),
    @("MobTracker.NearestWatched", "Lost", "Retrack::LostLine", @("NearestWatched::Pending", "arg prefab", "arg tamed", "ModConfig::AlwaysTrackNearest.Value", "Rules::FormatWatchlist"), $null),
    @("MobTracker.NearestWatched", "Lost", "Rules::FormatWatchlist", @("ModConfig::get_Watchlist"), $null),
    @("MobTracker.NearestWatched", "Cancel", "Retrack::get_IsPending", @("NearestWatched::Pending"), $brfalse),
    @("MobTracker.NearestWatched", "Cancel", "Retrack::EndedLine", @("NearestWatched::Pending", "Time::get_time", "ldstr"), $null),
    @("MobTracker.Tracker", "LateUpdate", "Character::IsTamed", @("Tracker::get_Target"), @("stsfld")),
    @("MobTracker.Tracker", "LateUpdate", "Character::GetZDOID", @("Tracker::get_Target"), $null),
    @("MobTracker.Tracker", "Track", "Character::IsTamed", @("arg character"), @("stsfld")),
    @("MobTracker.Tracker", "Track", "Creature::PrefabName", @("arg character"), @("stsfld"))
)
Test-Wiring @(
    @("MobTracker.NearestWatched", "Update", @("Player::m_localPlayer", "Retrack::Cancel", "Tracker::Track"),
        @("ModConfig::ListStars", "ModConfig::ListStarsText", "EntityListWindow::_appliedListStars", "ModConfig::AlertStars", "ModConfig::AlertStarsText")),
    @("MobTracker.Tracker", "Track", @("set Tracker::_targetPrefab", "set Tracker::_targetTamed", "Character::IsTamed"), @()),
    # Tamed is refreshed while tracking, but only while the creature is on the network (IsTamed says false after).
    @("MobTracker.Tracker", "LateUpdate", @("set Tracker::_targetTamed", "Character::GetZDOID", "ZDOID::op_Inequality"), @()),
    @("MobTracker.Tracker", "Stop", @(), @("NearestWatched::Lost")),
    @("MobTracker.EntityListWindow", "DrawWindow", @("NearestWatched::Cancel", "ModConfig::AlwaysTrackNearest"), @("NearestWatched::Lost")),
    # Every watch alert waits while a re-track waits: asking about the alerting creature's type only (as 0.3.0 to 0.5.1
    # did) would let an alert for another watched type take the arrow from a nearer creature the re-track would choose.
    # And NearestWatched.Update itself compares no types and never reads the lost one (0.6.0): its creature loop also
    # enumerates Character.GetAllCharacters() itself, hands IsListable the loop's creature, and branches only on
    # IsListable, IsCandidate and the distance comparison (the rows and shapes above and below).
    @("MobTracker.WatchAlerts", "Update", @("NearestWatched::get_IsPending"), @("NearestWatched::IsPendingFor", "Retrack::get_Prefab")),
    @("MobTracker.NearestWatched", "Update", @(), @("String::Equals", "String::op_Equality", "String::op_Inequality", "String::Compare", "String::CompareOrdinal", "Retrack::get_Prefab"))
)
# Where the wait's two exits lead and what follows them, how the nearest candidate is kept, that the creature loop runs
# to its end, the end of a look, and the lines NearestWatched.Lost and Cancel write: these, and Auto-track's below, are
# exact IL shapes, and an ldloc is keyed by the store before it in instruction order, not by control flow: a
# legitimate rewrite of NearestWatched.Update or of WatchAlerts' auto-track fails them, and they must then be
# re-read against the method's IL (ILSpy or Mono.Cecil), not loosened until they pass.
function Get-CallAt($ins, $key) { @(for ($q = 0; $q -lt $ins.Count; $q++) { $o = $ins[$q].Operand; if (($ins[$q].OpCode.Name -eq "call" -or $ins[$q].OpCode.Name -eq "callvirt") -and $o -is [Mono.Cecil.MethodReference] -and ($o.DeclaringType.Name + "::" + $o.Name) -eq $key) { $q } }) }
function Get-TrueAt($ins, $q) { $b = $ins[$q + 1]; if ($b.OpCode.Name -like "brtrue*") { return [array]::IndexOf($ins, $b.Operand) }; if ($b.OpCode.Name -like "brfalse*") { return $q + 2 }; return -1 }
$nwu = Get-Method "MobTracker.NearestWatched" "Update"
$ni = @($nwu.Body.Instructions)
$checks++
$ew = @(Get-CallAt $ni "Retrack::EndsWait")
$nullAt = @(Get-CallAt $ni "Object::op_Equality" | Where-Object { $src = Get-ArgumentSources $ni $_ $nwu.Body.ExceptionHandlers; $src -and (Get-SourceKey $nwu $ni $src[0]) -eq "loc <- Player::m_localPlayer" })
$why = @()
if ($ew.Count -ne 1) { $why += "EndsWait calls: $($ew.Count)" } else {
    $tp = Get-TrueAt $ni $ew[0]
    if ($tp -lt 0 -or $ni[$tp].OpCode.Name -ne "ldsfld" -or "$($ni[$tp].Operand.Name)" -ne "Pending" -or -not ($ni[$tp + 1].Operand -is [Mono.Cecil.MethodReference] -and $ni[$tp + 1].Operand.Name -eq "Cancel")) { $why += "EndsWait's true path does not go straight to Pending.Cancel" }
    if ($nullAt.Count -ne 1) { $why += "player == null tests: $($nullAt.Count)" } elseif ((Get-TrueAt $ni $nullAt[0]) -ne $tp) { $why += "player == null does not lead to the same Pending.Cancel" }
    # Since 0.6.0 the cancel is followed by the end line and the return: exactly this block.
    if ($tp -ge 0) {
        $exSh = Get-Shape $nwu
        $exWant = @("ldsfld NearestWatched::Pending", "callvirt Retrack::Cancel", "ldsfld MobTrackerPlugin::Log", "ldsfld NearestWatched::Pending",
            "call Time::get_time", "ldsfld ModConfig::AlwaysTrackNearest", 'callvirt ConfigEntry`1::get_Value', "call Tracker::get_IsTracking",
            "call ModConfig::get_Watchlist", "call Rules::FormatWatchlist", "call Retrack::EndReason", "callvirt Retrack::EndedLine",
            "callvirt ManualLogSource::LogInfo", "ret")
        $exGot = @($exSh[$tp..([Math]::Min($exSh.Count - 1, $tp + $exWant.Count - 1))])
        if (($exGot -join "`n") -cne ($exWant -join "`n")) { $why += ("the end of a wait is not: {0} - it is: {1}" -f ($exWant -join "; "), ($exGot -join "; ")) }
    }
}
if ($why.Count -eq 0) { Ok "NearestWatched.Update: no player, and EndsWait true, both lead straight to Pending.Cancel, then the end line and the return" } else { Fail ("NearestWatched.Update: " + ($why -join "; ")) }
$checks++
$ic = @(Get-CallAt $ni "Retrack::IsCandidate")
$why = @()
if ($ic.Count -ne 1) { $why += "IsCandidate calls: $($ic.Count)" } else {
    $c = $ic[0]; $skip = $ni[$c + 1].Operand
    $k2 = Get-SourceKey $nwu $ni ($c + 2); $k5 = Get-SourceKey $nwu $ni ($c + 5)
    if ($k2 -ne "loc <- Vector3::Distance" -or $ni[$c + 3].OpCode.Name -notmatch '^ldloc') { $why += "not 'distance < nearestDistance' after the candidate test ($k2)" }
    elseif ($ni[$c + 4].OpCode.Name -notmatch '^bge\.un' -or $ni[$c + 4].Operand -ne $skip) { $why += ("the comparison is {0}, not bge.un to the same skip" -f $ni[$c + 4].OpCode.Name) }
    elseif ($k5 -ne "loc <- Enumerator::get_Current" -or $ni[$c + 6].OpCode.Name -notmatch '^stloc') { $why += "the candidate is not stored as the nearest" }
    elseif ((Get-VarIndex $ni[$c + 7]) -ne (Get-VarIndex $ni[$c + 2]) -or $ni[$c + 8].OpCode.Name -notmatch '^stloc' -or (Get-VarIndex $ni[$c + 8]) -ne (Get-VarIndex $ni[$c + 3])) { $why += "its distance is not stored as the nearest distance" }
    else {
        $tr = @(Get-CallAt $ni "Tracker::Track")
        $ts = if ($tr.Count -eq 1) { Get-ArgumentSources $ni $tr[0] $nwu.Body.ExceptionHandlers } else { $null }
        if ($null -eq $ts -or (Get-VarIndex $ni[$ts[0]]) -ne (Get-VarIndex $ni[$c + 6])) { $why += "Tracker.Track is not given the kept nearest" }
    }
}
if ($why.Count -eq 0) { Ok "NearestWatched.Update: a candidate nearer than the nearest so far replaces it, with its distance, and the nearest is what is tracked" } else { Fail ("NearestWatched.Update: " + ($why -join "; ")) }
# The creature loop runs to its end and keeps only the nearest (since 0.6.0; SC-3 in part). The shape above
# reads c+0..c+8 only; 'break' after the store (a leave out of the try) or 'if (nearest != null) continue;' keep it and
# make the first candidate in GetAllCharacters' order win, whatever its distance.
$checks++
$why = @()
$mn = @(Get-CallAt $ni "Enumerator::MoveNext")
$ic = @(Get-CallAt $ni "Retrack::IsCandidate")
if ($mn.Count -ne 1 -or $ic.Count -ne 1) { $why += ("MoveNext / IsCandidate calls: {0} / {1}" -f $mn.Count, $ic.Count) } else {
    $back = $ni[$mn[0] + 1]
    $body = if ($back.OpCode.Name -like "brtrue*") { [array]::IndexOf($ni, $back.Operand) } else { -1 }
    $cont = $mn[0] - 1   # ldloca of the enumerator: where 'continue' and the end of the body go
    if ($body -lt 0 -or $body -gt $ic[0]) { $why += "the loop's MoveNext does not branch back to a body that holds the candidate test" } else {
        for ($k = $body; $k -lt $cont; $k++) {
            $i = $ni[$k]; $fc = "$($i.OpCode.FlowControl)"
            if ($fc -eq "Return" -or $fc -eq "Throw" -or $i.OpCode.Name -like "leave*") { $why += ("the loop body leaves the loop at {0} ({1})" -f $k, $i.OpCode.Name) }
            elseif (($fc -eq "Branch" -or $fc -eq "Cond_Branch") -and $i.Operand -is [Mono.Cecil.Cil.Instruction]) {
                $to = [array]::IndexOf($ni, $i.Operand)
                if ($to -lt $body -or $to -gt $cont) { $why += ("a branch at {0} jumps out of the loop body (to {1})" -f $k, $to) }
            }
        }
        if ([array]::IndexOf($ni, $ni[$ic[0] + 1].Operand) -ne $cont -or $ic[0] + 9 -ne $cont) { $why += "the candidate's store is not the end of the loop body" }
        # the kept nearest (c+6's local) is never read inside the loop; the nearest distance (c+8's) only at c+3
        $vN = Get-VarIndex $ni[$ic[0] + 6]; $vD = Get-VarIndex $ni[$ic[0] + 8]
        for ($k = $body; $k -lt $cont; $k++) {
            $i = $ni[$k]
            if ($i.OpCode.Name -match '^ldloc' -and $i.OpCode.Name -notmatch '^ldloca') {
                $v = Get-VarIndex $i
                if ($v -eq $vN) { $why += ("the kept nearest is read inside the loop at {0}" -f $k) }
                if ($v -eq $vD -and $k -ne $ic[0] + 3) { $why += ("the nearest distance is read inside the loop at {0}" -f $k) }
            }
        }
    }
}
if ($why.Count -eq 0) { Ok "NearestWatched.Update: the creature loop runs to its end, reading the nearest so far only in 'distance < nearestDistance'" } else { Fail ("NearestWatched.Update: " + ($why -join "; ")) }
# Nothing runs without a wait: Update starts with exactly 'if (!Pending.IsPending) return;'. Deleted, every frame with
# the option off, nothing watched, something tracked or no player would write an end line; inverted, the wait would
# never look. An exact IL shape, as above.
$checks++
$gWant = @("ldsfld NearestWatched::Pending", "callvirt Retrack::get_IsPending", "brtrue ->4", "ret")
$gGot = @(Get-Shape $nwu | Select-Object -First 4)
if (($gGot -join "`n") -ceq ($gWant -join "`n")) { Ok "NearestWatched.Update: starts with 'if (!Pending.IsPending) return;' - without a wait nothing runs and no line is written" }
else { Fail ("NearestWatched.Update: does not start with 'if (!Pending.IsPending) return;' ({0}) - it is: {1}" -f ($gWant -join "; "), ($gGot -join "; ")) }
# The creature loop's body branches only on IsListable, IsCandidate and 'distance < nearestDistance'. A per-creature
# guard of any other kind - a helper comparing the type with the lost one's, as 0.5.1's rule did - is another branch to
# the loop's continue, which the check above allows.
$checks++
$why = @()
$mn = @(Get-CallAt $ni "Enumerator::MoveNext"); $ic = @(Get-CallAt $ni "Retrack::IsCandidate"); $il = @(Get-CallAt $ni "Creature::IsListable")
if ($mn.Count -ne 1 -or $ic.Count -ne 1 -or $il.Count -ne 1) { $why += ("MoveNext / IsCandidate / IsListable calls: {0} / {1} / {2}" -f $mn.Count, $ic.Count, $il.Count) } else {
    $back = $ni[$mn[0] + 1]
    $body = if ($back.OpCode.Name -like "brtrue*") { [array]::IndexOf($ni, $back.Operand) } else { -1 }
    $cont = $mn[0] - 1
    $allowed = @(($il[0] + 1), ($ic[0] + 1), ($ic[0] + 4))
    $br = @(for ($k = [Math]::Max($body, 0); $k -lt $cont; $k++) { $fc = "$($ni[$k].OpCode.FlowControl)"; if ($fc -eq "Branch" -or $fc -eq "Cond_Branch") { $k } })
    $extra = @($br | Where-Object { $allowed -notcontains $_ })
    if ($body -lt 0) { $why += "the loop's MoveNext does not branch back to its body" }
    elseif ($extra.Count -gt 0) { $why += ("the loop body branches at {0} besides IsListable's, IsCandidate's and the distance comparison" -f ($extra -join ", ")) }
    elseif ($br.Count -ne 3) { $why += ("the loop body has {0} branch(es), expected 3" -f $br.Count) }
}
if ($why.Count -eq 0) { Ok "NearestWatched.Update: the creature loop branches only on IsListable, IsCandidate and the distance comparison" } else { Fail ("NearestWatched.Update: " + ($why -join "; ")) }
# Everything NearestWatched.Update calls, each as often as listed, and its returns and branches. The shapes above pin
# stretches of the method; a statement added between them - a return on another condition, a second cancel, a line
# through a helper or another logger - is a call, a return or a branch more, and fails here.
$checks++
$cc = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([StringComparer]::Ordinal)
foreach ($x in $ni) { if ($x.Operand -is [Mono.Cecil.MethodReference]) { $k = $x.OpCode.Name + " " + $x.Operand.DeclaringType.Name + "::" + $x.Operand.Name; if ($cc.ContainsKey($k)) { $cc[$k] = $cc[$k] + 1 } else { $cc[$k] = 1 } } }
$ccGot = @($cc.Keys | Sort-Object -CaseSensitive | ForEach-Object { "{0} x{1}" -f $_, $cc[$_] }) -join "; "
$nRet = @($ni | Where-Object { $_.OpCode.Name -ceq "ret" }).Count
$nCond = @($ni | Where-Object { "$($_.OpCode.FlowControl)" -ceq "Cond_Branch" }).Count
$nBr = @($ni | Where-Object { "$($_.OpCode.FlowControl)" -ceq "Branch" }).Count
$ccWant = @(
    'call Character::GetAllCharacters x1',
    'call Character::InInterior x1',
    'call Creature::DisplayName x1',
    'call Creature::IsListable x1',
    'call Creature::PrefabName x1',
    'call Enumerator::get_Current x1',
    'call Enumerator::MoveNext x1',
    'call Events::EmptyLook x1',
    'call ModConfig::get_Watchlist x3',
    'call Object::op_Equality x2',
    'call Retrack::EndReason x1',
    'call Retrack::EndsWait x1',
    'call Retrack::IsCandidate x1',
    'call Rules::FormatWatchlist x1',
    'call Rules::SameLayer x1',
    'call Rules::WithinRadius x1',
    'call StarSets::Accepts x1',
    'call Time::get_time x3',
    'call Tracker::get_IsTracking x2',
    'call Tracker::Track x1',
    'call Vector3::Distance x1',
    'call WatchAlerts::get_EffectiveAlertStars x1',
    'call ZDOID::op_Inequality x1',
    'callvirt Character::GetLevel x1',
    'callvirt Character::GetZDOID x1',
    'callvirt Character::InInterior x1',
    'callvirt Character::IsDead x1',
    'callvirt Character::IsTamed x1',
    'callvirt Component::get_transform x2',
    'callvirt ConfigEntry`1::get_Value x3',
    'callvirt HashSet`1::Contains x1',
    'callvirt HashSet`1::get_Count x1',
    'callvirt IDisposable::Dispose x1',
    'callvirt List`1::GetEnumerator x1',
    'callvirt ManualLogSource::LogInfo x2',
    'callvirt Retrack::Cancel x2',
    'callvirt Retrack::EndedLine x1',
    'callvirt Retrack::get_IsPending x1',
    'callvirt Retrack::ShouldLook x1',
    'callvirt Retrack::TookLine x1',
    'callvirt Transform::get_position x2'
) -join '; '
$flowWant = "5 ret, 9 conditional and 2 other branches"
$flowGot = "{0} ret, {1} conditional and {2} other branches" -f $nRet, $nCond, $nBr
if ($ccGot -ceq $ccWant -and $flowGot -ceq $flowWant) { Ok "NearestWatched.Update: calls exactly what it should, as often, with its returns and branches - nothing added between the checked stretches" }
else {
    # Only what differs: "+" a call the method makes and the check does not list (or makes more often), "-" the reverse.
    $ccDiff = @(Compare-Object -CaseSensitive @($ccWant -split '; ') @($ccGot -split '; ') | ForEach-Object { if ($_.SideIndicator -eq "=>") { "+ " + $_.InputObject } else { "- " + $_.InputObject } })
    if ($flowGot -cne $flowWant) { $ccDiff += ("{0}, checked: {1}" -f $flowGot, $flowWant) }
    Fail ("NearestWatched.Update: its calls, returns or branches differ from the checked ones: " + ($ccDiff -join "; "))
}
# MobTracker logs through BepInEx's ManualLogSource only: a UnityEngine.Debug call anywhere would reach the log past
# every count of ManualLogSource calls above and below, and so would System.Console, System.Diagnostics' Trace and
# Debug (BepInEx copies them to its log) or a Unity log callback of its own (since 0.7.0 MobTracker.log takes Unity's
# errors through BepInEx, one route only).
$checks++
$bypass = @("UnityEngine.Debug", "System.Console", "System.Diagnostics.Trace", "System.Diagnostics.Debug", "UnityEngine.ILogger", "UnityEngine.Logger")
$dbg = @(foreach ($t in $plug.GetTypes()) { foreach ($m in $t.Methods) { if ($m.HasBody) { foreach ($x in $m.Body.Instructions) { $o = $x.Operand; if ($o -is [Mono.Cecil.MethodReference] -and ($bypass -ccontains $o.DeclaringType.FullName -or ($o.DeclaringType.FullName -ceq "UnityEngine.Application" -and $o.Name -clike "add_logMessageReceived*"))) { $t.Name + "." + $m.Name + " -> " + $o.DeclaringType.Name + "." + $o.Name } } } } })
if ($dbg.Count -eq 0) { Ok "No method calls UnityEngine.Debug, System.Console, Trace, Diagnostics.Debug or a Unity log callback: every log line goes through BepInEx's ManualLogSource" } else { Fail ("a log route past ManualLogSource is used: " + ($dbg -join "; ")) }
# After the loop, an empty look returns at once - since 0.7.0 after its verbose line, Events.EmptyLook, given the
# player's position and side read before the loop (it returns at once with VerboseLog off); only then the took line,
# the cancel and the Track, in that order, each about the kept nearest (a line above the return would hand
# Creature.DisplayName a null on every look). Update writes three lines in all: this one, the end of a wait's and the
# empty look's verbose one - by any route: ManualLogSource, ModLog or Events.
$checks++
$why = @()
$sh = Get-Shape $nwu
$tk = @(for ($k = 0; $k -lt $sh.Count; $k++) { if ($sh[$k] -ceq "call Tracker::Track") { $k } })
$ic = @(Get-CallAt $ni "Retrack::IsCandidate")
if ($tk.Count -ne 1 -or $ic.Count -ne 1 -or $tk[0] -lt 19) { $why += "Tracker.Track / IsCandidate calls: {0} / {1}" -f $tk.Count, $ic.Count } else {
    $vN = Get-VarIndex $ni[$ic[0] + 6]; $vD = Get-VarIndex $ni[$ic[0] + 8]
    $tailWant = @("ldloc V$vN", "ldnull", "call Object::op_Equality", "brfalse ->8", "ldloc V1", "ldloc V2", "call Events::EmptyLook", "ret",
        "ldsfld MobTrackerPlugin::Log", "ldsfld NearestWatched::Pending",
        "ldloc V$vN", "call Creature::DisplayName", "ldloc V$vD", "call Time::get_time", "callvirt Retrack::TookLine", "callvirt ManualLogSource::LogInfo",
        "ldsfld NearestWatched::Pending", "callvirt Retrack::Cancel", "ldloc V$vN", "call Tracker::Track", "ret")
    $s0 = $tk[0] - 19
    $tailGot = @(for ($k = $s0; $k -lt [Math]::Min($sh.Count, $s0 + $tailWant.Count); $k++) { if ($sh[$k] -match '^(\S+) ->(\d+)$') { "{0} ->{1}" -f $Matches[1], ([int]$Matches[2] - $s0) } else { $sh[$k] } })
    if (($tailGot -join "`n") -cne ($tailWant -join "`n")) { $why += ("the end is not: {0} - it is: {1}" -f ($tailWant -join "; "), ($tailGot -join "; ")) }
    # Any level counts, and any route: a Message or a Debug line on every look would be as wrong as an Info one, and so
    # would a verbose line through ModLog or Events.
    $lg = @(for ($k = 0; $k -lt $sh.Count; $k++) { if ($sh[$k] -cmatch "^(callvirt ManualLogSource::Log|call ModLog::Event|call Events::)") { $k } })
    if ($lg.Count -ne 3) { $why += ("a log call (ManualLogSource, ModLog or Events) is made {0} time(s), expected 3 (the end line, the took line and the empty look's verbose line)" -f $lg.Count) }
}
if ($why.Count -eq 0) { Ok "NearestWatched.Update: an empty look writes its verbose line (Events.EmptyLook) and returns; then the log line, Pending.Cancel and Tracker.Track, each of the kept nearest" } else { Fail ("NearestWatched.Update: " + ($why -join "; ")) }
# The loss line (0.6.0): built right after Retrack.Lost, from its outcome, and written only when there is one (null with
# the option off). An exact IL shape from the Retrack.Lost call to the end of NearestWatched.Lost.
$checks++
$why = @()
$nwl = Get-Method "MobTracker.NearestWatched" "Lost"
if (-not $nwl) { $why += "NearestWatched.Lost not found" } else {
    $lSh = Get-Shape $nwl
    $la = @(for ($k = 0; $k -lt $lSh.Count; $k++) { if ($lSh[$k] -ceq "callvirt Retrack::Lost") { $k } })
    if ($la.Count -ne 1) { $why += ("Retrack.Lost calls: {0}" -f $la.Count) } else {
        $lWant = @("callvirt Retrack::Lost", "ldsfld NearestWatched::Pending", "ldarg.0", "ldarg.1", "ldsfld ModConfig::AlwaysTrackNearest",
            'callvirt ConfigEntry`1::get_Value', "call ModConfig::get_Watchlist", "call Rules::FormatWatchlist", "callvirt Retrack::LostLine",
            "stloc V0", "ldloc V0", "brfalse ->15", "ldsfld MobTrackerPlugin::Log", "ldloc V0", "callvirt ManualLogSource::LogInfo", "ret")
        $s0 = $la[0]
        $lGot = @(for ($k = $s0; $k -lt [Math]::Min($lSh.Count, $s0 + $lWant.Count); $k++) { if ($lSh[$k] -match '^(\S+) ->(\d+)$') { "{0} ->{1}" -f $Matches[1], ([int]$Matches[2] - $s0) } else { $lSh[$k] } })
        if (($lGot -join "`n") -cne ($lWant -join "`n")) { $why += ("the end of Lost is not: {0} - it is: {1}" -f ($lWant -join "; "), ($lGot -join "; ")) }
        elseif ($s0 + $lWant.Count -ne $lSh.Count) { $why += "Lost goes on after its line" }
        # And nothing before the Retrack.Lost call but the null-to-empty prologue and the call's values: no early return
        # (a tamed loss would lose its line) and no line of its own (written with the option off too).
        elseif ($s0 -ne 13 -or (@($lSh[0..12]) -join "`n") -cne (@("ldarg.0", "brtrue ->4", "ldstr ", "starg prefab", "ldsfld NearestWatched::Pending", "ldarg.0", "ldsfld ModConfig::AlwaysTrackNearest", 'callvirt ConfigEntry`1::get_Value', "call ModConfig::get_Watchlist", "ldarg.0", 'callvirt HashSet`1::Contains', "ldarg.1", "call Time::get_time") -join "`n")) { $why += ("Lost does more before Retrack.Lost than the null-to-empty prologue and its values: {0}" -f (@($lSh[0..([Math]::Max(0, $s0 - 1))]) -join "; ")) }
    }
}
if ($why.Count -eq 0) { Ok "NearestWatched.Lost: the loss line is built after Retrack.Lost, from its outcome, and written only when it is not null" } else { Fail ("NearestWatched.Lost: " + ($why -join "; ")) }
# Stop tracking's line (0.6.0): only while a wait is on, and before the cancel, which ends the method. An exact IL shape
# of NearestWatched.Cancel.
$checks++
$why = @()
$nwc = Get-Method "MobTracker.NearestWatched" "Cancel"
if (-not $nwc) { $why += "NearestWatched.Cancel not found" } else {
    $cWant = @("ldsfld NearestWatched::Pending", "callvirt Retrack::get_IsPending", "brfalse ->9", "ldsfld MobTrackerPlugin::Log", "ldsfld NearestWatched::Pending",
        "call Time::get_time", "ldstr Stop tracking", "callvirt Retrack::EndedLine", "callvirt ManualLogSource::LogInfo", "ldsfld NearestWatched::Pending",
        "callvirt Retrack::Cancel", "ret")
    $cGot = @(Get-Shape $nwc)
    if (($cGot -join "`n") -cne ($cWant -join "`n")) { $why += ("it is not: {0} - it is: {1}" -f ($cWant -join "; "), ($cGot -join "; ")) }
}
if ($why.Count -eq 0) { Ok "NearestWatched.Cancel: Stop tracking's line only while a wait is on, then the cancel and the return" } else { Fail ("NearestWatched.Cancel: " + ($why -join "; ")) }
# Auto-track's dungeon-entrance test asks about the creature Tracker.Track is given.
$checks++
$wau = Get-Method "MobTracker.WatchAlerts" "Update"
$wi = @($wau.Body.Instructions)
$tr = @(Get-CallAt $wi "Tracker::Track")
$why = @()
$ta = if ($tr.Count -eq 1) { Get-ArgumentSources $wi $tr[0] $wau.Body.ExceptionHandlers } else { $null }
$ii = @(Get-CallAt $wi "Character::InInterior" | Where-Object { $wi[$_].Operand.Parameters.Count -eq 0 })
$ia = if ($ii.Count -eq 1) { Get-ArgumentSources $wi $ii[0] $wau.Body.ExceptionHandlers } else { $null }
if ($tr.Count -ne 1 -or $ii.Count -ne 1) { $why += ("Track / InInterior() calls: {0} / {1}" -f $tr.Count, $ii.Count) }
elseif (-not $ia -or -not $ta -or $wi[$ia[0]].OpCode.Name -notmatch '^ldloc' -or (Get-VarIndex $wi[$ia[0]]) -ne (Get-VarIndex $wi[$ta[0]])) { $why += "the dungeon-entrance test asks about another creature than the one Tracker.Track is given" }
if ($why.Count -eq 0) { Ok "WatchAlerts.Update: the dungeon-entrance test asks about the creature Tracker.Track would take" } else { Fail ("WatchAlerts.Update: " + ($why -join "; ")) }
# The line of a tracking started or stopped (0.7.1): first in Tracker.Track, TrackPoint and Stop, before the fields it
# reads ("replaces" names what was tracked; the stop line asks IsTracking) change.
$checks++
$why = @()
foreach ($row in @(@("Track", @("ldarg.0", "call Events::TrackStarting")), @("TrackPoint", @("ldarg.0", "ldarg.1", "call Events::TrackStartingArea")),
        @("Stop", @("call Events::TrackStopping")))) {
    $tm = Get-Method "MobTracker.Tracker" $row[0]
    $tg = if ($tm) { @(Get-Shape $tm | Select-Object -First $row[1].Count) } else { @() }
    if (($tg -join "`n") -cne ($row[1] -join "`n")) { $why += ("Tracker.{0} does not start with {1} - it starts with {2}" -f $row[0], ($row[1] -join "; "), ($tg -join "; ")) }
}
if ($why.Count -eq 0) { Ok "Tracker.Track, TrackPoint and Stop write their line first, before the fields it reads change" } else { Fail ($why -join "; ") }
# Find area's done line (0.7.1) counts the frames the search ran in: the count starts at 1, the frame it begins in - its
# first store, and its only one of a constant - and goes up by 1 right before each pause (within three instructions of
# the store of the iterator's <>2__current), once per pause; nothing else stores it.
$checks++
$why = @()
$fsm = $null
foreach ($t in $plug.GetTypes()) { if ($t.FullName -clike "MobTracker.SpawnFinder/<Search>d__*") { $fsm = $t.Methods | Where-Object { $_.Name -ceq "MoveNext" } | Select-Object -First 1 } }
if (-not $fsm) { $why += "SpawnFinder.Search's MoveNext not found" }
else {
    $fi = @($fsm.Body.Instructions)
    $fst = @(for ($k = 2; $k -lt $fi.Count; $k++) { $o = $fi[$k].Operand; if ($fi[$k].OpCode.Name -eq "stfld" -and $o -is [Mono.Cecil.FieldReference] -and $o.Name -clike "<frames>*") { $k } })
    $yld = @(for ($k = 0; $k -lt $fi.Count; $k++) { $o = $fi[$k].Operand; if ($fi[$k].OpCode.Name -eq "stfld" -and $o -is [Mono.Cecil.FieldReference] -and $o.Name -clike "<>2__current*") { $k } })
    $starts = @($fst | Where-Object { $fi[$_ - 1].OpCode.Name -eq "ldc.i4.1" -and $fi[$_ - 2].OpCode.Name -eq "ldarg.0" })
    $ups = @($fst | Where-Object { $fi[$_ - 1].OpCode.Name -eq "add" -and $fi[$_ - 2].OpCode.Name -eq "ldc.i4.1" })
    $other = $fst.Count - $starts.Count - $ups.Count
    if ($starts.Count -ne 1 -or $other -ne 0) { $why += ("its frame count is set to 1 {0} time(s) and stored otherwise {1} time(s) - expected once and never" -f $starts.Count, $other) }
    elseif ($fst[0] -ne $starts[0]) { $why += "its first store is not the start at 1" }
    if ($ups.Count -ne $yld.Count) { $why += ("it is counted up {0} time(s) for {1} pause(s)" -f $ups.Count, $yld.Count) }
    foreach ($u in $ups) { if (@($yld | Where-Object { $_ -gt $u -and $_ -le $u + 3 }).Count -ne 1) { $why += "the count up at IL $u is not right before a pause" } }
    # 0.7.1: the done line is handed the count itself - Events.FindDone's third argument is the field (ldarg.0; ldfld
    # <frames>), not an expression of it, a constant or another count.
    $fd = @(for ($k = 0; $k -lt $fi.Count; $k++) { $o = $fi[$k].Operand; if ($fi[$k].OpCode.Name -eq "call" -and $o -is [Mono.Cecil.MethodReference] -and $o.DeclaringType.Name -ceq "Events" -and $o.Name -ceq "FindDone") { $k } })
    if ($fd.Count -ne 1) { $why += ("Events.FindDone is called {0} time(s) in the search, not once" -f $fd.Count) }
    else {
        # The replay starts at the statement's first instruction (after the last store, pop or branch before the call): a
        # cached lambda's dup/brtrue/pop earlier in the method (IsSpaced's) would leave it too few values.
        $st = $fd[0] - 1
        while ($st -ge 0 -and $fi[$st].OpCode.Name -notmatch '^(stfld|stsfld|stloc|pop)' -and "$($fi[$st].OpCode.FlowControl)" -notmatch 'Branch|Return|Throw') { $st-- }
        $fa = Get-ArgumentSources $fi $fd[0] $fsm.Body.ExceptionHandlers ($st + 1)
        $fs = if ($fa) { $fa[2] } else { -1 }
        if ($fs -lt 1 -or $fi[$fs].OpCode.Name -ne "ldfld" -or $fi[$fs].Operand.Name -cnotlike "<frames>*" -or $fi[$fs - 1].OpCode.Name -ne "ldarg.0") { $why += "the done line is not handed the frame count itself (Events.FindDone's third argument)" }
    }
}
if ($why.Count -eq 0) { Ok "SpawnFinder.Search: Find area's frame count starts at 1 (the frame it begins in) and goes up by 1 right before each pause, once per pause; its done line is handed that count itself" } else { Fail ("Find area: " + ($why -join "; ")) }
# Only Tracker.LateUpdate starts a wait: one call of NearestWatched.Lost in the plugin, there, and one of Retrack.Lost,
# in NearestWatched.Lost. Which branch of LateUpdate the call sits in is not checked.
$checks++
$lostCalls = @()
foreach ($t in $plug.GetTypes()) {
    foreach ($m in $t.Methods) {
        if (-not $m.HasBody) { continue }
        foreach ($i in $m.Body.Instructions) {
            $op = $i.Operand
            if ($op -is [Mono.Cecil.MethodReference] -and $op.Name -eq "Lost" -and $op.DeclaringType.FullName -eq "MobTracker.NearestWatched") {
                $lostCalls += ("{0}.{1}" -f $t.Name, $m.Name)
            }
        }
    }
}
if ($lostCalls.Count -eq 1 -and $lostCalls[0] -eq "Tracker.LateUpdate") { Ok "NearestWatched.Lost is called once, from Tracker.LateUpdate" }
else { Fail ("NearestWatched.Lost must be called exactly once, from Tracker.LateUpdate; found: {0}" -f $(if ($lostCalls.Count) { $lostCalls -join ", " } else { "none" })) }
# Which branch starts the re-track (SC-2): the NearestWatched.Lost call ends the lost-creature branch of LateUpdate -
# IsTracking, not a point, and Target == null or Target.IsDead() - after the "Lost track of" message and Stop, and
# nothing else leads to it (moved into the logged-out branch, Always track nearest watched would never start). An exact
# IL shape of that block, branch targets relative to its start; a legitimate rewrite must be re-read against the IL.
$checks++
$why = @()
$tlu = Get-Method "MobTracker.Tracker" "LateUpdate"
if (-not $tlu) { $why += "Tracker.LateUpdate not found" }
else {
    $tShape = Get-Shape $tlu
    $lost = [array]::IndexOf($tShape, "call NearestWatched::Lost")
    $tWant = @("call Tracker::get_IsTracking", "brfalse ->29", "ldsfld Tracker::_isPoint", "brtrue ->29", "call Tracker::get_Target", "ldnull",
        "call Object::op_Equality", "brtrue ->11", "call Tracker::get_Target", "callvirt Character::IsDead", "brfalse ->29",
        "call MessageHud::get_instance", "ldnull", "call Object::op_Inequality", "brfalse ->25", "call MessageHud::get_instance", "ldc.i4.1",
        "ldstr Lost track of ", "ldsfld Tracker::_targetName", "call String::Concat", "ldc.i4.0", "ldnull", "ldc.i4.0", "ldc.i4.1",
        "callvirt MessageHud::ShowMessage", "call Tracker::Stop", "ldsfld Tracker::_targetPrefab", "ldsfld Tracker::_targetTamed",
        "call NearestWatched::Lost")
    $start = $lost - ($tWant.Count - 1)
    if ($lost -lt 0 -or $start -lt 0) { $why += "no NearestWatched.Lost call, or too early in LateUpdate" }
    else {
        $tGot = @(for ($k = $start; $k -le $lost; $k++) {
            $line = $tShape[$k]
            if ($line -match '^(\S+) ->(\d+)$') { "{0} ->{1}" -f $Matches[1], ([int]$Matches[2] - $start) } else { $line }
        })
        if (($tGot -join "`n") -cne ($tWant -join "`n")) { $why += ("the block that ends in NearestWatched.Lost is not: {0} - it is: {1}" -f ($tWant -join "; "), ($tGot -join "; ")) }
        if (@($tShape | Where-Object { $_ -ceq "call NearestWatched::Lost" }).Count -ne 1) { $why += "NearestWatched.Lost is called more than once in LateUpdate" }
    }
}
if ($why.Count -eq 0) { Ok "Tracker.LateUpdate: NearestWatched.Lost ends the lost-creature branch (tracking, not a point, Target null or dead), after 'Lost track of' and Stop" }
else { Fail ("Tracker.LateUpdate: " + ($why -join "; ")) }
# Auto-track's "not while a creature is tracked" (SC-1): WatchAlerts.Update asks Tracker.IsTrackingCreature once and
# skips the auto-track on true (brtrue), and never asks IsTracking - which would also refuse to take over a Find area arrow.
Test-Calls @(,
    @("MobTracker.WatchAlerts", "Update", "Tracker::get_IsTrackingCreature", @(), $brtrue)
)
$checks++
$waU = Get-Method "MobTracker.WatchAlerts" "Update"
$waTracking = if ($waU) { @(Get-Shape $waU | Where-Object { $_ -ceq "call Tracker::get_IsTracking" }).Count } else { -1 }
if ($waTracking -eq 0) { Ok "WatchAlerts.Update never asks Tracker.IsTracking (a Find area arrow gives way to an alert)" }
else { Fail ("WatchAlerts.Update asks Tracker.IsTracking {0} time(s); Auto-track must ask IsTrackingCreature only" -f $waTracking) }
# What it asks, and the whole condition: IsTrackingCreature is 'IsTracking && !_isPoint', and every test of Auto-track's
# condition - AutoTrack on, no creature tracked, the same side of a dungeon entrance (asked first, into a local), no
# re-track waiting - skips to the instruction after Tracker.Track; and right there, after the decision (0.7.1), the
# Auto-track line, handed the creature and the very local the test branched on. Exact IL shapes, as above.
$checks++
$why = @()
$itc = Get-Method "MobTracker.Tracker" "get_IsTrackingCreature"
$itcWant = @("call Tracker::get_IsTracking", "brfalse ->6", "ldsfld Tracker::_isPoint", "ldc.i4.0", "ceq", "ret", "ldc.i4.0", "ret")
$itcGot = if ($itc) { @(Get-Shape $itc) } else { @() }
if (($itcGot -join "`n") -cne ($itcWant -join "`n")) { $why += ("IsTrackingCreature is not 'IsTracking && !_isPoint': {0}" -f ($itcGot -join "; ")) }
if ($waU) {
    $waSh = Get-Shape $waU
    $tk = @(for ($k = 0; $k -lt $waSh.Count; $k++) { if ($waSh[$k] -ceq "call Tracker::Track") { $k } })
    $atWant = @("ldloc V2", "callvirt Character::InInterior", "ldloc V1", "call Character::InInterior", "call Rules::SameLayer", "stloc V6",
        "ldsfld ModConfig::AutoTrack", 'callvirt ConfigEntry`1::get_Value', "brfalse ->17", "call Tracker::get_IsTrackingCreature", "brtrue ->17",
        "ldloc V6", "brfalse ->17", "call NearestWatched::get_IsPending", "brtrue ->17", "ldloc V2", "call Tracker::Track",
        "ldloc V2", "ldloc V6", "call Events::AutoTrack")
    if ($tk.Count -ne 1 -or $tk[0] -lt 16) { $why += "WatchAlerts.Update does not call Tracker.Track once" }
    elseif ($tk[0] + 3 -ge $waSh.Count) { $why += "the Auto-track line does not follow Tracker.Track - it must come right after the decision it reports" }
    else {
        $s0 = $tk[0] - 16
        $atGot = @(for ($k = $s0; $k -le $tk[0] + 3; $k++) { if ($waSh[$k] -match '^(\S+) ->(\d+)$') { "{0} ->{1}" -f $Matches[1], ([int]$Matches[2] - $s0) } else { $waSh[$k] } })
        if (($atGot -join "`n") -cne ($atWant -join "`n")) { $why += ("Auto-track is not: {0} - it is: {1}" -f ($atWant -join "; "), ($atGot -join "; ")) }
    }
} else { $why += "WatchAlerts.Update not found" }
if ($why.Count -eq 0) { Ok "Tracker.IsTrackingCreature is IsTracking && !_isPoint, and WatchAlerts.Update auto-tracks only with AutoTrack on, no creature tracked, the same side and no re-track waiting, then writes the Auto-track line with the side the test read" }
else { Fail ("Auto-track: " + ($why -join "; ")) }
# The tracking guide hides - arrow, ground-path line and label - while Rules.GuideHidden says so: LateUpdate gives it the
# HUD-hidden flag, the guarded cutscene test, dead, waiting for the respawn and teleporting, each read from the local
# player (V0, Player.m_localPlayer - never the target), stores the answer for OnGUI and, on true, turns the arrow and
# the line off and returns; OnGUI draws nothing while it is set. Exact IL shapes, as above.
$checks++
$why = @()
$tl = Get-Method "MobTracker.Tracker" "LateUpdate"
if (-not $tl) { $why += "Tracker.LateUpdate not found" } else {
    $sh = Get-Shape $tl
    if ($sh.Count -lt 2 -or $sh[0] -cne "ldsfld Player::m_localPlayer" -or $sh[1] -cne "stloc V0") { $why += "it does not start by storing Player.m_localPlayer in V0" }
    $calls = @(for ($k = 0; $k -lt $sh.Count; $k++) { if ($sh[$k] -ceq "call Rules::GuideHidden") { $k } })
    # Where it sits: right after the !IsTracking block and the tamed refresh - after the lost and reached tests, which
    # must go on while the guide is hidden, and before anything that shows the guide.
    $gWant = @("call Tracker::get_IsTracking", "brtrue ->11", "ldarg.0", "ldfld Tracker::_arrow", "ldc.i4.0", "callvirt GameObject::SetActive", "ldarg.0",
        "ldfld Tracker::_line", "ldc.i4.0", "callvirt Renderer::set_enabled", "ret",
        "ldsfld Tracker::_isPoint", "brtrue ->21", "call Tracker::get_Target", "callvirt Character::GetZDOID", "ldsfld ZDOID::None", "call ZDOID::op_Inequality",
        "brfalse ->21", "call Tracker::get_Target", "callvirt Character::IsTamed", "stsfld Tracker::_targetTamed",
        "call Hud::IsUserHidden", "ldloc V0", "call Tracker::InCutscene", "ldloc V0", "callvirt Character::IsDead", "call Tracker::WaitingForRespawn",
        "ldloc V0", "callvirt Character::IsTeleporting", "call Rules::GuideHidden", "stsfld Tracker::_guideHidden", "ldsfld Tracker::_guideHidden",
        "brfalse ->42", "ldarg.0", "ldfld Tracker::_arrow", "ldc.i4.0", "callvirt GameObject::SetActive", "ldarg.0", "ldfld Tracker::_line", "ldc.i4.0",
        "callvirt Renderer::set_enabled", "ret")
    if ($calls.Count -ne 1) { $why += ("Rules.GuideHidden is called {0} time(s), expected once" -f $calls.Count) }
    else {
        $start = $calls[0] - 29
        $gGot = @(for ($k = [Math]::Max(0, $start); $k -lt [Math]::Min($sh.Count, $start + $gWant.Count); $k++) {
            if ($sh[$k] -match '^(\S+) ->(\d+)$') { "{0} ->{1}" -f $Matches[1], ([int]$Matches[2] - $start) } else { $sh[$k] }
        })
        if ($start -lt 0 -or ($gGot -join "`n") -cne ($gWant -join "`n")) { $why += ("the gate is not: {0} - it is: {1}" -f ($gWant -join "; "), ($gGot -join "; ")) }
    }
}
$stores = @()
foreach ($t in $plug.GetTypes()) { foreach ($m in $t.Methods) { if (-not $m.HasBody) { continue }
    foreach ($i in $m.Body.Instructions) { if ($i.OpCode.Name -eq "stsfld" -and $i.Operand -is [Mono.Cecil.FieldReference] -and $i.Operand.Name -ceq "_guideHidden") { $stores += ("{0}.{1}" -f $t.Name, $m.Name) } } } }
if ($stores.Count -ne 1 -or $stores[0] -cne "Tracker.LateUpdate") { $why += ("_guideHidden is stored in {0}, expected only in Tracker.LateUpdate" -f ($stores -join ", ")) }
$tg = Get-Method "MobTracker.Tracker" "OnGUI"
$oWant = @("call Tracker::get_IsTracking", "brfalse ->4", "ldsfld Tracker::_guideHidden", "brfalse ->5", "ret")
$oGot = if ($tg) { @(Get-Shape $tg | Select-Object -First $oWant.Count) } else { @() }
if (($oGot -join "`n") -cne ($oWant -join "`n")) { $why += ("OnGUI does not start with: {0} - it starts with: {1}" -f ($oWant -join "; "), ($oGot -join "; ")) }
$ic = Get-Method "MobTracker.Tracker" "InCutscene"
$icWant = @("ldarg.0", "callvirt Character::InCutscene", "stloc V0", "leave ->8", "pop", "ldc.i4.0", "stloc V0", "leave ->8", "ldloc V0", "ret")
if (-not $ic) { $why += "Tracker.InCutscene not found" } else {
    $icGot = @(Get-Shape $ic)
    $icCatch = @($ic.Body.ExceptionHandlers | Where-Object { "$($_.HandlerType)" -eq "Catch" -and $_.CatchType.FullName -ceq "System.Exception" })
    if (($icGot -join "`n") -cne ($icWant -join "`n") -or $icCatch.Count -ne 1) { $why += ("InCutscene is not 'try {{ return player.InCutscene(); }} catch (Exception) {{ return false; }}': {0}; handlers: {1}" -f ($icGot -join "; "), ((@($ic.Body.ExceptionHandlers | ForEach-Object { "{0} {1}" -f $_.HandlerType, $_.CatchType.FullName })) -join ", ")) }
}
$wr = Get-Method "MobTracker.Tracker" "WaitingForRespawn"
$wrWant = @("call Game::get_instance", "stloc V0", "ldloc V0", "ldnull", "call Object::op_Inequality", "brfalse ->9", "ldloc V0", "callvirt Game::WaitingForRespawn", "ret", "ldc.i4.0", "ret")
$wrGot = if ($wr) { @(Get-Shape $wr) } else { @() }
if (($wrGot -join "`n") -cne ($wrWant -join "`n")) { $why += ("WaitingForRespawn is not 'Game.instance != null && Game.instance.WaitingForRespawn()': {0}" -f ($wrGot -join "; ")) }
if ($why.Count -eq 0) { Ok "Tracker: the guide hides (arrow, line, label) while Rules.GuideHidden(HUD hidden, cutscene, dead, waiting for the respawn, teleporting) of the local player says so; the cutscene test is guarded" }
else { Fail ("Tracker: " + ($why -join "; ")) }
# ArrowSize and ArrowHeight carry an allowed range (BepInEx clamps a value outside, also one read from the cfg): the
# arrow can neither turn round (a negative size) nor vanish (0).
$checks++
$why = @()
$bd = Get-Method "MobTracker.ModConfig" "Bind"
$bi2 = if ($bd) { @($bd.Body.Instructions) } else { @() }
foreach ($want in @(@("ArrowSize", [single]0.1, [single]3), @("ArrowHeight", [single]0, [single]5))) {
    $st = @(for ($k = 0; $k -lt $bi2.Count; $k++) { $o = $bi2[$k].Operand; if ($bi2[$k].OpCode.Name -eq "stsfld" -and $o -is [Mono.Cecil.FieldReference] -and $o.Name -ceq $want[0]) { $k } })
    if ($st.Count -ne 1) { $why += ("{0} is stored {1} time(s) in Bind" -f $want[0], $st.Count); continue }
    $ctor = -1
    for ($k = $st[0] - 1; $k -ge 0; $k--) {
        if ($bi2[$k].OpCode.Name -eq "stsfld") { break }
        $o = $bi2[$k].Operand
        if ($bi2[$k].OpCode.Name -eq "newobj" -and $o -is [Mono.Cecil.MethodReference] -and $o.DeclaringType.Name -ceq 'AcceptableValueRange`1') { $ctor = $k; break }
    }
    if ($ctor -lt 2 -or $bi2[$ctor - 2].OpCode.Name -ne "ldc.r4" -or $bi2[$ctor - 1].OpCode.Name -ne "ldc.r4") { $why += ("{0} has no AcceptableValueRange<float>(literal, literal)" -f $want[0]); continue }
    $lo = [single]$bi2[$ctor - 2].Operand; $hi = [single]$bi2[$ctor - 1].Operand
    if ($lo -ne $want[1] -or $hi -ne $want[2]) { $why += ("{0}'s range is {1} to {2}, expected {3} to {4}" -f $want[0], $lo, $hi, $want[1], $want[2]) }
    # The whole statement: config.Bind("Tracking", "<the field's name>", <float>, new ConfigDescription(<text>,
    # new AcceptableValueRange<float>(lo, hi))) - the range as ConfigDescription's acceptable values (a tag would range
    # nothing), on the field's own key (another key would hand back the other entry).
    $bc = $st[0] - 1
    $okStmt = $bc -ge 10
    if ($okStmt) {
        $seq = @($bi2[($bc - 10)..$bc])
        $okStmt = (($seq | ForEach-Object { $_.OpCode.Name }) -join ",") -ceq "ldarg.0,ldstr,ldstr,ldc.r4,ldstr,ldc.r4,ldc.r4,newobj,call,newobj,callvirt" -and
            "$($seq[1].Operand)" -ceq "Tracking" -and "$($seq[2].Operand)" -ceq $want[0] -and $seq[7].Operand.DeclaringType.Name -ceq 'AcceptableValueRange`1' -and
            $seq[8].Operand.Name -ceq "Empty" -and $seq[9].Operand.DeclaringType.Name -ceq "ConfigDescription" -and $seq[10].Operand.Name -ceq "Bind"
    }
    if (-not $okStmt) { $why += ("{0} is not config.Bind(Tracking, {0}, <default>, new ConfigDescription(<text>, new AcceptableValueRange<float>(lo, hi)))" -f $want[0]) }
}
if ($why.Count -eq 0) { Ok "ModConfig.Bind: ArrowSize ranges 0.1 to 3 and ArrowHeight 0 to 5 (AcceptableValueRange as ConfigDescription's acceptable values, each on its own key)" }
else { Fail ("ModConfig.Bind: " + ($why -join "; ")) }
# And the arrow uses them: its length is ArrowSize alone (read once, as the scale), its height ArrowHeight alone (read
# twice, each an up offset).
$checks++
$why = @()
$lu = Get-Method "MobTracker.Tracker" "LateUpdate"
$luSh = if ($lu) { @(Get-Shape $lu) } else { @() }
$sz = @(for ($k = 0; $k -lt $luSh.Count; $k++) { if ($luSh[$k] -ceq "ldsfld ModConfig::ArrowSize") { $k } })
$ht = @(for ($k = 0; $k -lt $luSh.Count; $k++) { if ($luSh[$k] -ceq "ldsfld ModConfig::ArrowHeight") { $k } })
if ($sz.Count -ne 1 -or $luSh[$sz[0] - 1] -cne "call Vector3::get_one" -or $luSh[$sz[0] + 2] -cne "call Vector3::op_Multiply" -or $luSh[$sz[0] + 3] -cne "callvirt Transform::set_localScale") { $why += "the arrow's scale is not Vector3.one * ArrowSize.Value (ArrowSize read once)" }
if ($ht.Count -ne 2) { $why += ("ArrowHeight is read {0} time(s), expected twice" -f $ht.Count) }
foreach ($h in $ht) { if ($luSh[$h - 1] -cne "call Vector3::get_up" -or $luSh[$h + 2] -cne "call Vector3::op_Multiply" -or $luSh[$h + 3] -cne "call Vector3::op_Addition") { $why += "ArrowHeight at $h is not an up offset" } }
if ($why.Count -eq 0) { Ok "Tracker.LateUpdate scales the arrow by ArrowSize alone and lifts it by ArrowHeight alone" } else { Fail ("Tracker.LateUpdate arrow settings: " + ($why -join "; ")) }
$checks++
$retrackLost = @()
foreach ($t in $plug.GetTypes()) {
    foreach ($m in $t.Methods) {
        if (-not $m.HasBody) { continue }
        foreach ($i in $m.Body.Instructions) {
            $op = $i.Operand
            if ($op -is [Mono.Cecil.MethodReference] -and $op.Name -eq "Lost" -and $op.DeclaringType.FullName -eq "MobTracker.Retrack") {
                $retrackLost += ("{0}.{1}" -f $t.Name, $m.Name)
            }
        }
    }
}
if ($retrackLost.Count -eq 1 -and $retrackLost[0] -eq "NearestWatched.Lost") { Ok "Retrack.Lost is called once, from NearestWatched.Lost" }
else { Fail ("Retrack.Lost must be called exactly once, from NearestWatched.Lost; found: {0}" -f $(if ($retrackLost.Count) { $retrackLost -join ", " } else { "none" })) }
# A component nobody adds never runs: Awake must add NearestWatched, GameSession and LogObserver (AddComponent<T>) to the plugin's
# own object (this.gameObject), which BepInEx keeps across scene loads - on an object of the scene, GameSession would
# go with the first logout.
foreach ($component in @("NearestWatched", "GameSession", "LogObserver")) {
    $checks++
    $added = $false
    if ($awake) {
        $ai = @($awake.Body.Instructions)
        for ($k = 0; $k -lt $ai.Count; $k++) {
            $op = $ai[$k].Operand
            if ($op -is [Mono.Cecil.GenericInstanceMethod] -and $op.Name -ceq "AddComponent" -and
                @($op.GenericArguments | Where-Object { $_.FullName -ceq "MobTracker.$component" }).Count -gt 0) {
                $src = Get-ArgumentSources $ai $k $awake.Body.ExceptionHandlers
                if ($null -ne $src -and $src.Count -eq 1 -and (Get-SourceKey $awake $ai $src[0]) -ceq "Component::get_gameObject" -and
                    $src[0] -ge 1 -and $ai[$src[0] - 1].OpCode.Name -eq "ldarg.0") { $added = $true }
            }
        }
    }
    if ($added) { Ok "MobTrackerPlugin.Awake adds the $component component to the plugin's own object" } else { Fail "MobTrackerPlugin.Awake never adds $component to this.gameObject" }
}

Write-Output "== the game session =="
# With KeepBetweenSessions off (the default), the watchlist and both star filters last one game session: the life of
# the world's Game object.
# GameSession.Update sees a session end or begin: Game.instance compared by reference with the Game of the last look
# (bne.un - Unity's == would be a call of op_Equality, to which the destroyed Game of the world just left equals null,
# so a logout would go unseen), and on a difference the new one stored, then ModConfig.ResetSession and
# WatchAlerts.ResetSession. Nothing else. (Their order does not matter - the settler is asked only in
# WatchAlerts.Update, after both - but an exact IL shape pins one.) Like the shapes above: a legitimate rewrite must be
# re-read against the method's IL, not loosened. Compared case-sensitively.
$checks++
$gsUpdate = Get-Method "MobTracker.GameSession" "Update"
$gsWant = @("call Game::get_instance", "stloc V0", "ldloc V0", "ldarg.0", "ldfld GameSession::_game", "bne.un ->7", "ret",
    "ldarg.0", "ldloc V0", "stfld GameSession::_game", "call ModConfig::ResetSession", "call WatchAlerts::ResetSession", "ret")
if (-not $gsUpdate) { Fail "GameSession.Update not found" }
else {
    $gsGot = Get-Shape $gsUpdate
    if (($gsGot -join "`n") -ceq ($gsWant -join "`n")) { Ok "GameSession.Update: when Game.instance is not (by reference) the Game of the last look, stores it, then ModConfig.ResetSession, then WatchAlerts.ResetSession" }
    else { Fail ("GameSession.Update is not: {0} - it is: {1}" -f ($gsWant -join "; "), ($gsGot -join "; ")) }
}
# The resets run from there only - one more caller (a per-frame one, say) would empty the choices within the session -
# and the settler that WatchAlerts.ResetSession starts over is the alerts' own.
$sessionCalls = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
foreach ($key in @("ModConfig::ResetSession", "WatchAlerts::ResetSession", "StarSetSettler::Reset")) { $sessionCalls[$key] = @() }
foreach ($t in $plug.GetTypes()) {
    foreach ($m in $t.Methods) {
        if (-not $m.HasBody) { continue }
        foreach ($i in $m.Body.Instructions) {
            $op = $i.Operand
            if (($i.OpCode.Name -eq "call" -or $i.OpCode.Name -eq "callvirt") -and $op -is [Mono.Cecil.MethodReference]) {
                $key = $op.DeclaringType.Name + "::" + $op.Name
                if ($sessionCalls.ContainsKey($key)) { $sessionCalls[$key] += ("{0}.{1}" -f $t.Name, $m.Name) }
            }
        }
    }
}
foreach ($pair in @(@("ModConfig::ResetSession", "GameSession.Update"), @("WatchAlerts::ResetSession", "GameSession.Update"), @("StarSetSettler::Reset", "WatchAlerts.ResetSession"))) {
    $checks++
    $found = @($sessionCalls[$pair[0]])
    if ($found.Count -eq 1 -and $found[0] -ceq $pair[1]) { Ok ("{0} is called once, from {1}" -f $pair[0], $pair[1]) }
    else { Fail ("{0} must be called exactly once, from {1}; found: {2}" -f $pair[0], $pair[1], $(if ($found.Count) { $found -join ", " } else { "none" })) }
}
# One row: the leading comma keeps PowerShell from unrolling it into its fields.
Test-Calls @(,
    @("MobTracker.WatchAlerts", "ResetSession", "StarSetSettler::Reset", @("WatchAlerts::AlertStarsSettler"), $null)
)
# ModConfig.ResetSession: KeepBetweenSessions on returns before anything is written; otherwise each of the three
# entries - Watchlist, ListStarFilter, AlertStarFilter - is written once, with its own default, while ConfigSaver.Each
# is false (set false before the first write, put back in a finally around the writes, from the value read before),
# and the file is saved once after them, through ConfigSaver.Save, which catches a failure (its own shape, below).
$checks++
$why = @()
$rs = Get-Method "MobTracker.ModConfig" "ResetSession"
if (-not $rs) { $why += "not found" }
else {
    $shape = Get-Shape $rs
    $writes = @()
    $head = @("ldsfld ModConfig::KeepBetweenSessions", 'callvirt ConfigEntry`1::get_Value', "brfalse ->4", "ret")
    if ($shape.Count -lt 4 -or (($shape[0..3]) -join "`n") -cne ($head -join "`n")) { $why += ("it does not start with: {0}" -f ($head -join "; ")) }
    $written = @()
    for ($k = 0; $k -lt $shape.Count; $k++) {
        if ($shape[$k] -cne 'callvirt ConfigEntry`1::set_Value') { continue }
        $field = if ($k -ge 4 -and $shape[$k - 4] -clike "ldsfld ModConfig::*") { $shape[$k - 4].Substring(7) } else { "?" }
        if ($k -lt 4 -or $shape[$k - 3] -cne $shape[$k - 4] -or $shape[$k - 2] -cne "callvirt ConfigEntryBase::get_DefaultValue" -or $shape[$k - 1] -cne "castclass System.String") {
            $why += "a write at $k is not <entry>.Value = (string)<the same entry>.DefaultValue"
        }
        $written += $field
        $writes += $k
    }
    $expected = @("ModConfig::AlertStarsText", "ModConfig::ListStarsText", "ModConfig::WatchlistEntry")
    if ((@($written | Sort-Object -CaseSensitive) -join ",") -cne ($expected -join ",")) { $why += ("it writes {0}, not each of {1} once" -f ($written -join ", "), ($expected -join ", ")) }
    # The single save around the writes.
    $rsIns = @($rs.Body.Instructions)
    $off = @(for ($k = 1; $k -lt $shape.Count; $k++) { if ($shape[$k] -ceq 'stsfld ConfigSaver::Each' -and (Test-LiteralZero $rsIns ($k - 1))) { $k } })
    $back = @(for ($k = 1; $k -lt $shape.Count; $k++) { if ($shape[$k] -ceq 'stsfld ConfigSaver::Each' -and $shape[$k - 1] -clike "ldloc V*") { $k } })
    $saves = @(for ($k = 0; $k -lt $shape.Count; $k++) { if ($shape[$k] -ceq 'call ConfigSaver::Save') { $k } })
    $first = if ($writes.Count) { ($writes | Measure-Object -Minimum).Minimum } else { -1 }
    $last = if ($writes.Count) { ($writes | Measure-Object -Maximum).Maximum } else { -1 }
    $fin = @($rs.Body.ExceptionHandlers | Where-Object { "$($_.HandlerType)" -eq "Finally" -and
        [array]::IndexOf($rsIns, $_.TryStart) -le $first -and [array]::IndexOf($rsIns, $_.TryEnd) -gt $last -and
        $back.Count -eq 1 -and [array]::IndexOf($rsIns, $_.HandlerStart) -le $back[0] -and [array]::IndexOf($rsIns, $_.HandlerEnd) -gt $back[0] })
    if ($off.Count -ne 1 -or $first -lt 0 -or $off[0] -gt $first) { $why += "ConfigSaver.Each is not set false once, before the first write" }
    if ($fin.Count -ne 1) { $why += "ConfigSaver.Each is not put back (from a local) in a finally around the writes" }
    # SC-5: what decides whether the writes happen, and that the value put back is the one read before - exact.
    $gate = @("ldsfld ModConfig::WatchlistEntry", "call ModConfig::Held", "ldsfld ModConfig::ListStarsText", "call ModConfig::Held",
        "ldsfld ModConfig::AlertStarsText", "call ModConfig::Held", "call String::Concat", "stloc V0", "ldloc V0", "callvirt String::get_Length",
        "brtrue ->16", "ret", "ldsfld ConfigSaver::Each", "stloc V1", "ldc.i4.0", "stsfld ConfigSaver::Each")
    if ($shape.Count -lt 20 -or (($shape[4..19]) -join "`n") -cne ($gate -join "`n")) {
        $why += ("after KeepBetweenSessions it is not: {0} - it is: {1}" -f ($gate -join "; "), (($shape | Select-Object -Skip 4 -First 16) -join "; "))
    }
    if ($back.Count -ne 1 -or $shape[$back[0] - 1] -cne "ldloc V1") { $why += "the finally does not put back the ConfigSaver.Each value read before (ldloc V1)" }
    $held = Get-Method "MobTracker.ModConfig" "Held"
    $hWant = @("ldarg.0", 'callvirt ConfigEntry`1::get_Value', "ldarg.0", "callvirt ConfigEntryBase::get_DefaultValue", "castclass System.String",
        "call String::op_Equality", "brfalse ->9", "ldstr ", "ret")
    $hGot = if ($held) { @(Get-Shape $held | Select-Object -First $hWant.Count) } else { @() }
    if (($hGot -join "`n") -cne ($hWant -join "`n")) { $why += ("Held does not start with: {0} - it starts with: {1}" -f ($hWant -join "; "), ($hGot -join "; ")) }
    if ($saves.Count -ne 1 -or $saves[0] -lt $last -or $shape[$saves[0] + 1] -cne "ret" -or $shape[$saves[0] - 1] -cne "ldstr after the session reset") { $why += "the cfg is not saved once, through ConfigSaver.Save(""after the session reset""), after the writes, as the method's last call" }
    # Each is stored only here (false, then put back) and by ConfigSaver's type initializer (true).
    $eachStores = @()
    foreach ($t in $plug.GetTypes()) { foreach ($m in $t.Methods) { if (-not $m.HasBody) { continue }; foreach ($x in $m.Body.Instructions) { $o = $x.Operand
        if ($x.OpCode.Name -eq "stsfld" -and $o -is [Mono.Cecil.FieldReference] -and ($o.DeclaringType.Name + "::" + $o.Name) -ceq "ConfigSaver::Each") { $eachStores += ("{0}.{1}" -f $t.Name, $m.Name) } } } }
    if ((@($eachStores | Sort-Object -CaseSensitive) -join ", ") -cne "ConfigSaver..cctor, ModConfig.ResetSession, ModConfig.ResetSession") { $why += ("ConfigSaver.Each is stored by: " + ($eachStores -join ", ")) }
}
if ($why.Count -eq 0) { Ok "ModConfig.ResetSession: returns first when KeepBetweenSessions is on, and when Held finds every entry at its default; else writes Watchlist, ListStarFilter and AlertStarFilter each once, with its own default, with ConfigSaver.Each off (the value read before put back in a finally; Each stored nowhere else), then saves once through ConfigSaver.Save(""after the session reset"")" }
else { Fail ("ModConfig.ResetSession: " + ($why -join "; ")) }
# KeepBetweenSessions is General.KeepBetweenSessions, off unless the player turns it on.
$checks++
$why = @()
$bind = Get-Method "MobTracker.ModConfig" "Bind"
if (-not $bind) { $why += "ModConfig.Bind not found" }
else {
    $ins = @($bind.Body.Instructions)
    $st = @(for ($k = 0; $k -lt $ins.Count; $k++) { $o = $ins[$k].Operand; if ($ins[$k].OpCode.Name -eq "stsfld" -and $o -is [Mono.Cecil.FieldReference] -and $o.Name -ceq "KeepBetweenSessions") { $k } })
    if ($st.Count -ne 1) { $why += ("KeepBetweenSessions is stored {0} time(s) in Bind, expected once" -f $st.Count) }
    else {
        $call = $st[0] - 1
        $from = 0
        for ($s = $call - 1; $s -ge 0; $s--) { if ($ins[$s].OpCode.Name -eq "stsfld") { $from = $s + 1; break } }
        $op = $ins[$call].Operand
        if (-not ($op -is [Mono.Cecil.MethodReference] -and $op.Name -eq "Bind" -and $op.DeclaringType.Name -eq "ConfigFile")) { $why += "KeepBetweenSessions is not stored straight from ConfigFile.Bind" }
        else {
            $src = Get-ArgumentSources $ins $call $bind.Body.ExceptionHandlers $from
            if ($null -eq $src -or $src.Count -ne 5) { $why += "its Bind call's values could not be traced" }
            else {
                if ($ins[$src[1]].OpCode.Name -ne "ldstr" -or $ins[$src[1]].Operand -cne "General") { $why += "its section is not General" }
                if ($ins[$src[2]].OpCode.Name -ne "ldstr" -or $ins[$src[2]].Operand -cne "KeepBetweenSessions") { $why += "its key is not KeepBetweenSessions" }
                if (-not (Test-LiteralZero $ins $src[3])) { $why += "its default is not a literal false" }
            }
        }
    }
}
if ($why.Count -eq 0) { Ok "ModConfig.Bind: General.KeepBetweenSessions, default false - the choices last one game session unless the player keeps them" }
else { Fail ("KeepBetweenSessions: " + ($why -join "; ")) }
# A Watch or Find area click is applied in the next Update while the list is open. Close drops both first (ldnull;
# stsfld _pendingWatchToggle; ldarg.0; ldflda _pendingFind; initobj, before its IsOpen test), so neither runs at a later
# opening, possibly in another world; and with no local player Update calls Close at once (the true branch of
# Player.m_localPlayer == null: ldarg.0; call Close; ret) - on every such frame, so a click is dropped with the player.
$checks++
$why = @()
$lwClose = Get-Method "MobTracker.EntityListWindow" "Close"
if (-not $lwClose) { $why += "Close not found" }
else {
    $cShape = Get-Shape $lwClose
    $cWant = @("ldnull", "stsfld EntityListWindow::_pendingWatchToggle", "ldarg.0", "ldflda EntityListWindow::_pendingFind",
        'initobj System.Nullable`1<MobTracker.EntityListWindow/Row>', "call EntityListWindow::get_IsOpen")
    if ($cShape.Count -lt $cWant.Count -or (($cShape[0..($cWant.Count - 1)]) -join "`n") -cne ($cWant -join "`n")) {
        $why += ("Close does not start with: {0} - it starts with: {1}" -f ($cWant -join "; "), (($cShape | Select-Object -First $cWant.Count) -join "; "))
    }
}
$lwUpdate = Get-Method "MobTracker.EntityListWindow" "Update"
if (-not $lwUpdate) { $why += "Update not found" }
else {
    $ins = @($lwUpdate.Body.Instructions)
    $shape = Get-Shape $lwUpdate
    $close = [array]::IndexOf($shape, "call EntityListWindow::Close")
    if ($close -lt 4) { $why += "no Close call after the player test" }
    else {
        if ($shape[$close - 1] -cne "ldarg.0" -or $shape[$close + 1] -cne "ret") { $why += "the first Close is not 'ldarg.0; call Close; ret'" }
        $keys = [array]::IndexOf($shape, "call EntityListWindow::HandleKeys")
        if ($keys -lt 0 -or $keys -lt $close) { $why += "the list's keys are read before the no-player test closes the list" }
        $eq = $close - 3
        if ($shape[$close - 2] -cnotlike "brfalse ->*" -or $shape[$eq] -cne "call Object::op_Equality") { $why += "the first Close is not in the branch of a == test" }
        else {
            $src = Get-ArgumentSources $ins $eq
            if ($null -eq $src -or (Get-SourceKey $lwUpdate $ins $src[0]) -cne "loc <- Player::m_localPlayer" -or $ins[$src[1]].OpCode.Name -ne "ldnull") { $why += "the == test before the first Close is not Player.m_localPlayer == null" }
        }
    }
}
if ($why.Count -eq 0) { Ok "EntityListWindow: Close drops a Watch and a Find area click still waiting before anything else, and Update closes the list on every frame with no local player, before it reads the list's keys" }
else { Fail ("EntityListWindow: " + ($why -join "; ")) }
# The parsed watchlist follows its entry: Bind adds exactly one SettingChanged handler to WatchlistEntry, and it is
# Watchlist = Rules.ParseWatchlist(WatchlistEntry.Value), nothing else. Without it, the reset (and every Watch click)
# would change the cfg and leave the watchlist the alerts read as it was.
$checks++
$why = @()
$wlBind = Get-Method "MobTracker.ModConfig" "Bind"
$wlIns = if ($wlBind) { @($wlBind.Body.Instructions) } else { @() }
$wHandlers = @()
foreach ($q in @(Get-CallAt $wlIns 'ConfigEntry`1::add_SettingChanged')) {
    $fn = -1; for ($k = $q - 1; $k -ge 0; $k--) { if ($wlIns[$k].OpCode.Name -eq "ldftn") { $fn = $k; break } }
    $en = -1; for ($k = $fn - 1; $k -ge 0; $k--) { $o = $wlIns[$k].Operand; if ($wlIns[$k].OpCode.Name -eq "ldsfld" -and $o -is [Mono.Cecil.FieldReference] -and $o.DeclaringType.Name -ceq "ModConfig" -and $o.FieldType.Name -ceq 'ConfigEntry`1') { $en = $k; break } }
    if ($fn -lt 0 -or $en -lt 0) { $why += "a SettingChanged handler whose entry or method could not be read"; continue }
    if ($wlIns[$en].Operand.Name -cne "WatchlistEntry") { continue }
    $hd = $null; try { $hd = $wlIns[$fn].Operand.Resolve() } catch { }
    $wHandlers += ,$hd
}
$wWant = @("ldsfld ModConfig::WatchlistEntry", 'callvirt ConfigEntry`1::get_Value', "call Rules::ParseWatchlist", "call ModConfig::set_Watchlist", "ret")
if ($wHandlers.Count -ne 1) { $why += ("WatchlistEntry has {0} SettingChanged handler(s), expected 1" -f $wHandlers.Count) }
elseif ($null -eq $wHandlers[0] -or -not $wHandlers[0].HasBody) { $why += "its handler could not be read" }
else {
    $wGot = Get-Shape $wHandlers[0]
    if (($wGot -join "`n") -cne ($wWant -join "`n")) { $why += ("its handler is not: {0} - it is: {1}" -f ($wWant -join "; "), ($wGot -join "; ")) }
}
if ($why.Count -eq 0) { Ok "ModConfig.Bind: WatchlistEntry's one SettingChanged handler is Watchlist = Rules.ParseWatchlist(WatchlistEntry.Value)" }
else { Fail ("ModConfig.Bind: " + ($why -join "; ")) }

Write-Output "== the star filters' entries =="
# The two filters are the same types all the way from the cfg text to the test, so every link where they could be
# crossed is checked: what each Accepts is given and which way the code branches on its answer, which entry each parsed
# field is filled from (at the start and when the entry changes), and what each window row shows and writes. The unit
# tests give Parse, Format, Toggle, IsMarked, Accepts, the settler and the two Alerts: row modes in full.
Test-Calls @(
    # A false answer leaves the creature out: in the alert poll it is then not watched (the && before the watchlist
    # test), in the list it is skipped (the continue).
    @("MobTracker.WatchAlerts", "Update", "StarSets::Accepts", @("WatchAlerts::get_EffectiveAlertStars", "Character::GetLevel"), $brfalse),
    @("MobTracker.EntityListWindow", "Refresh", "StarSets::Accepts", @("EntityListWindow::_appliedListStars", "Character::GetLevel"), $brfalse),
    # The alerts' set follows the Alerts: row through the one settler, restarted by every change of the row's text, on
    # the game's clock, as the build's mode says.
    @("MobTracker.WatchAlerts", "Update", "AlertsRow::Effective",
        @("ModConfig::AlertStars", "ModConfig::AlertStarsRevision", "WatchAlerts::AlertStarsSettler", "Time::get_time", "AlertsRow::AlertsChangeMode"), $null),
    # The window's title names the categories of the list's filter as last applied, not the alerts'.
    @("MobTracker.EntityListWindow", "OnGUI", "StarSets::Label", @("EntityListWindow::_appliedListStars"), $null)
)
# The settled set is worked out on every frame - before the once-a-second return, so the wait is timed from the row's
# last change - and stored straight into EffectiveAlertStars, which nothing but WatchAlerts.Update sets; nothing else
# works it out or asks a settler.
$checks++
$why = @()
$ef = @(Get-CallAt $wi "AlertsRow::Effective")
$np = @(for ($k = 0; $k -lt $wi.Count; $k++) { $o = $wi[$k].Operand; if ($wi[$k].OpCode.Name -eq "ldfld" -and $o -is [Mono.Cecil.FieldReference] -and $o.Name -eq "_nextPoll") { $k } })
$rt = @(for ($k = 0; $k -lt $wi.Count; $k++) { if ($wi[$k].OpCode.Name -eq "ret") { $k } })
if ($ef.Count -ne 1) { $why += "AlertsRow.Effective calls: $($ef.Count)" } else {
    $nx = $wi[$ef[0] + 1].Operand
    if (-not ($nx -is [Mono.Cecil.MethodReference] -and ($nx.DeclaringType.Name + "::" + $nx.Name) -eq "WatchAlerts::set_EffectiveAlertStars")) { $why += "its answer is not stored straight into EffectiveAlertStars" }
    if ($np.Count -eq 0 -or $ef[0] -gt $np[0] -or ($rt.Count -gt 0 -and $ef[0] -gt $rt[0])) { $why += "it is not worked out before the once-a-second test and its return" }
}
$effUsers = @()
foreach ($t in $plug.GetTypes()) {
    foreach ($m in $t.Methods) {
        if (-not $m.HasBody) { continue }
        foreach ($i in $m.Body.Instructions) {
            $op = $i.Operand
            if ($op -isnot [Mono.Cecil.MethodReference]) { continue }
            $key = $op.DeclaringType.Name + "::" + $op.Name
            if (@("WatchAlerts::set_EffectiveAlertStars", "AlertsRow::Effective", "StarSetSettler::Settled") -contains $key) { $effUsers += ("{0} in {1}.{2}" -f $key, $t.Name, $m.Name) }
        }
    }
}
$wantUsers = @("AlertsRow::Effective in WatchAlerts.Update", "StarSetSettler::Settled in AlertsRow.Effective", "WatchAlerts::set_EffectiveAlertStars in WatchAlerts.Update")
if ((@($effUsers | Sort-Object) -join ", ") -ne ($wantUsers -join ", ")) { $why += ("the settled set is worked out or stored in: {0}; expected {1}" -f (@($effUsers | Sort-Object) -join ", "), ($wantUsers -join ", ")) }
if ($why.Count -eq 0) { Ok "WatchAlerts.Update: EffectiveAlertStars = AlertsRow.Effective(...) on every frame, before the once-a-second return; set nowhere else, the settler asked nowhere else" }
else { Fail ("the settled Alerts set: " + ($why -join "; ")) }
# The build runs with the shipped mode, Settle: AlertsChange.Settle is 0 and AlertsRow.AlertsChangeMode is static
# readonly and never set to anything else (C# leaves out an initializer that sets the default, so usually no store at all).
$checks++
$why = @()
$acType = $null; $arType = $null
foreach ($t in $plug.GetTypes()) { if ($t.FullName -eq "MobTracker.AlertsChange") { $acType = $t }; if ($t.FullName -eq "MobTracker.AlertsRow") { $arType = $t } }
$settleField = if ($acType) { @($acType.Fields | Where-Object { $_.Name -eq "Settle" -and $_.HasConstant }) } else { @() }
$modeField = if ($arType) { @($arType.Fields | Where-Object { $_.Name -eq "AlertsChangeMode" }) } else { @() }
if ($settleField.Count -ne 1 -or [int]$settleField[0].Constant -ne 0) { $why += "AlertsChange.Settle is not the constant 0" }
if ($modeField.Count -ne 1 -or -not $modeField[0].IsStatic -or -not $modeField[0].IsInitOnly -or $modeField[0].FieldType.FullName -ne "MobTracker.AlertsChange") { $why += "AlertsRow.AlertsChangeMode is not a static readonly AlertsChange" }
foreach ($t in $plug.GetTypes()) {
    foreach ($m in $t.Methods) {
        if (-not $m.HasBody) { continue }
        $ins = @($m.Body.Instructions)
        for ($k = 0; $k -lt $ins.Count; $k++) {
            $op = $ins[$k].Operand
            if ($ins[$k].OpCode.Name -ne "stsfld" -or $op -isnot [Mono.Cecil.FieldReference] -or ($op.DeclaringType.Name + "::" + $op.Name) -ne "AlertsRow::AlertsChangeMode") { continue }
            if (-not (Test-LiteralZero $ins ($k - 1))) { $why += ("{0}.{1} sets AlertsChangeMode to something other than Settle ({2})" -f $t.Name, $m.Name, $ins[$k - 1].OpCode.Name) }
        }
    }
}
if ($why.Count -eq 0) { Ok "AlertsRow.AlertsChangeMode is Settle (0) and static readonly: the Alerts: row's changes wait, and it empties to All" }
else { Fail ("the Alerts: row's mode: " + ($why -join "; ")) }
# Every store to ModConfig.ListStars or AlertStars is in ModConfig.Bind or a lambda written in it, and stores
# ParseStars(<the field's own entry>, <whether None may be read>): the list's never (a literal false), the alerts' as the
# Alerts: row's mode says (AlertsRow.EmptyIsNothing(AlertsRow.AlertsChangeMode)); each field is stored in Bind and in a
# lambda. The replay starts after the store before, a statement start: Bind's cached lambdas leave a replay from the
# method's start too few values.
$checks++
$why = @()
$starStores = @{ "ListStars" = @(); "AlertStars" = @() }
foreach ($t in $plug.GetTypes()) {
    foreach ($m in $t.Methods) {
        if (-not $m.HasBody) { continue }
        $ins = @($m.Body.Instructions)
        for ($k = 0; $k -lt $ins.Count; $k++) {
            $op = $ins[$k].Operand
            if ($ins[$k].OpCode.Name -ne "stsfld" -or $op -isnot [Mono.Cecil.FieldReference] -or $op.DeclaringType.Name -ne "ModConfig" -or -not $starStores.ContainsKey($op.Name)) { continue }
            $where = "{0}.{1}" -f $t.Name, $m.Name
            $inBind = ($t.FullName -eq "MobTracker.ModConfig" -and $m.Name -eq "Bind") -or ($t.FullName -like "MobTracker.ModConfig/*" -and $m.Name -like "<Bind>*")
            if (-not $inBind) { $why += "$where stores ModConfig.$($op.Name), outside ModConfig.Bind"; continue }
            $prev = $ins[$k - 1].Operand
            if ($ins[$k - 1].OpCode.Name -ne "call" -or $prev -isnot [Mono.Cecil.MethodReference] -or ($prev.DeclaringType.Name + "::" + $prev.Name) -ne "ModConfig::ParseStars") {
                $why += "$where stores ModConfig.$($op.Name) from something other than ModConfig.ParseStars"; continue
            }
            $start = 0
            for ($s = $k - 2; $s -ge 0; $s--) { if ($ins[$s].OpCode.Name -eq "stsfld") { $start = $s + 1; break } }
            $pa = Get-ArgumentSources $ins ($k - 1) $m.Body.ExceptionHandlers $start
            if ($null -eq $pa -or $pa.Count -ne 2) { $why += "$where - ParseStars' values could not be traced"; continue }
            $from = Get-SourceKey $m $ins $pa[0]
            if ($from -ne ("ModConfig::" + $op.Name + "Text")) { $why += "$where parses ModConfig.$($op.Name) from $from"; continue }
            if ($op.Name -eq "ListStars") {
                if (-not (Test-LiteralZero $ins $pa[1])) { $why += ("{0} lets ModConfig.ListStars read None ({1}, not a literal false)" -f $where, $ins[$pa[1]].OpCode.Name); continue }
            }
            else {
                $allow = Get-SourceKey $m $ins $pa[1]
                $ma = if ($allow -eq "AlertsRow::EmptyIsNothing") { Get-ArgumentSources $ins $pa[1] $m.Body.ExceptionHandlers $start } else { $null }
                if ($null -eq $ma -or (Get-SourceKey $m $ins $ma[0]) -ne "AlertsRow::AlertsChangeMode") { $why += "$where lets ModConfig.AlertStars read None by $allow, not by AlertsRow.EmptyIsNothing(AlertsRow.AlertsChangeMode)"; continue }
            }
            $starStores[$op.Name] += $(if ($m.Name -eq "Bind") { "Bind" } else { "lambda" })
        }
    }
}
foreach ($f in @("ListStars", "AlertStars")) {
    if (@($starStores[$f]) -notcontains "Bind" -or @($starStores[$f]) -notcontains "lambda") { $why += ("ModConfig.{0} is parsed from {0}Text in: {1} - expected Bind and a lambda in it" -f $f, $(if ($starStores[$f].Count) { $starStores[$f] -join ", " } else { "nowhere" })) }
}
if ($why.Count -eq 0) { Ok "ModConfig.ListStars and AlertStars are each stored only as ParseStars(their own *Text entry, None: never / as the mode says), in Bind and in a lambda written in it" }
else { Fail ("the star filters' parsing: " + ($why -join "; ")) }
# ParseStars returns what StarSets.Parse made of the entry's own value (not its default), with the caller's leave to read
# None, as it is - stored once and returned - and warns exactly when Parse reported a problem: one LogWarning, jumped
# over by 'problem == null' (ldloc problem; brfalse past it).
$checks++
$why = @()
$ps = Get-Method "MobTracker.ModConfig" "ParseStars"
if (-not $ps) { $why += "not found" } else {
    $pi = @($ps.Body.Instructions)
    $pc = @(Get-CallAt $pi "StarSets::Parse")
    $pa = if ($pc.Count -eq 1) { Get-ArgumentSources $pi $pc[0] $ps.Body.ExceptionHandlers } else { $null }
    if ($null -eq $pa -or $pa.Count -ne 3) { $why += ("StarSets.Parse calls: {0}, or its values could not be traced" -f $pc.Count) } else {
        $value = Get-SourceKey $ps $pi $pa[0]
        $va = if ($value -eq 'ConfigEntry`1::get_Value') { Get-ArgumentSources $pi $pa[0] $ps.Body.ExceptionHandlers } else { $null }
        if ($null -eq $va -or (Get-SourceKey $ps $pi $va[0]) -ne "arg entry") { $why += "Parse is given $value, not entry.Value" }
        $problemVar = if ($pi[$pa[1]].OpCode.Name -like "ldloca*") { Get-VarIndex $pi[$pa[1]] } else { -1 }
        if ($problemVar -lt 0) { $why += "Parse's problem is not a local" }
        if ((Get-SourceKey $ps $pi $pa[2]) -ne "arg allowNone") { $why += ("Parse is told whether None may be read by {0}, not allowNone" -f (Get-SourceKey $ps $pi $pa[2])) }
        $setVar = if ($pi[$pc[0] + 1].OpCode.Name -like "stloc*") { Get-VarIndex $pi[$pc[0] + 1] } else { -1 }
        $setStores = @(for ($k = 0; $k -lt $pi.Count; $k++) { if ($pi[$k].OpCode.Name -like "stloc*" -and (Get-VarIndex $pi[$k]) -eq $setVar) { $k } })
        $rets = @(for ($k = 0; $k -lt $pi.Count; $k++) { if ($pi[$k].OpCode.Name -eq "ret") { $k } })
        $returned = $rets.Count -eq 1 -and $rets[0] -ge 1 -and $pi[$rets[0] - 1].OpCode.Name -like "ldloc*" -and $pi[$rets[0] - 1].OpCode.Name -notlike "ldloca*" -and (Get-VarIndex $pi[$rets[0] - 1]) -eq $setVar
        if ($setVar -lt 0 -or $setStores.Count -ne 1 -or -not $returned) { $why += "Parse's answer is not stored once and returned as it is" }
        $lw = @(Get-CallAt $pi "ManualLogSource::LogWarning")
        $guard = @(for ($k = 0; $k -lt $pi.Count - 1; $k++) { if ($pi[$k].OpCode.Name -like "ldloc*" -and $pi[$k].OpCode.Name -notlike "ldloca*" -and (Get-VarIndex $pi[$k]) -eq $problemVar -and $pi[$k + 1].OpCode.Name -like "brfalse*") { $k } })
        if ($lw.Count -ne 1) { $why += "LogWarning calls: $($lw.Count)" }
        elseif ($guard.Count -ne 1 -or $guard[0] -gt $lw[0] -or [array]::IndexOf($pi, $pi[$guard[0] + 1].Operand) -le $lw[0]) { $why += "the warning is not skipped exactly when Parse reports no problem" }
    }
}
if ($why.Count -eq 0) { Ok "ModConfig.ParseStars: StarSets.Parse(entry.Value, out problem, allowNone), returned as it is, and a warning only when problem is not null" }
else { Fail ("ModConfig.ParseStars: " + ($why -join "; ")) }
# The lambda that re-parses a filter is the SettingChanged handler of that filter's own entry, and each entry has one:
# for each add_SettingChanged in Bind, the handler (the ldftn before it) and the entry (the ConfigEntry field loaded
# before that), read backwards so that the delegate-caching IL of one C# version or another does not matter.
$checks++
$why = @()
$bm = Get-Method "MobTracker.ModConfig" "Bind"
$bi = if ($bm) { @($bm.Body.Instructions) } else { @() }
$reparsed = @{ "ListStarsText" = 0; "AlertStarsText" = 0 }
$alertHandler = $null   # the handler that re-parses AlertStars, for the revision check below
foreach ($q in @(Get-CallAt $bi 'ConfigEntry`1::add_SettingChanged')) {
    $fn = -1; for ($k = $q - 1; $k -ge 0; $k--) { if ($bi[$k].OpCode.Name -eq "ldftn") { $fn = $k; break } }
    $en = -1; for ($k = $fn - 1; $k -ge 0; $k--) { $o = $bi[$k].Operand; if ($bi[$k].OpCode.Name -eq "ldsfld" -and $o -is [Mono.Cecil.FieldReference] -and $o.DeclaringType.Name -eq "ModConfig" -and $o.FieldType.Name -eq 'ConfigEntry`1') { $en = $k; break } }
    if ($fn -lt 0 -or $en -lt 0) { $why += "a SettingChanged handler whose entry or method could not be read"; continue }
    $entry = $bi[$en].Operand.Name
    $hd = $null; try { $hd = $bi[$fn].Operand.Resolve() } catch { }
    $ht = if ($hd -and $hd.HasBody) { Get-Touches $hd } else { @{} }
    $sets = @(@("ListStars", "AlertStars") | Where-Object { $ht.ContainsKey("set ModConfig::$_") })
    if ($reparsed.ContainsKey($entry)) {
        $want = $entry -replace 'Text$', ''
        if (($sets -join ",") -ne $want) { $why += ("{0}'s SettingChanged handler stores {1}, not {2} alone" -f $entry, $(if ($sets.Count) { $sets -join ", " } else { "neither filter" }), $want) }
        else { $reparsed[$entry]++; if ($entry -eq "AlertStarsText") { $alertHandler = $hd.FullName } }
    }
    elseif ($sets.Count -gt 0) { $why += ("{0}'s SettingChanged handler stores {1}" -f $entry, ($sets -join ", ")) }
}
foreach ($e in @("ListStarsText", "AlertStarsText")) { if ($reparsed[$e] -ne 1) { $why += ("{0} has {1} handler(s) re-parsing its filter, expected 1" -f $e, $reparsed[$e]) } }
if ($why.Count -eq 0) { Ok "ModConfig.Bind: ListStarsText's SettingChanged re-parses ListStars, AlertStarsText's AlertStars, one handler each" }
else { Fail ("ModConfig.Bind: " + ($why -join "; ")) }
# The settled set's wait restarts at every change of AlertStarsText, also one that leaves AlertStars as it was
# (ConfigurationManager writes at every keystroke, and a text with no word it knows yet reads as All): ModConfig.AlertStarsRevision
# counts the changes, and is stored exactly once in the plugin, as AlertStarsRevision++ (ldsfld; ldc.i4.1; add;
# stsfld), in the handler found above to re-parse AlertStars. (What reads it: the AlertsRow.Effective row above.)
$checks++
$why = @()
$revStores = @()
foreach ($t in $plug.GetTypes()) {
    foreach ($m in $t.Methods) {
        if (-not $m.HasBody) { continue }
        $ins = @($m.Body.Instructions)
        for ($k = 0; $k -lt $ins.Count; $k++) {
            $op = $ins[$k].Operand
            if ($ins[$k].OpCode.Name -ne "stsfld" -or $op -isnot [Mono.Cecil.FieldReference] -or ($op.DeclaringType.Name + "::" + $op.Name) -ne "ModConfig::AlertStarsRevision") { continue }
            $ld = if ($k -ge 3) { $ins[$k - 3].Operand } else { $null }
            $shape = $k -ge 3 -and $ins[$k - 1].OpCode.Name -eq "add" -and $ins[$k - 2].OpCode.Name -eq "ldc.i4.1" -and $ins[$k - 3].OpCode.Name -eq "ldsfld" -and
                $ld -is [Mono.Cecil.FieldReference] -and ($ld.DeclaringType.Name + "::" + $ld.Name) -eq "ModConfig::AlertStarsRevision"
            $revStores += [pscustomobject]@{ Method = $m.FullName; Shape = $shape }
        }
    }
}
if ($revStores.Count -ne 1) { $why += ("ModConfig.AlertStarsRevision is stored {0} time(s) in the plugin, expected once" -f $revStores.Count) }
elseif (-not $revStores[0].Shape) { $why += "ModConfig.AlertStarsRevision is not stored as AlertStarsRevision++" }
elseif ($null -eq $alertHandler -or $revStores[0].Method -ne $alertHandler) { $why += ("ModConfig.AlertStarsRevision is counted in {0}, not in AlertStarsText's SettingChanged handler" -f $revStores[0].Method) }
if ($why.Count -eq 0) { Ok "ModConfig.AlertStarsRevision++ only in AlertStarsText's SettingChanged handler: every change of the text restarts the Alerts: wait" }
else { Fail ("the Alerts: text's revision: " + ($why -join "; ")) }
# Each window row, button by button (the loop counter i): shows StarSets.IsMarked(<its own filter>, StarButtons[i]) as
# GUILayout.Toggle(marked, StarChoices[i], ...), writes only when the toggle's answer differs from marked (beq skips the
# write), and writes its own entry, once, as StarSets.Format(StarSets.Toggle(<its own filter>, StarButtons[i]...)):
# the List: row with the two-value Toggle (taking off the last category gives All), the Alerts: row with the mode's
# leave to empty to None (AlertsRow.EmptyIsNothing(AlertsRow.AlertsChangeMode), kept in a local). The rows' ranges are
# the ones found above; each replay starts at the row's label, a statement start.
function Get-ElementVar($ins, $at, $arrayKey) {
    # The local that indexes <arrayKey>[local] when $ins[$at] is its ldelem; -1 otherwise.
    if ($at -lt 2 -or $ins[$at].OpCode.Name -notlike "ldelem*" -or $ins[$at - 1].OpCode.Name -notlike "ldloc*" -or $ins[$at - 1].OpCode.Name -like "ldloca*") { return -1 }
    $o = $ins[$at - 2].Operand
    if ($ins[$at - 2].OpCode.Name -ne "ldsfld" -or $o -isnot [Mono.Cecil.FieldReference] -or ($o.DeclaringType.Name + "::" + $o.Name) -ne $arrayKey) { return -1 }
    return (Get-VarIndex $ins[$at - 1])
}
$checks++
$why = @()
if ($iList -lt 0 -or $iAlerts -le $iList) { $why += "the 'List:' and 'Alerts:' row labels were not found in that order" }
else {
    foreach ($row in @(@("List:", "ListStars", $iList, $iAlerts, 2), @("Alerts:", "AlertStars", $iAlerts, $dwIns.Count, 3))) {
        $lo = $row[2]; $hi = $row[3]; $own = "ModConfig::" + $row[1]
        $inRow = { param($key) @(for ($k = $lo; $k -lt $hi; $k++) { $o = $dwIns[$k].Operand; if (($dwIns[$k].OpCode.Name -eq "call" -or $dwIns[$k].OpCode.Name -eq "callvirt") -and $o -is [Mono.Cecil.MethodReference] -and ($o.DeclaringType.Name + "::" + $o.Name) -eq $key) { $k } }) }
        $writes = @(& $inRow 'ConfigEntry`1::set_Value')
        $marks = @(& $inRow "StarSets::IsMarked")
        $toggles = @(& $inRow "GUILayout::Toggle" | Where-Object { $dwIns[$_].Operand.Parameters.Count -ge 2 -and $dwIns[$_].Operand.Parameters[1].ParameterType.Name -eq "GUIContent" })
        if ($writes.Count -ne 1 -or $marks.Count -ne 1 -or $toggles.Count -ne 1) { $why += ("the {0} row has {1} write(s), {2} IsMarked, {3} toggle button(s), not one each" -f $row[0], $writes.Count, $marks.Count, $toggles.Count); continue }
        # What is written: its own entry, Format(Toggle(its own filter, StarButtons[i], ...)).
        $a = Get-ArgumentSources $dwIns $writes[0] $dw.Body.ExceptionHandlers $lo
        if ($null -eq $a -or $a.Count -ne 2) { $why += "the $($row[0]) row's write could not be traced"; continue }
        $entry = Get-SourceKey $dw $dwIns $a[0]; $value = Get-SourceKey $dw $dwIns $a[1]
        $fa = if ($value -eq "StarSets::Format") { Get-ArgumentSources $dwIns $a[1] $dw.Body.ExceptionHandlers $lo } else { $null }
        $toggle = if ($null -ne $fa) { Get-SourceKey $dw $dwIns $fa[0] } else { "?" }
        $ta = if ($toggle -eq "StarSets::Toggle") { Get-ArgumentSources $dwIns $fa[0] $dw.Body.ExceptionHandlers $lo } else { $null }
        if ($entry -ne ($own + "Text")) { $why += ("the {0} row writes {1}, not {2}Text" -f $row[0], $entry, $own); continue }
        if ($value -ne "StarSets::Format") { $why += ("the {0} row writes {1}, not StarSets.Format(...)" -f $row[0], $value); continue }
        if ($null -eq $ta) { $why += ("the {0} row formats {1}, not StarSets.Toggle(...)" -f $row[0], $toggle); continue }
        if ($ta.Count -ne $row[4]) { $why += ("the {0} row's Toggle takes {1} values, not {2}" -f $row[0], $ta.Count, $row[4]); continue }
        $from = Get-SourceKey $dw $dwIns $ta[0]
        if (@($own, "loc <- $own") -notcontains $from) { $why += ("the {0} row toggles {1}, not {2}" -f $row[0], $from, $own); continue }
        $iv = Get-ElementVar $dwIns $ta[1] "EntityListWindow::StarButtons"
        if ($iv -lt 0) { $why += "the $($row[0]) row's Toggle is not given StarButtons[i]"; continue }
        if ($row[4] -eq 3) {
            $leave = Get-SourceKey $dw $dwIns $ta[2]
            $lc = -1
            if ($leave -eq "loc <- AlertsRow::EmptyIsNothing") { for ($s = $ta[2] - 1; $s -ge $lo; $s--) { if ($dwIns[$s].OpCode.Name -like "stloc*" -and (Get-VarIndex $dwIns[$s]) -eq (Get-VarIndex $dwIns[$ta[2]])) { $lc = $s - 1; break } } }
            $la = if ($lc -ge $lo) { Get-ArgumentSources $dwIns $lc $dw.Body.ExceptionHandlers $lo } else { $null }
            if ($null -eq $la -or (Get-SourceKey $dw $dwIns $la[0]) -ne "AlertsRow::AlertsChangeMode") { $why += "the $($row[0]) row's Toggle is told whether to empty to None by $leave, not by AlertsRow.EmptyIsNothing(AlertsRow.AlertsChangeMode)"; continue }
        }
        # What is shown: IsMarked(its own filter, StarButtons[i]) into the toggle, with StarChoices[i].
        $ma = Get-ArgumentSources $dwIns $marks[0] $dw.Body.ExceptionHandlers $lo
        $ga = Get-ArgumentSources $dwIns $toggles[0] $dw.Body.ExceptionHandlers $lo
        if ($null -eq $ma -or $null -eq $ga) { $why += "the $($row[0]) row's IsMarked or toggle could not be traced"; continue }
        if (@($own, "loc <- $own") -notcontains (Get-SourceKey $dw $dwIns $ma[0])) { $why += ("the {0} row marks the buttons from {1}, not {2}" -f $row[0], (Get-SourceKey $dw $dwIns $ma[0]), $own); continue }
        if ((Get-ElementVar $dwIns $ma[1] "EntityListWindow::StarButtons") -ne $iv) { $why += "the $($row[0]) row does not mark button i as StarButtons[i]"; continue }
        if ((Get-ElementVar $dwIns $ga[1] "EntityListWindow::StarChoices") -ne $iv) { $why += "the $($row[0]) row does not label button i with StarChoices[i]"; continue }
        $mv = if ((Get-SourceKey $dw $dwIns $ga[0]) -eq "loc <- StarSets::IsMarked") { Get-VarIndex $dwIns[$ga[0]] } else { -1 }
        if ($mv -lt 0) { $why += "the $($row[0]) row's toggle is not given the IsMarked answer"; continue }
        $counted = @(for ($k = $lo; $k -lt $hi - 3; $k++) { if ($dwIns[$k].OpCode.Name -like "ldloc*" -and (Get-VarIndex $dwIns[$k]) -eq $iv -and $dwIns[$k + 1].OpCode.Name -eq "ldc.i4.1" -and $dwIns[$k + 2].OpCode.Name -eq "add" -and $dwIns[$k + 3].OpCode.Name -like "stloc*" -and (Get-VarIndex $dwIns[$k + 3]) -eq $iv) { $k } })
        if ($counted.Count -ne 1) { $why += "the $($row[0]) row's index is not the loop's counter (i++)"; continue }
        # Written only on a click: the toggle's answer compared with marked, equal skipping the write.
        $t0 = $toggles[0]
        $cmp = $dwIns[$t0 + 2]
        $skip = if ($cmp.OpCode.Name -like "beq*") { [array]::IndexOf($dwIns, $cmp.Operand) } else { -1 }
        if (-not ($dwIns[$t0 + 1].OpCode.Name -like "ldloc*" -and (Get-VarIndex $dwIns[$t0 + 1]) -eq $mv) -or $skip -le $writes[0] -or $writes[0] -lt $t0) { $why += ("the {0} row's write is not skipped when the toggle's answer equals marked ({1} {2})" -f $row[0], $dwIns[$t0 + 1].OpCode.Name, $cmp.OpCode.Name) }
    }
}
if ($why.Count -eq 0) { Ok "EntityListWindow.DrawWindow: each star row shows IsMarked(its own filter, StarButtons[i]) and, on a click only, writes its own *StarsText as Format(Toggle(its own filter, StarButtons[i]) - the Alerts: row's with the mode's None rule)" }
else { Fail ("EntityListWindow.DrawWindow: " + ($why -join "; ")) }
# The List: row is greyed out in the all-types view: before its first button GUI.enabled is set from the state found and
# !_allTypes (ldfld _allTypes; ldc.i4.0; ceq), and after its last one, before the Alerts: label, put back as found.
$checks++
$why = @()
if ($iList -lt 0 -or $iAlerts -le $iList) { $why += "the row labels were not found" } else {
    $en = @(for ($k = $iList; $k -lt $iAlerts; $k++) { $o = $dwIns[$k].Operand; if ($o -is [Mono.Cecil.MethodReference] -and ($o.DeclaringType.Name + "::" + $o.Name) -eq "GUI::set_enabled") { $k } })
    $firstButton = @(for ($k = $iList; $k -lt $iAlerts; $k++) { $o = $dwIns[$k].Operand; if ($o -is [Mono.Cecil.MethodReference] -and ($o.DeclaringType.Name + "::" + $o.Name) -eq "GUILayout::Toggle") { $k } }) | Select-Object -First 1
    if ($en.Count -ne 2 -or $null -eq $firstButton -or $en[0] -gt $firstButton -or $en[1] -lt $firstButton) { $why += ("GUI.enabled is set {0} time(s) in the List: row, expected once before its buttons and once after" -f $en.Count) } else {
        $notAll = @(for ($k = $iList; $k -lt $en[0] - 2; $k++) { $o = $dwIns[$k].Operand; if ($dwIns[$k].OpCode.Name -eq "ldfld" -and $o -is [Mono.Cecil.FieldReference] -and ($o.DeclaringType.Name + "::" + $o.Name) -eq "EntityListWindow::_allTypes" -and $dwIns[$k + 1].OpCode.Name -eq "ldc.i4.0" -and $dwIns[$k + 2].OpCode.Name -eq "ceq") { $k } })
        $found = @(for ($k = $iList; $k -lt $en[0]; $k++) { $o = $dwIns[$k].Operand; if ($o -is [Mono.Cecil.MethodReference] -and ($o.DeclaringType.Name + "::" + $o.Name) -eq "GUI::get_enabled") { $k } })
        if ($notAll.Count -ne 1 -or $found.Count -ne 1) { $why += "the List: row is not enabled as 'GUI.enabled && !_allTypes'" }
        $back = Get-ArgumentSources $dwIns $en[1] $dw.Body.ExceptionHandlers $iList
        if ($null -eq $back -or (Get-SourceKey $dw $dwIns $back[0]) -ne "loc <- GUI::get_enabled") { $why += "GUI.enabled is not put back as found after the List: row" }
    }
}
if ($why.Count -eq 0) { Ok "EntityListWindow.DrawWindow: the List: row is enabled only as GUI.enabled && !_allTypes, and GUI.enabled is put back after it" }
else { Fail ("EntityListWindow.DrawWindow: " + ($why -join "; ")) }

Write-Output "== failure isolation =="
# A creature with no ZNetView (its Awake failed after it went on the game's list) throws on every network read, ending the
# loop that met it. Creature.IsListable - asked first by every creature loop (rows above) - skips it: m_nview != null, a
# false answer returning false, before any Character method is asked.
$checks++
$lm = Get-Method "MobTracker.Creature" "IsListable"
$why = @()
if (-not $lm) { $why += "not found" } else {
    $li = @($lm.Body.Instructions)
    $nv = @(for ($k = 0; $k -lt $li.Count; $k++) { $o = $li[$k].Operand; if ($li[$k].OpCode.Name -eq "ldfld" -and $o -is [Mono.Cecil.FieldReference] -and $o.DeclaringType.Name -eq "Character" -and $o.Name -eq "m_nview") { $k } })
    $asked = @(for ($k = 0; $k -lt $li.Count; $k++) { $o = $li[$k].Operand; if ($o -is [Mono.Cecil.MethodReference] -and $o.DeclaringType.Name -eq "Character") { $k } })
    if ($nv.Count -ne 1) { $why += "Character.m_nview is read $($nv.Count) times, not once" }
    else {
        $k = $nv[0]
        $shape = ($k + 3 -lt $li.Count) -and $li[$k + 1].OpCode.Name -eq "ldnull" -and $li[$k + 2].Operand -is [Mono.Cecil.MethodReference] -and
            $li[$k + 2].Operand.Name -eq "op_Inequality" -and $li[$k + 3].OpCode.Name -like "brfalse*"
        $to = if ($shape) { [array]::IndexOf($li, $li[$k + 3].Operand) } else { -1 }
        if (-not $shape) { $why += "not 'm_nview != null' followed by a false branch" }
        elseif ($to -lt 0 -or $to + 1 -ge $li.Count -or $li[$to].OpCode.Name -ne "ldc.i4.0" -or $li[$to + 1].OpCode.Name -ne "ret") { $why += "a null m_nview does not lead to 'return false'" }
        if ($asked.Count -eq 0 -or $asked[0] -lt $k) { $why += "a Character method is asked before the m_nview test" }
    }
}
if ($why.Count -eq 0) { Ok "Creature.IsListable: a creature whose m_nview is null is not listable, before anything is asked of it" } else { Fail ("Creature.IsListable: " + ($why -join "; ")) }
# One creature that throws is skipped and the poll goes on, so the alerts the gate recorded before it are still shown: in
# WatchAlerts.Update the creature's reads and the gate's ShouldAlert sit in a try inside the loop (not holding the
# enumerator's MoveNext) whose handler catches System.Exception, does not throw again, and logs once (_failureLogged).
$checks++
$why = @()
function Test-InTry($h, $i) { return $h.TryStart.Offset -le $i.Offset -and ($null -eq $h.TryEnd -or $i.Offset -lt $h.TryEnd.Offset) }
$sa = @(Get-CallAt $wi 'AlertGate`1::ShouldAlert'); $mn = @(Get-CallAt $wi "Enumerator::MoveNext"); $gz = @(Get-CallAt $wi "Character::GetZDOID")
if ($sa.Count -ne 1 -or $mn.Count -ne 1 -or $gz.Count -ne 1) { $why += ("ShouldAlert / MoveNext / GetZDOID calls: {0} / {1} / {2}" -f $sa.Count, $mn.Count, $gz.Count) }
else {
    $guard = @($wau.Body.ExceptionHandlers | Where-Object { "$($_.HandlerType)" -eq "Catch" -and "$($_.CatchType.FullName)" -eq "System.Exception" -and
        (Test-InTry $_ $wi[$gz[0]]) -and (Test-InTry $_ $wi[$sa[0]]) -and -not (Test-InTry $_ $wi[$mn[0]]) })
    if ($guard.Count -ne 1) { $why += "no catch (System.Exception) around one creature's reads and ShouldAlert, inside the loop" }
    else {
        $h = $guard[0]
        $body = @($wi | Where-Object { $_.Offset -ge $h.HandlerStart.Offset -and ($null -eq $h.HandlerEnd -or $_.Offset -lt $h.HandlerEnd.Offset) })
        if (@($body | Where-Object { $_.OpCode.Name -eq "rethrow" -or $_.OpCode.Name -eq "throw" }).Count -gt 0) { $why += "the handler throws again" }
        $flag = @($body | Where-Object { $_.Operand -is [Mono.Cecil.FieldReference] -and $_.Operand.Name -eq "_failureLogged" } | ForEach-Object { $_.OpCode.Name })
        if (-not ($flag -contains "ldfld" -and $flag -contains "stfld")) { $why += "the handler does not log only once (_failureLogged)" }
    }
}
if ($why.Count -eq 0) { Ok "WatchAlerts.Update: a creature that throws is skipped and logged once; the poll goes on" } else { Fail ("WatchAlerts.Update: " + ($why -join "; ")) }

Write-Output "== the window =="
# The twice-a-second refresh re-sorts the rows by distance; it waits while the pointer is over the window or a mouse button
# is held, since an IMGUI button fires for whatever row is in its place when the mouse comes up. The pointer test divides by
# the GUI scale (the window is drawn scaled). After drawing, the rect is clamped so a corner stays on screen.
# Rules.ShouldRefresh decides (the tests drive it); here, what it is given, and that a false answer returns before the rows
# change: the player's own change, "due" (Time.time >= _nextRefresh: clt.un, then not), the pointer test, a held button
# (hotControl != 0: cgt.un).
Test-Calls @(,   # one row: the comma keeps it a row, not the table
    @("MobTracker.EntityListWindow", "Update", "Rules::ShouldRefresh",
        @("EntityListWindow::PlayerChanged", "ceq", "EntityListWindow::Covers", "cgt.un"), $brtrue)
)
Test-Wiring @(
    @("MobTracker.EntityListWindow", "Update", @("GUIUtility::get_hotControl", "EntityListWindow::_nextRefresh"), @()),
    @("MobTracker.EntityListWindow", "PlayerChanged", @("EntityListWindow::_refreshNow", "EntityListWindow::_query", "EntityListWindow::_appliedQuery",
        "EntityListWindow::_allTypes", "EntityListWindow::_appliedAllTypes", "ModConfig::ListStars", "EntityListWindow::_appliedListStars"), @("ModConfig::AlertStars", "ModConfig::AlertStarsText")),
    @("MobTracker.EntityListWindow", "OnGUI", @("Mathf::Clamp", "Rect::set_x", "Rect::set_y", "Screen::get_width", "Screen::get_height"), @())
)
# GUI.matrix is IMGUI's global state: each OnGUI that scales puts back the matrix it found - the window's in a finally around
# GUILayout.Window, the HUD label's after its last Label.
$checks++
$why = @()
$gm = Get-Method "MobTracker.EntityListWindow" "OnGUI"
$gi = @($gm.Body.Instructions)
$gw = @(Get-CallAt $gi "GUILayout::Window")
$restored = $false
foreach ($h in @($gm.Body.ExceptionHandlers | Where-Object { "$($_.HandlerType)" -eq "Finally" })) {
    if ($gw.Count -ne 1 -or -not (Test-InTry $h $gi[$gw[0]])) { continue }
    foreach ($q in @(Get-CallAt $gi "GUI::set_matrix")) {
        if ($gi[$q].Offset -lt $h.HandlerStart.Offset -or ($null -ne $h.HandlerEnd -and $gi[$q].Offset -ge $h.HandlerEnd.Offset)) { continue }
        $src = Get-ArgumentSources $gi $q $gm.Body.ExceptionHandlers
        if ($src -and (Get-SourceKey $gm $gi $src[0]) -eq "loc <- GUI::get_matrix") { $restored = $true }
    }
}
if (-not $restored) { $why += "EntityListWindow.OnGUI does not put back, in a finally around GUILayout.Window, the GUI.matrix it found" }
$tm = Get-Method "MobTracker.Tracker" "OnGUI"
$ti = @($tm.Body.Instructions)
$ts = @(Get-CallAt $ti "GUI::set_matrix"); $tl = @(Get-CallAt $ti "GUI::Label")
$last = if ($ts.Count -gt 0) { $ts[-1] } else { -1 }
$tsrc = if ($last -ge 0) { Get-ArgumentSources $ti $last $tm.Body.ExceptionHandlers } else { $null }
if ($last -lt 0 -or $tl.Count -eq 0 -or $last -lt $tl[-1] -or -not $tsrc -or (Get-SourceKey $tm $ti $tsrc[0]) -ne "loc <- GUI::get_matrix") { $why += "Tracker.OnGUI does not put back, after its last Label, the GUI.matrix it found" }
if ($why.Count -eq 0) { Ok "EntityListWindow.OnGUI and Tracker.OnGUI put back the GUI.matrix they found" } else { Fail ($why -join "; ") }
# The clamp's bounds are in GUI units, as the rect is: the screen's width and height (pixels) divided by the scale OnGUI
# drew with. In pixels, above 1080p the window could be dragged until no corner is on screen.
$checks++
$why = @()
foreach ($name in @("Screen::get_width", "Screen::get_height")) {
    $c = @(Get-CallAt $gi $name)
    if ($c.Count -ne 1) { $why += "$name calls: $($c.Count)"; continue }
    $q = $c[0]
    if ($q + 3 -ge $gi.Count -or $gi[$q + 1].OpCode.Name -ne "conv.r4" -or $gi[$q + 2].OpCode.Name -notlike "ldloc*" -or (Get-SourceKey $gm $gi ($q + 2)) -ne "loc <- EntityListWindow::get_GuiScale" -or $gi[$q + 3].OpCode.Name -ne "div") {
        $why += "$name is not divided by the drawing scale (EntityListWindow.GuiScale, read once)"
    }
}
if ($why.Count -eq 0) { Ok "EntityListWindow.OnGUI: the clamp's bounds are Screen.width and Screen.height divided by the drawing scale - GUI units" }
else { Fail ("EntityListWindow.OnGUI: " + ($why -join "; ")) }

Write-Output "== the alert ding =="
# The ding goes through the game's mixer, so the game's Volume and Effect volume apply (vanilla-behaviour.md section 17):
# Ding.Play plays only when Ding.Routed says so; Routed puts the source on the group FindGuiGroup found; FindGuiGroup finds
# it by the name "GUI" alone and never reads AudioMan.m_guiMixer (null in the game); nothing else plays a sound.
Test-Calls @(
    @("MobTracker.Ding", "Play", "Ding::Routed", @(), $brtrue),
    @("MobTracker.Ding", "Routed", "AudioSource::set_outputAudioMixerGroup", @("Ding::_source", "loc <- Ding::FindGuiGroup"), $null)
)
$checks++
$why = @()
$fg = Get-Method "MobTracker.Ding" "FindGuiGroup"
if (-not $fg) { $why += "Ding.FindGuiGroup not found" } else {
    $fi = @($fg.Body.Instructions)
    $eqs = @(Get-CallAt $fi "String::op_Equality")
    $gui = @($eqs | Where-Object { $s = Get-ArgumentSources $fi $_ $fg.Body.ExceptionHandlers; $s -and $fi[$s[1]].OpCode.Name -eq "ldstr" -and "$($fi[$s[1]].Operand)" -ceq "GUI" })
    if ($eqs.Count -lt 1 -or $gui.Count -ne $eqs.Count) { $why += "Ding.FindGuiGroup does not find the group by the name GUI alone" }
}
$plays = @(); $guiMixer = @()
foreach ($t in $plug.GetTypes()) {
    foreach ($m in $t.Methods) {
        if (-not $m.HasBody) { continue }
        foreach ($i in $m.Body.Instructions) {
            $op = $i.Operand
            if ($op -is [Mono.Cecil.MethodReference] -and $op.DeclaringType.Name -eq "AudioSource" -and $op.Name -like "Play*") { $plays += ("{0}.{1}: {2}" -f $t.Name, $m.Name, $op.Name) }
            if ($op -is [Mono.Cecil.FieldReference] -and $op.DeclaringType.Name -eq "AudioMan" -and $op.Name -eq "m_guiMixer") { $guiMixer += ("{0}.{1}" -f $t.Name, $m.Name) }
        }
    }
}
if ($plays.Count -ne 1 -or $plays[0] -ne "Ding.Play: PlayOneShot") { $why += ("sounds played: {0}; expected only Ding.Play: PlayOneShot" -f $(if ($plays.Count) { $plays -join ", " } else { "none" })) }
if ($guiMixer.Count -gt 0) { $why += ("AudioMan.m_guiMixer (null in the game) is read in {0}" -f ($guiMixer -join ", ")) }
if ($why.Count -eq 0) { Ok "the ding plays only from Ding.Play, through the mixer group Ding.FindGuiGroup finds by the name GUI" } else { Fail ($why -join "; ") }
# The fallback lookup (every AudioMixerGroup loaded) takes a group named GUI only from the game's own master mixer:
# group.audioMixer == the mixer read from AudioMan, a false answer skipping the group. Another mod's mixer can have a
# group of that name, outside the game's volume settings.
$checks++
$mx = @()
if ($fg) {
    foreach ($q in @(Get-CallAt $fi "Object::op_Equality")) {
        $s = Get-ArgumentSources $fi $q $fg.Body.ExceptionHandlers
        if ($s -and $s.Count -eq 2 -and (Get-SourceKey $fg $fi $s[0]) -eq "AudioMixerGroup::get_audioMixer" -and (Get-SourceKey $fg $fi $s[1]) -eq "loc <- AudioMan::m_masterMixer" -and $fi[$q + 1].OpCode.Name -like "brfalse*") { $mx += $q }
    }
}
if ($mx.Count -eq 1) { Ok "Ding.FindGuiGroup: the fallback takes a GUI group only when its audioMixer is the game's master mixer" }
else { Fail "Ding.FindGuiGroup: the fallback does not test group.audioMixer == the game's master mixer (another mod's GUI group could take the ding)" }

Write-Output "== the list's keys and what it blocks =="
# A literal int an instruction pushes, or $null; the try/catch (System.Exception) blocks around an instruction whose
# handler neither throws nor rethrows (TomTom's preflight).
function Get-LiteralInt($i) {
    $n = $i.OpCode.Name
    if ($n -match '^ldc\.i4\.([0-8])$') { return [int]$Matches[1] }
    if ($n -eq "ldc.i4.m1") { return -1 }
    if ($n -eq "ldc.i4" -or $n -eq "ldc.i4.s") { return [int]"$($i.Operand)" }
    return $null
}
function Get-CatchTries($m, $i) {
    $found = @()
    $all = @($m.Body.Instructions)
    foreach ($h in $m.Body.ExceptionHandlers) {
        if ($h.HandlerType -ne [Mono.Cecil.Cil.ExceptionHandlerType]::Catch -or $h.CatchType.FullName -ne "System.Exception") { continue }
        $end = [int]::MaxValue; if ($h.TryEnd) { $end = $h.TryEnd.Offset }
        if ($i.Offset -lt $h.TryStart.Offset -or $i.Offset -ge $end) { continue }
        $hEnd = [int]::MaxValue; if ($h.HandlerEnd) { $hEnd = $h.HandlerEnd.Offset }
        $throws = @($all | Where-Object { $_.Offset -ge $h.HandlerStart.Offset -and $_.Offset -lt $hEnd -and ($_.OpCode.Name -eq "throw" -or $_.OpCode.Name -eq "rethrow") })
        if ($throws.Count -eq 0) { $found += ,$h }
    }
    return ,$found
}

# Both input postfixes report BlocksGameInput - open, or closed this frame - never IsOpen alone: Menu.Update reads
# TextInput.IsVisible, not Chat.HasFocus, so with IsOpen alone the Escape that closes the list opens the pause menu
# whenever Menu.Update runs after this plugin's Update. And they only ever add true: each bool they store is a literal
# true or an OR with the value already there, so another mod's true (or real chat focus) is never cleared.
foreach ($pc in @("MobTracker.TextInputVisiblePatch", "MobTracker.ChatHasFocusPatch")) {
    $checks++
    $pm = Get-Method $pc "Postfix"
    if (-not $pm) { Fail "$pc.Postfix not found"; continue }
    $touch = Get-Touches $pm
    $pins = @($pm.Body.Instructions)
    $stores = @(for ($k = 0; $k -lt $pins.Count; $k++) { if ($pins[$k].OpCode.Name -eq "stind.i1") { $k } })
    $badStores = @($stores | Where-Object { $_ -lt 1 -or ($pins[$_ - 1].OpCode.Name -ne "ldc.i4.1" -and $pins[$_ - 1].OpCode.Name -ne "or") })
    $why = @()
    if (-not $touch.ContainsKey("EntityListWindow::get_BlocksGameInput")) { $why += "does not read EntityListWindow.BlocksGameInput" }
    if ($touch.ContainsKey("EntityListWindow::get_IsOpen")) { $why += "reads EntityListWindow.IsOpen (the closing frame is lost)" }
    if ($stores.Count -eq 0) { $why += "stores nothing into __result" }
    if ($badStores.Count -gt 0) { $why += "stores a value that is neither true nor an OR with __result - it can clear another mod's true" }
    if ($why.Count -eq 0) { Ok ("{0}.Postfix reports BlocksGameInput and only ever adds true" -f $pc.Split('.')[-1]) }
    else { Fail ("{0}.Postfix: {1}" -f $pc.Split('.')[-1], ($why -join "; ")) }
}
# Chatter's Chat.HasFocus postfix assigns __result outright at the default priority and loads after MobTracker, so at
# any priority it outranks this one would be undone. Priority.Last (0), on the method.
$checks++
$hfp = Get-Method "MobTracker.ChatHasFocusPatch" "Postfix"
$hfPriority = if ($hfp) { Get-Priority $hfp } else { $null }
if ($null -ne $hfPriority -and $hfPriority -eq 0) { Ok "ChatHasFocusPatch.Postfix runs last (HarmonyPriority 0 = Priority.Last), after Chatter's" }
else { Fail ("ChatHasFocusPatch.Postfix priority is {0}; it must be 0 (Priority.Last), set on the method" -f $(if ($null -eq $hfPriority) { "unset" } else { $hfPriority })) }
# The closing frame: BlocksGameInput is IsOpen or the frame Close recorded; every way the list closes goes through
# Close (only Open and Close set IsOpen); OnGUI reads no key any more (the focused search box took Escape's event
# there first, so the list never closed on it).
Test-Wiring @(
    @("MobTracker.EntityListWindow", "get_BlocksGameInput", @("EntityListWindow::get_IsOpen", "EntityListWindow::_closedFrame", "Time::get_frameCount"), @()),
    @("MobTracker.EntityListWindow", "Close", @("set EntityListWindow::_closedFrame", "Time::get_frameCount", "set EntityListWindow::_searchFocused"), @()),
    @("MobTracker.EntityListWindow", "OnGUI", @(), @("Event::get_keyCode", "EntityListWindow::set_IsOpen", "EntityListWindow::Close", "ZInput::GetKeyDown")),
    @("MobTracker.EntityListWindow", "Update", @("EntityListWindow::HandleKeys", "Console::IsVisible", "set EntityListWindow::_consoleWasVisible", "InventoryGui::IsVisible", "EntityListWindow::Close"), @("ZInput::GetKeyDown")),
    @("MobTracker.EntityListWindow", "HandleKeys", @("ZInput::ResetButtonStatus", "PlayerController::SetTakeInputDelay", "EntityListWindow::Open", "EntityListWindow::Close"), @()),
    @("MobTracker.EntityListWindow", "DrawWindow", @("GUIUtility::get_keyboardControl", "set EntityListWindow::_searchFocused"), @()),
    # Typing is read from the game's own fields, not from the two flags this plugin and TomTom force.
    @("MobTracker.GameTyping", "Any", @("TextInput::m_panel", "Chat::m_wasFocused", "BuildUi::get_SearchFieldFocused", "Minimap::InTextInput", "Console::IsVisible"), @("TextInput::IsVisible", "Chat::HasFocus"))
)
$checks++
$setters = @()
foreach ($t in $plug.GetTypes()) {
    foreach ($m in $t.Methods) {
        if (-not $m.HasBody) { continue }
        foreach ($i in $m.Body.Instructions) {
            $op = $i.Operand
            if ($op -is [Mono.Cecil.MethodReference] -and $op.Name -eq "set_IsOpen" -and $op.DeclaringType.FullName -eq "MobTracker.EntityListWindow") { $setters += ("{0}.{1}" -f $t.Name, $m.Name) }
        }
    }
}
$otherSetters = @($setters | Where-Object { $_ -ne "EntityListWindow.Open" -and $_ -ne "EntityListWindow.Close" })
if ($otherSetters.Count -eq 0 -and $setters -contains "EntityListWindow.Open" -and $setters -contains "EntityListWindow.Close") { Ok "only EntityListWindow.Open and Close set IsOpen, so every close records its frame" }
else { Fail ("IsOpen is set outside Open and Close: {0}" -f $(if ($otherSetters.Count) { ($otherSetters | Sort-Object -Unique) -join ", " } else { "(Open or Close never sets it)" })) }
# The decisions are ListKeys' (the unit tests give them in full); what they are given, and which way the code branches.
Test-Calls @(
    @("MobTracker.EntityListWindow", "HandleKeys", "ListKeys::ClosesOnBack",
        @("EntityListWindow::get_IsOpen", "arg consoleVisible", "arg consoleWasVisible", "ZInput::GetKeyDown", "ZInput::GetButtonDown"), $brfalse),
    @("MobTracker.EntityListWindow", "HandleKeys", "ListKeys::MayToggle",
        @("EntityListWindow::get_IsOpen", "Hotkeys::TypesText", "EntityListWindow::_searchFocused", "GameTyping::Any", "Menu::IsVisible", "Hud::IsPieceSelectionVisible", "InventoryGui::IsVisible", "PlayerCustomizaton::IsBarberGuiVisible"), $brfalse),
    @("MobTracker.EntityListWindow", "HandleKeys", "Hotkeys::TypesText", @("ModConfig::ListKey.Value"), $null),
    @("MobTracker.EntityListWindow", "HandleKeys", "Hotkeys::Pressed", @("ModConfig::ListKey"), $brfalse),
    @("MobTracker.EntityListWindow", "Update", "EntityListWindow::HandleKeys", @($null, "loc <- Console::IsVisible", "loc <- EntityListWindow::_consoleWasVisible"), $null),
    @("MobTracker.Hotkeys", "Pressed", "ListKeys::IsClickButton", @($null), $brfalse),
    # A refused key is remembered (Pressed tests Refused first), so it warns once, not on every frame.
    @("MobTracker.Hotkeys", "Refuse", 'List`1::Add', @("Hotkeys::Refused", "arg key"), $null),
    # A sign's, portal's or pet's name box counts as typing while its panel is active (a false answer goes on to chat).
    @("MobTracker.GameTyping", "Any", "GameObject::get_activeSelf", @("TextInput::m_panel"), $brfalse)
)
# What Update keeps for the next frame is this frame's console visibility (read once, before anything else).
$checks++
$upd = Get-Method "MobTracker.EntityListWindow" "Update"
$ui = if ($upd) { @($upd.Body.Instructions) } else { @() }
$cw = @(for ($k = 1; $k -lt $ui.Count; $k++) { if ($ui[$k].OpCode.Name -eq "stfld" -and "$($ui[$k].Operand.Name)" -eq "_consoleWasVisible") { $k } })
if ($cw.Count -eq 1 -and (Get-SourceKey $upd $ui ($cw[0] - 1)) -eq "loc <- Console::IsVisible") { Ok "EntityListWindow.Update keeps this frame's Console.IsVisible for the next frame, once" }
else { Fail ("EntityListWindow.Update: _consoleWasVisible is stored {0} time(s){1}" -f $cw.Count, $(if ($cw.Count -eq 1) { ", from " + (Get-SourceKey $upd $ui ($cw[0] - 1)) + ", not Console.IsVisible" } else { ", expected once" })) }
# The literals: Escape with logWarning false, and the gamepad's B both read and consumed.
$checks++
$hk = Get-Method "MobTracker.EntityListWindow" "HandleKeys"
$why = @()
if (-not $hk) { $why += "HandleKeys not found" } else {
    $hi = @($hk.Body.Instructions)
    $kd = @(Get-CallAt $hi "ZInput::GetKeyDown")
    if ($kd.Count -ne 1) { $why += "ZInput.GetKeyDown calls: $($kd.Count)" } else {
        $a = Get-ArgumentSources $hi $kd[0] $hk.Body.ExceptionHandlers
        if (-not $a -or (Get-LiteralInt $hi[$a[0]]) -ne 27 -or $hi[$a[1]].OpCode.Name -ne "ldc.i4.0") { $why += "Escape is not read as ZInput.GetKeyDown(KeyCode.Escape, false)" }
    }
    foreach ($name in @("ZInput::GetButtonDown", "ZInput::ResetButtonStatus")) {
        $c = @(Get-CallAt $hi $name)
        if ($c.Count -ne 1) { $why += "$name calls: $($c.Count)"; continue }
        $a = Get-ArgumentSources $hi $c[0] $hk.Body.ExceptionHandlers
        if (-not $a -or $hi[$a[0]].OpCode.Name -ne "ldstr" -or "$($hi[$a[0]].Operand)" -ne "JoyButtonB") { $why += "$name is not given ""JoyButtonB""" }
    }
}
if ($why.Count -eq 0) { Ok "EntityListWindow.HandleKeys reads ZInput.GetKeyDown(KeyCode.Escape, false) and JoyButtonB, and consumes JoyButtonB" }
else { Fail ("EntityListWindow.HandleKeys: " + ($why -join "; ")) }
# ListKey is read only through Hotkeys, which passes logWarning false and catches (a KeyCode missing from ZInput's
# table throws on every read); elsewhere a key read must be a literal (Escape). The mouse buttons ListKeys refuses are
# UnityEngine.KeyCode's Mouse0 to Mouse2 in this Unity.
$checks++
$keyProblems = @(); $hotkeyReads = 0
foreach ($t in $plug.GetTypes()) {
    foreach ($m in $t.Methods) {
        if (-not $m.HasBody) { continue }
        $ins = @($m.Body.Instructions)
        for ($k = 0; $k -lt $ins.Count; $k++) {
            $op = $ins[$k].Operand
            if (-not ($op -is [Mono.Cecil.MethodReference]) -or $op.DeclaringType.FullName -ne "ZInput" -or @("GetKey", "GetKeyDown", "GetKeyUp") -notcontains $op.Name) { continue }
            if ($op.Parameters.Count -lt 1 -or $op.Parameters[0].ParameterType.FullName -ne "UnityEngine.KeyCode") { continue }
            $where = "{0}.{1} ZInput.{2}" -f $t.Name, $m.Name, $op.Name
            $src = Get-ArgumentSources $ins $k $m.Body.ExceptionHandlers
            if ($t.FullName -eq "MobTracker.Hotkeys") {
                $hotkeyReads++
                if ((Get-CatchTries $m $ins[$k]).Count -eq 0) { $keyProblems += "$where is not inside a try whose catch (System.Exception) does not rethrow" }
                if ($null -eq $src -or $src.Count -lt 2 -or $ins[$src[1]].OpCode.Name -ne "ldc.i4.0") { $keyProblems += "$where does not pass a literal false for logWarning" }
            }
            elseif ($null -eq $src -or $null -eq (Get-LiteralInt $ins[$src[0]])) { $keyProblems += "$where reads a key that is not a literal outside Hotkeys" }
        }
    }
}
if ($hotkeyReads -eq 0) { $keyProblems += "Hotkeys makes no ZInput key read" }
$kc = $null; foreach ($gm in $gameModules.Values) { $x = $gm.GetType("UnityEngine.KeyCode"); if ($x) { $kc = $x; break } }
$kcv = @{}; if ($kc) { foreach ($f in $kc.Fields) { if ($f.HasConstant) { $kcv[$f.Name] = [int]$f.Constant } } }
if ($kcv["Mouse0"] -ne 323 -or $kcv["Mouse2"] -ne 325) { $keyProblems += ("UnityEngine.KeyCode Mouse0/Mouse2 are {0}/{1}, not ListKeys' 323/325" -f $kcv["Mouse0"], $kcv["Mouse2"]) }
if ($keyProblems.Count -eq 0) { Ok "ListKey is read only through Hotkeys (logWarning false, caught); elsewhere only literal keys; KeyCode.Mouse0-Mouse2 are 323-325" }
else { foreach ($p in $keyProblems) { Fail $p } }
# A new ListKey is tried afresh: ModConfig.Bind hands ListKey.SettingChanged to Hotkeys.Forget.
$checks++
$bind = Get-TouchesWithLambdas "MobTracker.ModConfig" "Bind"
if ($bind -and $bind.ContainsKey("Hotkeys::Forget")) { Ok "ModConfig.Bind: a changed ListKey makes Hotkeys forget the keys it refused" }
else { Fail "ModConfig.Bind never calls Hotkeys.Forget - a refused ListKey stays refused after the setting changes" }

Write-Output "== the mouse wheel =="
# ZInput's wheel has readers that ask neither forced flag (the free-fly camera, Server Devcommands' wheel binds), so
# MouseWheelPatch zeroes it while the list blocks game input: it runs last (after MeasurementTracker has recorded the real
# wheel), reads BlocksGameInput, skips the store when that is false, and only ever stores 0.
$checks++
$mw = Get-Method "MobTracker.MouseWheelPatch" "Postfix"
$why = @()
if (-not $mw) { $why += "not found" } else {
    $mwp = Get-Priority $mw
    if ($null -eq $mwp -or $mwp -ne 0) { $why += ("priority is {0}; it must be 0 (Priority.Last), set on the method" -f $(if ($null -eq $mwp) { "unset" } else { $mwp })) }
    $mt = Get-Touches $mw
    if (-not $mt.ContainsKey("EntityListWindow::get_BlocksGameInput")) { $why += "does not read EntityListWindow.BlocksGameInput" }
    if ($mt.ContainsKey("EntityListWindow::get_IsOpen")) { $why += "reads EntityListWindow.IsOpen (the closing frame is lost)" }
    $mi = @($mw.Body.Instructions)
    $st = @(for ($k = 0; $k -lt $mi.Count; $k++) { if ($mi[$k].OpCode.Name -like "stind.*") { $k } })
    $bad = @($st | Where-Object { $_ -lt 1 -or $mi[$_ - 1].OpCode.Name -ne "ldc.r4" -or [single]"$($mi[$_ - 1].Operand)" -ne 0 })
    if ($st.Count -eq 0) { $why += "stores nothing into __result" }
    if ($bad.Count -gt 0) { $why += "stores a value other than 0 into __result" }
}
if ($why.Count -eq 0) { Ok "MouseWheelPatch.Postfix runs last, reads BlocksGameInput and only ever sets the wheel to 0" }
else { Fail ("MouseWheelPatch.Postfix: " + ($why -join "; ")) }
Test-Calls @(, @("MobTracker.MouseWheelPatch", "Postfix", "EntityListWindow::get_BlocksGameInput", @(), $brfalse))

Write-Output "== TomTom and Wayfinder: their keys over the open list =="
# TomTom and Wayfinder read their keys only while their Plugin.IsTypingElsewhere() is false, and it asks the two flags
# the list forces. WaypointerCompat puts a Prefix (SuspendDepth++) and a void Finalizer (SuspendDepth-- while above 0)
# on it, and both forcing postfixes stand aside while SuspendDepth is above 0. Each piece is one line a refactor can
# drop while everything else still passes.
# (1) Each forcing postfix tests SuspendDepth first, and a non-zero value jumps past every store to __result.
foreach ($pc in @("MobTracker.TextInputVisiblePatch", "MobTracker.ChatHasFocusPatch")) {
    $checks++
    $short = $pc.Split('.')[-1]
    $pm = Get-Method $pc "Postfix"
    $why = @()
    if (-not $pm) { $why += "no Postfix" } else {
        $pi = @($pm.Body.Instructions)
        $at = -1
        for ($k = 0; $k -lt $pi.Count; $k++) {
            $op = $pi[$k].Operand
            if ($pi[$k].OpCode.Name -eq "ldsfld" -and $op -is [Mono.Cecil.FieldReference] -and ($op.DeclaringType.Name + "::" + $op.Name) -eq "WaypointerCompat::SuspendDepth") { $at = $k; break }
        }
        $stores = @(for ($k = 0; $k -lt $pi.Count; $k++) { if ($pi[$k].OpCode.Name -like "stind.*") { $k } })
        if ($at -lt 0) { $why += "never reads WaypointerCompat.SuspendDepth" }
        elseif ($pi[$at + 1].OpCode.Name -notlike "brtrue*") { $why += ("SuspendDepth is followed by {0}, not brtrue (skip the forcing while it is above 0)" -f $pi[$at + 1].OpCode.Name) }
        elseif ($stores.Count -eq 0) { $why += "stores nothing to __result" }
        else {
            $skipTo = [array]::IndexOf($pi, $pi[$at + 1].Operand)
            if (@($stores | Where-Object { $_ -lt $at -or $_ -ge $skipTo }).Count -gt 0) { $why += "a store to __result that the SuspendDepth test does not skip" }
        }
    }
    if ($why.Count -eq 0) { Ok ("{0}.Postfix forces nothing while WaypointerCompat.SuspendDepth is above 0" -f $short) }
    else { Fail ("{0}.Postfix: {1}" -f $short, ($why -join "; ")) }
}
# (2) The Prefix only raises SuspendDepth by one; the Finalizer is void with no parameters (so an exception passes
#     through unchanged, HarmonyX 2.9) and lowers it by one behind a "> 0" test.
function Get-DepthStep($m) {
    # "+1" or "-1" for each SuspendDepth = SuspendDepth +/- 1 in the method (ldsfld, ldc.i4.1, add/sub, stsfld), "?" for any other store.
    $ins = @($m.Body.Instructions); $out = @()
    for ($k = 0; $k -lt $ins.Count; $k++) {
        $op = $ins[$k].Operand
        if ($ins[$k].OpCode.Name -ne "stsfld" -or -not ($op -is [Mono.Cecil.FieldReference]) -or $op.Name -ne "SuspendDepth") { continue }
        $shape = $k -ge 3 -and $ins[$k - 3].OpCode.Name -eq "ldsfld" -and $ins[$k - 3].Operand.Name -eq "SuspendDepth" -and $ins[$k - 2].OpCode.Name -eq "ldc.i4.1"
        if ($shape -and $ins[$k - 1].OpCode.Name -eq "add") { $out += "+1" } elseif ($shape -and $ins[$k - 1].OpCode.Name -eq "sub") { $out += "-1" } else { $out += "?" }
    }
    return ,$out
}
$checks++
$cPre = Get-Method "MobTracker.WaypointerCompat" "Prefix"
$cFin = Get-Method "MobTracker.WaypointerCompat" "Finalizer"
$why = @()
if (-not $cPre -or -not $cFin) { $why += "WaypointerCompat.Prefix or .Finalizer not found" } else {
    if (((Get-DepthStep $cPre) -join ",") -ne "+1") { $why += ("Prefix changes SuspendDepth by '{0}', not '+1'" -f ((Get-DepthStep $cPre) -join ",")) }
    if (((Get-DepthStep $cFin) -join ",") -ne "-1") { $why += ("Finalizer changes SuspendDepth by '{0}', not '-1'" -f ((Get-DepthStep $cFin) -join ",")) }
    if ($cFin.ReturnType.FullName -ne "System.Void" -or $cFin.Parameters.Count -ne 0) { $why += "Finalizer is not 'static void Finalizer()' - a non-void finalizer replaces or swallows the exception" }
    if (-not $cPre.IsStatic -or -not $cFin.IsStatic) { $why += "Prefix and Finalizer must be static" }
    $fi = @($cFin.Body.Instructions)
    $dec = -1; for ($k = 0; $k -lt $fi.Count; $k++) { if ($fi[$k].OpCode.Name -eq "stsfld") { $dec = $k } }
    $guarded = $false
    for ($k = 0; $k -lt $dec - 3; $k++) { if ("$($fi[$k].OpCode.FlowControl)" -eq "Cond_Branch" -and [array]::IndexOf($fi, $fi[$k].Operand) -gt $dec) { $guarded = $true } }
    if (-not $guarded) { $why += "Finalizer lowers SuspendDepth without a '> 0' test - a throw before the Prefix ran would drive it below 0" }
}
if ($why.Count -eq 0) { Ok "WaypointerCompat: Prefix raises SuspendDepth by 1; 'static void Finalizer()' lowers it by 1 while above 0" }
else { Fail ("WaypointerCompat: " + ($why -join "; ")) }
# (3) The one Harmony.Patch call: prefix = WaypointerCompat.Prefix, finalizer = WaypointerCompat.Finalizer, nothing
#     else. As a postfix, the reset would not run when the method throws, and the list would stop blocking the game.
$checks++
$cAt = Get-Method "MobTracker.WaypointerCompat" "ApplyTo"
$why = @()
if (-not $cAt) { $why += "WaypointerCompat.ApplyTo not found" } else {
    $ai = @($cAt.Body.Instructions)
    $pc = @(Get-CallAt $ai "Harmony::Patch")
    if ($pc.Count -ne 1) { $why += ("{0} Harmony.Patch calls, expected 1" -f $pc.Count) } else {
        $src = Get-ArgumentSources $ai $pc[0] $cAt.Body.ExceptionHandlers
        if ($ai[$pc[0]].Operand.Parameters.Count -ne 6) { $why += "not the 6-parameter Harmony.Patch" }
        elseif ($null -eq $src) { $why += "its values could not be traced" }
        else {
            $got = @()
            foreach ($v in 2..6) {
                $k = $src[$v]
                if ($ai[$k].OpCode.Name -ne "newobj") { $got += $ai[$k].OpCode.Name; continue }
                # Get-ArgumentSources counts a constructor's "this" for a newobj too, so the arguments are the last three.
                $hs = Get-ArgumentSources $ai $k $cAt.Body.ExceptionHandlers
                if ($hs -and $hs.Count -ge 3) { $hs = @($hs[($hs.Count - 3)..($hs.Count - 1)]) }
                $ok = $hs -and $hs.Count -eq 3 -and $ai[$hs[1]].OpCode.Name -eq "ldstr" -and $hs[0] -ge 1 -and $ai[$hs[0] - 1].OpCode.Name -eq "ldtoken" -and "$($ai[$hs[0] - 1].Operand.FullName)" -eq "MobTracker.WaypointerCompat"
                $got += $(if ($ok) { "WaypointerCompat." + $ai[$hs[1]].Operand } else { "a HarmonyMethod not built from (typeof(WaypointerCompat), name)" })
            }
            $want = @("WaypointerCompat.Prefix", "ldnull", "ldnull", "WaypointerCompat.Finalizer", "ldnull")
            if (($got -join ",") -cne ($want -join ",")) { $why += ("prefix, postfix, transpiler, finalizer, ilmanipulator are {0}, expected {1}" -f ($got -join ", "), ($want -join ", ")) }
            $orig = Get-SourceKey $cAt $ai $src[1]
            if ($orig -cne "loc <- Type::GetMethod") { $why += "the patched method is $orig, not the Type.GetMethod result" }
        }
    }
    # What it asks for: public static IsTypingElsewhere() with no parameters (BindingFlags 24 = Public | Static).
    $gm = @(Get-CallAt $ai "Type::GetMethod")
    $gs = if ($gm.Count -eq 1) { Get-ArgumentSources $ai $gm[0] $cAt.Body.ExceptionHandlers } else { $null }
    if ($null -eq $gs -or $gs.Count -ne 6) { $why += "expected one traceable Type.GetMethod(name, flags, binder, types, modifiers) call" }
    elseif ("$($ai[$gs[1]].Operand)" -cne "IsTypingElsewhere" -or $ai[$gs[2]].OpCode.Name -notlike "ldc.i4*" -or [int]"$($ai[$gs[2]].Operand)" -ne 24 -or (Get-SourceKey $cAt $ai $gs[4]) -ne "Type::EmptyTypes") {
        $why += ("GetMethod asks for '{0}' with flags {1} and types {2}, not 'IsTypingElsewhere', 24 (Public | Static), Type.EmptyTypes" -f $ai[$gs[1]].Operand, $ai[$gs[2]].Operand, (Get-SourceKey $cAt $ai $gs[4]))
    }
}
if ($why.Count -eq 0) { Ok "WaypointerCompat.ApplyTo patches public static IsTypingElsewhere() with prefix Prefix and finalizer Finalizer, nothing else" }
else { Fail ("WaypointerCompat.ApplyTo: " + ($why -join "; ")) }
# (4) Where it looks: both editions' GUIDs, in Chainloader.PluginInfos; applied once, from Start (in Awake TomTom's
#     assembly is not loaded yet: BepInEx creates the plugins in GUID order, com.mobtracker before DoomMachine).
$checks++
$cc = Get-Method "MobTracker.WaypointerCompat" ".cctor"
$gl = if ($cc) { @($cc.Body.Instructions | Where-Object { $_.OpCode.Name -eq "ldstr" } | ForEach-Object { "$($_.Operand)" }) } else { @() }
$why = @($(foreach ($g in @("DoomMachine.TomTom", "DoomMachine.Wayfinder")) { if ($gl -cnotcontains $g) { "no '$g' in WaypointerCompat.Guids" } }))
$cAp = Get-Method "MobTracker.WaypointerCompat" "Apply"
$tAp = if ($cAp) { Get-Touches $cAp } else { @{} }
foreach ($need in @("Chainloader::get_PluginInfos", "WaypointerCompat::Guids", "WaypointerCompat::ApplyTo")) { if (-not $tAp.ContainsKey($need)) { $why += "Apply does not use $need" } }
$applyCalls = @()
foreach ($t in $plug.GetTypes()) { foreach ($m in $t.Methods) { if (-not $m.HasBody) { continue }; foreach ($i in $m.Body.Instructions) { $op = $i.Operand; if ($op -is [Mono.Cecil.MethodReference] -and $op.Name -eq "Apply" -and $op.DeclaringType.FullName -eq "MobTracker.WaypointerCompat") { $applyCalls += ("{0}.{1}" -f $t.Name, $m.Name) } } } }
if (($applyCalls -join ",") -ne "MobTrackerPlugin.Start") { $why += ("WaypointerCompat.Apply is called from {0}, expected once, from MobTrackerPlugin.Start" -f $(if ($applyCalls.Count) { $applyCalls -join ", " } else { "nowhere" })) }
if ($why.Count -eq 0) { Ok "WaypointerCompat looks up DoomMachine.TomTom and DoomMachine.Wayfinder in Chainloader.PluginInfos, applied once from MobTrackerPlugin.Start" }
else { Fail ("WaypointerCompat: " + ($why -join "; ")) }
Test-Calls @(, @("MobTracker.MobTrackerPlugin", "Start", "WaypointerCompat::Apply", @("MobTrackerPlugin::_harmony"), $null))
# (5) The other side, read from TomTom's and Wayfinder's own DLLs (the installed ones, or -Waypointer <dll>,<dll>): the
#     method exists with that shape under a GUID WaypointerCompat names, it reads exactly the two flags the list
#     forces, and nothing else in the plugin reads them - so standing aside inside it is the whole carve-out.
$wpDlls = @($Waypointer | ForEach-Object { $_ -split "," } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($wpDlls.Count -eq 0) {
    foreach ($n in @("DoomMachine-TomTom\TomTom.dll", "DoomMachine-Wayfinder\Wayfinder.dll")) {
        $f = Join-Path $ValheimDir "BepInEx\plugins\$n"
        if (Test-Path -LiteralPath $f) { $wpDlls += $f }
    }
}
if ($wpDlls.Count -eq 0) { Write-Output "  note  neither TomTom nor Wayfinder is installed; their side is not checked (-Waypointer <dll> checks a copy)" }
foreach ($f in $wpDlls) {
    $checks++
    $why = @()
    $wm = $null
    try { $wm = [Mono.Cecil.ModuleDefinition]::ReadModule((Resolve-Path -LiteralPath $f).Path, $rp) } catch { $why += "cannot be read: $($_.Exception.Message)" }
    $wpGuid = ""
    if ($wm) {
        $wp = $wm.GetType("Waypointer.Plugin")
        if (-not $wp) { $why += "no Waypointer.Plugin" } else {
            foreach ($ca in $wp.CustomAttributes) { if ($ca.AttributeType.Name -eq "BepInPlugin") { $wpGuid = "$($ca.ConstructorArguments[0].Value) $($ca.ConstructorArguments[2].Value)" } }
            if ($gl -cnotcontains $wpGuid.Split(' ')[0]) { $why += "its GUID '$wpGuid' is not one WaypointerCompat looks for" }
            $ite = $wp.Methods | Where-Object { $_.Name -ceq "IsTypingElsewhere" -and $_.Parameters.Count -eq 0 } | Select-Object -First 1
            if (-not $ite -or -not $ite.IsPublic -or -not $ite.IsStatic -or $ite.ReturnType.FullName -ne "System.Boolean") { $why += "no 'public static bool IsTypingElsewhere()'" }
        }
        $readers = @()
        foreach ($t in $wm.GetTypes()) { foreach ($m in $t.Methods) { if (-not $m.HasBody) { continue }; foreach ($i in $m.Body.Instructions) { $op = $i.Operand
            if ($op -is [Mono.Cecil.MethodReference] -and @("TextInput::IsVisible", "Chat::HasFocus") -contains ($op.DeclaringType.Name + "::" + $op.Name)) { $readers += ("{0}.{1}>{2}::{3}" -f $t.Name, $m.Name, $op.DeclaringType.Name, $op.Name) } } } }
        $readers = @($readers | Sort-Object -Unique)
        if (($readers -join ",") -cne "Plugin.IsTypingElsewhere>Chat::HasFocus,Plugin.IsTypingElsewhere>TextInput::IsVisible") { $why += ("the readers of TextInput.IsVisible / Chat.HasFocus are {0}, expected Plugin.IsTypingElsewhere reading both" -f ($readers -join ", ")) }
    }
    if ($why.Count -eq 0) { Ok ("{0} ({1}): public static bool IsTypingElsewhere() is its only reader of TextInput.IsVisible and Chat.HasFocus" -f (Split-Path $f -Leaf), $wpGuid) }
    else { Fail ("{0}: {1}" -f (Split-Path $f -Leaf), ($why -join "; ")) }
}

Write-Output "== clicks on the list stay on the list =="
# The list is IMGUI, which uGUI cannot see: UiRaycastPatch empties EventSystem.RaycastAll's results while the pointer is
# on the window, so no game UI under it gets a hover, press, click, drop or wheel. Checked here, because no build or
# unit test can see it: the postfix runs last; it empties the list it is given (the input module's own cache, not a
# copy); it decides from the raycast's own position; a pointer off the window skips the Clear; and Covers hands the
# pure test (Rules.PointerOverWindow, unit-tested) the window's own rect in order, the drawing scale, the screen's
# height and the point - a constant for the scale is TomTom's unscaled test, which misses the window above 1080p.
$checks++
$rcPostfix = $null
foreach ($t in $patchClasses) { if ($t.Name -eq "UiRaycastPatch") { $rcPostfix = $t.Methods | Where-Object { $_.Name -eq "Postfix" } | Select-Object -First 1 } }
$rcPriority = if ($rcPostfix) { Get-Priority $rcPostfix } else { $null }
if ($null -ne $rcPriority -and $rcPriority -le 0) { Ok "UiRaycastPatch.Postfix runs at priority $rcPriority (Last), after every other postfix" }
else { Fail ("UiRaycastPatch.Postfix priority is {0}; it must be Priority.Last (0), set on the method" -f $(if ($null -eq $rcPriority) { "unset" } else { $rcPriority })) }
Test-Calls @(
    @("MobTracker.UiRaycastPatch", "Postfix", 'List`1::Clear', @("arg raycastResults"), $null),
    @("MobTracker.UiRaycastPatch", "Postfix", "EntityListWindow::Covers", @("PointerEventData::get_position"), $brfalse),
    @("MobTracker.UiRaycastPatch", "Postfix", "PointerEventData::get_position", @("arg eventData"), $null),
    @("MobTracker.EntityListWindow", "Covers", "Rules::PointerOverWindow",
        @("Rect::get_x", "Rect::get_y", "Rect::get_width", "Rect::get_height", "EntityListWindow::get_GuiScale", "Screen::get_height", "Vector2::x", "Vector2::y"), @("ret"))
)
Test-Wiring @(
    @("MobTracker.UiRaycastPatch", "Postfix", @("EntityListWindow::Covers"), @("ZInput::get_pointerPosition", 'List`1::Add', 'List`1::RemoveAt')),
    @("MobTracker.EntityListWindow", "Covers", @("EntityListWindow::get_IsOpen", "EntityListWindow::_rect"), @()),
    @("MobTracker.EntityListWindow", "OnGUI", @("GUILayout::Window", "set EntityListWindow::_rect"), @())
)

Write-Output "== what the traced answers decide =="
# The checks above trace what a call is given and which way the code branches on its answer. These follow the answers
# one step further - where a stored answer goes, what a branch's true path does, how two tests combine, where a loop
# starts and stops, which coordinate a bound clamps - each an exact IL shape read from the build, so a rewrite of these
# lines fails here and is re-read against the IL rather than the check loosened. tools\mutants.ps1 rows in brackets.
# The alert poll hands ShouldAlert its own values, and a false answer skips the creature; its second value, 'watched',
# is the local stored once at the join of 'StarSets.Accepts(...) && Watchlist.Contains(...)' [A14, A15, A16].
Test-Calls @(,
    @("MobTracker.WatchAlerts", "Update", 'AlertGate`1::ShouldAlert',
        @("WatchAlerts::_gate", "loc <- Character::GetZDOID", $null, "Character::IsTamed", "loc <- Vector3::Distance", "ModConfig::AlertRadius.Value"), $brtrue)
)
$checks++
$why = @()
$pwm = Get-Method "MobTracker.WatchAlerts" "Update"; $pwi = @($pwm.Body.Instructions)
$psa = @(Get-CallAt $pwi 'AlertGate`1::ShouldAlert'); $pac = @(Get-CallAt $pwi "StarSets::Accepts")
if ($psa.Count -ne 1 -or $pac.Count -ne 1) { $why += ("ShouldAlert / Accepts calls: {0} / {1}" -f $psa.Count, $pac.Count) } else {
    $src = Get-ArgumentSources $pwi $psa[0] $pwm.Body.ExceptionHandlers
    if ($null -eq $src -or $src.Count -ne 6) { $why += "ShouldAlert's values could not be traced" } else {
        $w = $pwi[$src[2]]
        $var = if ($w.OpCode.Name -like "ldloc*" -and $w.OpCode.Name -notlike "ldloca*") { Get-VarIndex $w } else { -1 }
        $st = @(for ($k = 0; $k -lt $pwi.Count; $k++) { if ($pwi[$k].OpCode.Name -like "stloc*" -and (Get-VarIndex $pwi[$k]) -eq $var) { $k } })
        $j = if ($var -ge 0 -and $st.Count -eq 1) { $st[0] } else { -1 }
        $shape = $j -ge 3 -and $pwi[$pac[0] + 1].OpCode.Name -like "brfalse*" -and [array]::IndexOf($pwi, $pwi[$pac[0] + 1].Operand) -eq ($j - 1) -and
            $pwi[$j - 1].OpCode.Name -eq "ldc.i4.0" -and @("br", "br.s") -contains $pwi[$j - 2].OpCode.Name -and [array]::IndexOf($pwi, $pwi[$j - 2].Operand) -eq $j -and
            (Get-SourceKey $pwm $pwi ($j - 3)) -eq 'HashSet`1::Contains'
        if (-not $shape) { $why += "ShouldAlert's second value is not the local stored once as StarSets.Accepts(...) && Watchlist.Contains(...)" }
    }
}
if ($why.Count -eq 0) { Ok "WatchAlerts.Update: ShouldAlert is given watched = Accepts(...) && Watchlist.Contains(...), stored once at the && join" }
else { Fail ("WatchAlerts.Update: " + ($why -join "; ")) }

# Pressed answers false at once for a key in Refused (Contains(Refused, the key read), its true answer going straight
# to 'return false'; the Count > 0 shortcut skipping only to where a key not refused goes), and for a mouse-button key
# refuses it and answers false at once [K39, K40, K41].
Test-Calls @(,
    @("MobTracker.Hotkeys", "Pressed", 'List`1::Contains', @("Hotkeys::Refused", 'loc <- ConfigEntry`1::get_Value'), $brfalse)
)
$checks++
$why = @()
$phm = Get-Method "MobTracker.Hotkeys" "Pressed"; $phi = @($phm.Body.Instructions)
$pco = @(Get-CallAt $phi 'List`1::Contains'); $pcn = @(Get-CallAt $phi 'List`1::get_Count'); $pic = @(Get-CallAt $phi "ListKeys::IsClickButton")
if ($pco.Count -ne 1 -or $pic.Count -ne 1) { $why += ("Contains / IsClickButton calls: {0} / {1}" -f $pco.Count, $pic.Count) } else {
    $q = $pco[0]
    if (-not ($phi[$q + 1].OpCode.Name -like "brfalse*" -and $phi[$q + 2].OpCode.Name -eq "ldc.i4.0" -and $phi[$q + 3].OpCode.Name -eq "ret")) { $why += "a refused key does not answer false at once" }
    $skip = [array]::IndexOf($phi, $phi[$q + 1].Operand)
    foreach ($c in $pcn) { if (-not ($phi[$c + 1].OpCode.Name -eq "ldc.i4.0" -and $phi[$c + 2].OpCode.Name -like "ble*" -and [array]::IndexOf($phi, $phi[$c + 2].Operand) -eq $skip)) { $why += "Refused.Count is not tested as '> 0', skipping to where a key not refused goes" } }
    $t = $pic[0] + 2
    $rf = @(for ($k = $t; $k -lt [Math]::Min($t + 6, $phi.Count); $k++) { $o = $phi[$k].Operand; if ($o -is [Mono.Cecil.MethodReference] -and ($o.DeclaringType.Name + "::" + $o.Name) -eq "Hotkeys::Refuse") { $k } })
    if ($phi[$pic[0] + 1].OpCode.Name -notlike "brfalse*" -or $rf.Count -ne 1 -or $phi[$rf[0] + 1].OpCode.Name -ne "ldc.i4.0" -or $phi[$rf[0] + 2].OpCode.Name -ne "ret") { $why += "a mouse-button ListKey is not refused and answered false at once" }
}
if ($why.Count -eq 0) { Ok "Hotkeys.Pressed: a refused key, and a mouse-button key once refused, answer false at once" }
else { Fail ("Hotkeys.Pressed: " + ($why -join "; ")) }

# In the ding's fallback, the name test (group.name == "GUI") and the mixer test are both required: each false answer
# skips to the same place [D8].
$checks++
$pfg = Get-Method "MobTracker.Ding" "FindGuiGroup"; $pfi = @($pfg.Body.Instructions)
$both = 0
foreach ($q in @(Get-CallAt $pfi "Object::op_Equality")) {
    $s = Get-ArgumentSources $pfi $q $pfg.Body.ExceptionHandlers
    if (-not ($s -and $s.Count -eq 2 -and (Get-SourceKey $pfg $pfi $s[0]) -eq "AudioMixerGroup::get_audioMixer" -and $pfi[$q + 1].OpCode.Name -like "brfalse*")) { continue }
    $skip = [array]::IndexOf($pfi, $pfi[$q + 1].Operand)
    foreach ($p in @(Get-CallAt $pfi "String::op_Equality" | Where-Object { $_ -lt $q -and $_ -gt $q - 8 })) {
        $ns = Get-ArgumentSources $pfi $p $pfg.Body.ExceptionHandlers
        if ($ns -and $ns.Count -eq 2 -and (Get-SourceKey $pfg $pfi $ns[0]) -eq "Object::get_name" -and $pfi[$ns[1]].OpCode.Name -eq "ldstr" -and "$($pfi[$ns[1]].Operand)" -eq "GUI" -and
            $pfi[$p + 1].OpCode.Name -like "brfalse*" -and [array]::IndexOf($pfi, $pfi[$p + 1].Operand) -eq $skip) { $both++ }
    }
}
if ($both -eq 1) { Ok "Ding.FindGuiGroup: the fallback takes a group only when its name is GUI AND its mixer is the game's" }
else { Fail "Ding.FindGuiGroup: the fallback's name test and mixer test are not both required (each false answer skipping the group)" }

# The List: row's GUI.enabled is exactly 'enabled && !_allTypes' [S31]:
# ldloc <enabled>; brfalse L; ldarg.0; ldfld _allTypes; ldc.i4.0; ceq; br M; L: ldc.i4.0; M: call GUI::set_enabled.
$checks++
$pen = @(for ($k = $iList; $k -lt $iAlerts; $k++) { $o = $dwIns[$k].Operand; if ($o -is [Mono.Cecil.MethodReference] -and ($o.DeclaringType.Name + "::" + $o.Name) -eq "GUI::set_enabled") { $k } })
$e = if ($pen.Count -ge 1) { $pen[0] } else { -1 }
$shape = $e -ge 8 -and $dwIns[$e - 1].OpCode.Name -eq "ldc.i4.0" -and @("br", "br.s") -contains $dwIns[$e - 2].OpCode.Name -and [array]::IndexOf($dwIns, $dwIns[$e - 2].Operand) -eq $e -and
    $dwIns[$e - 3].OpCode.Name -eq "ceq" -and $dwIns[$e - 4].OpCode.Name -eq "ldc.i4.0" -and $dwIns[$e - 5].OpCode.Name -eq "ldfld" -and "$($dwIns[$e - 5].Operand.Name)" -eq "_allTypes" -and
    $dwIns[$e - 7].OpCode.Name -like "brfalse*" -and [array]::IndexOf($dwIns, $dwIns[$e - 7].Operand) -eq ($e - 1) -and (Get-SourceKey $dw $dwIns ($e - 8)) -eq "loc <- GUI::get_enabled"
if ($shape) { Ok "EntityListWindow.DrawWindow: the List: row's GUI.enabled is 'enabled && !_allTypes' (false when either is)" }
else { Fail "EntityListWindow.DrawWindow: the List: row's GUI.enabled is not exactly 'enabled && !_allTypes'" }

# The title names the list's categories exactly when a category is marked: _appliedListStars == All (0) branches
# (brfalse) to " creatures loaded", and StarSets.Label sits on the other path [S32].
$checks++
$pgm = Get-Method "MobTracker.EntityListWindow" "OnGUI"; $pgi = @($pgm.Body.Instructions)
$ld = @(for ($k = 0; $k -lt $pgi.Count; $k++) { if ($pgi[$k].OpCode.Name -eq "ldstr" -and "$($pgi[$k].Operand)" -eq " creatures loaded") { $k } })
$lb = @(Get-CallAt $pgi "StarSets::Label")
$tt = @(for ($k = 0; $k -lt $pgi.Count - 1; $k++) { $o = $pgi[$k].Operand; if ($pgi[$k].OpCode.Name -eq "ldfld" -and $o -is [Mono.Cecil.FieldReference] -and $o.Name -eq "_appliedListStars" -and $pgi[$k + 1].OpCode.Name -like "br*") { $k } })
if ($ld.Count -eq 1 -and $tt.Count -eq 1 -and $lb.Count -eq 1 -and $pgi[$tt[0] + 1].OpCode.Name -like "brfalse*" -and [array]::IndexOf($pgi, $pgi[$tt[0] + 1].Operand) -eq $ld[0] -and $lb[0] -gt $tt[0] -and $lb[0] -lt $ld[0]) {
    Ok "EntityListWindow.OnGUI: the title says 'creatures loaded' only for _appliedListStars == All, and names the categories otherwise" }
else { Fail "EntityListWindow.OnGUI: the title's test is not '_appliedListStars == All ? creatures loaded : Label(...)'" }

# Each star row's loop runs i from 0 while i < StarButtons.Length, so it draws every button [S33, S34].
$checks++
$why = @()
foreach ($row in @(@("List:", $iList, $iAlerts), @("Alerts:", $iAlerts, $dwIns.Count))) {
    $lo = $row[1]; $hi2 = $row[2]
    $cond = @(for ($k = $lo + 1; $k -lt $hi2 - 3; $k++) { $o = $dwIns[$k].Operand; if ($dwIns[$k].OpCode.Name -eq "ldsfld" -and $o -is [Mono.Cecil.FieldReference] -and $o.Name -eq "StarButtons" -and $dwIns[$k + 1].OpCode.Name -eq "ldlen" -and $dwIns[$k + 2].OpCode.Name -eq "conv.i4" -and $dwIns[$k + 3].OpCode.Name -like "blt*" -and $dwIns[$k - 1].OpCode.Name -like "ldloc*") { $k } })
    if ($cond.Count -ne 1) { $why += "the $($row[0]) row's loop does not run while i < StarButtons.Length"; continue }
    $iv = Get-VarIndex $dwIns[$cond[0] - 1]
    $st = @(for ($k = $lo; $k -lt $cond[0]; $k++) { if ($dwIns[$k].OpCode.Name -like "stloc*" -and (Get-VarIndex $dwIns[$k]) -eq $iv) { $k } })
    $zero = @($st | Where-Object { $dwIns[$_ - 1].OpCode.Name -eq "ldc.i4.0" })
    if ($st.Count -ne 2 -or $zero.Count -ne 1) { $why += "the $($row[0]) row's loop does not start at i = 0" }
}
if ($why.Count -eq 0) { Ok "EntityListWindow.DrawWindow: each star row draws buttons 0 to StarButtons.Length - 1" }
else { Fail ("EntityListWindow.DrawWindow: " + ($why -join "; ")) }

# A sign's text box open answers true: get_activeSelf; brfalse; ldc.i4.1; ret [K38].
$checks++
$pgt = Get-Method "MobTracker.GameTyping" "Any"; $pgti = @($pgt.Body.Instructions)
$pas = @(Get-CallAt $pgti "GameObject::get_activeSelf")
if ($pas.Count -eq 1 -and $pgti[$pas[0] + 1].OpCode.Name -like "brfalse*" -and $pgti[$pas[0] + 2].OpCode.Name -eq "ldc.i4.1" -and $pgti[$pas[0] + 3].OpCode.Name -eq "ret") { Ok "GameTyping.Any: an active text-input panel answers true at once" }
else { Fail "GameTyping.Any: an active text-input panel does not answer true at once" }

# Each clamp keeps its own coordinate: Clamp(_rect.x, ...) into set_x, Clamp(_rect.y, ...) into set_y [G14].
$checks++
$why = @()
foreach ($pair in @(@("Rect::get_x", "Rect::set_x"), @("Rect::get_y", "Rect::set_y"))) {
    $hit = 0
    foreach ($q in @(Get-CallAt $pgi "Mathf::Clamp")) {
        $o = $pgi[$q + 1].Operand
        if (-not ($o -is [Mono.Cecil.MethodReference] -and ($o.DeclaringType.Name + "::" + $o.Name) -eq $pair[1])) { continue }
        $s = Get-ArgumentSources $pgi $q $pgm.Body.ExceptionHandlers
        if ($s -and $s.Count -eq 3 -and (Get-SourceKey $pgm $pgi $s[0]) -eq $pair[0]) { $hit++ }
    }
    if ($hit -ne 1) { $why += ("{0} is not Clamp({1}, ...)" -f $pair[1], $pair[0]) }
}
if ($why.Count -eq 0) { Ok "EntityListWindow.OnGUI: _rect.x = Clamp(_rect.x, ...), _rect.y = Clamp(_rect.y, ...)" }
else { Fail ("EntityListWindow.OnGUI: " + ($why -join "; ")) }

Write-Output "== the log (0.7.0) =="
# MobTracker.log and VerboseLog. LogFile, a listener on BepInEx's log, copies MobTracker's own lines - and the errors of
# its code that reach BepInEx from Unity's log or BepInEx's own source - into BepInEx\MobTracker.log; the verbose lines
# are written by Events, through ModLog.Event, at Info. The listener runs inside every plugin's log call, on its thread,
# with nothing round it: what it may do is pinned here as exact IL shapes, like the ones above - a legitimate rewrite
# fails them and must be re-read against the method's IL (ILSpy or Mono.Cecil), not loosened until they pass.
# Each shape below was read against the C# it compiles from (0.7.0 design, 2026-10-02).
function Get-ShapeText($m) {
    # Get-Shape, with a CR or LF in a string written as \r or \n, and a description (an ldstr of more than 100
    # characters) as 'ldstr <text>': the cfg's wording is not this check's to hold.
    @(Get-Shape $m | ForEach-Object { if ($_ -clike "ldstr *" -and $_.Length -gt 106) { "ldstr <text>" } else { $_.Replace("`r", "\r").Replace("`n", "\n") } })
}
function Get-HandlerText($m) {
    $ins = @($m.Body.Instructions)
    @($m.Body.ExceptionHandlers | ForEach-Object { "{0} {1} {2}..{3} {4}..{5}" -f $_.HandlerType, $(if ($_.CatchType) { $_.CatchType.FullName } else { "-" }),
        [array]::IndexOf($ins, $_.TryStart), [array]::IndexOf($ins, $_.TryEnd), [array]::IndexOf($ins, $_.HandlerStart), [array]::IndexOf($ins, $_.HandlerEnd) })
}
function Test-ExactShape($typeName, $methodName, $want, $what, $handlers = @()) {
    # The whole method, instruction by instruction, and its exception handlers (none unless listed).
    $script:checks++
    $where = "{0}.{1}" -f $typeName.Split('.')[-1], $methodName
    $m = Get-Method $typeName $methodName
    if (-not $m) { Fail "$where not found"; return }
    $why = @()
    $got = @(Get-ShapeText $m)
    if (($got -join "`n") -cne (@($want) -join "`n")) { $why += ("it is not: {0} - it is: {1}" -f (@($want) -join "; "), ($got -join "; ")) }
    $hGot = @(Get-HandlerText $m)
    if (($hGot -join "; ") -cne (@($handlers) -join "; ")) { $why += ("its exception handlers are [{0}], not [{1}]" -f ($hGot -join "; "), (@($handlers) -join "; ")) }
    if ($why.Count -eq 0) { Ok "${where}: $what" } else { Fail ("${where}: " + ($why -join "; ")) }
}
function Get-CallTable($match) {
    # "Caller.Method -> Type::Member xN" for every call (or newobj) of a member whose "Type::Name" matches; a compiler-made
    # nested type is named without its number (<Search>d__N), which changes with unrelated edits.
    $rows = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([StringComparer]::Ordinal)
    foreach ($t in $plug.GetTypes()) {
        foreach ($m in $t.Methods) {
            if (-not $m.HasBody) { continue }
            foreach ($x in $m.Body.Instructions) {
                $o = $x.Operand
                if ($o -isnot [Mono.Cecil.MethodReference] -or -not ($x.OpCode.Name -eq "call" -or $x.OpCode.Name -eq "callvirt" -or $x.OpCode.Name -eq "newobj")) { continue }
                $callee = $o.DeclaringType.Name + "::" + $o.Name
                if ($callee -cnotmatch $match) { continue }
                $k = "{0}.{1} -> {2}" -f ($t.Name -replace '>d__\d+$', '>d__N'), ($m.Name -replace '>b__\d+(_\d+)?$', '>b__N'), $callee
                if ($rows.ContainsKey($k)) { $rows[$k] = $rows[$k] + 1 } else { $rows[$k] = 1 }
            }
        }
    }
    return @($rows.Keys | Sort-Object -CaseSensitive | ForEach-Object { "{0} x{1}" -f $_, $rows[$_] })
}
function Test-Table($got, $want, $ok, $what) {
    $script:checks++
    $g = @($got) -join "; "; $w = @($want) -join "; "
    if ($g -ceq $w) { Ok $ok }
    else {
        # Compare-Object refuses an empty side: with no row at all (a type gone, 0.7.1's ConfigSaver - an empty table comes
        # back from Get-CallTable as $null), every wanted row is missing.
        $rows = @($got | Where-Object { $null -ne $_ })
        $diff = if ($rows.Count -eq 0) { @($want | ForEach-Object { "- " + $_ }) }
                else { @(Compare-Object -CaseSensitive @($want) $rows | ForEach-Object { if ($_.SideIndicator -eq "=>") { "+ " + $_.InputObject } else { "- " + $_.InputObject } }) }
        Fail ("{0} differ from the checked ones: {1}" -f $what, ($diff -join "; "))
    }
}

$Shape_LogFile_Start = @('ldarg.0', 'ldstr Logging', 'ldstr ErrorLog', 'ldc.i4.1', 'ldstr <text>', 'callvirt ConfigFile::Bind', 'stsfld LogFile::ErrorLog', 'ldarg.0',
    'ldstr Logging', 'ldstr VerboseLog', 'ldc.i4.0', 'ldstr <text>', 'callvirt ConfigFile::Bind', 'stsfld LogFile::VerboseLog',
    'ldsfld LogFile::VerboseLog', 'callvirt ConfigEntry`1::get_Value', 'stsfld ModLog::Verbose', 'ldarg.1', 'stsfld LogFile::_folder', 'ldarg.2',
    'stsfld LogFile::_gameFolder', 'call Thread::get_CurrentThread', 'callvirt Thread::get_ManagedThreadId', 'stsfld LogFile::_mainThread',
    'ldsfld LogFile::Clock', 'callvirt Stopwatch::Start', 'ldsfld LogFile::ErrorLog', 'callvirt ConfigEntry`1::get_Value', 'brtrue ->32',
    'ldsfld LogFile::VerboseLog', 'callvirt ConfigEntry`1::get_Value', 'brfalse ->34', 'ldstr at the game''s start', 'call LogFile::Open',
    'ldc.i4.1', 'stsfld LogFile::_binding', 'ldsfld LogFile::ErrorLog', 'ldsfld <>O::<0>__ErrorLogChanged', 'dup', 'brtrue ->46', 'pop', 'ldnull',
    'ldftn LogFile::ErrorLogChanged', 'newobj EventHandler::.ctor', 'dup', 'stsfld <>O::<0>__ErrorLogChanged',
    'callvirt ConfigEntry`1::add_SettingChanged', 'ldsfld LogFile::VerboseLog', 'ldsfld <>O::<1>__VerboseLogChanged', 'dup', 'brtrue ->57', 'pop',
    'ldnull', 'ldftn LogFile::VerboseLogChanged', 'newobj EventHandler::.ctor', 'dup', 'stsfld <>O::<1>__VerboseLogChanged',
    'callvirt ConfigEntry`1::add_SettingChanged', 'ret')
$Shape_LogFile_ErrorLogChanged = @('ldstr ErrorLog', 'ldsfld LogFile::ErrorLog', 'callvirt ConfigEntry`1::get_Value', 'call LogFile::Switched', 'ret')
$Shape_LogFile_VerboseLogChanged = @('ldsfld LogFile::VerboseLog', 'callvirt ConfigEntry`1::get_Value', 'stsfld ModLog::Verbose', 'ldstr VerboseLog', 'ldsfld LogFile::VerboseLog',
    'callvirt ConfigEntry`1::get_Value', 'call LogFile::Switched', 'ret')
$Shape_LogFile_Switched = @('ldarg.1', 'brfalse ->9', 'ldsfld LogFile::_opened', 'brtrue ->9', 'ldstr when ', 'ldarg.0', 'ldstr  was turned on', 'call String::Concat',
    'call LogFile::Open', 'ldsfld MobTrackerPlugin::Log', 'ldarg.0', 'ldarg.1', 'ldsfld LogFile::ErrorLog', 'callvirt ConfigEntry`1::get_Value',
    'ldsfld ModLog::Verbose', 'call EventLines::LoggingSwitch', 'callvirt ManualLogSource::LogMessage', 'ret')
$Shape_LogFile_Open = @('ldnull', 'stloc V0', 'ldnull', 'stloc V1', 'ldsfld LogFile::_folder', 'ldstr MobTracker.log', 'call Path::Combine', 'ldc.i4.4', 'ldc.i4.3',
    'ldc.i4.1', 'newobj FileStream::.ctor', 'stloc V0', 'ldc.i4.1', 'stsfld LogFile::_opened', 'ldnull', 'stloc V2', 'ldloc V0',
    'callvirt Stream::get_Length', 'ldc.i4.0', 'conv.i8', 'ble ->57', 'ldsfld LogFile::_folder', 'ldstr MobTracker-prev.log', 'call Path::Combine',
    'ldc.i4.2', 'ldc.i4.2', 'ldc.i4.1', 'newobj FileStream::.ctor', 'stloc V4', 'ldloc V0', 'ldc.i4.0', 'conv.i8', 'callvirt Stream::set_Position',
    'ldloc V0', 'ldloc V4', 'callvirt Stream::CopyTo', 'leave ->42', 'ldloc V4', 'brfalse ->41', 'ldloc V4', 'callvirt IDisposable::Dispose',
    'endfinally', 'ldloc V0', 'ldc.i4.0', 'conv.i8', 'callvirt Stream::SetLength', 'leave ->57', 'callvirt Exception::GetType',
    'callvirt MemberInfo::get_Name', 'stloc V2', 'ldloc V0', 'ldc.i4.0', 'conv.i8', 'ldc.i4.2', 'callvirt Stream::Seek', 'pop', 'leave ->57',
    'ldc.i4 40', 'call Environment::GetFolderPath', 'stsfld LogFile::_userFolder', 'newobj LogFile::.ctor', 'stloc V1', 'ldloc V1', 'ldloc V0',
    'callvirt Stream::get_Length', 'stfld LogFile::_written', 'ldloc V0', 'ldc.i4.0', 'newobj UTF8Encoding::.ctor', 'newobj StreamWriter::.ctor',
    'stloc V3', 'ldloc V3', 'ldstr \r\n', 'callvirt TextWriter::set_NewLine', 'ldloc V3', 'ldc.i4.1', 'callvirt StreamWriter::set_AutoFlush',
    'ldloc V1', 'ldloc V3', 'stfld LogFile::_writer', 'ldnull', 'stloc V0', 'ldloc V2', 'brfalse ->88', 'ldloc V1', 'ldloc V2',
    'call EventLines::PrevNotWritten', 'callvirt LogFile::WriteFile', 'ldloc V1', ("ldstr " + $ExpectedVersion), 'call LogFile::GameVersion',
    'call LogFile::BepInExVersion', 'ldarg.0', 'call EventLines::Header', 'callvirt LogFile::WriteFile', 'ldloc V1', 'ldsfld LogFile::ErrorLog',
    'callvirt ConfigEntry`1::get_Value', 'ldsfld ModLog::Verbose', 'call EventLines::HeaderSwitches', 'callvirt LogFile::WriteFile', 'ldloc V1',
    'stsfld LogFile::_tee', 'call Logger::get_Listeners', 'ldloc V1', 'callvirt ICollection`1::Add', 'leave ->123', 'stloc V5', 'ldloc V1',
    'brfalse ->112', 'ldloc V1', 'callvirt LogFile::Dispose', 'ldloc V0', 'brfalse ->116', 'ldloc V0', 'call LogFile::CloseQuietly',
    'ldsfld MobTrackerPlugin::Log', 'ldloc V5', 'callvirt Exception::GetType', 'callvirt MemberInfo::get_Name', 'call EventLines::OpenFailed',
    'callvirt ManualLogSource::LogWarning', 'leave ->123', 'ret')
$Handlers_LogFile_Open = @('Finally - 29..37 37..42', 'Catch System.Exception 21..47 47..57', 'Catch System.Exception 4..107 107..123')
$Shape_LogFile_LogEvent = @('ldarg.0', 'ldfld LogFile::_writer', 'brtrue ->4', 'ret', 'nop', 'ldarg.2', 'callvirt LogEventArgs::get_Level', 'stloc V0', 'ldarg.2',
    'callvirt LogEventArgs::get_Source', 'ldsfld MobTrackerPlugin::Log', 'bne.un ->28', 'ldloc V0', 'ldsfld LogFile::ErrorLog',
    'callvirt ConfigEntry`1::get_Value', 'ldsfld ModLog::Verbose', 'call LogRules::ToFile', 'brfalse ->27', 'ldarg.0', 'ldloc V0',
    'ldsfld MobTrackerPlugin::Log', 'callvirt ManualLogSource::get_SourceName', 'ldarg.2', 'callvirt LogEventArgs::get_Data',
    'call LogRules::TextOf', 'call LogRules::Line', 'call LogFile::Write', 'leave ->70', 'ldarg.2', 'callvirt LogEventArgs::get_Source',
    'call LogFile::NameOf', 'stloc V1', 'ldloc V1', 'ldloc V0', 'ldsfld LogFile::ErrorLog', 'callvirt ConfigEntry`1::get_Value', 'brtrue ->39',
    'ldsfld ModLog::Verbose', 'br ->40', 'ldc.i4.1', 'ldsfld LogFile::_binding', 'call LogRules::Foreign', 'stloc V2', 'ldloc V2', 'brtrue ->46',
    'leave ->70', 'ldarg.2', 'callvirt LogEventArgs::get_Data', 'call LogRules::TextOf', 'stloc V3', 'ldloc V2', 'ldc.i4.2', 'bne.un ->58',
    'ldarg.0', 'ldloc V3', 'call LogFile::Ours', 'brtrue ->58', 'leave ->70', 'ldarg.0', 'ldloc V0', 'ldloc V1', 'ldloc V3', 'call LogRules::Line',
    'call LogFile::Write', 'leave ->70', 'stloc V4', 'ldarg.0', 'ldloc V4', 'call LogFile::Broke', 'leave ->70', 'ret')
$Handlers_LogFile_LogEvent = @('Catch System.Exception 5..65 65..70')
$Shape_LogFile_Write = @('ldarg.0', 'ldfld LogFile::_gate', 'stloc V0', 'ldc.i4.0', 'stloc V1', 'ldloc V0', 'ldloca V_1', 'call Monitor::Enter', 'ldarg.0',
    'ldfld LogFile::_writer', 'stloc V2', 'ldloc V2', 'brtrue ->14', 'leave ->76', 'ldc.i4.m1', 'stloc V3', 'call Thread::get_CurrentThread',
    'callvirt Thread::get_ManagedThreadId', 'ldsfld LogFile::_mainThread', 'bne.un ->22', 'call LogHost::Frame', 'stloc V3',
    'call DateTime::get_Now', 'ldloc V3', 'ldarg.1', 'ldsfld LogFile::_gameFolder', 'ldsfld LogFile::_userFolder', 'call LogRules::Scrub',
    'call LogRules::FileLine', 'stloc V4', 'call Encoding::get_UTF8', 'ldloc V4', 'callvirt Encoding::GetByteCount', 'ldc.i4.2', 'add', 'conv.i8',
    'stloc V5', 'ldarg.0', 'ldfld LogFile::_written', 'ldloc V5', 'ldc.i4 5242880', 'conv.i8', 'call LogRules::Fits', 'brtrue ->61', 'ldloc V2',
    'call DateTime::get_Now', 'ldloc V3', 'ldstr [File   :MobTracker] ', 'ldc.i4 5242880', 'conv.i8', 'call EventLines::CapReached',
    'call String::Concat', 'call LogRules::FileLine', 'callvirt TextWriter::WriteLine', 'ldc.i4 5242880', 'conv.i8', 'call EventLines::CapReached',
    'stsfld LogFile::_notice', 'ldarg.0', 'call LogFile::Shut', 'leave ->76', 'ldloc V2', 'ldloc V4', 'callvirt TextWriter::WriteLine', 'ldarg.0',
    'ldarg.0', 'ldfld LogFile::_written', 'ldloc V5', 'add', 'stfld LogFile::_written', 'leave ->76', 'ldloc V1', 'brfalse ->75', 'ldloc V0',
    'call Monitor::Exit', 'endfinally', 'ret')
$Handlers_LogFile_Write = @('Finally - 5..71 71..76')
$Shape_LogFile_Ours = @('ldarg.1', 'call LogRules::NamesMobTracker', 'brtrue ->5', 'ldc.i4.0', 'ret', 'ldarg.0', 'ldfld LogFile::_gate', 'stloc V2', 'ldc.i4.0',
    'stloc V3', 'ldloc V2', 'ldloca V_3', 'call Monitor::Enter', 'ldarg.0', 'ldfld LogFile::_repeats', 'ldarg.1', 'call LogRules::RepeatKey',
    'ldsfld LogFile::Clock', 'callvirt Stopwatch::get_Elapsed', 'stloc V4', 'ldloca V_4', 'call TimeSpan::get_TotalSeconds', 'ldloca V_0',
    'callvirt RepeatLimiter::Write', 'stloc V1', 'leave ->31', 'ldloc V3', 'brfalse ->30', 'ldloc V2', 'call Monitor::Exit', 'endfinally',
    'ldloc V1', 'brfalse ->40', 'ldloc V0', 'ldc.i4.0', 'ble ->40', 'ldarg.0', 'ldloc V0', 'call EventLines::LeftOut', 'call LogFile::WriteFile',
    'ldloc V1', 'ret')
$Handlers_LogFile_Ours = @('Finally - 10..26 26..31')
$Shape_ModLog_Event = @('ldsfld ModLog::Verbose', 'brfalse ->5', 'ldsfld MobTrackerPlugin::Log', 'ldarg.0', 'callvirt ManualLogSource::LogInfo', 'ret')
$Shape_LogObserver_Update = @('call LogFile::ReportNotice', 'ldsfld ModLog::Verbose', 'brtrue ->10', 'ldarg.0', 'ldc.i4.0', 'stfld LogObserver::_known', 'ldarg.0',
    'ldc.i4.m1', 'stfld LogObserver::_generation', 'ret', 'call Events::FlushSettings', 'ldsfld Player::m_localPlayer', 'ldnull',
    'call Object::op_Inequality', 'stloc V0', 'call WatchAlerts::get_EffectiveAlertStars', 'stloc V1', 'ldarg.0', 'ldfld LogObserver::_known',
    'brfalse ->26', 'ldloc V0', 'ldarg.0', 'ldfld LogObserver::_player', 'beq ->26', 'ldloc V0', 'call Events::PlayerPresence', 'ldarg.0',
    'ldfld LogObserver::_known', 'brfalse ->35', 'ldloc V1', 'ldarg.0', 'ldfld LogObserver::_stars', 'beq ->35', 'ldloc V1',
    'call Events::AlertStars', 'ldarg.0', 'ldloc V0', 'stfld LogObserver::_player', 'ldarg.0', 'ldloc V1', 'stfld LogObserver::_stars', 'ldarg.0',
    'ldc.i4.1', 'stfld LogObserver::_known', 'call Tracker::get_IsTracking', 'brtrue ->50', 'ldarg.0', 'ldc.i4.m1',
    'stfld LogObserver::_generation', 'ret', 'call Tracker::get_Generation', 'ldarg.0', 'ldfld LogObserver::_generation', 'beq ->61', 'ldarg.0',
    'call Tracker::get_Generation', 'stfld LogObserver::_generation', 'ldarg.0', 'ldc.i4.2', 'stfld LogObserver::_wait', 'ret', 'ldarg.0',
    'ldfld LogObserver::_wait', 'ldc.i4.0', 'ble ->81', 'ldarg.0', 'ldarg.0', 'ldfld LogObserver::_wait', 'ldc.i4.1', 'sub',
    'stfld LogObserver::_wait', 'ldarg.0', 'ldfld LogObserver::_wait', 'brtrue ->80', 'ldarg.0', 'call Tracker::get_GuideHiddenNow',
    'stfld LogObserver::_guideHidden', 'ldarg.0', 'call Tracker::get_TargetTamed', 'stfld LogObserver::_tamed', 'ret',
    'call Tracker::get_GuideHiddenNow', 'ldarg.0', 'ldfld LogObserver::_guideHidden', 'beq ->91', 'ldarg.0', 'call Tracker::get_GuideHiddenNow',
    'stfld LogObserver::_guideHidden', 'ldarg.0', 'ldfld LogObserver::_guideHidden', 'call Events::Guide', 'call Tracker::get_IsTrackingCreature',
    'brfalse ->104', 'call Tracker::get_TargetTamed', 'ldarg.0', 'ldfld LogObserver::_tamed', 'beq ->104', 'ldarg.0',
    'call Tracker::get_TargetTamed', 'stfld LogObserver::_tamed', 'ldarg.0', 'ldfld LogObserver::_tamed', 'brfalse ->104', 'call Events::Tamed',
    'ret')
$Shape_Events_TrackEnding = @('ldsfld ModLog::Verbose', 'brtrue ->3', 'ret', 'nop', 'call Tracker::get_IsTracking', 'brtrue ->7', 'leave ->44', 'ldarg.0', 'ldnull',
    'call Object::op_Equality', 'brfalse ->15', 'call Tracker::get_Tracked', 'call EventLines::TrackNoPlayer', 'call ModLog::Event', 'leave ->44',
    'call Tracker::get_IsTrackingCreature', 'brtrue ->18', 'leave ->44', 'call Tracker::get_Target', 'stloc V0', 'ldloc V0', 'ldnull',
    'call Object::op_Equality', 'brtrue ->27', 'ldloc V0', 'callvirt Character::IsDead', 'brfalse ->38', 'ldnull', 'stsfld Events::_lastEmptyLook',
    'call Tracker::get_Tracked', 'ldloc V0', 'ldnull', 'call Object::op_Inequality', 'call Tracker::get_TargetTamed',
    'ldsfld ModConfig::AlwaysTrackNearest', 'callvirt ConfigEntry`1::get_Value', 'call EventLines::TrackLost', 'call ModLog::Event', 'leave ->44',
    'stloc V1', 'ldstr LateUpdate', 'ldloc V1', 'call Events::Failed', 'leave ->44', 'ret')
$Handlers_Events_TrackEnding = @('Catch System.Exception 4..39 39..44')
$Shape_Ding_Play = @('ldsfld Ding::_source', 'ldnull', 'call Object::op_Equality', 'brtrue ->6', 'call Ding::Routed', 'brtrue ->11', 'ldsfld Ding::_source',
    'ldnull', 'call Object::op_Equality', 'call Events::DingNotPlayed', 'ret', 'ldsfld Ding::_source', 'ldsfld Ding::_clip',
    'ldsfld ModConfig::AlertVolume', 'callvirt ConfigEntry`1::get_Value', 'callvirt AudioSource::PlayOneShot', 'call Events::DingPlayed', 'ret')
$Shape_Events_Watch = @('ldarg.0', 'stsfld Events::Config', 'ldarg.0', 'ldsfld <>O::<0>__OnSettingChanged', 'dup', 'brtrue ->12', 'pop', 'ldnull',
    'ldftn Events::OnSettingChanged', 'newobj EventHandler`1::.ctor', 'dup', 'stsfld <>O::<0>__OnSettingChanged',
    'callvirt ConfigFile::add_SettingChanged', 'ldsfld ModLog::Verbose', 'brfalse ->17', 'call Events::Snapshot', 'pop', 'ret')
$Shape_Tracker_LogPath = @('ldsfld ModLog::Verbose', 'brfalse ->11', 'ldarg.0', 'ldfld Tracker::_pathState', 'ldarg.0', 'ldfld Tracker::_loggedPathState', 'bne.un ->12',
    'call Tracker::get_Generation', 'ldarg.0', 'ldfld Tracker::_loggedGeneration', 'bne.un ->12', 'ret', 'ldarg.0', 'ldarg.0',
    'ldfld Tracker::_pathState', 'stfld Tracker::_loggedPathState', 'ldarg.0', 'call Tracker::get_Generation', 'stfld Tracker::_loggedGeneration',
    'ldarg.0', 'ldfld Tracker::_pathState', 'ldarg.0', 'ldfld Tracker::_points', 'callvirt List`1::get_Count', 'ldarg.0',
    'ldfld Tracker::_pathShortBy', 'call Events::GroundPath', 'ret')
# Since 0.7.0: LogFile.Bound's catch, and the guards and decisions inside Events - each once-only, on-change
# or on-press guard (a line at most once per creature, per site, per press, per change) and what each hands to EventLines.
$Shape_LogFile_Bound = @('ldc.i4.0', 'stsfld LogFile::_binding', 'ldsfld LogFile::_tee', 'stloc V0', 'ldloc V0', 'brtrue ->7', 'ret', 'nop', 'ldloc V0', 'ldarg.0',
    'call LogFile::Settings', 'call EventLines::Settings', 'callvirt LogFile::WriteFile', 'leave ->19', 'stloc V1', 'ldloc V0', 'ldloc V1',
    'callvirt LogFile::Broke', 'leave ->19', 'ret')
$Handlers_LogFile_Bound = @('Catch System.Exception 8..14 14..19')
$Shape_Events_Failed = @('ldsfld Events::FailedOnce', 'ldarg.0', 'callvirt HashSet`1::Add', 'brfalse ->11', 'ldsfld MobTrackerPlugin::Log', 'ldarg.1',
    'callvirt Exception::GetType', 'callvirt MemberInfo::get_Name', 'ldarg.0', 'call EventLines::VerboseFailed',
    'callvirt ManualLogSource::LogWarning', 'ret')
$Shape_Events_AlertMemoryClearing = @('ldsfld ModLog::Verbose', 'brtrue ->3', 'ret', 'nop', 'ldsfld Events::ToldNotAlerting', 'callvirt HashSet`1::Clear', 'ldarg.0', 'ldc.i4.0',
    'ble ->12', 'ldarg.0', 'call EventLines::AlertMemoryCleared', 'call ModLog::Event', 'leave ->18', 'stloc V0', 'ldstr AlertMemory', 'ldloc V0',
    'call Events::Failed', 'leave ->18', 'ret')
$Handlers_Events_AlertMemoryClearing = @('Catch System.Exception 4..13 13..18')
$Shape_Events_AutoTrack = @('ldsfld ModLog::Verbose', 'brtrue ->3', 'ret', 'nop', 'call Tracker::get_Generation', 'ldsfld Events::_alertGeneration',
    'call Tracker::get_IsTrackingCreature', 'call Tracker::get_Target', 'ldarg.0', 'call Object::op_Equality', 'ldsfld ModConfig::AutoTrack',
    'callvirt ConfigEntry`1::get_Value', 'ldarg.1', 'call EventLines::AutoTrackOutcome', 'call Tracker::get_Tracked',
    'call EventLines::AutoTrack', 'call ModLog::Event', 'leave ->23', 'stloc V0', 'ldstr AutoTrack', 'ldloc V0', 'call Events::Failed',
    'leave ->23', 'ret')
$Handlers_Events_AutoTrack = @('Catch System.Exception 4..18 18..23')
$Shape_Events_NotAlertingEach = @('call Character::GetAllCharacters', 'callvirt List`1::GetEnumerator', 'stloc V0', 'br ->83', 'ldloca V_0', 'call Enumerator::get_Current',
    'stloc V1', 'ldloc V1', 'call Creature::IsListable', 'brfalse ->15', 'ldsfld Events::ToldNotAlerting', 'ldloc V1',
    'callvirt Object::GetInstanceID', 'callvirt HashSet`1::Contains', 'brfalse ->16', 'leave ->83', 'ldloc V1', 'call Creature::PrefabName',
    'stloc V2', 'call ModConfig::get_Watchlist', 'ldloc V2', 'callvirt HashSet`1::Contains', 'brtrue ->24', 'leave ->83', 'ldloc V1',
    'callvirt Character::GetZDOID', 'stloc V3', 'ldloc V3', 'ldsfld ZDOID::None', 'call ZDOID::op_Inequality', 'brfalse ->36', 'ldarg.0',
    'ldloc V3', 'callvirt AlertGate`1::Has', 'brfalse ->36', 'leave ->83', 'ldarg.1', 'ldloc V1', 'callvirt Component::get_transform',
    'callvirt Transform::get_position', 'call Vector3::Distance', 'stloc V4', 'ldloc V3', 'ldsfld ZDOID::None', 'call ZDOID::op_Inequality',
    'ldloc V1', 'callvirt Character::IsTamed', 'call WatchAlerts::get_EffectiveAlertStars', 'ldloc V1', 'callvirt Character::GetLevel',
    'call StarSets::Accepts', 'ldloc V4', 'ldsfld ModConfig::AlertRadius', 'callvirt ConfigEntry`1::get_Value', 'call Rules::WithinRadius',
    'ldc.i4.1', 'call EventLines::TurnedAway', 'stloc V5', 'ldloc V5', 'brtrue ->61', 'leave ->83', 'ldsfld Events::ToldNotAlerting', 'ldloc V1',
    'callvirt Object::GetInstanceID', 'callvirt HashSet`1::Add', 'pop', 'ldloc V1', 'call Creature::DisplayName', 'ldloc V2', 'ldloc V1',
    'callvirt Character::GetLevel', 'ldloc V4', 'ldloc V5', 'call WatchAlerts::get_EffectiveAlertStars', 'call StarSets::Label',
    'call EventLines::NotAlerting', 'call ModLog::Event', 'leave ->83', 'stloc V6', 'ldstr NotAlerting', 'ldloc V6', 'call Events::Failed',
    'leave ->83', 'ldloca V_0', 'call Enumerator::MoveNext', 'brtrue ->4', 'leave ->91', 'ldloca V_0',
    'constrained. System.Collections.Generic.List`1/Enumerator<Character>', 'callvirt IDisposable::Dispose', 'endfinally', 'ret')
$Handlers_Events_NotAlertingEach = @('Catch System.Exception 7..78 78..83', 'Finally - 3..87 87..91')
$Shape_Events_EmptyLookEach = @('ldc.i4.0', 'stloc V0', 'ldc.i4.6', 'newarr System.Int32', 'stloc V1', 'call Character::GetAllCharacters', 'callvirt List`1::GetEnumerator',
    'stloc V2', 'br ->61', 'ldloca V_2', 'call Enumerator::get_Current', 'stloc V3', 'ldloc V3', 'call Creature::IsListable', 'brfalse ->20',
    'call ModConfig::get_Watchlist', 'ldloc V3', 'call Creature::PrefabName', 'callvirt HashSet`1::Contains', 'brtrue ->21', 'leave ->61',
    'ldloc V0', 'ldc.i4.1', 'add', 'stloc V0', 'ldloc V1', 'ldloc V3', 'callvirt Character::GetZDOID', 'ldsfld ZDOID::None',
    'call ZDOID::op_Inequality', 'ldloc V3', 'callvirt Character::IsTamed', 'call WatchAlerts::get_EffectiveAlertStars', 'ldloc V3',
    'callvirt Character::GetLevel', 'call StarSets::Accepts', 'ldarg.0', 'ldloc V3', 'callvirt Component::get_transform',
    'callvirt Transform::get_position', 'call Vector3::Distance', 'ldsfld ModConfig::AlertRadius', 'callvirt ConfigEntry`1::get_Value',
    'call Rules::WithinRadius', 'ldloc V3', 'callvirt Character::InInterior', 'ldarg.1', 'call Rules::SameLayer', 'call EventLines::TurnedAway',
    'ldelema System.Int32', 'dup', 'ldind.i4', 'ldc.i4.1', 'add', 'stind.i4', 'leave ->61', 'stloc V4', 'ldstr EmptyLook', 'ldloc V4',
    'call Events::Failed', 'leave ->61', 'ldloca V_2', 'call Enumerator::MoveNext', 'brtrue ->9', 'leave ->69', 'ldloca V_2',
    'constrained. System.Collections.Generic.List`1/Enumerator<Character>', 'callvirt IDisposable::Dispose', 'endfinally', 'nop', 'ldloc V0',
    'ldloc V1', 'ldc.i4.1', 'ldelem.i4', 'ldloc V1', 'ldc.i4.2', 'ldelem.i4', 'ldloc V1', 'ldc.i4.3', 'ldelem.i4', 'ldloc V1', 'ldc.i4.4',
    'ldelem.i4', 'ldloc V1', 'ldc.i4.5', 'ldelem.i4', 'call EventLines::EmptyLook', 'stloc V5', 'ldloc V5', 'ldsfld Events::_lastEmptyLook',
    'call String::op_Equality', 'brfalse ->93', 'leave ->103', 'ldloc V5', 'stsfld Events::_lastEmptyLook', 'ldloc V5', 'call ModLog::Event',
    'leave ->103', 'stloc V6', 'ldstr EmptyLook', 'ldloc V6', 'call Events::Failed', 'leave ->103', 'ret')
$Handlers_Events_EmptyLookEach = @('Catch System.Exception 12..56 56..61', 'Finally - 8..65 65..69', 'Catch System.Exception 70..98 98..103')
$Shape_Events_ListClosed = @('ldsfld ModLog::Verbose', 'brtrue ->3', 'ret', 'nop', 'ldarg.0', 'brtrue ->12', 'call InventoryGui::IsVisible', 'ldsfld Player::m_localPlayer',
    'ldnull', 'call Object::op_Inequality', 'call EventLines::ClosedUnseen', 'starg cause', 'ldarg.0', 'call EventLines::ListClosed',
    'call ModLog::Event', 'leave ->21', 'stloc V0', 'ldstr Close', 'ldloc V0', 'call Events::Failed', 'leave ->21', 'ret')
$Handlers_Events_ListClosed = @('Catch System.Exception 4..16 16..21')
$Shape_Events_ListKeyCheck = @('ldsfld ModLog::Verbose', 'brtrue ->3', 'ret', 'nop', 'ldsfld ModConfig::ListKey', 'callvirt ConfigEntry`1::get_Value', 'stloc V0', 'ldloc V0',
    'call Hotkeys::TypesText', 'stloc V1', 'call GameTyping::Any', 'stloc V2', 'call Menu::IsVisible', 'stloc V3',
    'call Hud::IsPieceSelectionVisible', 'stloc V4', 'call InventoryGui::IsVisible', 'stloc V5', 'call PlayerCustomizaton::IsBarberGuiVisible',
    'stloc V6', 'ldarg.0', 'ldloc V1', 'ldarg.1', 'ldloc V2', 'ldloc V3', 'ldloc V4', 'ldloc V5', 'ldloc V6', 'call ListKeys::MayToggle',
    'brfalse ->31', 'leave ->59', 'ldsfld ModConfig::ListKey', 'call Hotkeys::Pressed', 'brtrue ->35', 'leave ->59', 'ldloca V_0',
    'constrained. UnityEngine.KeyCode', 'callvirt Object::ToString', 'ldarg.0', 'ldloc V1', 'brfalse ->45', 'ldarg.1', 'ldloc V2', 'or', 'br ->46',
    'ldc.i4.0', 'ldloc V2', 'ldloc V3', 'ldloc V4', 'ldloc V5', 'ldloc V6', 'call EventLines::ListKeyRefused', 'call ModLog::Event', 'leave ->59',
    'stloc V7', 'ldstr HandleKeys', 'ldloc V7', 'call Events::Failed', 'leave ->59', 'ret')
$Handlers_Events_ListKeyCheck = @('Catch System.Exception 4..54 54..59')
$Shape_Events_SettingChanged = @('ldsfld ModLog::Verbose', 'brtrue ->3', 'ret', 'nop', 'ldarg.0', 'brtrue ->7', 'leave ->72', 'ldarg.0',
    'callvirt ConfigEntryBase::get_Definition', 'callvirt ConfigDefinition::get_Section', 'ldstr Logging', 'call String::op_Equality',
    'brfalse ->31', 'ldarg.0', 'callvirt ConfigEntryBase::get_Definition', 'callvirt ConfigDefinition::get_Key', 'ldstr VerboseLog',
    'call String::op_Equality', 'brfalse ->30', 'ldsfld Events::ToldNotAlerting', 'callvirt HashSet`1::Clear', 'ldnull',
    'stsfld Events::_lastEmptyLook', 'call Events::Snapshot', 'stloc V4', 'ldloc V4', 'brfalse ->30', 'ldloc V4', 'call EventLines::Settings',
    'call ModLog::Event', 'leave ->72', 'ldarg.0', 'callvirt ConfigEntryBase::get_Definition', 'callvirt ConfigDefinition::get_Section', 'ldstr .',
    'ldarg.0', 'callvirt ConfigEntryBase::get_Definition', 'callvirt ConfigDefinition::get_Key', 'call String::Concat', 'stloc V0', 'ldarg.0',
    'callvirt ConfigEntryBase::GetSerializedValue', 'stloc V1', 'ldsfld Events::Values', 'ldloc V0', 'ldloca V_2',
    'callvirt Dictionary`2::TryGetValue', 'brtrue ->50', 'ldstr ?', 'stloc V2', 'ldsfld Events::Values', 'ldloc V0', 'ldloc V1',
    'callvirt Dictionary`2::set_Item', 'ldsfld Events::Settler', 'ldloc V0', 'ldloc V2', 'ldloc V1', 'call Time::get_realtimeSinceStartup',
    'conv.r8', 'callvirt SettingSettler::Changed', 'stloc V3', 'ldloc V3', 'brfalse ->66', 'ldloc V3', 'call ModLog::Event', 'leave ->72',
    'stloc V5', 'ldstr SettingChanged', 'ldloc V5', 'call Events::Failed', 'leave ->72', 'ret')
$Handlers_Events_SettingChanged = @('Catch System.Exception 4..67 67..72')

# The two switches, first: LogFile.Start binds Logging.ErrorLog (default true) and Logging.VerboseLog (default false)
# before anything else, takes VerboseLog's value as the flag every verbose site asks, opens the file at the start only
# when one of them is on, takes BepInEx's warnings as MobTracker's (its cfg is being read) from then until Bound, and
# gives each switch its own handler.
Test-ExactShape "MobTracker.LogFile" "Start" $Shape_LogFile_Start "binds Logging.ErrorLog (true) and Logging.VerboseLog (false), VerboseLog's value is the verbose flag, the file opens at the start only when one is on, and each switch has its handler"
Test-ExactShape "MobTracker.LogFile" "ErrorLogChanged" $Shape_LogFile_ErrorLogChanged "ErrorLog's handler tells Switched"
Test-ExactShape "MobTracker.LogFile" "VerboseLogChanged" $Shape_LogFile_VerboseLogChanged "VerboseLog's handler sets the verbose flag from VerboseLog, then tells Switched"
Test-ExactShape "MobTracker.LogFile" "Switched" $Shape_LogFile_Switched "only a switch turned on opens the file, and only if it never was in this game start (a failed open is tried again then, never when a switch is turned off); a Message line says what the file gets now"
# The settings line at the end of the binding window: written in a catch that shuts the file and leaves the notice to
# LogObserver, as LogEvent does - Bound runs in Awake, and a throw out of it would drop the plugin.
Test-ExactShape "MobTracker.LogFile" "Bound" $Shape_LogFile_Bound "ends the binding window, then writes the settings line inside a catch that only hands the failure to Broke" $Handlers_LogFile_Bound

# Who starts and stops it: Awake begins with the log source, then ConfigSaver.Take (0.7.1: BepInEx saves nothing from
# here on - before the first setting is bound, so a read-only cfg cannot throw out of a Bind), LogFile.Start (the folder
# beside LogOutput.log and the game's folder), ModConfig.Bind, LogFile.Bound - so ModConfig.Bind's warnings reach the
# file - then ConfigSaver.Watch (after the last Bind: the first save, and the last handler on the whole cfg); OnDestroy
# starts with ConfigSaver.Stop and ends with LogFile.Stop; the file is opened only by Start and Switched, and only
# those two places touch BepInEx's listeners.
$checks++
$why = @()
$awWant = @("ldarg.0", "call BaseUnityPlugin::get_Logger", "stsfld MobTrackerPlugin::Log", "ldarg.0", "call BaseUnityPlugin::get_Config",
    "call ConfigSaver::Take", "ldarg.0", "call BaseUnityPlugin::get_Config",
    "call Paths::get_BepInExRootPath", "call Paths::get_GameRootPath", "call LogFile::Start", "ldarg.0", "call BaseUnityPlugin::get_Config",
    "call ModConfig::Bind", "ldarg.0", "call BaseUnityPlugin::get_Config", "call LogFile::Bound", "ldarg.0", "call BaseUnityPlugin::get_Config",
    "call ConfigSaver::Watch")
$awGot = if ($awake) { @(Get-Shape $awake | Select-Object -First $awWant.Count) } else { @() }
if (($awGot -join "`n") -cne ($awWant -join "`n")) { $why += ("Awake does not start with: {0} - it starts with: {1}" -f ($awWant -join "; "), ($awGot -join "; ")) }
$odm = Get-Method "MobTracker.MobTrackerPlugin" "OnDestroy"
$odGot = if ($odm) { @(Get-Shape $odm) } else { @() }
if ($odGot.Count -lt 3 -or (@($odGot[($odGot.Count - 3)..($odGot.Count - 1)]) -join "; ") -cne "call Harmony::UnpatchSelf; call LogFile::Stop; ret") { $why += ("OnDestroy does not end with UnpatchSelf, LogFile.Stop: {0}" -f ($odGot -join "; ")) }
if ($odGot.Count -lt 1 -or $odGot[0] -cne "call ConfigSaver::Stop") { $why += ("OnDestroy does not start with ConfigSaver.Stop: {0}" -f ($odGot -join "; ")) }
$lifeWant = @("LogFile.Open -> Logger::get_Listeners x1", "LogFile.Start -> LogFile::Open x1", "LogFile.Stop -> Logger::get_Listeners x1",
    "LogFile.Switched -> LogFile::Open x1", "MobTrackerPlugin.Awake -> LogFile::Bound x1", "MobTrackerPlugin.Awake -> LogFile::Start x1",
    "MobTrackerPlugin.OnDestroy -> LogFile::Stop x1")
$lifeGot = Get-CallTable '^(LogFile::(Start|Bound|Stop|Open)|Logger::get_Listeners)$'
if (($lifeGot -join "; ") -cne ($lifeWant -join "; ")) { $why += ("the calls that start, open and stop the file are [{0}], not [{1}]" -f ($lifeGot -join "; "), ($lifeWant -join "; ")) }
if ($why.Count -eq 0) { Ok "MobTrackerPlugin: Awake turns BepInEx's saving off first (ConfigSaver.Take), then starts the log (LogFile.Start, ModConfig.Bind, LogFile.Bound), then ConfigSaver.Watch; OnDestroy tries a failed save once more first and stops the log last; only Start and Switched open the file" }
else { Fail ("the log's start and stop: " + ($why -join "; ")) }

# Opening the file: MobTracker.log taken first (OpenOrCreate, ReadWrite, sharing Read only - a second copy of the game
# fails here and touches nothing), never again in this game start (_opened right after), its lines copied to
# MobTracker-prev.log (Create, Write, sharing Read) and only then emptied, both in a try that keeps them on failure;
# UTF-8 without a BOM, CRLF, each line flushed; the header; the listener added last; every exception of the open caught
# - one thrown out of Awake would drop the plugin - and said with its type only (an IOException's message holds the
# path). What the catch calls to let the file go has a catch of its own, held below (Shut, Dispose, CloseQuietly).
Test-ExactShape "MobTracker.LogFile" "Open" $Shape_LogFile_Open "takes MobTracker.log first (OpenOrCreate, ReadWrite, FileShare.Read), copies it to MobTracker-prev.log and only then empties it, writes UTF-8 without a BOM, flushed per line, adds the listener last, and catches every failure of the open, said by type only (what its catch calls to let the file go - Dispose, Shut, CloseQuietly - is held to its own shape and catch below)" $Handlers_LogFile_Open
# The file and folder calls are Open's alone, and LogFile never writes an exception's message or stack.
$checks++
$io = @()
foreach ($t in $plug.GetTypes()) {
    foreach ($m in $t.Methods) {
        if (-not $m.HasBody) { continue }
        foreach ($x in $m.Body.Instructions) {
            $o = $x.Operand
            if ($o -isnot [Mono.Cecil.MethodReference]) { continue }
            $dt = $o.DeclaringType.FullName
            $isFile = @("System.IO.File", "System.IO.Directory", "System.IO.FileInfo", "System.IO.DirectoryInfo", "System.IO.FileStream", "System.IO.StreamWriter") -ccontains $dt -or
                ($dt -ceq "System.IO.Stream" -and @("SetLength", "CopyTo") -ccontains $o.Name) -or ($dt -ceq "System.Environment" -and $o.Name -ceq "GetFolderPath")
            if ($isFile -and -not ($t.Name -ceq "LogFile" -and $m.Name -ceq "Open")) { $io += ("{0}.{1} -> {2}::{3}" -f $t.Name, $m.Name, $o.DeclaringType.Name, $o.Name) }
            if ($t.Name -ceq "LogFile" -and $dt -ceq "System.Exception" -and @("get_Message", "ToString", "get_StackTrace") -ccontains $o.Name) { $io += ("LogFile.{0} -> Exception::{1}" -f $m.Name, $o.Name) }
        }
    }
}
if ($io.Count -eq 0) { Ok "only LogFile.Open opens, copies or empties a file or reads a folder; LogFile names an exception by its type only" }
else { Fail ("file calls outside LogFile.Open, or an exception's message in LogFile: " + ($io -join "; ")) }

# The listener: returns at once while the file is shut; MobTracker's own source - by reference, not by name - goes
# through LogRules.ToFile with ErrorLog and the verbose flag; another source only through LogRules.Foreign, and an
# error about MobTracker's code only through Ours (NamesMobTracker, then the repeat limit); all of it in one catch
# whose only work is Broke. Never throws, never logs: below.
Test-ExactShape "MobTracker.LogFile" "LogEvent" $Shape_LogFile_LogEvent "MobTracker's own source (by reference) through LogRules.ToFile, another source only through LogRules.Foreign and Ours, all in one catch that only calls Broke" $Handlers_LogFile_LogEvent
Test-ExactShape "MobTracker.LogFile" "Ours" $Shape_LogFile_Ours "an error is MobTracker's only when NamesMobTracker finds its code in the stack, then the repeat limit decides, under the lock" $Handlers_LogFile_Ours
Test-ExactShape "MobTracker.LogFile" "Write" $Shape_LogFile_Write "under the lock: the date, time and frame (read on the main thread only), the folders scrubbed, the 5 MB cap with its last line and a notice, then the line" $Handlers_LogFile_Write
# Everything LogEvent can reach inside LogFile and its rules: no throw, no rethrow, and no log call of any route - one
# would re-enter this listener, and BepInEx would hand a throw to whichever plugin logged.
$checks++
$why = @()
$seen = @{}
$todo = New-Object System.Collections.Queue
$le = Get-Method "MobTracker.LogFile" "LogEvent"
if ($le) { $todo.Enqueue($le) } else { $why += "LogFile.LogEvent not found" }
while ($todo.Count -gt 0) {
    $m = $todo.Dequeue()
    $key = $m.DeclaringType.Name + "::" + $m.Name
    if ($seen.ContainsKey($key)) { continue }
    $seen[$key] = $true
    foreach ($x in $m.Body.Instructions) {
        if ($x.OpCode.Name -eq "throw" -or $x.OpCode.Name -eq "rethrow") { $why += ("{0} has a {1}" -f $key, $x.OpCode.Name) }
        $o = $x.Operand
        if ($o -isnot [Mono.Cecil.MethodReference]) { continue }
        $callee = $o.DeclaringType.Name + "::" + $o.Name
        if ($callee -cmatch '^(ManualLogSource::Log|ModLog::|Events::|Logger::|UnityLogWriter::|Debug::)') { $why += ("{0} calls {1}" -f $key, $callee) }
        if (@("LogFile", "LogRules", "RepeatLimiter", "EventLines") -ccontains $o.DeclaringType.Name) {
            $d = $null; try { $d = $o.Resolve() } catch { }
            if ($d -and $d.HasBody) { $todo.Enqueue($d) }
        }
    }
}
if ($why.Count -eq 0) { Ok ("LogFile.LogEvent and the {0} methods it reaches in LogFile, LogRules, RepeatLimiter and EventLines neither throw nor log" -f ($seen.Count - 1)) }
else { Fail ("LogFile.LogEvent: " + ($why -join "; ")) }

# One log source: MobTrackerPlugin.Log is BepInEx's own for the plugin, stored once in Awake; no second source (the
# listener filters by reference: a line through another one would miss MobTracker.log).
$checks++
$why = @()
$src2 = Get-CallTable '^(Logger::CreateLogSource|ManualLogSource::\.ctor)$'
if ($src2.Count -gt 0) { $why += ("another log source is made: " + ($src2 -join "; ")) }
$logStores = @(foreach ($t in $plug.GetTypes()) { foreach ($m in $t.Methods) { if ($m.HasBody) { foreach ($x in $m.Body.Instructions) { if ($x.OpCode.Name -eq "stsfld" -and $x.Operand.Name -ceq "Log" -and $x.Operand.DeclaringType.Name -ceq "MobTrackerPlugin") { "{0}.{1}" -f $t.Name, $m.Name } } } } })
if ($logStores.Count -ne 1 -or $logStores[0] -cne "MobTrackerPlugin.Awake") { $why += ("MobTrackerPlugin.Log is stored in: {0}" -f ($logStores -join ", ")) }
if ($why.Count -eq 0) { Ok "one log source: MobTrackerPlugin.Log, stored once in Awake, and no other is made" } else { Fail ("log source: " + ($why -join "; ")) }

# LogRules' level constants are BepInEx's LogLevel values (BepInEx 5.4.23.3): read from the BepInEx.dll in the game.
$checks++
$why = @()
$llType = $null
foreach ($gm in $gameModules.Values) { $tt = $gm.GetType("BepInEx.Logging.LogLevel"); if ($tt) { $llType = $tt; break } }
$lr = $null
foreach ($t in $plug.GetTypes()) { if ($t.FullName -ceq "MobTracker.LogRules") { $lr = $t } }
if (-not $llType -or -not $lr) { $why += "BepInEx.Logging.LogLevel or MobTracker.LogRules not found" }
else {
    foreach ($name in @("Fatal", "Error", "Warning", "Message", "Info", "Debug")) {
        $bf = $llType.Fields | Where-Object { $_.Name -ceq $name } | Select-Object -First 1
        $mf = $lr.Fields | Where-Object { $_.Name -ceq $name } | Select-Object -First 1
        if (-not $bf -or -not $mf -or -not $mf.HasConstant -or [int]$bf.Constant -ne [int]$mf.Constant) { $why += ("{0}: BepInEx {1}, LogRules {2}" -f $name, $(if ($bf) { $bf.Constant } else { "none" }), $(if ($mf) { $mf.Constant } else { "none" })) }
    }
}
if ($why.Count -eq 0) { Ok "LogRules' Fatal, Error, Warning, Message, Info and Debug are BepInEx's LogLevel values" } else { Fail ("LogRules levels: " + ($why -join "; ")) }

# Every log line by level: the verbose route is ModLog.Event alone - Info, and nothing while VerboseLog is off - called
# only by Events; LogMessage only for the switches' notes; LogDebug nowhere (BepInEx's default disk levels leave it out
# of LogOutput.log); every other line is one of the 0.6.0 lines or one of the log's own warnings. A new line anywhere,
# at any level, is a row more here.
Test-ExactShape "MobTracker.ModLog" "Event" $Shape_ModLog_Event "a verbose line is Info, written only while VerboseLog is on"
$mlWant = @("ConfigSaver.Save -> ManualLogSource::LogInfo x1", "ConfigSaver.Save -> ManualLogSource::LogWarning x1",
    "Ding.Routed -> ManualLogSource::LogInfo x1", "Ding.Routed -> ManualLogSource::LogWarning x1", "Events.Failed -> ManualLogSource::LogWarning x1",
    "Hotkeys.Refuse -> ManualLogSource::LogWarning x1", "LogFile.Open -> ManualLogSource::LogWarning x1", "LogFile.ReportNotice -> ManualLogSource::LogWarning x1",
    "LogFile.Switched -> ManualLogSource::LogMessage x1", "MobTrackerPlugin.Awake -> ManualLogSource::LogInfo x1", "MobTrackerPlugin.Patch -> ManualLogSource::LogError x1",
    "MobTrackerPlugin.Start -> ManualLogSource::LogError x1", "ModConfig.ParseStars -> ManualLogSource::LogWarning x1", "ModConfig.ResetSession -> ManualLogSource::LogInfo x1",
    "ModLog.Event -> ManualLogSource::LogInfo x1", "NearestWatched.Cancel -> ManualLogSource::LogInfo x1",
    "NearestWatched.Lost -> ManualLogSource::LogInfo x1", "NearestWatched.Update -> ManualLogSource::LogInfo x2", "SpawnFinder.Report -> ManualLogSource::LogInfo x3",
    "Tracker.Awake -> ManualLogSource::LogError x1", "WatchAlerts.Update -> ManualLogSource::LogWarning x1", "WaypointerCompat.ApplyTo -> ManualLogSource::LogError x1",
    "WaypointerCompat.ApplyTo -> ManualLogSource::LogInfo x1", "WaypointerCompat.ApplyTo -> ManualLogSource::LogWarning x1")
Test-Table (Get-CallTable '^ManualLogSource::Log') $mlWant "every log line is a 0.6.0 line, a warning of the log's own, a switch note (Message), the cfg's save lines (0.7.1) or a verbose line through ModLog.Event (Info); no Debug line" "the log lines by method and level"
$evWant = @(Get-CallTable '^ModLog::Event$' | Where-Object { $_ -cnotlike "Events.*" })
$checks++
if ($evWant.Count -eq 0 -and @(Get-CallTable '^ModLog::Event$').Count -gt 0) { Ok "ModLog.Event is called only from Events" } else { Fail ("ModLog.Event is called from outside Events: " + ($evWant -join "; ")) }

# Where the verbose lines are written from: this exact list of sites, so none sits in a Harmony patch, an OnGUI, a
# creature helper or anywhere that runs per frame beyond the ones listed (LogObserver writes changes only, and
# HandleKeys' ListKeyCheck writes only on a refused press). With VerboseLog off each returns at once (below).
$siteWant = @("<Search>d__N.MoveNext -> Events::FindDone x1", "Ding.FindGuiGroup -> Events::DingGroupSearchFailed x1", "Ding.Play -> Events::DingNotPlayed x1",
    "Ding.Play -> Events::DingPlayed x1", "EntityListWindow.Close -> Events::ListClosed x1", "EntityListWindow.DrawWindow -> Events::Clicked x2",
    "EntityListWindow.DrawWindow -> Events::RowClicked x3", "EntityListWindow.DrawWindow -> Events::ViewSwitched x1", "EntityListWindow.HandleKeys -> Events::ListKeyCheck x1",
    "EntityListWindow.Open -> Events::ListOpened x1", "LogObserver.Update -> Events::AlertStars x1", "LogObserver.Update -> Events::FlushSettings x1",
    "LogObserver.Update -> Events::Guide x1", "LogObserver.Update -> Events::PlayerPresence x1", "LogObserver.Update -> Events::Tamed x1",
    "MobTrackerPlugin.Patch -> Events::Patched x1", "ModConfig.Bind -> Events::Watch x1", "NearestWatched.Update -> Events::EmptyLook x1",
    "SpawnFinder.RemovePinNear -> Events::MapDeleteTookAreaPin x1", "SpawnFinder.RemovePins -> Events::PinsRemoved x1", "SpawnFinder.Say -> Events::FindSays x1",
    "SpawnFinder.StartFind -> Events::FindNotStarted x1", "SpawnFinder.StartFind -> Events::FindReplaced x1", "Tracker.LateUpdate -> Events::TrackEnding x1",
    "Tracker.LateUpdate -> Events::TrackReached x1", "Tracker.LogPath -> Events::GroundPath x1", "Tracker.Stop -> Events::TrackStopping x1",
    "Tracker.Track -> Events::TrackStarting x1", "Tracker.TrackPoint -> Events::TrackStartingArea x1", "WatchAlerts.ResetSession -> Events::Session x1",
    "WatchAlerts.Update -> Events::Alert x1", "WatchAlerts.Update -> Events::AlertMemoryClearing x1", "WatchAlerts.Update -> Events::AutoTrack x1",
    "WatchAlerts.Update -> Events::NotAlerting x1", "WaypointerCompat.Apply -> Events::CompatSkipped x1")
Test-Table (Get-CallTable '^Events::' | Where-Object { $_ -cnotlike "Events.*" }) $siteWant "the verbose lines are written from these sites only" "the verbose sites"
# Placement within three of them: the alert poll's lines after its once-a-second return; the loss line before the
# lost block (which must stay its exact shape); each of the window's clicks in the true branch of its button - IMGUI
# enters it on the click alone, outside it the line would be written at every GUI event.
$checks++
$why = @()
$wa = Get-Method "MobTracker.WatchAlerts" "Update"
if ($wa) {
    $wsh = @(Get-Shape $wa)
    $firstRet = [array]::IndexOf($wsh, "ret")
    $evAt = @(for ($k = 0; $k -lt $wsh.Count; $k++) { if ($wsh[$k] -clike "call Events::*") { $k } })
    if ($evAt.Count -eq 0 -or @($evAt | Where-Object { $_ -lt $firstRet }).Count -gt 0) { $why += "WatchAlerts.Update calls Events before its once-a-second return" }
}
$lu2 = Get-Method "MobTracker.Tracker" "LateUpdate"
if ($lu2) {
    $lsh = @(Get-Shape $lu2)
    $te = [array]::IndexOf($lsh, "call Events::TrackEnding"); $it = [array]::IndexOf($lsh, "call Tracker::get_IsTracking")
    if ($te -lt 0 -or $it -lt 0 -or $te -gt $it) { $why += "Tracker.LateUpdate does not call Events.TrackEnding before its first IsTracking test" }
}
$dw2 = Get-Method "MobTracker.EntityListWindow" "DrawWindow"
if ($dw2) {
    $di = @($dw2.Body.Instructions)
    for ($k = 0; $k -lt $di.Count; $k++) {
        $o = $di[$k].Operand
        if ($o -isnot [Mono.Cecil.MethodReference] -or $o.DeclaringType.Name -cne "Events") { continue }
        $b = -1
        for ($s = $k - 1; $s -ge 0; $s--) { $p = $di[$s].Operand; if ($p -is [Mono.Cecil.MethodReference] -and $p.DeclaringType.Name -ceq "GUILayout" -and $p.Name -ceq "Button") { $b = $s; break } }
        $inBranch = $b -ge 0 -and $di[$b + 1].OpCode.Name -like "brfalse*" -and [array]::IndexOf($di, $di[$b + 1].Operand) -gt $k
        if (-not $inBranch) { $why += ("DrawWindow's Events.{0} at {1} is not in the true branch of a GUILayout.Button" -f $o.Name, $k) }
    }
}
# And every site hands over values it already holds - with VerboseLog off nothing is put together: no text joined or
# formatted, no creature's name worked out, in the argument list of an Events call (read back to the end of the
# statement before it).
foreach ($t in $plug.GetTypes()) {
    if ($t.FullName -ceq "MobTracker.Events") { continue }
    foreach ($m in $t.Methods) {
        if (-not $m.HasBody) { continue }
        $xi = @($m.Body.Instructions)
        for ($k = 0; $k -lt $xi.Count; $k++) {
            $o = $xi[$k].Operand
            if ($o -isnot [Mono.Cecil.MethodReference] -or $o.DeclaringType.Name -cne "Events") { continue }
            for ($s = $k - 1; $s -ge 0; $s--) {
                $pi = $xi[$s]
                $po = $pi.Operand
                $void = "$($pi.OpCode.StackBehaviourPush)" -eq "Varpush" -and $po -is [Mono.Cecil.MethodReference] -and $pi.OpCode.Name -ne "newobj" -and $po.ReturnType.FullName -ceq "System.Void"
                if ($void -or "$($pi.OpCode.StackBehaviourPush)" -eq "Push0" -or "$($pi.OpCode.FlowControl)" -match 'Branch|Return|Throw') { break }
                if ($po -is [Mono.Cecil.MethodReference] -and (($po.DeclaringType.Name + "::" + $po.Name) -cmatch '^(String::(Concat|Format|Join)|Creature::(DisplayName|PrefabName)|Object::ToString|EventLines::)')) {
                    $why += ("{0}.{1} builds Events.{2}'s argument ({3}::{4}) whether VerboseLog is on or not" -f $t.Name, $m.Name, $o.Name, $po.DeclaringType.Name, $po.Name)
                }
            }
        }
    }
}
if ($why.Count -eq 0) { Ok "verbose sites: the alert poll's after its once-a-second return, the loss line before the lost block, each window click inside its button's branch; each hands over plain values" }
else { Fail ("verbose sites: " + ($why -join "; ")) }

# Each verbose method returns first thing while VerboseLog is off - nothing is read or put together - and does the rest
# inside a catch of its own that only says so once (Events.Failed): a verbose line can never stop or change what it
# describes. Events throws nothing.
$checks++
$why = @()
$evType = $null
foreach ($t in $plug.GetTypes()) { if ($t.FullName -ceq "MobTracker.Events") { $evType = $t } }
if (-not $evType) { $why += "MobTracker.Events not found" }
else {
    $guarded = 0
    foreach ($m in $evType.Methods) {
        if (-not $m.HasBody -or -not $m.IsPublic -or $m.Name -ceq "Watch") { continue }
        $guarded++
        $sh = @(Get-Shape $m); $ins = @($m.Body.Instructions)
        if ($sh.Count -lt 5 -or (@($sh[0..3]) -join "; ") -cne "ldsfld ModLog::Verbose; brtrue ->3; ret; nop") { $why += ("Events.{0} does not start with 'if (!ModLog.Verbose) return;'" -f $m.Name); continue }
        $hs = @($m.Body.ExceptionHandlers)
        $outer = @($hs | Where-Object { "$($_.HandlerType)" -eq "Catch" -and $_.CatchType.FullName -ceq "System.Exception" -and [array]::IndexOf($ins, $_.TryStart) -eq 4 -and [array]::IndexOf($ins, $_.HandlerEnd) -eq ($ins.Count - 1) })
        if ($outer.Count -ne 1) { $why += ("Events.{0}: its body is not inside one catch (System.Exception) up to its return" -f $m.Name); continue }
        $h0 = [array]::IndexOf($ins, $outer[0].HandlerStart)
        $hBody = @($sh[$h0..($ins.Count - 2)])
        if ($hBody.Count -ne 5 -or $hBody[0] -cnotlike "stloc V*" -or $hBody[1] -cnotlike "ldstr *" -or $hBody[2] -cnotlike "ldloc V*" -or $hBody[3] -cne "call Events::Failed" -or $hBody[4] -cnotlike "leave ->*") { $why += ("Events.{0}: its catch does more than Events.Failed: {1}" -f $m.Name, ($hBody -join "; ")) }
    }
    foreach ($m in $evType.Methods) { if ($m.HasBody) { foreach ($x in $m.Body.Instructions) { if ($x.OpCode.Name -eq "throw" -or $x.OpCode.Name -eq "rethrow") { $why += ("Events.{0} has a {1}" -f $m.Name, $x.OpCode.Name) } } } }
    if ($guarded -lt 30) { $why += "only $guarded public Events methods found" }
}
if ($why.Count -eq 0) { Ok ("every one of the {0} verbose methods of Events returns first while VerboseLog is off and does the rest in a catch that only says so once; Events throws nothing" -f $guarded) }
else { Fail ("Events: " + ($why -join "; ")) }

# Verbose changes nothing: Events, LogObserver and Tracker.LogPath only read what they describe - no alert gate
# answered or cleared, no setting written, no tracking, re-track, list, pin, message or ding started or ended, no key
# read but ListKey through Hotkeys.Pressed in ListKeyCheck (which can refuse an unreadable key a press earlier than
# HandleKeys would, with the same warning) - and they store only their own fields.
$checks++
$why = @()
$forbidden = '^(AlertGate`1::(ShouldAlert|Clear)|ConfigEntry`1::set_Value|ConfigEntryBase::(set_BoxedValue|SetSerializedValue)|ConfigFile::(Save|Reload|set_SaveOnConfigSet)|ConfigSaver::|Tracker::(Track|TrackPoint|Stop)|NearestWatched::(Cancel|Lost)|Retrack::|EntityListWindow::(Open|Close)|ModConfig::(ToggleWatch|ResetSession|Bind)|SpawnFinder::(Find|Clear|StartFind|RemovePins|RemovePinNear)|Minimap::|MessageHud::|Ding::|Hotkeys::(Forget|Refuse)|StarSetSettler::|WatchAlerts::ResetSession|ZInput::|Object::Destroy|GameObject::SetActive|Renderer::set_enabled)'
$bodies = @()
foreach ($t in $plug.GetTypes()) {
    if ($t.FullName -ceq "MobTracker.Events" -or $t.FullName -clike "MobTracker.Events/*" -or $t.FullName -ceq "MobTracker.LogObserver") { $bodies += @($t.Methods | Where-Object { $_.HasBody }) }
    if ($t.FullName -ceq "MobTracker.Tracker") { $bodies += @($t.Methods | Where-Object { $_.HasBody -and $_.Name -ceq "LogPath" }) }
}
foreach ($m in $bodies) {
    $own = $m.DeclaringType.Name
    foreach ($x in $m.Body.Instructions) {
        $o = $x.Operand
        if ($o -is [Mono.Cecil.MethodReference]) {
            $callee = $o.DeclaringType.Name + "::" + $o.Name
            if ($callee -cmatch $forbidden) { $why += ("{0}.{1} calls {2}" -f $own, $m.Name, $callee) }
            if ($callee -ceq "Hotkeys::Pressed" -and -not ($own -ceq "Events" -and $m.Name -ceq "ListKeyCheck")) { $why += ("{0}.{1} reads a key" -f $own, $m.Name) }
        }
        if (($x.OpCode.Name -eq "stsfld" -or $x.OpCode.Name -eq "stfld") -and $o -is [Mono.Cecil.FieldReference]) {
            $fOwner = $o.DeclaringType.Name
            $okStore = ($own -ceq "Events" -and $fOwner -ceq "Events") -or ($own -ceq "LogObserver" -and $fOwner -ceq "LogObserver") -or ($own -clike "<>*") -or ($fOwner -clike "<>*") -or ($own -ceq "Tracker" -and @("_loggedPathState", "_loggedGeneration") -ccontains $o.Name)
            if (-not $okStore) { $why += ("{0}.{1} stores {2}::{3}" -f $own, $m.Name, $fOwner, $o.Name) }
        }
    }
}
if ($bodies.Count -lt 30) { $why += "only $($bodies.Count) verbose method bodies found" }
if ($why.Count -eq 0) { Ok ("the {0} verbose methods (Events, LogObserver, Tracker.LogPath) change nothing they describe and store only their own fields" -f $bodies.Count) }
else { Fail ("verbose changes something: " + ($why -join "; ")) }

# The loss line asks the lost block's own question - tracking a creature, its Target destroyed or dead - after the
# no-player one, and clears the empty-look memory for the wait that may follow.
Test-ExactShape "MobTracker.Events" "TrackEnding" $Shape_Events_TrackEnding "no local player, or the tracked creature lost (Target null or dead, as Tracker's lost block asks), each said; nothing else" $Handlers_Events_TrackEnding
# LogObserver: says why the file stopped whatever VerboseLog says, then, with it on, writes each watched state on its
# change only (the guide and tamed state taken as a baseline two frames after each tracking change, not written).
Test-ExactShape "MobTracker.LogObserver" "Update" $Shape_LogObserver_Update "says a stopped file first, whatever VerboseLog says; with it on, the player, the Alerts: stars, the guide and tamed on change only"
# The ding's lines: not played (no source, or no GUI mixer group) right before that return, played right after
# PlayOneShot; the mixer search's caught failure goes to its verbose line and nowhere else.
Test-ExactShape "MobTracker.Ding" "Play" $Shape_Ding_Play "the not-played line before the not-routed return, the played line after PlayOneShot"
$checks++
$fg = Get-Method "MobTracker.Ding" "FindGuiGroup"
$fgH = if ($fg) { @($fg.Body.ExceptionHandlers | Where-Object { "$($_.HandlerType)" -eq "Catch" }) } else { @() }
$fgBody = @()
if ($fgH.Count -eq 1) { $fi = @($fg.Body.Instructions); $fgSh = @(Get-Shape $fg); $fgBody = @($fgSh[([array]::IndexOf($fi, $fgH[0].HandlerStart))..([array]::IndexOf($fi, $fgH[0].HandlerEnd) - 1)]) }
if (($fgBody -join "; ") -clike "call Events::DingGroupSearchFailed; leave ->*") { Ok "Ding.FindGuiGroup: its one catch hands the exception to its verbose line and goes on" }
else { Fail ("Ding.FindGuiGroup: its catch is not 'Events.DingGroupSearchFailed(e)' alone: " + ($fgBody -join "; ")) }
# Every setting's change reaches the verbose log through one handler on the whole cfg, added by Events.Watch as the
# last call of ModConfig.Bind - after every setting's own handler, which therefore runs first.
Test-ExactShape "MobTracker.Events" "Watch" $Shape_Events_Watch "keeps the cfg, adds the one file-wide SettingChanged handler, and takes the values as they are when VerboseLog is on"
$checks++
$why = @()
$bd2 = Get-Method "MobTracker.ModConfig" "Bind"
$bdSh = if ($bd2) { @(Get-Shape $bd2) } else { @() }
if ($bdSh.Count -lt 3 -or $bdSh[$bdSh.Count - 2] -cne "call Events::Watch" -or $bdSh[$bdSh.Count - 3] -cne "ldarg.0") { $why += "ModConfig.Bind does not end with Events.Watch(config)" }
if ($why.Count -eq 0) { Ok "ModConfig.Bind ends with Events.Watch" } else { Fail ("settings' changes: " + ($why -join "; ")) }
# The cfg (0.7.1): who binds, saves and listens to it, and who may turn BepInEx's own saving on or off. BepInEx saves a
# changed setting before it tells anyone, uncaught, so a read-only cfg threw out of the setter and no handler ran: its
# SaveOnConfigSet is turned off once, by ConfigSaver.Take (first in Awake), and the file is saved by ConfigSaver.Save
# alone. Every Bind sits in LogFile.Start or ModConfig.Bind - after Take, before Watch, by Awake's exact start above -
# and the cfg-wide handlers are Events.Watch's and ConfigSaver.Watch's, the saver last. ConfigSaver's own calls: Take
# and Watch from Awake, Stop from OnDestroy, Save from its own three and from the session reset.
$cfgWant = @("ConfigSaver.Save -> ConfigFile::Save x1", "ConfigSaver.Take -> ConfigFile::set_SaveOnConfigSet x1", "ConfigSaver.Watch -> ConfigFile::add_SettingChanged x1",
    "Events.Watch -> ConfigFile::add_SettingChanged x1", "LogFile.Start -> ConfigFile::Bind x2", "ModConfig.Bind -> ConfigFile::Bind x12")
Test-Table (Get-CallTable '^ConfigFile::(Save|Reload|Bind|set_SaveOnConfigSet|add_SettingChanged|remove_SettingChanged)$') $cfgWant "the cfg is bound only in LogFile.Start and ModConfig.Bind, saved only by ConfigSaver.Save, its SaveOnConfigSet set only by ConfigSaver.Take, and listened to by Events.Watch and ConfigSaver.Watch only" "the cfg's calls"
$csWant = @("ConfigSaver.SettingChanged -> ConfigSaver::Save x1", "ConfigSaver.Stop -> ConfigSaver::Save x1", "ConfigSaver.Watch -> ConfigSaver::Save x1",
    "MobTrackerPlugin.Awake -> ConfigSaver::Take x1", "MobTrackerPlugin.Awake -> ConfigSaver::Watch x1", "MobTrackerPlugin.OnDestroy -> ConfigSaver::Stop x1",
    "ModConfig.ResetSession -> ConfigSaver::Save x1")
Test-Table (Get-CallTable '^ConfigSaver::') $csWant "ConfigSaver is taken and watched from Awake, stopped from OnDestroy, and saves from its own handler, its start, its stop and the session reset" "ConfigSaver's callers"
Test-ExactShape "MobTracker.ConfigSaver" "Take" @('ldarg.0', 'stsfld ConfigSaver::_file', 'ldarg.0', 'ldc.i4.0', 'callvirt ConfigFile::set_SaveOnConfigSet', 'ret') "keeps the cfg and turns BepInEx's SaveOnConfigSet off"
Test-ExactShape "MobTracker.ConfigSaver" "Watch" @('ldarg.0', 'ldsfld <>O::<0>__SettingChanged', 'dup', 'brtrue ->10', 'pop', 'ldnull', 'ldftn ConfigSaver::SettingChanged',
    'newobj EventHandler`1::.ctor', 'dup', 'stsfld <>O::<0>__SettingChanged', 'callvirt ConfigFile::add_SettingChanged', "ldstr at the game's start",
    'call ConfigSaver::Save', 'ret') "adds its handler to the whole cfg, then saves once at the game's start"
Test-ExactShape "MobTracker.ConfigSaver" "SettingChanged" @('ldsfld ConfigSaver::Each', 'brfalse ->4', 'ldstr after a change', 'call ConfigSaver::Save', 'ret') "saves after every change, except while ConfigSaver.Each is off (the session reset's writes)"
Test-ExactShape "MobTracker.ConfigSaver" "Stop" @('ldsfld ConfigSaver::_failing', 'brfalse ->4', 'ldstr as the game quits', 'call ConfigSaver::Save', 'ret') "tries once more as the game quits, only when the last save failed"
Test-ExactShape "MobTracker.ConfigSaver" "Save" @('ldsfld ConfigSaver::_file', 'callvirt ConfigFile::Save', 'leave ->16', 'stloc V0', 'ldsfld ConfigSaver::_failing', 'brtrue ->15',
    'ldc.i4.1', 'stsfld ConfigSaver::_failing', 'ldsfld MobTrackerPlugin::Log', 'ldarg.0', 'ldloc V0', 'callvirt Exception::GetType', 'callvirt MemberInfo::get_Name',
    'call EventLines::CfgNotSaved', 'callvirt ManualLogSource::LogWarning', 'leave ->24', 'ldsfld ConfigSaver::_failing', 'brfalse ->24', 'ldc.i4.0',
    'stsfld ConfigSaver::_failing', 'ldsfld MobTrackerPlugin::Log', 'ldarg.0', 'call EventLines::CfgSavedAgain', 'callvirt ManualLogSource::LogInfo', 'ret') "saves inside a catch of every exception: the first failure warned about by its type only, nothing more until a save works again, which is said once" @('Catch System.Exception 0..3 3..16')
Test-ExactShape "MobTracker.ConfigSaver" ".cctor" @('ldc.i4.1', 'stsfld ConfigSaver::Each', 'ret') "saves each change unless told otherwise (Each starts true)"
# The ground path's line: only with VerboseLog on and only when the state or the tracking changed, from LateUpdate
# right after UpdatePath (at most once a second).
Test-ExactShape "MobTracker.Tracker" "LogPath" $Shape_Tracker_LogPath "only with VerboseLog on, only when the path's state or the tracking changed"
$checks++
$lsh2 = if ($lu2) { @(Get-Shape $lu2) } else { @() }
$up = [array]::IndexOf($lsh2, "call Tracker::UpdatePath")
# Inside UpdatePath's once-a-second branch: nothing branches to the LogPath statement, as something would if it stood
# after the branch's end.
$luIns = if ($lu2) { @($lu2.Body.Instructions) } else { @() }
$intoLog = if ($up -ge 0 -and $up + 1 -lt $luIns.Count) { @($luIns | Where-Object { $_.Operand -is [Mono.Cecil.Cil.Instruction] -and [object]::ReferenceEquals($_.Operand, $luIns[$up + 1]) }).Count } else { -1 }
if ($up -ge 0 -and $lsh2[$up + 1] -ceq "ldarg.0" -and $lsh2[$up + 2] -ceq "call Tracker::LogPath" -and $intoLog -eq 0 -and @($lsh2 | Where-Object { $_ -ceq "call Tracker::LogPath" }).Count -eq 1) { Ok "Tracker.LateUpdate calls LogPath once, right after UpdatePath, inside its once-a-second branch" }
else { Fail "Tracker.LateUpdate does not call LogPath once, right after UpdatePath, inside its once-a-second branch" }
# The guards and decisions inside Events, whole: each rate guard - a failure said once per site, the
# not-alerting line once per creature, the empty look's line only when it differs from the last, the refused-key line
# only on a press of ListKey, a setting's burst through the settler, the cleared alert memory only when it held some -
# and what each hands to EventLines, whose decisions (AutoTrackOutcome, TurnedAway, ClosedUnseen) the unit tests pin.
Test-ExactShape "MobTracker.Events" "Failed" $Shape_Events_Failed "a verbose line's failure is warned about once per site (FailedOnce), its words EventLines'"
Test-ExactShape "MobTracker.Events" "AlertMemoryClearing" $Shape_Events_AlertMemoryClearing "forgets the creatures told about, and says the memory is cleared only when it held some" $Handlers_Events_AlertMemoryClearing
Test-ExactShape "MobTracker.Events" "AutoTrack" $Shape_Events_AutoTrack "hands EventLines.AutoTrackOutcome the generation now and at the alert, the creature tracked, whether it is the alerted one, AutoTrack and the dungeon side Auto-track's test read (its second parameter)" $Handlers_Events_AutoTrack
Test-ExactShape "MobTracker.Events" "NotAlertingEach" $Shape_Events_NotAlertingEach "each watched creature without its alert, not told before, once (ToldNotAlerting), with the first reason EventLines.TurnedAway names - the dungeon side never asked - each in its own catch" $Handlers_Events_NotAlertingEach
Test-ExactShape "MobTracker.Events" "EmptyLookEach" $Shape_Events_EmptyLookEach "counts each watched creature by EventLines.TurnedAway's answer, each in its own catch, and writes the line only when it differs from the last look's" $Handlers_Events_EmptyLookEach
Test-ExactShape "MobTracker.Events" "ListClosed" $Shape_Events_ListClosed "a cause no caller named is EventLines.ClosedUnseen's, from the inventory and the local player" $Handlers_Events_ListClosed
Test-ExactShape "MobTracker.Events" "ListKeyCheck" $Shape_Events_ListKeyCheck "says nothing while the list may toggle, and nothing unless ListKey was pressed (Hotkeys.Pressed), then the reasons HandleKeys reads" $Handlers_Events_ListKeyCheck
Test-ExactShape "MobTracker.Events" "SettingChanged" $Shape_Events_SettingChanged "the Logging switches as no Setting line (VerboseLog turned on: the settings and the once-only lines afresh); every other change through the settler, which merges a burst" $Handlers_Events_SettingChanged

# Two guards that sit in the caller, not in Events: the list's close line only past Close's IsOpen test - Update calls
# Close on every frame with no local player - and the reached line only inside the reached block. And the file's failure
# paths, which the walk above (it starts at LogEvent) does not reach: Shut, called from Open's catch in Awake, from
# Broke and from Stop; Stop itself, in OnDestroy; the stop notice said once; Broke; Dispose; CloseQuietly. Exact IL
# shapes, as above: a legitimate rewrite must re-read the IL and rewrite them.
$Shape_EntityListWindow_Close = @('ldnull', 'stsfld EntityListWindow::_pendingWatchToggle', 'ldarg.0', 'ldflda EntityListWindow::_pendingFind',
    'initobj System.Nullable`1<MobTracker.EntityListWindow/Row>', 'call EntityListWindow::get_IsOpen', 'brtrue ->8', 'ret', 'ldc.i4.0',
    'call EntityListWindow::set_IsOpen', 'call Time::get_frameCount', 'stsfld EntityListWindow::_closedFrame', 'ldarg.0', 'ldc.i4.0',
    'stfld EntityListWindow::_focusSearch', 'ldarg.0', 'ldc.i4.0', 'stfld EntityListWindow::_searchFocused', 'ldarg.0',
    'ldfld EntityListWindow::_closeCause', 'call Events::ListClosed', 'ldarg.0', 'ldnull', 'stfld EntityListWindow::_closeCause', 'ret')
$Shape_LogFile_Shut = @('ldarg.0', 'ldfld LogFile::_writer', 'stloc V0', 'ldarg.0', 'ldnull', 'stfld LogFile::_writer', 'ldloc V0', 'brtrue ->9', 'ret', 'nop',
    'ldloc V0', 'callvirt TextWriter::Dispose', 'leave ->15', 'pop', 'leave ->15', 'ret')
$Handlers_LogFile_Shut = @('Catch System.Exception 10..13 13..15')
$Shape_LogFile_Stop = @('ldsfld LogFile::_tee', 'stloc V0', 'ldnull', 'stsfld LogFile::_tee', 'ldloc V0', 'brtrue ->7', 'ret', 'nop', 'call Logger::get_Listeners',
    'ldloc V0', 'callvirt ICollection`1::Remove', 'pop', 'ldloc V0', 'ldloc V0', 'callvirt LogFile::LeftOutInAll', 'call EventLines::Closing',
    'callvirt LogFile::WriteFile', 'leave ->20', 'pop', 'leave ->20', 'ldloc V0', 'callvirt LogFile::Dispose', 'ret')
$Handlers_LogFile_Stop = @('Catch System.Exception 8..18 18..20')
$Shape_LogFile_ReportNotice = @('ldsfld LogFile::_notice', 'stloc V0', 'ldloc V0', 'brtrue ->5', 'ret', 'ldnull', 'stsfld LogFile::_notice', 'ldsfld MobTrackerPlugin::Log',
    'ldloc V0', 'callvirt ManualLogSource::LogWarning', 'ret')
$Shape_LogFile_Dispose = @('ldarg.0', 'ldfld LogFile::_gate', 'stloc V0', 'ldc.i4.0', 'stloc V1', 'ldloc V0', 'ldloca V_1', 'call Monitor::Enter', 'ldarg.0',
    'call LogFile::Shut', 'leave ->16', 'ldloc V1', 'brfalse ->15', 'ldloc V0', 'call Monitor::Exit', 'endfinally', 'ret')
$Handlers_LogFile_Dispose = @('Finally - 5..11 11..16')
$Shape_LogFile_Broke = @('ldsfld LogFile::_notice', 'brtrue ->7', 'ldarg.1', 'callvirt Exception::GetType', 'callvirt MemberInfo::get_Name',
    'call EventLines::WriteFailed', 'stsfld LogFile::_notice', 'ldarg.0', 'call LogFile::Dispose', 'leave ->12', 'pop', 'leave ->12', 'ret')
$Handlers_LogFile_Broke = @('Catch System.Exception 0..10 10..12')
$Shape_LogFile_CloseQuietly = @('ldarg.0', 'callvirt Stream::Dispose', 'leave ->5', 'pop', 'leave ->5', 'ret')
$Handlers_LogFile_CloseQuietly = @('Catch System.Exception 0..3 3..5')
Test-ExactShape "MobTracker.EntityListWindow" "Close" $Shape_EntityListWindow_Close "drops a waiting click first, and writes the close line only past its IsOpen test - at a real close, not on every frame with no local player"
Test-ExactShape "MobTracker.LogFile" "Shut" $Shape_LogFile_Shut "lets the writer go, then disposes it inside a catch - Open's catch (in Awake), Broke and Stop reach it" $Handlers_LogFile_Shut
Test-ExactShape "MobTracker.LogFile" "Stop" $Shape_LogFile_Stop "takes the listener off and writes the closing line inside a catch, then shuts the file" $Handlers_LogFile_Stop
Test-ExactShape "MobTracker.LogFile" "ReportNotice" $Shape_LogFile_ReportNotice "the stop notice is cleared before its warning: said once"
Test-ExactShape "MobTracker.LogFile" "Dispose" $Shape_LogFile_Dispose "Shut under the lock" $Handlers_LogFile_Dispose
Test-ExactShape "MobTracker.LogFile" "Broke" $Shape_LogFile_Broke "keeps the first failure's notice and shuts the file, inside a catch" $Handlers_LogFile_Broke
Test-ExactShape "MobTracker.LogFile" "CloseQuietly" $Shape_LogFile_CloseQuietly "disposes the stream inside a catch" $Handlers_LogFile_CloseQuietly
# The reached line only inside the reached block, right before its Stop: an exact window of LateUpdate ending there,
# branch targets relative to its start, as the Auto-track check does.
$checks++
$why = @()
$rShape = if ($lu2) { @(Get-Shape $lu2) } else { @() }
$trAt = [array]::IndexOf($rShape, "call Events::TrackReached")
$rWant = @("call Tracker::get_IsTracking", "brfalse ->27", "ldsfld Tracker::_isPoint", "brfalse ->27", "ldloc V0", "callvirt Component::get_transform",
    "callvirt Transform::get_position", "ldsfld Tracker::_point", "call Utils::DistanceXZ", "ldc.r4 30", "bge.un ->27", "call MessageHud::get_instance", "ldnull",
    "call Object::op_Inequality", "brfalse ->25", "call MessageHud::get_instance", "ldc.i4.1", "ldstr Reached ", "ldsfld Tracker::_targetName", "call String::Concat",
    "ldc.i4.0", "ldnull", "ldc.i4.0", "ldc.i4.1", "callvirt MessageHud::ShowMessage", "call Events::TrackReached", "call Tracker::Stop")
$rStart = $trAt - 25
if ($trAt -lt 25 -or $rShape.Count -lt $trAt + 2) { $why += "no Events.TrackReached call where the reached block can be" }
else {
    $rGot = @(for ($k = $rStart; $k -le $trAt + 1; $k++) { $line = $rShape[$k]; if ($line -match '^(\S+) ->(\d+)$') { "{0} ->{1}" -f $Matches[1], ([int]$Matches[2] - $rStart) } else { $line } })
    if (($rGot -join "`n") -cne ($rWant -join "`n")) { $why += ("the block that ends in Events.TrackReached and Stop is not: {0} - it is: {1}" -f ($rWant -join "; "), ($rGot -join "; ")) }
}
if ($why.Count -eq 0) { Ok "Tracker.LateUpdate: the reached line only inside the reached block (tracking a point, within 30 m on the flat), after its message and right before its Stop" }
else { Fail ("Tracker.LateUpdate: " + ($why -join "; ")) }

# The alert poll's own guards round its verbose lines: the alert memory's line
# only inside the no-player block, right before the gate is cleared - above the test it would be written every second
# with a player there, and clear the not-alerting memory with it; and, after the not-alerting pass, nothing alerted
# returns at once, so the alert and Auto-track lines come only after that return. Exact windows, branch targets
# relative to their start, as the reached line's check does.
$checks++
$why = @()
$waP = Get-Method "MobTracker.WatchAlerts" "Update"
$wpS = if ($waP) { @(Get-Shape $waP) } else { @() }
$amAt = [array]::IndexOf($wpS, "call Events::AlertMemoryClearing")
$amWant = @('ldsfld Player::m_localPlayer', 'stloc V0', 'ldloc V0', 'ldnull', 'call Object::op_Equality', 'brfalse ->14', 'ldarg.0',
    'ldfld WatchAlerts::_gate', 'callvirt AlertGate`1::get_Count', 'call Events::AlertMemoryClearing', 'ldarg.0', 'ldfld WatchAlerts::_gate',
    'callvirt AlertGate`1::Clear', 'ret')
$amStart = $amAt - 9
if ($amAt -lt 9 -or $wpS.Count -lt $amAt + 5) { $why += "no Events.AlertMemoryClearing call where the no-player block can be" }
else {
    $amGot = @(for ($k = $amStart; $k -le $amAt + 4; $k++) { $line = $wpS[$k]; if ($line -match '^(\S+) ->(\d+)$') { "{0} ->{1}" -f $Matches[1], ([int]$Matches[2] - $amStart) } else { $line } })
    if (($amGot -join "`n") -cne ($amWant -join "`n")) { $why += ("the no-player block is not: {0} - it is: {1}" -f ($amWant -join "; "), ($amGot -join "; ")) }
}
$naAt = [array]::IndexOf($wpS, "call Events::NotAlerting")
$naWant = @('call Events::NotAlerting', 'ldloc V2', 'ldnull', 'call Object::op_Equality', 'brfalse ->6', 'ret')
if ($naAt -lt 0 -or $wpS.Count -lt $naAt + 6) { $why += "no Events.NotAlerting call" }
else {
    $naGot = @(for ($k = $naAt; $k -le $naAt + 5; $k++) { $line = $wpS[$k]; if ($line -match '^(\S+) ->(\d+)$') { "{0} ->{1}" -f $Matches[1], ([int]$Matches[2] - $naAt) } else { $line } })
    if (($naGot -join "`n") -cne ($naWant -join "`n")) { $why += ("the not-alerting pass is not followed by the nothing-alerted return: {0} - it is: {1}" -f ($naWant -join "; "), ($naGot -join "; ")) }
    $early = @(for ($k = 0; $k -le [Math]::Min($naAt + 5, $wpS.Count - 1); $k++) { if (@('call Events::Alert', 'call Events::AutoTrack') -ccontains $wpS[$k]) { "{0} at {1}" -f $wpS[$k], $k } })
    if ($early.Count -gt 0) { $why += ("before the nothing-alerted return: " + ($early -join ", ")) }
}
if ($why.Count -eq 0) { Ok "WatchAlerts.Update: the alert memory's line only in the no-player block, before the gate is cleared; the alert and Auto-track lines only after the nothing-alerted return" }
else { Fail ("WatchAlerts.Update: " + ($why -join "; ")) }
# The settings' snapshot: Events.Watch calls it outside any catch, from ModConfig.Bind in Awake.
$Shape_Events_Snapshot = @('ldnull', 'stloc V0', 'ldsfld Events::Config', 'brtrue ->7', 'ldnull', 'stloc V1', 'leave ->41', 'ldsfld Events::Config',
    'call LogFile::Settings', 'stloc V0', 'ldsfld Events::Values', 'callvirt Dictionary`2::Clear', 'ldloc V0', 'callvirt List`1::GetEnumerator',
    'stloc V2', 'br ->25', 'ldloca V_2', 'call Enumerator::get_Current', 'stloc V3', 'ldsfld Events::Values', 'ldloca V_3',
    'call KeyValuePair`2::get_Key', 'ldloca V_3', 'call KeyValuePair`2::get_Value', 'callvirt Dictionary`2::set_Item', 'ldloca V_2',
    'call Enumerator::MoveNext', 'brtrue ->16', 'leave ->33', 'ldloca V_2',
    'constrained. System.Collections.Generic.List`1/Enumerator<System.Collections.Generic.KeyValuePair`2<System.String,System.String>>',
    'callvirt IDisposable::Dispose', 'endfinally', 'leave ->39', 'stloc V4', 'ldstr Snapshot', 'ldloc V4', 'call Events::Failed', 'leave ->39',
    'ldloc V0', 'ret', 'ldloc V1', 'ret')
$Handlers_Events_Snapshot = @('Finally - 15..29 29..33', 'Catch System.Exception 2..34 34..39')
Test-ExactShape "MobTracker.Events" "Snapshot" $Shape_Events_Snapshot "reads every setting's value inside a catch that only says so once - Events.Watch calls it outside any catch, from ModConfig.Bind in Awake" $Handlers_Events_Snapshot
# Nothing that would put a player, a character, a world or the PC into a log line is read anywhere in the plugin.
$checks++
$priv = '^(Player::(GetPlayerName|GetPlayerID)|Game::GetPlayerProfile|PlayerProfile::|ZNet::(GetWorldName|GetWorld)|World::|ZNetPeer::|ZDOID::(get_UserID|get_ID)|Character::GetHoverName|Tameable::|Environment::(get_UserName|get_MachineName|get_UserDomainName)|Application::get_persistentDataPath|Utils::GetSaveDataPath|SteamFriends::|PlatformManager)'
$privHits = @()
foreach ($t in $plug.GetTypes()) { foreach ($m in $t.Methods) { if ($m.HasBody) { foreach ($x in $m.Body.Instructions) {
    $o = $x.Operand
    if ($o -is [Mono.Cecil.MemberReference] -and $o.DeclaringType -and ($o.DeclaringType.Name + "::" + $o.Name) -cmatch $priv) { $privHits += ("{0}.{1} -> {2}::{3}" -f $t.Name, $m.Name, $o.DeclaringType.Name, $o.Name) } } } } }
if ($privHits.Count -eq 0) { Ok "no player, character, world or PC name, ID or save path is read anywhere (the log lines name creature types and distances)" }
else { Fail ("reads what could put a player, a world or the PC into a log line: " + ($privHits -join "; ")) }

Write-Output "== assembly references =="
foreach ($ar in $plug.AssemblyReferences) {
    if ($ar.Name -eq "mscorlib" -or $ar.Name -eq "System.Core" -or $ar.Name -eq "System" -or $ar.Name -eq "netstandard") { continue }
    $checks++
    if ((Test-Path -LiteralPath (Join-Path $managed ($ar.Name + ".dll"))) -or (Test-Path -LiteralPath (Join-Path $core ($ar.Name + ".dll")))) { Ok $ar.Name }
    else { Fail ("{0} cannot be found in the game folder" -f $ar.Name) }
}

Close-Cecil

Write-Output ""
if ($failures -eq 0) { Write-Output "PREFLIGHT PASSED - $checks checks, 0 failures."; exit 0 }
Write-Output "PREFLIGHT FAILED - $failures of $checks checks failed."
exit 1
