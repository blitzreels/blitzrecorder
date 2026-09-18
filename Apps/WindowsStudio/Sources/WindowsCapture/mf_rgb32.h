#pragma once

#if defined(_WIN32)

#include <cstdint>
#include <vector>

#include <windows.h>
#include <mfobjects.h>

HRESULT copyMediaBufferToTopDownBGRA(
    IMFMediaBuffer* buffer,
    UINT width,
    UINT height,
    INT32 defaultStride,
    std::vector<std::uint8_t>& bgra
);

#endif
