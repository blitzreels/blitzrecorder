# BlitzRecorder Windows Studio

Win32 Swift executable with a WinUI XAML Islands shell (Win32 fallback):

- Screen: **Windows Graphics Capture** (`CreateForMonitor` + `CreateFreeThreaded`), DXGI Desktop Duplication fallback
- Audio: WASAPI loopback + microphone
- Camera: Media Foundation
- Export: D3D11 compose (WARP fallback) + Media Foundation H.264/AAC. Hardware encoder preference is NVENC → AMF → QSV → other MF hardware → Microsoft software
- Playback: parallel screen + camera PIP + mixed mic/system AAC
- Take JSON: `BlitzRecorderDomain` (`take.json`, `project.blitzrecorder.json`)

No Apple frameworks, no GPL encoders, no Continuity Camera / Liquid Glass / FluidAudio.

Requires **Windows 10 version 2004** (build 19041) for WGC free-threaded capture; 1903 still runs via DXGI fallback.

## Build

Install the [Swift toolchain for Windows](https://www.swift.org/install/windows/) (6.3+) **and** Visual Studio 2022 C++ (MSVC + Windows 10/11 SDK). Capture/WGC/WinUI are compiled with **MSVC via CMake**, then linked by Swift. SPM clang-cl does not compile those WinRT headers.

From Developer PowerShell at the repo root:

```powershell
.\Scripts\windows\build-studio.ps1 -Configuration release
```

That writes `Apps\WindowsStudio\build-native\lib\WindowsCaptureNative.lib` and the Swift exe under `Apps\WindowsStudio\.build\`. `build-studio.ps1` then embeds `BlitzRecorderWindows.exe.manifest` (`maxversiontested`) into the exe with `mt.exe` — a sidecar is ignored if Swift already stamped an embedded manifest, and XAML Islands will not start without it.

Copy `BlitzRecorderWindows.exe.manifest` next to the exe (XAML Islands needs `maxversiontested`). Stage a runnable tree with:

```powershell
.\Scripts\windows\stage-studio.ps1 -PackageRoot Apps\WindowsStudio -StageDir build\windows-stage
```

On macOS, `swift build --package-path Apps/WindowsStudio` links C ABI stubs only. Capture, compose, WinUI, and playback only run on Windows.

## Run

```powershell
Apps\WindowsStudio\.build\release\BlitzRecorderWindows.exe
Apps\WindowsStudio\.build\release\BlitzRecorderWindows.exe --output $env:USERPROFILE\Videos\BlitzRecorder --monitor 0
Apps\WindowsStudio\.build\release\BlitzRecorderWindows.exe --headless
Apps\WindowsStudio\.build\release\BlitzRecorderWindows.exe --export-fixture $env:TEMP\blitz-fixture
Apps\WindowsStudio\.build\release\BlitzRecorderWindows.exe --play $env:TEMP\blitz-fixture
```

Default output is the OS Movies/Videos folder (`Videos\BlitzRecorder` on most PCs; the Ready line shows the real path). Microphone and system audio are on unless `--no-mic` / `--no-system-audio`. Camera is off unless `--camera`.

The studio window has **Start** / **Stop** / **Open take** / **Export last**, plus checkboxes for system audio (on), microphone (on), and camera. WinUI XAML Islands is tried first; if it fails, the Win32 window is used; if that fails, the process falls back to console: `start`, `stop`, `quit`.

Each Start creates `take-YYYYMMDD-HHMMSS\` containing:

| File | Contents |
| --- | --- |
| `take.json` | `{ "id", "createdAt" }` |
| `project.blitzrecorder.json` | version 1 sources, cuts, scene layout |
| `screen.mp4` | H.264 monitor capture |
| `camera.mp4` | H.264 webcam, if enabled |
| `audio.m4a` | AAC microphone, if enabled |
| `system-audio.m4a` | AAC WASAPI loopback, if enabled |

`--export-fixture DIR` writes those plus composed `export.mp4` (D3D11, WARP fallback) without a desktop session. CI runs that on **`windows-11-vs2026-arm`** (Win11 client + MSVC; the `windows-11-arm` label has no Visual Studio until the Sept 2026 image migration). Microsoft's inbox H.264 encoder (`mfh264enc.dll`) is client-only — GitHub's `windows-2025` image is Server and cannot software-encode H.264. The ARM job builds `BlitzRecorderFixture.exe` with `-NativeOnly` (compose/player/H.264 only — no WGC/WinUI). `build-studio.ps1` prefers Ninja + `vcvarsall` (no CMake 4.2 VS 18 generator name); VS generators are fallback. x64 Swift app compile runs on `windows-2025-vs2026` and WHOLEARCHIVEs `WindowsCaptureNative.lib` + `WindowsCaptureAdapter.lib` + `WindowsStudioShell.lib`. `build-studio.ps1` then asserts the PE subsystem is WINDOWS GUI. After staging, CI launches `--help` so a missing Swift/CRT DLL fails the job. If the WinUI XAML Islands probe fails, the shell is Win32-only.

`--export TAKE_DIR` composes `screen.mp4` + `camera.mp4` into `export.mp4` with D3D11 (WARP/CPU fallback), applies `project.blitzrecorder.json` cuts to video and muxed `audio.m4a` + `system-audio.m4a`, and uses the project scene layout.

The GUI lets testers pick **Screen** (full display; WGC + DXGI fallback), **Area** (drag-rect crop of that display), or **Window** (WGC `CreateForWindow`, no DXGI). Same DXGI monitor order as before. Live preview and Open take compose camera PiP with D3D11 (CPU fallback) using the same 0.68/0.68/0.28/0.28 rect Domain writes. Hardware encode binds the Sink Writer to NVIDIA → AMD → Intel DXGI adapters (`MF_SINK_WRITER_D3D_MANAGER`) before Microsoft software H.264.

## Installer and signing

`Scripts/windows/BlitzRecorder.iss` builds an Inno Setup installer from `build/windows-stage`: exe (`/SUBSYSTEM:WINDOWS` + `/ENTRY:mainCRTStartup` — Swift emits `main`, no console flash), Swift runtime DLLs, app-local VC++ CRT (`vcruntime140*.dll` / `msvcp140*.dll`), `d3dcompiler_47.dll` (D3D11 compose), and the application manifest. Install is per-user (`{localappdata}\Programs\BlitzRecorder`); testers do not need admin. No machine-wide VC++ redist required.

`.github/workflows/windows-release.yml` on `v*` tags:

1. Builds the Windows package
2. Stages exe + runtime
3. **Fails** if Azure Artifact Signing secrets are missing
4. Signs PE files
5. Builds the installer and signs it
6. Attaches **only** `BlitzRecorder-Windows.exe` to the GitHub Release

workflow_dispatch builds `BlitzRecorder-Windows-unsigned.exe` as a CI artifact only. Testers install the signed `BlitzRecorder-Windows.exe` from GitHub Releases.

Unsigned local/CI artifacts trip SmartScreen (**More info** → **Run anyway**). After a `main` push, download Actions artifact **`windows-studio-installer-unsigned`** (`BlitzRecorder-Windows-ci-check.exe`, per-user Inno, same layout as the tagged installer) or **`windows-studio-portable`** (folder; run `BlitzRecorder.cmd`). Neither is a GitHub Release.

Tagged builds sign with **either**:

1. Azure Artifact Signing (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_SIGNING_ENDPOINT`, `AZURE_SIGNING_ACCOUNT`, `AZURE_SIGNING_PROFILE`). The workflow identity needs the Artifact Signing Certificate Profile Signer role. ~$10/mo, paid Azure sub, identity verification.
2. An OV Authenticode PFX (`WINDOWS_PFX_BASE64` + `WINDOWS_PFX_PASSWORD`). `signtool` + DigiCert timestamp. No Azure. USB EV tokens are not used.

A self-signed PFX is not enough — tag verify requires Authenticode `Valid`.

## Permissions and session

- **Screen recording:** denied fails Start and opens Settings.
- **Microphone:** denied fails Start (checkbox on by default) and opens Settings.
- **Camera:** off by default. If enabled and denied, Start continues without camera after a short wait.
- **System audio:** WASAPI loopback, no consent dialog. Exclusive-mode apps are missing from the mix.
- **Windows Graphics Capture** needs an interactive desktop. First use can show the capture border. DXGI Desktop Duplication is the fallback (not Session 0, not lock/UAC secure desktop, not WARP).
- Headless CI cannot prove live capture; it proves fixture encode + parallel decode.
- Windows **N / KN** needs the [Media Feature Pack](https://support.microsoft.com/windows/media-feature-pack-for-windows-n).
