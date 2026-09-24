param(
    [Parameter(Mandatory = $true)][string]$PackageRoot,
    [Parameter(Mandatory = $true)][string]$StageDir,
    [string]$ZipPath = ""
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "msvc-env.ps1")
$vsArch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "arm64" } else { "x64" }
if (-not (Enter-MsvcDevCmd $vsArch)) {
    Write-Host "vcvars merge skipped; dumpbin/mt will use vswhere fallbacks"
}

$exe = Get-ChildItem -Path (Join-Path $PackageRoot ".build") -Recurse -Filter BlitzRecorderWindows.exe |
    Where-Object { $_.FullName -match '\\release\\' } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if (-not $exe) {
    throw "BlitzRecorderWindows.exe not found under $PackageRoot\.build"
}

if (Test-Path $StageDir) {
    Remove-Item -Recurse -Force $StageDir
}
New-Item -ItemType Directory -Force -Path $StageDir | Out-Null

function Add-Dir([System.Collections.Specialized.OrderedDictionary]$dirs, $path) {
    if (-not $path) { return }
    if (-not (Test-Path $path)) { return }
    $full = (Resolve-Path $path).Path
    if (-not $dirs[$full]) {
        $dirs[$full] = $true
    }
}

$runtimeDirs = [ordered]@{}
Add-Dir $runtimeDirs $exe.Directory.FullName

Get-ChildItem -Path $exe.Directory -Directory -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -notmatch '^(Modules|IndexStore|Description)$'
} | ForEach-Object { Add-Dir $runtimeDirs $_.FullName }

$swift = Get-Command swift -ErrorAction SilentlyContinue
if ($swift) {
    $swiftDir = Split-Path $swift.Source
    Add-Dir $runtimeDirs $swiftDir
    $root = Split-Path $swiftDir
    foreach ($rel in @("usr\bin", "usr\lib", "usr\lib\swift", "usr\lib\swift\windows", "bin", "runtime", "Runtimes")) {
        Add-Dir $runtimeDirs (Join-Path $root $rel)
        Add-Dir $runtimeDirs (Join-Path (Split-Path $root) $rel)
    }
    $windowsLib = Join-Path $root "usr\lib\swift\windows"
    if (Test-Path $windowsLib) {
        Get-ChildItem -Path $windowsLib -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            Add-Dir $runtimeDirs $_.FullName
        }
    }
}

if ($env:SDKROOT) {
    foreach ($rel in @("usr\bin", "usr\lib", "bin")) {
        Add-Dir $runtimeDirs (Join-Path $env:SDKROOT $rel)
    }
}

foreach ($entry in ($env:PATH -split ';')) {
    if ($entry -and (
            (Test-Path (Join-Path $entry "swiftCore.dll")) -or
            (Test-Path (Join-Path $entry "swift_Core.dll")) -or
            (Test-Path (Join-Path $entry "Foundation.dll"))
        )) {
        Add-Dir $runtimeDirs $entry
    }
}

foreach ($root in @(
        (Join-Path $env:LOCALAPPDATA "Programs\Swift"),
        (Join-Path ${env:ProgramFiles} "Swift")
    )) {
    if (-not $root -or -not (Test-Path $root)) { continue }
    Get-ChildItem -Path $root -Recurse -Directory -Filter "bin" -ErrorAction SilentlyContinue |
        Select-Object -First 16 |
        ForEach-Object { Add-Dir $runtimeDirs $_.FullName }
}

Get-ChildItem -Path $exe.Directory -File | Where-Object {
    $_.Extension -match '\.(exe|dll|manifest)$'
} | ForEach-Object {
    Copy-Item -Path $_.FullName -Destination $StageDir -Force
}

$runtimePattern = '^(_?swift.*|_Foundation.*|Foundation.*|BlocksRuntime|dispatch|icu.*)\.dll$'
foreach ($dir in $runtimeDirs.Keys) {
    Get-ChildItem -Path $dir -File -Filter *.dll -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $runtimePattern } |
        ForEach-Object {
            Copy-Item -Path $_.FullName -Destination (Join-Path $StageDir $_.Name) -Force
        }
    Get-ChildItem -Path $dir -File -Filter swift-backtrace.exe -ErrorAction SilentlyContinue |
        ForEach-Object {
            Copy-Item -Path $_.FullName -Destination (Join-Path $StageDir $_.Name) -Force
        }
}

