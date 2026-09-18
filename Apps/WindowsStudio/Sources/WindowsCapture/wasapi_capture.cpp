#if defined(_WIN32)

#include "wasapi_capture.h"

#include "capture_common.h"

#include <algorithm>
#include <cmath>
#include <cstring>

#include <functiondiscoverykeys_devpkey.h>
#include <avrt.h>
#include <ksmedia.h>

namespace {

WAVEFORMATEX* asWave(std::vector<BYTE>& bytes) {
    return bytes.empty() ? nullptr : reinterpret_cast<WAVEFORMATEX*>(bytes.data());
}

}  // namespace

HRESULT WasapiCapture::open(Kind kind) {
    close();
    Microsoft::WRL::ComPtr<IMMDeviceEnumerator> enumerator;
    HRESULT hr = CoCreateInstance(
        __uuidof(MMDeviceEnumerator),
        nullptr,
        CLSCTX_ALL,
        IID_PPV_ARGS(&enumerator)
    );
    if (FAILED(hr)) {
        br::setLastError("CoCreateInstance(MMDeviceEnumerator) failed", hr);
        return hr;
    }

    IMMDevice* raw = nullptr;
    hr = static_cast<HRESULT>(br::defaultAudioDevice(enumerator.Get(), kind == Kind::Loopback ? 1 : 0, reinterpret_cast<void**>(&raw)));
    device_.Attach(raw);
    if (FAILED(hr) || !device_) {
        br::setLastError(
            kind == Kind::Loopback
                ? "No default render endpoint for WASAPI loopback"
                : "No default capture endpoint for the microphone",
            hr
        );
        return FAILED(hr) ? hr : E_FAIL;
    }

    hr = device_->Activate(
        __uuidof(IAudioClient),
        CLSCTX_ALL,
        nullptr,
        reinterpret_cast<void**>(client_.ReleaseAndGetAddressOf())
    );
    if (FAILED(hr)) {
        br::setLastError("IAudioClient activate failed", hr);
        return hr;
    }

    WAVEFORMATEX* mix = nullptr;
    hr = client_->GetMixFormat(&mix);
    if (FAILED(hr) || !mix) {
        br::setLastError("GetMixFormat failed", hr);
        return FAILED(hr) ? hr : E_POINTER;
    }
    const size_t mixBytes = sizeof(WAVEFORMATEX) + mix->cbSize;
    mixFormatBytes_.assign(reinterpret_cast<BYTE*>(mix), reinterpret_cast<BYTE*>(mix) + mixBytes);
    CoTaskMemFree(mix);
    mixFormat_ = asWave(mixFormatBytes_);

    inRate_ = mixFormat_->nSamplesPerSec;
    inChannels_ = mixFormat_->nChannels;
    inBits_ = mixFormat_->wBitsPerSample;
    inBlockAlign_ = mixFormat_->nBlockAlign;
    isFloat_ = mixFormat_->wFormatTag == WAVE_FORMAT_IEEE_FLOAT;
    if (mixFormat_->wFormatTag == WAVE_FORMAT_EXTENSIBLE && mixFormat_->cbSize >= 22) {
        const auto* ext = reinterpret_cast<WAVEFORMATEXTENSIBLE*>(mixFormat_);
        isFloat_ = IsEqualGUID(ext->SubFormat, KSDATAFORMAT_SUBTYPE_IEEE_FLOAT);
        inBits_ = ext->Samples.wValidBitsPerSample ? ext->Samples.wValidBitsPerSample : mixFormat_->wBitsPerSample;
    }

    DWORD autoFlags = AUDCLNT_STREAMFLAGS_NOPERSIST
        | AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM
        | AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY;
    if (kind == Kind::Loopback) {
        autoFlags |= AUDCLNT_STREAMFLAGS_LOOPBACK;
    }
    const REFERENCE_TIME bufferHns = 10'000'000;  // 1s
    WAVEFORMATEX pcm48{};
    pcm48.wFormatTag = WAVE_FORMAT_PCM;
    pcm48.nChannels = static_cast<WORD>(kOutChannels);
    pcm48.nSamplesPerSec = kOutRate;
    pcm48.wBitsPerSample = 16;
    pcm48.nBlockAlign = static_cast<WORD>(kOutChannels * 2);
    pcm48.nAvgBytesPerSec = kOutRate * pcm48.nBlockAlign;
    auto initializeClient = [&](DWORD streamFlags, WAVEFORMATEX* format) -> HRESULT {
        client_.Reset();
        HRESULT initHr = device_->Activate(
            __uuidof(IAudioClient),
            CLSCTX_ALL,
            nullptr,
            reinterpret_cast<void**>(client_.ReleaseAndGetAddressOf())
        );
        if (FAILED(initHr)) {
            return initHr;
        }
        return client_->Initialize(AUDCLNT_SHAREMODE_SHARED, streamFlags, bufferHns, 0, format, nullptr);
    };
    hr = initializeClient(autoFlags, &pcm48);
    if (SUCCEEDED(hr)) {
        inRate_ = kOutRate;
        inChannels_ = kOutChannels;
        inBits_ = 16;
        inBlockAlign_ = pcm48.nBlockAlign;
        isFloat_ = false;
    } else {
        hr = initializeClient(autoFlags, mixFormat_);
        if (FAILED(hr)) {
            DWORD flags = AUDCLNT_STREAMFLAGS_NOPERSIST;
            if (kind == Kind::Loopback) {
                flags |= AUDCLNT_STREAMFLAGS_LOOPBACK;
            }
            hr = initializeClient(flags, mixFormat_);
        }
    }
    if (FAILED(hr)) {
        if (hr == AUDCLNT_E_DEVICE_IN_USE) {
            br::setLastError(
                kind == Kind::Loopback
                    ? "System audio is exclusive in another app. Close it, or turn off Exclusive Mode in Sound settings."
                    : "Microphone is exclusive in another app. Close it, or turn off Exclusive Mode in Sound settings.",
                hr
            );
        } else {
            br::setLastError(
                kind == Kind::Loopback ? "WASAPI loopback Initialize failed" : "WASAPI microphone Initialize failed",
                hr
            );
        }
        return hr;
    }
    hr = client_->GetService(
        __uuidof(IAudioCaptureClient),
        reinterpret_cast<void**>(capture_.ReleaseAndGetAddressOf())
    );
    if (FAILED(hr)) {
        br::setLastError("IAudioCaptureClient failed", hr);
        return hr;
    }
    resamplePos_ = 0;
    hasPrev_ = false;
    return S_OK;
}

