#pragma once

#if defined(_WIN32)

int runStudioWindow(
    const char* outputRoot,
    int monitorIndex,
    int (*prepare)(const char*, int, int, int, char*, int, void*),
    void* ctx
);

#endif
