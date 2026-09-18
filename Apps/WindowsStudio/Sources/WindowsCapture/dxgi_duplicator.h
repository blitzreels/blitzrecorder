#pragma once

#if defined(_WIN32)

#include <cstdint>
#include <vector>

#include <windows.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <wrl/client.h>

class DesktopDuplicator {
public:
    HRESULT open(int monitorIndex);
    void close();
    HRESULT rebind();

    // S_OK: desktop image copied into bgra (tight BGRA, top-down, stride = width*4).
    // S_FALSE: timeout, no new frame (bgra left unchanged if it already had pixels).
    HRESULT acquireBGRA(UINT timeoutMs, std::vector<std::uint8_t>& bgra, UINT& width, UINT& height);

    UINT width() const { return width_; }
    UINT height() const { return height_; }

private:
    struct OutputPick {
        Microsoft::WRL::ComPtr<IDXGIAdapter1> adapter;
        Microsoft::WRL::ComPtr<IDXGIOutput1> output;
        DXGI_OUTPUT_DESC desc{};
        bool primary = false;
    };

    HRESULT pickOutput(int monitorIndex, OutputPick& pick);
    HRESULT createDevice(IDXGIAdapter1* adapter);
    HRESULT duplicate(IDXGIOutput1* output);
    HRESULT ensureStaging(ID3D11Texture2D* gpuTex);
    void compositeCursor(std::uint8_t* bgra, UINT width, UINT height) const;

    Microsoft::WRL::ComPtr<IDXGIAdapter1> adapter_;
    Microsoft::WRL::ComPtr<IDXGIOutput1> output_;
    Microsoft::WRL::ComPtr<ID3D11Device> device_;
    Microsoft::WRL::ComPtr<ID3D11DeviceContext> context_;
    Microsoft::WRL::ComPtr<IDXGIOutputDuplication> duplication_;
    Microsoft::WRL::ComPtr<ID3D11Texture2D> staging_;
    DXGI_OUTPUT_DESC outputDesc_{};
    DXGI_OUTDUPL_POINTER_SHAPE_INFO pointerShape_{};
    DXGI_OUTDUPL_POINTER_POSITION pointerPos_{};
    std::vector<std::uint8_t> pointerPixels_;
    UINT width_ = 0;
    UINT height_ = 0;
    int monitorIndex_ = 0;
};

#endif
