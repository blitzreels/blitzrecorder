#include "capture_common.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <objbase.h>
#include <roapi.h>
#include <shellapi.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <wrl/client.h>

extern "C" HRESULT WINAPI SetCurrentProcessExplicitAppUserModelID(const wchar_t* appId);
#endif

namespace br {
namespace {

std::mutex gErrorMu;
char gErrorBuf[2048] = {0};
char gEncoderBuf[512] = "Microsoft software H.264";

void storeError(const std::string& text) {
    std::lock_guard<std::mutex> lock(gErrorMu);
    std::snprintf(gErrorBuf, sizeof(gErrorBuf), "%s", text.c_str());
}

}  // namespace

void setLastEncoder(const std::string& name) {
    std::lock_guard<std::mutex> lock(gErrorMu);
    if (name.empty()) {
        std::snprintf(gEncoderBuf, sizeof(gEncoderBuf), "%s", "Microsoft software H.264");
        return;
    }
    std::snprintf(gEncoderBuf, sizeof(gEncoderBuf), "%s", name.c_str());
}

const char* lastEncoderCStr() {
    return gEncoderBuf;
}

void setLastError(const std::string& message) {
    storeError(message);
}

void setLastError(const std::string& message, long hr) {
#if defined(_WIN32)
    std::string text = message;
    text += " (";
    text += hrToString(hr);
    text += ")";
    storeError(text);
#else
    (void)hr;
    storeError(message);
#endif
}

const char* lastErrorCStr() {
    return gErrorBuf;
}

#if defined(_WIN32)

std::wstring utf8ToWide(const char* utf8) {
    if (!utf8 || !utf8[0]) {
        return {};
    }
    const int needed = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, nullptr, 0);
    if (needed <= 1) {
        return {};
    }
    std::wstring wide(static_cast<size_t>(needed - 1), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, utf8, -1, wide.data(), needed);
    // Swift Foundation URL.path on Windows is often "/C:/Users/..." which
    // CreateFileW / MFCreateSinkWriterFromURL will not open.
    if (wide.size() >= 3 && wide[0] == L'/' && wide[2] == L':'
        && ((wide[1] >= L'A' && wide[1] <= L'Z') || (wide[1] >= L'a' && wide[1] <= L'z'))) {
        wide.erase(0, 1);
    }
    for (wchar_t& ch : wide) {
        if (ch == L'/') {
            ch = L'\\';
        }
    }
    return wide;
}

std::wstring utf8ToWide(const std::string& utf8) {
    return utf8ToWide(utf8.c_str());
}

bool fileExistsUtf8(const char* path) {
    const std::wstring wide = utf8ToWide(path);
    if (wide.empty()) {
        return false;
    }
    WIN32_FILE_ATTRIBUTE_DATA data{};
    if (!GetFileAttributesExW(wide.c_str(), GetFileExInfoStandard, &data)) {
        return false;
    }
    if (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
        return false;
    }
    ULARGE_INTEGER size{};
    size.HighPart = data.nFileSizeHigh;
    size.LowPart = data.nFileSizeLow;
    return size.QuadPart >= 16;
}

std::int64_t fileSizeUtf8(const char* path) {
    const std::wstring wide = utf8ToWide(path);
    if (wide.empty()) {
        return -1;
    }
    WIN32_FILE_ATTRIBUTE_DATA data{};
    if (!GetFileAttributesExW(wide.c_str(), GetFileExInfoStandard, &data)) {
        return -1;
    }
    if (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
        return -1;
    }
    ULARGE_INTEGER size{};
    size.HighPart = data.nFileSizeHigh;
    size.LowPart = data.nFileSizeLow;
    return static_cast<std::int64_t>(size.QuadPart);
}

bool writeUtf8File(const char* path, const std::string& body) {
    const std::wstring wide = utf8ToWide(path);
    if (wide.empty()) {
        setLastError("take sidecar path is empty");
        return false;
    }
    HANDLE file = CreateFileW(
        wide.c_str(),
        GENERIC_WRITE,
        0,
        nullptr,
        CREATE_ALWAYS,
        FILE_ATTRIBUTE_NORMAL,
        nullptr
    );
    if (file == INVALID_HANDLE_VALUE) {
        setLastError("could not write take sidecar", static_cast<long>(GetLastError()));
        return false;
    }
    DWORD written = 0;
    const BOOL ok = WriteFile(
        file,
        body.data(),
        static_cast<DWORD>(body.size()),
        &written,
        nullptr
    );
    CloseHandle(file);
    if (!ok || written != body.size()) {
        setLastError("could not write take sidecar");
        return false;
    }
    return true;
}

