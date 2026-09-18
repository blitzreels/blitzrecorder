#pragma once

#if defined(_WIN32)

#include <cstdint>
#include <string>
#include <vector>

#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <wrl/client.h>

class VideoSink {
public:
    ~VideoSink() { finalize(); }

    HRESULT open(const std::wstring& path, UINT width, UINT height, UINT fps, bool muxAudio = false);
    HRESULT writeBGRA(const std::uint8_t* bgra, UINT stride, std::int64_t timeHns, std::int64_t durationHns);
    HRESULT writePCM16(const std::int16_t* interleaved, UINT32 frames, std::int64_t timeHns);
    HRESULT finalize();
    bool isOpen() const { return writer_ != nullptr; }
    bool hasAudio() const { return muxAudio_ && writer_ != nullptr; }
    UINT64 frameCount() const { return frames_; }

private:
    HRESULT configure(BOOL hardware, bool nv12, UINT32 profile);
    HRESULT configureAudio();
    HRESULT writeSample(const std::uint8_t* data, DWORD size, std::int64_t timeHns, std::int64_t durationHns);
    void noteEncoder(BOOL hardware);

    Microsoft::WRL::ComPtr<IMFSinkWriter> writer_;
    std::wstring pathCache_;
    DWORD stream_ = 0;
    DWORD audioStream_ = 0;
    UINT width_ = 0;
    UINT height_ = 0;
    UINT fps_ = 30;
    UINT bitrate_ = 8'000'000;
    UINT audioRate_ = 48000;
    UINT audioChannels_ = 2;
    bool nv12_ = false;
    bool muxAudio_ = false;
    bool finalized_ = false;
    std::vector<std::uint8_t> convertBuf_;
    UINT64 frames_ = 0;
};

class AudioSink {
public:
    ~AudioSink() { finalize(); }

    HRESULT open(const std::wstring& path, UINT sampleRate, UINT channels);
    HRESULT writePCM16(const std::int16_t* interleaved, UINT32 frames, std::int64_t timeHns);
    HRESULT finalize();
    bool isOpen() const { return writer_ != nullptr; }
    UINT64 frameCount() const { return frames_; }

private:
    Microsoft::WRL::ComPtr<IMFSinkWriter> writer_;
    DWORD stream_ = 0;
    UINT sampleRate_ = 48000;
    UINT channels_ = 2;
    bool finalized_ = false;
    UINT64 frames_ = 0;
};

#endif
