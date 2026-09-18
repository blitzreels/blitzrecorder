param(
    [Parameter(Mandatory = $true)][string]$ExePath,
    [Parameter(Mandatory = $true)][string]$ManifestPath
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ExePath)) { throw "exe missing: $ExePath" }
if (-not (Test-Path $ManifestPath)) { throw "manifest missing: $ManifestPath" }

function Find-MtExe {
    if (Get-Command mt.exe -ErrorAction SilentlyContinue) {
        return (Get-Command mt.exe).Source
    }
    $hostArchs = @()
    if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
        $hostArchs += @("arm64", "x64")
    } else {
        $hostArchs += @("x64", "x86")
    }
    $roots = @(
        $env:WindowsSdkDir,
        "${env:ProgramFiles(x86)}\Windows Kits\10\bin",
        "${env:ProgramFiles}\Windows Kits\10\bin"
    )
    $vswhere = @(
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\Installer\vswhere.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($vswhere) {
        $kitRoot = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.Windows10SDK -property installationPath
        if ($kitRoot) {
            $roots += @(
                (Join-Path $kitRoot "Windows Kits\10\bin"),
                "${env:ProgramFiles(x86)}\Windows Kits\10\bin"
            )
        }
    }
    foreach ($root in ($roots | Where-Object { $_ } | Select-Object -Unique)) {
        $bin = $root
        if (Test-Path (Join-Path $root "bin")) { $bin = Join-Path $root "bin" }
        if (-not (Test-Path $bin)) { continue }
        $dirs = @($bin)
        $dirs += @(Get-ChildItem $bin -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | ForEach-Object { $_.FullName })
        foreach ($dir in $dirs) {
            foreach ($arch in $hostArchs) {
                $candidate = Join-Path $dir "$arch\mt.exe"
                if (Test-Path $candidate) { return $candidate }
                $nested = Join-Path $dir "bin\$arch\mt.exe"
                if (Test-Path $nested) { return $nested }
            }
        }
    }
    return $null
}

$mt = Find-MtExe
if (-not $mt) {
    throw "mt.exe not found. Windows SDK is required to embed maxversiontested for XAML Islands."
}

function Test-EmbeddedManifest([string]$exe, [string]$mtExe) {
    $extracted = Join-Path ([IO.Path]::GetTempPath()) ("br-manifest-" + [guid]::NewGuid().ToString() + ".xml")
    try {
        & $mtExe -nologo "-inputresource:${exe};#1" "-out:$extracted" 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $extracted)) {
            return $false
        }
        $xml = Get-Content $extracted -Raw -ErrorAction SilentlyContinue
        return ($xml -match 'maxversiontested' -and $xml -match 'asInvoker')
    } finally {
        Remove-Item $extracted -ErrorAction SilentlyContinue
    }
}

if (Test-EmbeddedManifest $ExePath $mt) {
    Write-Host "manifest already has maxversiontested+asInvoker; skipping mt.exe rewrite (keeps RT_GROUP_ICON)"
    return
}

& $mt -nologo -manifest $ManifestPath "-outputresource:$ExePath;#1"
if ($LASTEXITCODE -ne 0) {
    throw "mt.exe failed embedding $ManifestPath into $ExePath"
}
if (-not (Test-EmbeddedManifest $ExePath $mt)) {
    throw "mt.exe ran but $ExePath is still missing maxversiontested/asInvoker"
}
Write-Host "embedded manifest into $ExePath"
