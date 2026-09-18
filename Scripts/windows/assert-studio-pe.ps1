param(
    [Parameter(Mandatory = $true)][string]$ExePath,
    [string]$StageDir = "",
    [string[]]$SearchDirs = @()
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ExePath)) {
    throw "exe missing: $ExePath"
}

function Find-Dumpbin {
    if (Get-Command dumpbin -ErrorAction SilentlyContinue) {
        return (Get-Command dumpbin).Source
    }
    $vswhere = @(
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\Installer\vswhere.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $vswhere) { return $null }
    $vsPath = & $vswhere -latest -products * -property installationPath
    if (-not $vsPath) { return $null }
    $hosts = @("Hostx64\x64", "Hostarm64\arm64", "Hostx86\x86")
    $msvc = Join-Path $vsPath "VC\Tools\MSVC"
    if (-not (Test-Path $msvc)) { return $null }
    foreach ($dir in @(Get-ChildItem -Path $msvc -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
        foreach ($hostDir in $hosts) {
            $candidate = Join-Path $dir.FullName "bin\$hostDir\dumpbin.exe"
            if (Test-Path $candidate) {
                return $candidate
            }
        }
    }
    return $null
}

function Find-LlvmReadobj {
    if (Get-Command llvm-readobj -ErrorAction SilentlyContinue) {
        return (Get-Command llvm-readobj).Source
    }
    $swift = Get-Command swift -ErrorAction SilentlyContinue
    if (-not $swift) { return $null }
    $candidate = Join-Path (Split-Path $swift.Source) "llvm-readobj.exe"
    if (Test-Path $candidate) { return $candidate }
    return $null
}

$dumpbin = Find-Dumpbin
$readobj = Find-LlvmReadobj
$gui = $false
$dependents = @()

if ($dumpbin) {
    $headers = & $dumpbin /HEADERS $ExePath 2>&1 | Out-String
    if ($headers -match 'subsystem \(Windows GUI\)') {
        $gui = $true
    }
    $depText = & $dumpbin /DEPENDENTS $ExePath 2>&1 | Out-String
    $dependents = [regex]::Matches($depText, '(?im)^\s+([A-Za-z0-9._\-]+\.dll)\s*$') |
        ForEach-Object { $_.Groups[1].Value }
} elseif ($readobj) {
    $headers = & $readobj --file-headers $ExePath 2>&1 | Out-String
    if ($headers -match 'IMAGE_SUBSYSTEM_WINDOWS_GUI') {
        $gui = $true
    }
    $imp = & $readobj --coff-imports $ExePath 2>&1 | Out-String
    $dependents = [regex]::Matches($imp, '(?im)Name:\s+([A-Za-z0-9._\-]+\.dll)') |
        ForEach-Object { $_.Groups[1].Value }
} else {
    throw "dumpbin/llvm-readobj missing; cannot verify WINDOWS GUI subsystem"
}

if (-not $gui) {
    throw "BlitzRecorderWindows.exe is not WINDOWS GUI (Swift must link /SUBSYSTEM:WINDOWS /ENTRY:mainCRTStartup)"
}

Write-Host "PE subsystem=WINDOWS GUI ($ExePath)"

$hasIcon = $false
if ($dumpbin) {
    $all = & $dumpbin /ALL $ExePath 2>&1 | Out-String
    if ($all -match 'GROUP_ICON|RT_GROUP_ICON') {
        $hasIcon = $true
    }
} elseif ($readobj) {
    $resDump = & $readobj --coff-resources $ExePath 2>&1 | Out-String
    if ($resDump -match 'GROUP_ICON|RT_GROUP_ICON|Icon Group') {
        $hasIcon = $true
    }
}
if (-not $hasIcon) {
    throw "BlitzRecorderWindows.exe is missing RT_GROUP_ICON (link BlitzRecorder.res from app.rc)"
}
Write-Host "PE has RT_GROUP_ICON"

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
            }
        }
    }
    return $null
}

