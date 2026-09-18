#if defined(_WIN32)

#include "mf_sink.h"

#include "capture_common.h"

#include <algorithm>
#include <cstring>
#include <string>
#include <vector>

#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mftransform.h>
#include <d3d11.h>
#include <dxgi.h>

#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mfreadwrite.lib")
#pragma comment(lib, "mfuuid.lib")
#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxgi.lib")

namespace {

HRESULT setFrameSize(IMFMediaType* type, UINT width, UINT height) {
    return MFSetAttributeSize(type, MF_MT_FRAME_SIZE, width, height);
}

HRESULT setFrameRate(IMFMediaType* type, UINT fps) {
    return MFSetAttributeRatio(type, MF_MT_FRAME_RATE, fps, 1);
}

void bgraToNV12(const std::uint8_t* bgra, UINT width, UINT height, UINT stride, std::uint8_t* nv12) {
    std::uint8_t* yPlane = nv12;
    std::uint8_t* uvPlane = nv12 + static_cast<size_t>(width) * height;
    for (UINT y = 0; y < height; ++y) {
        for (UINT x = 0; x < width; ++x) {
            const std::uint8_t* p = bgra + y * stride + x * 4;
            const int b = p[0];
            const int g = p[1];
            const int r = p[2];
            const int yy = (66 * r + 129 * g + 25 * b + 128) >> 8;
            yPlane[y * width + x] = static_cast<std::uint8_t>((std::max)(0, (std::min)(255, yy + 16)));
            if ((y % 2) == 0 && (x % 2) == 0) {
                const int uu = (-38 * r - 74 * g + 112 * b + 128) >> 8;
                const int vv = (112 * r - 94 * g - 18 * b + 128) >> 8;
                const size_t uvIndex = (y / 2) * width + x;
                uvPlane[uvIndex] = static_cast<std::uint8_t>((std::max)(0, (std::min)(255, uu + 128)));
                uvPlane[uvIndex + 1] = static_cast<std::uint8_t>((std::max)(0, (std::min)(255, vv + 128)));
            }
        }
    }
}

}  // namespace

