#if defined(_WIN32)

#include "compose_export.h"

#include "capture_common.h"
#include "mf_rgb32.h"
#include "mf_sink.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include <d3d11.h>
#include <d3dcompiler.h>
#include <objbase.h>
#include <mfapi.h>
#include <mferror.h>
#include <mfreadwrite.h>
#include <wrl/client.h>

#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "d3dcompiler.lib")

namespace {

struct Vertex {
    float x, y, z;
    float u, v;
};

const char* kShader = R"(
Texture2D tex : register(t0);
SamplerState samp : register(s0);
struct VSIn { float3 pos : POSITION; float2 uv : TEXCOORD; };
struct VSOut { float4 pos : SV_POSITION; float2 uv : TEXCOORD; };
VSOut vs_main(VSIn input) {
    VSOut o;
    o.pos = float4(input.pos, 1);
    o.uv = input.uv;
    return o;
}
float4 ps_main(VSOut input) : SV_TARGET {
    return tex.Sample(samp, input.uv);
}
)";

void fillBars(std::uint8_t* bgra, UINT width, UINT height, int frame) {
    const UINT bar = (std::max)(1u, width / 8);
    const std::uint8_t colors[8][3] = {
        {255, 255, 255}, {0, 255, 255}, {255, 255, 0}, {0, 255, 0},
        {255, 0, 255}, {0, 0, 255}, {255, 0, 0}, {32, 32, 32}
    };
    for (UINT y = 0; y < height; ++y) {
        for (UINT x = 0; x < width; ++x) {
            const UINT index = (std::min)(7u, x / bar);
            std::uint8_t* pixel = bgra + (static_cast<size_t>(y) * width + x) * 4;
            pixel[0] = colors[index][0];
            pixel[1] = colors[index][1];
            pixel[2] = colors[index][2];
            pixel[3] = 255;
        }
    }
    const UINT line = static_cast<UINT>((frame * 7) % (std::max)(1u, height));
    std::memset(bgra + static_cast<size_t>(line) * width * 4, 255, static_cast<size_t>(width) * 4);
}

void fillCamera(std::uint8_t* bgra, UINT width, UINT height, int frame) {
    const std::uint8_t b = 40;
    const std::uint8_t g = 160;
    const std::uint8_t r = static_cast<std::uint8_t>(50 + (frame * 5) % 180);
    for (UINT i = 0; i < width * height; ++i) {
        bgra[i * 4 + 0] = b;
        bgra[i * 4 + 1] = g;
        bgra[i * 4 + 2] = r;
        bgra[i * 4 + 3] = 255;
    }
}

void cpuCompose(
    const std::uint8_t* screen,
    UINT screenW,
    UINT screenH,
    const std::uint8_t* camera,
    UINT camW,
    UINT camH,
    std::uint8_t* dest,
    UINT pipX,
    UINT pipY,
    UINT pipW,
    UINT pipH
) {
    std::memcpy(dest, screen, static_cast<size_t>(screenW) * screenH * 4);
    if (!camera || pipW < 2 || pipH < 2 || camW < 2 || camH < 2) {
        return;
    }
    for (UINT y = 0; y < pipH; ++y) {
        const UINT dy = pipY + y;
        if (dy >= screenH) {
            break;
        }
            const UINT sy = (std::min)(camH - 1, y * camH / pipH);
        for (UINT x = 0; x < pipW; ++x) {
            const UINT dx = pipX + x;
            if (dx >= screenW) {
                break;
            }
            const UINT sx = (std::min)(camW - 1, x * camW / pipW);
            std::memcpy(
                dest + (static_cast<size_t>(dy) * screenW + dx) * 4,
                camera + (static_cast<size_t>(sy) * camW + sx) * 4,
                4
            );
        }
    }
}

HRESULT createDevice(ID3D11Device** device, ID3D11DeviceContext** context) {
    D3D_FEATURE_LEVEL levels[] = {D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_0};
    D3D_FEATURE_LEVEL got{};
    HRESULT hr = D3D11CreateDevice(
        nullptr,
        D3D_DRIVER_TYPE_HARDWARE,
        nullptr,
        D3D11_CREATE_DEVICE_BGRA_SUPPORT,
        levels,
        2,
        D3D11_SDK_VERSION,
        device,
        &got,
        context
    );
    if (SUCCEEDED(hr)) {
        return hr;
    }
    return D3D11CreateDevice(
        nullptr,
        D3D_DRIVER_TYPE_WARP,
        nullptr,
        D3D11_CREATE_DEVICE_BGRA_SUPPORT,
        levels,
        2,
        D3D11_SDK_VERSION,
        device,
        &got,
        context
    );
}

