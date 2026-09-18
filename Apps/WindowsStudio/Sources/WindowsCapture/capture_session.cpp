#if defined(_WIN32)

#include "capture_session.h"

#include "capture_common.h"
#include "compose_export.h"
#include "dxgi_duplicator.h"
#include "mf_camera.h"
#include "mf_sink.h"
#include "monitor_list.h"
#include "wasapi_capture.h"
#include "wgc_capturer.h"

#include <algorithm>
#include <chrono>
#include <cstring>
#include <string>

#include <avrt.h>
#include <mfapi.h>
#include <mferror.h>
#include <windows.h>

int CaptureSession::start(
    const char* outputDir,
    int monitorIndex,
    bool systemAudio,
    bool mic,
    bool camera,
    void* hwnd,
    int cropX,
    int cropY,
    int cropW,
    int cropH
) {
    if (running_.load()) {
        br::setLastError("Capture is already running");
        return 1;
    }
    if (!outputDir || !outputDir[0]) {
        br::setLastError("output_dir is empty");
        return 1;
    }
    br::setLastError("");
    const std::wstring directory = br::utf8ToWide(outputDir);
    if (directory.empty()) {
        br::setLastError("output_dir is not valid UTF-8");
        return 1;
    }

    HRESULT mfHr = MFStartup(MF_VERSION, MFSTARTUP_LITE);
    if (FAILED(mfHr) && mfHr != MF_E_ALREADY_INITIALIZED) {
        br::setLastError("MFStartup failed (install the Media Feature Pack on N/KN SKUs)", mfHr);
        return 1;
    }

    running_ = true;
    previewCamera_ = camera;
    takeDir_ = outputDir;
    pipX_ = 0.68;
    pipY_ = 0.68;
    pipW_ = 0.28;
    pipH_ = 0.28;
    br::readCameraPip(outputDir, pipX_, pipY_, pipW_, pipH_);
    if (hwnd) {
        cropX_ = 0;
        cropY_ = 0;
        cropW_ = 0;
        cropH_ = 0;
    } else {
        cropX_ = cropX;
        cropY_ = cropY;
        cropW_ = cropW;
        cropH_ = cropH;
    }
    {
        std::lock_guard<std::mutex> lock(previewMu_);
        preview_.clear();
        previewW_ = 0;
        previewH_ = 0;
        cameraPreview_.clear();
        cameraPreviewW_ = 0;
        cameraPreviewH_ = 0;
    }
    videoReady_ = false;
    cameraReady_ = !camera;
    loopbackReady_ = !systemAudio;
    micReady_ = !mic;
    videoHr_ = static_cast<long>(0x80004005L);
    cameraHr_ = 0;
    loopbackHr_ = 0;
    micHr_ = 0;

    videoThread_ = std::thread(&CaptureSession::videoMain, this, directory, monitorIndex, hwnd);
    if (camera) {
        cameraThread_ = std::thread(&CaptureSession::cameraMain, this, br::joinPath(directory, L"camera.mp4"));
    }
    if (systemAudio) {
        loopbackThread_ = std::thread(
            &CaptureSession::audioMain,
            this,
            br::joinPath(directory, L"system-audio.m4a"),
            true
        );
    }
    if (mic) {
        micThread_ = std::thread(
            &CaptureSession::audioMain,
            this,
            br::joinPath(directory, L"audio.m4a"),
            false
        );
    }

    const ULONGLONG deadline = GetTickCount64() + 70000;
    ULONGLONG optionalDeadline = 0;
    ULONGLONG micDeadline = 0;
    auto requiredReady = [&] {
        return videoReady_ && (!mic || micReady_);
    };
    std::unique_lock<std::mutex> lock(readyMu_);
    for (;;) {
        if (requiredReady() && cameraReady_ && loopbackReady_) {
            break;
        }
        if (GetTickCount64() >= deadline) {
            break;
        }
        if (videoReady_ && !FAILED(videoHr_) && mic) {
            if (micDeadline == 0) {
                micDeadline = GetTickCount64() + 8000;
            }
            if (!micReady_ && GetTickCount64() >= micDeadline) {
                break;
            }
        }
        if (requiredReady()) {
            if (FAILED(videoHr_) || (mic && FAILED(micHr_))) {
                break;
            }
            if (optionalDeadline == 0) {
                optionalDeadline = GetTickCount64() + 4000;
            }
            if (GetTickCount64() >= optionalDeadline) {
                break;
            }
        }
        const ULONGLONG now = GetTickCount64();
        const DWORD slice = static_cast<DWORD>((std::min)(static_cast<ULONGLONG>(50), deadline - now));
        readyCv_.wait_for(lock, std::chrono::milliseconds(slice));
        lock.unlock();
        MSG msg{};
        while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
            if (msg.message == WM_QUIT) {
                running_ = false;
                PostQuitMessage(static_cast<int>(msg.wParam));
                br::setLastError("capture start cancelled");
                stop();
                return 1;
            }
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
        lock.lock();
    }
    if (!videoReady_ || FAILED(videoHr_)) {
        lock.unlock();
        const bool denied = videoHr_ == static_cast<long>(0x80070005L)
            || videoHr_ == static_cast<long>(0x887A002BL);
        if (!videoReady_) {
            br::setLastError("No screen frame. Allow Screen recording in Windows Settings > Privacy.");
            br::openSettingsUri(L"ms-settings:privacy-graphicscapture");
        } else if (denied) {
            br::openSettingsUri(L"ms-settings:privacy-graphicscapture");
        }
        stop();
        return 1;
    }
    if (mic && (!micReady_ || FAILED(micHr_))) {
        lock.unlock();
        const bool denied = micHr_ == static_cast<long>(0x80070005L)
            || micHr_ == static_cast<long>(0x887A002BL);
        if (!micReady_) {
            br::setLastError("Microphone did not start. Allow Microphone in Windows Settings > Privacy.");
            br::openSettingsUri(L"ms-settings:privacy-microphone");
        } else if (denied) {
            br::openSettingsUri(L"ms-settings:privacy-microphone");
        }
        stop();
        return 1;
    }
    std::string warning;
    if (camera && (FAILED(cameraHr_) || !cameraReady_)) {
        warning = cameraReady_ ? "camera failed; recording without camera" : "camera still starting";
    }
    if (systemAudio && (FAILED(loopbackHr_) || !loopbackReady_)) {
        if (!warning.empty()) {
            warning += "; ";
        }
        warning += loopbackReady_ ? "system audio failed; recording without loopback" : "system audio still starting";
    }
    if (camera && cameraHr_ == static_cast<long>(0x80070005L)) {
        br::openSettingsUri(L"ms-settings:privacy-webcam");
    }
    if (!warning.empty()) {
        br::setLastError(warning);
    }
    return 0;
}

