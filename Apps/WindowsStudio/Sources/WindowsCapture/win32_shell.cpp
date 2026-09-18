#if defined(_WIN32)

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

#include "win32_shell.h"

#include "capture_common.h"
#include "monitor_list.h"
#include "studio_dialogs.h"
#include "windows_capture.h"

#include <algorithm>
#include <cstring>
#include <string>
#include <vector>

#include <windows.h>
#include <windowsx.h>
#include <commctrl.h>
#include <roapi.h>

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "gdi32.lib")

namespace {

constexpr int kStart = 1001;
constexpr int kStop = 1002;
constexpr int kOpen = 1003;
constexpr int kSys = 1004;
constexpr int kMic = 1005;
constexpr int kCam = 1006;
constexpr int kStatus = 1007;
constexpr int kPreview = 1008;
constexpr int kExport = 1009;
constexpr int kMonitor = 1010;
constexpr UINT kPreviewTimer = 1;

struct StudioState {
    std::string outputRoot;
    int monitor = 0;
    br_prepare_take_fn prepare = nullptr;
    void* ctx = nullptr;
    HWND window = nullptr;
    HWND preview = nullptr;
    HWND status = nullptr;
    HWND monitors = nullptr;
    bool recording = false;
    bool starting = false;
    bool playing = false;
    bool paused = false;
    std::string lastTake;
    std::vector<br::CaptureTarget> targets;
    std::vector<unsigned char> pixels;
    unsigned int pixelW = 0;
    unsigned int pixelH = 0;
};

StudioState gState;

void startCapture();
void stopCapture();

void setStatus(const char* text) {
    if (gState.status) {
        const std::wstring wide = br::utf8ToWide(text);
        SetWindowTextW(gState.status, wide.c_str());
    }
}

void setTransportButtons(bool recording, bool busy) {
    if (!gState.window) {
        return;
    }
    EnableWindow(GetDlgItem(gState.window, kStart), !recording && !busy);
    EnableWindow(GetDlgItem(gState.window, kStop), recording && !busy);
    EnableWindow(GetDlgItem(gState.window, kOpen), !recording && !busy);
    EnableWindow(GetDlgItem(gState.window, kExport), !recording && !busy);
}

bool checked(HWND window, int id) {
    return IsDlgButtonChecked(window, id) == BST_CHECKED;
}

void paintPreview(HWND hwnd) {
    PAINTSTRUCT ps{};
    HDC hdc = BeginPaint(hwnd, &ps);
    RECT rc{};
    GetClientRect(hwnd, &rc);
    FillRect(hdc, &rc, reinterpret_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)));
    if (!gState.pixels.empty() && gState.pixelW > 0 && gState.pixelH > 0) {
        BITMAPINFO info{};
        info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        info.bmiHeader.biWidth = static_cast<LONG>(gState.pixelW);
        info.bmiHeader.biHeight = -static_cast<LONG>(gState.pixelH);
        info.bmiHeader.biPlanes = 1;
        info.bmiHeader.biBitCount = 32;
        info.bmiHeader.biCompression = BI_RGB;
        int x = 0;
        int y = 0;
        int w = 0;
        int h = 0;
        br::letterboxDest(rc.right - rc.left, rc.bottom - rc.top, gState.pixelW, gState.pixelH, x, y, w, h);
        SetStretchBltMode(hdc, HALFTONE);
        SetBrushOrgEx(hdc, 0, 0, nullptr);
        StretchDIBits(
            hdc,
            x,
            y,
            w,
            h,
            0,
            0,
            static_cast<int>(gState.pixelW),
            static_cast<int>(gState.pixelH),
            gState.pixels.data(),
            &info,
            DIB_RGB_COLORS,
            SRCCOPY
        );
    }
    EndPaint(hwnd, &ps);
}

LRESULT CALLBACK previewProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    if (msg == WM_PAINT) {
        paintPreview(hwnd);
        return 0;
    }
    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

void growPreviewBuffer(unsigned int width, unsigned int height) {
    const size_t need = static_cast<size_t>(width) * height * 4;
    const size_t want = (std::max)(7680ull * 4320ull * 4ull, need);
    if (gState.pixels.size() < want) {
        gState.pixels.resize(want);
    }
}