HRESULT createTexture(
    ID3D11Device* device,
    UINT width,
    UINT height,
    D3D11_BIND_FLAG extraBind,
    ID3D11Texture2D** texture
) {
    D3D11_TEXTURE2D_DESC desc{};
    desc.Width = width;
    desc.Height = height;
    desc.MipLevels = 1;
    desc.ArraySize = 1;
    desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    desc.SampleDesc.Count = 1;
    desc.Usage = D3D11_USAGE_DEFAULT;
    desc.BindFlags = D3D11_BIND_SHADER_RESOURCE | extraBind;
    return device->CreateTexture2D(&desc, nullptr, texture);
}

struct GpuComposer {
    Microsoft::WRL::ComPtr<ID3D11Device> device;
    Microsoft::WRL::ComPtr<ID3D11DeviceContext> context;
    Microsoft::WRL::ComPtr<ID3D11VertexShader> vs;
    Microsoft::WRL::ComPtr<ID3D11PixelShader> ps;
    Microsoft::WRL::ComPtr<ID3D11InputLayout> inputLayout;
    Microsoft::WRL::ComPtr<ID3D11Buffer> vb;
    Microsoft::WRL::ComPtr<ID3D11SamplerState> sampler;
    Microsoft::WRL::ComPtr<ID3D11Texture2D> screenTex;
    Microsoft::WRL::ComPtr<ID3D11Texture2D> cameraTex;
    Microsoft::WRL::ComPtr<ID3D11Texture2D> outputTex;
    Microsoft::WRL::ComPtr<ID3D11Texture2D> staging;
    Microsoft::WRL::ComPtr<ID3D11RenderTargetView> rtv;
    Microsoft::WRL::ComPtr<ID3D11ShaderResourceView> screenSRV;
    Microsoft::WRL::ComPtr<ID3D11ShaderResourceView> cameraSRV;
    UINT width = 0;
    UINT height = 0;
    UINT camW = 0;
    UINT camH = 0;
    std::vector<std::uint8_t> blackCam;

    bool matches(UINT canvasW, UINT canvasH, UINT cameraW, UINT cameraH) const {
        return device && width == canvasW && height == canvasH
            && camW == (std::max)(2u, cameraW) && camH == (std::max)(2u, cameraH);
    }

    HRESULT init(UINT canvasW, UINT canvasH, UINT cameraW, UINT cameraH) {
        vs.Reset();
        ps.Reset();
        inputLayout.Reset();
        vb.Reset();
        sampler.Reset();
        screenTex.Reset();
        cameraTex.Reset();
        outputTex.Reset();
        staging.Reset();
        rtv.Reset();
        screenSRV.Reset();
        cameraSRV.Reset();
        context.Reset();
        device.Reset();
        width = canvasW;
        height = canvasH;
        camW = (std::max)(2u, cameraW);
        camH = (std::max)(2u, cameraH);
        blackCam.assign(static_cast<size_t>(camW) * camH * 4, 0);
        HRESULT hr = createDevice(device.ReleaseAndGetAddressOf(), context.ReleaseAndGetAddressOf());
        if (FAILED(hr)) {
            return hr;
        }
        Microsoft::WRL::ComPtr<ID3DBlob> vsBlob;
        Microsoft::WRL::ComPtr<ID3DBlob> psBlob;
        Microsoft::WRL::ComPtr<ID3DBlob> errors;
        hr = D3DCompile(
            kShader,
            std::strlen(kShader),
            nullptr,
            nullptr,
            nullptr,
            "vs_main",
            "vs_5_0",
            0,
            0,
            &vsBlob,
            &errors
        );
        if (FAILED(hr)) {
            return hr;
        }
        hr = D3DCompile(
            kShader,
            std::strlen(kShader),
            nullptr,
            nullptr,
            nullptr,
            "ps_main",
            "ps_5_0",
            0,
            0,
            &psBlob,
            &errors
        );
        if (FAILED(hr)) {
            return hr;
        }
        hr = device->CreateVertexShader(vsBlob->GetBufferPointer(), vsBlob->GetBufferSize(), nullptr, &vs);
        if (FAILED(hr)) {
            return hr;
        }
        hr = device->CreatePixelShader(psBlob->GetBufferPointer(), psBlob->GetBufferSize(), nullptr, &ps);
        if (FAILED(hr)) {
            return hr;
        }
        D3D11_INPUT_ELEMENT_DESC layout[] = {
            {"POSITION", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 0, D3D11_INPUT_PER_VERTEX_DATA, 0},
            {"TEXCOORD", 0, DXGI_FORMAT_R32G32_FLOAT, 0, 12, D3D11_INPUT_PER_VERTEX_DATA, 0}
        };
        hr = device->CreateInputLayout(
            layout,
            2,
            vsBlob->GetBufferPointer(),
            vsBlob->GetBufferSize(),
            &inputLayout
        );
        if (FAILED(hr)) {
            return hr;
        }
        D3D11_BUFFER_DESC vbDesc{};
        vbDesc.ByteWidth = sizeof(Vertex) * 8;
        vbDesc.Usage = D3D11_USAGE_DYNAMIC;
        vbDesc.BindFlags = D3D11_BIND_VERTEX_BUFFER;
        vbDesc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
        hr = device->CreateBuffer(&vbDesc, nullptr, &vb);
        if (FAILED(hr)) {
            return hr;
        }
        D3D11_SAMPLER_DESC sampDesc{};
        sampDesc.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR;
        sampDesc.AddressU = D3D11_TEXTURE_ADDRESS_CLAMP;
        sampDesc.AddressV = D3D11_TEXTURE_ADDRESS_CLAMP;
        sampDesc.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP;
        hr = device->CreateSamplerState(&sampDesc, &sampler);
        if (FAILED(hr)) {
            return hr;
        }
        hr = createTexture(device.Get(), width, height, D3D11_BIND_RENDER_TARGET, &screenTex);
        if (FAILED(hr)) {
            return hr;
        }
        hr = createTexture(device.Get(), camW, camH, static_cast<D3D11_BIND_FLAG>(0), &cameraTex);
        if (FAILED(hr)) {
            return hr;
        }
        hr = createTexture(device.Get(), width, height, D3D11_BIND_RENDER_TARGET, &outputTex);
        if (FAILED(hr)) {
            return hr;
        }
        D3D11_TEXTURE2D_DESC stagingDesc{};
        outputTex->GetDesc(&stagingDesc);
        stagingDesc.Usage = D3D11_USAGE_STAGING;
        stagingDesc.BindFlags = 0;
        stagingDesc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
        hr = device->CreateTexture2D(&stagingDesc, nullptr, &staging);
        if (FAILED(hr)) {
            return hr;
        }
        hr = device->CreateRenderTargetView(outputTex.Get(), nullptr, &rtv);
        if (FAILED(hr)) {
            return hr;
        }
        hr = device->CreateShaderResourceView(screenTex.Get(), nullptr, &screenSRV);
        if (FAILED(hr)) {
            return hr;
        }
        return device->CreateShaderResourceView(cameraTex.Get(), nullptr, &cameraSRV);
    }

