#if defined(_WIN32)

#include "mf_player.h"

#include "capture_common.h"
#include "mf_rgb32.h"

#include "compose_export.h"

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include <audioclient.h>
#include <mmdeviceapi.h>
#include <objbase.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>
#include <wrl/client.h>

namespace {

constexpr UINT kRate = 48000;
constexpr UINT kChannels = 2;

struct VideoStream {
    Microsoft::WRL::ComPtr<IMFSourceReader> reader;
    UINT width = 0;
    UINT height = 0;
    std::vector<std::uint8_t> lastFrame;
    LONGLONG lastTime = -1;
};

struct AudioStream {
    Microsoft::WRL::ComPtr<IMFSourceReader> reader;
    std::vector<std::int16_t> leftover;
};

struct Player {
    VideoStream screen;
    VideoStream camera;
    AudioStream mic;
    AudioStream systemAudio;
    Microsoft::WRL::ComPtr<IAudioClient> render;
    Microsoft::WRL::ComPtr<IAudioRenderClient> renderClient;
    UINT32 renderBufferFrames = 0;
    std::vector<br_kept_range> ranges;
    size_t rangeIndex = 0;
    double camX = 0.68;
    double camY = 0.68;
    double camW = 0.28;
    double camH = 0.28;
    bool hasCamera = false;
    bool ended = false;
    bool audioPrimed = false;
    bool presentPending = false;
};

std::mutex gPlayerMu;
Player gPlayer;

HRESULT seekTo(IMFSourceReader* reader, int64_t hns) {
    if (!reader) {
        return S_OK;
    }
    PROPVARIANT var;
    PropVariantInit(&var);
    var.vt = VT_I8;
    var.hVal.QuadPart = (std::max)(int64_t{0}, hns);
    const HRESULT hr = reader->SetCurrentPosition(GUID_NULL, var);
    PropVariantClear(&var);
    return hr;
}

HRESULT openVideo(const char* path, VideoStream& stream) {
    stream = {};
    if (!path || !path[0]) {
        return S_FALSE;
    }
    Microsoft::WRL::ComPtr<IMFAttributes> attrs;
    HRESULT hr = MFCreateAttributes(&attrs, 1);
    if (FAILED(hr)) {
        return hr;
    }
    attrs->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE);
    const std::wstring wide = br::utf8ToWide(path);
    IMFSourceReader* raw = nullptr;
    hr = static_cast<HRESULT>(br::openMfSourceReader(wide.c_str(), attrs.Get(), reinterpret_cast<void**>(&raw)));
    if (FAILED(hr) || !raw) {
        return FAILED(hr) ? hr : E_FAIL;
    }
    stream.reader.Attach(raw);
    Microsoft::WRL::ComPtr<IMFMediaType> type;
    hr = MFCreateMediaType(&type);
    if (FAILED(hr)) {
        return hr;
    }
    type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
    hr = stream.reader->SetCurrentMediaType(static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), nullptr, type.Get());
    if (FAILED(hr)) {
        br::setLastError("Player RGB32 type rejected", hr);
        return hr;
    }
    Microsoft::WRL::ComPtr<IMFMediaType> current;
    hr = stream.reader->GetCurrentMediaType(static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), &current);
    if (FAILED(hr)) {
        return hr;
    }
    UINT32 w = 0;
    UINT32 h = 0;
    MFGetAttributeSize(current.Get(), MF_MT_FRAME_SIZE, &w, &h);
    stream.width = w & ~1u;
    stream.height = h & ~1u;
    return S_OK;
}

