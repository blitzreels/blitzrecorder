import Foundation

enum EditorBackgroundMusicResolution {
    struct Request {
        let path: String?
        let bookmarkData: Data?
        let volume: Double?
    }

    struct Result {
        let music: ExportBackgroundMusic?
        let refreshedBookmarkData: Data?
    }

    static func resolve(_ request: Request) -> Result {
        guard let path = request.path else {
            return Result(music: nil, refreshedBookmarkData: nil)
        }
        var url = URL(fileURLWithPath: path)
        var refreshedBookmarkData: Data?
        if let bookmarkData = request.bookmarkData {
            var isStale = false
            if let resolvedURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                url = resolvedURL
                if isStale {
                    refreshedBookmarkData = RecordingSettingsStore.bookmarkData(for: resolvedURL)
                }
            }
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return Result(music: nil, refreshedBookmarkData: refreshedBookmarkData)
        }
        return Result(
            music: ExportBackgroundMusic(url: url, volume: request.volume ?? 0.18),
            refreshedBookmarkData: refreshedBookmarkData
        )
    }
}
