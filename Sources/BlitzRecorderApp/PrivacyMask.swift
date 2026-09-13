import CoreGraphics
import CoreImage
import Foundation

struct PrivacyMask: Codable, Equatable, Identifiable, Sendable {
    enum Style: String, Codable, CaseIterable {
        case cover = "Cover"
        case blur = "Blur"
    }

    let id: UUID
    var source: SceneLayerKind
    var frame: CGRect
    var start: Double
    var end: Double
    var style: Style

    func isVisible(at time: Double) -> Bool {
        time >= start && time < end && frame.width > 0 && frame.height > 0
    }

    struct FrameRequest {
        let start: CGPoint
        let end: CGPoint
        let size: CGSize
    }

    static func frame(_ request: FrameRequest) -> CGRect {
        guard request.size.width > 0, request.size.height > 0 else { return .zero }
        let rect = CGRect(x: min(request.start.x, request.end.x) / request.size.width,
                          y: min(request.start.y, request.end.y) / request.size.height,
                          width: abs(request.end.x - request.start.x) / request.size.width,
                          height: abs(request.end.y - request.start.y) / request.size.height)
        let bounded = rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        return bounded.isNull ? .zero : bounded
    }
}

enum PrivacyMaskRenderer {
    struct Request {
        let image: CIImage
        let masks: [PrivacyMask]
        let source: SceneLayerKind
        let time: Double
    }

    static func render(_ request: Request) -> CIImage {
        var image = request.image
        let bounds = image.extent
        for mask in request.masks where mask.source == request.source && mask.isVisible(at: request.time) {
            let rect = CGRect(x: bounds.minX + mask.frame.minX * bounds.width,
                              y: bounds.minY + (1 - mask.frame.maxY) * bounds.height,
                              width: mask.frame.width * bounds.width,
                              height: mask.frame.height * bounds.height).intersection(bounds)
            guard !rect.isEmpty, !rect.isNull else { continue }
            let patch: CIImage
            switch mask.style {
            case .cover:
                patch = CIImage(color: .black).cropped(to: rect)
            case .blur:
                patch = image.clampedToExtent()
                    .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: max(12, bounds.width * 0.025)])
                    .cropped(to: rect)
            }
            image = patch.composited(over: image)
        }
        return image.cropped(to: bounds)
    }
}
