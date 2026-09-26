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
  4. the star filters read the right settings; Find area honours the spawn rules' key and event conditions,
     takes the map's delete gesture for its own pins after other mods' prefixes, and adds them local-only
     (save false, ownerID 0, and no Minimap method that adds pins of its own)
  5. every assembly the plugin references is in the game folder
  Run it after every Valheim update. Exits 1 on any failure.

.EXAMPLE
  .\tools\preflight.ps1                                  # the installed BepInEx\plugins\MobTracker.dll
  .\tools\preflight.ps1 -Plugin build\MobTracker.dll
#>
param(
    [string]$Plugin = "",
    [string]$ExpectedVersion = "0.2.0",
    [string]$ValheimDir = $(if ($env:VALHEIM) { $env:VALHEIM } else { "E:\SteamLibrary\steamapps\common\Valheim" })
)
$ErrorActionPreference = "Stop"
$managed = Join-Path $ValheimDir "valheim_Data\Managed"
$core = Join-Path $ValheimDir "BepInEx\core"
if ($Plugin -eq "") { $Plugin = Join-Path $ValheimDir "BepInEx\plugins\MobTracker.dll" }
if (-not (Test-Path $Plugin)) { Write-Output "FAIL  plugin not found: $Plugin"; exit 1 }
Add-Type -Path (Join-Path $core "Mono.Cecil.dll")

$resolver = New-Object Mono.Cecil.DefaultAssemblyResolver
$resolver.AddSearchDirectory($managed)
$resolver.AddSearchDirectory($core)
$rp = New-Object Mono.Cecil.ReaderParameters
$rp.AssemblyResolver = $resolver
$rp.InMemory = $true
$plug = [Mono.Cecil.ModuleDefinition]::ReadModule((Resolve-Path $Plugin).Path, $rp)
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
foreach ($f in @(Get-ChildItem $managed -Filter *.dll) + @(Get-ChildItem $core -Filter *.dll)) { try { $gameModules[$f.Name] = [Mono.Cecil.ModuleDefinition]::ReadModule($f.FullName) } catch { } }
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
foreach ($w in $wiring) {
    $checks++
    $m = Get-Method $w[0] $w[1]
    if (-not $m) { Fail ("{0}.{1} not found" -f $w[0], $w[1]); continue }
    $touches = Get-Touches $m
    $missing = @($w[2] | Where-Object { -not $touches.ContainsKey($_) })
    $wrong = @($w[3] | Where-Object { $touches.ContainsKey($_) })
    if ($missing.Count -eq 0 -and $wrong.Count -eq 0) { Ok ("{0}.{1} uses {2}" -f $w[0].Split('.')[-1], $w[1], ($w[2] -join ", ")) }
    else { Fail ("{0}.{1}: missing {2}; must not use {3}" -f $w[0].Split('.')[-1], $w[1], ($missing -join ", "), ($wrong -join ", ")) }
}
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

Write-Output "== assembly references =="
foreach ($ar in $plug.AssemblyReferences) {
    if ($ar.Name -eq "mscorlib" -or $ar.Name -eq "System.Core" -or $ar.Name -eq "System" -or $ar.Name -eq "netstandard") { continue }
    $checks++
    if ((Test-Path (Join-Path $managed ($ar.Name + ".dll"))) -or (Test-Path (Join-Path $core ($ar.Name + ".dll")))) { Ok $ar.Name }
    else { Fail ("{0} cannot be found in the game folder" -f $ar.Name) }
}

Write-Output ""
if ($failures -eq 0) { Write-Output "PREFLIGHT PASSED - $checks checks, 0 failures."; exit 0 }
Write-Output "PREFLIGHT FAILED - $failures of $checks checks failed."
exit 1
