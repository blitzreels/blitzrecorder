#pragma once

#if defined(_WIN32)

#include "windows_capture.h"

int playerOpen(const char* videoPath, const br_kept_range* ranges, int rangeCount);
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
);
int playerTick(
    unsigned char* bgra,
    unsigned int maxBytes,
    unsigned int* width,
    unsigned int* height,
    int64_t* takeHns,
    int* ended
);
int playerClose();
int playerSetPaused(int paused);

#endif