void WasapiCapture::close() {
    stop();
    capture_.Reset();
    client_.Reset();
    device_.Reset();
    mixFormatBytes_.clear();
    mixFormat_ = nullptr;
}

HRESULT WasapiCapture::start() {
    if (!client_) {
        return E_FAIL;
    }
    const HRESULT hr = client_->Start();
    if (FAILED(hr)) {
        if (hr == AUDCLNT_E_DEVICE_IN_USE) {
            br::setLastError(
                "Audio device is exclusive in another app. Close it, or turn off Exclusive Mode in Sound settings.",
                hr
            );
        } else {
            br::setLastError("IAudioClient::Start failed", hr);
        }
    }
    return hr;
}

void WasapiCapture::stop() {
    if (client_) {
        client_->Stop();
    }
}

void WasapiCapture::nativeFrameToStereoFloat(const BYTE* data, UINT32 frameIndex, float& left, float& right) const {
    const BYTE* frame = data + static_cast<size_t>(frameIndex) * inBlockAlign_;
    auto sample = [&](UINT channel) -> float {
        if (channel >= inChannels_) {
            channel = 0;
        }
        if (isFloat_ && inBits_ >= 32) {
            float value = 0;
            std::memcpy(&value, frame + channel * 4, 4);
            return value;
        }
        if (inBits_ == 16) {
            std::int16_t value = 0;
            std::memcpy(&value, frame + channel * 2, 2);
            return static_cast<float>(value) / 32768.0f;
        }
        if (inBits_ == 8) {
            return (static_cast<float>(frame[channel]) - 128.0f) / 128.0f;
        }
        if (inBits_ == 24) {
            const UINT bytesPerSample = inChannels_ > 0 ? inBlockAlign_ / inChannels_ : 3;
            if (bytesPerSample >= 4) {
                std::int32_t value = 0;
                std::memcpy(&value, frame + channel * 4, 4);
                return static_cast<float>(value >> 8) / 8388608.0f;
            }
            const UINT offset = channel * 3;
            std::int32_t value = static_cast<std::int32_t>(frame[offset])
                | (static_cast<std::int32_t>(frame[offset + 1]) << 8)
                | (static_cast<std::int32_t>(frame[offset + 2]) << 16);
            if (value & 0x800000) {
                value |= ~0xFFFFFF;
            }
            return static_cast<float>(value) / 8388608.0f;
        }
        if (inBits_ == 32 && !isFloat_) {
            std::int32_t value = 0;
            std::memcpy(&value, frame + channel * 4, 4);
            return static_cast<float>(value) / 2147483648.0f;
        }
        return 0;
    };
    left = sample(0);
    right = inChannels_ > 1 ? sample(1) : left;
}

