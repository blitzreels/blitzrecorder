#if defined(_WIN32)

#include "webview_shell.h"
#include "capture_common.h"
#include "monitor_list.h"
#include "studio_dialogs.h"
#include "windows_capture.h"

#include <WebView2.h>
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cwchar>
#include <filesystem>
#include <functional>
#include <string>
#include <vector>
#include <windows.h>
#include <wrl.h>

using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;

namespace {

constexpr UINT_PTR kPreviewTimer = 1;

struct Studio {
    std::string outputRoot;
    int selected = 0;
    br_prepare_take_fn prepare = nullptr;
    void* context = nullptr;
    HWND window = nullptr;
    HWND preview = nullptr;
    ComPtr<ICoreWebView2Controller> controller;
    ComPtr<ICoreWebView2> web;
    std::vector<br::CaptureTarget> targets;
    std::vector<std::string> takes;
    std::vector<unsigned char> pixels;
    unsigned width = 0;
    unsigned height = 0;
    RECT previewRect{};
    bool recording = false;
    bool starting = false;
    bool playing = false;
    bool paused = false;
    bool microphone = true;
    bool systemAudio = true;
    bool camera = false;
    bool browserReady = false;
    bool canvasVisible = true;
    std::string lastTake;
    std::string status = "Ready to record";
};

Studio g;

std::wstring executableDirectory() {
    std::wstring path(MAX_PATH, L'\0');
    DWORD count = GetModuleFileNameW(nullptr, path.data(), static_cast<DWORD>(path.size()));
    while (count == path.size()) {
        path.resize(path.size() * 2);
        count = GetModuleFileNameW(nullptr, path.data(), static_cast<DWORD>(path.size()));
    }
    path.resize(count);
    return std::filesystem::path(path).parent_path().wstring();
}

std::wstring escape(const std::string& value) {
    std::wstring result = L"\"";
    for (const wchar_t byte : br::utf8ToWide(value)) {
        if (byte == L'"' || byte == L'\\') {
            result += L'\\';
            result += byte;
        } else if (byte == L'\n') {
            result += L"\\n";
        } else if (byte == L'\r') {
            result += L"\\r";
        } else if (byte == L'\t') {
            result += L"\\t";
        } else if (byte < 0x20) {
            result += L' ';
        } else {
            result += byte;
        }
    }
    result += L'"';
    return result;
}

void postState() {
    if (!g.web) return;
    std::wstring json = L"{\"kind\":\"state\",\"status\":" + escape(g.status);
    json += L",\"recording\":" + std::wstring(g.recording ? L"true" : L"false");
    json += L",\"starting\":" + std::wstring(g.starting ? L"true" : L"false");
    json += L",\"playing\":" + std::wstring(g.playing ? L"true" : L"false");
    json += L",\"paused\":" + std::wstring(g.paused ? L"true" : L"false");
    json += L",\"microphone\":" + std::wstring(g.microphone ? L"true" : L"false");
    json += L",\"systemAudio\":" + std::wstring(g.systemAudio ? L"true" : L"false");
    json += L",\"camera\":" + std::wstring(g.camera ? L"true" : L"false");
    json += L",\"selected\":" + std::to_wstring(g.selected);
    json += L",\"lastTake\":" + escape(g.lastTake);
    json += L",\"targets\":[";
    for (size_t i = 0; i < g.targets.size(); ++i) {
        if (i) json += L',';
        json += escape(g.targets[i].label);
    }
    json += L"],\"takes\":[";
    for (size_t i = 0; i < g.takes.size(); ++i) {
        if (i) json += L',';
        json += escape(g.takes[i]);
    }
    json += L"]}";
    g.web->PostWebMessageAsJson(json.c_str());
}

void status(const std::string& value) {
    g.status = value;
    postState();
}

void refreshTakes() {
    g.takes.clear();
    const std::wstring pattern = br::utf8ToWide(g.outputRoot) + L"\\take-*";
    WIN32_FIND_DATAW data{};
    HANDLE finder = FindFirstFileW(pattern.c_str(), &data);
    if (finder != INVALID_HANDLE_VALUE) {
        do {
            if ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) && wcscmp(data.cFileName, L".") && wcscmp(data.cFileName, L"..")) {
                g.takes.push_back(br::wideToUtf8(data.cFileName));
            }
        } while (FindNextFileW(finder, &data));
        FindClose(finder);
    }
    std::sort(g.takes.begin(), g.takes.end(), std::greater<std::string>());
}

