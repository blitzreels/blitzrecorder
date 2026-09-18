#pragma once

#if defined(_WIN32)

#include <string>
#include <vector>

#include <dxgi1_2.h>
#include <wrl/client.h>

namespace br {

struct AttachedOutput {
    Microsoft::WRL::ComPtr<IDXGIAdapter1> adapter;
    Microsoft::WRL::ComPtr<IDXGIOutput1> output;
    void* monitor = nullptr;
    int left = 0;
    int top = 0;
    unsigned width = 0;
    unsigned height = 0;
    bool primary = false;
    std::string label;
};

struct CaptureTarget {
    std::string label;
    int monitorIndex = 0;
    void* hwnd = nullptr;
    bool area = false;
};

std::vector<AttachedOutput> listAttachedOutputs();
std::vector<CaptureTarget> listCaptureTargets(void* excludeHwnd);

}  // namespace br

#endif
