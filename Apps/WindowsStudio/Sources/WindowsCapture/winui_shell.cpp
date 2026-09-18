#if defined(_WIN32)

#include "winui_shell.h"

#include "capture_common.h"
#include "monitor_list.h"
#include "studio_dialogs.h"
#include "windows_capture.h"

#include <algorithm>
#include <functional>
#include <string>
#include <vector>

#include <windows.h>
#include "winrt_compat.h"
#include <inspectable.h>
#include <roapi.h>
#include <winstring.h>
#include <windows.foundation.h>
#include <windows.foundation.collections.h>
#include <windows.ui.xaml.h>
#include <windows.ui.xaml.controls.h>
#include <windows.ui.xaml.controls.primitives.h>
#include <windows.ui.xaml.hosting.h>
#include <windows.ui.xaml.hosting.desktopwindowxamlsource.h>
#include <windows.ui.xaml.markup.h>
#include <wrl.h>
#include <wrl/event.h>
#include "winrt_compat.h"

#pragma comment(lib, "windowsapp.lib")
#pragma comment(lib, "runtimeobject.lib")

using ABI::Windows::Foundation::IEventHandler;
using ABI::Windows::Foundation::IPropertyValueStatics;
using ABI::Windows::Foundation::Collections::IObservableVector;
using ABI::Windows::Foundation::Collections::IVector;
using ABI::Windows::UI::Xaml::Controls::IControl;
using ABI::Windows::UI::Xaml::IRoutedEventArgs;
using ABI::Windows::UI::Xaml::IRoutedEventHandler;
using ABI::Windows::UI::Xaml::IUIElement;
using ABI::Windows::UI::Xaml::Controls::IComboBox;
using ABI::Windows::UI::Xaml::Controls::IItemsControl;
using ABI::Windows::UI::Xaml::Controls::Primitives::IButtonBase;
using ABI::Windows::UI::Xaml::Controls::Primitives::IToggleButton;
using ABI::Windows::UI::Xaml::Hosting::IDesktopWindowXamlSource;
using ABI::Windows::UI::Xaml::Hosting::IWindowsXamlManager;
using ABI::Windows::UI::Xaml::Hosting::IWindowsXamlManagerStatics;
using ABI::Windows::UI::Xaml::Markup::IXamlReaderStatics;
using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;

