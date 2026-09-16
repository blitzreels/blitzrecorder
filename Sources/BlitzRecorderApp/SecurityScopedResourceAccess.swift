import Foundation

struct SecurityScopedResourceAccess {
    private let urls: [URL]
    private var started: [Bool] = []

    init(urls: [URL]) {
        self.urls = urls
    }

    mutating func start() {
        started = urls.map { $0.startAccessingSecurityScopedResource() }
    }

    func stop() {
        for (url, didStart) in zip(urls, started) where didStart {
            url.stopAccessingSecurityScopedResource()
        }
    }
}
