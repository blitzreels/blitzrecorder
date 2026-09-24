param(
    [string]$StageDir = "build\windows-stage",
    [string]$OutputPath = "build\windows-store\BlitzRecorder-Windows-Store-x64.msix"
)

$ErrorActionPreference = "Stop"

function Find-SdkTool([string]$name) {
    $onPath = Get-Command $name -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    $kits = Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin"
    if (Test-Path $kits) {
        foreach ($version in (Get-ChildItem $kits -Directory | Sort-Object Name -Descending)) {
            $candidate = Join-Path $version.FullName "x64\$name"
            if (Test-Path $candidate) { return $candidate }
        }
    }
    throw "$name missing from PATH and Windows SDK"
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$source = Join-Path $repoRoot "Apps\WindowsStudio\MSIX"
$stage = (Resolve-Path $StageDir).Path
$output = [IO.Path]::GetFullPath((Join-Path $repoRoot $OutputPath))
$content = Join-Path $repoRoot "build\windows-store\content"
$makeappx = Find-SdkTool "makeappx.exe"
$signtool = Find-SdkTool "signtool.exe"

if (-not (Test-Path (Join-Path $stage "BlitzRecorderWindows.exe"))) {
    throw "Staged Windows executable missing: $stage"
}
if (Test-Path $content) { Remove-Item $content -Recurse -Force }
New-Item $content -ItemType Directory -Force | Out-Null
Copy-Item (Join-Path $stage "*") $content -Recurse -Force
Copy-Item (Join-Path $source "AppxManifest.xml") $content -Force
Copy-Item (Join-Path $source "Assets") $content -Recurse -Force
foreach ($name in @("BlitzRecorder.cmd", "READ_ME.txt")) {
    $path = Join-Path $content $name
    if (Test-Path $path) { Remove-Item $path -Force }
}

[xml]$manifest = Get-Content (Join-Path $content "AppxManifest.xml")
$identity = $manifest.Package.Identity
$publisher = "CN=10E13D0E-EE81-40C5-B37C-4052971ED410"
if ($identity.Name -ne "BlitzReels.BlitzRecorder" -or $identity.Publisher -ne $publisher -or $identity.ProcessorArchitecture -ne "x64") {
    throw "MSIX identity does not match the reserved Microsoft Store product"
}
$parts = $identity.Version.Split(".")
if ($parts.Count -ne 4 -or [int]$parts[0] -lt 1 -or [int]$parts[3] -ne 0 -or ($parts | Where-Object { [int]$_ -gt 65535 })) {
    throw "MSIX version must have four values <= 65535, a nonzero major, and revision 0"
}

New-Item (Split-Path $output) -ItemType Directory -Force | Out-Null
& $makeappx pack /d $content /p $output /o
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $output)) { throw "MakeAppx pack failed" }

$certificate = New-SelfSignedCertificate -Type CodeSigningCert -Subject $publisher -CertStoreLocation "Cert:\CurrentUser\My"
if (-not $certificate) { throw "Unable to create temporary Store upload certificate" }
& $signtool sign /fd SHA256 /sha1 $certificate.Thumbprint /s My $output
if ($LASTEXITCODE -ne 0) { throw "SignTool sign failed" }
$archive = [System.IO.Compression.ZipFile]::OpenRead($output)
try {
    if (-not ($archive.Entries | Where-Object { $_.FullName -eq "AppxSignature.p7x" })) {
        throw "Signed MSIX has no AppxSignature.p7x"
    }
} finally {
    $archive.Dispose()
}
Write-Host "Store MSIX: $output"
Write-Host "Identity: $($identity.Name) $($identity.Version) $($identity.Publisher)"
Write-Host "Temporary upload signature: $($certificate.Thumbprint)"