void refreshTargets() {
    const auto previous = g.selected >= 0 && static_cast<size_t>(g.selected) < g.targets.size()
        ? g.targets[static_cast<size_t>(g.selected)].label : std::string();
    g.targets = br::listCaptureTargets(g.window);
    if (g.targets.empty()) {
        br::CaptureTarget target;
        target.label = "Screen · Primary";
        g.targets.push_back(target);
    }
    g.selected = previous.empty() ? (std::max)(0, (std::min)(g.selected, static_cast<int>(g.targets.size()) - 1)) : 0;
    for (size_t i = 0; i < g.targets.size(); ++i) {
        if (g.targets[i].label == previous) g.selected = static_cast<int>(i);
    }
    postState();
}

void setPreviewBounds() {
    if (!g.preview) return;
    const int width = (std::max)(0L, g.previewRect.right - g.previewRect.left);
    const int height = (std::max)(0L, g.previewRect.bottom - g.previewRect.top);
    SetWindowPos(g.preview, HWND_TOP, g.previewRect.left, g.previewRect.top, width, height,
        SWP_NOACTIVATE | SWP_SHOWWINDOW);
}

void showPreview() {
    if (!g.preview) return;
    if (g.canvasVisible && g.width && g.height && (g.recording || g.playing)) {
        setPreviewBounds();
        InvalidateRect(g.preview, nullptr, FALSE);
    } else {
        ShowWindow(g.preview, SW_HIDE);
    }
}

void openTake(const std::string& path) {
    if (g.recording || g.starting) return;
    std::string take;
    if (!br::resolveTakeDirectory(path.c_str(), take)) {
        status(br_capture_last_error());
        return;
    }
    br_player_close();
    if (br::openTakePlayback(take.c_str()) != 0) {
        status(br_capture_last_error());
        return;
    }
    g.lastTake = take;
    g.playing = true;
    g.paused = false;
    g.width = 0;
    g.height = 0;
    status("Playing take");
}

void stopCapture() {
    if (!g.recording) return;
    const int result = br_capture_stop();
    g.recording = false;
    refreshTakes();
    if (result != 0) {
        status(br_capture_last_error()[0] ? br_capture_last_error() : "Could not stop recording");
        return;
    }
    openTake(g.lastTake);
}

void startCapture() {
    if (g.recording || g.starting || !g.prepare) return;
    g.starting = true;
    status("Starting capture…");
    br_player_close();
    g.playing = false;
    g.paused = false;
    g.width = 0;
    g.height = 0;
    showPreview();
    refreshTargets();
    const br::CaptureTarget& target = g.targets[static_cast<size_t>(g.selected)];
    const int monitor = target.monitorIndex;
    void* hwnd = target.hwnd;
    int cropX = 0, cropY = 0, cropW = 0, cropH = 0;
    if (target.area && !hwnd && !pickCaptureArea(g.window, monitor, cropX, cropY, cropW, cropH)) {
        g.starting = false;
        status("Area selection cancelled");
        return;
    }
    const long screenHr = br::primeGraphicsCaptureConsent(monitor, hwnd);
    if (br::isConsentDenied(screenHr)) {
        br::openSettingsUri(L"ms-settings:privacy-graphicscapture");
        g.starting = false;
        status("Allow screen recording in Windows Settings");
        return;
    }
    if (g.microphone && br::isConsentDenied(br::primeMicrophoneConsent())) {
        br::openSettingsUri(L"ms-settings:privacy-microphone");
        g.starting = false;
        status("Allow microphone access in Windows Settings");
        return;
    }
    char directory[4096]{};
    if (g.prepare(g.outputRoot.c_str(), g.microphone, g.systemAudio, g.camera, directory, sizeof(directory), g.context) != 0 || !directory[0]) {
        g.starting = false;
        status(br_capture_last_error()[0] ? br_capture_last_error() : "Could not create take folder");
        return;
    }
    if (br_capture_start(directory, monitor, g.systemAudio, g.microphone, g.camera, hwnd, cropX, cropY, cropW, cropH) != 0) {
        g.starting = false;
        status(br_capture_last_error());
        return;
    }
    g.lastTake = directory;
    g.recording = true;
    g.starting = false;
    status("Recording");
}

