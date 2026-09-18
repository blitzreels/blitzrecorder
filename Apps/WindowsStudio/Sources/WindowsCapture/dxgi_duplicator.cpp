#if defined(_WIN32)

#include "dxgi_duplicator.h"

#include "capture_common.h"
#include "monitor_list.h"

#include <algorithm>
#include <cstring>

namespace {

constexpr UINT kPointerColor = DXGI_OUTDUPL_POINTER_SHAPE_TYPE_COLOR;
constexpr UINT kPointerMasked = DXGI_OUTDUPL_POINTER_SHAPE_TYPE_MASKED_COLOR;
constexpr UINT kPointerMono = DXGI_OUTDUPL_POINTER_SHAPE_TYPE_MONOCHROME;

inline std::uint8_t blendChannel(std::uint8_t dst, std::uint8_t src, std::uint8_t alpha) {
    return static_cast<std::uint8_t>((src * alpha + dst * (255 - alpha) + 127) / 255);
}

bool bitAt(const std::uint8_t* bits, UINT pitch, UINT x, UINT y) {
    const std::uint8_t byte = bits[y * pitch + (x / 8)];
    return (byte & (0x80 >> (x % 8))) != 0;
}

}  // namespace

HRESULT DesktopDuplicator::open(int monitorIndex) {
    close();
    monitorIndex_ = monitorIndex;
    OutputPick pick;
    HRESULT hr = pickOutput(monitorIndex, pick);
    if (FAILED(hr)) {
        return hr;
    }
    adapter_ = pick.adapter;
    output_ = pick.output;
    outputDesc_ = pick.desc;
    hr = createDevice(adapter_.Get());
    if (FAILED(hr)) {
        close();
        return hr;
    }
    hr = duplicate(output_.Get());
    if (FAILED(hr)) {
        close();
        return hr;
    }
    return S_OK;
}

void DesktopDuplicator::close() {
    duplication_.Reset();
    staging_.Reset();
    context_.Reset();
    device_.Reset();
    output_.Reset();
    adapter_.Reset();
    pointerPixels_.clear();
    pointerShape_ = {};
    pointerPos_ = {};
    width_ = 0;
    height_ = 0;
}

HRESULT DesktopDuplicator::rebind() {
    const int index = monitorIndex_;
    close();
    return open(index);
}

HRESULT DesktopDuplicator::pickOutput(int monitorIndex, OutputPick& pick) {
    const std::vector<br::AttachedOutput> rows = br::listAttachedOutputs();
    if (rows.empty()) {
        br::setLastError("No attached DXGI desktop output. DXGI Desktop Duplication needs an interactive GPU desktop session.");
        return HRESULT_FROM_WIN32(ERROR_NOT_FOUND);
    }
    if (monitorIndex < 0 || static_cast<size_t>(monitorIndex) >= rows.size()) {
        br::setLastError("monitor_index is out of range");
        return E_INVALIDARG;
    }
    const br::AttachedOutput& row = rows[static_cast<size_t>(monitorIndex)];
    pick.adapter = row.adapter;
    pick.output = row.output;
    pick.primary = row.primary;
    if (row.output) {
        row.output->GetDesc(&pick.desc);
    }
    return S_OK;
}

HRESULT DesktopDuplicator::createDevice(IDXGIAdapter1* adapter) {
    D3D_FEATURE_LEVEL levels[] = {
        D3D_FEATURE_LEVEL_11_1,
        D3D_FEATURE_LEVEL_11_0,
        D3D_FEATURE_LEVEL_10_1,
        D3D_FEATURE_LEVEL_10_0
    };
    D3D_FEATURE_LEVEL got{};
    HRESULT hr = D3D11CreateDevice(
        adapter,
        D3D_DRIVER_TYPE_UNKNOWN,
        nullptr,
        D3D11_CREATE_DEVICE_BGRA_SUPPORT,
        levels,
        4,
        D3D11_SDK_VERSION,
        device_.ReleaseAndGetAddressOf(),
        &got,
        context_.ReleaseAndGetAddressOf()
    );
    if (FAILED(hr)) {
        br::setLastError("D3D11CreateDevice failed on the output adapter (WARP cannot duplicate a desktop)", hr);
    }
    return hr;
}

