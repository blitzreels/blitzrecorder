cmake_minimum_required(VERSION 3.21)
project(WindowsCaptureNative LANGUAGES CXX)

cmake_policy(SET CMP0091 NEW)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL")
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

option(BR_BUILD_CAPTURE_ADAPTER "WGC/DXGI/WASAPI/camera (off for the H.264 fixture)" ON)
option(BR_BUILD_STUDIO_SHELL "WinUI/Win32 studio shell (off for the H.264 fixture)" ON)

# WRL + WinRT ABI headers need two-phase lookup off under MSVC 17/18.
set(BR_MSVC_CXX /EHsc /utf-8 /W3 /Zc:twoPhase- /permissive-)

add_library(WindowsCaptureNative STATIC
    Sources/WindowsCapture/capture_common.cpp
    Sources/WindowsCapture/compose_export.cpp
    Sources/WindowsCapture/mf_player.cpp
    Sources/WindowsCapture/mf_rgb32.cpp
    Sources/WindowsCapture/mf_sink.cpp
    Sources/WindowsCapture/monitor_list.cpp
    Sources/WindowsCapture/windows_capture.cpp
)

target_include_directories(WindowsCaptureNative
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/Sources/WindowsCapture/include
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/Sources/WindowsCapture
)

target_compile_definitions(WindowsCaptureNative
    PRIVATE
        UNICODE
        _UNICODE
        NOMINMAX
        WINVER=0x0A00
        _WIN32_WINNT=0x0A00
        NTDDI_VERSION=0x0A00000C
        BR_HAS_CAPTURE=$<BOOL:${BR_BUILD_CAPTURE_ADAPTER}>
)

target_compile_options(WindowsCaptureNative PRIVATE ${BR_MSVC_CXX})

target_link_libraries(WindowsCaptureNative
    PUBLIC
        d3d11
        dxgi
        d3dcompiler
        mf
        mfplat
        mfreadwrite
        mfuuid
        ole32
        oleaut32
        avrt
        uuid
        user32
        dwmapi
        shell32
        mmdevapi
        runtimeobject
)

set_target_properties(WindowsCaptureNative PROPERTIES
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
    ARCHIVE_OUTPUT_DIRECTORY_DEBUG "${CMAKE_BINARY_DIR}/lib"
    ARCHIVE_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/lib"
    ARCHIVE_OUTPUT_DIRECTORY_RELWITHDEBINFO "${CMAKE_BINARY_DIR}/lib"
    ARCHIVE_OUTPUT_DIRECTORY_MINSIZEREL "${CMAKE_BINARY_DIR}/lib"
)

if(BR_BUILD_CAPTURE_ADAPTER)
    add_library(WindowsCaptureAdapter STATIC
        Sources/WindowsCapture/capture_abi.cpp
        Sources/WindowsCapture/capture_session.cpp
        Sources/WindowsCapture/dxgi_duplicator.cpp
        Sources/WindowsCapture/mf_camera.cpp
        Sources/WindowsCapture/wasapi_capture.cpp
        Sources/WindowsCapture/wgc_capturer.cpp
    )
    target_include_directories(WindowsCaptureAdapter
        PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}/Sources/WindowsCapture
            ${CMAKE_CURRENT_SOURCE_DIR}/Sources/WindowsCapture/include
    )
    target_compile_definitions(WindowsCaptureAdapter
        PRIVATE
            UNICODE
            _UNICODE
            NOMINMAX
            WINVER=0x0A00
            _WIN32_WINNT=0x0A00
            NTDDI_VERSION=0x0A00000C
    )
    target_compile_options(WindowsCaptureAdapter PRIVATE ${BR_MSVC_CXX})
    target_link_libraries(WindowsCaptureAdapter
        PUBLIC
            WindowsCaptureNative
            windowsapp
            runtimeobject
    )
    set_target_properties(WindowsCaptureAdapter PROPERTIES
        ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
        ARCHIVE_OUTPUT_DIRECTORY_DEBUG "${CMAKE_BINARY_DIR}/lib"
        ARCHIVE_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/lib"
        ARCHIVE_OUTPUT_DIRECTORY_RELWITHDEBINFO "${CMAKE_BINARY_DIR}/lib"
        ARCHIVE_OUTPUT_DIRECTORY_MINSIZEREL "${CMAKE_BINARY_DIR}/lib"
    )
endif()

