#if !defined(_WIN32)

int main() {
    return 1;
}

#else

#include "windows_capture.h"
#include "capture_common.h"

#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>

#include <windows.h>
#include <objbase.h>

namespace {

std::string joinUtf8(const char* directory, const char* name) {
    std::string path = directory ? directory : "";
    if (!path.empty() && path.back() != '\\' && path.back() != '/') {
        path += '\\';
    }
    path += name;
    return path;
}

int fail(const char* prefix) {
    std::fprintf(stderr, "%s: %s\n", prefix, br_capture_last_error());
    return 1;
}

}  // namespace

int main(int argc, char** argv) {
    if (argc < 2 || !argv[1] || !argv[1][0]) {
        std::fprintf(stderr, "usage: BlitzRecorderFixture OUTPUT_DIR\n");
        return 1;
    }
    const char* directory = argv[1];
    CreateDirectoryW(br::utf8ToWide(directory).c_str(), nullptr);
    CoInitializeEx(nullptr, COINIT_MULTITHREADED);

    const int exported = br_export_composed_fixture(
        directory,
        1280,
        720,
        0.68,
        0.68,
        0.28,
        0.28,
        90,
        30
    );
    if (exported != 0) {
        return fail("fixture export failed");
    }
    std::printf("exported fixture %s encoder=%s\n", directory, br_last_video_encoder());

    const std::string screen = joinUtf8(directory, "screen.mp4");
    const std::string camera = joinUtf8(directory, "camera.mp4");
    const std::string mic = joinUtf8(directory, "audio.m4a");
    const std::string composed = joinUtf8(directory, "export.mp4");
    if (br_compose_take(screen.c_str(), camera.c_str(), composed.c_str(), 0.68, 0.68, 0.28, 0.28) != 0) {
        return fail("take compose failed");
    }

    if (br_player_open_take(
            screen.c_str(),
            camera.c_str(),
            mic.c_str(),
            "",
            nullptr,
            0,
            0.68,
            0.68,
            0.28,
            0.28
        )
        != 0) {
        return fail("fixture playback failed");
    }

    std::vector<unsigned char> pixels(static_cast<size_t>(7680) * 4320 * 4);
    int frames = 0;
    int ended = 0;
    int ticks = 0;
    unsigned int width = 0;
    unsigned int height = 0;
    int64_t takeHns = 0;
    while (ended == 0 && ticks < 500) {
        const int code = br_player_tick(
            pixels.data(),
            static_cast<unsigned int>(pixels.size()),
            &width,
            &height,
            &takeHns,
            &ended
        );
        ++ticks;
        if (code != 0) {
            break;
        }
        ++frames;
    }
    br_player_close();
    if (frames <= 0) {
        std::fprintf(stderr, "fixture playback decoded 0 frames\n");
        return 1;
    }
    std::printf("decoded %d parallel frames from %s\n", frames, directory);
    return 0;
}

#endif
