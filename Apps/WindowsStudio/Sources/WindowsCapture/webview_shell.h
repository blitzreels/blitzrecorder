#pragma once

#if defined(_WIN32)
int runWebViewStudio(const char* outputRoot, int monitorIndex, int (*prepare)(const char*, int, int, int, char*, int, void*), void* ctx);
#endif
