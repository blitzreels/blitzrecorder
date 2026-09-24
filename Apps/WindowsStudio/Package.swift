// swift-tools-version: 5.9
import PackageDescription

#if os(Windows)
/// Package.swift has no Foundation. Map path separators with stdlib only.
func brMapSlash(_ raw: String, from: Character, to: Character) -> String {
    String(raw.map { $0 == from ? to : $0 })
}

/// SwiftPM on Windows sometimes yields `/D:/Users/...`. Positional linker inputs
/// need `D:\Users\...`; a leading slash makes link.exe miss BlitzRecorder.res.
func brWindowsPath(_ raw: String) -> String {
    var path = raw
    if path.count >= 3 {
        let start = path.startIndex
        let driveColon = path.index(start, offsetBy: 2)
        if path[start] == "/", path[driveColon] == ":" {
            path.removeFirst()
        }
    }
    return brMapSlash(path, from: "/", to: "\\")
}

let windowsCaptureSkip = [
    "capture_common.cpp",
    "capture_abi.cpp",
    "capture_session.cpp",
    "compose_export.cpp",
    "dxgi_duplicator.cpp",
    "mf_camera.cpp",
    "mf_player.cpp",
    "mf_rgb32.cpp",
    "mf_sink.cpp",
    "monitor_list.cpp",
    "wasapi_capture.cpp",
    "wgc_capturer.cpp",
    "win32_shell.cpp",
    "webview_shell.cpp",
    "studio_dialogs.cpp",
    "windows_capture.cpp",
    "winui_shell.cpp",
    "studio_run.cpp",
    "fixture_main.cpp"
]
// Relative to the Swift cwd (build-studio.ps1 Push-Locations into this package).
// Absolute `D:\...` is poison: lld-link splits on the drive colon in
// `/LIBPATH:D:\...` and `/WHOLEARCHIVE:D:\...`. Ignore env values that contain `:`.
let nativeLibDirEnv = Context.environment["BR_WINDOWS_CAPTURE_LIBDIR"] ?? ""
let nativeLibDir = (!nativeLibDirEnv.isEmpty && !nativeLibDirEnv.contains(where: { $0 == ":" }))
    ? brMapSlash(nativeLibDirEnv, from: "\\", to: "/")
    : "build-native/lib"
// Basename only. Never pass BlitzRecorder.res as -Xlinker D:\... — lld-link
// splits on the drive colon. cvtres+lib.exe wrap the .res as this .lib.
let nativeLinkExe: [LinkerSetting] = [
    .unsafeFlags([
        "-L", nativeLibDir,
        "-Xlinker", "/WHOLEARCHIVE:WindowsCaptureNative.lib",
        "-Xlinker", "/WHOLEARCHIVE:WindowsCaptureAdapter.lib",
        "-Xlinker", "/WHOLEARCHIVE:WindowsStudioShell.lib",
        "-Xlinker", "/WHOLEARCHIVE:BlitzRecorderRes.lib",
        "-Xlinker", "/INCLUDE:br_capture_start",
        "-Xlinker", "/INCLUDE:br_capture_stop",
        "-Xlinker", "/INCLUDE:br_capture_alive",
        "-Xlinker", "/INCLUDE:br_capture_last_error",
        "-Xlinker", "/INCLUDE:br_set_last_error",
        "-Xlinker", "/INCLUDE:br_studio_run",
        "-Xlinker", "/INCLUDE:br_export_composed_fixture",
        "-Xlinker", "/INCLUDE:br_compose_take",
        "-Xlinker", "/INCLUDE:br_player_open_take",
        "-Xlinker", "/INCLUDE:br_player_tick",
        "-Xlinker", "/INCLUDE:br_player_close",
        "-Xlinker", "/INCLUDE:br_player_set_paused",
        "-Xlinker", "/INCLUDE:br_attach_parent_console",
        "-Xlinker", "/INCLUDE:br_last_video_encoder",
        // Swift @main emits `main`. WINDOWS CRT without /ENTRY looks for wWinMain.
        "-Xlinker", "/SUBSYSTEM:WINDOWS",
        "-Xlinker", "/ENTRY:mainCRTStartup",
        // Last: stop Swift's default RT_MANIFEST from fighting app.rc (icon + XAML Islands).
        "-Xlinker", "/MANIFEST:NO",
        "-Xlinker", "/MANIFESTUAC:NO"
    ]),
    .linkedLibrary("WindowsCaptureNative"),
    .linkedLibrary("WindowsCaptureAdapter"),
    .linkedLibrary("WindowsStudioShell"),
    .linkedLibrary("WebView2Loader"),
    .linkedLibrary("BlitzRecorderRes")
]
#else
let windowsCaptureSkip: [String] = ["spm_link_placeholder.cpp", "fixture_main.cpp"]
let nativeLinkExe: [LinkerSetting] = []
#endif

let windowsLibs: [LinkerSetting] = [
    .linkedLibrary("d3d11", .when(platforms: [.windows])),
    .linkedLibrary("dxgi", .when(platforms: [.windows])),
    .linkedLibrary("d3dcompiler", .when(platforms: [.windows])),
    .linkedLibrary("mf", .when(platforms: [.windows])),
    .linkedLibrary("mfplat", .when(platforms: [.windows])),
    .linkedLibrary("mfreadwrite", .when(platforms: [.windows])),
    .linkedLibrary("mfuuid", .when(platforms: [.windows])),
    .linkedLibrary("ole32", .when(platforms: [.windows])),
    .linkedLibrary("oleaut32", .when(platforms: [.windows])),
    .linkedLibrary("avrt", .when(platforms: [.windows])),
    .linkedLibrary("uuid", .when(platforms: [.windows])),
    .linkedLibrary("user32", .when(platforms: [.windows])),
    .linkedLibrary("gdi32", .when(platforms: [.windows])),
    .linkedLibrary("comctl32", .when(platforms: [.windows])),
    .linkedLibrary("dwmapi", .when(platforms: [.windows])),
    .linkedLibrary("shcore", .when(platforms: [.windows])),
    .linkedLibrary("shell32", .when(platforms: [.windows])),
    .linkedLibrary("mmdevapi", .when(platforms: [.windows])),
    .linkedLibrary("windowsapp", .when(platforms: [.windows])),
    .linkedLibrary("runtimeobject", .when(platforms: [.windows]))
]

let package = Package(
    name: "BlitzRecorderWindows",
    products: [
        .executable(name: "BlitzRecorderWindows", targets: ["BlitzRecorderWindows"])
    ],
    dependencies: [
        .package(path: "../../Packages/BlitzRecorderDomain")
    ],
    targets: [
        .target(
            name: "WindowsCapture",
            path: "Sources/WindowsCapture",
            exclude: windowsCaptureSkip,
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("."),
                .define("NOMINMAX", .when(platforms: [.windows])),
                .define("UNICODE", .when(platforms: [.windows])),
                .define("_UNICODE", .when(platforms: [.windows])),
                .define("NTDDI_VERSION", to: "0x0A00000C", .when(platforms: [.windows])),
                .define("WINVER", to: "0x0A00", .when(platforms: [.windows])),
                .define("_WIN32_WINNT", to: "0x0A00", .when(platforms: [.windows]))
            ],
            linkerSettings: windowsLibs
        ),
        .executableTarget(
            name: "BlitzRecorderWindows",
            dependencies: [
                "WindowsCapture",
                .product(name: "BlitzRecorderDomain", package: "BlitzRecorderDomain")
            ],
            linkerSettings: nativeLinkExe + windowsLibs
        )
    ],
    cxxLanguageStandard: .cxx17
)
