#pragma once

#if defined(_WIN32)
struct WebViewStudioOptions {
    const char* outputRoot;
    int monitorIndex;
    int (*prepare)(const char*, int, int, int, char*, int, void*);
    void* context;
};
int runWebViewStudio(WebViewStudioOptions options);
#endif
