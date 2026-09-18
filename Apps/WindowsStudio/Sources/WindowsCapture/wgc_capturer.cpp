#if defined(_WIN32)

#include "wgc_capturer.h"

#include "capture_common.h"
#include "monitor_list.h"

#include <algorithm>
#include <cstring>
#include <string>
#include <vector>

#include <dwmapi.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <combaseapi.h>
#include "winrt_compat.h"
#include <inspectable.h>
#include <roapi.h>
#include <unknwn.h>
#include <winstring.h>
#include <windows.foundation.h>
#include <windows.graphics.capture.h>
#include <windows.graphics.directx.direct3d11.h>
#include "winrt_interop.h"
#include "winrt_compat.h"

#ifndef DWMWA_CLOAKED
#define DWMWA_CLOAKED 14
#endif

#pragma comment(lib, "windowsapp.lib")
#pragma comment(lib, "runtimeobject.lib")
#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "dwmapi.lib")

using ABI::Windows::Foundation::IClosable;
using ABI::Windows::Graphics::Capture::IDirect3D11CaptureFrame;
using ABI::Windows::Graphics::Capture::IDirect3D11CaptureFramePool;
using ABI::Windows::Graphics::Capture::IDirect3D11CaptureFramePoolStatics2;
using ABI::Windows::Graphics::Capture::IGraphicsCaptureItem;
using ABI::Windows::Graphics::Capture::IGraphicsCaptureSession;
using ABI::Windows::Graphics::Capture::IGraphicsCaptureSession2;
using ABI::Windows::Graphics::DirectX::Direct3D11::IDirect3DDevice;
using ABI::Windows::Graphics::DirectX::DirectXPixelFormat_B8G8R8A8UIntNormalized;
using ABI::Windows::Graphics::SizeInt32;

namespace {

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

MIDL_INTERFACE("f2cdd966-22ae-5ea1-9596-3a289344c3be")
IBrGraphicsCaptureSession3 : public IInspectable {
    virtual HRESULT STDMETHODCALLTYPE get_IsBorderRequired(boolean* value) = 0;
    virtual HRESULT STDMETHODCALLTYPE put_IsBorderRequired(boolean value) = 0;
};

template <typename T>
HRESULT activate(const wchar_t* runtimeClass, Microsoft::WRL::ComPtr<T>& out) {
    HString name(runtimeClass);
    out.Reset();
    HRESULT hr = RoGetActivationFactory(name.get(), IID_PPV_ARGS(&out));
    if (SUCCEEDED(hr) && out) {
        return hr;
    }
    Microsoft::WRL::ComPtr<IUnknown> unk;
    hr = RoGetActivationFactory(name.get(), IID_PPV_ARGS(&unk));
    if (FAILED(hr) || !unk) {
        return hr;
    }
    return unk.As(&out);
}

void disableWgcBorder(IGraphicsCaptureSession* session) {
    if (!session) {
        return;
    }
    Microsoft::WRL::ComPtr<IBrGraphicsCaptureSession3> session3;
    if (SUCCEEDED(session->QueryInterface(IID_PPV_ARGS(&session3))) && session3) {
        session3->put_IsBorderRequired(FALSE);
    }
}

}  // namespace

HRESULT WgcCapturer::pickMonitor(int monitorIndex, HMONITOR& monitor, UINT& width, UINT& height) {
    const std::vector<br::AttachedOutput> rows = br::listAttachedOutputs();
    if (rows.empty()) {
        br::setLastError("No attached monitor for Windows Graphics Capture");
        return HRESULT_FROM_WIN32(ERROR_NOT_FOUND);
    }
    if (monitorIndex < 0 || static_cast<size_t>(monitorIndex) >= rows.size()) {
        br::setLastError("monitor_index is out of range");
        return E_INVALIDARG;
    }
    const br::AttachedOutput& row = rows[static_cast<size_t>(monitorIndex)];
    monitor = static_cast<HMONITOR>(row.monitor);
    width = row.width;
    height = row.height;
    return S_OK;
}

