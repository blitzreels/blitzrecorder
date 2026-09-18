#if defined(_WIN32)

#include "mf_camera.h"

#include "capture_common.h"
#include "mf_rgb32.h"

#include <cstring>
#include <string>
#include <vector>

#include <mfapi.h>
#include <mferror.h>

#pragma comment(lib, "mf.lib")
#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mfreadwrite.lib")
#pragma comment(lib, "mfuuid.lib")

namespace {

bool looksLikeIrOrHelloCamera(const wchar_t* name) {
    if (!name || !name[0]) {
        return false;
    }
    std::wstring lower(name);
    for (wchar_t& ch : lower) {
        if (ch >= L'A' && ch <= L'Z') {
            ch = static_cast<wchar_t>(ch - L'A' + L'a');
        }
    }
    auto has = [&](const wchar_t* needle) {
        return lower.find(needle) != std::wstring::npos;
    };
    return has(L"infrared")
        || has(L"windows hello")
        || has(L"ir camera")
        || has(L"ir webcam")
        || has(L"rgb-ir")
        || has(L"rgbir")
        || has(L"tof camera")
        || has(L"depth camera");
}

void releaseActivates(IMFActivate** devices, UINT32 count) {
    if (!devices) {
        return;
    }
    for (UINT32 i = 0; i < count; ++i) {
        if (devices[i]) {
            devices[i]->Release();
        }
    }
    CoTaskMemFree(devices);
}

}  // namespace

HRESULT CameraReader::tryOpenActivate(IMFActivate* activate) {
    close();
    if (!activate) {
        return E_POINTER;
    }

    HRESULT hr = activate->ActivateObject(
        __uuidof(IMFMediaSource),
        reinterpret_cast<void**>(source_.ReleaseAndGetAddressOf())
    );
    if (FAILED(hr) || !source_) {
        br::setLastError("Camera ActivateObject failed", hr);
        close();
        return FAILED(hr) ? hr : E_FAIL;
    }

    Microsoft::WRL::ComPtr<IMFAttributes> readerAttrs;
    hr = MFCreateAttributes(&readerAttrs, 2);
    if (FAILED(hr)) {
        close();
        return hr;
    }
    readerAttrs->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE);
    hr = MFCreateSourceReaderFromMediaSource(source_.Get(), readerAttrs.Get(), &reader_);
    if (FAILED(hr)) {
        br::setLastError("MFCreateSourceReaderFromMediaSource failed", hr);
        close();
        return hr;
    }

    Microsoft::WRL::ComPtr<IMFMediaType> type;
    hr = MFCreateMediaType(&type);
    if (FAILED(hr)) {
        close();
        return hr;
    }
    type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
    hr = reader_->SetCurrentMediaType(static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), nullptr, type.Get());
    if (FAILED(hr)) {
        br::setLastError("Camera RGB32 media type rejected", hr);
        close();
        return hr;
    }

    Microsoft::WRL::ComPtr<IMFMediaType> current;
    hr = reader_->GetCurrentMediaType(static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), &current);
    if (FAILED(hr)) {
        close();
        return hr;
    }
    UINT32 w = 0;
    UINT32 h = 0;
    MFGetAttributeSize(current.Get(), MF_MT_FRAME_SIZE, &w, &h);
    width_ = w & ~1u;
    height_ = h & ~1u;
    if (width_ < 320 || height_ < 240) {
        br::setLastError("Camera frame size is too small");
        close();
        return E_UNEXPECTED;
    }
    UINT32 strideAttr = 0;
    stride_ = static_cast<INT32>(width_ * 4);
    if (SUCCEEDED(current->GetUINT32(MF_MT_DEFAULT_STRIDE, &strideAttr)) && strideAttr != 0) {
        stride_ = static_cast<INT32>(strideAttr);
    }
    return S_OK;
}

