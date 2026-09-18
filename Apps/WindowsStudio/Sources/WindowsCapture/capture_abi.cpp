#if defined(_WIN32)

#include "windows_capture.h"
#include "capture_common.h"
#include "capture_session.h"

#include <memory>
#include <mutex>
#include <string>

namespace {

std::mutex gSessionMu;
std::unique_ptr<CaptureSession> gSession;
std::string gTakeDir;
bool gStarting = false;
bool gWantMic = false;

}  // namespace

int br_capture_start(
    const char* output_dir,
    int monitor_index,
    int include_system_audio,
    int include_mic,
    int include_camera,
    void* hwnd,
    int crop_x,
    int crop_y,
    int crop_width,
    int crop_height
) {
    {
        std::lock_guard<std::mutex> lock(gSessionMu);
        if (gSession || gStarting) {
            br::setLastError("Capture is already running");
            return 1;
        }
        gStarting = true;
    }
    struct StartingGuard {
        ~StartingGuard() {
            std::lock_guard<std::mutex> lock(gSessionMu);
            gStarting = false;
        }
    } startingGuard;

    auto session = std::make_unique<CaptureSession>();
    const int rc = session->start(
        output_dir,
        monitor_index,
        include_system_audio != 0,
        include_mic != 0,
        include_camera != 0,
        hwnd,
        crop_x,
        crop_y,
        crop_width,
        crop_height
    );
    if (rc != 0) {
        br::removeTakeDirectory(output_dir);
        return rc;
    }
    std::lock_guard<std::mutex> lock(gSessionMu);
    gSession = std::move(session);
    gTakeDir = output_dir ? output_dir : "";
    gWantMic = include_mic != 0;
    return 0;
}

int br_capture_stop(void) {
    std::unique_ptr<CaptureSession> session;
    std::string takeDir;
    bool wantMic = false;
    {
        std::lock_guard<std::mutex> lock(gSessionMu);
        session = std::move(gSession);
        takeDir = std::move(gTakeDir);
        wantMic = gWantMic;
        gWantMic = false;
    }
    int rc = 0;
    if (session) {
        rc = session->stop();
    } else {
        br::setLastError("");
    }
    if (!takeDir.empty()) {
        const std::string screen = br::joinUtf8Path(takeDir, "screen.mp4");
        const std::string mic = br::joinUtf8Path(takeDir, "audio.m4a");
        const std::int64_t screenBytes = br::fileSizeUtf8(screen.c_str());
        const std::int64_t micBytes = br::fileSizeUtf8(mic.c_str());
        br::syncTakeSidecarsFromDisk(takeDir.c_str());
        if (screenBytes < 4096) {
            br::setLastError("Take is missing screen.mp4. Allow Screen recording in Windows Settings > Privacy.");
            br::openSettingsUri(L"ms-settings:privacy-graphicscapture");
            return 1;
        }
        if (wantMic && micBytes < 256) {
            br::setLastError("Take is missing microphone audio. Allow Microphone in Windows Settings > Privacy.");
            br::openSettingsUri(L"ms-settings:privacy-microphone");
            return 1;
        }
    }
    return rc;
}

int br_capture_copy_preview(
    unsigned char* bgra,
    unsigned int max_bytes,
    unsigned int* width,
    unsigned int* height
) {
    std::lock_guard<std::mutex> lock(gSessionMu);
    if (!gSession) {
        return 1;
    }
    return gSession->copyPreview(bgra, max_bytes, width, height);
}

int br_capture_alive(void) {
    std::lock_guard<std::mutex> lock(gSessionMu);
    return gSession && gSession->videoLooping() ? 1 : 0;
}

#else
[[maybe_unused]] static int br_windows_capture_tu_capture_abi = 0;
#endif