HRESULT openAudio(const char* path, AudioStream& stream) {
    stream = {};
    if (!path || !path[0]) {
        return S_FALSE;
    }
    const std::wstring wide = br::utf8ToWide(path);
    IMFSourceReader* raw = nullptr;
    HRESULT hr = static_cast<HRESULT>(br::openMfSourceReader(wide.c_str(), nullptr, reinterpret_cast<void**>(&raw)));
    if (FAILED(hr) || !raw) {
        stream.reader.Reset();
        return FAILED(hr) ? hr : E_FAIL;
    }
    stream.reader.Attach(raw);
    Microsoft::WRL::ComPtr<IMFMediaType> type;
    hr = MFCreateMediaType(&type);
    if (FAILED(hr)) {
        return hr;
    }
    type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
    type->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
    type->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, kChannels);
    type->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, kRate);
    type->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
    type->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, kChannels * 2);
    type->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, kRate * kChannels * 2);
    hr = stream.reader->SetCurrentMediaType(static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM), nullptr, type.Get());
    if (FAILED(hr)) {
        br::setLastError("take audio did not decode as 48 kHz stereo PCM", hr);
        stream.reader.Reset();
        return hr;
    }
    stream.reader->SetStreamSelection(static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), FALSE);
    stream.reader->SetStreamSelection(static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM), TRUE);
    return S_OK;
}

HRESULT openRenderer(Player& player) {
    player.render.Reset();
    player.renderClient.Reset();
    player.renderBufferFrames = 0;
    Microsoft::WRL::ComPtr<IMMDeviceEnumerator> enumerator;
    HRESULT hr = CoCreateInstance(
        __uuidof(MMDeviceEnumerator),
        nullptr,
        CLSCTX_ALL,
        IID_PPV_ARGS(&enumerator)
    );
    if (FAILED(hr)) {
        br::setLastError("playback audio enumerator failed", hr);
        return hr;
    }
    Microsoft::WRL::ComPtr<IMMDevice> device;
    IMMDevice* raw = nullptr;
    hr = static_cast<HRESULT>(br::defaultAudioDevice(enumerator.Get(), 1, reinterpret_cast<void**>(&raw)));
    device.Attach(raw);
    if (FAILED(hr) || !device) {
        br::setLastError("no speakers for take playback", hr);
        return FAILED(hr) ? hr : E_FAIL;
    }
    WAVEFORMATEX pcm48{};
    pcm48.wFormatTag = WAVE_FORMAT_PCM;
    pcm48.nChannels = static_cast<WORD>(kChannels);
    pcm48.nSamplesPerSec = kRate;
    pcm48.wBitsPerSample = 16;
    pcm48.nBlockAlign = static_cast<WORD>(kChannels * 2);
    pcm48.nAvgBytesPerSec = kRate * pcm48.nBlockAlign;
    const DWORD convertFlags = AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM | AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY;
    auto tryInit = [&](DWORD flags, WAVEFORMATEX* format) -> HRESULT {
        Microsoft::WRL::ComPtr<IAudioClient> client;
        HRESULT initHr = device->Activate(
            __uuidof(IAudioClient),
            CLSCTX_ALL,
            nullptr,
            reinterpret_cast<void**>(client.ReleaseAndGetAddressOf())
        );
        if (FAILED(initHr) || !client) {
            return initHr;
        }
        initHr = client->Initialize(AUDCLNT_SHAREMODE_SHARED, flags, 800'000, 0, format, nullptr);
        if (FAILED(initHr)) {
            return initHr;
        }
        player.render = client;
        return S_OK;
    };
    hr = tryInit(convertFlags, &pcm48);
    if (FAILED(hr)) {
        hr = tryInit(0, &pcm48);
    }
    if (FAILED(hr)) {
        Microsoft::WRL::ComPtr<IAudioClient> probe;
        if (SUCCEEDED(device->Activate(
                __uuidof(IAudioClient),
                CLSCTX_ALL,
                nullptr,
                reinterpret_cast<void**>(probe.ReleaseAndGetAddressOf())
            ))
            && probe) {
            WAVEFORMATEX* mix = nullptr;
            if (SUCCEEDED(probe->GetMixFormat(&mix)) && mix) {
                hr = tryInit(convertFlags, mix);
                if (FAILED(hr)) {
                    hr = tryInit(0, mix);
                }
                CoTaskMemFree(mix);
            }
        }
    }
    if (FAILED(hr) || !player.render) {
        br::setLastError("could not open speakers for take playback", hr);
        player.render.Reset();
        return hr;
    }
    hr = player.render->GetBufferSize(&player.renderBufferFrames);
    if (FAILED(hr)) {
        player.render.Reset();
        return hr;
    }
    hr = player.render->GetService(
        __uuidof(IAudioRenderClient),
        reinterpret_cast<void**>(player.renderClient.ReleaseAndGetAddressOf())
    );
    if (FAILED(hr)) {
        player.render.Reset();
        return hr;
    }
    return player.render->Start();
}

HRESULT readVideo(VideoStream& stream, LONGLONG& timestamp, bool& ended) {
    ended = false;
    if (!stream.reader) {
        ended = true;
        return S_FALSE;
    }
    Microsoft::WRL::ComPtr<IMFSample> sample;
    DWORD flags = 0;
    HRESULT hr = stream.reader->ReadSample(
        static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM),
        0,
        nullptr,
        &flags,
        &timestamp,
        &sample
    );
    if (FAILED(hr) || (flags & MF_SOURCE_READERF_ENDOFSTREAM) || !sample) {
        ended = true;
        return S_FALSE;
    }
    Microsoft::WRL::ComPtr<IMFMediaBuffer> buffer;
    hr = sample->ConvertToContiguousBuffer(&buffer);
    if (FAILED(hr)) {
        return hr;
    }
    stream.lastTime = timestamp;
    return copyMediaBufferToTopDownBGRA(
        buffer.Get(),
        stream.width,
        stream.height,
        0,
        stream.lastFrame
    );
}