namespace {

std::string classifyEncoder(const std::string& name, BOOL hardware) {
    std::string lower = name;
    for (char& c : lower) {
        if (c >= 'A' && c <= 'Z') {
            c = static_cast<char>(c - 'A' + 'a');
        }
    }
    if (lower.find("nvenc") != std::string::npos || lower.find("nvidia") != std::string::npos) {
        return "NVENC H.264";
    }
    if (lower.find("amf") != std::string::npos || lower.find("amd") != std::string::npos || lower.find("vce") != std::string::npos) {
        return "AMF H.264";
    }
    if (lower.find("qsv") != std::string::npos || lower.find("quick sync") != std::string::npos || lower.find("intel") != std::string::npos) {
        return "QSV H.264";
    }
    if (!hardware) {
        return name.empty() ? "Microsoft software H.264" : name;
    }
    return name.empty() ? "MF hardware H.264" : name;
}

int encoderRank(const std::string& name) {
    std::string lower = name;
    for (char& c : lower) {
        if (c >= 'A' && c <= 'Z') {
            c = static_cast<char>(c - 'A' + 'a');
        }
    }
    if (lower.find("nvenc") != std::string::npos || lower.find("nvidia") != std::string::npos) {
        return 0;
    }
    if (lower.find("amf") != std::string::npos || lower.find("amd") != std::string::npos || lower.find("vce") != std::string::npos) {
        return 1;
    }
    if (lower.find("qsv") != std::string::npos || lower.find("quick sync") != std::string::npos || lower.find("intel") != std::string::npos) {
        return 2;
    }
    if (lower.find("h264") != std::string::npos || lower.find("h.264") != std::string::npos) {
        return 8;
    }
    return 20;
}

int gpuVendorRank(UINT vendorId) {
    if (vendorId == 0x10DE) {
        return 0;
    }
    if (vendorId == 0x1002 || vendorId == 0x1022) {
        return 1;
    }
    if (vendorId == 0x8086) {
        return 2;
    }
    if (vendorId == 0x1414) {
        return -1;
    }
    return 9;
}

HRESULT makeDxgiDeviceManager(IDXGIAdapter* adapter, IMFDXGIDeviceManager** out) {
    if (!out) {
        return E_POINTER;
    }
    *out = nullptr;
    Microsoft::WRL::ComPtr<ID3D11Device> device;
    D3D_FEATURE_LEVEL level{};
    UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT | D3D11_CREATE_DEVICE_VIDEO_SUPPORT;
    const D3D_DRIVER_TYPE type = adapter ? D3D_DRIVER_TYPE_UNKNOWN : D3D_DRIVER_TYPE_HARDWARE;
    HRESULT hr = D3D11CreateDevice(
        adapter,
        type,
        nullptr,
        flags,
        nullptr,
        0,
        D3D11_SDK_VERSION,
        device.ReleaseAndGetAddressOf(),
        &level,
        nullptr
    );
    if (FAILED(hr)) {
        flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
        hr = D3D11CreateDevice(
            adapter,
            type,
            nullptr,
            flags,
            nullptr,
            0,
            D3D11_SDK_VERSION,
            device.ReleaseAndGetAddressOf(),
            &level,
            nullptr
        );
    }
    if (FAILED(hr) || !device) {
        return hr;
    }
    Microsoft::WRL::ComPtr<ID3D10Multithread> mt;
    if (SUCCEEDED(device.As(&mt)) && mt) {
        mt->SetMultithreadProtected(TRUE);
    }
    UINT token = 0;
    Microsoft::WRL::ComPtr<IMFDXGIDeviceManager> manager;
    hr = MFCreateDXGIDeviceManager(&token, manager.ReleaseAndGetAddressOf());
    if (FAILED(hr) || !manager) {
        return hr;
    }
    hr = manager->ResetDevice(device.Get(), token);
    if (FAILED(hr)) {
        return hr;
    }
    *out = manager.Detach();
    return S_OK;
}

struct GpuBind {
    Microsoft::WRL::ComPtr<IMFDXGIDeviceManager> manager;
};

std::vector<GpuBind> rankedGpuBinds() {
    struct Ranked {
        int rank = 9;
        Microsoft::WRL::ComPtr<IDXGIAdapter> adapter;
    };
    std::vector<Ranked> ranked;
    Microsoft::WRL::ComPtr<IDXGIFactory1> factory;
    if (SUCCEEDED(CreateDXGIFactory1(IID_PPV_ARGS(&factory))) && factory) {
        for (UINT i = 0; ; ++i) {
            Microsoft::WRL::ComPtr<IDXGIAdapter> adapter;
            const HRESULT hr = factory->EnumAdapters(i, adapter.ReleaseAndGetAddressOf());
            if (hr == DXGI_ERROR_NOT_FOUND) {
                break;
            }
            if (FAILED(hr) || !adapter) {
                continue;
            }
            DXGI_ADAPTER_DESC desc{};
            if (FAILED(adapter->GetDesc(&desc))) {
                continue;
            }
            const int rank = gpuVendorRank(desc.VendorId);
            if (rank < 0) {
                continue;
            }
            Ranked row;
            row.rank = rank;
            row.adapter = adapter;
            ranked.push_back(std::move(row));
        }
    }
    std::sort(ranked.begin(), ranked.end(), [](const Ranked& a, const Ranked& b) {
        return a.rank < b.rank;
    });
    std::vector<GpuBind> binds;
    for (Ranked& row : ranked) {
        GpuBind bind;
        if (SUCCEEDED(makeDxgiDeviceManager(row.adapter.Get(), bind.manager.ReleaseAndGetAddressOf())) && bind.manager) {
            binds.push_back(std::move(bind));
        }
    }
    GpuBind fallback;
    if (SUCCEEDED(makeDxgiDeviceManager(nullptr, fallback.manager.ReleaseAndGetAddressOf())) && fallback.manager) {
        binds.push_back(std::move(fallback));
    }
    binds.push_back(GpuBind{});
    return binds;
}

void noteAvailableEncoders() {
    auto scan = [](UINT32 flags) {
        MFT_REGISTER_TYPE_INFO input{MFMediaType_Video, MFVideoFormat_NV12};
        MFT_REGISTER_TYPE_INFO output{MFMediaType_Video, MFVideoFormat_H264};
        IMFActivate** activates = nullptr;
        UINT32 count = 0;
        std::string best;
        int bestRank = 1000;
        if (FAILED(MFTEnumEx(MFT_CATEGORY_VIDEO_ENCODER, flags, &input, &output, &activates, &count)) || !activates) {
            return best;
        }
        for (UINT32 i = 0; i < count; ++i) {
            if (!activates[i]) {
                continue;
            }
            WCHAR* name = nullptr;
            UINT32 length = 0;
            if (SUCCEEDED(activates[i]->GetAllocatedString(MFT_FRIENDLY_NAME_Attribute, &name, &length)) && name) {
                const std::string utf8 = br::wideToUtf8(name);
                const int rank = encoderRank(utf8);
                if (rank < bestRank) {
                    bestRank = rank;
                    best = utf8;
                }
                CoTaskMemFree(name);
            }
            activates[i]->Release();
        }
        CoTaskMemFree(activates);
        return best;
    };
    std::string best = scan(MFT_ENUM_FLAG_SYNCMFT | MFT_ENUM_FLAG_ASYNCMFT | MFT_ENUM_FLAG_HARDWARE | MFT_ENUM_FLAG_SORTANDFILTER);
    const bool hardware = !best.empty();
    if (best.empty()) {
        best = scan(MFT_ENUM_FLAG_SYNCMFT | MFT_ENUM_FLAG_ASYNCMFT | MFT_ENUM_FLAG_SORTANDFILTER);
    }
    if (!best.empty()) {
        br::setLastEncoder(classifyEncoder(best, hardware ? TRUE : FALSE));
    }
}

}  // namespace

