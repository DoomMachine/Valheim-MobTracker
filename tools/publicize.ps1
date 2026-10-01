<#
.SYNOPSIS
  Writes copies of game assemblies with every type, method and field made public, for the compiler only.

.DESCRIPTION
  MobTracker reads a few private game members (the ground-path guide's Pathfinding internals, Find area's
  spawn lists). The C# compiler refuses to bind to private members, so it compiles against these publicized
  copies; at run time the plugin binds to the game's own DLLs, and the assembly-level
  [IgnoresAccessChecksTo(...)] (IgnoresAccessChecksTo.cs) plus SkipVerification (from AllowUnsafeBlocks) let it
  reach them. This does what the BepInEx.AssemblyPublicizer.MSBuild package does, without NuGet.

  The copies go to lib\publicized\ (git-ignored, never shipped - they are the game's code), each with a stamp: the
  SHA-256 of the game DLL it was made from and of this script; a copy is rebuilt when either changes. Mono.Cecil is
  the copy BepInEx ships. Hashing uses .NET's SHA256, not Get-FileHash: a build started from PowerShell 7 hands this
  Windows PowerShell child PowerShell 7's module path, where Get-FileHash (a script function in 5.1) cannot load.

  Skipped on purpose: compiler-generated members (a field-like event's backing field has the event's own
  name, so publishing it would make every use of the event ambiguous).
#>
[CmdletBinding(PositionalBinding = $false)]   # every argument named: a stray one is an error
param(
    [string]$ValheimDir = $(if ($env:VALHEIM) { $env:VALHEIM } else { "E:\SteamLibrary\steamapps\common\Valheim" }),
    [string[]]$Assemblies = @("assembly_valheim", "assembly_utils"),
    [string]$OutDir = ""   # default: lib\publicized in this repository (set below)
)
$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 leaves $PSScriptRoot empty in an advanced script's parameter defaults when the script is
# started with powershell.exe -File, as the build does; the body always has it.
if (-not $OutDir) { $OutDir = Join-Path (Split-Path $PSScriptRoot -Parent) "lib\publicized" }
# Drop a trailing \, and the " that powershell.exe -File leaves when a quoted path ending in
# \ is the last argument (anywhere earlier it swallows the arguments after it: leave the \ off).
$ValheimDir = $ValheimDir.TrimEnd('\', '"')
$managed = Join-Path $ValheimDir "valheim_Data\Managed"
$cecilLoaded = $false

function Get-Sha256([string]$path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($path))).Replace("-", "") }
    finally { $sha.Dispose() }
}
# This script's own hash is part of every stamp, so an edited publicizer rebuilds the copies.
$scriptHash = Get-Sha256 $PSCommandPath

function Test-Generated($member) {
    foreach ($ca in $member.CustomAttributes) {
        if ($ca.AttributeType.FullName -eq "System.Runtime.CompilerServices.CompilerGeneratedAttribute") { return $true }
    }
    return $false
}

function Publicize($type, $counts) {
    if ($type.IsNested) { $type.IsNestedPublic = $true } else { $type.IsPublic = $true }
    $counts.types++
    $eventNames = @{}
    foreach ($e in $type.Events) { $eventNames[$e.Name] = $true }
    foreach ($m in $type.Methods) {
        if (-not $m.IsPublic) { $m.IsPublic = $true; $counts.methods++ }
    }
    foreach ($f in $type.Fields) {
        if ($f.IsPublic -or $eventNames.ContainsKey($f.Name) -or (Test-Generated $f)) { continue }
        $f.IsPublic = $true
        $counts.fields++
    }
    foreach ($n in $type.NestedTypes) { Publicize $n $counts }
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
foreach ($name in $Assemblies) {
    $source = Join-Path $managed ($name + ".dll")
    if (-not (Test-Path -LiteralPath $source)) { throw "$name.dll not found at $source (pass -ValheimDir)" }
    $target = Join-Path $OutDir ($name + ".dll")
    $stamp = Join-Path $OutDir ($name + ".source.sha256")
    $hash = (Get-Sha256 $source) + " " + $scriptHash
    if ((Test-Path -LiteralPath $target) -and (Test-Path -LiteralPath $stamp) -and ([IO.File]::ReadAllText($stamp).Trim() -ceq $hash)) {
        Write-Output "publicized $name.dll is current"
        continue
    }
    if (-not $cecilLoaded) { Add-Type -LiteralPath (Join-Path $ValheimDir "BepInEx\core\Mono.Cecil.dll"); $cecilLoaded = $true }
    $resolver = New-Object Mono.Cecil.DefaultAssemblyResolver
    $resolver.AddSearchDirectory($managed)
    $rp = New-Object Mono.Cecil.ReaderParameters
    $rp.AssemblyResolver = $resolver
    $rp.InMemory = $true
    $module = [Mono.Cecil.ModuleDefinition]::ReadModule($source, $rp)
    $counts = @{ types = 0; methods = 0; fields = 0 }
    foreach ($t in $module.Types) { Publicize $t $counts }
    $module.Write($target)
    [IO.File]::WriteAllText($stamp, $hash, (New-Object Text.UTF8Encoding $false))
    Write-Output ("publicized {0}.dll written: {1} types, {2} methods and {3} fields made public" -f $name, $counts.types, $counts.methods, $counts.fields)
}
