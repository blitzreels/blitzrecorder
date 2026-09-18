#pragma once

#if defined(_WIN32)

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "mf_camera.h"

class CaptureSession {
public:
    CaptureSession() = default;
    CaptureSession(const CaptureSession&) = delete;
    CaptureSession& operator=(const CaptureSession&) = delete;
    ~CaptureSession() { stop(); }

    int start(
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
    );
    int stop();
    int copyPreview(unsigned char* bgra, unsigned int maxBytes, unsigned int* width, unsigned int* height);
    bool videoLooping() const { return videoLooping_.load(); }

private:
    void videoMain(std::wstring directory, int monitorIndex, void* hwnd);
    void cameraMain(std::wstring path);
    void audioMain(std::wstring path, bool loopback);
    void publishPreview(const std::vector<std::uint8_t>& bgra, unsigned int width, unsigned int height);
    void publishCameraPreview(const std::vector<std::uint8_t>& bgra, unsigned int width, unsigned int height);
    bool waitForVideoReady();

    std::atomic<bool> running_{false};
    std::atomic<bool> videoLooping_{false};
    std::thread videoThread_;
    std::thread cameraThread_;
    std::thread loopbackThread_;
    std::thread micThread_;

    std::mutex readyMu_;
    std::condition_variable readyCv_;
    bool videoReady_ = false;
    long videoHr_ = static_cast<long>(0x80004005L);
    bool cameraReady_ = true;
    long cameraHr_ = 0;
    bool loopbackReady_ = true;
    long loopbackHr_ = 0;
    bool micReady_ = true;
    long micHr_ = 0;

    std::mutex previewMu_;
    std::vector<std::uint8_t> preview_;
    unsigned int previewW_ = 0;
    unsigned int previewH_ = 0;
    std::vector<std::uint8_t> cameraPreview_;
    unsigned int cameraPreviewW_ = 0;
    unsigned int cameraPreviewH_ = 0;
    bool previewCamera_ = false;
    std::string takeDir_;
    double pipX_ = 0.68;
    double pipY_ = 0.68;
    double pipW_ = 0.28;
    double pipH_ = 0.28;
    int cropX_ = 0;
    int cropY_ = 0;
    int cropW_ = 0;
    int cropH_ = 0;

    CameraReader camera_;
};

#endif
