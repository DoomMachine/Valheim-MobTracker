<#
.SYNOPSIS
  Builds the release zip from a clean checkout: dist\MobTracker-<version>.zip, the same bytes every time.

.DESCRIPTION
  Refuses unless the working tree is clean, so the zip is the commit and nothing else. Builds MobTracker.csproj
  from scratch (Release, with no debug symbols whatever a local .csproj.user says), checks that the DLL's version
  names this commit and that it carries no symbol-file path, and zips three entries in this order: MobTracker.dll
  as built, and README.md and LICENSE exactly as the commit stores them. Every entry carries the commit's time.

  So the same commit gives a byte-identical zip when this runs in Windows PowerShell 5.1 (its .NET Framework does
  the compressing; PowerShell 7 compresses differently, so this script refuses to run there) with the same .NET
  SDK, against the same Valheim and BepInEx files - which is how a release's zip can be checked. It prints the
  zip's SHA-256, writes it beside the zip as <zip>.sha256, and names the SDK, BepInEx and game files it used.

  The game folder is -ValheimDir, else the VALHEIM environment variable, else the default - as for the build.

.EXAMPLE
  .\tools\package.ps1
#>
param(
    [string]$ValheimDir = ""
)
$ErrorActionPreference = "Stop"
if ($PSVersionTable.PSEdition -ne "Desktop") {
    throw "Run this in Windows PowerShell 5.1 (powershell.exe): another PowerShell compresses the zip into different bytes."
}
$repo = Split-Path $PSScriptRoot -Parent
$ValheimDir = $ValheimDir.TrimEnd('\')
$game = if ($ValheimDir) { $ValheimDir } elseif ($env:VALHEIM) { $env:VALHEIM.TrimEnd('\') } else { "E:\SteamLibrary\steamapps\common\Valheim" }

function Git-Bytes([string[]]$arguments) {
    # git's output as raw bytes (PowerShell's own capture would re-encode it as text).
    $psi = New-Object System.Diagnostics.ProcessStartInfo("git")
    $psi.Arguments = "-C `"$repo`" " + ($arguments -join " ")
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $buffer = New-Object System.IO.MemoryStream
    $p.StandardOutput.BaseStream.CopyTo($buffer)
    $errors = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    if ($p.ExitCode -ne 0) { throw "git $($arguments -join ' ') failed: $errors" }
    return ,$buffer.ToArray()
}
function Git-Text([string[]]$arguments) { return [Text.Encoding]::UTF8.GetString((Git-Bytes $arguments)).Trim() }

if (Git-Text @("status", "--porcelain")) { throw "The working tree has changes - commit or stash them; the zip must be exactly a commit." }
$commit = Git-Text @("rev-parse", "HEAD")
$csproj = [IO.File]::ReadAllText((Join-Path $repo "MobTracker.csproj"))
$m = [regex]::Match($csproj, "<Version>([^<]+)</Version>")
if (-not $m.Success) { throw "No <Version> in MobTracker.csproj" }
$version = $m.Groups[1].Value
$seconds = [long](Git-Text @("log", "-1", "--format=%ct", "HEAD"))
$stamp = [DateTimeOffset]::FromUnixTimeSeconds($seconds)   # UTC, so the zip does not depend on the time zone
$tag = ""
try { $tag = Git-Text @("describe", "--exact-match", "--tags", "HEAD") } catch { }
if ($tag -ne "v$version") {
    Write-Warning "HEAD is not the tag v$version, so this zip is not that release's asset - upload only from a clone of the tag."
}

# DebugType=none on the command line: a global property, so an ignored MobTracker.csproj.user cannot turn symbols
# (and the build folder's path) back on.
$build = @("build", (Join-Path $repo "MobTracker.csproj"), "-c", "Release", "--no-incremental", "-nologo", "-v", "q", "-p:DebugType=none")
if ($ValheimDir) { $build += "-p:ValheimDir=$ValheimDir" }
& dotnet @build
if ($LASTEXITCODE -ne 0) { throw "The build failed." }
$dll = Join-Path $repo "build\MobTracker.dll"
$stamped = [Diagnostics.FileVersionInfo]::GetVersionInfo($dll).ProductVersion
if ($stamped -ne "$version+$commit") { throw "The DLL says $stamped, not $version+$commit." }
$dllBytes = [IO.File]::ReadAllBytes($dll)
$ascii = [Text.Encoding]::ASCII.GetString($dllBytes)
if ($ascii.Contains("RSDS") -or $ascii.IndexOf(".pdb", [StringComparison]::OrdinalIgnoreCase) -ge 0) {
    throw "The DLL carries a symbol-file (CodeView) entry or a .pdb name - it would publish a local path."
}

$dist = Join-Path $repo "dist"
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$zip = Join-Path $dist ("MobTracker-{0}.zip" -f $version)
Add-Type -AssemblyName System.IO.Compression
$entries = @(
    @("MobTracker.dll", $dllBytes),
    @("README.md", (Git-Bytes @("cat-file", "blob", "HEAD:README.md"))),
    @("LICENSE", (Git-Bytes @("cat-file", "blob", "HEAD:LICENSE")))
)
$stream = [IO.File]::Open($zip, [IO.FileMode]::Create)
try {
    $archive = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($e in $entries) {
            $entry = $archive.CreateEntry($e[0], [System.IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime = $stamp
            $w = $entry.Open()
            try { $w.Write($e[1], 0, $e[1].Length) } finally { $w.Dispose() }
        }
    } finally { $archive.Dispose() }
} finally { $stream.Dispose() }

$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText($zip + ".sha256", "$hash  MobTracker-$version.zip`n", (New-Object Text.UTF8Encoding $false))
$bepinex = Join-Path $game "BepInEx\core\BepInEx.dll"
$valheim = Join-Path $game "valheim_Data\Managed\assembly_valheim.dll"
Write-Output ("MobTracker {0} ({1})" -f $version, $commit)
Write-Output (".NET SDK {0}; BepInEx {1}; assembly_valheim.dll SHA-256 {2}" -f (& dotnet --version),
    $(if (Test-Path -LiteralPath $bepinex) { [Diagnostics.FileVersionInfo]::GetVersionInfo($bepinex).ProductVersion } else { "?" }),
    $(if (Test-Path -LiteralPath $valheim) { (Get-FileHash -LiteralPath $valheim -Algorithm SHA256).Hash.ToLowerInvariant() } else { "?" }))
Write-Output ("{0}  {1}" -f $hash, $zip)