HRESULT DesktopDuplicator::duplicate(IDXGIOutput1* output) {
    HRESULT hr = output->DuplicateOutput(device_.Get(), duplication_.ReleaseAndGetAddressOf());
    if (FAILED(hr)) {
        if (hr == E_ACCESSDENIED || hr == DXGI_ERROR_ACCESS_DENIED) {
            br::setLastError(
                "Desktop Duplication access denied. Allow Screen recording in Windows Settings > Privacy, and use an interactive desktop (not Session 0 / a service / UAC secure desktop).",
                hr
            );
        } else if (hr == DXGI_ERROR_UNSUPPORTED) {
            br::setLastError(
                "Desktop Duplication is unsupported on this output (WARP / Session 0 / cloned display).",
                hr
            );
        } else {
            br::setLastError("IDXGIOutput1::DuplicateOutput failed", hr);
        }
        return hr;
    }
    DXGI_OUTDUPL_DESC dupDesc{};
    duplication_->GetDesc(&dupDesc);
    width_ = dupDesc.ModeDesc.Width;
    height_ = dupDesc.ModeDesc.Height;
    if (width_ == 0 || height_ == 0) {
        const RECT& desktop = outputDesc_.DesktopCoordinates;
        width_ = static_cast<UINT>((std::max)(0L, desktop.right - desktop.left));
        height_ = static_cast<UINT>((std::max)(0L, desktop.bottom - desktop.top));
    }
    width_ &= ~1u;
    height_ &= ~1u;
    if (width_ < 2 || height_ < 2) {
        br::setLastError("Desktop output size is too small to encode");
        return E_UNEXPECTED;
    }
    return S_OK;
}