int CaptureSession::stop() {
    running_ = false;
    camera_.abort();
    if (videoThread_.joinable()) {
        videoThread_.join();
    }
    if (cameraThread_.joinable()) {
        cameraThread_.join();
    }
    if (loopbackThread_.joinable()) {
        loopbackThread_.join();
    }
    if (micThread_.joinable()) {
        micThread_.join();
    }
    camera_.close();
    return 0;
}

int CaptureSession::copyPreview(unsigned char* bgra, unsigned int maxBytes, unsigned int* width, unsigned int* height) {
    std::vector<std::uint8_t> screen;
    std::vector<std::uint8_t> camera;
    unsigned int screenW = 0;
    unsigned int screenH = 0;
    unsigned int camW = 0;
    unsigned int camH = 0;
    {
        std::lock_guard<std::mutex> lock(previewMu_);
        if (preview_.empty() || previewW_ == 0 || previewH_ == 0) {
            return 1;
        }
        screen = preview_;
        screenW = previewW_;
        screenH = previewH_;
        camera = cameraPreview_;
        camW = cameraPreviewW_;
        camH = cameraPreviewH_;
    }
    if (width) {
        *width = screenW;
    }
    if (height) {
        *height = screenH;
    }
    const size_t needed = static_cast<size_t>(screenW) * screenH * 4;
    if (!bgra || maxBytes < needed) {
        return 1;
    }
    if (previewCamera_ && !camera.empty() && camW >= 2 && camH >= 2) {
        composePipBGRA(
            screen.data(),
            screenW,
            screenH,
            camera.data(),
            camW,
            camH,
            bgra,
            maxBytes,
            pipX_,
            pipY_,
            pipW_,
            pipH_
        );
    } else {
        std::memcpy(bgra, screen.data(), needed);
    }
    if (width) {
        *width = screenW;
    }
    if (height) {
        *height = screenH;
    }
    return 0;
}

