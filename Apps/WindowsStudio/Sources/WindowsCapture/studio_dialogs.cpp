#if defined(_WIN32)

#include "studio_dialogs.h"

#include "capture_common.h"
#include "monitor_list.h"

#include <algorithm>

#include <windows.h>
#include <windowsx.h>
#include <shobjidl.h>

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shell32.lib")

bool pickTakeDirectory(void* ownerHwnd, std::string& outUtf8, const char* startDir) {
    br::ensureCom();
    IFileOpenDialog* dialog = nullptr;
    HRESULT hr = CoCreateInstance(
        CLSID_FileOpenDialog,
        nullptr,
        CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&dialog)
    );
    if (FAILED(hr) || !dialog) {
        br::setLastError("folder picker unavailable", hr);
        return false;
    }
    DWORD options = 0;
    dialog->GetOptions(&options);
    dialog->SetOptions(options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM);
    dialog->SetTitle(L"Open BlitzRecorder take");
    if (startDir && startDir[0]) {
        IShellItem* folder = nullptr;
        const std::wstring wide = br::utf8ToWide(startDir);
        if (!wide.empty()
            && SUCCEEDED(SHCreateItemFromParsingName(wide.c_str(), nullptr, IID_PPV_ARGS(&folder)))
            && folder) {
            dialog->SetFolder(folder);
            folder->Release();
        }
    }
    hr = dialog->Show(reinterpret_cast<HWND>(ownerHwnd));
    if (hr == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
        dialog->Release();
        return false;
    }
    if (FAILED(hr)) {
        dialog->Release();
        br::setLastError("folder picker failed", hr);
        return false;
    }
    IShellItem* item = nullptr;
    hr = dialog->GetResult(&item);
    dialog->Release();
    if (FAILED(hr) || !item) {
        return false;
    }
    PWSTR path = nullptr;
    hr = item->GetDisplayName(SIGDN_FILESYSPATH, &path);
    item->Release();
    if (FAILED(hr) || !path) {
        return false;
    }
    outUtf8 = br::wideToUtf8(path);
    CoTaskMemFree(path);
    return !outUtf8.empty();
}

namespace {

struct AreaPick {
    POINT start{};
    POINT current{};
    bool dragging = false;
    bool done = false;
    bool ok = false;
};

RECT normalizedClientRect(const AreaPick& pick) {
    RECT rc{};
    rc.left = (std::min)(pick.start.x, pick.current.x);
    rc.top = (std::min)(pick.start.y, pick.current.y);
    rc.right = (std::max)(pick.start.x, pick.current.x);
    rc.bottom = (std::max)(pick.start.y, pick.current.y);
    return rc;
}

LRESULT CALLBACK areaProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    auto* pick = reinterpret_cast<AreaPick*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    switch (msg) {
    case WM_LBUTTONDOWN:
        if (!pick) {
            break;
        }
        pick->dragging = true;
        pick->start.x = GET_X_LPARAM(lParam);
        pick->start.y = GET_Y_LPARAM(lParam);
        pick->current = pick->start;
        SetCapture(hwnd);
        InvalidateRect(hwnd, nullptr, FALSE);
        return 0;
    case WM_MOUSEMOVE:
        if (pick && pick->dragging) {
            pick->current.x = GET_X_LPARAM(lParam);
            pick->current.y = GET_Y_LPARAM(lParam);
            InvalidateRect(hwnd, nullptr, FALSE);
        }
        return 0;
    case WM_LBUTTONUP:
        if (pick && pick->dragging) {
            pick->current.x = GET_X_LPARAM(lParam);
            pick->current.y = GET_Y_LPARAM(lParam);
            const RECT rc = normalizedClientRect(*pick);
            pick->ok = (rc.right - rc.left) >= 16 && (rc.bottom - rc.top) >= 16;
            pick->done = true;
            ReleaseCapture();
            DestroyWindow(hwnd);
        }
        return 0;
    case WM_KEYDOWN:
        if (!pick) {
            break;
        }
        if (wParam == VK_ESCAPE) {
            pick->ok = false;
            pick->done = true;
            DestroyWindow(hwnd);
            return 0;
        }
        return 0;
    case WM_PAINT: {
        PAINTSTRUCT ps{};
        HDC hdc = BeginPaint(hwnd, &ps);
        RECT client{};
        GetClientRect(hwnd, &client);
        FillRect(hdc, &client, reinterpret_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)));
        if (pick && pick->dragging) {
            RECT rc = normalizedClientRect(*pick);
            FrameRect(hdc, &rc, reinterpret_cast<HBRUSH>(GetStockObject(WHITE_BRUSH)));
            InflateRect(&rc, -1, -1);
            FrameRect(hdc, &rc, reinterpret_cast<HBRUSH>(GetStockObject(WHITE_BRUSH)));
        }
        SetBkMode(hdc, TRANSPARENT);
        SetTextColor(hdc, RGB(255, 255, 255));
        DrawTextW(hdc, L"Drag an area. Esc cancels.", -1, &client, DT_CENTER | DT_TOP | DT_SINGLELINE);
        EndPaint(hwnd, &ps);
        return 0;
    }
    default:
        break;
    }
    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

}  // namespace