    HRESULT compose(
        const std::uint8_t* screen,
        const std::uint8_t* camera,
        float camX,
        float camY,
        float camNormW,
        float camNormH,
        std::vector<std::uint8_t>& bgra
    ) {
        if (!device || !context || !screen) {
            return E_FAIL;
        }
        context->UpdateSubresource(screenTex.Get(), 0, nullptr, screen, width * 4, 0);
        context->UpdateSubresource(
            cameraTex.Get(),
            0,
            nullptr,
            camera ? camera : blackCam.data(),
            camW * 4,
            0
        );

        const float left = camX * 2.0f - 1.0f;
        const float right = (camX + camNormW) * 2.0f - 1.0f;
        const float top = 1.0f - camY * 2.0f;
        const float bottom = 1.0f - (camY + camNormH) * 2.0f;
        Vertex verts[] = {
            {-1, 1, 0, 0, 0}, {1, 1, 0, 1, 0}, {-1, -1, 0, 0, 1}, {1, -1, 0, 1, 1},
            {left, top, 0, 0, 0}, {right, top, 0, 1, 0}, {left, bottom, 0, 0, 1}, {right, bottom, 0, 1, 1}
        };
        D3D11_MAPPED_SUBRESOURCE mappedVb{};
        HRESULT hr = context->Map(vb.Get(), 0, D3D11_MAP_WRITE_DISCARD, 0, &mappedVb);
        if (FAILED(hr)) {
            return hr;
        }
        std::memcpy(mappedVb.pData, verts, sizeof(verts));
        context->Unmap(vb.Get(), 0);

        D3D11_VIEWPORT viewport{};
        viewport.Width = static_cast<float>(width);
        viewport.Height = static_cast<float>(height);
        viewport.MaxDepth = 1.0f;
        context->OMSetRenderTargets(1, rtv.GetAddressOf(), nullptr);
        context->RSSetViewports(1, &viewport);
        context->IASetInputLayout(inputLayout.Get());
        context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLESTRIP);
        UINT stride = sizeof(Vertex);
        UINT offset = 0;
        context->IASetVertexBuffers(0, 1, vb.GetAddressOf(), &stride, &offset);
        context->VSSetShader(vs.Get(), nullptr, 0);
        context->PSSetShader(ps.Get(), nullptr, 0);
        context->PSSetSamplers(0, 1, sampler.GetAddressOf());
        context->PSSetShaderResources(0, 1, screenSRV.GetAddressOf());
        context->Draw(4, 0);
        if (camera) {
            context->PSSetShaderResources(0, 1, cameraSRV.GetAddressOf());
            context->Draw(4, 4);
        }
        ID3D11ShaderResourceView* none = nullptr;
        context->PSSetShaderResources(0, 1, &none);
        context->OMSetRenderTargets(0, nullptr, nullptr);

