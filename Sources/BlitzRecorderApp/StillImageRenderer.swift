import CoreImage
import CoreMedia
import Foundation

/// Small still pictures from live frames and video samples. Making a Core Image context is slow; one shared
/// context renders on any thread.
enum StillImageRenderer {
    private static let context = CIContext(options: [.cacheIntermediates: false])
    private static let queue = DispatchQueue(label: "blitzrecorder.still-images", qos: .utility)

    struct Request {
        let image: CIImage
        let maxSize: CGSize
    }

    struct DeferredRequest {
        let still: Request
        let completion: @MainActor (CGImage?) -> Void
    }

    static func render(_ request: Request) -> CGImage? {
        let extent = request.image.extent
        guard extent.width > 0, extent.height > 0, !extent.isInfinite else { return nil }
        let scale = min(1, request.maxSize.width / extent.width, request.maxSize.height / extent.height)
        let scaled = request.image
            .transformed(by: .init(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: .init(scaleX: scale, y: scale))
        return context.createCGImage(scaled, from: scaled.extent)
    }

    static func renderOffMain(_ request: DeferredRequest) {
        queue.async {
            let image = render(request.still)
            DispatchQueue.main.async { MainActor.assumeIsolated { request.completion(image) } }
        }
    }
}