void exportTake() {
    if (g.recording || g.starting) return;
    if (g.lastTake.empty()) {
        std::string picked;
        if (!pickTakeDirectory(g.window, picked, g.outputRoot.c_str())) return;
        g.lastTake = picked;
    }
    std::string take;
    if (!br::resolveTakeDirectory(g.lastTake.c_str(), take)) {
        status(br_capture_last_error());
        return;
    }
    g.lastTake = take;
    br_player_close();
    g.playing = false;
    showPreview();
    status("Exporting…");
    const std::string screen = br::joinUtf8Path(take, "screen.mp4");
    const std::string camera = br::joinUtf8Path(take, "camera.mp4");
    const std::string output = br::joinUtf8Path(take, "export.mp4");
    double x = .68, y = .68, width = .28, height = .28;
    br::readCameraPip(take.c_str(), x, y, width, height);
    if (br_compose_take(screen.c_str(), br::fileExistsUtf8(camera.c_str()) ? camera.c_str() : "", output.c_str(), x, y, width, height) != 0) {
        status(br_capture_last_error());
        return;
    }
    status(std::string("Exported ") + (br_last_video_encoder()[0] ? br_last_video_encoder() : "H.264") + " · " + output);
}

void refreshPreview() {
    if (!g.recording && (!g.playing || g.paused)) return;
    if (g.recording && !br_capture_alive()) {
        stopCapture();
        return;
    }
    const size_t required = (std::max)(static_cast<size_t>(g.width) * g.height * 4, static_cast<size_t>(1920) * 1080 * 4);
    if (g.pixels.size() < required) g.pixels.resize(required);
    unsigned width = 0, height = 0;
    int64_t position = 0;
    int ended = 0;
    auto tick = [&]() {
        if (g.recording) return br_capture_copy_preview(g.pixels.data(), static_cast<unsigned>(g.pixels.size()), &width, &height);
        return br_player_tick(g.pixels.data(), static_cast<unsigned>(g.pixels.size()), &width, &height, &position, &ended);
    };
    int result = tick();
    if (result != 0 && !ended && width >= 2 && height >= 2) {
        g.pixels.resize(static_cast<size_t>(width) * height * 4);
        result = tick();
    }
    if (result == 0 && width && height) {
        g.width = width;
        g.height = height;
        showPreview();
    }
    if (ended) {
        g.playing = false;
        g.paused = false;
        br_player_set_paused(1);
        showPreview();
        status("Playback finished");
    }
}

void handleMessage(const std::string& message) {
    if (message == "ready") {
        SetPropW(g.window, L"BlitzWorkspaceReady", reinterpret_cast<HANDLE>(static_cast<INT_PTR>(1)));
        refreshTargets();
        refreshTakes();
        postState();
    } else if (message == "start") {
        startCapture();
    } else if (message == "stop") {
        stopCapture();
    } else if (message == "open") {
        std::string picked;
        if (pickTakeDirectory(g.window, picked, g.lastTake.empty() ? g.outputRoot.c_str() : g.lastTake.c_str())) openTake(picked);
    } else if (message == "export") {
        exportTake();
    } else if (message == "refresh") {
        refreshTargets();
        refreshTakes();
        postState();
    } else if (message == "view|library" || message == "view|record") {
        g.canvasVisible = message == "view|record";
        showPreview();
    } else if (message == "pause" && g.playing) {
        g.paused = !g.paused;
        br_player_set_paused(g.paused);
        status(g.paused ? "Paused" : "Playing take");
    } else if (message.rfind("target|", 0) == 0) {
        const int index = atoi(message.c_str() + 7);
        if (index >= 0 && static_cast<size_t>(index) < g.targets.size() && !g.recording) {
            g.selected = index;
            postState();
        }
    } else if (message.rfind("take|", 0) == 0) {
        const int index = atoi(message.c_str() + 5);
        if (index >= 0 && static_cast<size_t>(index) < g.takes.size()) {
            openTake(br::joinUtf8Path(g.outputRoot, g.takes[static_cast<size_t>(index)].c_str()));
        }
    } else if (message.rfind("audio|", 0) == 0 && !g.recording && !g.starting) {
        if (message == "audio|microphone") g.microphone = !g.microphone;
        if (message == "audio|system") g.systemAudio = !g.systemAudio;
        if (message == "audio|camera") g.camera = !g.camera;
        postState();
    } else if (message.rfind("bounds|", 0) == 0) {
        int left = 0, top = 0, width = 0, height = 0;
        if (sscanf_s(message.c_str(), "bounds|%d|%d|%d|%d", &left, &top, &width, &height) == 4) {
            RECT client{};
            GetClientRect(g.window, &client);
            if (left >= 0 && top >= 0 && width > 0 && height > 0 && left + width <= client.right && top + height <= client.bottom) {
                g.previewRect = {left, top, left + width, top + height};
                showPreview();
            }
        }
    }
}