        context->CopyResource(staging.Get(), outputTex.Get());
        D3D11_MAPPED_SUBRESOURCE mapped{};
        hr = context->Map(staging.Get(), 0, D3D11_MAP_READ, 0, &mapped);
        if (FAILED(hr)) {
            return hr;
        }
        bgra.resize(static_cast<size_t>(width) * height * 4);
        for (UINT y = 0; y < height; ++y) {
            std::memcpy(
                bgra.data() + static_cast<size_t>(y) * width * 4,
                static_cast<const std::uint8_t*>(mapped.pData) + static_cast<size_t>(y) * mapped.RowPitch,
                static_cast<size_t>(width) * 4
            );
        }
        context->Unmap(staging.Get(), 0);
        return S_OK;
    }
};

bool timestampKept(std::int64_t hns, const std::vector<br_kept_range>& ranges) {
    if (ranges.empty()) {
        return true;
    }
    for (const br_kept_range& range : ranges) {
        if (hns >= range.take_start_hns && hns < range.take_end_hns) {
            return true;
        }
    }
    return false;
}

void keepPcmRanges(std::vector<std::int16_t>& mixed, const std::vector<br_kept_range>& ranges) {
    if (ranges.empty() || mixed.size() < 2) {
        return;
    }
    std::vector<std::int16_t> kept;
    const size_t frames = mixed.size() / 2;
    for (const br_kept_range& range : ranges) {
        const size_t startFrame = static_cast<size_t>(
            (std::max)(std::int64_t{0}, range.take_start_hns) * 48000 / 10'000'000
        );
        size_t endFrame = static_cast<size_t>(
            (std::max)(std::int64_t{0}, range.take_end_hns) * 48000 / 10'000'000
        );
        if (startFrame >= frames) {
            continue;
        }
        endFrame = (std::min)(endFrame, frames);
        if (endFrame <= startFrame) {
            continue;
        }
        kept.insert(
            kept.end(),
            mixed.begin() + static_cast<std::ptrdiff_t>(startFrame * 2),
            mixed.begin() + static_cast<std::ptrdiff_t>(endFrame * 2)
        );
    }
    mixed.swap(kept);
}

GpuComposer gSharedComposer;
std::mutex gSharedComposerMu;

void cpuComposeNormalized(
    const std::uint8_t* screen,
    UINT screenW,
    UINT screenH,
    const std::uint8_t* camera,
    UINT camW,
    UINT camH,
    std::uint8_t* dest,
    double cameraX,
    double cameraY,
    double cameraWidth,
    double cameraHeight
) {
    const UINT pipW = (std::max)(2u, static_cast<UINT>(cameraWidth * screenW) & ~1u);
    const UINT pipH = (std::max)(2u, static_cast<UINT>(cameraHeight * screenH) & ~1u);
    const UINT pipX = static_cast<UINT>((std::min)(1.0, (std::max)(0.0, cameraX)) * screenW);
    const UINT pipY = static_cast<UINT>((std::min)(1.0, (std::max)(0.0, cameraY)) * screenH);
    cpuCompose(screen, screenW, screenH, camera, camW, camH, dest, pipX, pipY, pipW, pipH);
}

HRESULT writeSine(const std::wstring& path, UINT seconds, UINT rate) {
    AudioSink sink;
    HRESULT hr = sink.open(path, rate, 2);
    if (FAILED(hr)) {
        return hr;
    }
    const UINT frames = rate;
    std::vector<std::int16_t> pcm(static_cast<size_t>(frames) * 2);
    std::int64_t time = 0;
    for (UINT s = 0; s < seconds; ++s) {
        for (UINT i = 0; i < frames; ++i) {
            const float sample = std::sin(2.0f * 3.14159265f * 440.0f * static_cast<float>(s * frames + i) / static_cast<float>(rate));
            const auto q = static_cast<std::int16_t>(sample * 0.2f * 32767.0f);
            pcm[i * 2] = q;
            pcm[i * 2 + 1] = q;
        }
        sink.writePCM16(pcm.data(), frames, time);
        time += 10'000'000;
    }
    return sink.finalize();
}

HRESULT writeVideo(
    const std::wstring& path,
    const std::vector<std::vector<std::uint8_t>>& frames,
    UINT width,
    UINT height,
    int fps
) {
    VideoSink sink;
    HRESULT hr = sink.open(path, width, height, static_cast<UINT>(fps));
    if (FAILED(hr)) {
        return hr;
    }
    const std::int64_t duration = 10'000'000 / (std::max)(1, fps);
    for (size_t i = 0; i < frames.size(); ++i) {
        sink.writeBGRA(frames[i].data(), width * 4, static_cast<std::int64_t>(i) * duration, duration);
    }
    return sink.finalize();
}

}  // namespace