HRESULT WgcCapturer::createDevice() {
    D3D_FEATURE_LEVEL levels[] = {
        D3D_FEATURE_LEVEL_11_1,
        D3D_FEATURE_LEVEL_11_0,
        D3D_FEATURE_LEVEL_10_0
    };
    D3D_FEATURE_LEVEL got{};
    HRESULT hr = D3D11CreateDevice(
        nullptr,
        D3D_DRIVER_TYPE_HARDWARE,
        nullptr,
        D3D11_CREATE_DEVICE_BGRA_SUPPORT,
        levels,
        3,
        D3D11_SDK_VERSION,
        device_.ReleaseAndGetAddressOf(),
        &got,
        context_.ReleaseAndGetAddressOf()
    );
    if (FAILED(hr)) {
        hr = D3D11CreateDevice(
            nullptr,
            D3D_DRIVER_TYPE_WARP,
            nullptr,
            D3D11_CREATE_DEVICE_BGRA_SUPPORT,
            levels,
            3,
            D3D11_SDK_VERSION,
            device_.ReleaseAndGetAddressOf(),
            &got,
            context_.ReleaseAndGetAddressOf()
        );
    }
    if (FAILED(hr)) {
        br::setLastError("D3D11CreateDevice failed for WGC", hr);
        return hr;
    }
    Microsoft::WRL::ComPtr<IDXGIDevice> dxgiDevice;
    hr = device_.As(&dxgiDevice);
    if (FAILED(hr)) {
        return hr;
    }
    Microsoft::WRL::ComPtr<IInspectable> inspectable;
    hr = CreateDirect3D11DeviceFromDXGIDevice(dxgiDevice.Get(), inspectable.ReleaseAndGetAddressOf());
    if (FAILED(hr)) {
        br::setLastError("CreateDirect3D11DeviceFromDXGIDevice failed", hr);
        return hr;
    }
    winrtDevice_ = inspectable;
    return S_OK;
}

HRESULT WgcCapturer::createPoolAndSession(HMONITOR monitor, HWND window) {
    Microsoft::WRL::ComPtr<IGraphicsCaptureItemInterop> interop;
    HRESULT hr = activate(RuntimeClass_Windows_Graphics_Capture_GraphicsCaptureItem, interop);
    if (FAILED(hr)) {
        br::setLastError("GraphicsCaptureItem activation factory missing (need Windows 10 1903+)", hr);
        return hr;
    }
    Microsoft::WRL::ComPtr<IGraphicsCaptureItem> item;
    if (window) {
        hr = interop->CreateForWindow(
            window,
            __uuidof(IGraphicsCaptureItem),
            reinterpret_cast<void**>(item.ReleaseAndGetAddressOf())
        );
        if (FAILED(hr) || !item) {
            br::setLastError(
                "WGC CreateForWindow failed. Window may be minimized, protected, or elevated.",
                hr
            );
            return FAILED(hr) ? hr : E_FAIL;
        }
    } else {
        hr = interop->CreateForMonitor(
            monitor,
            __uuidof(IGraphicsCaptureItem),
            reinterpret_cast<void**>(item.ReleaseAndGetAddressOf())
        );
        if (FAILED(hr) || !item) {
            br::setLastError(
                "WGC CreateForMonitor failed. Allow Screen recording in Windows Settings > Privacy. Remote/admin sessions can block Graphics Capture.",
                hr
            );
            return FAILED(hr) ? hr : E_FAIL;
        }
    }
    SizeInt32 size{};
    item->get_Size(&size);
    if (size.Width >= 2) {
        width_ = static_cast<UINT>(size.Width) & ~1u;
    }
    if (size.Height >= 2) {
        height_ = static_cast<UINT>(size.Height) & ~1u;
    }
    if (width_ < 2 || height_ < 2) {
        br::setLastError("WGC item size is too small");
        return E_UNEXPECTED;
    }

    Microsoft::WRL::ComPtr<IDirect3D11CaptureFramePoolStatics2> poolStatics;
    hr = activate(RuntimeClass_Windows_Graphics_Capture_Direct3D11CaptureFramePool, poolStatics);
    if (FAILED(hr)) {
        br::setLastError("Direct3D11CaptureFramePool.CreateFreeThreaded missing (need Windows 10 2004+)", hr);
        return hr;
    }
    Microsoft::WRL::ComPtr<IDirect3DDevice> d3dDevice;
    hr = winrtDevice_.As(&d3dDevice);
    if (FAILED(hr)) {
        return hr;
    }
    SizeInt32 poolSize{};
    poolSize.Width = static_cast<INT32>(width_);
    poolSize.Height = static_cast<INT32>(height_);
    Microsoft::WRL::ComPtr<IDirect3D11CaptureFramePool> pool;
    hr = poolStatics->CreateFreeThreaded(
        d3dDevice.Get(),
        DirectXPixelFormat_B8G8R8A8UIntNormalized,
        2,
        poolSize,
        pool.ReleaseAndGetAddressOf()
    );
    if (FAILED(hr)) {
        br::setLastError("WGC CreateFreeThreaded failed", hr);
        return hr;
    }
    Microsoft::WRL::ComPtr<IGraphicsCaptureSession> session;
    hr = pool->CreateCaptureSession(item.Get(), session.ReleaseAndGetAddressOf());
    if (FAILED(hr)) {
        br::setLastError("WGC CreateCaptureSession failed", hr);
        return hr;
    }
    Microsoft::WRL::ComPtr<IGraphicsCaptureSession2> session2;
    if (SUCCEEDED(session.As(&session2))) {
        session2->put_IsCursorCaptureEnabled(TRUE);
    }
    disableWgcBorder(session.Get());
    hr = session->StartCapture();
    if (FAILED(hr)) {
        br::setLastError("WGC StartCapture failed", hr);
        return hr;
    }
    item_ = item;
    pool_ = pool;
    session_ = session;
    return S_OK;
}