std::string newTakeId() {
    GUID guid{};
    if (FAILED(CoCreateGuid(&guid))) {
        return "00000000-0000-4000-8000-000000000001";
    }
    char id[40];
    std::snprintf(
        id,
        sizeof(id),
        "%08X-%04X-%04X-%02X%02X-%02X%02X%02X%02X%02X%02X",
        guid.Data1,
        guid.Data2,
        guid.Data3,
        guid.Data4[0],
        guid.Data4[1],
        guid.Data4[2],
        guid.Data4[3],
        guid.Data4[4],
        guid.Data4[5],
        guid.Data4[6],
        guid.Data4[7]
    );
    return id;
}

std::string utcNowIso8601() {
    SYSTEMTIME st{};
    GetSystemTime(&st);
    char stamp[40];
    std::snprintf(
        stamp,
        sizeof(stamp),
        "%04u-%02u-%02uT%02u:%02u:%02uZ",
        st.wYear,
        st.wMonth,
        st.wDay,
        st.wHour,
        st.wMinute,
        st.wSecond
    );
    return stamp;
}

std::string readUtf8File(const char* takeDir, const char* name);

static bool extractBalanced(const std::string& json, size_t open, char closer, std::string& out) {
    if (open >= json.size()) {
        return false;
    }
    const char opener = json[open];
    int depth = 0;
    for (size_t i = open; i < json.size(); ++i) {
        if (json[i] == opener) {
            ++depth;
        } else if (json[i] == closer) {
            --depth;
            if (depth == 0) {
                out.assign(json, open, i - open + 1);
                return true;
            }
        }
    }
    return false;
}

static bool extractCutsArray(const std::string& json, std::string& out) {
    const size_t key = json.find("\"cuts\"");
    if (key == std::string::npos) {
        return false;
    }
    const size_t arr = json.find('[', key);
    if (arr == std::string::npos) {
        return false;
    }
    return extractBalanced(json, arr, ']', out);
}

static bool extractDomainScene(const std::string& json, std::string& out) {
    size_t pos = 0;
    while (true) {
        pos = json.find("\"scene\"", pos);
        if (pos == std::string::npos) {
            return false;
        }
        if (json.compare(pos, 13, "\"sceneEvents\"") == 0) {
            pos += 13;
            continue;
        }
        const size_t brace = json.find('{', pos + 7);
        if (brace == std::string::npos) {
            return false;
        }
        std::string object;
        if (!extractBalanced(json, brace, '}', object)) {
            return false;
        }
        if (object.find("\"canvasWidth\"") != std::string::npos
            || object.find("\"screen\"") != std::string::npos) {
            out = std::move(object);
            return true;
        }
        pos = brace + 1;
    }
}

static bool writeProjectSidecar(const char* takeDir, bool microphone, bool systemAudio, bool camera) {
    std::string sources = "    {\n      \"path\" : \"screen.mp4\",\n      \"role\" : \"screen\"\n    }";
    if (camera) {
        sources += ",\n    {\n      \"path\" : \"camera.mp4\",\n      \"role\" : \"camera\"\n    }";
    }
    if (microphone) {
        sources += ",\n    {\n      \"path\" : \"audio.m4a\",\n      \"role\" : \"microphone\"\n    }";
    }
    if (systemAudio) {
        sources += ",\n    {\n      \"path\" : \"system-audio.m4a\",\n      \"role\" : \"systemAudio\"\n    }";
    }
    std::string cuts = "[\n\n  ]";
    std::string scene =
        "{\n    \"canvasHeight\" : 1080,\n    \"canvasWidth\" : 1920,\n    \"screen\" : {\n      \"height\" : 1,\n      \"width\" : 1,\n      \"x\" : 0,\n      \"y\" : 0\n    }\n  }";
    if (camera) {
        scene =
            "{\n    \"camera\" : {\n      \"height\" : 0.28,\n      \"width\" : 0.28,\n      \"x\" : 0.68,\n      \"y\" : 0.68\n    },\n    \"canvasHeight\" : 1080,\n    \"canvasWidth\" : 1920,\n    \"screen\" : {\n      \"height\" : 1,\n      \"width\" : 1,\n      \"x\" : 0,\n      \"y\" : 0\n    }\n  }";
    }
    const std::string existing = readUtf8File(takeDir, "project.blitzrecorder.json");
    if (!existing.empty()) {
        extractCutsArray(existing, cuts);
        extractDomainScene(existing, scene);
    }
    std::string project = "{\n  \"cuts\" : ";
    project += cuts;
    project += ",\n  \"scene\" : ";
    project += scene;
    project += ",\n  \"sources\" : [\n";
    project += sources;
    project += "\n  ],\n  \"version\" : 1\n}\n";
    return writeUtf8File(joinUtf8Path(takeDir, "project.blitzrecorder.json").c_str(), project);
}