namespace {

constexpr wchar_t kXaml[] =
    L"<Grid xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'"
    L" xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml' Background='#1C1C1E'>"
    L"<StackPanel Margin='16' Spacing='12'>"
    L"<TextBlock Text='BlitzRecorder' FontSize='22' Foreground='White'/>"
    L"<StackPanel Orientation='Horizontal' Spacing='8'>"
    L"<Button x:Name='StartButton' Content='Start' Width='110' Height='36'/>"
    L"<Button x:Name='StopButton' Content='Stop' Width='110' Height='36'/>"
    L"<Button x:Name='OpenButton' Content='Open take' Width='150' Height='36'/>"
    L"<Button x:Name='ExportButton' Content='Export last' Width='120' Height='36'/>"
    L"</StackPanel>"
    L"<ComboBox x:Name='MonitorBox' Width='720' Height='36'/>"
    L"<TextBlock Text='Screen · full display · Area · drag a crop · Window · one app' Foreground='#D1D1D6'/>"
    L"<StackPanel Orientation='Horizontal' Spacing='16'>"
    L"<CheckBox x:Name='SysBox' Content='System audio' IsChecked='True' Foreground='White'/>"
    L"<CheckBox x:Name='MicBox' Content='Microphone' IsChecked='True' Foreground='White'/>"
    L"<CheckBox x:Name='CamBox' Content='Camera' Foreground='White'/>"
    L"</StackPanel>"
    L"<TextBlock x:Name='StatusText' Text='Ready' Foreground='#D1D1D6'/>"
    L"</StackPanel></Grid>";

struct WinUiState {
    std::string outputRoot;
    int monitor = 0;
    br_prepare_take_fn prepare = nullptr;
    void* ctx = nullptr;
    HWND window = nullptr;
    HWND island = nullptr;
    HWND preview = nullptr;
    bool recording = false;
    bool starting = false;
    bool playing = false;
    bool paused = false;
    bool sys = true;
    bool mic = true;
    bool cam = false;
    bool enteredLoop = false;
    std::string lastTake;
    std::vector<br::CaptureTarget> targets;
    std::vector<unsigned char> pixels;
    unsigned int pixelW = 0;
    unsigned int pixelH = 0;
    ComPtr<IInspectable> root;
};

WinUiState gUi;

class HString {
public:
    explicit HString(const wchar_t* value) {
        WindowsCreateString(value, static_cast<UINT32>(wcslen(value)), &str_);
    }
    ~HString() {
        if (str_) {
            WindowsDeleteString(str_);
        }
    }
    HSTRING get() const { return str_; }

private:
    HSTRING str_ = nullptr;
};

template <typename T>
HRESULT activateFactory(HSTRING name, ComPtr<T>& out) {
    out.Reset();
    HRESULT hr = RoGetActivationFactory(name, IID_PPV_ARGS(&out));
    if (SUCCEEDED(hr) && out) {
        return hr;
    }
    ComPtr<IUnknown> unk;
    hr = RoGetActivationFactory(name, IID_PPV_ARGS(&unk));
    if (FAILED(hr) || !unk) {
        return hr;
    }
    return unk.As(&out);
}

HRESULT findNamed(IInspectable* root, const wchar_t* name, IInspectable** out) {
    ComPtr<ABI::Windows::UI::Xaml::IFrameworkElement> fe;
    HRESULT hr = root->QueryInterface(IID_PPV_ARGS(&fe));
    if (FAILED(hr)) {
        return hr;
    }
    HString id(name);
    return fe->FindName(id.get(), out);
}

void setStatus(const char* text) {
    if (!gUi.root) {
        return;
    }
    ComPtr<IInspectable> obj;
    if (FAILED(findNamed(gUi.root.Get(), L"StatusText", &obj)) || !obj) {
        return;
    }
    ComPtr<ABI::Windows::UI::Xaml::Controls::ITextBlock> block;
    if (FAILED(obj.As(&block))) {
        return;
    }
    HString value(br::utf8ToWide(text).c_str());
    block->put_Text(value.get());
}

void setEnabled(const wchar_t* name, bool enabled) {
    if (!gUi.root) {
        return;
    }
    ComPtr<IInspectable> obj;
    if (FAILED(findNamed(gUi.root.Get(), name, &obj)) || !obj) {
        return;
    }
    ComPtr<IControl> control;
    if (FAILED(obj.As(&control)) || !control) {
        return;
    }
    control->put_IsEnabled(enabled ? TRUE : FALSE);
}

void setRecordingButtons(bool recording) {
    setEnabled(L"StartButton", !recording);
    setEnabled(L"StopButton", recording);
    setEnabled(L"OpenButton", !recording);
    setEnabled(L"ExportButton", !recording);
}

void setBusyButtons() {
    setEnabled(L"StartButton", false);
    setEnabled(L"StopButton", false);
    setEnabled(L"OpenButton", false);
    setEnabled(L"ExportButton", false);
}

int selectedMonitorIndex() {
    if (!gUi.root) {
        return gUi.monitor;
    }
    ComPtr<IInspectable> obj;
    if (FAILED(findNamed(gUi.root.Get(), L"MonitorBox", &obj)) || !obj) {
        return gUi.monitor;
    }
    ComPtr<ABI::Windows::UI::Xaml::Controls::Primitives::ISelector> selector;
    if (FAILED(obj.As(&selector)) || !selector) {
        return gUi.monitor;
    }
    INT32 index = 0;
    selector->get_SelectedIndex(&index);
    return index < 0 ? 0 : static_cast<int>(index);
}

void fillMonitorBox() {
    ComPtr<IInspectable> obj;
    ComPtr<IVector<IInspectable*>> list;
    if (gUi.root && SUCCEEDED(findNamed(gUi.root.Get(), L"MonitorBox", &obj)) && obj) {
        ComPtr<IItemsControl> items;
        if (SUCCEEDED(obj.As(&items)) && items) {
            ComPtr<IObservableVector<IInspectable*>> observable;
            if (SUCCEEDED(items->get_Items(observable.ReleaseAndGetAddressOf())) && observable) {
                observable.As(&list);
            }
        }
    }
    HString pvName(RuntimeClass_Windows_Foundation_PropertyValue);
    ComPtr<IPropertyValueStatics> factory;
    if (FAILED(activateFactory(pvName.get(), factory)) || !factory) {
        gUi.targets = br::listCaptureTargets(gUi.window);
        return;
    }
    void* prevHwnd = nullptr;
    int prevMonitor = gUi.monitor;
    bool prevArea = false;
    if (gUi.monitor >= 0 && static_cast<size_t>(gUi.monitor) < gUi.targets.size()) {
        prevHwnd = gUi.targets[static_cast<size_t>(gUi.monitor)].hwnd;
        prevMonitor = gUi.targets[static_cast<size_t>(gUi.monitor)].monitorIndex;
        prevArea = gUi.targets[static_cast<size_t>(gUi.monitor)].area;
    }
    gUi.targets = br::listCaptureTargets(gUi.window);
    if (list) {
        list->Clear();
    }
    int select = 0;
    auto appendLabel = [&](const wchar_t* wide) {
        if (!list) {
            return;
        }
        HString label(wide);
        ComPtr<IInspectable> value;
        if (SUCCEEDED(factory->CreateString(label.get(), value.ReleaseAndGetAddressOf())) && value) {
            list->Append(value.Get());
        }
    };
    for (size_t i = 0; i < gUi.targets.size(); ++i) {
        const br::CaptureTarget& target = gUi.targets[i];
        appendLabel(br::utf8ToWide(target.label).c_str());
        if (prevHwnd && target.hwnd == prevHwnd) {
            select = static_cast<int>(i);
        } else if (!prevHwnd && !target.hwnd && target.monitorIndex == prevMonitor && target.area == prevArea) {
            select = static_cast<int>(i);
        }
    }
    if (gUi.targets.empty()) {
        br::CaptureTarget fallback;
        fallback.label = "Screen · Primary";
        gUi.targets.push_back(fallback);
        appendLabel(L"Screen · Primary");
    }
    ComPtr<ABI::Windows::UI::Xaml::Controls::Primitives::ISelector> selector;
    if (obj && SUCCEEDED(obj.As(&selector)) && selector) {
        selector->put_SelectedIndex(select);
        gUi.monitor = select;
    }
}

void hookMonitorDropDown() {
    if (!gUi.root) {
        return;
    }
    ComPtr<IInspectable> obj;
    if (FAILED(findNamed(gUi.root.Get(), L"MonitorBox", &obj)) || !obj) {
        return;
    }
    ComPtr<IComboBox> combo;
    if (SUCCEEDED(obj.As(&combo)) && combo) {
        auto opened = Callback<IEventHandler<IInspectable*>>([](IInspectable*, IInspectable*) -> HRESULT {
            fillMonitorBox();
            return S_OK;
        });
        EventRegistrationToken drop{};
        combo->add_DropDownOpened(opened.Get(), &drop);
    }
    ComPtr<IUIElement> element;
    if (SUCCEEDED(obj.As(&element)) && element) {
        auto focused = Callback<IRoutedEventHandler>([](IInspectable*, IRoutedEventArgs*) -> HRESULT {
            fillMonitorBox();
            return S_OK;
        });
        EventRegistrationToken focus{};
        element->add_GotFocus(focused.Get(), &focus);
    }
}

void startCapture() {
    if (gUi.recording || gUi.starting || !gUi.prepare) {
        return;
    }
    struct Starting {
        bool& flag;
        explicit Starting(bool& f) : flag(f) { flag = true; }
        ~Starting() { flag = false; }
    } starting(gUi.starting);
    br_player_close();
    gUi.playing = false;
    gUi.paused = false;
    setBusyButtons();
    setStatus("starting…");
    fillMonitorBox();
    gUi.monitor = selectedMonitorIndex();
    int monitorIndex = gUi.monitor;
    void* hwnd = nullptr;
    bool area = false;
    if (gUi.monitor >= 0 && static_cast<size_t>(gUi.monitor) < gUi.targets.size()) {
        monitorIndex = gUi.targets[static_cast<size_t>(gUi.monitor)].monitorIndex;
        hwnd = gUi.targets[static_cast<size_t>(gUi.monitor)].hwnd;
        area = gUi.targets[static_cast<size_t>(gUi.monitor)].area;
    }
    int cropX = 0;
    int cropY = 0;
    int cropW = 0;
    int cropH = 0;
    if (area && !hwnd) {
        if (!pickCaptureArea(gUi.window, monitorIndex, cropX, cropY, cropW, cropH)) {
            if (!gUi.window || !IsWindow(gUi.window)) {
                return;
            }
            setRecordingButtons(false);
            setStatus("area cancelled");
            return;
        }
    }
    char takeDir[4096] = {0};
    const int mic = gUi.mic ? 1 : 0;
    const int systemAudio = gUi.sys ? 1 : 0;
    const int camera = gUi.cam ? 1 : 0;
    if (gUi.prepare(gUi.outputRoot.c_str(), mic, systemAudio, camera, takeDir, static_cast<int>(sizeof(takeDir)), gUi.ctx) != 0) {
        if (!gUi.window || !IsWindow(gUi.window)) {
            return;
        }
        setRecordingButtons(false);
        setStatus(br_capture_last_error()[0] ? br_capture_last_error() : "could not create take folder");
        return;
    }
    if (br_capture_start(takeDir, monitorIndex, systemAudio, mic, camera, hwnd, cropX, cropY, cropW, cropH) != 0) {
        if (!gUi.window || !IsWindow(gUi.window)) {
            return;
        }
        setRecordingButtons(false);
        setStatus(br_capture_last_error());
        return;
    }
    if (!gUi.window || !IsWindow(gUi.window)) {
        br_capture_stop();
        return;
    }
    gUi.recording = true;
    gUi.playing = false;
    gUi.lastTake = takeDir;
    setRecordingButtons(true);
    std::string status = "recording ";
    status += takeDir;
    if (br_capture_last_error()[0]) {
        status += " — ";
        status += br_capture_last_error();
    }
    setStatus(status.c_str());
}

void stopCapture() {
    br_capture_stop();
    gUi.recording = false;
    setRecordingButtons(false);
    if (!gUi.lastTake.empty() && br::openTakePlayback(gUi.lastTake.c_str()) == 0) {
        gUi.playing = true;
        gUi.paused = false;
        if (br_capture_last_error()[0]) {
            std::string status = "playing last take — ";
            status += br_capture_last_error();
            setStatus(status.c_str());
        } else {
            setStatus("playing last take");
        }
        return;
    }
    setStatus(gUi.lastTake.empty() ? "stopped" : "stopped — Open take to play");
}

void openTake() {
    if (gUi.recording || gUi.starting) {
        setStatus(gUi.starting ? "wait — capture is starting" : "stop recording first");
        return;
    }
    std::string directory;
    const char* start = gUi.lastTake.empty() ? gUi.outputRoot.c_str() : gUi.lastTake.c_str();
    if (!pickTakeDirectory(gUi.window, directory, start)) {
        return;
    }
    std::string take;
    if (!br::resolveTakeDirectory(directory.c_str(), take)) {
        setStatus(br_capture_last_error());
        return;
    }
    if (br::openTakePlayback(take.c_str()) != 0) {
        setStatus(br_capture_last_error());
        return;
    }
    gUi.lastTake = take;
    gUi.playing = true;
    gUi.paused = false;
    if (br_capture_last_error()[0]) {
        std::string status = "playing take — ";
        status += br_capture_last_error();
        setStatus(status.c_str());
    } else {
        setStatus("playing take");
    }
}

void exportLast() {
    if (gUi.recording || gUi.starting) {
        setStatus(gUi.starting ? "wait — capture is starting" : "stop recording first");
        return;
    }
    br_player_close();
    gUi.playing = false;
    if (gUi.lastTake.empty()) {
        if (!pickTakeDirectory(gUi.window, gUi.lastTake, gUi.outputRoot.c_str())) {
            return;
        }
    }
    std::string take;
    if (!br::resolveTakeDirectory(gUi.lastTake.c_str(), take)) {
        setStatus(br_capture_last_error());
        return;
    }
    gUi.lastTake = take;
    const std::string screen = br::joinUtf8Path(gUi.lastTake, "screen.mp4");
    const std::string camera = br::joinUtf8Path(gUi.lastTake, "camera.mp4");
    const std::string exported = br::joinUtf8Path(gUi.lastTake, "export.mp4");
    const char* cam = br::fileExistsUtf8(camera.c_str()) ? camera.c_str() : "";
    double pipX = 0.68;
    double pipY = 0.68;
    double pipW = 0.28;
    double pipH = 0.28;
    br::readCameraPip(gUi.lastTake.c_str(), pipX, pipY, pipW, pipH);
    if (br_compose_take(screen.c_str(), cam, exported.c_str(), pipX, pipY, pipW, pipH) != 0) {
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

HRESULT hookButton(IInspectable* root, const wchar_t* name, std::function<void()> fn) {
    ComPtr<IInspectable> obj;
    HRESULT hr = findNamed(root, name, &obj);
    if (FAILED(hr) || !obj) {
        return hr;
    }
    ComPtr<IButtonBase> base;
    hr = obj.As(&base);
    if (FAILED(hr)) {
        return hr;
    }
    auto handler = Callback<IRoutedEventHandler>([fn = std::move(fn)](IInspectable*, IRoutedEventArgs*) -> HRESULT {
        if (fn) {
            fn();
        }
        return S_OK;
    });
    EventRegistrationToken token{};
    return base->add_Click(handler.Get(), &token);
}

void hookCheckBox(IInspectable* root, const wchar_t* name, bool* value) {
    if (!value) {
        return;
    }
    ComPtr<IInspectable> obj;
    if (FAILED(findNamed(root, name, &obj)) || !obj) {
        return;
    }
    ComPtr<IToggleButton> toggle;
    if (FAILED(obj.As(&toggle)) || !toggle) {
        return;
    }
    auto checkedHandler = Callback<IRoutedEventHandler>([value](IInspectable*, IRoutedEventArgs*) -> HRESULT {
        *value = true;
        return S_OK;
    });
    auto uncheckedHandler = Callback<IRoutedEventHandler>([value](IInspectable*, IRoutedEventArgs*) -> HRESULT {
        *value = false;
        return S_OK;
    });
    EventRegistrationToken token{};
    toggle->add_Checked(checkedHandler.Get(), &token);
    toggle->add_Unchecked(uncheckedHandler.Get(), &token);
}

void paintPreview(HWND hwnd) {
    PAINTSTRUCT ps{};
    HDC hdc = BeginPaint(hwnd, &ps);
    RECT rc{};
    GetClientRect(hwnd, &rc);
    FillRect(hdc, &rc, reinterpret_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)));
    if (!gUi.pixels.empty() && gUi.pixelW > 0 && gUi.pixelH > 0) {
        BITMAPINFO info{};
        info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        info.bmiHeader.biWidth = static_cast<LONG>(gUi.pixelW);
        info.bmiHeader.biHeight = -static_cast<LONG>(gUi.pixelH);
        info.bmiHeader.biPlanes = 1;
        info.bmiHeader.biBitCount = 32;
        info.bmiHeader.biCompression = BI_RGB;
        int x = 0;
        int y = 0;
        int w = 0;
        int h = 0;
        br::letterboxDest(rc.right - rc.left, rc.bottom - rc.top, gUi.pixelW, gUi.pixelH, x, y, w, h);
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
            static_cast<int>(gUi.pixelW),
            static_cast<int>(gUi.pixelH),
            gUi.pixels.data(),
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

void layoutChrome(HWND hwnd) {
    if (!hwnd) {
        return;
    }
    RECT rc{};
    GetClientRect(hwnd, &rc);
    const int width = (std::max)(1, static_cast<int>(rc.right - rc.left));
    const int height = (std::max)(1, static_cast<int>(rc.bottom - rc.top));
    const int islandH = 220;
    if (gUi.island) {
        SetWindowPos(gUi.island, HWND_TOP, 0, 0, width, islandH, SWP_SHOWWINDOW);
    }
    if (gUi.preview) {
        const int y = islandH + 8;
        SetWindowPos(
            gUi.preview,
            HWND_TOP,
            8,
            y,
            (std::max)(1, width - 16),
            (std::max)(1, height - y - 8),
            SWP_SHOWWINDOW
        );
    }
}

void growPreviewBuffer(unsigned int width, unsigned int height) {
    const size_t need = static_cast<size_t>(width) * height * 4;
    const size_t want = (std::max)(7680ull * 4320ull * 4ull, need);
    if (gUi.pixels.size() < want) {
        gUi.pixels.resize(want);
    }
}

void onTransportKey(WPARAM vk) {
    if (gUi.starting) {
        return;
    }
    if (vk == VK_ESCAPE && gUi.recording) {
        stopCapture();
        return;
    }
    if (vk != VK_SPACE) {
        return;
    }
    if (gUi.recording) {
        stopCapture();
    } else if (gUi.playing) {
        gUi.paused = !gUi.paused;
        br_player_set_paused(gUi.paused ? 1 : 0);
        setStatus(gUi.paused ? "paused" : "playing take");
    } else {
        startCapture();
    }
}

void refreshPreview() {
    unsigned int width = 0;
    unsigned int height = 0;
    int64_t takeHns = 0;
    int ended = 0;
    growPreviewBuffer(gUi.pixelW, gUi.pixelH);
    if (gUi.recording) {
        if (!br_capture_alive()) {
            stopCapture();
            return;
        }
        if (br_capture_copy_preview(gUi.pixels.data(), static_cast<unsigned int>(gUi.pixels.size()), &width, &height) == 0) {
            gUi.pixelW = width;
            gUi.pixelH = height;
        } else if (width >= 2 && height >= 2) {
            growPreviewBuffer(width, height);
            if (br_capture_copy_preview(gUi.pixels.data(), static_cast<unsigned int>(gUi.pixels.size()), &width, &height) == 0) {
                gUi.pixelW = width;
                gUi.pixelH = height;
            }
        }
    } else if (gUi.playing && !gUi.paused) {
        if (br_player_tick(gUi.pixels.data(), static_cast<unsigned int>(gUi.pixels.size()), &width, &height, &takeHns, &ended) == 0) {
            gUi.pixelW = width;
            gUi.pixelH = height;
        } else if (!ended && width >= 2 && height >= 2) {
            growPreviewBuffer(width, height);
            if (br_player_tick(gUi.pixels.data(), static_cast<unsigned int>(gUi.pixels.size()), &width, &height, &takeHns, &ended) == 0) {
                gUi.pixelW = width;
                gUi.pixelH = height;
            }
        }
        if (ended) {
            gUi.playing = false;
            gUi.paused = false;
            br_player_set_paused(1);
        }
    }
    if (gUi.preview) {
        InvalidateRect(gUi.preview, nullptr, FALSE);
    }
}

LRESULT CALLBACK wndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
    case WM_TIMER:
        refreshPreview();
        return 0;
    case WM_SIZE:
        layoutChrome(hwnd);
        return 0;
    case WM_DESTROY:
        KillTimer(hwnd, 1);
        if (gUi.window == hwnd) {
            gUi.window = nullptr;
            if (gUi.recording) {
                br_capture_stop();
            }
            br_player_close();
            if (gUi.enteredLoop) {
                PostQuitMessage(0);
            }
        }
        return 0;
    default:
        break;
    }
    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

}  // namespace

int runWinUiStudio(
    const char* outputRoot,
    int monitorIndex,
    int (*prepare)(const char*, int, int, int, char*, int, void*),
    void* ctx
) {
    auto fail = [](const char* message, HRESULT code = S_OK) -> int {
        if (FAILED(code)) {
            br::setLastError(message, code);
        } else {
            br::setLastError(message);
        }
        return 1;
    };
    if (!prepare) {
        return fail("prepare callback is missing");
    }
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    const HRESULT comHr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(comHr) && comHr != RPC_E_CHANGED_MODE && comHr != S_FALSE) {
        return fail("CoInitializeEx STA failed", comHr);
    }
    RoInitialize(RO_INIT_SINGLETHREADED);