LRESULT CALLBACK previewProc(HWND hwnd, UINT message, WPARAM wp, LPARAM lp) {
    if (message != WM_PAINT) return DefWindowProcW(hwnd, message, wp, lp);
    PAINTSTRUCT paint{};
    HDC dc = BeginPaint(hwnd, &paint);
    RECT rect{};
    GetClientRect(hwnd, &rect);
    FillRect(dc, &rect, reinterpret_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)));
    if (g.width && g.height && !g.pixels.empty()) {
        BITMAPINFO info{};
        info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        info.bmiHeader.biWidth = static_cast<LONG>(g.width);
        info.bmiHeader.biHeight = -static_cast<LONG>(g.height);
        info.bmiHeader.biPlanes = 1;
        info.bmiHeader.biBitCount = 32;
        info.bmiHeader.biCompression = BI_RGB;
        int x = 0, y = 0, width = 0, height = 0;
        br::letterboxDest(rect.right, rect.bottom, g.width, g.height, x, y, width, height);
        SetStretchBltMode(dc, HALFTONE);
        StretchDIBits(dc, x, y, width, height, 0, 0, g.width, g.height, g.pixels.data(), &info, DIB_RGB_COLORS, SRCCOPY);
    }
    EndPaint(hwnd, &paint);
    return 0;
}

LRESULT CALLBACK windowProc(HWND hwnd, UINT message, WPARAM wp, LPARAM lp) {
    switch (message) {
    case WM_SIZE:
        if (g.controller) {
            RECT bounds{};
            GetClientRect(hwnd, &bounds);
            g.controller->put_Bounds(bounds);
        }
        showPreview();
        return 0;
    case WM_TIMER:
        if (wp == kPreviewTimer) refreshPreview();
        return 0;
    case WM_CLOSE:
        DestroyWindow(hwnd);
        return 0;
    case WM_DESTROY:
        KillTimer(hwnd, kPreviewTimer);
        RemovePropW(hwnd, L"BlitzWorkspaceReady");
        if (g.recording) br_capture_stop();
        br_player_close();
        if (g.controller) g.controller->Close();
        g.web.Reset();
        g.controller.Reset();
        g.window = nullptr;
        PostQuitMessage(0);
        return 0;
    default:
        return DefWindowProcW(hwnd, message, wp, lp);
    }
}

HRESULT onController(HRESULT result, ICoreWebView2Controller* controller) {
    if (FAILED(result) || !controller || !g.window || !IsWindow(g.window)) {
        br::setLastError("WebView2 controller unavailable", result);
        if (g.window) DestroyWindow(g.window);
        return S_OK;
    }
    g.controller = controller;
    g.controller->get_CoreWebView2(&g.web);
    if (!g.web) {
        br::setLastError("WebView2 browser unavailable");
        DestroyWindow(g.window);
        return S_OK;
    }
    RECT bounds{};
    GetClientRect(g.window, &bounds);
    g.controller->put_Bounds(bounds);
    ComPtr<ICoreWebView2Settings> settings;
    g.web->get_Settings(&settings);
    if (settings) {
        settings->put_AreDefaultContextMenusEnabled(FALSE);
        settings->put_AreDevToolsEnabled(FALSE);
    }
    ComPtr<ICoreWebView2_3> web3;
    if (FAILED(g.web.As(&web3)) || !web3) {
        br::setLastError("WebView2 runtime is too old for local assets");
        DestroyWindow(g.window);
        return S_OK;
    }
    const std::wstring assets = executableDirectory() + L"\\WebUI";
    if (FAILED(web3->SetVirtualHostNameToFolderMapping(L"app.blitzrecorder", assets.c_str(), COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_DENY_CORS))) {
        br::setLastError("Could not load Windows workspace assets");
        DestroyWindow(g.window);
        return S_OK;
    }
    EventRegistrationToken token{};
    g.web->add_WebMessageReceived(Callback<ICoreWebView2WebMessageReceivedEventHandler>(
        [](ICoreWebView2*, ICoreWebView2WebMessageReceivedEventArgs* args) -> HRESULT {
            LPWSTR raw = nullptr;
            if (SUCCEEDED(args->TryGetWebMessageAsString(&raw)) && raw) {
                const std::string message = br::wideToUtf8(raw);
                CoTaskMemFree(raw);
                handleMessage(message);
            }
            return S_OK;
        }).Get(), &token);
    g.web->add_NavigationStarting(Callback<ICoreWebView2NavigationStartingEventHandler>(
        [](ICoreWebView2*, ICoreWebView2NavigationStartingEventArgs* args) -> HRESULT {
            LPWSTR uri = nullptr;
            if (SUCCEEDED(args->get_Uri(&uri)) && uri) {
                const bool local = wcsncmp(uri, L"https://app.blitzrecorder/", 26) == 0;
                CoTaskMemFree(uri);
                if (!local) args->put_Cancel(TRUE);
            }
            return S_OK;
        }).Get(), &token);
    if (FAILED(g.web->Navigate(L"https://app.blitzrecorder/index.html"))) {
        br::setLastError("Could not navigate to Windows workspace");
        DestroyWindow(g.window);
        return S_OK;
    }
    g.browserReady = true;
    return S_OK;
}

} 