bool writeTakeSidecars(const char* takeDir, bool microphone, bool systemAudio, bool camera) {
    if (!takeDir || !takeDir[0]) {
        setLastError("take folder is empty");
        return false;
    }
    std::string manifest = "{\n  \"createdAt\" : \"";
    manifest += utcNowIso8601();
    manifest += "\",\n  \"id\" : \"";
    manifest += newTakeId();
    manifest += "\"\n}\n";
    if (!writeUtf8File(joinUtf8Path(takeDir, "take.json").c_str(), manifest)) {
        return false;
    }
    return writeProjectSidecar(takeDir, microphone, systemAudio, camera);
}

bool syncTakeSidecarsFromDisk(const char* takeDir) {
    if (!takeDir || !takeDir[0]) {
        return false;
    }
    const bool microphone = fileExistsUtf8(joinUtf8Path(takeDir, "audio.m4a").c_str());
    const bool systemAudio = fileExistsUtf8(joinUtf8Path(takeDir, "system-audio.m4a").c_str());
    const bool camera = fileExistsUtf8(joinUtf8Path(takeDir, "camera.mp4").c_str());
    if (!fileExistsUtf8(joinUtf8Path(takeDir, "take.json").c_str())) {
        return writeTakeSidecars(takeDir, microphone, systemAudio, camera);
    }
    return writeProjectSidecar(takeDir, microphone, systemAudio, camera);
}

void removeTakeDirectory(const char* takeDir) {
    if (!takeDir || !takeDir[0]) {
        return;
    }
    const std::wstring root = utf8ToWide(takeDir);
    if (root.empty()) {
        return;
    }
    const wchar_t* names[] = {
        L"screen.mp4",
        L"camera.mp4",
        L"audio.m4a",
        L"system-audio.m4a",
        L"export.mp4",
        L"take.json",
        L"project.blitzrecorder.json"
    };
    for (const wchar_t* name : names) {
        DeleteFileW(joinPath(root, name).c_str());
    }
    RemoveDirectoryW(root.c_str());
}

void openSettingsUri(const wchar_t* uri) {
    if (!uri || !uri[0]) {
        return;
    }
    ShellExecuteW(nullptr, L"open", uri, nullptr, nullptr, SW_SHOWNORMAL);
}

bool isConsentDenied(long hr) {
    const HRESULT h = static_cast<HRESULT>(hr);
    return h == E_ACCESSDENIED || h == HRESULT_FROM_WIN32(ERROR_CANCELLED);
}

