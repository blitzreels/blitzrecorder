import AVFoundation
import Foundation

/// Hands each audio chunk to the live transcript the moment the recorders' backup writer has it, with its time on
/// the take timeline, so live lines do not wait for a backup file to be finished. Chunks are kept only for tracks
/// someone listens to, and only up to a minute of them.
final class LiveAudioTap: @unchecked Sendable {
    static let shared = LiveAudioTap()
    static let maximumQueuedSeconds = 60.0

    struct Chunk: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
        /// Seconds on the take timeline where the chunk starts.
        let seconds: Double
        var duration: Double { Double(buffer.frameLength) / buffer.format.sampleRate }
    }

    private let lock = NSLock()
    private var queues: [String: [Chunk]] = [:]

    func subscribe(_ directory: URL) {
        lock.withLock { queues[directory.standardizedFileURL.path] = [] }
    }

    func unsubscribe(_ directory: URL) {
        lock.withLock { queues[directory.standardizedFileURL.path] = nil }
    }

    func publish(_ chunk: Chunk, to directory: URL) {
        let key = directory.standardizedFileURL.path
        lock.withLock {
            guard var queue = queues[key] else { return }
            queue.append(chunk)
            if let first = queue.first, chunk.seconds - first.seconds > Self.maximumQueuedSeconds { queue.removeFirst() }
            queues[key] = queue
        }
    }

    func drain(_ directory: URL) -> [Chunk] {
        let key = directory.standardizedFileURL.path
        return lock.withLock {
            let chunks = queues[key] ?? []
            if queues[key] != nil { queues[key] = [] }
            return chunks
        }
    }
}