void CaptureSession::publishPreview(const std::vector<std::uint8_t>& bgra, unsigned int width, unsigned int height) {
    std::lock_guard<std::mutex> lock(previewMu_);
    preview_ = bgra;
    previewW_ = width;
    previewH_ = height;
}

void CaptureSession::publishCameraPreview(const std::vector<std::uint8_t>& bgra, unsigned int width, unsigned int height) {
    std::lock_guard<std::mutex> lock(previewMu_);
    cameraPreview_ = bgra;
    cameraPreviewW_ = width;
    cameraPreviewH_ = height;
}

bool CaptureSession::waitForVideoReady() {
    std::unique_lock<std::mutex> lock(readyMu_);
    while (running_.load() && !videoReady_) {
        readyCv_.wait_for(lock, std::chrono::milliseconds(50));
    }
    return running_.load() && videoReady_ && !FAILED(videoHr_);
}

void CaptureSession::videoMain(std::wstring directory, int monitorIndex, void* hwnd) {
    br::ComInit com;
    const long comHr = com.init(COINIT_MULTITHREADED);
    if (FAILED(comHr)) {
        br::setLastError("CoInitializeEx failed on the video thread", comHr);
        std::lock_guard<std::mutex> lock(readyMu_);
        videoReady_ = true;
        videoHr_ = comHr;
        readyCv_.notify_all();
        return;
    }
    br::RoInit ro;
    ro.init();
    DWORD mmcssIndex = 0;
    HANDLE mmcss = AvSetMmThreadCharacteristicsW(L"Capture", &mmcssIndex);

    WgcCapturer wgc;
    DesktopDuplicator dxgi;
    HWND window = static_cast<HWND>(hwnd);
    HRESULT hr = E_FAIL;
    bool useWgc = false;
    if (window) {
        hr = wgc.openWindow(window);
        useWgc = SUCCEEDED(hr);
    } else {
        hr = wgc.open(monitorIndex);
        useWgc = SUCCEEDED(hr);
        if (!useWgc) {
            hr = dxgi.open(monitorIndex);
        }
    }
    UINT width0 = 0;
    UINT height0 = 0;
    UINT areaPickerW = 0;
    UINT areaPickerH = 0;
    if (!window) {
        const std::vector<br::AttachedOutput> outputs = br::listAttachedOutputs();
        if (monitorIndex >= 0 && static_cast<size_t>(monitorIndex) < outputs.size()) {
            areaPickerW = outputs[static_cast<size_t>(monitorIndex)].width;
            areaPickerH = outputs[static_cast<size_t>(monitorIndex)].height;
        }
    }
    VideoSink sink;
    bool sinkOpen = false;

    auto signalVideo = [&](HRESULT value) {
        std::lock_guard<std::mutex> lock(readyMu_);
        if (videoReady_) {
            return;
        }
        videoReady_ = true;
        videoHr_ = value;
        readyCv_.notify_all();
    };

    if (FAILED(hr)) {
        signalVideo(hr);
        if (mmcss) {
            AvRevertMmThreadCharacteristics(mmcss);
        }
        return;
    }

    const std::int64_t frameDuration = 10'000'000 / 30;
    std::vector<std::uint8_t> bgra;
    std::vector<std::uint8_t> fitted;
    std::int64_t origin = 0;
    const ULONGLONG firstFrameDeadline = GetTickCount64() + 60000;
    const ULONGLONG silentGiveUp = GetTickCount64() + 3000;
    bool gotFrame = false;
    videoLooping_ = true;
    while (running_.load()) {
        UINT width = 0;
        UINT height = 0;
        if (useWgc) {
            hr = wgc.acquireBGRA(80, bgra, width, height);
            const bool wgcDead = FAILED(hr) && hr != S_FALSE;
            const bool wgcSilent = !gotFrame && (hr == S_FALSE || bgra.empty()) &&
                GetTickCount64() >= silentGiveUp;
            if (wgcDead || wgcSilent) {
                if (!window && SUCCEEDED(dxgi.open(monitorIndex))) {
                    wgc.close();
                    useWgc = false;
                    continue;
                }
                if (window && wgcSilent) {
                    br::setLastError("No window frames. Restore the window; DXGI cannot capture a single window.");
                } else if (wgcSilent) {
                    br::setLastError(
                        "No screen frames from Graphics Capture or Desktop Duplication. Allow Screen recording in Windows Settings > Privacy, and use an interactive desktop (not Session 0 / RDP service session)."
                    );
                }
                signalVideo(FAILED(hr) ? hr : HRESULT_FROM_WIN32(ERROR_TIMEOUT));
                running_ = false;
                break;
            }
        } else {
            hr = dxgi.acquireBGRA(80, bgra, width, height);
            if (hr == DXGI_ERROR_ACCESS_LOST || hr == DXGI_ERROR_INVALID_CALL) {
                dxgi.rebind();
                continue;
            }
            if (hr == DXGI_ERROR_ACCESS_DENIED || hr == DXGI_ERROR_UNSUPPORTED) {
                br::setLastError(
                    "Desktop Duplication access denied. Allow Screen recording in Windows Settings > Privacy, and use an interactive desktop (not Session 0 / RDP service session).",
                    hr
                );
                signalVideo(hr);
                running_ = false;
                break;
            }
            const bool dxgiSilent = !gotFrame && (hr == S_FALSE || bgra.empty()) &&
                GetTickCount64() >= silentGiveUp;
            if (dxgiSilent) {
                br::setLastError(
                    "No screen frames from Desktop Duplication. Allow Screen recording in Windows Settings > Privacy, and use an interactive desktop (not Session 0 / RDP service session)."
                );
                signalVideo(HRESULT_FROM_WIN32(ERROR_TIMEOUT));
                running_ = false;
                break;
            }
        }
        const bool timedOut = !gotFrame && GetTickCount64() >= firstFrameDeadline;
        if (hr == S_FALSE || FAILED(hr) || bgra.empty() || width < 2 || height < 2) {
            if (timedOut) {
                br::setLastError("No screen frame. Allow Screen recording in Windows Settings > Privacy.");
                signalVideo(HRESULT_FROM_WIN32(ERROR_TIMEOUT));
                break;
            }
            continue;
        }
        int cropX = 0;
        int cropY = 0;
        int cropW = 0;
        int cropH = 0;
        if (!window && cropW_ >= 16 && cropH_ >= 16) {
            const UINT srcW = areaPickerW >= 16 ? areaPickerW : width;
            const UINT srcH = areaPickerH >= 16 ? areaPickerH : height;
            cropX = static_cast<int>((static_cast<std::int64_t>(cropX_) * width + srcW / 2) / srcW) & ~1;
            cropY = static_cast<int>((static_cast<std::int64_t>(cropY_) * height + srcH / 2) / srcH) & ~1;
            cropW = static_cast<int>((static_cast<std::int64_t>(cropW_) * width + srcW / 2) / srcW) & ~1;
            cropH = static_cast<int>((static_cast<std::int64_t>(cropH_) * height + srcH / 2) / srcH) & ~1;
            if (cropX < 0) {
                cropX = 0;
            }
            if (cropY < 0) {
                cropY = 0;
            }
            if (cropX > static_cast<int>(width) - 16) {
                cropX = 0;
            }
            if (cropY > static_cast<int>(height) - 16) {
                cropY = 0;
            }
            cropW = (std::min)(cropW, static_cast<int>(width) - cropX) & ~1;
            cropH = (std::min)(cropH, static_cast<int>(height) - cropY) & ~1;
            if (cropW < 16 || cropH < 16) {
                cropX = 0;
                cropY = 0;
                cropW = 0;
                cropH = 0;
            }
        }
        const UINT outW = cropW >= 16 ? static_cast<UINT>(cropW) : width;
        const UINT outH = cropH >= 16 ? static_cast<UINT>(cropH) : height;
        if (!sinkOpen) {
            const HRESULT openHr = sink.open(br::joinPath(directory, L"screen.mp4"), outW, outH, 30);
            if (FAILED(openHr)) {
                signalVideo(openHr);
                break;
            }
            sinkOpen = true;
            width0 = outW;
            height0 = outH;
            origin = br::qpcHns();
        }
        const std::uint8_t* pixels = bgra.data();
        UINT stride = width * 4;
        if (cropW >= 16 && cropH >= 16) {
            fitted.assign(static_cast<size_t>(width0) * height0 * 4, 0);
            const int srcX = (std::min)(cropX, static_cast<int>(width) - 2) & ~1;
            const int srcY = (std::min)(cropY, static_cast<int>(height) - 2) & ~1;
            const UINT copyW = (std::min)(width0, width - static_cast<UINT>((std::max)(0, srcX)));
            const UINT copyH = (std::min)(height0, height - static_cast<UINT>((std::max)(0, srcY)));
            for (UINT y = 0; y < copyH; ++y) {
                std::memcpy(
                    fitted.data() + static_cast<size_t>(y) * width0 * 4,
                    bgra.data() + (static_cast<size_t>(srcY + static_cast<int>(y)) * width + static_cast<size_t>(srcX)) * 4,
                    static_cast<size_t>(copyW) * 4
                );
            }
            pixels = fitted.data();
            stride = width0 * 4;
            width = width0;
            height = height0;
        } else if (width != width0 || height != height0) {
            fitted.assign(static_cast<size_t>(width0) * height0 * 4, 0);
            const UINT copyW = (std::min)(width, width0);
            const UINT copyH = (std::min)(height, height0);
            for (UINT y = 0; y < copyH; ++y) {
                std::memcpy(
                    fitted.data() + static_cast<size_t>(y) * width0 * 4,
                    bgra.data() + static_cast<size_t>(y) * width * 4,
                    static_cast<size_t>(copyW) * 4
                );
            }
            pixels = fitted.data();
            stride = width0 * 4;
            width = width0;
            height = height0;
        }
        const std::int64_t now = br::qpcHns();
        const HRESULT writeHr = sink.writeBGRA(pixels, stride, now - origin, frameDuration);
        if (FAILED(writeHr)) {
            if (timedOut) {
                br::setLastError("H.264 screen write failed", writeHr);
                signalVideo(writeHr);
                break;
            }
            continue;
        }
        publishPreview(pixels == bgra.data() ? bgra : fitted, width, height);
        if (!gotFrame) {
            gotFrame = true;
            signalVideo(S_OK);
        }
    }
    if (!gotFrame) {
        signalVideo(HRESULT_FROM_WIN32(ERROR_CANCELLED));
    }
    if (sinkOpen) {
        sink.finalize();
    }
    videoLooping_ = false;
    if (mmcss) {
        AvRevertMmThreadCharacteristics(mmcss);
    }
}

