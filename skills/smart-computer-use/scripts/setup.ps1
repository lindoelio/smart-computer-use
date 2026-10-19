# Install the computer-use CLI into $HOME\.local\bin on Windows.
# Idempotent and quiet. Laya is optional; a failure there does not fail setup.
#Requires -Version 5.1
[CmdletBinding()]
param(
    [Alias('with-laya')]
    [switch]$WithLaya,
    [Alias('help')]
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$MinVersion = @(0, 1, 0)
$RepoUrl = 'https://github.com/lindoelio/computer-use'
$AssetName = 'computer-use-windows-x64.zip'
$InstallDir = Join-Path $HOME '.local\bin'
$BinaryName = 'computer-use.exe'

function Show-Usage {
    @"
Usage: setup.ps1 [-WithLaya] [-Verbose] [-Help]

Install the computer-use CLI into `$HOME\.local\bin.

  -WithLaya   Also run install-laya.sh when bash is available.
  -Verbose    Print progress.
  -Help       Show this help.

Environment:
  COMPUTER_USE_VERSION   Release tag to pin, for example v0.1.0 or 0.1.0.
                         Default: the latest GitHub release.

If computer-use is already on PATH or in `$HOME\.local\bin at an acceptable
version, the download is skipped. Acceptable means >= 0.1.0, or exactly
COMPUTER_USE_VERSION when that variable is set.

The release asset is computer-use-windows-x64.zip with a matching .sha256
file. Checksums are verified with Get-FileHash. On failure the script tries
cargo install computer-use --locked when cargo exists.
"@
}

function Write-Log {
    param([string]$Message)
    if ($VerbosePreference -eq 'Continue') {
        Write-Host $Message
    }
}

function Write-SetupWarning {
    param([string]$Message)
    Write-Warning "smart-computer-use: $Message"
}

function ConvertTo-VersionTriple {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }
    $line = ($Text -split "`n")[0].Trim()
    if ($line -match '(\d+)\.(\d+)\.(\d+)') {
        return @([int]$Matches[1], [int]$Matches[2], [int]$Matches[3])
    }
    return $null
}

function Test-VersionAtLeast {
    param($Got, $Want)
    for ($i = 0; $i -lt 3; $i++) {
        if ($Got[$i] -gt $Want[$i]) { return $true }
        if ($Got[$i] -lt $Want[$i]) { return $false }
    }
    return $true
}

function Test-VersionAcceptable {
    param($Got)
    if ($null -eq $Got) { return $false }
    if ($env:COMPUTER_USE_VERSION) {
        $want = ConvertTo-VersionTriple $env:COMPUTER_USE_VERSION
        if ($null -eq $want) { return $false }
        return ($Got[0] -eq $want[0] -and $Got[1] -eq $want[1] -and $Got[2] -eq $want[2])
    }
    return (Test-VersionAtLeast $Got $MinVersion)
}

function Get-ComputerUseCommand {
    $commands = @(Get-Command computer-use -ErrorAction SilentlyContinue)
    if ($commands.Count -eq 0) {
        $commands = @(Get-Command computer-use.exe -ErrorAction SilentlyContinue)
    }
    foreach ($cmd in $commands) {
        if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source)) {
            return $cmd.Source
        }
    }
    $candidates = @(
        (Join-Path $InstallDir $BinaryName),
        (Join-Path $InstallDir 'computer-use'),
        (Join-Path $HOME '.cargo\bin\computer-use.exe'),
        (Join-Path $HOME '.cargo\bin\computer-use')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }
    return $null
}

function Get-InstalledVersion {
    param([string]$Path)
    try {
        $output = & $Path --version 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        return (ConvertTo-VersionTriple (($output | Select-Object -First 1) -as [string]))
    } catch {
        return $null
    }
}

function Get-ReleaseBase {
    $tag = $env:COMPUTER_USE_VERSION
    if ([string]::IsNullOrWhiteSpace($tag)) {
        return "$RepoUrl/releases/latest/download"
    }
    if ($tag -notmatch '^v') {
        $tag = "v$tag"
    }
    return "$RepoUrl/releases/download/$tag"
}

function Get-ExpectedHash {
    param([string]$SumFile)
    $text = Get-Content -LiteralPath $SumFile -Raw
    $match = [regex]::Match($text, '[A-Fa-f0-9]{64}')
    if (-not $match.Success) {
        throw "checksum file has no sha256"
    }
    return $match.Value.ToLowerInvariant()
}

