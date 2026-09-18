#pragma once

#if defined(_WIN32)

#include <cstdint>
#include <string>
#include <vector>

#include <windows.h>
#include <wrl/client.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>

class CameraReader {
public:
    ~CameraReader() { close(); }

    HRESULT open();
    void abort();
    void close();
    HRESULT readBGRA(std::vector<std::uint8_t>& bgra, UINT& width, UINT& height);
    UINT width() const { return width_; }
    UINT height() const { return height_; }

private:
    HRESULT tryOpenActivate(IMFActivate* activate);

    Microsoft::WRL::ComPtr<IMFMediaSource> source_;
    Microsoft::WRL::ComPtr<IMFSourceReader> reader_;
    UINT width_ = 0;
    UINT height_ = 0;
    INT32 stride_ = 0;
};

#endif