void pumpAudio(Player& player, UINT32 maxFrames) {
    if (!player.render || !player.renderClient || maxFrames < 48) {
        return;
    }
    UINT32 padding = 0;
    player.render->GetCurrentPadding(&padding);
    UINT32 available = player.renderBufferFrames > padding ? player.renderBufferFrames - padding : 0;
    if (available > maxFrames) {
        available = maxFrames;
    }
    if (available < 48) {
        return;
    }
    BYTE* dest = nullptr;
    if (FAILED(player.renderClient->GetBuffer(available, &dest)) || !dest) {
        return;
    }
    std::memset(dest, 0, static_cast<size_t>(available) * kChannels * 2);
    auto mixSamples = [&](const std::int16_t* src, UINT32 frames, BYTE*& cursor, UINT32& remaining) {
        const UINT32 take = (std::min)(remaining, frames);
        auto* dst = reinterpret_cast<std::int16_t*>(cursor);
        for (UINT32 i = 0; i < take * kChannels; ++i) {
            const int mixed = static_cast<int>(dst[i]) + static_cast<int>(src[i]);
            dst[i] = static_cast<std::int16_t>((std::max)(-32768, (std::min)(32767, mixed)));
        }
        remaining -= take;
        cursor += take * kChannels * 2;
        return take;
    };
    auto mix = [&](AudioStream& stream) {
        if (!stream.reader) {
            return;
        }
        UINT32 remaining = available;
        BYTE* cursor = dest;
        if (!stream.leftover.empty()) {
            const UINT32 leftoverFrames = static_cast<UINT32>(stream.leftover.size() / kChannels);
            const UINT32 take = mixSamples(stream.leftover.data(), leftoverFrames, cursor, remaining);
            stream.leftover.erase(
                stream.leftover.begin(),
                stream.leftover.begin() + static_cast<std::ptrdiff_t>(take) * kChannels
            );
        }
        while (remaining > 0) {
            Microsoft::WRL::ComPtr<IMFSample> sample;
            DWORD flags = 0;
            HRESULT hr = stream.reader->ReadSample(
                static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM),
                0,
                nullptr,
                &flags,
                nullptr,
                &sample
            );
            if (FAILED(hr) || (flags & MF_SOURCE_READERF_ENDOFSTREAM) || !sample) {
                return;
            }
            Microsoft::WRL::ComPtr<IMFMediaBuffer> buffer;
            if (FAILED(sample->ConvertToContiguousBuffer(&buffer))) {
                return;
            }
            BYTE* data = nullptr;
            DWORD current = 0;
            if (FAILED(buffer->Lock(&data, nullptr, &current)) || !data) {
                return;
            }
            const UINT32 frames = current / (kChannels * 2);
            auto* src = reinterpret_cast<const std::int16_t*>(data);
            const UINT32 take = mixSamples(src, frames, cursor, remaining);
            if (take < frames) {
                stream.leftover.assign(src + take * kChannels, src + frames * kChannels);
            }
            buffer->Unlock();
        }
    };
    mix(player.systemAudio);
    mix(player.mic);
    player.renderClient->ReleaseBuffer(available, 0);
}