HRESULT DesktopDuplicator::ensureStaging(ID3D11Texture2D* gpuTex) {
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

HRESULT DesktopDuplicator::acquireBGRA(UINT timeoutMs, std::vector<std::uint8_t>& bgra, UINT& width, UINT& height) {
    if (!duplication_) {
        return E_FAIL;
    }

    DXGI_OUTDUPL_FRAME_INFO frameInfo{};
    Microsoft::WRL::ComPtr<IDXGIResource> resource;
    HRESULT hr = duplication_->AcquireNextFrame(timeoutMs, &frameInfo, resource.ReleaseAndGetAddressOf());
    if (hr == DXGI_ERROR_WAIT_TIMEOUT) {
        width = width_;
        height = height_;
        return S_FALSE;
    }
    if (hr == DXGI_ERROR_ACCESS_LOST || hr == DXGI_ERROR_INVALID_CALL) {
        br::setLastError("Desktop Duplication access lost (mode change or switched desktop)", hr);
        return hr;
    }
    if (hr == DXGI_ERROR_ACCESS_DENIED || hr == DXGI_ERROR_UNSUPPORTED) {
        br::setLastError("Screen capture is in use or blocked on this desktop", hr);
        return hr;
    }
    if (FAILED(hr)) {
        br::setLastError("AcquireNextFrame failed", hr);
        return hr;
    }

    struct ReleaseGuard {
        IDXGIOutputDuplication* dup;
        ~ReleaseGuard() { if (dup) dup->ReleaseFrame(); }
    } release{duplication_.Get()};

    if (frameInfo.PointerPosition.Visible || frameInfo.LastMouseUpdateTime.QuadPart != 0) {
        pointerPos_ = frameInfo.PointerPosition;
    }
    if (frameInfo.PointerShapeBufferSize > 0) {
        pointerPixels_.resize(frameInfo.PointerShapeBufferSize);
        UINT used = 0;
        hr = duplication_->GetFramePointerShape(
            frameInfo.PointerShapeBufferSize,
            pointerPixels_.data(),
            &used,
            &pointerShape_
        );
        if (FAILED(hr)) {
            pointerPixels_.clear();
        } else {
            pointerPixels_.resize(used);
        }
    }

    if (!resource) {
        width = width_;
        height = height_;
        return S_FALSE;
    }

    Microsoft::WRL::ComPtr<ID3D11Texture2D> gpuTex;
    hr = resource.As(&gpuTex);
    if (FAILED(hr)) {
        return hr;
    }
    hr = ensureStaging(gpuTex.Get());
    if (FAILED(hr)) {
        br::setLastError("Create staging texture failed", hr);
        return hr;
    }
    context_->CopyResource(staging_.Get(), gpuTex.Get());

    D3D11_TEXTURE2D_DESC stagingDesc{};
    staging_->GetDesc(&stagingDesc);
    const UINT copyW = (std::min)(width_, stagingDesc.Width) & ~1u;
    const UINT copyH = (std::min)(height_, stagingDesc.Height) & ~1u;
    width_ = copyW;
    height_ = copyH;

    D3D11_MAPPED_SUBRESOURCE mapped{};
    hr = context_->Map(staging_.Get(), 0, D3D11_MAP_READ, 0, &mapped);
    if (FAILED(hr)) {
        br::setLastError("Map staging texture failed", hr);
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

    compositeCursor(bgra.data(), copyW, copyH);
    width = copyW;
    height = copyH;
    return S_OK;
}

void DesktopDuplicator::compositeCursor(std::uint8_t* bgra, UINT width, UINT height) const {
    if (!pointerPos_.Visible || pointerPixels_.empty() || width == 0 || height == 0) {
        return;
    }
    const RECT& desktop = outputDesc_.DesktopCoordinates;
    const int originX = desktop.left;
    const int originY = desktop.top;
    const int posX = pointerPos_.Position.x - originX;
    const int posY = pointerPos_.Position.y - originY;
    const UINT shapeW = pointerShape_.Width;
    UINT shapeH = pointerShape_.Height;
    const UINT pitch = pointerShape_.Pitch;
    const UINT type = pointerShape_.Type;
    if (shapeW == 0 || shapeH == 0 || pitch == 0) {
        return;
    }
    if (pointerPixels_.size() < static_cast<size_t>(shapeH) * pitch) {
        return;
    }
    const std::uint8_t* src = pointerPixels_.data();
    if (type == kPointerMono) {
        shapeH /= 2;
    }

    for (UINT y = 0; y < shapeH; ++y) {
        const int dy = posY + static_cast<int>(y);
        if (dy < 0 || dy >= static_cast<int>(height)) {
            continue;
        }
        for (UINT x = 0; x < shapeW; ++x) {
            const int dx = posX + static_cast<int>(x);
            if (dx < 0 || dx >= static_cast<int>(width)) {
                continue;
            }
            std::uint8_t* dst = bgra + (static_cast<size_t>(dy) * width + static_cast<size_t>(dx)) * 4;
            if (type == kPointerColor) {
                const std::uint8_t* p = src + y * pitch + x * 4;
                const std::uint8_t a = p[3];
                if (a == 0) {
                    continue;
                }
                dst[0] = blendChannel(dst[0], p[0], a);
                dst[1] = blendChannel(dst[1], p[1], a);
                dst[2] = blendChannel(dst[2], p[2], a);
            } else if (type == kPointerMasked) {
                const std::uint8_t* p = src + y * pitch + x * 4;
                if (p[3] == 0xFF) {
                    dst[0] ^= p[0];
                    dst[1] ^= p[1];
                    dst[2] ^= p[2];
                } else {
                    dst[0] = p[0];
                    dst[1] = p[1];
                    dst[2] = p[2];
                }
            } else if (type == kPointerMono) {
                const bool andBit = bitAt(src, pitch, x, y);
                const bool xorBit = bitAt(src + shapeH * pitch, pitch, x, y);
                if (andBit && !xorBit) {
                    continue;
                }
                if (!andBit && !xorBit) {
                    dst[0] = dst[1] = dst[2] = 0;
                } else if (!andBit && xorBit) {
                    dst[0] = dst[1] = dst[2] = 255;
                } else {
                    dst[0] = static_cast<std::uint8_t>(dst[0] ^ 255);
                    dst[1] = static_cast<std::uint8_t>(dst[1] ^ 255);
                    dst[2] = static_cast<std::uint8_t>(dst[2] ^ 255);
                }
            }
        }
    }
}

#else
[[maybe_unused]] static int br_windows_capture_tu_dxgi = 0;
#endif
