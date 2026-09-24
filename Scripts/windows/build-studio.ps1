param(
    [ValidateSet("debug", "release")]
    [string]$Configuration = "release",
    [string]$PackageRoot = "Apps/WindowsStudio",
    [switch]$NativeOnly
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "msvc-env.ps1")

& (Join-Path $PSScriptRoot "assert-studio-tree.ps1") -PackageRoot $PackageRoot -NativeOnly:$NativeOnly

$PackageRoot = (Resolve-Path $PackageRoot).Path

$webviewSdk = Join-Path $PackageRoot ".webview-sdk/package"
if (-not $NativeOnly) {
    $header = Join-Path $webviewSdk "build/native/include/WebView2.h"
    if (-not (Test-Path $header)) {
        $archive = Join-Path $PackageRoot ".webview-sdk/WebView2.zip"
        New-Item -ItemType Directory -Force -Path (Split-Path $archive) | Out-Null
        Invoke-WebRequest -Uri "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/1.0.2903.40" -OutFile $archive
        $hash = (Get-FileHash -Algorithm SHA256 $archive).Hash.ToLowerInvariant()
        if ($hash -ne "ef128016dd1e51c59178c827ed5b8aa3322c57afa8675d930f8109505542ad74") {
            throw "WebView2 SDK checksum mismatch"
        }
        New-Item -ItemType Directory -Force -Path $webviewSdk | Out-Null
        Expand-Archive -Path $archive -DestinationPath $webviewSdk -Force
    }
}

$arch = "x64"
if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
    $arch = "ARM64"
}

function Add-ToPath([string]$dir) {
    if ($dir -and (Test-Path $dir)) {
        $env:PATH = "$dir;$env:PATH"
    }
}

function Ensure-Cmake {
    if (Get-Command cmake -ErrorAction SilentlyContinue) { return }
    $vswhere = Get-VsWhere
    if ($vswhere) {
        $vsPath = & $vswhere -latest -products * -property installationPath
        $bundled = Join-Path $vsPath "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
        if (Test-Path $bundled) {
            Add-ToPath (Split-Path $bundled)
        }
    }
    if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
        throw "cmake is required. Install Visual Studio C++ tools (windows-2025 / VS 2026 images have it)."
    }
    Write-Host "cmake=$((Get-Command cmake).Source)"
}

function Ensure-Ninja {
    if (Get-Command ninja -ErrorAction SilentlyContinue) { return $true }
    $vswhere = Get-VsWhere
    if ($vswhere) {
        $vsPath = & $vswhere -latest -products * -property installationPath
        $cmakeNinja = Join-Path $vsPath "Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe"
        if (Test-Path $cmakeNinja) {
            Add-ToPath (Split-Path $cmakeNinja)
            return $true
        }
    }
    $zipName = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "ninja-winarm64.zip" } else { "ninja-win.zip" }
    $url = "https://github.com/ninja-build/ninja/releases/download/v1.12.1/$zipName"
    $dir = Join-Path $env:TEMP "br-ninja"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $zip = Join-Path $dir $zipName
    try {
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
        Expand-Archive -Path $zip -DestinationPath $dir -Force
    } catch {
        Write-Host "ninja download failed: $_"
        return $false
    }
    if (-not (Test-Path (Join-Path $dir "ninja.exe"))) { return $false }
    Add-ToPath $dir
    return $true
}

Ensure-Cmake

function Get-CmakeMajorMinor {
    $text = (& cmake --version | Select-Object -First 1)
    if ($text -match '(\d+)\.(\d+)') {
        return [int]$Matches[1], [int]$Matches[2]
    }
    return 0, 0
}

function Get-VsCmakeGenerator {
    $vswhere = Get-VsWhere
    if (-not $vswhere) { return $null }
    $installationVersion = & $vswhere -latest -products * -property installationVersion
    if (-not $installationVersion) { return $null }
    $major = [int]($installationVersion.Split(".")[0])
    switch ($major) {
        18 { return "Visual Studio 18 2026" }
        17 { return "Visual Studio 17 2022" }
        16 { return "Visual Studio 16 2019" }
        default { return $null }
    }
}

$cmakeConfig = if ($Configuration -eq "debug") { "Debug" } else { "Release" }
$buildDir = Join-Path $PackageRoot "build-native"
$generator = Get-VsCmakeGenerator
$cmakeMajor, $cmakeMinor = Get-CmakeMajorMinor
$candidates = @()
if ($generator) { $candidates += $generator }
$candidates += @("Visual Studio 18 2026", "Visual Studio 17 2022")
$candidates = $candidates | Select-Object -Unique
if ($cmakeMajor -lt 4 -or ($cmakeMajor -eq 4 -and $cmakeMinor -lt 2)) {
    $candidates = @($candidates | Where-Object { $_ -ne "Visual Studio 18 2026" })
    Write-Host "cmake $cmakeMajor.$cmakeMinor < 4.2; skipping Visual Studio 18 2026 generator"
}

