#pragma once

#include "winrt_compat.h"

#include <windows.h>
#include <unknwn.h>
#include <inspectable.h>
#include <dxgi.h>

#if defined(__has_include)
#  if __has_include(<windows.graphics.capture.interop.h>)
#    include <windows.graphics.capture.interop.h>
#    define BR_HAS_WGC_INTEROP_H 1
#  endif
#  if __has_include(<windows.graphics.directx.direct3d11.interop.h>)
#    include <windows.graphics.directx.direct3d11.interop.h>
#    define BR_HAS_D3D11_INTEROP_H 1
#  endif
#else
#  include <windows.graphics.capture.interop.h>
#  include <windows.graphics.directx.direct3d11.interop.h>
#  define BR_HAS_WGC_INTEROP_H 1
#  define BR_HAS_D3D11_INTEROP_H 1
#endif

#if !defined(BR_HAS_WGC_INTEROP_H) && !defined(__IGraphicsCaptureItemInterop_INTERFACE_DEFINED__)
#define __IGraphicsCaptureItemInterop_INTERFACE_DEFINED__
MIDL_INTERFACE("3628E81B-3CAC-4C60-B7F4-23CE0E0C3356")
IGraphicsCaptureItemInterop : public IUnknown {
    virtual HRESULT STDMETHODCALLTYPE CreateForWindow(HWND windowId, REFIID riid, void** result) = 0;
    virtual HRESULT STDMETHODCALLTYPE CreateForMonitor(HMONITOR monitorId, REFIID riid, void** result) = 0;
};
#endif

#if !defined(BR_HAS_D3D11_INTEROP_H)
#if !defined(__IDirect3DDxgiInterfaceAccess_INTERFACE_DEFINED__)
#define __IDirect3DDxgiInterfaceAccess_INTERFACE_DEFINED__
MIDL_INTERFACE("A9B3D012-3DF2-4EE3-B8D1-86926B929D52")
IDirect3DDxgiInterfaceAccess : public IUnknown {
    virtual HRESULT STDMETHODCALLTYPE GetInterface(REFIID iid, void** p) = 0;
};
#endif
extern "C" HRESULT WINAPI CreateDirect3D11DeviceFromDXGIDevice(
    IDXGIDevice* dxgiDevice,
    IInspectable** graphicsDevice
);
#endif