void applySeeks(Player& player, int64_t hns) {
    seekTo(player.screen.reader.Get(), hns);
    seekTo(player.camera.reader.Get(), hns);
    seekTo(player.mic.reader.Get(), hns);
    seekTo(player.systemAudio.reader.Get(), hns);
    player.mic.leftover.clear();
    player.systemAudio.leftover.clear();
    player.screen.lastTime = -1;
    player.camera.lastTime = -1;
    player.presentPending = false;
}

}  // namespace

int playerOpen(const char* videoPath, const br_kept_range* ranges, int rangeCount) {
    return playerOpenTake(videoPath, nullptr, nullptr, nullptr, ranges, rangeCount, 0.68, 0.68, 0.28, 0.28);
}

int playerOpenTake(
    const char* screenPath,
    const char* cameraPath,
    const char* micPath,
    const char* systemAudioPath,
    const br_kept_range* ranges,
    int rangeCount,
    double cameraX,
    double cameraY,
    double cameraWidth,
    double cameraHeight
) {
    playerClose();
    HRESULT hr = MFStartup(MF_VERSION, MFSTARTUP_LITE);
    if (FAILED(hr) && hr != MF_E_ALREADY_INITIALIZED) {
        br::setLastError("MFStartup failed for player", hr);
        return 1;
    }
    br::ensureCom();
    std::lock_guard<std::mutex> lock(gPlayerMu);
    br::setLastError("");
    hr = openVideo(screenPath, gPlayer.screen);
    if (FAILED(hr)) {
        return 1;
    }
    gPlayer.hasCamera = SUCCEEDED(openVideo(cameraPath, gPlayer.camera)) && gPlayer.camera.reader;
    std::string warn;
    auto noteAudio = [&](const char* path, const char* label, AudioStream& stream) {
        if (!path || !path[0]) {
            return;
        }
        const HRESULT audioHr = openAudio(path, stream);
        if (FAILED(audioHr) || !stream.reader) {
            if (!warn.empty()) {
                warn += "; ";
            }
            warn += label;
            warn += " did not decode";
        }
    };
    noteAudio(micPath, "audio.m4a", gPlayer.mic);
    noteAudio(systemAudioPath, "system-audio.m4a", gPlayer.systemAudio);
    if (FAILED(openRenderer(gPlayer))) {
        if (!warn.empty()) {
            warn += "; ";
        }
        warn += "no speakers for playback";
    }
    if (!warn.empty()) {
        br::setLastError(warn);
    }
    gPlayer.camX = cameraX;
    gPlayer.camY = cameraY;
    gPlayer.camW = cameraWidth;
    gPlayer.camH = cameraHeight;
    gPlayer.ranges.clear();
    if (ranges && rangeCount > 0) {
        gPlayer.ranges.assign(ranges, ranges + rangeCount);
        gPlayer.rangeIndex = 0;
        applySeeks(gPlayer, gPlayer.ranges.front().take_start_hns);
    }
    gPlayer.ended = false;
    return 0;
}

