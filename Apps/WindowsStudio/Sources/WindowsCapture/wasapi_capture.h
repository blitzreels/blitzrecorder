#pragma once

#if defined(_WIN32)

#include <cstdint>
#include <vector>

#include <windows.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <mmreg.h>
#include <wrl/client.h>

class WasapiCapture {
public:
    enum class Kind { Loopback, Microphone };

    HRESULT open(Kind kind);
    void close();
    HRESULT start();
    void stop();

    // Converts the next native packet to 48 kHz stereo s16. frames=0 if none.
    HRESULT read(std::vector<std::int16_t>& interleavedStereo, UINT32& frames);

    static constexpr UINT kOutRate = 48000;
    static constexpr UINT kOutChannels = 2;

private:
    void convertPacket(const BYTE* data, UINT32 nativeFrames, DWORD flags, std::vector<std::int16_t>& out, UINT32& outFrames);
    void nativeFrameToStereoFloat(const BYTE* data, UINT32 frameIndex, float& left, float& right) const;

    Microsoft::WRL::ComPtr<IMMDevice> device_;
    Microsoft::WRL::ComPtr<IAudioClient> client_;
    Microsoft::WRL::ComPtr<IAudioCaptureClient> capture_;
    std::vector<BYTE> mixFormatBytes_;
    WAVEFORMATEX* mixFormat_ = nullptr;
    bool isFloat_ = false;
    UINT inRate_ = 48000;
    UINT inChannels_ = 2;
    UINT inBits_ = 32;
    UINT inBlockAlign_ = 8;
    double resamplePos_ = 0;
    float prevLeft_ = 0;
    float prevRight_ = 0;
    bool hasPrev_ = false;
};

#endif