$staged = Join-Path $StageDir "BlitzRecorderWindows.exe"
if (-not (Test-Path $staged)) {
    throw "Staging failed: $staged missing"
}

$manifest = Join-Path $PackageRoot "BlitzRecorderWindows.exe.manifest"
if (Test-Path $manifest) {
    Copy-Item $manifest (Join-Path $StageDir "BlitzRecorderWindows.exe.manifest") -Force
    & (Join-Path $PSScriptRoot "embed-manifest.ps1") -ExePath $staged -ManifestPath $manifest
}

$ico = Join-Path $PackageRoot "BlitzRecorder.ico"
if (Test-Path $ico) {
    Copy-Item $ico (Join-Path $StageDir "BlitzRecorder.ico") -Force
}

$webviewAssets = Join-Path $PackageRoot "WebUI"
if (-not (Test-Path (Join-Path $webviewAssets "index.html"))) {
    throw "Windows workspace assets missing"
}
Copy-Item $webviewAssets (Join-Path $StageDir "WebUI") -Recurse -Force
$sdkArch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "arm64" } else { "x64" }
$webviewLoader = Join-Path $PackageRoot ".webview-sdk/package/build/native/$sdkArch/WebView2Loader.dll"
if (-not (Test-Path $webviewLoader)) {
    throw "WebView2Loader.dll missing"
}
Copy-Item $webviewLoader (Join-Path $StageDir "WebView2Loader.dll") -Force

$system32 = Join-Path $env:SystemRoot "System32"
$crtNames = @(
    "vcruntime140.dll",
    "vcruntime140_1.dll",
    "vcruntime140_threads.dll",
    "msvcp140.dll",
    "msvcp140_1.dll",
    "msvcp140_2.dll",
    "msvcp140_atomic_wait.dll",
    "msvcp140_codecvt_ids.dll",
    "concrt140.dll",
    "vccorlib140.dll",
    "d3dcompiler_47.dll"
)
foreach ($name in $crtNames) {
    $from = Join-Path $system32 $name
    $to = Join-Path $StageDir $name
    if ((Test-Path $from) -and -not (Test-Path $to)) {
        Copy-Item $from $to
    }
}