$configured = $false
$multiConfig = $true
$shellFlag = if ($NativeOnly) { "OFF" } else { "ON" }
$adapterFlag = if ($NativeOnly) { "OFF" } else { "ON" }
$webviewFlag = "-DBR_WEBVIEW2_SDK=$($webviewSdk.Replace('\', '/'))"
$vcArch = if ($arch -eq "ARM64") { "arm64" } else { "x64" }
$msvcReady = Enter-MsvcDevCmd $vcArch
if (-not $msvcReady) {
    Write-Host "vcvars merge skipped before cmake; VS generator may still work"
}

# Ninja first: uses vcvars cl.exe, no CMake 4.2 "Visual Studio 18 2026" generator name.
if ($msvcReady -and (Ensure-Ninja)) {
    Write-Host "cmake generator=Ninja first arch=$arch BR_BUILD_CAPTURE_ADAPTER=$adapterFlag BR_BUILD_STUDIO_SHELL=$shellFlag"
    if (Test-Path $buildDir) {
        Remove-Item -Recurse -Force $buildDir
    }
    & cmake -S $PackageRoot -B $buildDir -G Ninja "-DCMAKE_BUILD_TYPE=$cmakeConfig" "-DBR_BUILD_CAPTURE_ADAPTER=$adapterFlag" "-DBR_BUILD_STUDIO_SHELL=$shellFlag" $webviewFlag
    if ($LASTEXITCODE -eq 0) {
        $configured = $true
        $multiConfig = $false
    } else {
        Write-Host "Ninja configure failed; trying VS generators"
        if (Test-Path $buildDir) {
            Remove-Item -Recurse -Force $buildDir
        }
    }
}

if (-not $configured) {
    foreach ($gen in $candidates) {
        Write-Host "cmake generator=$gen arch=$arch BR_BUILD_CAPTURE_ADAPTER=$adapterFlag BR_BUILD_STUDIO_SHELL=$shellFlag"
        & cmake -S $PackageRoot -B $buildDir -G $gen -A $arch "-DBR_BUILD_CAPTURE_ADAPTER=$adapterFlag" "-DBR_BUILD_STUDIO_SHELL=$shellFlag" $webviewFlag
        if ($LASTEXITCODE -eq 0) {
            $configured = $true
            break
        }
        Write-Host "cmake configure failed with $gen; wiping cache and trying next generator"
        if (Test-Path $buildDir) {
            Remove-Item -Recurse -Force $buildDir
        }
    }
}
if (-not $configured) {
    if ((Ensure-Ninja) -and (Enter-MsvcDevCmd $vcArch)) {
        Write-Host "cmake generator=Ninja (CMake 4.2+ required for VS 18; falling back)"
        if (Test-Path $buildDir) {
            Remove-Item -Recurse -Force $buildDir
        }
        & cmake -S $PackageRoot -B $buildDir -G Ninja "-DCMAKE_BUILD_TYPE=$cmakeConfig" "-DBR_BUILD_CAPTURE_ADAPTER=$adapterFlag" "-DBR_BUILD_STUDIO_SHELL=$shellFlag" $webviewFlag
        if ($LASTEXITCODE -eq 0) {
            $configured = $true
            $multiConfig = $false
        }
    }
}
if (-not $configured) {
    throw "cmake configure failed (tried: Ninja first, $($candidates -join ', '), Ninja)"
}

if ($multiConfig) {
    cmake --build $buildDir --config $cmakeConfig
} else {
    cmake --build $buildDir
}
if ($LASTEXITCODE -ne 0) { throw "MSVC WindowsCaptureNative build failed" }

$libDir = Join-Path $buildDir "lib"
if (-not (Test-Path (Join-Path $libDir "WindowsCaptureNative.lib"))) {
    $alt = Get-ChildItem -Path $buildDir -Recurse -Filter WindowsCaptureNative.lib | Select-Object -First 1
    if (-not $alt) { throw "WindowsCaptureNative.lib missing after MSVC build" }
    $libDir = $alt.Directory.FullName
}

