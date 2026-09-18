#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

failures=0

pass() {
  printf 'ok: %s\n' "$1"
}

fail() {
  printf 'error: %s\n' "$1" >&2
  failures=$((failures + 1))
}

tracked_files() {
  git ls-files
}

reject_tracked_path() {
  local path="$1"
  if git ls-files --error-unmatch "$path" >/dev/null 2>&1; then
    fail "tracked local-only path: $path"
  else
    pass "not tracked: $path"
  fi
}

reject_tracked_glob() {
  local glob="$1"
  local matches
  matches="$(git ls-files "$glob")"
  if [[ -n "$matches" ]]; then
    fail "tracked local-only paths matching $glob"
    printf '%s\n' "$matches" >&2
  else
    pass "not tracked: $glob"
  fi
}

reject_literal() {
  local needle="$1"
  local label="$2"
  local matches
  matches="$(git grep -n -I -F -- "$needle" -- . ':!Scripts/check-repo-hygiene.sh' || true)"
  if [[ -n "$matches" ]]; then
    fail "$label"
    printf '%s\n' "$matches" >&2
  else
    pass "$label"
  fi
}

reject_regex() {
  local pattern="$1"
  local label="$2"
  local matches
  matches="$(git grep -n -I -E -- "$pattern" -- . ':!Scripts/check-repo-hygiene.sh' || true)"
  if [[ -n "$matches" ]]; then
    fail "$label"
    printf '%s\n' "$matches" >&2
  else
    pass "$label"
  fi
}

require_literal_in_file() {
  local file="$1"
  local needle="$2"
  if [[ ! -f "$file" ]]; then
    fail "missing file: $file"
  elif grep -Fq -- "$needle" "$file"; then
    pass "$file contains $needle"
  else
    fail "$file missing $needle"
  fi
}

reject_tracked_glob "docs/*"
reject_tracked_glob "Web/blitzrecorder/docs/*"
reject_tracked_path "CONTEXT.md"
reject_tracked_path "AppStore/CI.md"
reject_tracked_path "Scripts/check-open-source-readiness.sh"
reject_tracked_path "AG""ENTS.md"
reject_tracked_path "CLA""UDE.md"
reject_tracked_path "PRODUCT.md"
reject_tracked_glob "features/*"

reject_literal "blitzrecorder-public" "no stale public-repo URL"
reject_literal "not for the public repo" "no public-tree contradiction text"
reject_literal "private release handoff" "no private handoff language"
reject_literal "public snapshot" "no snapshot-publication language"
reject_literal "fresh-history" "no private-history publication language"
reject_literal "private history" "no private-history wording"
reject_literal "private repo" "no private-repo wording"
reject_literal "repo is private" "no private-repo status wording"
reject_literal "still private" "no stale private-status wording"
reject_literal "once public" "no stale publication-timing wording"
reject_literal "NEXT_PUBLIC_OPEN_SOURCE" "no open-source feature flag"

reject_regex 'price_1[[:alnum:]]{8,}' "no live Stripe price IDs"
reject_regex 'prod_[[:alnum:]]{8,}' "no live Stripe product IDs"

