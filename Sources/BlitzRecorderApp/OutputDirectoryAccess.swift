import Foundation

final class OutputDirectoryAccess {
    private let accesses: [(url: URL, needsScope: Bool, started: Bool)]
    private var isStopped = false

    init(url: URL, usesSecurityScopedBookmark: Bool) {
        accesses = [(url, usesSecurityScopedBookmark,
                     usesSecurityScopedBookmark && url.startAccessingSecurityScopedResource())]
    }

    init(locations: [RecordingStorageLocation]) {
        var seen: Set<URL> = []
        accesses = locations.filter { seen.insert($0.url.standardizedFileURL).inserted }.map {
            let needsScope = $0.bookmarkData != nil
            return ($0.url, needsScope, needsScope && $0.url.startAccessingSecurityScopedResource())
        }
    }

    var hasSecurityScopedAccess: Bool {
        accesses.allSatisfy { !$0.needsScope || ($0.started && !isStopped) }
    }

    var unavailableURL: URL? { accesses.first { $0.needsScope && !$0.started }?.url }

    deinit {
        stop()
    }

    func stop() {
        guard !isStopped else { return }
        for access in accesses where access.started { access.url.stopAccessingSecurityScopedResource() }
        isStopped = true
    }
}