function Install-ReleaseZip {
    param([string]$WorkRoot)
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    } catch {
        Write-Log "could not set TLS 1.2 explicitly; continuing"
    }
    $base = Get-ReleaseBase
    $archive = Join-Path $WorkRoot $AssetName
    $sumFile = Join-Path $WorkRoot "$AssetName.sha256"
    Write-Log "downloading $base/$AssetName"
    Invoke-WebRequest -Uri "$base/$AssetName" -OutFile $archive -UseBasicParsing
    Invoke-WebRequest -Uri "$base/$AssetName.sha256" -OutFile $sumFile -UseBasicParsing
    $expected = Get-ExpectedHash $sumFile
    $actual = (Get-FileHash -Algorithm SHA256 -Path $archive).Hash.ToLowerInvariant()
    if ($actual -ne $expected) {
        throw "sha256 mismatch for $AssetName"
    }
    $extract = Join-Path $WorkRoot 'extract'
    New-Item -ItemType Directory -Force -Path $extract | Out-Null
    Expand-Archive -LiteralPath $archive -DestinationPath $extract
    $exe = Get-ChildItem -LiteralPath $extract -Recurse -Filter $BinaryName | Select-Object -First 1
    if (-not $exe) {
        throw "archive did not contain $BinaryName"
    }
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    $dest = Join-Path $InstallDir $BinaryName
    Copy-Item -LiteralPath $exe.FullName -Destination $dest -Force
    Unblock-File -LiteralPath $dest
    return $dest
}

function Install-WithCargo {
    $cargo = Get-Command cargo -ErrorAction SilentlyContinue
    if (-not $cargo) { return $false }
    $cargoArgs = @('install', 'computer-use', '--locked')
    if ($env:COMPUTER_USE_VERSION) {
        $ver = ConvertTo-VersionTriple $env:COMPUTER_USE_VERSION
        if ($null -eq $ver) {
            Write-SetupWarning "COMPUTER_USE_VERSION is not major.minor.patch"
            return $false
        }
        $cargoArgs += @('--version', ('{0}.{1}.{2}' -f $ver[0], $ver[1], $ver[2]))
    }
    Write-Log ("running cargo " + ($cargoArgs -join ' '))
    & cargo @cargoArgs
    return ($LASTEXITCODE -eq 0)
}

function Show-ManualInstall {
    Write-SetupWarning @"
Could not install the computer-use CLI.
Download computer-use-windows-x64.zip from ${RepoUrl}/releases and verify the matching .sha256 file.
Or, with Rust 1.81 or newer: cargo install computer-use --locked
Put computer-use.exe on PATH, for example $InstallDir.
"@
}

function Test-DirOnPath {
    param([string]$Dir)
    $parts = $env:PATH -split ';'
    foreach ($part in $parts) {
        if ($part.TrimEnd('\') -ieq $Dir.TrimEnd('\')) {
            return $true
        }
    }
    return $false
}

function Invoke-LayaInstaller {
    $bash = Get-Command bash -ErrorAction SilentlyContinue
    $script = Join-Path $PSScriptRoot 'install-laya.sh'
    if (-not $bash -or -not (Test-Path -LiteralPath $script)) {
        Write-SetupWarning "Laya is optional and experimental. install-laya.sh needs bash; skipping it."
        return
    }
    & bash $script --yes
    if ($LASTEXITCODE -ne 0) {
        Write-SetupWarning "Laya install did not succeed; continuing without it."
    }
}

function Invoke-DependencyCheck {
    $bash = Get-Command bash -ErrorAction SilentlyContinue
    $script = Join-Path $PSScriptRoot 'check-deps.sh'
    if ($bash -and (Test-Path -LiteralPath $script)) {
        & bash $script
        return
    }
    $found = Get-ComputerUseCommand
    if ($found) {
        Write-Host "cli: present — $found"
    } else {
        Write-Host "cli: missing — computer-use.exe was not found on PATH or in $InstallDir"
    }
    Write-Host "session: run computer-use in an interactive desktop session, not Session 0."
}

if ($Help) {
    Show-Usage
    exit 0
}

$needInstall = $true
$existing = Get-ComputerUseCommand
if ($existing) {
    $current = Get-InstalledVersion $existing
    if (Test-VersionAcceptable $current) {
        Write-Log "computer-use already installed at $existing"
        $needInstall = $false
    } else {
        Write-Log "computer-use at $existing is not an acceptable version; reinstalling"
    }
}

$status = 0
if ($needInstall) {
    $work = Join-Path ([System.IO.Path]::GetTempPath()) ("smart-computer-use-" + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $installed = $false
    try {
        try {
            Install-ReleaseZip $work | Out-Null
            $installed = $true
        } catch {
            Write-SetupWarning "release download or checksum failed; trying cargo install computer-use --locked"
            Write-Log $_.Exception.Message
        }
        if (-not $installed) {
            if (Install-WithCargo) {
                $installed = $true
            }
        }
    } finally {
        if (Test-Path -LiteralPath $work) {
            Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    if (-not $installed) {
        Show-ManualInstall
        $status = 1
    } else {
        Write-Host "installed computer-use into $InstallDir or cargo bin"
    }
}

$resolved = Get-ComputerUseCommand
if ($resolved) {
    $dir = Split-Path -Parent $resolved
    if (-not (Test-DirOnPath $dir)) {
        Write-SetupWarning "$dir is not on PATH. Add it to the user PATH."
    }
    $resolvedVersion = Get-InstalledVersion $resolved
    if (-not (Test-VersionAcceptable $resolvedVersion)) {
        Write-SetupWarning "computer-use at $resolved is still not an acceptable version"
        $status = 1
    }
} else {
    $status = 1
}

if ($WithLaya) {
    Invoke-LayaInstaller
}
Invoke-DependencyCheck
exit $status