# Package.swift `-L` must stay colon-free. Absolute D:\... becomes /LIBPATH:D:\...
# and lld-link splits on the drive colon. Stage libs next to Package.swift and
# run swift from that directory with BR_WINDOWS_CAPTURE_LIBDIR=build-native/lib.
$linkDir = Join-Path $PackageRoot "build-native/lib"
New-Item -ItemType Directory -Force -Path $linkDir | Out-Null
if (-not $NativeOnly) {
    $sdkArch = if ($arch -eq "ARM64") { "arm64" } else { "x64" }
    Copy-Item (Join-Path $webviewSdk "build/native/$sdkArch/WebView2Loader.dll.lib") (Join-Path $linkDir "WebView2Loader.lib") -Force
}
$toCopy = @("WindowsCaptureNative.lib")
if (-not $NativeOnly) {
    $toCopy += @("WindowsCaptureAdapter.lib", "WindowsStudioShell.lib")
}
foreach ($name in $toCopy) {
    $from = Join-Path $libDir $name
    if (-not (Test-Path $from)) {
        $altLib = Get-ChildItem -Path $buildDir -Recurse -Filter $name | Select-Object -First 1
        if (-not $altLib) { throw "$name missing after MSVC build" }
        $from = $altLib.FullName
    }
    $dest = Join-Path $linkDir $name
    if ([IO.Path]::GetFullPath($from) -ne [IO.Path]::GetFullPath($dest)) {
        Copy-Item $from $dest -Force
    }
}
$libDir = $linkDir
$env:BR_WINDOWS_CAPTURE_LIBDIR = "build-native/lib"
Write-Host "BR_WINDOWS_CAPTURE_LIBDIR=$env:BR_WINDOWS_CAPTURE_LIBDIR (relative; lld-safe)"

$fixture = Get-ChildItem -Path $buildDir -Recurse -Filter BlitzRecorderFixture.exe |
    Where-Object { $_.FullName -match "\\$cmakeConfig\\" -or $_.DirectoryName -match '\\bin$' } |
    Select-Object -First 1
if (-not $fixture) {
    throw "BlitzRecorderFixture.exe missing after MSVC build"
}
Write-Host "fixture=$($fixture.FullName)"

if ($NativeOnly) {
    return
}

$vcArch = if ($arch -eq "ARM64") { "arm64" } else { "x64" }
if (-not (Enter-MsvcDevCmd $vcArch)) {
    throw "vcvarsall failed; swift cannot link windowsapp.lib / mfplat.lib"
}
if (-not (Get-Command swift -ErrorAction SilentlyContinue)) {
    throw "swift missing from PATH after vcvars merge (CI must run setup-swift before build-studio.ps1)"
}

function Find-SdkTool([string]$exeName) {
    if (Get-Command $exeName -ErrorAction SilentlyContinue) {
        return (Get-Command $exeName).Source
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
    $vswhere = Get-VsWhere
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
                $candidate = Join-Path $dir "$arch\$exeName"
                if (Test-Path $candidate) { return $candidate }
                $nested = Join-Path $dir "bin\$arch\$exeName"
                if (Test-Path $nested) { return $nested }
            }
        }
    }
    return $null
}

$rc = Find-SdkTool "rc.exe"
if (-not $rc) { throw "rc.exe missing. Windows SDK is required to embed BlitzRecorder.ico into the exe." }
$ico = Join-Path $PackageRoot "BlitzRecorder.ico"
$rcFile = Join-Path $PackageRoot "app.rc"
if (-not (Test-Path $ico)) { throw "BlitzRecorder.ico missing" }
if (-not (Test-Path $rcFile)) { throw "app.rc missing" }
$res = Join-Path $libDir "BlitzRecorder.res"
Push-Location $PackageRoot
try {
    & $rc /nologo /fo $res $rcFile
} finally {
    Pop-Location
}
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $res)) { throw "rc.exe failed writing $res" }
Copy-Item $res (Join-Path $PackageRoot "BlitzRecorder.res") -Force
Write-Host "icon resource=$res"

$cvtres = Get-Command cvtres.exe -ErrorAction SilentlyContinue
$libExe = Get-Command lib.exe -ErrorAction SilentlyContinue
if (-not $cvtres) { throw "cvtres.exe missing after vcvars" }
if (-not $libExe) { throw "lib.exe missing after vcvars" }
$machine = "X64"
switch -Regex ($env:VSCMD_ARG_TGT_ARCH) {
    '^arm64$' { $machine = "ARM64" }
    '^x86$' { $machine = "X86" }
}
$resObj = Join-Path $libDir "BlitzRecorderRes.obj"
$resLib = Join-Path $libDir "BlitzRecorderRes.lib"
& $cvtres.Source /nologo "/MACHINE:$machine" "/OUT:$resObj" $res
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $resObj)) { throw "cvtres failed converting $res" }
& $libExe.Source /nologo "/OUT:$resLib" $resObj
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $resLib)) { throw "lib.exe failed wrapping BlitzRecorder.res" }
Write-Host "icon lib=$resLib (cvtres $machine)"

