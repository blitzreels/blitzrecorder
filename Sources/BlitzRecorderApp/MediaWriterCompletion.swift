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
