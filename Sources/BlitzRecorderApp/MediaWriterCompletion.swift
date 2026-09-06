import Foundation

struct MediaWriterCompletion: Equatable {
    let url: URL?
    let wroteMedia: Bool

    static func wrote(_ url: URL? = nil) -> MediaWriterCompletion {
        MediaWriterCompletion(url: url, wroteMedia: true)
    }

    static func empty(_ url: URL? = nil) -> MediaWriterCompletion {
        MediaWriterCompletion(url: url, wroteMedia: false)
    }
}

final class MediaWriterFinalization {
    private var result: Result<MediaWriterCompletion, Error>?
    private var waiters: [CheckedContinuation<MediaWriterCompletion, Error>] = []

    func begin(_ continuation: CheckedContinuation<MediaWriterCompletion, Error>) -> Bool {
        if let result {
            continuation.resume(with: result)
            return false
        }
        waiters.append(continuation)
        return waiters.count == 1
    }

    func complete(_ result: Result<MediaWriterCompletion, Error>) {
        self.result = result
        let pending = waiters
        waiters.removeAll()
        for continuation in pending { continuation.resume(with: result) }
    }
}