void CaptureSession::cameraMain(std::wstring path) {
    br::ComInit com;
    const long comHr = com.init(COINIT_MULTITHREADED);
    HRESULT hr = static_cast<HRESULT>(comHr);
    VideoSink sink;
    bool sinkOpen = false;
    auto signal = [&](HRESULT value) {
        std::lock_guard<std::mutex> lock(readyMu_);
        if (cameraReady_) {
            return;
        }
        cameraReady_ = true;
        cameraHr_ = value;
        readyCv_.notify_all();
    };
    if (SUCCEEDED(hr)) {
        hr = camera_.open();
    }
    if (FAILED(hr)) {
        signal(hr);
        return;
    }
    if (!waitForVideoReady()) {
        signal(HRESULT_FROM_WIN32(ERROR_CANCELLED));
        return;
    }

    const std::int64_t frameDuration = 10'000'000 / 30;
    std::int64_t origin = 0;
    std::vector<std::uint8_t> bgra;
    while (running_.load()) {
        UINT width = 0;
        UINT height = 0;
        hr = camera_.readBGRA(bgra, width, height);
        if (hr == S_FALSE || FAILED(hr) || bgra.empty() || width < 2 || height < 2) {
            if (hr == static_cast<HRESULT>(0x80070005L)) {
                signal(hr);
                break;
            }
            Sleep(8);
            continue;
        }
        if (!sinkOpen) {
            hr = sink.open(path, width, height, 30);
            if (FAILED(hr)) {
                signal(hr);
                return;
            }
            sinkOpen = true;
            origin = br::qpcHns();
            signal(S_OK);
        }
        const std::int64_t now = br::qpcHns();
        sink.writeBGRA(bgra.data(), width * 4, now - origin, frameDuration);
        publishCameraPreview(bgra, width, height);
    }
    if (sinkOpen) {
        sink.finalize();
    }
}