long primeMicrophoneConsent() {
    Microsoft::WRL::ComPtr<IMMDeviceEnumerator> enumerator;
    HRESULT hr = CoCreateInstance(
        __uuidof(MMDeviceEnumerator),
        nullptr,
        CLSCTX_ALL,
        IID_PPV_ARGS(&enumerator)
    );
    if (FAILED(hr)) {
        return static_cast<long>(hr);
    }
    IMMDevice* raw = nullptr;
    hr = static_cast<HRESULT>(defaultAudioDevice(enumerator.Get(), 0, reinterpret_cast<void**>(&raw)));
    Microsoft::WRL::ComPtr<IMMDevice> device;
    if (raw) {
        device.Attach(raw);
    }
    if (FAILED(hr) || !device) {
        return FAILED(hr) ? static_cast<long>(hr) : static_cast<long>(E_FAIL);
    }
    Microsoft::WRL::ComPtr<IAudioClient> client;
    hr = device->Activate(
        __uuidof(IAudioClient),
        CLSCTX_ALL,
        nullptr,
        reinterpret_cast<void**>(client.ReleaseAndGetAddressOf())
    );
    if (FAILED(hr)) {
        return static_cast<long>(hr);
    }
    WAVEFORMATEX* mix = nullptr;
    hr = client->GetMixFormat(&mix);
    if (FAILED(hr) || !mix) {
        return FAILED(hr) ? static_cast<long>(hr) : static_cast<long>(E_POINTER);
    }
    hr = client->Initialize(
        AUDCLNT_SHAREMODE_SHARED,
        AUDCLNT_STREAMFLAGS_NOPERSIST,
        200000,
        0,
        mix,
        nullptr
    );
    CoTaskMemFree(mix);
    if (hr == AUDCLNT_E_ALREADY_INITIALIZED) {
        return 0;
    }
    if (FAILED(hr)) {
        return static_cast<long>(hr);
    }
    if (SUCCEEDED(client->Start())) {
        Sleep(30);
        client->Stop();
    }
    return 0;
}

void excludeWindowFromCapture(void* hwnd) {
    HWND window = static_cast<HWND>(hwnd);
    if (!window) {
        return;
    }
    wchar_t screenshotMode[2]{};
    if (GetEnvironmentVariableW(L"BLITZRECORDER_STORE_SCREENSHOT", screenshotMode, 2) == 1 && screenshotMode[0] == L'1') {
        return;
    }
#ifndef WDA_EXCLUDEFROMCAPTURE
#define WDA_EXCLUDEFROMCAPTURE 0x00000011
#endif
    SetWindowDisplayAffinity(window, WDA_EXCLUDEFROMCAPTURE);
}

long defaultAudioDevice(void* enumerator, int render, void** device) {
    if (!enumerator || !device) {
        return E_POINTER;
    }
    *device = nullptr;
    auto* devices = static_cast<IMMDeviceEnumerator*>(enumerator);
    const EDataFlow flow = render ? eRender : eCapture;
    const ERole roles[] = { eConsole, eMultimedia, eCommunications };
    HRESULT hr = E_FAIL;
    for (ERole role : roles) {
        IMMDevice* got = nullptr;
        hr = devices->GetDefaultAudioEndpoint(flow, role, &got);
        if (SUCCEEDED(hr) && got) {
            *device = got;
            return S_OK;
        }
        if (got) {
            got->Release();
        }
    }
    return FAILED(hr) ? static_cast<long>(hr) : static_cast<long>(E_FAIL);
}

long openMfSourceReader(const wchar_t* path, void* attributes, void** reader) {
    if (!path || !path[0] || !reader) {
        return E_POINTER;
    }
    *reader = nullptr;
    Microsoft::WRL::ComPtr<IMFByteStream> stream;
    HRESULT hr = MFCreateFile(
        MF_ACCESSMODE_READ,
        MF_OPENMODE_FAIL_IF_NOT_EXIST,
        MF_FILEFLAGS_NONE,
        path,
        stream.ReleaseAndGetAddressOf()
    );
    if (FAILED(hr) || !stream) {
        setLastError("MFCreateFile failed", hr);
        return FAILED(hr) ? static_cast<long>(hr) : static_cast<long>(E_FAIL);
    }
    IMFSourceReader* local = nullptr;
    hr = MFCreateSourceReaderFromByteStream(
        stream.Get(),
        static_cast<IMFAttributes*>(attributes),
        &local
    );
    if (FAILED(hr) || !local) {
        setLastError("MFCreateSourceReaderFromByteStream failed", hr);
        return FAILED(hr) ? static_cast<long>(hr) : static_cast<long>(E_FAIL);
    }
    *reader = local;
    return S_OK;
}