int playerTick(
    unsigned char* bgra,
    unsigned int maxBytes,
    unsigned int* width,
    unsigned int* height,
    int64_t* takeHns,
    int* ended
) {
    std::lock_guard<std::mutex> lock(gPlayerMu);
    if (!gPlayer.screen.reader || gPlayer.ended) {
        if (ended) {
            *ended = 1;
        }
        return 1;
    }
    LONGLONG timestamp = gPlayer.screen.lastTime >= 0 ? gPlayer.screen.lastTime : 0;
    if (!gPlayer.presentPending) {
        bool videoEnded = false;
        HRESULT hr = readVideo(gPlayer.screen, timestamp, videoEnded);
        if (videoEnded || FAILED(hr) || gPlayer.screen.lastFrame.empty()) {
            gPlayer.ended = true;
            if (ended) {
                *ended = 1;
            }
            return 1;
        }
        if (!gPlayer.ranges.empty()) {
            while (gPlayer.rangeIndex < gPlayer.ranges.size()
                && timestamp >= gPlayer.ranges[gPlayer.rangeIndex].take_end_hns) {
                ++gPlayer.rangeIndex;
                if (gPlayer.rangeIndex >= gPlayer.ranges.size()) {
                    gPlayer.ended = true;
                    if (ended) {
                        *ended = 1;
                    }
                    return 1;
                }
                applySeeks(gPlayer, gPlayer.ranges[gPlayer.rangeIndex].take_start_hns);
                hr = readVideo(gPlayer.screen, timestamp, videoEnded);
                if (videoEnded || FAILED(hr)) {
                    gPlayer.ended = true;
                    if (ended) {
                        *ended = 1;
                    }
                    return 1;
                }
            }
        }
        if (gPlayer.hasCamera) {
            const LONGLONG slack = 10'000'000 / 30;
            if (gPlayer.camera.lastTime < 0) {
                LONGLONG camTime = 0;
                bool camEnded = false;
                readVideo(gPlayer.camera, camTime, camEnded);
            }
            while (gPlayer.camera.reader && gPlayer.camera.lastTime >= 0
                && gPlayer.camera.lastTime + slack < timestamp) {
                LONGLONG camTime = 0;
                bool camEnded = false;
                readVideo(gPlayer.camera, camTime, camEnded);
                if (camEnded) {
                    break;
                }
            }
        }
    }

    const UINT w = gPlayer.screen.width;
    const UINT h = gPlayer.screen.height;
    const size_t needed = static_cast<size_t>(w) * h * 4;
    if (width) {
        *width = w;
    }
    if (height) {
        *height = h;
    }
    if (!bgra || maxBytes < needed) {
        gPlayer.presentPending = true;
        if (ended) {
            *ended = 0;
        }
        return 1;
    }
    if (gPlayer.hasCamera && !gPlayer.camera.lastFrame.empty()) {
        composePipBGRA(
            gPlayer.screen.lastFrame.data(),
            w,
            h,
            gPlayer.camera.lastFrame.data(),
            gPlayer.camera.width,
            gPlayer.camera.height,
            bgra,
            maxBytes,
            gPlayer.camX,
            gPlayer.camY,
            gPlayer.camW,
            gPlayer.camH
        );
    } else {
        std::memcpy(bgra, gPlayer.screen.lastFrame.data(), needed);
    }
    UINT32 audioFrames = kRate / 30;
    if (!gPlayer.audioPrimed) {
        audioFrames = (kRate / 30) * 2;
        gPlayer.audioPrimed = true;
    }
    pumpAudio(gPlayer, audioFrames);
    gPlayer.presentPending = false;
    if (takeHns) {
        *takeHns = timestamp;
    }
    if (ended) {
        *ended = 0;
    }
    return 0;
}

int playerClose() {
    std::lock_guard<std::mutex> lock(gPlayerMu);
    if (gPlayer.render) {
        gPlayer.render->Stop();
    }
    gPlayer = {};
    return 0;
}

int playerSetPaused(int paused) {
    std::lock_guard<std::mutex> lock(gPlayerMu);
    if (!gPlayer.render) {
        return 0;
    }
    if (paused) {
        gPlayer.render->Stop();
        return 0;
    }
    const HRESULT hr = gPlayer.render->Start();
    if (FAILED(hr) && hr != AUDCLNT_E_NOT_STOPPED) {
        br::setLastError("could not resume take audio", hr);
        return 1;
    }
    return 0;
}

#else
[[maybe_unused]] static int br_windows_capture_tu_player = 0;
#endif
