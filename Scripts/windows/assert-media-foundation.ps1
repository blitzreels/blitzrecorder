$ErrorActionPreference = "Stop"

$system32 = Join-Path $env:WINDIR "System32"
$required = @(
    "mfplat.dll",
    "mfreadwrite.dll",
    "mfh264enc.dll",
    "msmpeg2vdec.dll"
)
$missing = @()
foreach ($name in $required) {
    if (-not (Test-Path (Join-Path $system32 $name))) {
        $missing += $name
    }
}
if ($missing.Count -gt 0) {
    throw ("Inbox Media Foundation H.264 missing: {0}. Microsoft's H.264 encoder/decoder are client-only (not Windows Server). Run the fixture job on windows-11-vs2026-arm." -f ($missing -join ", "))
}

Write-Host "Media Foundation H.264 present:"
Get-Item ($required | ForEach-Object { Join-Path $system32 $_ }) | Format-Table Name, Length -AutoSize