void onTransportKey(WPARAM vk) {
    if (gState.starting) {
        return;
    }
    if (vk == VK_ESCAPE && gState.recording) {
        stopCapture();
        return;
    }
    if (vk != VK_SPACE) {
        return;
    }
    const HWND focus = GetFocus();
    if (focus && gState.monitors && (focus == gState.monitors || IsChild(gState.monitors, focus))) {
        return;
    }
    if (gState.recording) {
        stopCapture();
    } else if (gState.playing) {
        gState.paused = !gState.paused;
        br_player_set_paused(gState.paused ? 1 : 0);
        setStatus(gState.paused ? "paused" : "playing take");
    } else {
        startCapture();
    }
}

void refreshPreview() {
    unsigned int width = 0;
    unsigned int height = 0;
    int64_t takeHns = 0;
    int ended = 0;
    growPreviewBuffer(gState.pixelW, gState.pixelH);
    auto copyOrTick = [&] {
        if (gState.recording) {
            if (!br_capture_alive()) {
                stopCapture();
                return;
            }
            if (br_capture_copy_preview(gState.pixels.data(), static_cast<unsigned int>(gState.pixels.size()), &width, &height) == 0) {
                gState.pixelW = width;
                gState.pixelH = height;
            } else if (width >= 2 && height >= 2) {
                growPreviewBuffer(width, height);
                if (br_capture_copy_preview(gState.pixels.data(), static_cast<unsigned int>(gState.pixels.size()), &width, &height) == 0) {
                    gState.pixelW = width;
                    gState.pixelH = height;
                }
            }
        } else if (gState.playing && !gState.paused) {
            if (br_player_tick(gState.pixels.data(), static_cast<unsigned int>(gState.pixels.size()), &width, &height, &takeHns, &ended) == 0) {
                gState.pixelW = width;
                gState.pixelH = height;
            } else if (!ended && width >= 2 && height >= 2) {
                growPreviewBuffer(width, height);
                if (br_player_tick(gState.pixels.data(), static_cast<unsigned int>(gState.pixels.size()), &width, &height, &takeHns, &ended) == 0) {
                    gState.pixelW = width;
                    gState.pixelH = height;
                }
            }
            if (ended) {
                gState.playing = false;
                gState.paused = false;
                br_player_set_paused(1);
                setStatus("playback finished");
            }
        }
    };
    copyOrTick();
    if (gState.preview) {
        InvalidateRect(gState.preview, nullptr, FALSE);
    }
}

void fillTargets() {
    if (!gState.monitors) {
        return;
    }
    void* prevHwnd = nullptr;
    int prevMonitor = gState.monitor;
    bool prevArea = false;
    if (gState.monitor >= 0 && static_cast<size_t>(gState.monitor) < gState.targets.size()) {
        prevHwnd = gState.targets[static_cast<size_t>(gState.monitor)].hwnd;
        prevMonitor = gState.targets[static_cast<size_t>(gState.monitor)].monitorIndex;
        prevArea = gState.targets[static_cast<size_t>(gState.monitor)].area;
    }
    gState.targets = br::listCaptureTargets(gState.window);
    ComboBox_ResetContent(gState.monitors);
    int select = 0;
    for (size_t i = 0; i < gState.targets.size(); ++i) {
        const br::CaptureTarget& target = gState.targets[i];
        ComboBox_AddString(gState.monitors, br::utf8ToWide(target.label).c_str());
        if (prevHwnd && target.hwnd == prevHwnd) {
            select = static_cast<int>(i);
        } else if (!prevHwnd && !target.hwnd && target.monitorIndex == prevMonitor && target.area == prevArea) {
            select = static_cast<int>(i);
        }
    }
    if (gState.targets.empty()) {
        ComboBox_AddString(gState.monitors, L"Screen · Primary");
        br::CaptureTarget fallback;
        fallback.label = "Screen · Primary";
        gState.targets.push_back(fallback);
    }
    ComboBox_SetCurSel(gState.monitors, select);
    gState.monitor = select;
}