int runWebViewStudio(WebViewStudioOptions options) {
    if (!options.prepare) return 1;
    const std::wstring assets = executableDirectory() + L"\\WebUI\\index.html";
    if (!std::filesystem::exists(assets)) {
        br::setLastError("Windows workspace assets missing");
        return 1;
    }
    const HRESULT com = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(com) && com != RPC_E_CHANGED_MODE) {
        br::setLastError("WebView2 COM initialization failed", com);
        return 1;
    }
    g = {};
    g.outputRoot = options.outputRoot ? options.outputRoot : "";
    g.selected = options.monitorIndex;
    g.prepare = options.prepare;
    g.context = options.context;
    const HINSTANCE instance = GetModuleHandleW(nullptr);
    WNDCLASSEXW previewClass{};
    previewClass.cbSize = sizeof(previewClass);
    previewClass.hInstance = instance;
    previewClass.lpfnWndProc = previewProc;
    previewClass.lpszClassName = L"BlitzWebPreview";
    previewClass.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    RegisterClassExW(&previewClass);
    WNDCLASSEXW windowClass{};
    windowClass.cbSize = sizeof(windowClass);
    windowClass.hInstance = instance;
    windowClass.lpfnWndProc = windowProc;
    windowClass.lpszClassName = L"BlitzWebStudio";
    windowClass.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    windowClass.hIcon = LoadIconW(instance, MAKEINTRESOURCEW(101));
    windowClass.hbrBackground = CreateSolidBrush(RGB(18, 19, 21));
    RegisterClassExW(&windowClass);
    g.window = CreateWindowExW(0, L"BlitzWebStudio", L"BlitzRecorder", WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT, CW_USEDEFAULT, 1440, 900, nullptr, nullptr, instance, nullptr);
    if (!g.window) {
        br::setLastError("Windows workspace window failed", HRESULT_FROM_WIN32(GetLastError()));
        return 1;
    }
    g.preview = CreateWindowExW(0, L"BlitzWebPreview", L"", WS_CHILD, 0, 0, 0, 0, g.window, nullptr, instance, nullptr);
    br::excludeWindowFromCapture(g.window);
    br::excludeWindowFromCapture(g.preview);
    const std::wstring userData = std::wstring(_wgetenv(L"LOCALAPPDATA") ? _wgetenv(L"LOCALAPPDATA") : L".") + L"\\BlitzRecorder\\WebView2";
    const HRESULT created = CreateCoreWebView2EnvironmentWithOptions(nullptr, userData.c_str(), nullptr,
        Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
            [](HRESULT result, ICoreWebView2Environment* environment) -> HRESULT {
                if (FAILED(result) || !environment || !g.window) {
                    br::setLastError("WebView2 Runtime unavailable", result);
                    if (g.window) DestroyWindow(g.window);
                    return S_OK;
                }
                environment->CreateCoreWebView2Controller(g.window,
                    Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(onController).Get());
                return S_OK;
            }).Get());
    if (FAILED(created)) {
        br::setLastError("WebView2 Runtime unavailable", created);
        DestroyWindow(g.window);
        return 1;
    }
    ShowWindow(g.window, SW_SHOW);
    UpdateWindow(g.window);
    br::hideOwnConsole();
    SetTimer(g.window, kPreviewTimer, 33, nullptr);
    MSG message{};
    while (GetMessageW(&message, nullptr, 0, 0) > 0) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }
    return g.browserReady ? 0 : 1;
}

#endif