$extraSwift = @(
    "swift_StringProcessing.dll",
    "swiftObservation.dll",
    "swift_Synchronization.dll",
    "FoundationInternationalization.dll",
    "FoundationNetworking.dll",
    "FoundationXML.dll",
    "_FoundationICU.dll"
)
foreach ($name in $extraSwift) {
    $to = Join-Path $StageDir $name
    if (Test-Path $to) { continue }
    foreach ($dir in $runtimeDirs.Keys) {
        if (-not $dir) { continue }
        $from = Join-Path $dir $name
        if (Test-Path $from) {
            Copy-Item $from $to -Force
            break
        }
    }
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
            if (Test-Path $candidate) { return $candidate }
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

function Get-ImportedDlls([string]$pe, [string]$dumpbin, [string]$readobj) {
    if ($dumpbin) {
        $text = & $dumpbin /DEPENDENTS $pe 2>&1 | Out-String
        return [regex]::Matches($text, '(?im)^\s+([A-Za-z0-9._\-]+\.dll)\s*$') | ForEach-Object { $_.Groups[1].Value }
    }
    if ($readobj) {
        $text = & $readobj --coff-imports $pe 2>&1 | Out-String
        return [regex]::Matches($text, '(?im)Name:\s+([A-Za-z0-9._\-]+\.dll)') | ForEach-Object { $_.Groups[1].Value }
    }
    return @()
}

$dumpbin = Find-Dumpbin
$readobj = Find-LlvmReadobj
$runtimeImport = '^(swift|_swift|_Foundation|Foundation|BlocksRuntime|dispatch|icu|vcruntime|msvcp|concrt|vccorlib|d3dcompiler)'
$searchDirs = @($runtimeDirs.Keys) + @($system32)
$queue = New-Object System.Collections.Generic.Queue[string]
Get-ChildItem $StageDir -File | Where-Object { $_.Extension -match '\.(exe|dll)$' } | ForEach-Object {
    $queue.Enqueue($_.FullName)
}
$seenPe = @{}
while ($queue.Count -gt 0) {
    $pe = $queue.Dequeue()
    if ($seenPe.ContainsKey($pe)) { continue }
    $seenPe[$pe] = $true
    foreach ($dll in (Get-ImportedDlls $pe $dumpbin $readobj | Select-Object -Unique)) {
        if ($dll -notmatch $runtimeImport) { continue }
        $dest = Join-Path $StageDir $dll
        if (-not (Test-Path $dest)) {
            foreach ($dir in $searchDirs) {
                if (-not $dir) { continue }
                $from = Join-Path $dir $dll
                if (Test-Path $from) {
                    Copy-Item $from $dest -Force
                    break
                }
            }
        }
        if (Test-Path $dest) {
            $queue.Enqueue($dest)
        }
    }
}

function Test-AnyStaged([string[]]$names) {
    foreach ($name in $names) {
        if (Test-Path (Join-Path $StageDir $name)) {
            return $true
        }
    }
    return $false
}

$missing = @()
if (-not (Test-AnyStaged @("swiftCore.dll", "swift_Core.dll"))) { $missing += "swiftCore.dll" }
if (-not (Test-AnyStaged @("Foundation.dll", "FoundationEssentials.dll"))) { $missing += "Foundation.dll" }
if (-not (Test-AnyStaged @("BlocksRuntime.dll"))) { $missing += "BlocksRuntime.dll" }
if (-not (Test-AnyStaged @("swiftCRT.dll"))) { $missing += "swiftCRT.dll" }
if (-not (Test-AnyStaged @("swiftWinSDK.dll"))) { $missing += "swiftWinSDK.dll" }
if (-not (Test-AnyStaged @("swift_Concurrency.dll"))) { $missing += "swift_Concurrency.dll" }
if (-not (Test-AnyStaged @("dispatch.dll", "swiftDispatch.dll"))) { $missing += "dispatch.dll" }
if (-not (Test-AnyStaged @("vcruntime140.dll"))) { $missing += "vcruntime140.dll" }
if (-not (Test-AnyStaged @("msvcp140.dll"))) { $missing += "msvcp140.dll" }
if (-not (Test-AnyStaged @("d3dcompiler_47.dll"))) { $missing += "d3dcompiler_47.dll" }
$icu = @(Get-ChildItem $StageDir -File -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match '^(icu|_FoundationICU)'
})
if ($icu.Count -eq 0) { $missing += "icu" }
if ($missing.Count -gt 0) {
    $searched = $runtimeDirs.Keys -join "; "
    throw "staged runtime missing: $($missing -join ', '). installer would not launch on a clean machine. searched: $searched"
}

& (Join-Path $PSScriptRoot "assert-studio-pe.ps1") -ExePath $staged -StageDir $StageDir -SearchDirs @($runtimeDirs.Keys + $system32)

Set-Content -Path (Join-Path $StageDir "BlitzRecorder.cmd") -Encoding ASCII -Value @"
@echo off
cd /d "%~dp0"
start "" "%~dp0BlitzRecorderWindows.exe"
"@

Set-Content -Path (Join-Path $StageDir "READ_ME.txt") -Encoding ASCII -Value @"
BlitzRecorder for Windows 11 x64.
Double-click BlitzRecorder.cmd (or BlitzRecorderWindows.exe).
First take: Screen + Mic. Leave Camera off.
Takes land in the folder shown as Ready (usually Videos\BlitzRecorder\take-*).
Grant Screen recording + Microphone when Windows asks.
"@

Write-Host "staged $(@(Get-ChildItem $StageDir -File).Count) files into $StageDir"

if ($ZipPath) {
    Set-Content -Path (Join-Path $StageDir "UNSIGNED.txt") -Encoding ASCII -Value @"
This zip is an unsigned CI drop, not the signed GitHub installer.
SmartScreen: More info -> Run anyway.
"@
    $zipDir = Split-Path $ZipPath
    if ($zipDir) {
        New-Item -ItemType Directory -Force -Path $zipDir | Out-Null
    }
    if (Test-Path $ZipPath) {
        Remove-Item -Force $ZipPath
    }
    Compress-Archive -Path (Join-Path $StageDir '*') -DestinationPath $ZipPath -CompressionLevel Optimal
    if (-not (Test-Path $ZipPath) -or (Get-Item $ZipPath).Length -lt 1024) {
        throw "portable zip missing or empty: $ZipPath"
    }
    Write-Host "portable zip=$ZipPath ($((Get-Item $ZipPath).Length) bytes)"
}