void startCapture() {
    if (gState.recording || gState.starting || !gState.prepare) {
        return;
    }
    struct Starting {
        bool& flag;
        explicit Starting(bool& f) : flag(f) { flag = true; }
        ~Starting() { flag = false; }
    } starting(gState.starting);
    br_player_close();
    gState.playing = false;
    gState.paused = false;
    setTransportButtons(false, true);
    setStatus("starting…");
    fillTargets();
    if (gState.monitors) {
        const int selected = ComboBox_GetCurSel(gState.monitors);
        if (selected >= 0) {
            gState.monitor = selected;
        }
    }
    int monitorIndex = gState.monitor;
    void* hwnd = nullptr;
    bool area = false;
    if (gState.monitor >= 0 && static_cast<size_t>(gState.monitor) < gState.targets.size()) {
        monitorIndex = gState.targets[static_cast<size_t>(gState.monitor)].monitorIndex;
        hwnd = gState.targets[static_cast<size_t>(gState.monitor)].hwnd;
        area = gState.targets[static_cast<size_t>(gState.monitor)].area;
    }
    int cropX = 0;
    int cropY = 0;
    int cropW = 0;
    int cropH = 0;
    if (area && !hwnd) {
        if (!pickCaptureArea(gState.window, monitorIndex, cropX, cropY, cropW, cropH)) {
            setTransportButtons(false, false);
            setStatus("area cancelled");
            return;
        }
    }
    char takeDir[4096] = {0};
    const int mic = checked(gState.window, kMic) ? 1 : 0;
    const int systemAudio = checked(gState.window, kSys) ? 1 : 0;
    const int camera = checked(gState.window, kCam) ? 1 : 0;
    {
        const long screenHr = br::primeGraphicsCaptureConsent(monitorIndex, hwnd);
        if (br::isConsentDenied(screenHr)) {
            br::setLastError("Screen recording permission denied. Allow Screen recording in Windows Settings > Privacy.");
            br::openSettingsUri(L"ms-settings:privacy-graphicscapture");
            setTransportButtons(false, false);
            setStatus(br_capture_last_error());
            return;
        }
    }
    if (mic) {
        const long primeHr = br::primeMicrophoneConsent();
        if (br::isConsentDenied(primeHr)) {
            br::setLastError("Microphone permission denied. Allow Microphone in Windows Settings > Privacy.");
            br::openSettingsUri(L"ms-settings:privacy-microphone");
            setTransportButtons(false, false);
            setStatus(br_capture_last_error());
            return;
        }
    }
    const int prepared = gState.prepare(
        gState.outputRoot.c_str(),
        mic,
        systemAudio,
        camera,
        takeDir,
        static_cast<int>(sizeof(takeDir)),
        gState.ctx
    );
    if (prepared != 0 || !takeDir[0]) {
        if (!gState.window || !IsWindow(gState.window)) {
            return;
        }
        setTransportButtons(false, false);
        setStatus(br_capture_last_error()[0] ? br_capture_last_error() : "could not create take folder");
        return;
    }
    const int code = br_capture_start(
        takeDir,
        monitorIndex,
        systemAudio,
        mic,
        camera,
        hwnd,
        cropX,
        cropY,
        cropW,
        cropH
    );
    if (code != 0) {
        if (!gState.window || !IsWindow(gState.window)) {
            return;
        }
        setTransportButtons(false, false);
        setStatus(br_capture_last_error());
        return;
    }
    if (!gState.window || !IsWindow(gState.window)) {
        br_capture_stop();
        return;
    }
    gState.recording = true;
    gState.playing = false;
    gState.lastTake = takeDir;
    setTransportButtons(true, false);
    std::string status = "recording ";
    status += takeDir;
    if (br_capture_last_error()[0]) {
        status += " — ";
        status += br_capture_last_error();
    }
    setStatus(status.c_str());
}

void stopCapture() {
    const int code = br_capture_stop();
    gState.recording = false;
    setTransportButtons(false, false);
    if (code != 0) {
        setStatus(br_capture_last_error()[0] ? br_capture_last_error() : "stop failed");
        return;
    }
    if (!gState.lastTake.empty() && br::openTakePlayback(gState.lastTake.c_str()) == 0) {
        gState.playing = true;
        gState.paused = false;
        if (br_capture_last_error()[0]) {
            std::string status = "playing last take — ";
            status += br_capture_last_error();
            setStatus(status.c_str());
        } else {
            setStatus("playing last take");
        }
        return;
    }
    setStatus(gState.lastTake.empty() ? "stopped" : "stopped — Open take to play");
}