int exportComposedFixture(
    const char* outputDir,
    int canvasWidth,
    int canvasHeight,
    double cameraX,
    double cameraY,
    double cameraWidth,
    double cameraHeight,
    int frameCount,
    int fps
) {
    if (!outputDir || !outputDir[0]) {
        br::setLastError("export output_dir is empty");
        return 1;
    }
    const UINT width = static_cast<UINT>((std::max)(2, canvasWidth)) & ~1u;
    const UINT height = static_cast<UINT>((std::max)(2, canvasHeight)) & ~1u;
    const UINT camW = (std::max)(2u, (width / 4) & ~1u);
    const UINT camH = (std::max)(2u, (height / 4) & ~1u);
    const int frames = (std::max)(1, frameCount);
    const int frameRate = (std::max)(1, fps);
    const std::wstring directory = br::utf8ToWide(outputDir);

    br::ensureCom();
    HRESULT hr = MFStartup(MF_VERSION, MFSTARTUP_LITE);
    if (FAILED(hr) && hr != MF_E_ALREADY_INITIALIZED) {
        br::setLastError("MFStartup failed for fixture export", hr);
        return 1;
    }

    std::vector<std::vector<std::uint8_t>> screenFrames(static_cast<size_t>(frames));
    std::vector<std::vector<std::uint8_t>> cameraFrames(static_cast<size_t>(frames));
    std::vector<std::vector<std::uint8_t>> composedFrames(static_cast<size_t>(frames));
    for (int i = 0; i < frames; ++i) {
        screenFrames[static_cast<size_t>(i)].assign(static_cast<size_t>(width) * height * 4, 0);
        cameraFrames[static_cast<size_t>(i)].assign(static_cast<size_t>(camW) * camH * 4, 0);
        fillBars(screenFrames[static_cast<size_t>(i)].data(), width, height, i);
        fillCamera(cameraFrames[static_cast<size_t>(i)].data(), camW, camH, i);
    }

    GpuComposer gpu;
    bool usedD3D = SUCCEEDED(gpu.init(width, height, camW, camH));
    if (usedD3D) {
        for (int i = 0; i < frames; ++i) {
            const HRESULT composeHr = gpu.compose(
                screenFrames[static_cast<size_t>(i)].data(),
                cameraFrames[static_cast<size_t>(i)].data(),
                static_cast<float>(cameraX),
                static_cast<float>(cameraY),
                static_cast<float>(cameraWidth),
                static_cast<float>(cameraHeight),
                composedFrames[static_cast<size_t>(i)]
            );
            if (FAILED(composeHr)) {
                usedD3D = false;
                break;
            }
        }
    }

    if (!usedD3D) {
        const UINT pipW = (std::max)(2u, static_cast<UINT>(cameraWidth * width) & ~1u);
        const UINT pipH = (std::max)(2u, static_cast<UINT>(cameraHeight * height) & ~1u);
        const UINT pipX = static_cast<UINT>(cameraX * width);
        const UINT pipY = static_cast<UINT>(cameraY * height);
        for (int i = 0; i < frames; ++i) {
            composedFrames[static_cast<size_t>(i)].assign(static_cast<size_t>(width) * height * 4, 0);
            cpuCompose(
                screenFrames[static_cast<size_t>(i)].data(),
                width,
                height,
                cameraFrames[static_cast<size_t>(i)].data(),
                camW,
                camH,
                composedFrames[static_cast<size_t>(i)].data(),
                pipX,
                pipY,
                pipW,
                pipH
            );
        }
    }

    hr = writeVideo(br::joinPath(directory, L"screen.mp4"), screenFrames, width, height, frameRate);
    if (FAILED(hr)) {
        return 1;
    }
    hr = writeVideo(br::joinPath(directory, L"camera.mp4"), cameraFrames, camW, camH, frameRate);
    if (FAILED(hr)) {
        return 1;
    }
    hr = writeVideo(br::joinPath(directory, L"export.mp4"), composedFrames, width, height, frameRate);
    if (FAILED(hr)) {
        return 1;
    }
    hr = writeSine(br::joinPath(directory, L"audio.m4a"), (std::max)(1, frames / frameRate), 48000);
    if (FAILED(hr)) {
        return 1;
    }
    const std::string manifest = br::joinUtf8Path(outputDir, "take.json");
    if (!br::fileExistsUtf8(manifest.c_str())
        && !br::writeTakeSidecars(outputDir, true, false, true)) {
        return 1;
    }
    return 0;
}

