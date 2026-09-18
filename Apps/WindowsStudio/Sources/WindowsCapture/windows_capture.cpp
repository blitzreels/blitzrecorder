#include "windows_capture.h"

#include "capture_common.h"

#if defined(_WIN32)

#include "compose_export.h"
#include "mf_player.h"

#include <cstdio>
#include <windows.h>

#if !defined(BR_HAS_CAPTURE) || !BR_HAS_CAPTURE
int br_capture_start(const char*, int, int, int, int, void*, int, int, int, int) {
    br::setLastError("Capture adapter was not built into this binary");
    return 1;
}

int br_capture_stop(void) {
    return 0;
}

int br_capture_copy_preview(unsigned char*, unsigned int, unsigned int*, unsigned int*) {
    return 1;
}

int br_capture_alive(void) {
    return 0;
}
#endif

int br_export_composed_fixture(
    const char* output_dir,
    int canvas_width,
    int canvas_height,
    double camera_x,
    double camera_y,
    double camera_width,
    double camera_height,
    int frame_count,
    int fps
) {
    return exportComposedFixture(
        output_dir,
        canvas_width,
        canvas_height,
        camera_x,
        camera_y,
        camera_width,
        camera_height,
        frame_count,
        fps
    );
}

int br_compose_take(
    const char* screen_path,
    const char* camera_path,
    const char* export_path,
    double camera_x,
    double camera_y,
    double camera_width,
    double camera_height
) {
    return composeTakeFiles(
        screen_path,
        camera_path,
        export_path,
        camera_x,
        camera_y,
        camera_width,
        camera_height
    );
}

int br_player_open(const char* video_path, const br_kept_range* ranges, int range_count) {
    return playerOpen(video_path, ranges, range_count);
}

int br_player_open_take(
    const char* screen_path,
    const char* camera_path,
    const char* mic_path,
    const char* system_audio_path,
    const br_kept_range* ranges,
    int range_count,
    double camera_x,
    double camera_y,
    double camera_width,
    double camera_height
) {
    return playerOpenTake(
        screen_path,
        camera_path,
        mic_path,
        system_audio_path,
        ranges,
        range_count,
        camera_x,
        camera_y,
        camera_width,
        camera_height
    );
}

int br_player_tick(
    unsigned char* bgra,
    unsigned int max_bytes,
    unsigned int* width,
    unsigned int* height,
    int64_t* take_hns,
    int* ended
) {
    return playerTick(bgra, max_bytes, width, height, take_hns, ended);
}

int br_player_close(void) {
    return playerClose();
}

int br_player_set_paused(int paused) {
    return playerSetPaused(paused);
}

void br_attach_parent_console(void) {
    if (!AttachConsole(ATTACH_PARENT_PROCESS)) {
        const DWORD err = GetLastError();
        if (err == ERROR_ACCESS_DENIED) {
            // already has a console
        } else if (!AllocConsole()) {
            return;
        }
    }
    FILE* stream = nullptr;
    freopen_s(&stream, "CONOUT$", "w", stdout);
    freopen_s(&stream, "CONOUT$", "w", stderr);
    freopen_s(&stream, "CONIN$", "r", stdin);
    SetConsoleOutputCP(CP_UTF8);
}

#else

int br_capture_start(const char*, int, int, int, int, void*, int, int, int, int) {
    br::setLastError("Windows capture is only available on Windows");
    return 1;
}

int br_capture_stop(void) {
    return 0;
}

int br_capture_copy_preview(unsigned char*, unsigned int, unsigned int*, unsigned int*) {
    br::setLastError("Windows capture is only available on Windows");
    return 1;
}

int br_capture_alive(void) {
    return 0;
}

int br_export_composed_fixture(const char*, int, int, double, double, double, double, int, int) {
    br::setLastError("Windows compose export is only available on Windows");
    return 1;
}

int br_compose_take(const char*, const char*, const char*, double, double, double, double) {
    br::setLastError("Windows compose export is only available on Windows");
    return 1;
}

int br_player_open(const char*, const br_kept_range*, int) {
    br::setLastError("Windows playback is only available on Windows");
    return 1;
}

int br_player_open_take(
    const char*,
    const char*,
    const char*,
    const char*,
    const br_kept_range*,
    int,
    double,
    double,
    double,
    double
) {
    br::setLastError("Windows playback is only available on Windows");
    return 1;
}

int br_player_tick(unsigned char*, unsigned int, unsigned int*, unsigned int*, int64_t*, int*) {
    return 1;
}

int br_player_close(void) {
    return 0;
}

int br_player_set_paused(int) {
    return 0;
}

int br_studio_run(const char*, int, br_prepare_take_fn, void*) {
    br::setLastError("Windows studio window is only available on Windows");
    return 1;
}

void br_attach_parent_console(void) {}

#endif

const char* br_capture_last_error(void) {
    return br::lastErrorCStr();
}

void br_set_last_error(const char* message) {
    br::setLastError(message ? message : "");
}

const char* br_last_video_encoder(void) {
    return br::lastEncoderCStr();
}