void VideoSink::noteEncoder(BOOL hardware) {
    Microsoft::WRL::ComPtr<IMFSinkWriterEx> writerEx;
    std::string found;
    if (SUCCEEDED(writer_.As(&writerEx))) {
        for (DWORD index = 0; index < 6; ++index) {
            GUID category{};
            Microsoft::WRL::ComPtr<IMFTransform> transform;
            if (FAILED(writerEx->GetTransformForStream(stream_, index, &category, &transform)) || !transform) {
                break;
            }
            Microsoft::WRL::ComPtr<IMFAttributes> attrs;
            if (FAILED(transform->GetAttributes(&attrs)) || !attrs) {
                continue;
            }
            WCHAR* name = nullptr;
            UINT32 length = 0;
            if (SUCCEEDED(attrs->GetAllocatedString(MFT_FRIENDLY_NAME_Attribute, &name, &length)) && name) {
                found = br::wideToUtf8(name);
                CoTaskMemFree(name);
                if (category == MFT_CATEGORY_VIDEO_ENCODER) {
                    break;
                }
            }
        }
    }
    br::setLastEncoder(classifyEncoder(found, hardware));
}

HRESULT VideoSink::configure(BOOL hardware, bool nv12, UINT32 profile) {
    Microsoft::WRL::ComPtr<IMFMediaType> output;
    HRESULT hr = MFCreateMediaType(&output);
    if (FAILED(hr)) {
        return hr;
    }
    output->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    output->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264);
    if (profile != 0) {
        output->SetUINT32(MF_MT_MPEG2_PROFILE, profile);
    }
    output->SetUINT32(MF_MT_AVG_BITRATE, width_ * height_ * fps_ / 4);
    output->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
    setFrameSize(output.Get(), width_, height_);
    setFrameRate(output.Get(), fps_);
    MFSetAttributeRatio(output.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
    hr = writer_->AddStream(output.Get(), &stream_);
    if (FAILED(hr)) {
        return hr;
    }

    Microsoft::WRL::ComPtr<IMFMediaType> input;
    hr = MFCreateMediaType(&input);
    if (FAILED(hr)) {
        return hr;
    }
    input->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    input->SetGUID(MF_MT_SUBTYPE, nv12 ? MFVideoFormat_NV12 : MFVideoFormat_RGB32);
    input->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
    setFrameSize(input.Get(), width_, height_);
    setFrameRate(input.Get(), fps_);
    input->SetUINT32(MF_MT_DEFAULT_STRIDE, nv12 ? static_cast<UINT32>(width_) : static_cast<UINT32>(width_ * 4));
    (void)hardware;
    hr = writer_->SetInputMediaType(stream_, input.Get(), nullptr);
    if (FAILED(hr)) {
        return hr;
    }
    if (!muxAudio_) {
        return S_OK;
    }
    return configureAudio();
}

