#if defined(_WIN32)

#include "windows_capture.h"
#include "capture_common.h"
#include "win32_shell.h"
#include "webview_shell.h"
#if defined(BR_HAS_WINUI) && BR_HAS_WINUI
#include "winui_shell.h"
#endif

#include <string>
#include <windows.h>

int br_studio_run(
    const char* output_root,
    int monitor_index,
    br_prepare_take_fn prepare,
    void* ctx
) {
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    br::setAppUserModelId();
    if (runWebViewStudio(output_root, monitor_index, prepare, ctx) == 0) {
        return 0;
    }
    MSG webQuit{};
    while (PeekMessageW(&webQuit, nullptr, WM_QUIT, WM_QUIT, PM_REMOVE)) {
    }
#if defined(BR_HAS_WINUI) && BR_HAS_WINUI
    if (runWinUiStudio(output_root, monitor_index, prepare, ctx) == 0) {
        return 0;
    }
    MSG quit{};
    while (PeekMessageW(&quit, nullptr, WM_QUIT, WM_QUIT, PM_REMOVE)) {
    }
    const char* prior = br::lastErrorCStr();
    if (prior && prior[0]) {
        std::string text = "WinUI shell failed; using Win32 - ";
        text += prior;
        br::setLastError(text);
    } else {
        br::setLastError("WinUI shell failed; using Win32");
    }
#endif
    return runStudioWindow(output_root, monitor_index, prepare, ctx);
}

#else
[[maybe_unused]] static int br_windows_capture_tu_studio_run = 0;
#endif