bool pickCaptureArea(void* ownerHwnd, int monitorIndex, int& x, int& y, int& width, int& height) {
    const std::vector<br::AttachedOutput> outputs = br::listAttachedOutputs();
    if (monitorIndex < 0 || static_cast<size_t>(monitorIndex) >= outputs.size()) {
        br::setLastError("Area monitor is out of range");
        return false;
    }
    const br::AttachedOutput& output = outputs[static_cast<size_t>(monitorIndex)];
    WNDCLASSW wc{};
    wc.lpfnWndProc = areaProc;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpszClassName = L"BlitzRecorderAreaPick";
    wc.hCursor = LoadCursorW(nullptr, IDC_CROSS);
    if (!RegisterClassW(&wc) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
        br::setLastError("Could not register the area picker");
        return false;
    }
    HWND overlay = CreateWindowExW(
        WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_LAYERED,
        wc.lpszClassName,
        L"Select area",
        WS_POPUP,
        output.left,
        output.top,
        static_cast<int>(output.width),
        static_cast<int>(output.height),
        nullptr,
        nullptr,
        wc.hInstance,
        nullptr
    );
    if (!overlay) {
        br::setLastError("Could not open the area picker");
        return false;
    }
    AreaPick pick{};
    SetWindowLongPtrW(overlay, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(&pick));
    SetLayeredWindowAttributes(overlay, 0, 140, LWA_ALPHA);
    br::excludeWindowFromCapture(overlay);
    SetWindowPos(overlay, HWND_TOPMOST, output.left, output.top, static_cast<int>(output.width), static_cast<int>(output.height), SWP_SHOWWINDOW);
    UpdateWindow(overlay);
    SetForegroundWindow(overlay);
    HWND owner = reinterpret_cast<HWND>(ownerHwnd);
    if (owner) {
        EnableWindow(owner, FALSE);
    }
    MSG msg{};
    while (!pick.done) {
        const BOOL gm = GetMessageW(&msg, nullptr, 0, 0);
        if (gm <= 0) {
            pick.ok = false;
            pick.done = true;
            if (gm == 0) {
                PostQuitMessage(static_cast<int>(msg.wParam));
            }
            break;
        }
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    if (owner) {
        EnableWindow(owner, TRUE);
        SetForegroundWindow(owner);
    }
    if (IsWindow(overlay)) {
        DestroyWindow(overlay);
    }
    if (!pick.ok) {
        return false;
    }
    const RECT rc = normalizedClientRect(pick);
    x = static_cast<int>(rc.left) & ~1;
    y = static_cast<int>(rc.top) & ~1;
    width = static_cast<int>(rc.right - rc.left) & ~1;
    height = static_cast<int>(rc.bottom - rc.top) & ~1;
    if (width < 16 || height < 16) {
        return false;
    }
    return true;
}

#else
[[maybe_unused]] static int br_windows_capture_tu_studio_dialogs = 0;
#endif