HRESULT VideoSink::configureAudio() {
    Microsoft::WRL::ComPtr<IMFMediaType> output;
    HRESULT hr = MFCreateMediaType(&output);
    if (FAILED(hr)) {
        return hr;
    }
    output->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
    output->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_AAC);
    output->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, audioRate_);
    output->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, audioChannels_);
    output->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
    output->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, 24000);
    hr = writer_->AddStream(output.Get(), &audioStream_);
    if (FAILED(hr)) {
        return hr;
    }

    Microsoft::WRL::ComPtr<IMFMediaType> input;
    hr = MFCreateMediaType(&input);
    if (FAILED(hr)) {
        return hr;
    }
    input->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
    input->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
    input->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, audioChannels_);
    input->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, audioRate_);
    input->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, audioChannels_ * 2);
    input->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, audioRate_ * audioChannels_ * 2);
    input->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
    return writer_->SetInputMediaType(audioStream_, input.Get(), nullptr);
}

HRESULT VideoSink::open(const std::wstring& path, UINT width, UINT height, UINT fps, bool muxAudio) {
    finalize();
    width_ = width & ~1u;
    height_ = height & ~1u;
    fps_ = fps == 0 ? 30 : fps;
    nv12_ = true;
    frames_ = 0;
    finalized_ = false;
    muxAudio_ = muxAudio;
    audioStream_ = 0;

    pathCache_ = path;
    noteAvailableEncoders();
    const std::vector<GpuBind> binds = rankedGpuBinds();
    HRESULT last = E_FAIL;
    const BOOL hwOptions[] = {TRUE, FALSE};
    const bool nv12Options[] = {true, false};
    // 0 = encoder default (NVENC/AMF/QSV first). 77 = Main (inbox software). 66 = Baseline. 100 = High.
    const UINT32 profileOptions[] = {0, 77, 66, 100};
    for (BOOL hardware : hwOptions) {
        for (const GpuBind& bind : binds) {
            if (!hardware && bind.manager) {
                continue;
            }
            const int nv12Count = hardware ? 2 : 1;
            const int profileCount = hardware ? 4 : 1;
            for (int nv12Index = 0; nv12Index < nv12Count; ++nv12Index) {
                const bool nv12 = hardware ? nv12Options[nv12Index] : false;
                for (int profileIndex = 0; profileIndex < profileCount; ++profileIndex) {
                    const UINT32 profile = hardware ? profileOptions[profileIndex] : 77u;
                    writer_.Reset();
                    Microsoft::WRL::ComPtr<IMFAttributes> attributes;
                    last = MFCreateAttributes(&attributes, 5);
                    if (FAILED(last)) {
                        continue;
                    }
                    attributes->SetUINT32(MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS, hardware);
                    attributes->SetUINT32(MF_SINK_WRITER_DISABLE_THROTTLING, TRUE);
                    attributes->SetUINT32(MF_LOW_LATENCY, TRUE);
                    if (hardware && bind.manager) {
                        attributes->SetUnknown(MF_SINK_WRITER_D3D_MANAGER, bind.manager.Get());
                    }
                    DeleteFileW(path.c_str());
                    IMFSinkWriter* raw = nullptr;
                    last = static_cast<HRESULT>(
                        br::openMfSinkWriter(path.c_str(), attributes.Get(), reinterpret_cast<void**>(&raw))
                    );
                    if (FAILED(last) || !raw) {
                        continue;
                    }
                    writer_.Attach(raw);
                    nv12_ = nv12;
                    last = configure(hardware, nv12, profile);
                    if (SUCCEEDED(last)) {
                        last = writer_->BeginWriting();
                        if (SUCCEEDED(last)) {
                            noteEncoder(hardware);
                            return S_OK;
                        }
                    }
                    if (writer_) {
                        writer_->Finalize();
                        writer_.Reset();
                    }
                }
            }
        }
    }
    br::setLastError(
        "H.264 sink writer failed. Install the Media Feature Pack on Windows N/KN.",
        last
    );
    return last;
}

