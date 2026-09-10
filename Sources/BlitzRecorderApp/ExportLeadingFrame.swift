import AVFoundation
import CoreGraphics
import Foundation

final class ExportLeadingFrame: @unchecked Sendable {
    struct Request {
        let asset: AVAsset
        let sourceStart: CMTime
        let compositionStart: CMTime
        let frameDuration: CMTime
    }

    private let request: Request
    private let lock = NSLock()
    private var resolved = false
    private var image: CGImage?

    init(_ request: Request) {
        self.request = request
    }

    func image(at time: CMTime) -> CGImage? {
        let offset = CMTimeSubtract(time, request.compositionStart)
        guard offset.isNumeric, CMTimeCompare(offset, .zero) >= 0,
              CMTimeCompare(offset, request.frameDuration) < 0 else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if resolved { return image }
        resolved = true
        let generator = AVAssetImageGenerator(asset: request.asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = request.frameDuration
        var actualTime = CMTime.invalid
        guard let candidate = try? generator.copyCGImage(at: request.sourceStart, actualTime: &actualTime) else { return nil }
        let gap = CMTimeSubtract(actualTime, request.sourceStart)
        guard gap.isNumeric, CMTimeCompare(gap, .zero) >= 0,
              CMTimeCompare(gap, request.frameDuration) <= 0 else { return nil }
        image = candidate
        return candidate
    }
}
