#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <vector>
#include <cstring>

// Post-link RT_GROUP_ICON + RT_MANIFEST. Swift/lld can keep a default
// RT_MANIFEST and drop the icon when merging a positional .res (and lld-link
// splits D:\ paths on the colon so BlitzRecorder.res never even arrives).

#pragma pack(push, 1)
struct IconDir {
    WORD reserved;
    WORD type;
    WORD count;
};
struct IconDirEntry {
    BYTE width;
    BYTE height;
    BYTE colorCount;
    BYTE reserved;
    WORD planes;
    WORD bitCount;
    DWORD bytesInRes;
    DWORD imageOffset;
};
struct GrpIconDirEntry {
    BYTE width;
    BYTE height;
    BYTE colorCount;
    BYTE reserved;
    WORD planes;
    WORD bitCount;
    DWORD bytesInRes;
    WORD id;
};
#pragma pack(pop)

static std::vector<unsigned char> readFile(const wchar_t* path) {
    FILE* f = nullptr;
    if (_wfopen_s(&f, path, L"rb") != 0 || !f) {
        return {};
    }
    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        return {};
    }
    const long n = ftell(f);
    if (n <= 0) {
        fclose(f);
        return {};
    }
    if (fseek(f, 0, SEEK_SET) != 0) {
        fclose(f);
        return {};
    }
    std::vector<unsigned char> b(static_cast<size_t>(n));
    const size_t got = fread(b.data(), 1, b.size(), f);
    fclose(f);
    if (got != b.size()) {
        return {};
    }
    return b;
}

int wmain(int argc, wchar_t** argv) {
    if (argc != 4) {
        fwprintf(stderr, L"usage: embed_pe_resources <exe> <ico> <manifest>\n");
        return 2;
    }
    const wchar_t* exe = argv[1];
    const auto ico = readFile(argv[2]);
    auto man = readFile(argv[3]);
    if (ico.size() < sizeof(IconDir)) {
        fwprintf(stderr, L"embed_pe_resources: cannot read ico\n");
        return 3;
    }
    if (man.empty()) {
        fwprintf(stderr, L"embed_pe_resources: cannot read manifest\n");
        return 3;
    }
    // UTF-8 BOM breaks mt/loader XML parse.
    if (man.size() >= 3 && man[0] == 0xEF && man[1] == 0xBB && man[2] == 0xBF) {
        man.erase(man.begin(), man.begin() + 3);
    }

    HANDLE h = BeginUpdateResourceW(exe, FALSE);
    if (!h) {
        fwprintf(stderr, L"BeginUpdateResource failed %lu\n", GetLastError());
        return 4;
    }

    const WORD lang = MAKELANGID(LANG_ENGLISH, SUBLANG_ENGLISH_US);
    if (!UpdateResourceW(h, MAKEINTRESOURCEW(24), MAKEINTRESOURCEW(1), lang, man.data(), (DWORD)man.size())) {
        fwprintf(stderr, L"UpdateResource manifest failed %lu\n", GetLastError());
        EndUpdateResourceW(h, TRUE);
        return 5;
    }

    IconDir dir{};
    memcpy(&dir, ico.data(), sizeof(dir));
    if (dir.reserved != 0 || dir.type != 1 || dir.count == 0) {
        fwprintf(stderr, L"embed_pe_resources: not an ICO\n");
        EndUpdateResourceW(h, TRUE);
        return 6;
    }
    const size_t tableBytes = sizeof(IconDir) + static_cast<size_t>(dir.count) * sizeof(IconDirEntry);
    if (ico.size() < tableBytes) {
        fwprintf(stderr, L"embed_pe_resources: truncated ICO directory\n");
        EndUpdateResourceW(h, TRUE);
        return 6;
    }

    const auto* ents = reinterpret_cast<const IconDirEntry*>(ico.data() + sizeof(IconDir));
    std::vector<GrpIconDirEntry> grp(dir.count);
    for (WORD i = 0; i < dir.count; ++i) {
        const WORD id = static_cast<WORD>(i + 1);
        const auto& e = ents[i];
        if (e.imageOffset > ico.size() || e.bytesInRes == 0 ||
            e.imageOffset + e.bytesInRes > ico.size()) {
            fwprintf(stderr, L"embed_pe_resources: ICO image %u out of range\n", id);
            EndUpdateResourceW(h, TRUE);
            return 7;
        }
        if (!UpdateResourceW(h, MAKEINTRESOURCEW(3), MAKEINTRESOURCEW(id), lang,
                             const_cast<unsigned char*>(ico.data() + e.imageOffset), e.bytesInRes)) {
            fwprintf(stderr, L"UpdateResource RT_ICON %u failed %lu\n", id, GetLastError());
            EndUpdateResourceW(h, TRUE);
            return 8;
        }
        grp[i].width = e.width;
        grp[i].height = e.height;
        grp[i].colorCount = e.colorCount;
        grp[i].reserved = 0;
        grp[i].planes = e.planes;
        grp[i].bitCount = e.bitCount;
        grp[i].bytesInRes = e.bytesInRes;
        grp[i].id = id;
    }

    std::vector<unsigned char> grpBlob(sizeof(IconDir) + grp.size() * sizeof(GrpIconDirEntry));
    memcpy(grpBlob.data(), &dir, sizeof(dir));
    memcpy(grpBlob.data() + sizeof(dir), grp.data(), grp.size() * sizeof(GrpIconDirEntry));
    // IDI_APPICON 101 — same id as app.rc.
    if (!UpdateResourceW(h, MAKEINTRESOURCEW(14), MAKEINTRESOURCEW(101), lang,
                         grpBlob.data(), (DWORD)grpBlob.size())) {
        fwprintf(stderr, L"UpdateResource GROUP_ICON failed %lu\n", GetLastError());
        EndUpdateResourceW(h, TRUE);
        return 9;
    }

    if (!EndUpdateResourceW(h, FALSE)) {
        fwprintf(stderr, L"EndUpdateResource failed %lu\n", GetLastError());
        return 10;
    }
    fwprintf(stderr, L"embedded icon+manifest into %s\n", exe);
    return 0;
}