HRESULT VideoSink::writeSample(const std::uint8_t* data, DWORD size, std::int64_t timeHns, std::int64_t durationHns) {
    Microsoft::WRL::ComPtr<IMFMediaBuffer> buffer;
    HRESULT hr = MFCreateMemoryBuffer(size, &buffer);
    if (FAILED(hr)) {
        return hr;
    }
    BYTE* dst = nullptr;
    DWORD maxLen = 0;
    hr = buffer->Lock(&dst, &maxLen, nullptr);
    if (FAILED(hr)) {
        return hr;
    }
    std::memcpy(dst, data, (std::min)(size, maxLen));
    buffer->Unlock();
    buffer->SetCurrentLength((std::min)(size, maxLen));

    Microsoft::WRL::ComPtr<IMFSample> sample;
    hr = MFCreateSample(&sample);
    if (FAILED(hr)) {
        return hr;
    }
    sample->AddBuffer(buffer.Get());
    sample->SetSampleTime(timeHns);
    sample->SetSampleDuration(durationHns);
    return writer_->WriteSample(stream_, sample.Get());
}

HRESULT VideoSink::writeBGRA(const std::uint8_t* bgra, UINT stride, std::int64_t timeHns, std::int64_t durationHns) {
    if (!writer_ || !bgra) {
        return E_FAIL;
    }
    if (nv12_) {
        convertBuf_.assign(static_cast<size_t>(width_) * height_ * 3 / 2, 0);
        bgraToNV12(bgra, width_, height_, stride, convertBuf_.data());
        const HRESULT hr = writeSample(
            convertBuf_.data(),
            static_cast<DWORD>(convertBuf_.size()),
            timeHns,
            durationHns
        );
        if (SUCCEEDED(hr)) {
            ++frames_;
        }
        return hr;
    }

    convertBuf_.assign(static_cast<size_t>(width_) * height_ * 4, 0);
    for (UINT y = 0; y < height_; ++y) {
        const std::uint8_t* src = bgra + static_cast<size_t>(y) * stride;
        std::uint8_t* dst = convertBuf_.data() + static_cast<size_t>(height_ - 1 - y) * width_ * 4;
        std::memcpy(dst, src, static_cast<size_t>(width_) * 4);
    }
    const HRESULT hr = writeSample(
        convertBuf_.data(),
        static_cast<DWORD>(convertBuf_.size()),
        timeHns,
        durationHns
    );
    if (SUCCEEDED(hr)) {
        ++frames_;
    }
    return hr;
}

HRESULT VideoSink::writePCM16(const std::int16_t* interleaved, UINT32 frames, std::int64_t timeHns) {
    if (!writer_ || !muxAudio_ || frames == 0 || !interleaved) {
        return S_OK;
    }
    const DWORD bytes = frames * audioChannels_ * 2;
    Microsoft::WRL::ComPtr<IMFMediaBuffer> buffer;
    HRESULT hr = MFCreateMemoryBuffer(bytes, &buffer);
    if (FAILED(hr)) {
        return hr;
    }
    BYTE* dst = nullptr;
    hr = buffer->Lock(&dst, nullptr, nullptr);
    if (FAILED(hr)) {
        return hr;
    }
    std::memcpy(dst, interleaved, bytes);
    buffer->Unlock();
    buffer->SetCurrentLength(bytes);

    Microsoft::WRL::ComPtr<IMFSample> sample;
    hr = MFCreateSample(&sample);
    if (FAILED(hr)) {
        return hr;
    }
    sample->AddBuffer(buffer.Get());
    sample->SetSampleTime(timeHns);
    sample->SetSampleDuration(static_cast<std::int64_t>(frames) * 10'000'000 / audioRate_);
    return writer_->WriteSample(audioStream_, sample.Get());
}