HRESULT WgcCapturer::open(int monitorIndex) {
    close();
    monitorIndex_ = monitorIndex;
    HRESULT hr = pickMonitor(monitorIndex, monitor_, width_, height_);
    if (FAILED(hr)) {
        return hr;
    }
    hr = createDevice();
    if (FAILED(hr)) {
        close();
        return hr;
    }
    hr = createPoolAndSession(monitor_, nullptr);
    if (FAILED(hr)) {
        close();
        return hr;
    }
    return S_OK;
}

HRESULT WgcCapturer::openWindow(HWND window) {
    close();
    if (!window || !IsWindow(window)) {
        br::setLastError("Window capture target is gone");
        return E_INVALIDARG;
    }
    window_ = window;
    monitorIndex_ = -1;
    HRESULT hr = createDevice();
    if (FAILED(hr)) {
        close();
        return hr;
    }
    hr = createPoolAndSession(nullptr, window);
    if (FAILED(hr)) {
        close();
        return hr;
    }
    return S_OK;
}

void WgcCapturer::close() {
    Microsoft::WRL::ComPtr<IClosable> closable;
    if (session_ && SUCCEEDED(session_.As(&closable)) && closable) {
        closable->Close();
    }
    closable.Reset();
    if (pool_ && SUCCEEDED(pool_.As(&closable)) && closable) {
        closable->Close();
    }
    session_.Reset();
    pool_.Reset();
    item_.Reset();
    staging_.Reset();
    winrtDevice_.Reset();
    context_.Reset();
    device_.Reset();
    monitor_ = nullptr;
    window_ = nullptr;
    width_ = 0;
    height_ = 0;
}

HRESULT WgcCapturer::rebind() {
    if (window_) {
        HWND window = window_;
        close();
        return openWindow(window);
    }
    const int index = monitorIndex_;
    close();
    return open(index);
}

HRESULT WgcCapturer::ensureStaging(ID3D11Texture2D* gpuTex) {
    D3D11_TEXTURE2D_DESC desc{};
    gpuTex->GetDesc(&desc);
    desc.Usage = D3D11_USAGE_STAGING;
    desc.BindFlags = 0;
    desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    desc.MiscFlags = 0;
    desc.ArraySize = 1;
    desc.MipLevels = 1;
    desc.SampleDesc.Count = 1;
    desc.SampleDesc.Quality = 0;
    if (staging_) {
        D3D11_TEXTURE2D_DESC existing{};
        staging_->GetDesc(&existing);
        if (existing.Width == desc.Width && existing.Height == desc.Height && existing.Format == desc.Format) {
            return S_OK;
        }
        staging_.Reset();
    }
    return device_->CreateTexture2D(&desc, nullptr, &staging_);
}

