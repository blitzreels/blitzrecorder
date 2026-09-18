#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <process.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <string>
#include <vector>

// Swift's clang driver still injects -debug:dwarf with -use-ld=link (LNK1117).
// This wrapper is a colon-free basename on PATH so we can actually reach MSVC link.exe.

static bool isDwarf(const wchar_t* arg) {
    return _wcsicmp(arg, L"-debug:dwarf") == 0 || _wcsicmp(arg, L"/debug:dwarf") == 0;
}

int wmain(int argc, wchar_t** argv) {
    wchar_t found[MAX_PATH] = {};
    if (!SearchPathW(nullptr, L"link.exe", nullptr, MAX_PATH, found, nullptr)) {
        fwprintf(stderr, L"br-link: link.exe not on PATH\n");
        return 1;
    }

    std::vector<std::wstring> args;
    args.push_back(found);
    for (int i = 1; i < argc; ++i) {
        if (isDwarf(argv[i])) {
            continue;
        }
        args.push_back(argv[i]);
    }

    std::vector<const wchar_t*> ptrs;
    ptrs.reserve(args.size() + 1);
    for (auto& a : args) {
        ptrs.push_back(a.c_str());
    }
    ptrs.push_back(nullptr);

    intptr_t rc = _wspawnvp(_P_WAIT, found, ptrs.data());
    if (rc == -1) {
        fwprintf(stderr, L"br-link: spawn %s failed errno=%d\n", found, errno);
        return 1;
    }
    return (int)rc;
}