long openMfSinkWriter(const wchar_t* path, void* attributes, void** writer) {
    if (!path || !path[0] || !writer) {
        return E_POINTER;
    }
    *writer = nullptr;
    auto* attrs = static_cast<IMFAttributes*>(attributes);
    Microsoft::WRL::ComPtr<IMFByteStream> stream;
    HRESULT hr = MFCreateFile(
        MF_ACCESSMODE_READWRITE,
        MF_OPENMODE_DELETE_IF_EXIST,
        MF_FILEFLAGS_NONE,
        path,
        stream.ReleaseAndGetAddressOf()
    );
    IMFSinkWriter* local = nullptr;
    if (SUCCEEDED(hr) && stream) {
        hr = MFCreateSinkWriterFromURL(path, stream.Get(), attrs, &local);
        if (SUCCEEDED(hr) && local) {
            *writer = local;
            return S_OK;
        }
        if (local) {
            local->Release();
            local = nullptr;
        }
        stream.Reset();
    }
    hr = MFCreateSinkWriterFromURL(path, nullptr, attrs, &local);
    if (FAILED(hr) || !local) {
        setLastError("MFCreateSinkWriterFromURL failed", hr);
        return FAILED(hr) ? static_cast<long>(hr) : static_cast<long>(E_FAIL);
    }
    *writer = local;
    return S_OK;
}

std::string wideToUtf8(const wchar_t* wide) {
    if (!wide || !wide[0]) {
        return {};
    }
    const int needed = WideCharToMultiByte(CP_UTF8, 0, wide, -1, nullptr, 0, nullptr, nullptr);
    if (needed <= 1) {
        return {};
    }
    std::string utf8(static_cast<size_t>(needed - 1), '\0');
    WideCharToMultiByte(CP_UTF8, 0, wide, -1, utf8.data(), needed, nullptr, nullptr);
    return utf8;
}

std::string hrToString(long hr) {
    wchar_t* buffer = nullptr;
    const DWORD flags = FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS;
    const DWORD n = FormatMessageW(
        flags,
        nullptr,
        static_cast<DWORD>(hr),
        MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
        reinterpret_cast<LPWSTR>(&buffer),
        0,
        nullptr
    );
    char hex[20];
    std::snprintf(hex, sizeof(hex), "0x%08lX", static_cast<unsigned long>(static_cast<unsigned long>(hr)));
    if (!n || !buffer) {
        return hex;
    }
    std::string text = wideToUtf8(buffer);
    LocalFree(buffer);
    while (!text.empty() && (text.back() == '\n' || text.back() == '\r' || text.back() == ' ')) {
        text.pop_back();
    }
    if (text.empty()) {
        return hex;
    }
    text += " ";
    text += hex;
    return text;
}

std::wstring joinPath(const std::wstring& directory, const wchar_t* fileName) {
    if (directory.empty()) {
        return fileName ? fileName : std::wstring();
    }
    if (directory.back() == L'\\' || directory.back() == L'/') {
        return directory + fileName;
    }
    return directory + L'\\' + fileName;
}

std::string joinUtf8Path(const std::string& directory, const char* fileName) {
    std::string path = directory;
    if (!path.empty() && path.back() != '\\' && path.back() != '/') {
        path += '\\';
    }
    path += fileName ? fileName : "";
    return path;
}

void hideOwnConsole() {
    HWND hwnd = GetConsoleWindow();
    if (!hwnd) {
        return;
    }
    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    if (pid == GetCurrentProcessId()) {
        FreeConsole();
    }
}

void setAppUserModelId() {
    SetCurrentProcessExplicitAppUserModelID(L"BlitzReels.BlitzRecorder");
}

void letterboxDest(int dstW, int dstH, unsigned srcW, unsigned srcH, int& x, int& y, int& w, int& h) {
    if (dstW < 1 || dstH < 1 || srcW < 1 || srcH < 1) {
        x = 0;
        y = 0;
        w = (std::max)(1, dstW);
        h = (std::max)(1, dstH);
        return;
    }
    const double src = static_cast<double>(srcW) / static_cast<double>(srcH);
    const double dst = static_cast<double>(dstW) / static_cast<double>(dstH);
    if (src > dst) {
        w = dstW;
        h = (std::max)(1, static_cast<int>(dstW / src));
        x = 0;
        y = (dstH - h) / 2;
    } else {
        h = dstH;
        w = (std::max)(1, static_cast<int>(dstH * src));
        x = (dstW - w) / 2;
        y = 0;
    }
}

