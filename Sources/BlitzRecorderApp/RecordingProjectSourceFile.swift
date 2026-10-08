import Foundation

final class RecordingSourceAccess {
    let url: URL
    let bookmarkIsStale: Bool
    private let started: Bool

    init(bookmarkData: Data) throws {
        var stale = false
        url = try URL(resolvingBookmarkData: bookmarkData, options: [.withSecurityScope, .withoutUI],
                      relativeTo: nil, bookmarkDataIsStale: &stale)
        bookmarkIsStale = stale
        started = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if started { url.stopAccessingSecurityScopedResource() }
    }
}

extension RecordingProject.SourceFile {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(String.self, forKey: .role)
        path = try container.decode(String.self, forKey: .path)
        exists = try container.decode(Bool.self, forKey: .exists)
        bookmarkData = try container.decodeIfPresent(Data.self, forKey: .bookmarkData)
        resolveExternalReference()
    }

    mutating func resolveExternalReference() {
        guard let bookmarkData else { return }
        guard let access = try? RecordingSourceAccess(bookmarkData: bookmarkData) else {
            exists = false
            return
        }
        resourceAccess = access
        path = access.url.path
        exists = FileManager.default.isReadableFile(atPath: path)
        if access.bookmarkIsStale {
            self.bookmarkData = try? access.url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil, relativeTo: nil)
            if self.bookmarkData == nil { self.bookmarkData = bookmarkData }
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.role == rhs.role && lhs.path == rhs.path && lhs.exists == rhs.exists && lhs.bookmarkData == rhs.bookmarkData
    }
}
