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
     the right values and branches on them the right way, and is started only from Tracker.LateUpdate; neither it
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
     watchlist and the two star filters back to its own default, saving the cfg once afterwards; the watchlist
     entry's own change handler re-parses it; a Watch click still waiting with no player is dropped
  8. every assembly the plugin references is in the game folder
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
    [string]$ExpectedVersion = "0.5.0",
    [string]$ValheimDir = $(if ($env:VALHEIM) { $env:VALHEIM } else { "E:\SteamLibrary\steamapps\common\Valheim" }),
    [string[]]$Waypointer = @()   # TomTom / Wayfinder DLLs to check the carve-out against; default: the installed ones
)
$ErrorActionPreference = "Stop"
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
        if (-not $p -or $p.Name -ne "__runOriginal" -or $ins[$k].OpCode.Name -notlike "ldarg*") { continue }
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
    # The wait ends (a true answer skips no code: the cancel follows) on death, any tracking, the option off, unwatching.
    @("MobTracker.NearestWatched", "Update", "Retrack::EndsWait",
        @("Character::IsDead", "Tracker::get_IsTracking", "ModConfig::AlwaysTrackNearest.Value", 'HashSet`1::Contains'), $brfalse),
    @("MobTracker.NearestWatched", "Update", 'HashSet`1::Contains', @("ModConfig::get_Watchlist", "Retrack::get_Prefab"), $null),
    @("MobTracker.NearestWatched", "Update", "Retrack::ShouldLook", @("NearestWatched::Pending", "Time::get_time"), $brtrue),
    # Which creature: listable first (the null and dead check), then the candidate test, a false answer skipping it.
    @("MobTracker.NearestWatched", "Update", "Creature::IsListable", @($null), $brfalse),
    @("MobTracker.NearestWatched", "Update", "Retrack::IsCandidate",
        @("String::Equals", "ZDOID::op_Inequality", "Character::IsTamed", "StarSets::Accepts", "Rules::WithinRadius", "Rules::SameLayer"), $brfalse),
    # The same side of a dungeon entrance: the loop's creature (the overload without parameters) against the player's
    # side, read once before the loop from the player's position (the Vector3 overload).
    @("MobTracker.NearestWatched", "Update", "Rules::SameLayer", @("Character::InInterior", "loc <- Character::InInterior"), $null),
    @("MobTracker.NearestWatched", "Update", "Character::InInterior()", @("loc <- Enumerator::get_Current"), $null),
    @("MobTracker.NearestWatched", "Update", "Character::InInterior(UnityEngine.Vector3)", @("loc <- Transform::get_position"), $null),
    # Auto-track never crosses a dungeon entrance either (a false answer skips the Track): the alerting creature kept as
    # the nearest, against the player's position read before the loop. Which local the creature is: the deferral check.
    @("MobTracker.WatchAlerts", "Update", "Rules::SameLayer", @("Character::InInterior", "Character::InInterior"), $brfalse),
    @("MobTracker.WatchAlerts", "Update", "Character::InInterior()", @("loc <- loc <- Enumerator::get_Current"), $null),
    @("MobTracker.WatchAlerts", "Update", "Character::InInterior(UnityEngine.Vector3)", @("loc <- Transform::get_position"), $null),
    # Every creature loop asks IsListable first (it skips a creature with no ZNetView, below), a false answer skipping
    # the creature: in WatchAlerts a true answer jumps over the leave out of its per-creature try.
    @("MobTracker.WatchAlerts", "Update", "Creature::IsListable", @("loc <- Enumerator::get_Current"), $brtrue),
    @("MobTracker.EntityListWindow", "Refresh", "Creature::IsListable", @("loc <- Enumerator::get_Current"), $brfalse),
    @("MobTracker.NearestWatched", "Update", "String::Equals", @("Creature::PrefabName", "Retrack::get_Prefab", $null), $null),
    @("MobTracker.NearestWatched", "Update", "ZDOID::op_Inequality", @("Character::GetZDOID", "ZDOID::None"), $null),
    @("MobTracker.NearestWatched", "Update", "StarSets::Accepts", @("WatchAlerts::get_EffectiveAlertStars", "Character::GetLevel"), $null),
    @("MobTracker.NearestWatched", "Update", "Rules::WithinRadius", @("loc <- Vector3::Distance", "ModConfig::AlertRadius.Value"), $null),
    # A watch alert for the type being waited for leaves the choice to the re-track (true skips the auto-track); the
    # window shows Stop tracking while a wait is on (false skips the button only when nothing is tracked either).
    @("MobTracker.WatchAlerts", "Update", "NearestWatched::IsPendingFor", @("Creature::PrefabName"), $brtrue),
    @("MobTracker.EntityListWindow", "DrawWindow", "NearestWatched::get_IsPending", @(), $brfalse),
    # Whose members the code reads (the creature's, not the player's), and what the wrappers forward.
    @("MobTracker.NearestWatched", "Update", "Character::GetZDOID", @("loc <- Enumerator::get_Current"), $null),
    @("MobTracker.NearestWatched", "Update", "Character::IsTamed", @("loc <- Enumerator::get_Current"), $null),
    @("MobTracker.NearestWatched", "Update", "Character::GetLevel", @("loc <- Enumerator::get_Current"), $null),
    @("MobTracker.NearestWatched", "Update", "Creature::PrefabName", @("loc <- Enumerator::get_Current"), $null),
    @("MobTracker.NearestWatched", "Update", "Vector3::Distance", @("loc <- Transform::get_position", "Transform::get_position"), $null),
    @("MobTracker.NearestWatched", "IsPendingFor", "Retrack::IsPendingFor", @("NearestWatched::Pending", "arg prefab"), @("ret")),
    @("MobTracker.NearestWatched", "get_IsPending", "Retrack::get_IsPending", @("NearestWatched::Pending"), @("ret")),
    @("MobTracker.NearestWatched", "Cancel", "Retrack::Cancel", @("NearestWatched::Pending"), @("ret")),
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
    # Standing down for every watched type while waiting would leave an alert for another type silently untracked.
    @("MobTracker.WatchAlerts", "Update", @(), @("NearestWatched::get_IsPending"))
)
# Where the wait's two exits lead, and how the nearest candidate is kept. These two, and the deferral check below,
# are exact IL shapes, and an ldloc is keyed by the store before it in instruction order, not by control flow: a
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
}
if ($why.Count -eq 0) { Ok "NearestWatched.Update: no player, and EndsWait true, both lead straight to Pending.Cancel" } else { Fail ("NearestWatched.Update: " + ($why -join "; ")) }
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
# The deferral asks about the creature Tracker.Track would be given (one level below IsPendingFor's argument).
$checks++
$wau = Get-Method "MobTracker.WatchAlerts" "Update"
$wi = @($wau.Body.Instructions)
$pf = @(Get-CallAt $wi "NearestWatched::IsPendingFor"); $tr = @(Get-CallAt $wi "Tracker::Track")
$why = @()
if ($pf.Count -ne 1 -or $tr.Count -ne 1) { $why += ("IsPendingFor / Track calls: {0} / {1}" -f $pf.Count, $tr.Count) } else {
    $a = Get-ArgumentSources $wi $pf[0] $wau.Body.ExceptionHandlers
    $pn = if ($a) { $a[0] } else { -1 }
    if ($pn -lt 0 -or -not ($wi[$pn].Operand -is [Mono.Cecil.MethodReference] -and $wi[$pn].Operand.Name -eq "PrefabName")) { $why += "IsPendingFor is not given Creature.PrefabName(...)" } else {
        $pa = Get-ArgumentSources $wi $pn $wau.Body.ExceptionHandlers
        $ta = Get-ArgumentSources $wi $tr[0] $wau.Body.ExceptionHandlers
        if (-not $pa -or -not $ta -or $wi[$pa[0]].OpCode.Name -notmatch '^ldloc' -or (Get-VarIndex $wi[$pa[0]]) -ne (Get-VarIndex $wi[$ta[0]])) { $why += "IsPendingFor asks about another creature than the one Tracker.Track is given" }
        # The layer test too: the creature asked Character.InInterior() is the one Tracker.Track is given.
        $ii = @(Get-CallAt $wi "Character::InInterior" | Where-Object { $wi[$_].Operand.Parameters.Count -eq 0 })
        $ia = if ($ii.Count -eq 1) { Get-ArgumentSources $wi $ii[0] $wau.Body.ExceptionHandlers } else { $null }
        if (-not $ia -or -not $ta -or $wi[$ia[0]].OpCode.Name -notmatch '^ldloc' -or (Get-VarIndex $wi[$ia[0]]) -ne (Get-VarIndex $wi[$ta[0]])) { $why += "the dungeon-entrance test asks about another creature than the one Tracker.Track is given" }
    }
}
if ($why.Count -eq 0) { Ok "WatchAlerts.Update: the deferral and the dungeon-entrance test ask about the creature Tracker.Track would take" } else { Fail ("WatchAlerts.Update: " + ($why -join "; ")) }
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
# A component nobody adds never runs: Awake must add NearestWatched and GameSession (AddComponent<T>) to the plugin's
# own object (this.gameObject), which BepInEx keeps across scene loads - on an object of the scene, GameSession would
# go with the first logout.
foreach ($component in @("NearestWatched", "GameSession")) {
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
# the world's Game object. A method's instructions as text, for the exact shapes below: branch targets as indexes,
# locals by number, members as Type::Name, the short forms of opcodes as the long ones.
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
# entries - Watchlist, ListStarFilter, AlertStarFilter - is written once, with its own default, while the cfg's
# SaveOnConfigSet is false (set false before the first write, put back in a finally around the writes), and the file
# is saved once after them, in a try with a catch: BepInEx saves before it runs a setting's change handlers, so a save
# that threw inside a write would leave a parsed view behind its entry for good.
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
    $off = @(for ($k = 1; $k -lt $shape.Count; $k++) { if ($shape[$k] -ceq 'callvirt ConfigFile::set_SaveOnConfigSet' -and (Test-LiteralZero $rsIns ($k - 1))) { $k } })
    $back = @(for ($k = 1; $k -lt $shape.Count; $k++) { if ($shape[$k] -ceq 'callvirt ConfigFile::set_SaveOnConfigSet' -and $shape[$k - 1] -clike "ldloc V*") { $k } })
    $saves = @(for ($k = 0; $k -lt $shape.Count; $k++) { if ($shape[$k] -ceq 'callvirt ConfigFile::Save') { $k } })
    $first = if ($writes.Count) { ($writes | Measure-Object -Minimum).Minimum } else { -1 }
    $last = if ($writes.Count) { ($writes | Measure-Object -Maximum).Maximum } else { -1 }
    $fin = @($rs.Body.ExceptionHandlers | Where-Object { "$($_.HandlerType)" -eq "Finally" -and
        [array]::IndexOf($rsIns, $_.TryStart) -le $first -and [array]::IndexOf($rsIns, $_.TryEnd) -gt $last -and
        $back.Count -eq 1 -and [array]::IndexOf($rsIns, $_.HandlerStart) -le $back[0] -and [array]::IndexOf($rsIns, $_.HandlerEnd) -gt $back[0] })
    $caught = @($rs.Body.ExceptionHandlers | Where-Object { "$($_.HandlerType)" -eq "Catch" -and $saves.Count -eq 1 -and
        [array]::IndexOf($rsIns, $_.TryStart) -le $saves[0] -and [array]::IndexOf($rsIns, $_.TryEnd) -gt $saves[0] })
    if ($off.Count -ne 1 -or $first -lt 0 -or $off[0] -gt $first) { $why += "SaveOnConfigSet is not set false once, before the first write" }
    if ($fin.Count -ne 1) { $why += "SaveOnConfigSet is not put back (from a local) in a finally around the writes" }
    if ($saves.Count -ne 1 -or $saves[0] -lt $last -or $caught.Count -ne 1) { $why += "the cfg is not saved once, after the writes, inside a try with a catch" }
}
if ($why.Count -eq 0) { Ok "ModConfig.ResetSession: returns first when KeepBetweenSessions is on; else writes Watchlist, ListStarFilter and AlertStarFilter each once, with its own default, with SaveOnConfigSet off (put back in a finally), then saves once, catching a failure" }
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
# A Watch click is applied in the next Update while the list is open; one still waiting when the player is gone is
# dropped there (ldnull; stsfld _pendingWatchToggle before the no-player Close), not carried into the next session.
$checks++
$why = @()
$lwUpdate = Get-Method "MobTracker.EntityListWindow" "Update"
if (-not $lwUpdate) { $why += "not found" }
else {
    $ins = @($lwUpdate.Body.Instructions)
    $shape = Get-Shape $lwUpdate
    $close = [array]::IndexOf($shape, "call EntityListWindow::Close")
    if ($close -lt 6) { $why += "no Close call after the player test" }
    else {
        if ($shape[$close - 3] -cne "ldnull" -or $shape[$close - 2] -cne "stsfld EntityListWindow::_pendingWatchToggle" -or $shape[$close - 1] -cne "ldarg.0" -or $shape[$close + 1] -cne "ret") {
            $why += "the first Close is not preceded by _pendingWatchToggle = null and followed by return"
        }
        $eq = $close - 5
        if ($shape[$close - 4] -cnotlike "brfalse ->*" -or $shape[$eq] -cne "call Object::op_Equality") { $why += "the first Close is not in the branch of a == test" }
        else {
            $src = Get-ArgumentSources $ins $eq
            if ($null -eq $src -or (Get-SourceKey $lwUpdate $ins $src[0]) -cne "loc <- Player::m_localPlayer" -or $ins[$src[1]].OpCode.Name -ne "ldnull") { $why += "the == test before the first Close is not Player.m_localPlayer == null" }
        }
    }
}
if ($why.Count -eq 0) { Ok "EntityListWindow.Update: with no local player, a Watch click still waiting is dropped before the list closes" }
else { Fail ("EntityListWindow.Update: " + ($why -join "; ")) }
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

Write-Output "== assembly references =="
foreach ($ar in $plug.AssemblyReferences) {
    if ($ar.Name -eq "mscorlib" -or $ar.Name -eq "System.Core" -or $ar.Name -eq "System" -or $ar.Name -eq "netstandard") { continue }
    $checks++
    if ((Test-Path -LiteralPath (Join-Path $managed ($ar.Name + ".dll"))) -or (Test-Path -LiteralPath (Join-Path $core ($ar.Name + ".dll")))) { Ok $ar.Name }
    else { Fail ("{0} cannot be found in the game folder" -f $ar.Name) }
}

Write-Output ""
if ($failures -eq 0) { Write-Output "PREFLIGHT PASSED - $checks checks, 0 failures."; exit 0 }
Write-Output "PREFLIGHT FAILED - $failures of $checks checks failed."
exit 1