HRESULT openRGBReader(const std::wstring& path, IMFSourceReader** reader, UINT& width, UINT& height) {
    Microsoft::WRL::ComPtr<IMFAttributes> attrs;
    HRESULT hr = MFCreateAttributes(&attrs, 1);
    if (FAILED(hr)) {
        return hr;
    }
    attrs->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE);
    Microsoft::WRL::ComPtr<IMFSourceReader> local;
    IMFSourceReader* raw = nullptr;
    hr = static_cast<HRESULT>(br::openMfSourceReader(path.c_str(), attrs.Get(), reinterpret_cast<void**>(&raw)));
    if (FAILED(hr) || !raw) {
        return FAILED(hr) ? hr : E_FAIL;
    }
    local.Attach(raw);
    Microsoft::WRL::ComPtr<IMFMediaType> type;
    hr = MFCreateMediaType(&type);
    if (FAILED(hr)) {
        return hr;
    }
    type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
    hr = local->SetCurrentMediaType(static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), nullptr, type.Get());
    if (FAILED(hr)) {
        br::setLastError("compose RGB32 type rejected", hr);
        return hr;
    }
    Microsoft::WRL::ComPtr<IMFMediaType> current;
    hr = local->GetCurrentMediaType(static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), &current);
    if (FAILED(hr)) {
        return hr;
    }
    UINT32 w = 0;
    UINT32 h = 0;
    MFGetAttributeSize(current.Get(), MF_MT_FRAME_SIZE, &w, &h);
    width = w & ~1u;
    height = h & ~1u;
    *reader = local.Detach();
    return S_OK;
}

HRESULT readBGRA(IMFSourceReader* reader, UINT width, UINT height, std::vector<std::uint8_t>& bgra, LONGLONG& timestamp, bool& ended) {
    ended = false;
    Microsoft::WRL::ComPtr<IMFSample> sample;
    DWORD flags = 0;
    HRESULT hr = reader->ReadSample(
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
    return copyMediaBufferToTopDownBGRA(buffer.Get(), width, height, 0, bgra);
}

std::string parentUtf8(const char* path) {
    std::string s = path ? path : "";
    while (!s.empty() && (s.back() == '\\' || s.back() == '/')) {
        s.pop_back();
    }
    const auto slash = s.find_last_of("\\/");
    if (slash == std::string::npos) {
        return ".";
    }
    return s.substr(0, slash);
}

HRESULT openPcmReader(const char* path, IMFSourceReader** reader) {
    if (!path || !path[0] || !br::fileExistsUtf8(path) || !reader) {
        return S_FALSE;
    }
    *reader = nullptr;
    Microsoft::WRL::ComPtr<IMFSourceReader> local;
    IMFSourceReader* raw = nullptr;
    HRESULT hr = static_cast<HRESULT>(
        br::openMfSourceReader(br::utf8ToWide(path).c_str(), nullptr, reinterpret_cast<void**>(&raw))
    );
    if (FAILED(hr) || !raw) {
        return S_FALSE;
    }
    local.Attach(raw);
    Microsoft::WRL::ComPtr<IMFMediaType> type;
    hr = MFCreateMediaType(&type);
    if (FAILED(hr)) {
        return hr;
    }
    type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
    type->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
    type->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, 2);
    type->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, 48000);
    type->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
    type->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, 4);
    type->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, 48000 * 4);
    hr = local->SetCurrentMediaType(static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM), nullptr, type.Get());
    if (FAILED(hr)) {
        return S_FALSE;
    }
    local->SetStreamSelection(static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), FALSE);
    local->SetStreamSelection(static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM), TRUE);
    *reader = local.Detach();
    return S_OK;
}

void decodePcm16(IMFSourceReader* reader, std::vector<std::int16_t>& pcm) {
    if (!reader) {
        return;
    }
    for (;;) {
        Microsoft::WRL::ComPtr<IMFSample> sample;
        DWORD flags = 0;
        if (FAILED(reader->ReadSample(
                static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM),
                0,
                nullptr,
                &flags,
                nullptr,
                &sample
            ))
            || (flags & MF_SOURCE_READERF_ENDOFSTREAM)
            || !sample) {
            break;
        }
        Microsoft::WRL::ComPtr<IMFMediaBuffer> buffer;
        if (FAILED(sample->ConvertToContiguousBuffer(&buffer))) {
            continue;
        }
        BYTE* data = nullptr;
        DWORD current = 0;
        if (FAILED(buffer->Lock(&data, nullptr, &current)) || !data || current < 2) {
            continue;
        }
        const size_t samples = current / sizeof(std::int16_t);
        const size_t offset = pcm.size();
        pcm.resize(offset + samples);
        std::memcpy(pcm.data() + offset, data, samples * sizeof(std::int16_t));
        buffer->Unlock();
    }
}