void CaptureSession::audioMain(std::wstring path, bool loopback) {
    br::ComInit com;
    const long comHr = com.init(COINIT_MULTITHREADED);
    HRESULT hr = static_cast<HRESULT>(comHr);
    WasapiCapture capture;
    AudioSink sink;
    bool sinkOpen = false;
    if (SUCCEEDED(hr)) {
        hr = capture.open(loopback ? WasapiCapture::Kind::Loopback : WasapiCapture::Kind::Microphone);
    }
    if (SUCCEEDED(hr)) {
        hr = capture.start();
    }
    DWORD mmcssIndex = 0;
    HANDLE mmcss = AvSetMmThreadCharacteristicsW(L"Pro Audio", &mmcssIndex);
    auto signal = [&](HRESULT value) {
        std::lock_guard<std::mutex> lock(readyMu_);
        if (loopback) {
            if (loopbackReady_) {
                return;
            }
            loopbackReady_ = true;
            loopbackHr_ = value;
        } else {
            if (micReady_) {
                return;
            }
            micReady_ = true;
            micHr_ = value;
        }
        readyCv_.notify_all();
    };
    if (FAILED(hr)) {
        signal(hr);
        if (mmcss) {
            AvRevertMmThreadCharacteristics(mmcss);
        }
        return;
    }
    while (running_.load()) {
        {
            std::lock_guard<std::mutex> lock(readyMu_);
            if (videoReady_) {
                if (FAILED(videoHr_)) {
                    signal(HRESULT_FROM_WIN32(ERROR_CANCELLED));
                    if (mmcss) {
                        AvRevertMmThreadCharacteristics(mmcss);
                    }
                    return;
                }
                break;
            }
        }
        UINT32 drainFrames = 0;
        std::vector<std::int16_t> drain;
        capture.read(drain, drainFrames);
        Sleep(8);
    }
    if (!running_.load()) {
        signal(HRESULT_FROM_WIN32(ERROR_CANCELLED));
        if (mmcss) {
            AvRevertMmThreadCharacteristics(mmcss);
        }
        return;
    }
    const std::int64_t origin = br::qpcHns();
    std::vector<std::int16_t> pcm;
    bool gotPcm = false;
    while (running_.load()) {
        UINT32 frames = 0;
        const HRESULT readHr = capture.read(pcm, frames);
        if (FAILED(readHr)) {
            if (!gotPcm) {
                signal(readHr);
            }
            break;
        }
        if (frames > 0) {
            if (!sinkOpen) {
                hr = sink.open(path, WasapiCapture::kOutRate, WasapiCapture::kOutChannels);
                if (FAILED(hr)) {
                    signal(hr);
                    break;
                }
                sinkOpen = true;
            }
            const std::int64_t now = br::qpcHns();
            sink.writePCM16(pcm.data(), frames, now - origin);
            if (!gotPcm) {
                gotPcm = true;
                signal(S_OK);
            }
        } else {
            Sleep(8);
        }
    }
    if (!gotPcm) {
        if (!loopback) {
            br::setLastError("Microphone produced no samples. Allow Microphone in Windows Settings > Privacy.");
        }
        signal(HRESULT_FROM_WIN32(ERROR_NO_DATA));
    }
    capture.stop();
    if (sinkOpen) {
        sink.finalize();
    }
    if (mmcss) {
        AvRevertMmThreadCharacteristics(mmcss);
    }
}

#else
[[maybe_unused]] static int br_windows_capture_tu_session = 0;
#endif