$mt = Find-MtExe
if (-not $mt) {
    throw "mt.exe missing; cannot verify maxversiontested (XAML Islands)"
}
$extracted = Join-Path ([IO.Path]::GetTempPath()) ("br-assert-manifest-" + [guid]::NewGuid().ToString() + ".xml")
try {
    & $mt -nologo "-inputresource:${ExePath};#1" "-out:$extracted" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $extracted)) {
        throw "BlitzRecorderWindows.exe is missing RT_MANIFEST (link app.rc + /MANIFEST:NO, or mt.exe embed)"
    }
    $xml = Get-Content $extracted -Raw
    if ($xml -notmatch 'maxversiontested') {
        throw "embedded manifest is missing maxversiontested (WinUI XAML Islands will fail)"
    }
    if ($xml -notmatch 'asInvoker') {
        throw "embedded manifest is missing asInvoker"
    }
    Write-Host "PE manifest has maxversiontested + asInvoker"
} finally {
    Remove-Item $extracted -ErrorAction SilentlyContinue
}

if (-not $StageDir) {
    return
}

$runtime = '^(swift|_swift|_Foundation|Foundation|BlocksRuntime|dispatch|icu|vcruntime|msvcp|concrt|vccorlib|d3dcompiler)'
$pes = @($ExePath)
if ($StageDir -and (Test-Path $StageDir)) {
    $pes += @(Get-ChildItem $StageDir -File | Where-Object { $_.Extension -match '\.(exe|dll)$' } | ForEach-Object { $_.FullName })
}
$pes = $pes | Select-Object -Unique

foreach ($pe in $pes) {
    $peDeps = @()
    if ($dumpbin) {
        $depText = & $dumpbin /DEPENDENTS $pe 2>&1 | Out-String
        $peDeps = [regex]::Matches($depText, '(?im)^\s+([A-Za-z0-9._\-]+\.dll)\s*$') |
            ForEach-Object { $_.Groups[1].Value }
    } elseif ($readobj) {
        $imp = & $readobj --coff-imports $pe 2>&1 | Out-String
        $peDeps = [regex]::Matches($imp, '(?im)Name:\s+([A-Za-z0-9._\-]+\.dll)') |
            ForEach-Object { $_.Groups[1].Value }
    }
    foreach ($dll in ($peDeps | Select-Object -Unique)) {
        if ($dll -notmatch $runtime) { continue }
        $dest = Join-Path $StageDir $dll
        if (Test-Path $dest) { continue }
        foreach ($dir in $SearchDirs) {
            if (-not $dir) { continue }
            $from = Join-Path $dir $dll
            if (Test-Path $from) {
                Copy-Item $from $dest -Force
                break
            }
        }
    }
}

$missing = @()
foreach ($pe in $pes) {
    $peDeps = @()
    if ($dumpbin) {
        $depText = & $dumpbin /DEPENDENTS $pe 2>&1 | Out-String
        $peDeps = [regex]::Matches($depText, '(?im)^\s+([A-Za-z0-9._\-]+\.dll)\s*$') |
            ForEach-Object { $_.Groups[1].Value }
    } elseif ($readobj) {
        $imp = & $readobj --coff-imports $pe 2>&1 | Out-String
        $peDeps = [regex]::Matches($imp, '(?im)Name:\s+([A-Za-z0-9._\-]+\.dll)') |
            ForEach-Object { $_.Groups[1].Value }
    }
    foreach ($dll in ($peDeps | Select-Object -Unique)) {
        if ($dll -notmatch $runtime) { continue }
        if (-not (Test-Path (Join-Path $StageDir $dll))) {
            $missing += "$dll (via $(Split-Path $pe -Leaf))"
        }
    }
}
if ($missing.Count -gt 0) {
    $missing = $missing | Select-Object -Unique
    throw "staged runtime missing imported DLLs (clean-machine launch would fail): $($missing -join ', ')"
}
