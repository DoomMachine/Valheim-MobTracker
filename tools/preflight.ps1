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
     the right values and branches on them the right way, and is started only from Tracker.LateUpdate; Find area
     honours the spawn rules' key and event conditions, takes the map's delete gesture for its own pins after other
     mods' prefixes, and adds them local-only (save false, ownerID 0, and no Minimap method that adds pins of its own)
  5. every assembly the plugin references is in the game folder
  Run it after every Valheim update. Exits 1 on any failure.

.EXAMPLE
  .\tools\preflight.ps1                                  # the installed BepInEx\plugins\MobTracker.dll
  .\tools\preflight.ps1 -Plugin build\MobTracker.dll
#>
[CmdletBinding(PositionalBinding = $false)]   # every argument named: a stray one is an error
param(
    [string]$Plugin = "",
    [string]$ExpectedVersion = "0.3.0",
    [string]$ValheimDir = $(if ($env:VALHEIM) { $env:VALHEIM } else { "E:\SteamLibrary\steamapps\common\Valheim" })
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
    # Each row: type, method, the call ("Type::Member", exactly one in the method), where each value it consumes must
    # come from (the instance first; $null = anything; @() = not checked), and the branches that may follow it ($null =
    # not checked).
    foreach ($c in $table) {
        $script:checks++
        $where = "{0}.{1}" -f $c[0].Split('.')[-1], $c[1]
        $m = Get-Method $c[0] $c[1]
        if (-not $m) { Fail ("{0} not found" -f $where); continue }
        $ins = @($m.Body.Instructions)
        $at = @(for ($k = 0; $k -lt $ins.Count; $k++) {
            $op = $ins[$k].Operand
            if (($ins[$k].OpCode.Name -eq "call" -or $ins[$k].OpCode.Name -eq "callvirt") -and $op -is [Mono.Cecil.MethodReference] -and
                ($op.DeclaringType.Name + "::" + $op.Name) -eq $c[2]) { $k }
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
        @("String::Equals", "ZDOID::op_Inequality", "Character::IsTamed", "StarFilters::Accepts", "Rules::WithinRadius"), $brfalse),
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
    }
}
if ($why.Count -eq 0) { Ok "WatchAlerts.Update: the deferral asks about the type of the creature Tracker.Track would take" } else { Fail ("WatchAlerts.Update: " + ($why -join "; ")) }
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