HRESULT CameraReader::open() {
    close();
    HRESULT hr = MFStartup(MF_VERSION, MFSTARTUP_LITE);
    if (FAILED(hr) && hr != MF_E_ALREADY_INITIALIZED) {
        br::setLastError("MFStartup failed for camera", hr);
        return hr;
    }

    Microsoft::WRL::ComPtr<IMFAttributes> attributes;
    hr = MFCreateAttributes(&attributes, 1);
    if (FAILED(hr)) {
        return hr;
    }
    attributes->SetGUID(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE, MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID);

    IMFActivate** devices = nullptr;
    UINT32 count = 0;
    hr = MFEnumDeviceSources(attributes.Get(), &devices, &count);
    if (FAILED(hr) || count == 0 || !devices) {
        br::setLastError("No camera capture device. Connect a webcam or turn Camera access on for desktop apps.");
        releaseActivates(devices, count);
        return FAILED(hr) ? hr : HRESULT_FROM_WIN32(ERROR_NOT_FOUND);
    }

    struct Slot {
        IMFActivate* activate = nullptr;
        bool ir = false;
    };
    std::vector<Slot> slots;
    slots.reserve(count);
    for (UINT32 i = 0; i < count; ++i) {
        WCHAR* name = nullptr;
        UINT32 nameLen = 0;
        devices[i]->GetAllocatedString(MF_DEVSOURCE_ATTRIBUTE_FRIENDLY_NAME, &name, &nameLen);
        Slot slot;
        slot.activate = devices[i];
        slot.ir = looksLikeIrOrHelloCamera(name);
        if (name) {
            CoTaskMemFree(name);
        }
        slots.push_back(slot);
    }

    HRESULT lastHr = HRESULT_FROM_WIN32(ERROR_NOT_FOUND);
    auto tryPass = [&](bool wantIr) -> bool {
        for (const Slot& slot : slots) {
            if (slot.ir != wantIr) {
                continue;
            }
            lastHr = tryOpenActivate(slot.activate);
            if (SUCCEEDED(lastHr)) {
                return true;
            }
        }
        return false;
    };

    const bool opened = tryPass(false) || tryPass(true);
    releaseActivates(devices, count);
    if (!opened) {
        close();
        if (FAILED(lastHr) && lastHr != HRESULT_FROM_WIN32(ERROR_NOT_FOUND)) {
            return lastHr;
        }
        br::setLastError("No usable RGB camera. Skip Windows Hello / IR sensors or turn Camera access on.");
        return lastHr;
    }
    return S_OK;
}

void CameraReader::abort() {
    if (source_) {
        source_->Shutdown();
    }
}

void CameraReader::close() {
    reader_.Reset();
    if (source_) {
        source_->Shutdown();
        source_.Reset();
    }
    width_ = 0;
    height_ = 0;
    stride_ = 0;
}

HRESULT CameraReader::readBGRA(std::vector<std::uint8_t>& bgra, UINT& width, UINT& height) {
    if (!reader_) {
        return E_FAIL;
    }
    Microsoft::WRL::ComPtr<IMFSample> sample;
    DWORD flags = 0;
    HRESULT hr = reader_->ReadSample(
        static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM),
        0,
        nullptr,
        &flags,
        nullptr,
        &sample
    );
    if (FAILED(hr)) {
        return hr;
    }
    if (flags & MF_SOURCE_READERF_ENDOFSTREAM) {
        return S_FALSE;
    }
    if (!sample) {
        return S_FALSE;
    }
    Microsoft::WRL::ComPtr<IMFMediaBuffer> buffer;
    hr = sample->ConvertToContiguousBuffer(&buffer);
    if (FAILED(hr)) {
        return hr;
    }
    hr = copyMediaBufferToTopDownBGRA(buffer.Get(), width_, height_, stride_, bgra);
    if (FAILED(hr)) {
        return hr;
    }
    width = width_;
    height = height_;
    return S_OK;
}

#else
[[maybe_unused]] static int br_windows_capture_tu_camera = 0;
#endif