void mixPcm16(std::vector<std::int16_t>& dest, const std::vector<std::int16_t>& src) {
    if (src.size() > dest.size()) {
        dest.resize(src.size(), 0);
    }
    for (size_t i = 0; i < src.size(); ++i) {
        const int mixed = static_cast<int>(dest[i]) + static_cast<int>(src[i]);
        dest[i] = static_cast<std::int16_t>((std::max)(-32768, (std::min)(32767, mixed)));
    }
}

void loadMixedTakePcm(
    const char* micPath,
    const char* systemPath,
    const std::vector<br_kept_range>& ranges,
    std::vector<std::int16_t>& mixed
) {
    mixed.clear();
    Microsoft::WRL::ComPtr<IMFSourceReader> mic;
    Microsoft::WRL::ComPtr<IMFSourceReader> systemAudio;
    openPcmReader(micPath, &mic);
    openPcmReader(systemPath, &systemAudio);
    std::vector<std::int16_t> extra;
    decodePcm16(mic.Get(), mixed);
    decodePcm16(systemAudio.Get(), extra);
    mixPcm16(mixed, extra);
    keepPcmRanges(mixed, ranges);
}

void writePcmAt(
    VideoSink& sink,
    const std::vector<std::int16_t>& mixed,
    size_t& offset,
    UINT32 frames,
    std::int64_t timeHns
) {
    if (!sink.hasAudio() || frames == 0 || offset >= mixed.size()) {
        return;
    }
    const UINT32 available = static_cast<UINT32>((mixed.size() - offset) / 2);
    const UINT32 take = (std::min)(frames, available);
    if (take == 0) {
        return;
    }
    sink.writePCM16(mixed.data() + offset, take, timeHns);
    offset += static_cast<size_t>(take) * 2;
}

int composeTakeFiles(
    const char* screenPath,
    const char* cameraPath,
    const char* exportPath,
    double cameraX,
    double cameraY,
    double cameraWidth,
    double cameraHeight
) {
    if (!screenPath || !screenPath[0] || !exportPath || !exportPath[0]) {
        br::setLastError("compose take paths are empty");
        return 1;
    }
    br::setLastError("");
    br::ensureCom();
    HRESULT hr = MFStartup(MF_VERSION, MFSTARTUP_LITE);
    if (FAILED(hr) && hr != MF_E_ALREADY_INITIALIZED) {
        br::setLastError("MFStartup failed for compose take", hr);
        return 1;
    }

    Microsoft::WRL::ComPtr<IMFSourceReader> screen;
    UINT screenW = 0;
    UINT screenH = 0;
    hr = openRGBReader(br::utf8ToWide(screenPath), &screen, screenW, screenH);
    if (FAILED(hr)) {
        return 1;
    }

    Microsoft::WRL::ComPtr<IMFSourceReader> camera;
    UINT camW = 0;
    UINT camH = 0;
    bool hasCamera = cameraPath && cameraPath[0];
    if (hasCamera) {
        hr = openRGBReader(br::utf8ToWide(cameraPath), &camera, camW, camH);
        if (FAILED(hr) || !camera) {
            hasCamera = false;
            camera.Reset();
            hr = S_OK;
        }
    }

    VideoSink sink;
    const std::string takeDir = parentUtf8(screenPath);
    const std::string mic = br::joinUtf8Path(takeDir, "audio.m4a");
    const std::string systemAudio = br::joinUtf8Path(takeDir, "system-audio.m4a");
    const bool wantAudio = br::fileExistsUtf8(mic.c_str()) || br::fileExistsUtf8(systemAudio.c_str());
    std::vector<br_kept_range> ranges;
    br::readKeptRangesHNS(takeDir.c_str(), ranges);
    hr = sink.open(br::utf8ToWide(exportPath), screenW, screenH, 30, wantAudio);
    if (FAILED(hr) && wantAudio) {
        br::setLastError("AAC mux failed; export is video-only", hr);
        hr = sink.open(br::utf8ToWide(exportPath), screenW, screenH, 30, false);
    }
    if (FAILED(hr)) {
        return 1;
    }

    std::vector<std::int16_t> mixed;
    if (sink.hasAudio()) {
        loadMixedTakePcm(mic.c_str(), systemAudio.c_str(), ranges, mixed);
        if (mixed.empty()) {
            br::setLastError("audio.m4a did not decode; export is video-only");
        }
    }
    size_t pcmOffset = 0;
    const UINT32 pcmPerFrame = 48000 / 30;

    const UINT pipW = (std::max)(2u, static_cast<UINT>(cameraWidth * screenW) & ~1u);
    const UINT pipH = (std::max)(2u, static_cast<UINT>(cameraHeight * screenH) & ~1u);
    const UINT pipX = static_cast<UINT>((std::min)(1.0, (std::max)(0.0, cameraX)) * screenW);
    const UINT pipY = static_cast<UINT>((std::min)(1.0, (std::max)(0.0, cameraY)) * screenH);
    GpuComposer gpu;
    bool useGpu = SUCCEEDED(gpu.init(
        screenW,
        screenH,
        hasCamera ? camW : 2u,
        hasCamera ? camH : 2u
    ));
    const std::int64_t duration = 10'000'000 / 30;
    std::vector<std::uint8_t> screenBGRA;
    std::vector<std::uint8_t> cameraBGRA;
    std::vector<std::uint8_t> composed;
    std::int64_t outTime = 0;
    auto consumeCamera = [&] {
        if (!hasCamera) {
            return;
        }
        LONGLONG camTime = 0;
        bool camEnded = false;
        const HRESULT camHr = readBGRA(camera.Get(), camW, camH, cameraBGRA, camTime, camEnded);
        if (FAILED(camHr) && !camEnded && cameraBGRA.empty()) {
            cameraBGRA.assign(static_cast<size_t>(camW) * camH * 4, 0);
        }
    };
    auto composeFrame = [&] {
        const std::uint8_t* camPixels = hasCamera && !cameraBGRA.empty() ? cameraBGRA.data() : nullptr;
        if (useGpu) {
            const HRESULT gpuHr = gpu.compose(
                screenBGRA.data(),
                camPixels,
                static_cast<float>(cameraX),
                static_cast<float>(cameraY),
                static_cast<float>(cameraWidth),
                static_cast<float>(cameraHeight),
                composed
            );
            if (SUCCEEDED(gpuHr)) {
                return;
            }
            useGpu = false;
        }
        composed.assign(static_cast<size_t>(screenW) * screenH * 4, 0);
        cpuCompose(
            screenBGRA.data(),
            screenW,
            screenH,
            camPixels,
            camW,
            camH,
            composed.data(),
            pipX,
            pipY,
            pipW,
            pipH
        );
    };
    for (;;) {
        LONGLONG timestamp = 0;
        bool ended = false;
        hr = readBGRA(screen.Get(), screenW, screenH, screenBGRA, timestamp, ended);
        if (ended || FAILED(hr)) {
            break;
        }
        consumeCamera();
        if (!timestampKept(timestamp, ranges)) {
            continue;
        }
        composeFrame();
        const HRESULT writeHr = sink.writeBGRA(composed.data(), screenW * 4, outTime, duration);
        if (FAILED(writeHr)) {
            br::setLastError("H.264 compose write failed", writeHr);
            return 1;
        }
        writePcmAt(sink, mixed, pcmOffset, pcmPerFrame, outTime);
        outTime += duration;
    }
    if (sink.hasAudio() && pcmOffset < mixed.size()) {
        const UINT32 left = static_cast<UINT32>((mixed.size() - pcmOffset) / 2);
        writePcmAt(sink, mixed, pcmOffset, left, outTime);
    }
    return FAILED(sink.finalize()) ? 1 : 0;
}