if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) {
    throw "cl.exe missing; cannot build br-link / embed_pe_resources"
}
Push-Location $PackageRoot
try {
    & cl.exe /nologo /O2 /EHsc /DUNICODE /D_UNICODE /Fe:br-link.exe br_link_wrap.cpp
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $PackageRoot "br-link.exe"))) {
        throw "cl.exe failed building br-link.exe"
    }
    & cl.exe /nologo /O2 /EHsc /DUNICODE /D_UNICODE /Fe:embed_pe_resources.exe embed_pe_resources.cpp
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $PackageRoot "embed_pe_resources.exe"))) {
        throw "cl.exe failed building embed_pe_resources.exe"
    }
} finally {
    Pop-Location
}
$env:PATH = "$PackageRoot;$env:PATH"

$swiftArgs = @("build")
if ($Configuration -eq "release") {
    $swiftArgs += @("-c", "release")
}

function Get-StudioExe {
    Get-ChildItem -Path (Join-Path $PackageRoot ".build") -Recurse -Filter BlitzRecorderWindows.exe |
        Where-Object { $_.FullName -match '\\release\\' -or ($Configuration -eq "debug" -and $_.FullName -match '\\debug\\') } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Invoke-PeGate([string]$exePath) {
    $manifest = Join-Path $PackageRoot "BlitzRecorderWindows.exe.manifest"
    $embed = Join-Path $PackageRoot "embed_pe_resources.exe"
    if (-not (Test-Path $embed)) { throw "embed_pe_resources.exe missing" }
    & $embed $exePath $ico $manifest
    if ($LASTEXITCODE -ne 0) { throw "embed_pe_resources failed ($LASTEXITCODE) for $exePath" }
    & (Join-Path $PSScriptRoot "embed-manifest.ps1") -ExePath $exePath -ManifestPath $manifest
    & (Join-Path $PSScriptRoot "assert-studio-pe.ps1") -ExePath $exePath
}

function Invoke-SwiftBuild([string[]]$extra) {
    $args = $swiftArgs + $extra
    Write-Host "swift $($args -join ' ')  (cwd=$PackageRoot)"
    Push-Location $PackageRoot
    try {
        # Native swift stdout must not become this function's return value or
        # `$exit -eq 0` is never true (and a green lld retry still throws).
        $nativeEA = $PSNativeCommandUseErrorActionPreference
        $PSNativeCommandUseErrorActionPreference = $false
        try {
            & swift @args | Out-Host
            return [int]$LASTEXITCODE
        } finally {
            $PSNativeCommandUseErrorActionPreference = $nativeEA
        }
    } finally {
        Pop-Location
    }
}

$peOk = $false
Write-Host "linking with MSVC link.exe first; lld-link splits /LIBPATH:D:\\ on the drive colon"
$exit = Invoke-SwiftBuild @(
    "-Xswiftc", "-use-ld=br-link",
    "-Xswiftc", "-debug-info-format=codeview",
    "-Xswiftc", "-gnone",
    "-Xlinker", "/MANIFEST:NO",
    "-Xlinker", "/MANIFESTUAC:NO"
)
if ($exit -eq 0) {
    $exe = Get-StudioExe
    if ($exe) {
        try {
            Invoke-PeGate $exe.FullName
            $peOk = $true
        } catch {
            Write-Host "PE gate failed after link.exe: $($_.Exception.Message)"
        }
    } else {
        Write-Host "BlitzRecorderWindows.exe missing after swift build (link.exe)"
    }
} else {
    Write-Host "swift build failed with link.exe (exit $exit)"
}

if (-not $peOk) {
    Write-Host "retrying default Swift linker (lld) with relative -L build-native/lib"
    $stale = Get-StudioExe
    if ($stale) {
        Remove-Item $stale.FullName -Force -ErrorAction SilentlyContinue
    }
    $exit = Invoke-SwiftBuild @(
        "-Xlinker", "/MANIFEST:NO",
        "-Xlinker", "/MANIFESTUAC:NO"
    )
    if ($exit -ne 0) { throw "swift build failed" }
    $exe = Get-StudioExe
    if (-not $exe) { throw "BlitzRecorderWindows.exe missing after swift build" }
    Invoke-PeGate $exe.FullName
}