HRESULT WgcCapturer::copyTexture(ID3D11Texture2D* gpuTex, std::vector<std::uint8_t>& bgra, UINT& width, UINT& height) {
    HRESULT hr = ensureStaging(gpuTex);
    if (FAILED(hr)) {
        return hr;
    }
    context_->CopyResource(staging_.Get(), gpuTex);
    D3D11_TEXTURE2D_DESC desc{};
    staging_->GetDesc(&desc);
    const UINT copyW = (std::min)(width_, desc.Width) & ~1u;
    const UINT copyH = (std::min)(height_, desc.Height) & ~1u;
    width_ = copyW;
    height_ = copyH;
    D3D11_MAPPED_SUBRESOURCE mapped{};
    hr = context_->Map(staging_.Get(), 0, D3D11_MAP_READ, 0, &mapped);
    if (FAILED(hr)) {
        return hr;
    }
    bgra.resize(static_cast<size_t>(copyW) * copyH * 4);
    const UINT dstStride = copyW * 4;
    for (UINT y = 0; y < copyH; ++y) {
        std::memcpy(
            bgra.data() + static_cast<size_t>(y) * dstStride,
            static_cast<const std::uint8_t*>(mapped.pData) + static_cast<size_t>(y) * mapped.RowPitch,
            dstStride
        );
    }
    context_->Unmap(staging_.Get(), 0);
    width = copyW;
    height = copyH;
    return S_OK;
}

HRESULT WgcCapturer::acquireBGRA(UINT timeoutMs, std::vector<std::uint8_t>& bgra, UINT& width, UINT& height) {
    if (window_) {
        if (!IsWindow(window_)) {
            br::setLastError("Window capture target is gone");
            return HRESULT_FROM_WIN32(ERROR_INVALID_WINDOW_HANDLE);
        }
        if (IsIconic(window_)) {
            br::setLastError("No window frames. Restore the window; DXGI cannot capture a single window.");
            return HRESULT_FROM_WIN32(ERROR_INVALID_WINDOW_HANDLE);
        }
        BOOL cloaked = FALSE;
        if (SUCCEEDED(DwmGetWindowAttribute(window_, DWMWA_CLOAKED, &cloaked, sizeof(cloaked))) && cloaked) {
            br::setLastError("Window capture target is on another desktop. Restore the window.");
            return HRESULT_FROM_WIN32(ERROR_INVALID_WINDOW_HANDLE);
        }
    }
    Microsoft::WRL::ComPtr<IDirect3D11CaptureFramePool> pool;
    if (FAILED(pool_.As(&pool)) || !pool) {
        return E_FAIL;
    }
    const DWORD start = GetTickCount();
    Microsoft::WRL::ComPtr<IDirect3D11CaptureFrame> frame;
    for (;;) {
        frame.Reset();
        const HRESULT hr = pool->TryGetNextFrame(frame.ReleaseAndGetAddressOf());
        if (SUCCEEDED(hr) && frame) {
            break;
        }
        if (GetTickCount() - start >= timeoutMs) {
            width = width_;
            height = height_;
            return S_FALSE;
        }
        Sleep(4);
    }
    Microsoft::WRL::ComPtr<ABI::Windows::Graphics::DirectX::Direct3D11::IDirect3DSurface> surface;
    HRESULT hr = frame->get_Surface(surface.ReleaseAndGetAddressOf());
    if (FAILED(hr) || !surface) {
        return hr;
    }
    Microsoft::WRL::ComPtr<IDirect3DDxgiInterfaceAccess> access;
    hr = surface.As(&access);
    if (FAILED(hr)) {
        return hr;
    }
    Microsoft::WRL::ComPtr<ID3D11Texture2D> texture;
    hr = access->GetInterface(
        __uuidof(ID3D11Texture2D),
        reinterpret_cast<void**>(texture.ReleaseAndGetAddressOf())
    );
    if (FAILED(hr)) {
        br::setLastError("WGC GetInterface(ID3D11Texture2D) failed", hr);
        return hr;
    }
    SizeInt32 content{};
    if (SUCCEEDED(frame->get_ContentSize(&content)) && content.Width >= 2 && content.Height >= 2) {
        const UINT nextW = static_cast<UINT>(content.Width) & ~1u;
        const UINT nextH = static_cast<UINT>(content.Height) & ~1u;
        if (nextW != width_ || nextH != height_) {
            width_ = nextW;
            height_ = nextH;
            Microsoft::WRL::ComPtr<IDirect3DDevice> d3dDevice;
            if (SUCCEEDED(winrtDevice_.As(&d3dDevice)) && d3dDevice) {
                SizeInt32 poolSize{static_cast<INT32>(width_), static_cast<INT32>(height_)};
                pool->Recreate(d3dDevice.Get(), DirectXPixelFormat_B8G8R8A8UIntNormalized, 2, poolSize);
            }
        }
    }
    return copyTexture(texture.Get(), bgra, width, height);
}

#else
[[maybe_unused]] static int br_windows_capture_tu_wgc = 0;
#endif
