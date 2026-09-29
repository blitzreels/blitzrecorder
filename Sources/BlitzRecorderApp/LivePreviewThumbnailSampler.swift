import AVFoundation
import CoreImage

struct LiveSceneThumbnails {
    var screen: CGImage?
    var camera: CGImage?
}

@MainActor
final class LivePreviewThumbnailSampler {
    private static let interval: TimeInterval = 1
    nonisolated private static let maximumDimension: CGFloat = 180
    nonisolated(unsafe) private static let context = CIContext(options: [.cacheIntermediates: false])
    private static let queue = DispatchQueue(label: "dev.blitzreels.blitzrecorder.preview-thumbnails", qos: .utility)

    private var lastSampleTime = Date.distantPast
    private var isRendering = false
    var onImage: ((CGImage) -> Void)?

    func offer(_ sampleBuffer: CMSampleBuffer) {
        guard onImage != nil, !isRendering,
              Date().timeIntervalSince(lastSampleTime) >= Self.interval,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        render(CIImage(cvPixelBuffer: pixelBuffer))
    }

    func offer(_ image: CGImage) {
        guard onImage != nil, !isRendering,
              Date().timeIntervalSince(lastSampleTime) >= Self.interval else { return }
        render(CIImage(cgImage: image))
    }

    private func render(_ image: CIImage) {
        lastSampleTime = Date()
        isRendering = true
        Self.queue.async { [weak self] in
            let longest = max(image.extent.width, image.extent.height)
            let scale = longest > 0 ? min(1, Self.maximumDimension / longest) : 1
            let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let thumbnail = Self.context.createCGImage(scaled, from: scaled.extent)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRendering = false
                if let thumbnail { self.onImage?(thumbnail) }
            }
        }
    }
}
