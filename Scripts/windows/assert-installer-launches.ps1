param(
    [Parameter(Mandatory = $true)][string]$InstallerPath
)

$ErrorActionPreference = "Stop"

$installer = (Resolve-Path $InstallerPath).Path
$tempRoot = [IO.Path]::GetTempPath()
$installDir = Join-Path $tempRoot "BlitzRecorder CI Install"
$log = Join-Path $tempRoot "blitzrecorder-install.log"

if (Test-Path $installDir) {
    Remove-Item -Recurse -Force $installDir
}

$arguments = @(
    "/VERYSILENT",
    "/SUPPRESSMSGBOXES",
    "/NORESTART",
    "/SP-",
    "/DIR=`"$installDir`"",
    "/LOG=`"$log`""
)
$process = Start-Process -FilePath $installer -ArgumentList $arguments -PassThru -Wait
if ($process.ExitCode -ne 0) {
    throw "installer exited $($process.ExitCode); log=$log"
}

$exe = Join-Path $installDir "BlitzRecorderWindows.exe"
$uninstaller = Join-Path $installDir "unins000.exe"
if (-not (Test-Path $exe) -or -not (Test-Path $uninstaller)) {
    throw "installer did not create the app and uninstaller in $installDir"
}

$originalPath = $env:PATH
try {
    $env:PATH = "$env:SystemRoot\System32;$env:SystemRoot"
    & (Join-Path $PSScriptRoot "assert-studio-launches.ps1") -StageDir $installDir
} finally {
    $env:PATH = $originalPath
}

$uninstall = Start-Process -FilePath $uninstaller -ArgumentList @(
    "/VERYSILENT",
    "/SUPPRESSMSGBOXES",
    "/NORESTART"
) -PassThru -Wait
if ($uninstall.ExitCode -ne 0) {
    throw "uninstaller exited $($uninstall.ExitCode)"
}
Write-Host "installed app launched without Swift or Visual Studio on PATH"
