import Foundation

/// Decoded project files, reused until the file on disk changes. Search, voice discovery, folders and the
/// transcription queue each read every project in the library; with the cache, each file is decoded once
/// per change instead of once per reader.
final class ProjectFileCache: @unchecked Sendable {
    /// What identifies one version of a file. Atomic saves replace the file, so the file number changes too.
    /// Read with `stat`, which costs a fraction of `FileManager.attributesOfItem` on external drives.
    struct Stamp: Equatable {
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let size: Int64
        let fileNumber: UInt64

        init?(url: URL) {
            var info = stat()
            guard stat(url.path, &info) == 0 else { return nil }
            modifiedSeconds = info.st_mtimespec.tv_sec
            modifiedNanoseconds = info.st_mtimespec.tv_nsec
            size = info.st_size
            fileNumber = info.st_ino
        }
    }

    private struct Entry {
        let stamp: Stamp
        let project: RecordingProject
    }

    /// The whole 190-take library is about 5 MB of JSON, so this bound only matters for unusually large libraries.
    private static let capacity = 1_000

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func project(path: String, stamp: Stamp) -> RecordingProject? {
        lock.withLock { entries[path].flatMap { $0.stamp == stamp ? $0.project : nil } }
    }

    struct Insertion {
        let path: String
        let stamp: Stamp
        let project: RecordingProject
    }

    func insert(_ insertion: Insertion) {
        lock.withLock {
            if entries.count >= Self.capacity, entries[insertion.path] == nil, let evicted = entries.keys.first {
                entries.removeValue(forKey: evicted)
            }
            entries[insertion.path] = Entry(stamp: insertion.stamp, project: insertion.project)
        }
    }
}
