param(
    [string]$PackageRoot = "Apps/WindowsStudio",
    [switch]$NativeOnly
)

$ErrorActionPreference = "Stop"

if (-not [IO.Path]::IsPathRooted($PackageRoot)) {
    $PackageRoot = Join-Path (Get-Location) $PackageRoot
}
if (-not (Test-Path $PackageRoot)) {
    throw "Windows studio package missing: $PackageRoot"
}

$files = @(
    "CMakeLists.txt",
    "Sources/WindowsCapture/capture_common.cpp",
    "Sources/WindowsCapture/capture_common.h",
    "Sources/WindowsCapture/compose_export.cpp",
    "Sources/WindowsCapture/compose_export.h",
    "Sources/WindowsCapture/mf_player.cpp",
    "Sources/WindowsCapture/mf_player.h",
    "Sources/WindowsCapture/mf_rgb32.cpp",
    "Sources/WindowsCapture/mf_rgb32.h",
    "Sources/WindowsCapture/mf_sink.cpp",
    "Sources/WindowsCapture/mf_sink.h",
    "Sources/WindowsCapture/monitor_list.cpp",
    "Sources/WindowsCapture/monitor_list.h",
    "Sources/WindowsCapture/windows_capture.cpp",
    "Sources/WindowsCapture/fixture_main.cpp",
    "Sources/WindowsCapture/include/windows_capture.h"
)
if (-not $NativeOnly) {
    $files += @(
        "BlitzRecorder.ico",
        "app.rc",
        "BlitzRecorderWindows.exe.manifest",
        "embed_pe_resources.cpp",
        "br_link_wrap.cpp",
        "Package.swift",
        "Sources/BlitzRecorderWindows/main.swift",
        "Sources/WindowsCapture/capture_abi.cpp",
        "Sources/WindowsCapture/capture_session.cpp",
        "Sources/WindowsCapture/capture_session.h",
        "Sources/WindowsCapture/dxgi_duplicator.cpp",
        "Sources/WindowsCapture/dxgi_duplicator.h",
        "Sources/WindowsCapture/mf_camera.cpp",
        "Sources/WindowsCapture/mf_camera.h",
        "Sources/WindowsCapture/wasapi_capture.cpp",
        "Sources/WindowsCapture/wasapi_capture.h",
        "Sources/WindowsCapture/wgc_capturer.cpp",
        "Sources/WindowsCapture/wgc_capturer.h",
        "Sources/WindowsCapture/studio_run.cpp",
        "Sources/WindowsCapture/studio_dialogs.cpp",
        "Sources/WindowsCapture/studio_dialogs.h",
        "Sources/WindowsCapture/win32_shell.cpp",
        "Sources/WindowsCapture/win32_shell.h",
        "Sources/WindowsCapture/webview_shell.cpp",
        "Sources/WindowsCapture/webview_shell.h",
        "WebUI/index.html",
        "WebUI/workspace.css",
        "WebUI/workspace.js",
        "Sources/WindowsCapture/winui_shell.cpp",
        "Sources/WindowsCapture/winui_shell.h",
        "Sources/WindowsCapture/winrt_interop.h",
        "Sources/WindowsCapture/winrt_compat.h",
        "cmake/winui_probe.cpp"
    )
}

$missing = @()
foreach ($rel in $files) {
    if (-not (Test-Path (Join-Path $PackageRoot $rel))) {
        $missing += $rel
    }
}
$domainRoot = Join-Path $PackageRoot "..\..\Packages\BlitzRecorderDomain\Sources\BlitzRecorderDomain"
foreach ($rel in @(
    "TakeFolderLayout.swift",
    "MediaTime.swift",
    "TimelineCut.swift",
    "TimelineTimeMap.swift",
    "PortableSceneLayout.swift"
)) {
    $path = Join-Path $domainRoot $rel
    if (-not (Test-Path $path)) {
        $missing += "Packages/BlitzRecorderDomain/$rel"
    }
}
if (-not (Test-Path (Join-Path $PSScriptRoot "msvc-env.ps1"))) {
    $missing += "Scripts/windows/msvc-env.ps1"
}
if (-not $NativeOnly -and -not (Test-Path (Join-Path $PSScriptRoot "assert-studio-launches.ps1"))) {
    $missing += "Scripts/windows/assert-studio-launches.ps1"
}
if (-not $NativeOnly -and -not (Test-Path (Join-Path $PSScriptRoot "assert-installer-launches.ps1"))) {
    $missing += "Scripts/windows/assert-installer-launches.ps1"
}
if (-not $NativeOnly -and -not (Test-Path (Join-Path $PSScriptRoot "sign-pe.ps1"))) {
    $missing += "Scripts/windows/sign-pe.ps1"
}
if ($missing.Count -gt 0) {
    throw "Windows studio tree missing (commit the untracked Apps/WindowsStudio + Domain files): $($missing -join ', ')"
}

if (-not $NativeOnly) {
    $ico = Get-Item (Join-Path $PackageRoot "BlitzRecorder.ico")
    if ($ico.Length -lt 1024) {
        throw "BlitzRecorder.ico is too small ($($ico.Length) bytes)"
    }
}

Write-Host "windows tree ok ($($files.Count) files) NativeOnly=$NativeOnly"
