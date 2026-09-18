#pragma once

#include <string>

#if defined(_WIN32)

/* IFileOpenDialog folder picker. ownerHwnd is HWND; startDir may be null. */
bool pickTakeDirectory(void* ownerHwnd, std::string& outUtf8, const char* startDir);
/* Drag-rect overlay on monitor_index. Returns monitor-local even crop. Esc cancels. */
bool pickCaptureArea(void* ownerHwnd, int monitorIndex, int& x, int& y, int& width, int& height);

#endif
