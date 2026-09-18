#if defined(_WIN32)

#include "mf_rgb32.h"

#include <algorithm>
#include <cstring>

#include <wrl/client.h>

HRESULT copyMediaBufferToTopDownBGRA(
    IMFMediaBuffer* buffer,
    UINT width,
    UINT height,
    INT32 defaultStride,
    std::vector<std::uint8_t>& bgra
) {
    if (!buffer || width < 2 || height < 2) {
        return E_INVALIDARG;
    }
    const UINT dstStride = width * 4;
    bgra.assign(static_cast<size_t>(width) * height * 4, 0);

    Microsoft::WRL::ComPtr<IMF2DBuffer> buffer2D;
    BYTE* data = nullptr;
    LONG pitch = 0;
    bool locked2D = false;
    if (SUCCEEDED(buffer->QueryInterface(IID_PPV_ARGS(&buffer2D))) && buffer2D) {
        if (SUCCEEDED(buffer2D->Lock2D(&data, &pitch)) && data && pitch != 0) {
            locked2D = true;
        }
    }

    if (!locked2D) {
        const HRESULT hr = buffer->Lock(&data, nullptr, nullptr);
        if (FAILED(hr) || !data) {
            return FAILED(hr) ? hr : E_POINTER;
        }
        pitch = defaultStride != 0 ? defaultStride : static_cast<LONG>(dstStride);
    }

    const UINT absPitch = static_cast<UINT>(pitch < 0 ? -pitch : pitch);
    const UINT rowBytes = (std::min)(dstStride, absPitch);
    for (UINT y = 0; y < height; ++y) {
        const BYTE* src = pitch >= 0
            ? data + static_cast<size_t>(y) * static_cast<size_t>(pitch)
            : data + static_cast<size_t>(height - 1 - y) * static_cast<size_t>(-pitch);
        std::memcpy(bgra.data() + static_cast<size_t>(y) * dstStride, src, rowBytes);
    }

    if (locked2D) {
        buffer2D->Unlock2D();
    } else {
        buffer->Unlock();
    }
    return S_OK;
}

#else
[[maybe_unused]] static int br_windows_capture_tu_rgb32 = 0;
#endif