    ComPtr<IWindowsXamlManagerStatics> managerStatics;
    HString managerName(RuntimeClass_Windows_UI_Xaml_Hosting_WindowsXamlManager);
    HRESULT hr = activateFactory(managerName.get(), managerStatics);
    if (FAILED(hr) || !managerStatics) {
        return fail("WindowsXamlManager factory failed", hr);
    }
    ComPtr<IWindowsXamlManager> manager;
    hr = managerStatics->InitializeForCurrentThread(manager.ReleaseAndGetAddressOf());
    if (FAILED(hr)) {
        return fail("WindowsXamlManager init failed", hr);
    }

    WNDCLASSEXW previewClass{};
    previewClass.cbSize = sizeof(previewClass);
    previewClass.lpfnWndProc = previewProc;
    previewClass.hInstance = GetModuleHandleW(nullptr);
    previewClass.lpszClassName = L"BlitzWinUiPreview";
    previewClass.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    RegisterClassExW(&previewClass);

    HICON appIcon = LoadIconW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(101));
    WNDCLASSEXW wc{};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = wndProc;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpszClassName = L"BlitzRecorderWinUI";
    wc.hbrBackground = reinterpret_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.hIcon = appIcon;
    wc.hIconSm = appIcon;
    RegisterClassExW(&wc);

    HWND window = CreateWindowExW(
        0,
        L"BlitzRecorderWinUI",
        L"BlitzRecorder",
        WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_CLIPCHILDREN,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        976,
        720,
        nullptr,
        nullptr,
        GetModuleHandleW(nullptr),
        nullptr
    );
    if (!window) {
        return fail("WinUI host window failed");
    }
    br::excludeWindowFromCapture(window);

    ComPtr<IInspectable> sourceInspectable;
    HString sourceName(RuntimeClass_Windows_UI_Xaml_Hosting_DesktopWindowXamlSource);
    hr = RoActivateInstance(sourceName.get(), sourceInspectable.ReleaseAndGetAddressOf());
    if (FAILED(hr)) {
        DestroyWindow(window);
        return fail("DesktopWindowXamlSource activate failed", hr);
    }
    ComPtr<::IDesktopWindowXamlSourceNative> native;
    hr = sourceInspectable.As(&native);
    if (FAILED(hr) || FAILED(native->AttachToWindow(window))) {
        DestroyWindow(window);
        return fail("XAML Island AttachToWindow failed", hr);
    }
    ComPtr<::IDesktopWindowXamlSourceNative2> native2;
    sourceInspectable.As(&native2);
    HWND island = nullptr;
    native->get_WindowHandle(&island);
    SetWindowPos(island, nullptr, 0, 0, 960, 220, SWP_NOZORDER | SWP_SHOWWINDOW);
    br::excludeWindowFromCapture(island);

    ComPtr<IXamlReaderStatics> reader;
    HString readerName(RuntimeClass_Windows_UI_Xaml_Markup_XamlReader);
    hr = activateFactory(readerName.get(), reader);
    if (FAILED(hr) || !reader) {
        DestroyWindow(window);
        return fail("XamlReader factory failed", hr);
    }
    HString xaml(kXaml);
    ComPtr<IInspectable> tree;
    hr = reader->Load(xaml.get(), tree.ReleaseAndGetAddressOf());
    if (FAILED(hr) || !tree) {
        DestroyWindow(window);
        return fail("XAML Island markup failed", hr);
    }
    ComPtr<IDesktopWindowXamlSource> source;
    if (FAILED(sourceInspectable.As(&source)) || !source) {
        DestroyWindow(window);
        return fail("DesktopWindowXamlSource QI failed");
    }
    ComPtr<IUIElement> element;
    if (FAILED(tree.As(&element)) || !element) {
        DestroyWindow(window);
        return fail("XAML tree is not a UIElement");
    }
    hr = source->put_Content(element.Get());
    if (FAILED(hr)) {
        DestroyWindow(window);
        return fail("XAML Island put_Content failed", hr);
    }

    gUi = {};
    gUi.outputRoot = outputRoot ? outputRoot : "";
    gUi.monitor = monitorIndex;
    gUi.prepare = prepare;
    gUi.ctx = ctx;
    gUi.window = window;
    gUi.island = island;
    gUi.root = tree;
    gUi.sys = true;
    gUi.mic = true;
    if (FAILED(hookButton(tree.Get(), L"StartButton", startCapture))
        || FAILED(hookButton(tree.Get(), L"StopButton", stopCapture))
        || FAILED(hookButton(tree.Get(), L"OpenButton", openTake))
        || FAILED(hookButton(tree.Get(), L"ExportButton", exportLast))) {
        gUi.window = nullptr;
        DestroyWindow(window);
        return fail("WinUI buttons failed");
    }
    hookCheckBox(tree.Get(), L"SysBox", &gUi.sys);
    hookCheckBox(tree.Get(), L"MicBox", &gUi.mic);
    hookCheckBox(tree.Get(), L"CamBox", &gUi.cam);
    fillMonitorBox();
    hookMonitorDropDown();
    setRecordingButtons(false);
    {
        std::string ready = "Ready — takes in ";
        ready += gUi.outputRoot.empty() ? "Videos\\BlitzRecorder" : gUi.outputRoot;
        setStatus(ready.c_str());
    }

    gUi.preview = CreateWindowW(
        L"BlitzWinUiPreview",
        L"",
        WS_CHILD | WS_VISIBLE | WS_BORDER,
        8,
        228,
        944,
        450,
        window,
        nullptr,
        GetModuleHandleW(nullptr),
        nullptr
    );
    br::excludeWindowFromCapture(gUi.preview);
    SetTimer(window, 1, 33, nullptr);
    layoutChrome(window);
    gUi.enteredLoop = true;
    ShowWindow(window, SW_SHOW);
    UpdateWindow(window);
    br::hideOwnConsole();

    MSG msg{};
    while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
        BOOL processed = FALSE;
        if (native2) {
            native2->PreTranslateMessage(&msg, &processed);
        }
        if (processed) {
            continue;
        }
        if (msg.message == WM_KEYDOWN && (msg.wParam == VK_SPACE || msg.wParam == VK_ESCAPE)) {
            onTransportKey(msg.wParam);
            continue;
        }
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    gUi = {};
    return 0;
}

#else
[[maybe_unused]] static int br_windows_capture_tu_winui = 0;
#endif
