#pragma once

#if defined(_WIN32)

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
);

int composeTakeFiles(
    const char* screenPath,
    const char* cameraPath,
    const char* exportPath,
    double cameraX,
    double cameraY,
    double cameraWidth,
    double cameraHeight
);

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
);

#endif