void exportLast() {
    if (gState.recording || gState.starting) {
        setStatus(gState.starting ? "wait — capture is starting" : "stop recording first");
        return;
    }
    br_player_close();
    gState.playing = false;
    if (gState.lastTake.empty()) {
        if (!pickTakeDirectory(gState.window, gState.lastTake, gState.outputRoot.c_str())) {
            return;
        }
    }
    std::string take;
    if (!br::resolveTakeDirectory(gState.lastTake.c_str(), take)) {
        setStatus(br_capture_last_error());
        return;
    }
    gState.lastTake = take;
    const std::string screen = br::joinUtf8Path(gState.lastTake, "screen.mp4");
    const std::string camera = br::joinUtf8Path(gState.lastTake, "camera.mp4");
    const std::string exported = br::joinUtf8Path(gState.lastTake, "export.mp4");
    const char* cameraArg = br::fileExistsUtf8(camera.c_str()) ? camera.c_str() : "";
    double pipX = 0.68;
    double pipY = 0.68;
    double pipW = 0.28;
    double pipH = 0.28;
    br::readCameraPip(gState.lastTake.c_str(), pipX, pipY, pipW, pipH);
    if (br_compose_take(screen.c_str(), cameraArg, exported.c_str(), pipX, pipY, pipW, pipH) != 0) {
        setStatus(br_capture_last_error());
        return;
    }
    std::string status = "exported ";
    const char* encoder = br_last_video_encoder();
    status += encoder && encoder[0] ? encoder : "H.264";
    if (br_capture_last_error()[0]) {
        status += " — ";
        status += br_capture_last_error();
    }
    setStatus(status.c_str());
}

void openTake() {
    if (gState.recording || gState.starting) {
        setStatus(gState.starting ? "wait — capture is starting" : "stop recording first");
        return;
    }
    std::string directory;
    const char* start = gState.lastTake.empty() ? gState.outputRoot.c_str() : gState.lastTake.c_str();
    if (!pickTakeDirectory(gState.window, directory, start)) {
        return;
    }
    std::string take;
    if (!br::resolveTakeDirectory(directory.c_str(), take)) {
        setStatus(br_capture_last_error());
        return;
    }
    br_player_close();
    if (br::openTakePlayback(take.c_str()) != 0) {
        setStatus(br_capture_last_error());
        return;
    }
    gState.lastTake = take;
    gState.playing = true;
    gState.paused = false;
    if (br_capture_last_error()[0]) {
        std::string status = "playing take — ";
        status += br_capture_last_error();
        setStatus(status.c_str());
    } else {
        setStatus("playing take");
    }
}

