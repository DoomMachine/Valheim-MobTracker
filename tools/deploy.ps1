<#
.SYNOPSIS
  Installs a built MobTracker.dll into the game, keeping the one it replaces.

.DESCRIPTION
  Refuses while Valheim is running, when -Dll is not a file that passes tools\preflight.ps1, and when
  BepInEx\plugins\MobTracker.dll is a folder - all before anything is moved. Then moves the installed
  BepInEx\plugins\MobTracker.dll (never deletes it) to <KeepDir>\MobTracker-<its version>-<date>\ - by default the
  repository's own retired\ folder, which git ignores - copies the new DLL in, confirms the installed file's
  SHA-256 equals the build's, and runs tools\preflight.ps1 on the installed file.

  The game folder is -ValheimDir, else the VALHEIM environment variable (as the build uses), else the default.

.EXAMPLE
  .\tools\deploy.ps1                                          # build\MobTracker.dll
  .\tools\deploy.ps1 -KeepDir D:\Backups\MobTracker          # keep the replaced DLL somewhere else
#>
[CmdletBinding(PositionalBinding = $false)]   # every argument named: a stray one is an error
param(
    [string]$Dll = "",       # default: build\MobTracker.dll in this repository (set below)
    [string]$ExpectedVersion = "0.2.0",
    [string]$ValheimDir = $(if ($env:VALHEIM) { $env:VALHEIM } else { "E:\SteamLibrary\steamapps\common\Valheim" }),
    [string]$KeepDir = ""    # default: retired\ in this repository (set below)
)
$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 leaves $PSScriptRoot empty in an advanced script's parameter defaults when the script is
# started with powershell.exe -File; the body always has it.
$repo = Split-Path $PSScriptRoot -Parent
if (-not $Dll) { $Dll = Join-Path $repo "build\MobTracker.dll" }
if (-not $KeepDir) { $KeepDir = Join-Path $repo "retired" }
# Drop a trailing \ (the quoted path handed to preflight.ps1 below would end in \", an escaped quote), and the "
# that powershell.exe -File leaves when a quoted path ending in \ is the last argument (anywhere earlier it
# swallows the arguments after it: leave the \ off).
$ValheimDir = $ValheimDir.TrimEnd('\', '"')
if (Get-Process -Name valheim -ErrorAction SilentlyContinue) { throw "Valheim is running - close the game first." }
if (-not (Test-Path -LiteralPath $Dll -PathType Leaf)) { throw "No built DLL at $Dll (not a file) - run dotnet build first." }
# The file must be the plugin before anything is moved: preflight checks its identity, its version and every
# reference against this game, so a zip or any other file stops here with the installed plugin in place.
# (Continue around the call: under Stop, the child's error output through 2>&1 would end this script with a bare
# NativeCommandError instead of the explanation below.)
# The child is the console PowerShell of this installation, found in $PSHOME rather than on PATH (not the host
# process: inside the ISE that would be another ISE window), and the exit code is cleared first, so a check that
# could not run counts as failed rather than reading an earlier command's 0.
$self = (Join-Path $PSHOME $(if ($PSVersionTable.PSEdition -eq "Core") { "pwsh.exe" } else { "powershell.exe" }))
$global:LASTEXITCODE = $null
$ErrorActionPreference = "Continue"
$pre = & $self -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "preflight.ps1") -Plugin $Dll -ExpectedVersion $ExpectedVersion -ValheimDir $ValheimDir 2>&1 | ForEach-Object { "$_" }
$preCode = $global:LASTEXITCODE
$ErrorActionPreference = "Stop"
if ($preCode -ne 0) { $pre | Write-Output; throw "$Dll does not pass preflight - nothing was installed or moved." }

$target = Join-Path $ValheimDir "BepInEx\plugins\MobTracker.dll"
$newHash = (Get-FileHash -LiteralPath $Dll -Algorithm SHA256).Hash
if (-not $newHash) { throw "Could not hash $Dll." }
# Checked before anything is moved: a folder where the plugin should be is not something to put away blindly.
if (Test-Path -LiteralPath $target -PathType Container) { throw "$target is a folder, not the plugin - look at it and move it away first." }
if (Test-Path -LiteralPath $target) {
    $oldHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    if ($oldHash -eq $newHash) { Write-Output "already installed ($newHash)"; exit 0 }
    $oldVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($target).ProductVersion
    if (-not $oldVersion) { $oldVersion = "unknown" }
    $oldVersion = ($oldVersion -split '\+')[0]
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"   # milliseconds: two installs in one second keep both DLLs
    $keep = Join-Path $KeepDir ("MobTracker-{0}-{1}" -f $oldVersion, $stamp)
    New-Item -ItemType Directory -Force -Path $keep | Out-Null
    Move-Item -LiteralPath $target -Destination (Join-Path $keep "MobTracker.dll")
    [IO.File]::WriteAllText((Join-Path $keep "SHA256.txt"), $oldHash + "  MobTracker.dll`r`n", (New-Object Text.UTF8Encoding $false))
    Write-Output ("moved the installed {0} ({1}) to {2}" -f $oldVersion, $oldHash.Substring(0, 16), $keep)
}
Copy-Item -LiteralPath $Dll -Destination $target
$installedHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
if ($installedHash -ne $newHash) { throw "installed hash $installedHash differs from the build's $newHash" }
Write-Output ("installed {0}  SHA-256 {1}" -f $target, $installedHash)
$global:LASTEXITCODE = $null
& $self -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "preflight.ps1") -Plugin $target -ExpectedVersion $ExpectedVersion -ValheimDir $ValheimDir
exit $global:LASTEXITCODE
