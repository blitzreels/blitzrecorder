#pragma once

#if defined(_WIN32)

#include <cstdint>
#include <vector>

#include <windows.h>
#include <d3d11.h>
#include <wrl/client.h>

class WgcCapturer {
public:
    WgcCapturer() = default;
    WgcCapturer(const WgcCapturer&) = delete;
    WgcCapturer& operator=(const WgcCapturer&) = delete;
    ~WgcCapturer() { close(); }

    HRESULT open(int monitorIndex);
    HRESULT openWindow(HWND window);
    void close();
    HRESULT rebind();
    HRESULT acquireBGRA(UINT timeoutMs, std::vector<std::uint8_t>& bgra, UINT& width, UINT& height);

    UINT width() const { return width_; }
    UINT height() const { return height_; }
    bool isOpen() const { return session_ != nullptr; }

private:
    HRESULT pickMonitor(int monitorIndex, HMONITOR& monitor, UINT& width, UINT& height);
    HRESULT createDevice();
    HRESULT createPoolAndSession(HMONITOR monitor, HWND window);
    HRESULT copyTexture(ID3D11Texture2D* gpuTex, std::vector<std::uint8_t>& bgra, UINT& width, UINT& height);
    HRESULT ensureStaging(ID3D11Texture2D* gpuTex);

    Microsoft::WRL::ComPtr<ID3D11Device> device_;
    Microsoft::WRL::ComPtr<ID3D11DeviceContext> context_;
    Microsoft::WRL::ComPtr<IUnknown> winrtDevice_;
    Microsoft::WRL::ComPtr<IUnknown> item_;
    Microsoft::WRL::ComPtr<IUnknown> pool_;
    Microsoft::WRL::ComPtr<IUnknown> session_;
    Microsoft::WRL::ComPtr<ID3D11Texture2D> staging_;
    HMONITOR monitor_ = nullptr;
    HWND window_ = nullptr;
    UINT width_ = 0;
    UINT height_ = 0;
    int monitorIndex_ = 0;
};

#endif