require_literal_in_file ".github/release.yml" "categories:"
require_literal_in_file ".github/workflows/macos-dmg.yml" "tags:"
require_literal_in_file ".github/workflows/macos-dmg.yml" "\"v*\""
require_literal_in_file ".github/workflows/macos-dmg.yml" "gh release create"
require_literal_in_file ".github/workflows/macos-dmg.yml" "--generate-notes"
require_literal_in_file ".github/workflows/macos-dmg.yml" "appcast.xml"
require_literal_in_file "Web/blitzrecorder/.env.example" "BLITZRECORDER_STRIPE_PRODUCT_ID="
require_literal_in_file "Web/blitzrecorder/.env.example" "BLITZRECORDER_STRIPE_PRICE_ID="
require_literal_in_file ".github/workflows/ci.yml" "windows-2025"
require_literal_in_file ".github/workflows/ci.yml" "windows-2025-vs2026"
require_literal_in_file ".github/workflows/ci.yml" "windows-11-vs2026-arm"
require_literal_in_file ".github/workflows/ci.yml" "stage-studio.ps1"
require_literal_in_file ".github/workflows/ci.yml" "ilammy/msvc-dev-cmd@v1"
require_literal_in_file ".github/workflows/windows-release.yml" "ilammy/msvc-dev-cmd@v1"
require_literal_in_file ".github/workflows/windows-release.yml" "tags:"
require_literal_in_file ".github/workflows/windows-release.yml" "\"v*\""
require_literal_in_file ".github/workflows/windows-release.yml" "AZURE_CLIENT_ID"
require_literal_in_file ".github/workflows/windows-release.yml" "WINDOWS_PFX_BASE64"
require_literal_in_file ".github/workflows/windows-release.yml" "method=pfx"
require_literal_in_file "Scripts/windows/sign-pe.ps1" "signtool"
require_literal_in_file "Scripts/windows/sign-pe.ps1" "Import-PfxCertificate"
require_literal_in_file ".github/workflows/windows-release.yml" "NotSigned"
require_literal_in_file ".github/workflows/windows-release.yml" "BlitzRecorder-Windows.exe"
require_literal_in_file ".github/workflows/windows-release.yml" "BlitzRecorder-Windows-unsigned"
require_literal_in_file ".github/workflows/windows-release.yml" "gh release create"
require_literal_in_file ".github/workflows/windows-release.yml" "gh release upload"
require_literal_in_file "Apps/WindowsStudio/CMakeLists.txt" "WindowsCaptureAdapter"
require_literal_in_file "Apps/WindowsStudio/CMakeLists.txt" "WindowsStudioShell"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/win32_shell.cpp" "Win32 studio window failed"
require_literal_in_file "Apps/WindowsStudio/CMakeLists.txt" "BR_BUILD_CAPTURE_ADAPTER"
require_literal_in_file "Apps/WindowsStudio/CMakeLists.txt" "GITHUB_ACTIONS"
require_literal_in_file "Apps/WindowsStudio/CMakeLists.txt" "CMAKE_TRY_COMPILE_TARGET_TYPE"
require_literal_in_file "Apps/WindowsStudio/CMakeLists.txt" "set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)"
require_literal_in_file "Apps/WindowsStudio/CMakeLists.txt" "/permissive-"
require_literal_in_file ".github/workflows/ci.yml" "workflow_dispatch:"
require_literal_in_file "Apps/WindowsStudio/Package.swift" "WindowsCaptureAdapter.lib"
require_literal_in_file "Apps/WindowsStudio/Package.swift" "/SUBSYSTEM:WINDOWS"
require_literal_in_file "Apps/WindowsStudio/Package.swift" "/INCLUDE:br_capture_alive"
require_literal_in_file "Apps/WindowsStudio/Package.swift" "/MANIFEST:NO"
require_literal_in_file "Apps/WindowsStudio/Package.swift" "/MANIFESTUAC:NO"
require_literal_in_file "Apps/WindowsStudio/app.rc" "IDI_APPICON 101"
require_literal_in_file "Apps/WindowsStudio/app.rc" "1 24"
require_literal_in_file "Apps/WindowsStudio/BlitzRecorderWindows.exe.manifest" "asInvoker"
require_literal_in_file "Apps/WindowsStudio/BlitzRecorderWindows.exe.manifest" "maxversiontested"
require_literal_in_file "Scripts/windows/assert-studio-pe.ps1" "GROUP_ICON"
require_literal_in_file "Scripts/windows/assert-studio-pe.ps1" "maxversiontested"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/mf_player.cpp" "800'000"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/win32_shell.cpp" "7680ull * 4320ull"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/mf_player.cpp" "presentPending"
require_literal_in_file "Apps/WindowsStudio/Package.swift" "/ENTRY:mainCRTStartup"
require_literal_in_file "Apps/WindowsStudio/Package.swift" "/WHOLEARCHIVE:BlitzRecorderRes.lib"
require_literal_in_file "Apps/WindowsStudio/Package.swift" "func brWindowsPath"
require_literal_in_file "Scripts/windows/build-studio.ps1" "-gnone"
require_literal_in_file "Apps/WindowsStudio/Package.swift" "func brMapSlash"
require_literal_in_file "Apps/WindowsStudio/Package.swift" "splits on the drive colon"
require_literal_in_file "Apps/WindowsStudio/Package.swift" 'contains(where: { $0 == ":" })'
require_literal_in_file "Scripts/windows/build-studio.ps1" "rc.exe"
require_literal_in_file "Scripts/windows/build-studio.ps1" "cvtres"
require_literal_in_file "Scripts/windows/build-studio.ps1" "embed_pe_resources"
require_literal_in_file "Scripts/windows/build-studio.ps1" "-use-ld=br-link"
require_literal_in_file "Scripts/windows/build-studio.ps1" "-debug-info-format=codeview"
require_literal_in_file "Scripts/windows/build-studio.ps1" "Out-Host"
require_literal_in_file "Scripts/windows/build-studio.ps1" "PSNativeCommandUseErrorActionPreference"
require_literal_in_file "Scripts/windows/build-studio.ps1" "PE gate failed"
require_literal_in_file "Scripts/windows/build-studio.ps1" "linking with MSVC link.exe first"
require_literal_in_file "Scripts/windows/build-studio.ps1" "BR_WINDOWS_CAPTURE_LIBDIR = \"build-native/lib\""
require_literal_in_file "Scripts/windows/build-studio.ps1" 'Push-Location $PackageRoot'
require_literal_in_file "Scripts/windows/build-studio.ps1" "cmake generator=Ninja first"
require_literal_in_file "Scripts/windows/msvc-env.ps1" "keep Swift PATH"
require_literal_in_file "Scripts/windows/BlitzRecorder.iss" "{localappdata}"
require_literal_in_file ".github/workflows/ci.yml" "windows-studio-x64"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/wgc_capturer.cpp" "CreateForWindow"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/studio_dialogs.cpp" "pickCaptureArea"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/mf_sink.cpp" "MF_SINK_WRITER_D3D_MANAGER"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/mf_sink.cpp" "MF_MT_MPEG2_PROFILE"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/mf_sink.cpp" "profileOptions"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/mf_sink.cpp" "hardware ? 4 : 1"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/mf_sink.cpp" "writer_->Finalize()"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/compose_export.cpp" "writePcmAt"
require_literal_in_file ".github/workflows/ci.yml" "BlitzRecorder-Windows-ci-check"
require_literal_in_file "Scripts/windows/compile-installer.ps1" "ISCC.exe"
require_literal_in_file "Scripts/windows/compile-installer.ps1" "Find-Iscc"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/capture_session.cpp" "privacy-graphicscapture"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/capture_session.cpp" "privacy-webcam"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/capture_session.cpp" "areaPickerW"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/mf_camera.cpp" "windows hello"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/capture_abi.cpp" "syncTakeSidecarsFromDisk"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/capture_common.cpp" "WDA_EXCLUDEFROMCAPTURE"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/capture_common.cpp" "eCommunications"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/include/windows_capture.h" "br_set_last_error"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/include/windows_capture.h" "br_player_set_paused"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/dxgi_duplicator.cpp" "DXGI_ERROR_ACCESS_DENIED"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/wgc_capturer.cpp" "ERROR_INVALID_WINDOW_HANDLE"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/wgc_capturer.cpp" "DWMWA_CLOAKED"
require_literal_in_file "Scripts/windows/BlitzRecorder.iss" "SetupIconFile"
require_literal_in_file "Scripts/windows/BlitzRecorder.iss" "AppUserModelID"
require_literal_in_file "Scripts/windows/BlitzRecorder.iss" "Ver >= 0x06020000"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/capture_session.cpp" "Graphics Capture or Desktop Duplication"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/capture_common.cpp" "BlitzReels.BlitzRecorder"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/capture_common.cpp" "letterboxDest"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/capture_common.cpp" "openMfSourceReader"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/capture_common.cpp" "MFCreateSourceReaderFromByteStream"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/capture_common.cpp" "openMfSinkWriter"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/capture_common.cpp" "MF_ACCESSMODE_READWRITE"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/capture_common.cpp" "resolveTakeDirectory"
require_literal_in_file "Sources/BlitzRecorderApp/RecordingProject.swift" "portableSceneLayout"
require_literal_in_file "Sources/BlitzRecorderApp/RecordingProject.swift" "importedPortable"
require_literal_in_file "Sources/BlitzRecorderApp/TakeFileStore.swift" "importedPortable"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/capture_common.cpp" "extractDomainScene"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/capture_common.cpp" "cameraFrame"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/capture_common.cpp" "keyIsFalse(\"enabled\")"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/capture_session.cpp" "readCameraPip"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/capture_session.cpp" "FAILED(micHr_)"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/capture_session.cpp" "micDeadline"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/capture_session.cpp" "0x887A002B"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/winui_shell.cpp" "IVector<IInspectable*>"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/winui_shell.cpp" "activateFactory(managerName.get()"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/winui_shell.cpp" "activateFactory(readerName.get()"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/winrt_interop.h" "IBrDirect3DDxgiInterfaceAccess"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/wgc_capturer.cpp" "ComPtr<IBrDirect3DDxgiInterfaceAccess>"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/winui_shell.cpp" "static_cast<int>(rc.right - rc.left)"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/winrt_interop.h" "BR_HAS_WGC_INTEROP_H"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/winui_shell.cpp" "add_DropDownOpened"
require_literal_in_file "Apps/WindowsStudio/CMakeLists.txt" "string(REPLACE \";\" \" \" _br_probe_cxx"
require_literal_in_file "Apps/WindowsStudio/cmake/winui_probe.cpp" "using ABI::Windows::UI::Xaml::Controls::IControl"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/winui_shell.cpp" "using ABI::Windows::UI::Xaml::Controls::IControl"
require_literal_in_file "Apps/WindowsStudio/cmake/winui_probe.cpp" "IVector<IInspectable*>"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/winui_shell.cpp" "add_GotFocus"
require_literal_in_file "Apps/WindowsStudio/cmake/winui_probe.cpp" "add_DropDownOpened"
require_literal_in_file "Apps/WindowsStudio/cmake/winui_probe.cpp" "add_GotFocus"
require_literal_in_file "Apps/WindowsStudio/cmake/winui_probe.cpp" "IWindowsXamlManagerStatics"
require_literal_in_file "Apps/WindowsStudio/cmake/winui_probe.cpp" "IXamlReaderStatics"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/winui_shell.cpp" "reader->Load(xaml.get(), tree.ReleaseAndGetAddressOf())"
require_literal_in_file "Scripts/windows/export-fixture.ps1" "decoded \\d+ parallel frames"
require_literal_in_file "Scripts/windows/export-fixture.ps1" '$exportCode'
require_literal_in_file "Scripts/windows/stage-studio.ps1" "BlitzRecorder.ico"
require_literal_in_file "Scripts/windows/stage-studio.ps1" "msvc-env.ps1"
require_literal_in_file "Scripts/windows/stage-studio.ps1" "BlitzRecorder.cmd"
require_literal_in_file "Scripts/windows/stage-studio.ps1" "READ_ME.txt"
require_literal_in_file "Scripts/windows/stage-studio.ps1" "UNSIGNED.txt"
require_literal_in_file "Scripts/windows/stage-studio.ps1" "msvcp140.dll"
require_literal_in_file "Scripts/windows/stage-studio.ps1" "Compress-Archive"
require_literal_in_file "Scripts/windows/build-studio.ps1" "msvc-env.ps1"
require_literal_in_file "Apps/WindowsStudio/Package.swift" "/INCLUDE:br_set_last_error"
require_literal_in_file "Apps/WindowsStudio/Package.swift" "/INCLUDE:br_attach_parent_console"
require_literal_in_file ".github/workflows/ci.yml" "BlitzRecorder-Windows-ci.zip"
require_literal_in_file ".github/workflows/ci.yml" "windows-studio-portable"
require_literal_in_file ".github/workflows/ci.yml" "windows-studio-installer-unsigned"
require_literal_in_file ".github/workflows/ci.yml" "BlitzRecorder-Windows-ci-check.exe"
require_literal_in_file "Apps/WindowsStudio/README.md" "windows-studio-portable"
require_literal_in_file "Apps/WindowsStudio/README.md" "windows-studio-installer-unsigned"
require_literal_in_file "Scripts/windows/BlitzRecorder.iss" "VersionInfoVersion"
require_literal_in_file "Scripts/windows/compile-installer.ps1" "ConvertTo-InnoVersion"
require_literal_in_file "Scripts/windows/assert-studio-tree.ps1" "BlitzRecorder.ico"
require_literal_in_file "Scripts/windows/assert-studio-tree.ps1" "winrt_interop.h"
require_literal_in_file "Scripts/windows/assert-studio-tree.ps1" "TakeFolderLayout.swift"
require_literal_in_file "Scripts/windows/assert-studio-tree.ps1" "msvc-env.ps1"
require_literal_in_file "Scripts/windows/assert-studio-tree.ps1" "mf_sink.h"
require_literal_in_file "Scripts/windows/assert-studio-tree.ps1" "wgc_capturer.h"
require_literal_in_file "Scripts/windows/assert-studio-tree.ps1" "capture_session.h"
require_literal_in_file "Scripts/windows/assert-studio-tree.ps1" "assert-studio-launches.ps1"
require_literal_in_file "Scripts/windows/assert-studio-launches.ps1" "--help"
require_literal_in_file ".github/workflows/ci.yml" "assert-studio-launches.ps1"
require_literal_in_file ".github/workflows/windows-release.yml" "assert-studio-launches.ps1"
require_literal_in_file ".github/workflows/windows-release.yml" "windows-2025-vs2026"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/capture_session.cpp" "silentGiveUp"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/capture_session.cpp" "dxgiSilent"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/compose_export.cpp" "(std::max)(1u, width / 8)"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/mf_sink.cpp" "SetCurrentLength((std::min)(size, maxLen))"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/wgc_capturer.cpp" "IID_PPV_ARGS(&unk)"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/wgc_capturer.cpp" "QueryInterface(IID_PPV_ARGS(&session3))"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/winui_shell.cpp" "QueryInterface(IID_PPV_ARGS(&fe))"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/wgc_capturer.cpp" "FAILED(hr) || !item"
require_literal_in_file "Apps/WindowsStudio/Sources/BlitzRecorderWindows/main.swift" "moviesDirectory"
require_literal_in_file "Scripts/windows/build-studio.ps1" "assert-studio-tree.ps1"
require_literal_in_file ".github/workflows/ci.yml" "assert-studio-tree.ps1"
require_literal_in_file ".github/workflows/windows-release.yml" "assert-studio-tree.ps1"
require_literal_in_file ".github/workflows/ci.yml" "swift missing after setup-swift"
require_literal_in_file ".github/workflows/windows-release.yml" "swift missing after setup-swift"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/wasapi_capture.cpp" "AUDCLNT_E_DEVICE_IN_USE"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/wasapi_capture.cpp" "inBits_ == 24"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/wgc_capturer.cpp" "CreateFreeThreaded"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/wgc_capturer.cpp" "pool.ReleaseAndGetAddressOf()"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/wgc_capturer.cpp" "TryGetNextFrame(frame.ReleaseAndGetAddressOf())"
require_literal_in_file "Apps/WindowsStudio/CMakeLists.txt" "LINK_LIBRARIES runtimeobject ole32 oleaut32 uuid"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/winui_shell.cpp" "(std::max)(1, width - 16)"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/winui_shell.cpp" "setBusyButtons"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/winui_shell.cpp" "gUi.starting"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/win32_shell.cpp" "setTransportButtons"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/winui_shell.cpp" "Ready — takes in "
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/win32_shell.cpp" "gState.starting"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/winui_shell.cpp" "excludeWindowFromCapture(gUi.preview)"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/win32_shell.cpp" "Ready — takes in "
require_literal_in_file "Scripts/windows/stage-studio.ps1" "folder shown as Ready"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/win32_shell.cpp" "excludeWindowFromCapture(gState.preview)"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/studio_dialogs.cpp" "excludeWindowFromCapture(overlay)"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/wasapi_capture.cpp" "(std::min)(index + 1, nativeFrames - 1)"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/wasapi_capture.cpp" "IID_PPV_ARGS(&enumerator)"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/wasapi_capture.cpp" "reinterpret_cast<void**>(client_.ReleaseAndGetAddressOf())"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/mf_player.cpp" "IID_PPV_ARGS(&enumerator)"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/monitor_list.cpp" "CreateDXGIFactory1(IID_PPV_ARGS(&factory))"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/mf_sink.cpp" "CreateDXGIFactory1(IID_PPV_ARGS(&factory))"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/winui_shell.cpp" "InitializeForCurrentThread(manager.ReleaseAndGetAddressOf())"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/winui_shell.cpp" "RoActivateInstance(sourceName.get(), sourceInspectable.ReleaseAndGetAddressOf())"
require_literal_in_file "Apps/WindowsStudio/cmake/winui_probe.cpp" "InitializeForCurrentThread(manager.ReleaseAndGetAddressOf())"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/wgc_capturer.cpp" "CreateCaptureSession(item.Get(), session.ReleaseAndGetAddressOf())"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/wgc_capturer.cpp" "get_Surface(surface.ReleaseAndGetAddressOf())"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/capture_common.cpp" "stream.ReleaseAndGetAddressOf()"
require_literal_in_file "Apps/WindowsStudio/Sources/BlitzRecorderWindows/main.swift" "ticks < 500"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/mf_camera.cpp" "reinterpret_cast<void**>(source_.ReleaseAndGetAddressOf())"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/compose_export.cpp" "createDevice(device.ReleaseAndGetAddressOf(), context.ReleaseAndGetAddressOf())"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/dxgi_duplicator.cpp" "DuplicateOutput(device_.Get(), duplication_.ReleaseAndGetAddressOf())"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/dxgi_duplicator.cpp" "AcquireNextFrame(timeoutMs, &frameInfo, resource.ReleaseAndGetAddressOf())"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/dxgi_duplicator.cpp" "pointerPixels_.size() < static_cast<size_t>(shapeH) * pitch"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/wgc_capturer.cpp" "device_.ReleaseAndGetAddressOf()"
require_literal_in_file "Apps/WindowsStudio/Sources/WindowsCapture/mf_sink.cpp" "MFCreateDXGIDeviceManager(&token, manager.ReleaseAndGetAddressOf())"
require_literal_in_file ".gitattributes" "*.ico binary"

# winbase.h Interlocked* + WRL become br::_InterlockedIncrement if included
# inside namespace br (MSVC C2664 on the ARM fixture).
while IFS= read -r file; do
  [[ -f "$file" ]] || continue
  if ! grep -Eq '#include <(windows\.h|wrl/)' "$file"; then
    continue
  fi
  if ! grep -Fq 'namespace br {' "$file"; then
    continue
  fi
  win_line="$(grep -nE '#include <(windows\.h|wrl/)' "$file" | head -1 | cut -d: -f1)"
  ns_line="$(grep -nF 'namespace br {' "$file" | head -1 | cut -d: -f1)"
  if [[ -z "$win_line" || -z "$ns_line" || "$win_line" -gt "$ns_line" ]]; then
    fail "$file includes Windows/WRL headers inside namespace br"
  else
    pass "$file includes Windows/WRL headers before namespace br"
  fi
done < <(git ls-files 'Apps/WindowsStudio/**/*.cpp' 'Apps/WindowsStudio/**/*.h')

if grep -Fq 'COMPILE_DEFINITIONS UNICODE' Apps/WindowsStudio/CMakeLists.txt; then
  fail "try_compile COMPILE_DEFINITIONS UNICODE is passed as extra source files on CMake 4.2"
else
  pass "try_compile does not pass bare UNICODE as COMPILE_DEFINITIONS"
fi

if git grep -F -q replacingOccurrences -- Apps/WindowsStudio/Package.swift; then
  fail "Package.swift cannot use Foundation replacingOccurrences"
else
  pass "Package.swift does not use Foundation replacingOccurrences"
fi

if grep -Fq -- ".zip" .github/workflows/windows-release.yml; then
  fail "windows-release.yml must not attach a zip"
else
  pass "windows-release.yml does not attach a zip"
fi

if (( failures > 0 )); then
  echo "Repository hygiene checks failed with $failures issue(s)." >&2
  exit 1
fi

echo "Repository hygiene checks passed."