long ensureCom() {
    const HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (hr == S_OK || hr == S_FALSE || hr == RPC_E_CHANGED_MODE) {
        return S_OK;
    }
    return static_cast<long>(hr);
}

void readCameraPip(const char* takeDir, double& x, double& y, double& width, double& height) {
    x = 0.68;
    y = 0.68;
    width = 0.28;
    height = 0.28;
    if (!takeDir || !takeDir[0]) {
        return;
    }
    const std::wstring path = utf8ToWide(joinUtf8Path(takeDir, "project.blitzrecorder.json"));
    if (path.empty()) {
        return;
    }
    HANDLE file = CreateFileW(
        path.c_str(),
        GENERIC_READ,
        FILE_SHARE_READ,
        nullptr,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        nullptr
    );
    if (file == INVALID_HANDLE_VALUE) {
        return;
    }
    LARGE_INTEGER size{};
    if (!GetFileSizeEx(file, &size) || size.QuadPart <= 0 || size.QuadPart > 1'000'000) {
        CloseHandle(file);
        return;
    }
    std::string json(static_cast<size_t>(size.QuadPart), '\0');
    DWORD read = 0;
    const BOOL ok = ReadFile(file, json.data(), static_cast<DWORD>(json.size()), &read, nullptr);
    CloseHandle(file);
    if (!ok || read == 0) {
        return;
    }
    json.resize(read);
    auto parseRectAt = [&](size_t key) -> bool {
        const size_t brace = json.find('{', key);
        const size_t end = brace == std::string::npos ? std::string::npos : json.find('}', brace);
        if (brace == std::string::npos || end == std::string::npos) {
            return false;
        }
        auto numberFor = [&](const char* field, double& out) {
            const std::string needle = std::string("\"") + field + "\"";
            size_t pos = json.find(needle, brace);
            if (pos == std::string::npos || pos > end) {
                return;
            }
            pos = json.find(':', pos);
            if (pos == std::string::npos || pos > end) {
                return;
            }
            out = std::strtod(json.c_str() + pos + 1, nullptr);
        };
        double parsedX = x;
        double parsedY = y;
        double parsedW = width;
        double parsedH = height;
        numberFor("x", parsedX);
        numberFor("y", parsedY);
        numberFor("width", parsedW);
        numberFor("height", parsedH);
        if (parsedW <= 0.0 || parsedH <= 0.0) {
            return false;
        }
        x = parsedX;
        y = parsedY;
        width = parsedW;
        height = parsedH;
        return true;
    };
    const size_t scene = json.find("\"scene\"");
    if (scene != std::string::npos) {
        const size_t camera = json.find("\"camera\"", scene);
        if (camera != std::string::npos && parseRectAt(camera)) {
            return;
        }
    }
    const size_t cameraFrame = json.find("\"cameraFrame\"");
    if (cameraFrame != std::string::npos) {
        parseRectAt(cameraFrame);
    }
}

std::string readUtf8File(const char* takeDir, const char* name) {
    if (!takeDir || !takeDir[0] || !name) {
        return {};
    }
    const std::wstring path = utf8ToWide(joinUtf8Path(takeDir, name));
    if (path.empty()) {
        return {};
    }
    HANDLE file = CreateFileW(
        path.c_str(),
        GENERIC_READ,
        FILE_SHARE_READ,
        nullptr,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        nullptr
    );
    if (file == INVALID_HANDLE_VALUE) {
        return {};
    }
    LARGE_INTEGER size{};
    if (!GetFileSizeEx(file, &size) || size.QuadPart <= 0 || size.QuadPart > 4'000'000) {
        CloseHandle(file);
        return {};
    }
    std::string json(static_cast<size_t>(size.QuadPart), '\0');
    DWORD read = 0;
    const BOOL ok = ReadFile(file, json.data(), static_cast<DWORD>(json.size()), &read, nullptr);
    CloseHandle(file);
    if (!ok || read == 0) {
        return {};
    }
    json.resize(read);
    return json;
}

int64_t hnsFromSeconds(double seconds) {
    if (!std::isfinite(seconds) || seconds <= 0) {
        return 0;
    }
    const std::int64_t ticks = static_cast<std::int64_t>(std::llround(seconds * 600.0));
    return static_cast<std::int64_t>(std::llround((static_cast<double>(ticks) / 600.0) * 10'000'000.0));
}