HRESULT VideoSink::finalize() {
    if (!writer_ || finalized_) {
        writer_.Reset();
        return S_OK;
    }
    finalized_ = true;
    const HRESULT hr = writer_->Finalize();
    writer_.Reset();
    if (FAILED(hr)) {
        br::setLastError("Video sink Finalize failed", hr);
    }
    return hr;
}

HRESULT AudioSink::open(const std::wstring& path, UINT sampleRate, UINT channels) {
    finalize();
    sampleRate_ = sampleRate;
    channels_ = channels;
    frames_ = 0;
    finalized_ = false;

    IMFSinkWriter* raw = nullptr;
    HRESULT hr = static_cast<HRESULT>(
        br::openMfSinkWriter(path.c_str(), nullptr, reinterpret_cast<void**>(&raw))
    );
    if (FAILED(hr) || !raw) {
        br::setLastError("audio sink writer failed", hr);
        return FAILED(hr) ? hr : E_FAIL;
    }
    writer_.Attach(raw);

    Microsoft::WRL::ComPtr<IMFMediaType> output;
    hr = MFCreateMediaType(&output);
    if (FAILED(hr)) {
        return hr;
    }
    output->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
    output->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_AAC);
    output->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, sampleRate_);
    output->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, channels_);
    output->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
    output->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, 24000);
    hr = writer_->AddStream(output.Get(), &stream_);
    if (FAILED(hr)) {
        br::setLastError("AAC output type rejected", hr);
        writer_.Reset();
        return hr;
    }

    Microsoft::WRL::ComPtr<IMFMediaType> input;
    hr = MFCreateMediaType(&input);
    if (FAILED(hr)) {
        return hr;
    }
    input->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
    input->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
    input->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, channels_);
    input->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, sampleRate_);
    input->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, channels_ * 2);
    input->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, sampleRate_ * channels_ * 2);
    input->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
    hr = writer_->SetInputMediaType(stream_, input.Get(), nullptr);
    if (FAILED(hr)) {
        br::setLastError("PCM audio input type rejected", hr);
        writer_.Reset();
        return hr;
    }
    hr = writer_->BeginWriting();
    if (FAILED(hr)) {
        br::setLastError("IMFSinkWriter::BeginWriting (audio) failed", hr);
        writer_.Reset();
        DeleteFileW(path.c_str());
    }
    return hr;
}

HRESULT AudioSink::writePCM16(const std::int16_t* interleaved, UINT32 frames, std::int64_t timeHns) {
    if (!writer_ || frames == 0) {
        return S_OK;
    }
    const DWORD bytes = frames * channels_ * 2;
    Microsoft::WRL::ComPtr<IMFMediaBuffer> buffer;
    HRESULT hr = MFCreateMemoryBuffer(bytes, &buffer);
    if (FAILED(hr)) {
        return hr;
    }
    BYTE* dst = nullptr;
    hr = buffer->Lock(&dst, nullptr, nullptr);
    if (FAILED(hr)) {
        return hr;
    }
    std::memcpy(dst, interleaved, bytes);
    buffer->Unlock();
    buffer->SetCurrentLength(bytes);

    Microsoft::WRL::ComPtr<IMFSample> sample;
    hr = MFCreateSample(&sample);
    if (FAILED(hr)) {
        return hr;
    }
    sample->AddBuffer(buffer.Get());
    sample->SetSampleTime(timeHns);
    const std::int64_t duration = static_cast<std::int64_t>(frames) * 10'000'000 / sampleRate_;
    sample->SetSampleDuration(duration);
    hr = writer_->WriteSample(stream_, sample.Get());
    if (SUCCEEDED(hr)) {
        frames_ += frames;
    }
    return hr;
}

HRESULT AudioSink::finalize() {
    if (!writer_ || finalized_) {
        writer_.Reset();
        return S_OK;
    }
    finalized_ = true;
    const HRESULT hr = writer_->Finalize();
    writer_.Reset();
    if (FAILED(hr)) {
        br::setLastError("Audio sink Finalize failed", hr);
    }
    return hr;
}

#else
[[maybe_unused]] static int br_windows_capture_tu_mf = 0;
#endif
