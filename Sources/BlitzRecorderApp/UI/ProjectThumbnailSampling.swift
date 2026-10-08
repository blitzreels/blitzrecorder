import AVFoundation
import CoreGraphics
import CoreImage
import Foundation

enum ProjectThumbnailSampling {
    struct Request {
        let url: URL
        let startSeconds: Double
    }

    static func firstFrame(_ request: Request) async -> CGImage? {
        guard !Task.isCancelled else { return nil }
        let asset = AVURLAsset(url: request.url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let range = try? await track.load(.timeRange) else { return nil }
        guard request.startSeconds.isFinite else { return nil }
        let time = CMTimeMaximum(range.start, CMTime(seconds: max(0, request.startSeconds), preferredTimescale: 60_000))
        guard CMTimeCompare(time, CMTimeRangeGetEnd(range)) < 0 else { return nil }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image: CGImage? = await withTaskCancellationHandler {
            guard !Task.isCancelled else { return nil }
            return try? await generator.image(at: time).image
        } onCancel: {
            generator.cancelAllCGImageGeneration()
        }
        if let image { return image }
        guard !Task.isCancelled,
              let transform = try? await track.load(.preferredTransform),
              let reader = try? AVAssetReader(asset: asset) else { return nil }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        reader.timeRange = CMTimeRange(start: time, end: CMTimeRangeGetEnd(range))
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        defer { reader.cancelReading() }
        guard !Task.isCancelled,
              let sample = output.copyNextSampleBuffer(),
              let pixels = CMSampleBufferGetImageBuffer(sample) else { return nil }
        let frame = CIImage(cvPixelBuffer: pixels).transformed(by: transform)
        let extent = frame.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        let scale = min(1, 640 / extent.width, 360 / extent.height)
        let scaled = frame.transformed(by: .init(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: .init(scaleX: scale, y: scale))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}