LRESULT CALLBACK wndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
    case WM_CREATE: {
        gState.window = hwnd;
        CreateWindowW(L"BUTTON", L"Start", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON, 16, 16, 110, 32, hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kStart)), nullptr, nullptr);
        CreateWindowW(L"BUTTON", L"Stop", WS_CHILD | WS_VISIBLE | WS_DISABLED | BS_PUSHBUTTON, 136, 16, 110, 32, hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kStop)), nullptr, nullptr);
        CreateWindowW(L"BUTTON", L"Open take", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON, 256, 16, 140, 32, hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kOpen)), nullptr, nullptr);
        CreateWindowW(L"BUTTON", L"Export last", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON, 406, 16, 120, 32, hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kExport)), nullptr, nullptr);
        CreateWindowW(L"BUTTON", L"System audio", WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX, 16, 60, 140, 24, hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kSys)), nullptr, nullptr);
        CreateWindowW(L"BUTTON", L"Microphone", WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX, 170, 60, 130, 24, hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kMic)), nullptr, nullptr);
        CreateWindowW(L"BUTTON", L"Camera", WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX, 310, 60, 110, 24, hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kCam)), nullptr, nullptr);
        gState.monitors = CreateWindowW(
            L"COMBOBOX",
            L"",
            CBS_DROPDOWNLIST | WS_CHILD | WS_VISIBLE | WS_VSCROLL,
            16,
            92,
            928,
            280,
            hwnd,
            reinterpret_cast<HMENU>(static_cast<INT_PTR>(kMonitor)),
            nullptr,
            nullptr
        );
        fillTargets();
        CheckDlgButton(hwnd, kSys, BST_CHECKED);
        CheckDlgButton(hwnd, kMic, BST_CHECKED);
        gState.status = CreateWindowW(L"STATIC", L"Ready", WS_CHILD | WS_VISIBLE, 16, 128, 900, 22, hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kStatus)), nullptr, nullptr);
        if (br_capture_last_error()[0]) {
            setStatus(br_capture_last_error());
        } else {
            std::string ready = "Ready — takes in ";
            ready += gState.outputRoot.empty() ? "Videos\\BlitzRecorder" : gState.outputRoot;
            setStatus(ready.c_str());
        }
        gState.preview = CreateWindowW(L"BlitzPreview", L"", WS_CHILD | WS_VISIBLE | WS_BORDER, 16, 156, 928, 430, hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kPreview)), nullptr, nullptr);
        SetTimer(hwnd, kPreviewTimer, 33, nullptr);
        br::excludeWindowFromCapture(hwnd);
        br::excludeWindowFromCapture(gState.preview);
        SetFocus(hwnd);
        return 0;
    }
    case WM_KEYDOWN:
        if (wParam == VK_SPACE || wParam == VK_ESCAPE) {
            onTransportKey(wParam);
            return 0;
        }
        break;
    case WM_COMMAND: {
        const int id = LOWORD(wParam);
        if (id == kMonitor && HIWORD(wParam) == CBN_DROPDOWN) {
            fillTargets();
        } else if (id == kStart) {
            startCapture();
        } else if (id == kStop) {
            stopCapture();
        } else if (id == kOpen) {
            openTake();
        } else if (id == kExport) {
            exportLast();
        }
        return 0;
    }
    case WM_TIMER:
        if (wParam == kPreviewTimer) {
            refreshPreview();
        }
        return 0;
    case WM_DESTROY:
        KillTimer(hwnd, kPreviewTimer);
        gState.window = nullptr;
        if (gState.recording) {
            br_capture_stop();
        }
        br_player_close();
        PostQuitMessage(0);
        return 0;
    default:
        break;
    }
    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

}  // namespace

int runStudioWindow(
    const char* outputRoot,
    int monitorIndex,
    int (*prepare)(const char*, int, int, int, char*, int, void*),
    void* ctx
) {
    if (!prepare) {
        return 1;
    }
    const HRESULT comHr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(comHr) && comHr != RPC_E_CHANGED_MODE && comHr != S_FALSE) {
        br::setLastError("CoInitializeEx STA failed", comHr);
        return 1;
    }
    RoInitialize(RO_INIT_SINGLETHREADED);
    INITCOMMONCONTROLSEX icc{};
    icc.dwSize = sizeof(icc);
    icc.dwICC = ICC_STANDARD_CLASSES;
    InitCommonControlsEx(&icc);
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);

    gState = {};
    gState.outputRoot = outputRoot ? outputRoot : "";
    gState.monitor = monitorIndex;
    gState.prepare = prepare;
    gState.ctx = ctx;

    WNDCLASSEXW previewClass{};
    previewClass.cbSize = sizeof(previewClass);
    previewClass.lpfnWndProc = previewProc;
    previewClass.hInstance = GetModuleHandleW(nullptr);
    previewClass.lpszClassName = L"BlitzPreview";
    previewClass.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    RegisterClassExW(&previewClass);

    HICON appIcon = LoadIconW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(101));
    WNDCLASSEXW wc{};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = wndProc;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpszClassName = L"BlitzRecorderStudio";
    wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.hIcon = appIcon;
    wc.hIconSm = appIcon;
    RegisterClassExW(&wc);

    gState.window = CreateWindowExW(
        0,
        L"BlitzRecorderStudio",
        L"BlitzRecorder",
        WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        976,
        640,
        nullptr,
        nullptr,
        GetModuleHandleW(nullptr),
        nullptr
    );
    if (!gState.window) {
        br::setLastError("Win32 studio window failed", HRESULT_FROM_WIN32(GetLastError()));
        return 1;
    }
    ShowWindow(gState.window, SW_SHOW);
    UpdateWindow(gState.window);
    br::hideOwnConsole();

    MSG msg{};
    while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    return 0;
}

#else
[[maybe_unused]] static int br_windows_capture_tu_shell = 0;
#endif