int composePipBGRA(
    const unsigned char* screen,
    unsigned screenW,
    unsigned screenH,
    const unsigned char* camera,
    unsigned camW,
    unsigned camH,
    unsigned char* dest,
    unsigned destBytes,
    double cameraX,
    double cameraY,
    double cameraWidth,
    double cameraHeight
) {
    if (!screen || !dest || screenW < 2 || screenH < 2) {
        return 1;
    }
    const size_t needed = static_cast<size_t>(screenW) * screenH * 4;
    if (destBytes < needed) {
        return 1;
    }
    if (!camera || camW < 2 || camH < 2) {
        std::memcpy(dest, screen, needed);
        return 0;
    }
    std::lock_guard<std::mutex> lock(gSharedComposerMu);
    if (!gSharedComposer.matches(screenW, screenH, camW, camH)) {
        if (FAILED(gSharedComposer.init(screenW, screenH, camW, camH))) {
            cpuComposeNormalized(
                screen,
                screenW,
                screenH,
                camera,
                camW,
                camH,
                dest,
                cameraX,
                cameraY,
                cameraWidth,
                cameraHeight
            );
            return 0;
        }
    }
    std::vector<std::uint8_t> composed;
    if (SUCCEEDED(gSharedComposer.compose(
            screen,
            camera,
            static_cast<float>(cameraX),
            static_cast<float>(cameraY),
            static_cast<float>(cameraWidth),
            static_cast<float>(cameraHeight),
            composed
        ))
        && composed.size() >= needed) {
        std::memcpy(dest, composed.data(), needed);
        return 0;
    }
    cpuComposeNormalized(
        screen,
        screenW,
        screenH,
        camera,
        camW,
        camH,
        dest,
        cameraX,
        cameraY,
        cameraWidth,
        cameraHeight
    );
    return 0;
}

#else
[[maybe_unused]] static int br_windows_capture_tu_compose = 0;
#endif
