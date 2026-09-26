<#
.SYNOPSIS
  Checks a compiled MobTracker.dll against the shipped game, without launching it.

.DESCRIPTION
  1. identity: BepInPlugin GUID com.mobtracker.plugin, name MobTracker, the expected version
  2. every [HarmonyPatch] target type and method still exists in the game
  3. every type and member the plugin uses in the game, Unity, BepInEx and Harmony resolves with its exact
     signature - including the private members it reaches (the ground-path guide's Pathfinding internals,
     Find area's SpawnSystem.m_instances), which it lists - and a deliberately
     wrong member fails to resolve, so the check cannot pass vacuously
  4. every assembly the plugin references is in the game folder
  Run it after every Valheim update. Exits 1 on any failure.

.EXAMPLE
  .\tools\preflight.ps1                                  # the installed BepInEx\plugins\MobTracker.dll
  .\tools\preflight.ps1 -Plugin build\MobTracker.dll
#>
param(
    [string]$Plugin = "",
    [string]$ExpectedVersion = "0.1.0",
    [string]$ValheimDir = "E:\SteamLibrary\steamapps\common\Valheim"
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

Write-Output "== Harmony patch targets =="
$gameModules = @{}
foreach ($f in @(Get-ChildItem $managed -Filter *.dll) + @(Get-ChildItem $core -Filter *.dll)) { try { $gameModules[$f.Name] = [Mono.Cecil.ModuleDefinition]::ReadModule($f.FullName) } catch { } }
$patches = 0
foreach ($t in $plug.GetTypes()) {
    foreach ($ca in $t.CustomAttributes) {
        if ($ca.AttributeType.Name -ne "HarmonyPatch" -or $ca.ConstructorArguments.Count -lt 2) { continue }
        $patches++; $checks++
        $typeName = "$($ca.ConstructorArguments[0].Value)"; $method = "$($ca.ConstructorArguments[1].Value)"
        $found = $false
        foreach ($m in $gameModules.Values) { $gt = $m.GetType($typeName); if ($gt -and @($gt.Methods | Where-Object { $_.Name -eq $method }).Count -gt 0) { $found = $true; break } }
        if ($found) { Ok ("{0} -> {1}.{2}" -f $t.Name, $typeName, $method) } else { Fail ("{0}: {1}.{2} not found in the game" -f $t.Name, $typeName, $method) }
    }
}
$checks++
if ($patches -ge 1) { Ok "$patches Harmony patch(es) found" } else { Fail "no [HarmonyPatch] found - the scan would be vacuous" }

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
