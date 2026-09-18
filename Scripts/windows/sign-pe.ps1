param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$Filter = "exe,dll"
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($env:WINDOWS_PFX_BASE64)) {
    throw "WINDOWS_PFX_BASE64 is empty"
}
if ($null -eq $env:WINDOWS_PFX_PASSWORD) {
    throw "WINDOWS_PFX_PASSWORD is missing"
}

function Find-SignTool {
    if (Get-Command signtool -ErrorAction SilentlyContinue) {
        return (Get-Command signtool).Source
    }
    $vswhere = @(
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\Installer\vswhere.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($vswhere) {
        $vsPath = & $vswhere -latest -products * -property installationPath
        $msvc = Join-Path $vsPath "VC\Tools\MSVC"
        $hosts = @("Hostx64\x64", "Hostarm64\arm64", "Hostx86\x86")
        if (Test-Path $msvc) {
            foreach ($dir in @(Get-ChildItem -Path $msvc -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)) {
                foreach ($hostDir in $hosts) {
                    $candidate = Join-Path $dir.FullName "bin\$hostDir\signtool.exe"
                    if (Test-Path $candidate) { return $candidate }
                }
            }
        }
    }
    $kit = "${env:ProgramFiles(x86)}\Windows Kits\10\bin"
    if (Test-Path $kit) {
        $vers = @(Get-ChildItem $kit -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
        foreach ($ver in $vers) {
            foreach ($arch in @("x64", "arm64", "x86")) {
                $candidate = Join-Path $ver.FullName "$arch\signtool.exe"
                if (Test-Path $candidate) { return $candidate }
            }
        }
    }
    return $null
}

$signtool = Find-SignTool
if (-not $signtool) { throw "signtool.exe missing" }

$files = @()
if (Test-Path $Path -PathType Leaf) {
    $files = @(Get-Item $Path)
} elseif (Test-Path $Path -PathType Container) {
    $exts = @($Filter.Split(",") | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
    $files = @(Get-ChildItem $Path -File | Where-Object { $exts -contains $_.Extension.TrimStart(".").ToLowerInvariant() })
} else {
    throw "sign path missing: $Path"
}
if ($files.Count -eq 0) {
    throw "no files to sign under $Path (filter=$Filter)"
}

$pfx = Join-Path ([IO.Path]::GetTempPath()) ("br-sign-" + [guid]::NewGuid().ToString() + ".pfx")
$thumb = $null
try {
    [IO.File]::WriteAllBytes($pfx, [Convert]::FromBase64String($env:WINDOWS_PFX_BASE64))
    $secure = ConvertTo-SecureString $env:WINDOWS_PFX_PASSWORD -AsPlainText -Force
    $cert = Import-PfxCertificate -FilePath $pfx -CertStoreLocation Cert:\CurrentUser\My -Password $secure
    if (-not $cert) { throw "Import-PfxCertificate failed" }
    $thumb = $cert.Thumbprint
    foreach ($file in $files) {
        & $signtool sign /sha1 $thumb /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 $file.FullName
        if ($LASTEXITCODE -ne 0) {
            throw "signtool failed for $($file.Name)"
        }
        $sig = Get-AuthenticodeSignature $file.FullName
        if ($sig.Status -eq "NotSigned") {
            throw "$($file.Name) still NotSigned after signtool"
        }
        Write-Host "signed $($file.Name) status=$($sig.Status)"
    }
} finally {
    if ($thumb) {
        Remove-Item "Cert:\CurrentUser\My\$thumb" -ErrorAction SilentlyContinue
    }
    if (Test-Path $pfx) {
        Remove-Item $pfx -Force -ErrorAction SilentlyContinue
    }
}
