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
  4. the star filters read the right settings; always-track-nearest-watched gives its tested decisions (Retrack)
     the right values and branches on them the right way, and is started only from Tracker.LateUpdate; neither it
     nor Auto-track takes a creature on the other side of a dungeon entrance; Find area honours the spawn rules' key
     and event conditions, takes the map's delete gesture for its own pins after other mods' prefixes, and adds them
     local-only (save false, ownerID 0, and no Minimap method that adds pins of its own)
  5. a creature with no ZNetView is skipped by every creature loop, and one that throws cannot end the alert poll;
     the window pauses its re-sorting under the pointer, stays on screen and puts GUI.matrix back, as the HUD label
     does; the alert ding plays only through the game's GUI mixer group
  6. the list's input: the TextInput.IsVisible and Chat.HasFocus postfixes report the list open or closed this
     frame and only ever add true, the HasFocus one last; Escape and the gamepad's B are read in Update, not OnGUI,
     and B is consumed; ListKey is read only through Hotkeys (caught, no warning spam, mouse buttons refused) and
     never opens the list while the player types, over the pause menu, the build menu or the inventory; the wheel
     is zeroed last; TomTom's and Wayfinder's typing test sees the real state (and the installed TomTom/Wayfinder,
     or the -Waypointer DLLs, still read the two flags only there); clicks on the list reach no uGUI element under it
  7. every assembly the plugin references is in the game folder
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
    [string]$ExpectedVersion = "0.3.1",
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
if ($bep -and $bep[0] -eq "com.mobtracker.plugin" -and $bep[1] -eq "MobTracker" -and $bep[2] -eq $ExpectedVersion) { Ok ("BepInPlugin {0} / {1} / {2}" -f $bep[0], $bep[1], $bep[2]) }
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
foreach ($t in $plug.Types) { if ($t.Name -eq "MobTrackerPlugin") { $awake = $t.Methods | Where-Object { $_.Name -eq "Awake" -and $_.HasBody } | Select-Object -First 1 } }
$hasLine = $awake -and @($awake.Body.Instructions | Where-Object { $_.OpCode.Name -eq "ldstr" -and "$($_.Operand)" -eq $loadedLine }).Count -gt 0
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
                if ($gm.Name -ne $method) { continue }
                if ($null -ne $want -and (@($gm.Parameters | ForEach-Object { $_.ParameterType.FullName }) -join ",") -ne ($want -join ",")) { continue }
                $target = $gm; break
            }
            if ($target) { break }
        }
        $shown = "{0}.{1}" -f $typeName, $method
        if ($null -ne $want) { $shown += "(" + ($want -join ", ") + ")" }
        if (-not $target) { Fail ("{0}: {1} not found in the game" -f $t.Name, $shown); continue }
        $badParams = @()
        foreach ($pm in $t.Methods | Where-Object { @("Prefix", "Postfix", "Finalizer") -contains $_.Name }) {
            foreach ($p in $pm.Parameters) {
                if ($injected -contains $p.Name -or $p.Name -like "___*") { continue }
                $tp = $target.Parameters | Where-Object { $_.Name -eq $p.Name } | Select-Object -First 1
                $pType = $p.ParameterType.FullName.TrimEnd('&')
                if (-not $tp -or $tp.ParameterType.FullName -ne $pType) { $badParams += ("{0}({1} {2})" -f $pm.Name, $pType, $p.Name) }
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
foreach ($t in $patchClasses) { if ($t.Name -eq "RemoveAreaPinPatch") { $rpPrefix = $t.Methods | Where-Object { $_.Name -eq "Prefix" } | Select-Object -First 1 } }
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
# The list's filter and the alerts' filter are the same type, so crossing them compiles, passes the unit tests
# (which cannot run the game-side code) and would still ship. Read the IL instead: the list refreshes from the
# list's setting only, the alerts from the alerts' setting only, and both ask StarFilters.Accepts.
function Get-Method($typeName, $methodName) {
    foreach ($t in $plug.GetTypes()) { if ($t.FullName -eq $typeName) { return $t.Methods | Where-Object { $_.Name -eq $methodName -and $_.HasBody } | Select-Object -First 1 } }
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
    @("MobTracker.WatchAlerts", "Update", @("ModConfig::AlertStars", "StarFilters::Accepts", "Character::GetLevel"), @("ModConfig::ListStars", "EntityListWindow::_appliedListStars")),
    @("MobTracker.EntityListWindow", "Refresh", @("EntityListWindow::_appliedListStars", "StarFilters::Accepts", "Character::GetLevel"), @("ModConfig::AlertStars")),
    @("MobTracker.EntityListWindow", "Update", @("ModConfig::ListStars", "EntityListWindow::_appliedListStars", "set EntityListWindow::_appliedListStars"), @("ModConfig::AlertStars"))
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
# The two toolbar rows: from the "List:" label to the "Alerts:" label only the list's setting may be touched, from
# there to the end of DrawWindow only the alerts'. Swapping the rows compiles and passes everything else.
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
    $o = @{}
    for ($k = $from; $k -lt $to; $k++) {
        $op = $dwIns[$k].Operand
        if ($op -is [Mono.Cecil.FieldReference] -and $op.DeclaringType.Name -eq "ModConfig" -and $op.Name -like "*Stars") { $o[$op.Name] = $true }
    }
    return $o
}
if ($iList -ge 0 -and $iAlerts -gt $iList) {
    $listRow = Get-StarSettings $iList $iAlerts
    $alertRow = Get-StarSettings $iAlerts $dwIns.Count
    if ($listRow.ContainsKey("ListStars") -and -not $listRow.ContainsKey("AlertStars") -and $alertRow.ContainsKey("AlertStars") -and -not $alertRow.ContainsKey("ListStars")) {
        Ok "EntityListWindow.DrawWindow: the List: row uses ModConfig::ListStars only, the Alerts: row ModConfig::AlertStars only"
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
function Get-ArgumentSources($ins, [int]$callAt, $handlers = $null) {
    # Replays the evaluation stack over the code before a call and returns, for each value the call consumes (the
    # instance first), the index of the instruction that pushed it; $null if it does not add up. A branch or return
    # starts a new statement (compiled C# has an empty stack there); a branch INSIDE the argument list (a ?:
    # operand) leaves too few values, so it returns $null and the check fails. A catch or filter handler starts
    # with the exception object on an otherwise empty stack, which the straight replay never pushed.
    $stack = New-Object System.Collections.ArrayList
    for ($k = 0; $k -lt $callAt; $k++) {
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
        @("String::Equals", "ZDOID::op_Inequality", "Character::IsTamed", "StarFilters::Accepts", "Rules::WithinRadius", "Rules::SameLayer"), $brfalse),
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
    @("MobTracker.NearestWatched", "Update", "StarFilters::Accepts", @("ModConfig::AlertStars.Value", "Character::GetLevel"), $null),
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
        @("ModConfig::ListStars", "EntityListWindow::_appliedListStars")),
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
# A component nobody adds never runs: Awake must add NearestWatched (AddComponent<NearestWatched>).
$checks++
$added = $false
if ($awake) {
    foreach ($i in $awake.Body.Instructions) {
        $op = $i.Operand
        if ($op -is [Mono.Cecil.GenericInstanceMethod] -and $op.Name -eq "AddComponent" -and
            @($op.GenericArguments | Where-Object { $_.FullName -eq "MobTracker.NearestWatched" }).Count -gt 0) { $added = $true }
    }
}
if ($added) { Ok "MobTrackerPlugin.Awake adds the NearestWatched component" } else { Fail "MobTrackerPlugin.Awake never adds NearestWatched" }

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
        "EntityListWindow::_allTypes", "EntityListWindow::_appliedAllTypes", "ModConfig::ListStars", "EntityListWindow::_appliedListStars"), @("ModConfig::AlertStars")),
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
        @("EntityListWindow::get_IsOpen", "Hotkeys::TypesText", "EntityListWindow::_searchFocused", "GameTyping::Any", "Menu::IsVisible", "Hud::IsPieceSelectionVisible", "InventoryGui::IsVisible"), $brfalse),
    @("MobTracker.EntityListWindow", "HandleKeys", "Hotkeys::TypesText", @("ModConfig::ListKey.Value"), $null),
    @("MobTracker.EntityListWindow", "HandleKeys", "Hotkeys::Pressed", @("ModConfig::ListKey"), $brfalse),
    @("MobTracker.EntityListWindow", "Update", "EntityListWindow::HandleKeys", @($null, "loc <- Console::IsVisible", "loc <- EntityListWindow::_consoleWasVisible"), $null),
    @("MobTracker.Hotkeys", "Pressed", "ListKeys::IsClickButton", @($null), $brfalse)
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
            $ite = $wp.Methods | Where-Object { $_.Name -eq "IsTypingElsewhere" -and $_.Parameters.Count -eq 0 } | Select-Object -First 1
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