void readKeptRangesHNS(const char* takeDir, std::vector<br_kept_range>& out) {
    out.clear();
    const std::string json = readUtf8File(takeDir, "project.blitzrecorder.json");
    if (json.empty()) {
        return;
    }
    const size_t cutsKey = json.find("\"cuts\"");
    if (cutsKey == std::string::npos) {
        return;
    }
    const size_t arr = json.find('[', cutsKey);
    if (arr == std::string::npos) {
        return;
    }
    size_t arrEnd = arr + 1;
    int depth = 1;
    while (arrEnd < json.size() && depth > 0) {
        if (json[arrEnd] == '[') {
            ++depth;
        } else if (json[arrEnd] == ']') {
            --depth;
        }
        ++arrEnd;
    }
    struct Cut {
        double start = 0;
        double end = 0;
        bool enabled = true;
    };
    std::vector<Cut> cuts;
    size_t cursor = arr;
    while (cursor < arrEnd) {
        const size_t brace = json.find('{', cursor);
        if (brace == std::string::npos || brace >= arrEnd) {
            break;
        }
        const size_t end = json.find('}', brace);
        if (end == std::string::npos || end >= arrEnd) {
            break;
        }
        Cut cut;
        auto numberFor = [&](const char* key, double& value) {
            const std::string needle = std::string("\"") + key + "\"";
            size_t pos = json.find(needle, brace);
            if (pos == std::string::npos || pos > end) {
                return;
            }
            pos = json.find(':', pos);
            if (pos == std::string::npos || pos > end) {
                return;
            }
            value = std::strtod(json.c_str() + pos + 1, nullptr);
        };
        numberFor("start", cut.start);
        numberFor("end", cut.end);
        auto keyIsFalse = [&](const char* key) {
            const std::string needle = std::string("\"") + key + "\"";
            const size_t keyPos = json.find(needle, brace);
            if (keyPos == std::string::npos || keyPos > end) {
                return false;
            }
            const size_t falsePos = json.find("false", keyPos);
            return falsePos != std::string::npos && falsePos < end;
        };
        if (keyIsFalse("isEnabled") || keyIsFalse("enabled")) {
            cut.enabled = false;
        }
        if (cut.enabled && cut.end > cut.start) {
            cuts.push_back(cut);
        }
        cursor = end + 1;
    }
    if (cuts.empty()) {
        return;
    }
    std::sort(cuts.begin(), cuts.end(), [](const Cut& a, const Cut& b) {
        return a.start < b.start;
    });
    constexpr double kTakeSeconds = 24.0 * 3600.0;
    constexpr double kEpsilon = 1.0 / 600.0;
    struct Removed {
        double start;
        double end;
    };
    std::vector<Removed> removed;
    for (const Cut& cut : cuts) {
        const double start = (std::min)((std::max)(0.0, cut.start), kTakeSeconds);
        const double end = (std::min)((std::max)(start, cut.end), kTakeSeconds);
        if (end - start <= kEpsilon) {
            continue;
        }
        if (!removed.empty() && start <= removed.back().end + kEpsilon) {
            removed.back().end = (std::max)(removed.back().end, end);
        } else {
            removed.push_back({start, end});
        }
    }
    if (removed.empty()) {
        return;
    }
    double cursorSeconds = 0;
    for (const Removed& range : removed) {
        if (range.start > cursorSeconds) {
            out.push_back({hnsFromSeconds(cursorSeconds), hnsFromSeconds(range.start)});
        }
        cursorSeconds = (std::max)(cursorSeconds, range.end);
    }
    if (kTakeSeconds > cursorSeconds) {
        out.push_back({hnsFromSeconds(cursorSeconds), hnsFromSeconds(kTakeSeconds)});
    }
}

