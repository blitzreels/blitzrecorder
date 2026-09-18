param(
    [Parameter(Mandatory = $true)][string]$PackageRoot
)

$ErrorActionPreference = "Stop"

function Find-ReleaseExe([string]$Root, [string]$Name) {
    Get-ChildItem -Path $Root -Recurse -Filter $Name -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -match '\\release\\' -or
            $_.FullName -match '\\bin\\BlitzRecorderFixture\.exe$' -or
            $_.DirectoryName -match '\\bin$'
        } |
        Select-Object -First 1
}

$swift = Find-ReleaseExe (Join-Path $PackageRoot ".build") "BlitzRecorderWindows.exe"
$native = Find-ReleaseExe (Join-Path $PackageRoot "build-native") "BlitzRecorderFixture.exe"
if (-not $swift -and -not $native) {
    throw "No BlitzRecorderWindows.exe or BlitzRecorderFixture.exe under $PackageRoot"
}

$out = Join-Path (Get-Location) "build/windows-fixture"
New-Item -ItemType Directory -Force -Path $out | Out-Null

if ($native) {
    Write-Host "using native fixture $($native.FullName)"
    $exportLines = & $native.FullName $out 2>&1
    $exportCode = $LASTEXITCODE
    $exportLog = $exportLines | Out-String
    Write-Host $exportLog
    if ($exportCode -ne 0) { throw "fixture export/play failed (exit $exportCode)" }
} else {
    Write-Host "using Swift studio $($swift.FullName)"
    $exportLines = & $swift.FullName --export-fixture $out 2>&1
    $exportCode = $LASTEXITCODE
    $exportLog = $exportLines | Out-String
    Write-Host $exportLog
    if ($exportCode -ne 0) { throw "fixture export failed (exit $exportCode)" }
    & $swift.FullName --export $out
    if ($LASTEXITCODE -ne 0) { throw "take compose failed" }
    & $swift.FullName --play $out
    if ($LASTEXITCODE -ne 0) { throw "fixture playback failed" }
}

if ($exportLog -notmatch "encoder=") { throw "fixture did not report encoder" }
if ($exportLog -notmatch "decoded \d+ parallel frames") { throw "fixture did not decode parallel frames" }

foreach ($name in @(
    "screen.mp4",
    "camera.mp4",
    "export.mp4",
    "audio.m4a",
    "take.json",
    "project.blitzrecorder.json"
)) {
    $path = Join-Path $out $name
    if (-not (Test-Path $path) -or (Get-Item $path).Length -lt 16) {
        throw "$name missing or too small"
    }
}

$project = Get-Content (Join-Path $out "project.blitzrecorder.json") -Raw
if ($project -notmatch '"role"\s*:\s*"screen"' -or $project -notmatch '"camera"') {
    throw "project.blitzrecorder.json is not Domain camera-pip JSON"
}
