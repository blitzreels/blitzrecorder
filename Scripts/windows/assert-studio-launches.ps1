param(
    [Parameter(Mandatory = $true)][string]$StageDir,
    [int]$TimeoutMs = 20000
)

$ErrorActionPreference = "Stop"

if (-not [IO.Path]::IsPathRooted($StageDir)) {
    $StageDir = Join-Path (Get-Location) $StageDir
}
$exe = Join-Path $StageDir "BlitzRecorderWindows.exe"
if (-not (Test-Path $exe)) {
    throw "missing $exe"
}

# GUI subsystem: a missing Swift/CRT DLL pops a blocking dialog. Time-box --help
# so CI fails instead of hanging until the job timeout.
$p = Start-Process `
    -FilePath $exe `
    -ArgumentList "--help" `
    -WorkingDirectory $StageDir `
    -PassThru `
    -WindowStyle Hidden
if (-not $p.WaitForExit($TimeoutMs)) {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    throw "BlitzRecorderWindows.exe --help hung after ${TimeoutMs}ms (missing DLL or main ignored --help)"
}
if ($p.ExitCode -ne 0) {
    throw "BlitzRecorderWindows.exe --help exited $($p.ExitCode)"
}
Write-Host "studio --help ok ($($p.Id))"
