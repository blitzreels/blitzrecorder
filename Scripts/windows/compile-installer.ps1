param(
    [Parameter(Mandatory = $true)][string]$OutputName,
    [string]$OutputDir = "dist",
    [string]$AppVersion = "0.0.0"
)

$ErrorActionPreference = "Stop"

function ConvertTo-InnoVersion([string]$version) {
    if ($version -match '^(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:\.(\d+))?') {
        $major = $Matches[1]
        $minor = if ($Matches[2]) { $Matches[2] } else { "0" }
        $patch = if ($Matches[3]) { $Matches[3] } else { "0" }
        $build = if ($Matches[4]) { $Matches[4] } else { "0" }
        return "$major.$minor.$patch.$build"
    }
    return "0.0.0.0"
}

function Find-Iscc {
    $candidates = @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles}\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles(x86)}\Inno Setup 5\ISCC.exe",
        "${env:LOCALAPPDATA}\Programs\Inno Setup 6\ISCC.exe"
    )
    foreach ($path in $candidates) {
        if ($path -and (Test-Path $path)) {
            return $path
        }
    }
    $cmd = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }
    return $null
}

function Refresh-MachinePath {
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($machine) {
        $env:Path = "$machine;$user;$env:Path"
    }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$stageExe = Join-Path $repoRoot "build\windows-stage\BlitzRecorderWindows.exe"
if (-not (Test-Path $stageExe)) {
    throw "build/windows-stage/BlitzRecorderWindows.exe missing; run stage-studio.ps1 first"
}

$iscc = Find-Iscc
if (-not $iscc) {
    $chocoExe = $null
    $chocoCmd = Get-Command choco -ErrorAction SilentlyContinue
    if ($chocoCmd) {
        $chocoExe = $chocoCmd.Source
    } elseif ($env:ChocolateyInstall) {
        $candidate = Join-Path $env:ChocolateyInstall "bin\choco.exe"
        if (Test-Path $candidate) {
            $chocoExe = $candidate
        }
    }
    if (-not $chocoExe) {
        throw "ISCC.exe missing and chocolatey is not on PATH. Install Inno Setup 6."
    }
    Write-Host "installing Inno Setup via chocolatey ($chocoExe)"
    & $chocoExe install innosetup --no-progress -y
    if ($LASTEXITCODE -ne 0) {
        throw "choco install innosetup failed"
    }
    Refresh-MachinePath
    $iscc = Find-Iscc
}
if (-not $iscc) {
    throw "ISCC.exe missing after Inno Setup install (checked Program Files and PATH)"
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$out = (Resolve-Path $OutputDir).Path
$iss = Join-Path $PSScriptRoot "BlitzRecorder.iss"
$infoVersion = ConvertTo-InnoVersion $AppVersion
Write-Host "ISCC=$iscc /DAppVersion=$AppVersion /DVersionInfoVersion=$infoVersion /F$OutputName /O$out $iss"
& $iscc "/DAppVersion=$AppVersion" "/DVersionInfoVersion=$infoVersion" "/F$OutputName" "/O$out" $iss
if ($LASTEXITCODE -ne 0) { throw "Inno Setup compile failed" }
$built = Join-Path $out "$OutputName.exe"
if (-not (Test-Path $built)) { throw "installer missing: $built" }
Write-Host "installer=$built"