bool resolveTakeDirectory(const char* picked, std::string& takeDir) {
    takeDir.clear();
    if (!picked || !picked[0]) {
        setLastError("take folder is empty");
        return false;
    }
    if (fileExistsUtf8(joinUtf8Path(picked, "screen.mp4").c_str())) {
        takeDir = picked;
        return true;
    }
    const std::wstring root = utf8ToWide(picked);
    if (root.empty()) {
        setLastError("take folder is empty");
        return false;
    }
    WIN32_FIND_DATAW fd{};
    const std::wstring glob = joinPath(root, L"*");
    HANDLE find = FindFirstFileW(glob.c_str(), &fd);
    if (find == INVALID_HANDLE_VALUE) {
        setLastError("screen.mp4 missing in take folder");
        return false;
    }
    FILETIME newest{};
    std::wstring best;
    do {
        if ((fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0) {
            continue;
        }
        if (fd.cFileName[0] == L'.') {
            continue;
        }
        const std::wstring child = joinPath(root, fd.cFileName);
        const std::string utf8 = wideToUtf8(child.c_str());
        if (!fileExistsUtf8(joinUtf8Path(utf8, "screen.mp4").c_str())) {
            continue;
        }
        if (best.empty() || CompareFileTime(&fd.ftLastWriteTime, &newest) > 0) {
            newest = fd.ftLastWriteTime;
            best = child;
        }
    } while (FindNextFileW(find, &fd));
    FindClose(find);
    if (best.empty()) {
        setLastError("screen.mp4 missing in take folder");
        return false;
    }
    takeDir = wideToUtf8(best.c_str());
    return !takeDir.empty();
}

int openTakePlayback(const char* takeDir) {
    if (!takeDir || !takeDir[0]) {
        setLastError("take folder is empty");
        return 1;
    }
    const std::string screen = joinUtf8Path(takeDir, "screen.mp4");
    if (!fileExistsUtf8(screen.c_str())) {
        setLastError("screen.mp4 missing in take folder");
        return 1;
    }
    const std::string camera = joinUtf8Path(takeDir, "camera.mp4");
    const std::string mic = joinUtf8Path(takeDir, "audio.m4a");
    const std::string systemAudio = joinUtf8Path(takeDir, "system-audio.m4a");
    double pipX = 0.68;
    double pipY = 0.68;
    double pipW = 0.28;
    double pipH = 0.28;
    readCameraPip(takeDir, pipX, pipY, pipW, pipH);
    std::vector<br_kept_range> ranges;
    readKeptRangesHNS(takeDir, ranges);
    return br_player_open_take(
        screen.c_str(),
        fileExistsUtf8(camera.c_str()) ? camera.c_str() : "",
        fileExistsUtf8(mic.c_str()) ? mic.c_str() : "",
        fileExistsUtf8(systemAudio.c_str()) ? systemAudio.c_str() : "",
        ranges.empty() ? nullptr : ranges.data(),
        static_cast<int>(ranges.size()),
        pipX,
        pipY,
        pipW,
        pipH
    );
}

std::int64_t qpcHns() {
    static LARGE_INTEGER frequency = [] {
        LARGE_INTEGER value;
        QueryPerformanceFrequency(&value);
        return value;
    }();
    LARGE_INTEGER now;
    QueryPerformanceCounter(&now);
    const std::int64_t ticks = now.QuadPart;
    const std::int64_t freq = frequency.QuadPart;
    if (freq == 0) {
        return 0;
    }
    return (ticks / freq) * 10'000'000 + ((ticks % freq) * 10'000'000) / freq;
}

ComInit::~ComInit() {
    if (shouldUninit_) {
        CoUninitialize();
    }
}

long ComInit::init(unsigned long coinit) {
    const HRESULT hr = CoInitializeEx(nullptr, coinit);
    if (hr == S_OK || hr == S_FALSE) {
        initialized_ = true;
        shouldUninit_ = true;
        return S_OK;
    }
    if (hr == RPC_E_CHANGED_MODE) {
        initialized_ = true;
        shouldUninit_ = false;
        return S_OK;
    }
    return static_cast<long>(hr);
}

RoInit::~RoInit() {
    if (shouldUninit_) {
        RoUninitialize();
    }
}

long RoInit::init() {
    const HRESULT hr = RoInitialize(RO_INIT_MULTITHREADED);
    if (hr == S_OK) {
        shouldUninit_ = true;
        return S_OK;
    }
    if (hr == S_FALSE || hr == RPC_E_CHANGED_MODE) {
        shouldUninit_ = false;
        return S_OK;
    }
    return static_cast<long>(hr);
}

#endif

}  // namespace br