void WasapiCapture::convertPacket(
    const BYTE* data,
    UINT32 nativeFrames,
    DWORD flags,
    std::vector<std::int16_t>& out,
    UINT32& outFrames
) {
    outFrames = 0;
    out.clear();
    if (nativeFrames == 0 || inRate_ == 0) {
        return;
    }
    const bool silent = (flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0;
    const double step = static_cast<double>(inRate_) / static_cast<double>(kOutRate);
    while (resamplePos_ < static_cast<double>(nativeFrames)) {
        const UINT32 index = static_cast<UINT32>(resamplePos_);
        const UINT32 next = (std::min)(index + 1, nativeFrames - 1);
        const float frac = static_cast<float>(resamplePos_ - static_cast<double>(index));
        float left0 = 0;
        float right0 = 0;
        float left1 = 0;
        float right1 = 0;
        if (!silent && data) {
            nativeFrameToStereoFloat(data, index, left0, right0);
            nativeFrameToStereoFloat(data, next, left1, right1);
        }
        const float left = left0 + (left1 - left0) * frac;
        const float right = right0 + (right1 - right0) * frac;
        auto quantize = [](float value) -> std::int16_t {
            const float clamped = (std::max)(-1.0f, (std::min)(1.0f, value));
            return static_cast<std::int16_t>(clamped * 32767.0f);
        };
        out.push_back(quantize(left));
        out.push_back(quantize(right));
        ++outFrames;
        resamplePos_ += step;
    }
    resamplePos_ -= static_cast<double>(nativeFrames);
    if (resamplePos_ < 0) {
        resamplePos_ = 0;
    }
}

HRESULT WasapiCapture::read(std::vector<std::int16_t>& interleavedStereo, UINT32& frames) {
    frames = 0;
    interleavedStereo.clear();
    if (!capture_) {
        return E_FAIL;
    }
    UINT32 packet = 0;
    HRESULT hr = capture_->GetNextPacketSize(&packet);
    if (FAILED(hr)) {
        return hr;
    }
    while (packet > 0) {
        BYTE* data = nullptr;
        UINT32 nativeFrames = 0;
        DWORD flags = 0;
        hr = capture_->GetBuffer(&data, &nativeFrames, &flags, nullptr, nullptr);
        if (FAILED(hr)) {
            return hr;
        }
        std::vector<std::int16_t> piece;
        UINT32 pieceFrames = 0;
        convertPacket(data, nativeFrames, flags, piece, pieceFrames);
        capture_->ReleaseBuffer(nativeFrames);
        interleavedStereo.insert(interleavedStereo.end(), piece.begin(), piece.end());
        frames += pieceFrames;
        hr = capture_->GetNextPacketSize(&packet);
        if (FAILED(hr)) {
            return hr;
        }
    }
    return S_OK;
}

#else
[[maybe_unused]] static int br_windows_capture_tu_wasapi = 0;
#endif
