#ifndef BLITZRECORDER_WINDOWS_CAPTURE_H
#define BLITZRECORDER_WINDOWS_CAPTURE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct br_kept_range {
    int64_t take_start_hns;
    int64_t take_end_hns;
} br_kept_range;

/* Create take directory sidecars in Swift, then start capture into that folder.
 *
 * Writes:
 *   screen.mp4           H.264 WGC monitor or window (DXGI fallback for monitors only)
 *   camera.mp4           H.264 MF webcam, when include_camera is non-zero
 *   audio.m4a            AAC microphone, when include_mic is non-zero
 *   system-audio.m4a     AAC WASAPI loopback, when include_system_audio is non-zero
 *
 * monitor_index: 0 is the primary attached output (ignored when hwnd is set).
 * hwnd: optional top-level HWND for WGC CreateForWindow. Null = full display
 * (WGC, DXGI fallback). Window capture has no DXGI fallback.
 * crop_*: monitor-local area crop in pixels. crop_width < 2 means full frame.
 * Returns 0 on success.
 */
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
);

int br_capture_stop(void);

/* 1 while the screen capture thread is still writing frames. */
int br_capture_alive(void);

/* Tight top-down BGRA of the latest screen frame. Returns 0 if a frame was copied. */
int br_capture_copy_preview(
    unsigned char* bgra,
    unsigned int max_bytes,
    unsigned int* width,
    unsigned int* height
);

const char* br_capture_last_error(void);
void br_set_last_error(const char* message);

/* Synthetic parallel take + D3D11 compose (WARP fallback) + MF H.264/AAC.
 * Writes screen.mp4, camera.mp4, audio.m4a, export.mp4 under output_dir.
 */
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
);

/* Decode screen.mp4 (+ optional camera.mp4) and write composed export.mp4. */
int br_compose_take(
    const char* screen_path,
    const char* camera_path,
    const char* export_path,
    double camera_x,
    double camera_y,
    double camera_width,
    double camera_height
);

int br_player_open(const char* video_path, const br_kept_range* ranges, int range_count);
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
);
int br_player_tick(
    unsigned char* bgra,
    unsigned int max_bytes,
    unsigned int* width,
    unsigned int* height,
    int64_t* take_hns,
    int* ended
);
int br_player_close(void);
int br_player_set_paused(int paused);

/* Last H.264 encoder used by VideoSink: NVENC / AMF / QSV / MF hardware / Microsoft software. */
const char* br_last_video_encoder(void);

typedef int (*br_prepare_take_fn)(
    const char* output_root,
    int mic,
    int system_audio,
    int camera,
    char* out_dir,
    int out_dir_cap,
    void* ctx
);

/* Blocking Win32 studio window. Returns 0 after WM_QUIT, non-zero if the window could not be created. */
int br_studio_run(
    const char* output_root,
    int monitor_index,
    br_prepare_take_fn prepare,
    void* ctx
);

/* Attach stdout/stderr to the parent console for CLI (--play / --export / --help). */
void br_attach_parent_console(void);

#ifdef __cplusplus
}
#endif

#endif
