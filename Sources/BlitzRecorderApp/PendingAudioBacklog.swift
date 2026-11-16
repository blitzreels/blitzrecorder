import AVFoundation
import CoreMedia
import Foundation

/// Sound an audio writer input was not ready for yet. It is written as soon as the input catches up instead of
/// being dropped; only a backlog of several seconds loses its oldest buffers. Use it from the writer's queue.
struct PendingAudioBacklog {
    struct DrainResult {
        let appended: Int
        /// The input refused a buffer: the writer has failed.
        let rejected: Bool
    }

    private static let capacity = 300
    private var buffers: [CMSampleBuffer] = []
    private(set) var droppedCount = 0

    var isEmpty: Bool { buffers.isEmpty }

    mutating func add(_ buffer: CMSampleBuffer) {
        buffers.append(buffer)
        if buffers.count > Self.capacity {
            buffers.removeFirst()
            droppedCount += 1
        }
    }

    /// Appends what the input takes now and keeps the rest for later.
    mutating func drain(into input: AVAssetWriterInput) -> DrainResult {
        var appended = 0
        while !buffers.isEmpty, input.isReadyForMoreMediaData {
            let next = buffers.removeFirst()
            guard input.append(next) else { return .init(appended: appended, rejected: true) }
            appended += 1
        }
        return .init(appended: appended, rejected: false)
    }

    /// At the end of a take: gives the input up to a second to take the rest, then counts what is left as dropped.
    mutating func flush(into input: AVAssetWriterInput) -> DrainResult {
        let deadline = DispatchTime.now() + .seconds(1)
        var appended = 0
        while !buffers.isEmpty, DispatchTime.now() < deadline {
            let result = drain(into: input)
            appended += result.appended
            if result.rejected { return .init(appended: appended, rejected: true) }
            if !buffers.isEmpty { usleep(2_000) }
        }
        droppedCount += buffers.count
        buffers.removeAll()
        return .init(appended: appended, rejected: false)
    }
}
