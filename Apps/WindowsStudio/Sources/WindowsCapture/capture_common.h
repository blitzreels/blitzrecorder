#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "windows_capture.h"

namespace br {

void setLastError(const std::string& message);
void setLastError(const std::string& message, long hr);
const char* lastErrorCStr();
void setLastEncoder(const std::string& name);
const char* lastEncoderCStr();

#if defined(_WIN32)

std::wstring utf8ToWide(const char* utf8);
std::wstring utf8ToWide(const std::string& utf8);
std::string wideToUtf8(const wchar_t* wide);
std::string hrToString(long hr);
std::wstring joinPath(const std::wstring& directory, const wchar_t* fileName);
std::string joinUtf8Path(const std::string& directory, const char* fileName);
bool fileExistsUtf8(const char* path);
std::int64_t fileSizeUtf8(const char* path);
std::int64_t qpcHns();
void hideOwnConsole();
long ensureCom();
void readCameraPip(const char* takeDir, double& x, double& y, double& width, double& height);
void readKeptRangesHNS(const char* takeDir, std::vector<br_kept_range>& out);
bool writeTakeSidecars(const char* takeDir, bool microphone, bool systemAudio, bool camera);
bool syncTakeSidecarsFromDisk(const char* takeDir);
void removeTakeDirectory(const char* takeDir);
void openSettingsUri(const wchar_t* uri);
bool isConsentDenied(long hr);
long primeMicrophoneConsent();
long primeGraphicsCaptureConsent(int monitorIndex, void* hwnd);
void excludeWindowFromCapture(void* hwnd);
void setAppUserModelId();
void letterboxDest(int dstW, int dstH, unsigned srcW, unsigned srcH, int& x, int& y, int& w, int& h);
long defaultAudioDevice(void* enumerator, int render, void** device);
long openMfSourceReader(const wchar_t* path, void* attributes, void** reader);
long openMfSinkWriter(const wchar_t* path, void* attributes, void** writer);
int openTakePlayback(const char* takeDir);
bool resolveTakeDirectory(const char* picked, std::string& takeDir);

class RoInit {
public:
    RoInit() = default;
    RoInit(const RoInit&) = delete;
    RoInit& operator=(const RoInit&) = delete;
    ~RoInit();
    long init();

private:
    bool shouldUninit_ = false;
};

class ComInit {
public:
    ComInit() = default;
    ComInit(const ComInit&) = delete;
    ComInit& operator=(const ComInit&) = delete;
    ~ComInit();

    long init(unsigned long coinit);
    bool ok() const { return initialized_; }

private:
    bool initialized_ = false;
    bool shouldUninit_ = false;
};

#endif

}  // namespace br
