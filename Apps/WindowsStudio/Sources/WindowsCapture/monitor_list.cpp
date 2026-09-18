#if defined(_WIN32)

#include "monitor_list.h"

#include "capture_common.h"

#include <algorithm>
#include <cstdio>
#include <cwchar>
#include <string>

#include <windows.h>
#include <dxgi.h>
#include <dwmapi.h>

#ifndef DWMWA_CLOAKED
#define DWMWA_CLOAKED 14
#endif

namespace br {

std::vector<AttachedOutput> listAttachedOutputs() {
    std::vector<AttachedOutput> rows;
    Microsoft::WRL::ComPtr<IDXGIFactory1> factory;
    HRESULT hr = CreateDXGIFactory1(IID_PPV_ARGS(&factory));
    if (FAILED(hr) || !factory) {
        setLastError("CreateDXGIFactory1 failed", hr);
        return rows;
    }
    for (UINT adapterIndex = 0; ; ++adapterIndex) {
        Microsoft::WRL::ComPtr<IDXGIAdapter1> adapter;
        hr = factory->EnumAdapters1(adapterIndex, adapter.ReleaseAndGetAddressOf());
        if (hr == DXGI_ERROR_NOT_FOUND) {
            break;
        }
        if (FAILED(hr) || !adapter) {
            continue;
        }
        for (UINT outputIndex = 0; ; ++outputIndex) {
            Microsoft::WRL::ComPtr<IDXGIOutput> output0;
            hr = adapter->EnumOutputs(outputIndex, output0.ReleaseAndGetAddressOf());
            if (hr == DXGI_ERROR_NOT_FOUND) {
                break;
            }
            if (FAILED(hr) || !output0) {
                continue;
            }
            DXGI_OUTPUT_DESC desc{};
            output0->GetDesc(&desc);
            if (!desc.AttachedToDesktop || !desc.Monitor) {
                continue;
            }
            Microsoft::WRL::ComPtr<IDXGIOutput1> output1;
            if (FAILED(output0.As(&output1)) || !output1) {
                continue;
            }
            MONITORINFO info{};
            info.cbSize = sizeof(info);
            const bool primary = GetMonitorInfoW(desc.Monitor, &info) && (info.dwFlags & MONITORINFOF_PRIMARY);
            const unsigned width = static_cast<unsigned>((std::max)(0L, desc.DesktopCoordinates.right - desc.DesktopCoordinates.left)) & ~1u;
            const unsigned height = static_cast<unsigned>((std::max)(0L, desc.DesktopCoordinates.bottom - desc.DesktopCoordinates.top)) & ~1u;
            AttachedOutput row;
            row.adapter = adapter;
            row.output = output1;
            row.monitor = desc.Monitor;
            row.left = desc.DesktopCoordinates.left;
            row.top = desc.DesktopCoordinates.top;
            row.width = width;
            row.height = height;
            row.primary = primary;
            char label[96];
            if (primary) {
                std::snprintf(label, sizeof(label), "Primary %ux%u", width, height);
            } else {
                std::snprintf(label, sizeof(label), "Display %ux%u", width, height);
            }
            row.label = label;
            rows.push_back(std::move(row));
        }
    }
    std::stable_sort(rows.begin(), rows.end(), [](const AttachedOutput& a, const AttachedOutput& b) {
        return static_cast<int>(a.primary) > static_cast<int>(b.primary);
    });
    int display = 2;
    for (AttachedOutput& row : rows) {
        if (row.primary) {
            continue;
        }
        char label[96];
        std::snprintf(label, sizeof(label), "Display %d %ux%u", display, row.width, row.height);
        row.label = label;
        ++display;
    }
    return rows;
}

bool skipCaptureWindow(HWND hwnd, HWND exclude) {
    if (!hwnd || !IsWindow(hwnd) || !IsWindowVisible(hwnd) || IsIconic(hwnd)) {
        return true;
    }
    RECT rc{};
    if (!GetWindowRect(hwnd, &rc) || (rc.right - rc.left) < 16 || (rc.bottom - rc.top) < 16) {
        return true;
    }
    if (exclude && (hwnd == exclude || IsChild(exclude, hwnd))) {
        return true;
    }
    if (GetWindow(hwnd, GW_OWNER)) {
        return true;
    }
    if (hwnd == GetShellWindow()) {
        return true;
    }
    const LONG ex = GetWindowLongW(hwnd, GWL_EXSTYLE);
    if (ex & WS_EX_TOOLWINDOW) {
        return true;
    }
    wchar_t cls[64] = {};
    GetClassNameW(hwnd, cls, 64);
    if (wcscmp(cls, L"Progman") == 0 || wcscmp(cls, L"WorkerW") == 0 || wcscmp(cls, L"Shell_TrayWnd") == 0) {
        return true;
    }
    BOOL cloaked = FALSE;
    if (SUCCEEDED(DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, &cloaked, sizeof(cloaked))) && cloaked) {
        return true;
    }
    wchar_t title[256] = {};
    if (GetWindowTextW(hwnd, title, 256) <= 0) {
        return true;
    }
    return false;
}

struct EnumState {
    HWND exclude = nullptr;
    std::vector<CaptureTarget>* out = nullptr;
};

BOOL CALLBACK enumCaptureWindows(HWND hwnd, LPARAM lp) {
    auto* state = reinterpret_cast<EnumState*>(lp);
    if (!state || !state->out) {
        return FALSE;
    }
    if (skipCaptureWindow(hwnd, state->exclude)) {
        return TRUE;
    }
    if (state->out->size() >= 40) {
        return FALSE;
    }
    wchar_t title[256] = {};
    GetWindowTextW(hwnd, title, 256);
    CaptureTarget target;
    target.hwnd = hwnd;
    target.monitorIndex = 0;
    target.label = std::string("Window · ") + wideToUtf8(title);
    state->out->push_back(std::move(target));
    return TRUE;
}

std::vector<CaptureTarget> listCaptureTargets(void* excludeHwnd) {
    std::vector<CaptureTarget> rows;
    const std::vector<AttachedOutput> outputs = listAttachedOutputs();
    int index = 0;
    for (const AttachedOutput& output : outputs) {
        CaptureTarget screen;
        screen.label = std::string("Screen · ") + output.label;
        screen.monitorIndex = index;
        rows.push_back(std::move(screen));
        CaptureTarget area;
        area.label = std::string("Area · ") + output.label;
        area.monitorIndex = index;
        area.area = true;
        rows.push_back(std::move(area));
        ++index;
    }
    if (rows.empty()) {
        CaptureTarget target;
        target.label = "Screen · Primary";
        rows.push_back(std::move(target));
    }
    EnumState state;
    state.exclude = static_cast<HWND>(excludeHwnd);
    state.out = &rows;
    EnumWindows(enumCaptureWindows, reinterpret_cast<LPARAM>(&state));
    return rows;
}

}  // namespace br

#else
[[maybe_unused]] static int br_windows_capture_tu_monitors = 0;
#endif