add_executable(BlitzRecorderFixture Sources/WindowsCapture/fixture_main.cpp)
target_link_libraries(BlitzRecorderFixture PRIVATE WindowsCaptureNative)
target_compile_definitions(BlitzRecorderFixture PRIVATE UNICODE _UNICODE NOMINMAX)
target_compile_options(BlitzRecorderFixture PRIVATE ${BR_MSVC_CXX})
set_target_properties(BlitzRecorderFixture PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
    RUNTIME_OUTPUT_DIRECTORY_DEBUG "${CMAKE_BINARY_DIR}/bin"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/bin"
    RUNTIME_OUTPUT_DIRECTORY_RELWITHDEBINFO "${CMAKE_BINARY_DIR}/bin"
    RUNTIME_OUTPUT_DIRECTORY_MINSIZEREL "${CMAKE_BINARY_DIR}/bin"
)

if(BR_BUILD_STUDIO_SHELL)
    # Compile-only: an isolated try_compile *link* of windowsapp.lib is a false
    # FATAL on some images even when winui_shell.cpp compiles in-tree.
    # CMAKE_FLAGS -D is not enough on every CMake; set the variable too.
    set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
    try_compile(BR_WINUI_OK
        "${CMAKE_BINARY_DIR}/winui_probe"
        "${CMAKE_CURRENT_SOURCE_DIR}/cmake/winui_probe.cpp"
        CMAKE_FLAGS
            "-DCMAKE_CXX_FLAGS=/EHsc /utf-8 /Zc:twoPhase- /permissive-"
            "-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY"
        COMPILE_DEFINITIONS UNICODE _UNICODE NOMINMAX WINVER=0x0A00 _WIN32_WINNT=0x0A00 NTDDI_VERSION=0x0A00000C
        LINK_LIBRARIES runtimeobject ole32 oleaut32 uuid
        OUTPUT_VARIABLE BR_WINUI_PROBE_LOG
        CXX_STANDARD 17
    )
    unset(CMAKE_TRY_COMPILE_TARGET_TYPE)
    set(_shell_sources
        Sources/WindowsCapture/studio_run.cpp
        Sources/WindowsCapture/studio_dialogs.cpp
        Sources/WindowsCapture/win32_shell.cpp
    )
    if(BR_WINUI_OK)
        message(STATUS "WinUI XAML Islands headers OK")
        list(APPEND _shell_sources Sources/WindowsCapture/winui_shell.cpp)
    else()
        if(DEFINED ENV{GITHUB_ACTIONS} OR DEFINED ENV{CI})
            message(FATAL_ERROR "WinUI XAML Islands headers required in CI; refusing Win32-only studio\n${BR_WINUI_PROBE_LOG}")
        endif()
        message(WARNING "WinUI XAML Islands probe failed; shipping Win32-only shell\n${BR_WINUI_PROBE_LOG}")
    endif()
    add_library(WindowsStudioShell STATIC ${_shell_sources})
    target_include_directories(WindowsStudioShell
        PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}/Sources/WindowsCapture
            ${CMAKE_CURRENT_SOURCE_DIR}/Sources/WindowsCapture/include
    )
    target_compile_definitions(WindowsStudioShell
        PRIVATE
            UNICODE
            _UNICODE
            NOMINMAX
            WINVER=0x0A00
            _WIN32_WINNT=0x0A00
            NTDDI_VERSION=0x0A00000C
            BR_HAS_WINUI=$<BOOL:${BR_WINUI_OK}>
    )
    target_compile_options(WindowsStudioShell PRIVATE ${BR_MSVC_CXX})
    target_link_libraries(WindowsStudioShell
        PUBLIC
            WindowsCaptureNative
            user32
            gdi32
            comctl32
            shcore
            shell32
            ole32
            oleaut32
            uuid
            windowsapp
            runtimeobject
    )
    if(BR_BUILD_CAPTURE_ADAPTER)
        target_link_libraries(WindowsStudioShell PUBLIC WindowsCaptureAdapter)
    endif()
    set_target_properties(WindowsStudioShell PROPERTIES
        ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
        ARCHIVE_OUTPUT_DIRECTORY_DEBUG "${CMAKE_BINARY_DIR}/lib"
        ARCHIVE_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/lib"
        ARCHIVE_OUTPUT_DIRECTORY_RELWITHDEBINFO "${CMAKE_BINARY_DIR}/lib"
        ARCHIVE_OUTPUT_DIRECTORY_MINSIZEREL "${CMAKE_BINARY_DIR}/lib"
    )
endif()
