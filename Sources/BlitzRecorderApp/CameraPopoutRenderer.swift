import CoreGraphics
import CoreImage
import Vision

struct CameraPopoutStyle: Equatable {
    let target: CGRect
    let cropAmount: CGPoint
    let cropPosition: CGPoint
    let fitsSource: Bool
    let cornerRadius: CGFloat
    let headroom: CGFloat

    struct PlacementRequest {
        let placement: SceneRenderLayerPlacement
        let headroom: CGFloat
    }

    init(_ request: PlacementRequest) {
        target = request.placement.targetRect
        cropAmount = request.placement.videoPlacement.sourceCropAmount
        cropPosition = request.placement.videoPlacement.sourceCropPosition
        fitsSource = request.placement.videoPlacement.contentMode == .aspectFit
        cornerRadius = request.placement.cornerRadius
        headroom = request.headroom
    }

    struct Request {
        let target: CGRect
        let cropAmount: CGPoint
        let cropPosition: CGPoint
        let fitsSource: Bool
        let cornerRadius: CGFloat
        let headroom: CGFloat
    }

    init(_ request: Request) {
        target = request.target
        cropAmount = request.cropAmount
        cropPosition = request.cropPosition
        fitsSource = request.fitsSource
        cornerRadius = request.cornerRadius
        headroom = request.headroom
    }

    var placement: VideoRenderPlacement {
        VideoRenderPlacement(kind: .camera, targetRect: target, sourceCropAmount: cropAmount,
                             sourceCropPosition: cropPosition, contentMode: fitsSource ? .aspectFit : .aspectFill)
    }

    static let defaultHeadroom: CGFloat = 0.2
    static let headroomRange: ClosedRange<CGFloat> = 0.1...0.45

    static func clampedHeadroom(_ headroom: CGFloat) -> CGFloat {
        min(headroomRange.upperBound, max(headroomRange.lowerBound, headroom))
    }

    func panel(in bounds: CGRect) -> CGRect {
        CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height * (1 - headroom))
    }
}

final class CameraPopoutRenderer: @unchecked Sendable {
    struct Request {
        let image: CIImage
        let style: CameraPopoutStyle
    }

    struct CompositeRequest {
        let image: CIImage
        let personMask: CIImage
        let style: CameraPopoutStyle
    }

    private static let segmentationLock = NSLock()

    func image(_ request: Request) -> CIImage {
        Self.segmentationLock.lock()
        defer { Self.segmentationLock.unlock() }
        let segmentation = VNGeneratePersonSegmentationRequest()
        segmentation.qualityLevel = .balanced
        segmentation.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let source = request.image.extent
        guard source.width > 0, source.height > 0 else { return request.image }
        let scale = min(1, 720 / max(source.width, source.height))
        let input = request.image
            .transformed(by: .init(translationX: -source.minX, y: -source.minY))
            .transformed(by: .init(scaleX: scale, y: scale))
        let handler = VNImageRequestHandler(ciImage: input, options: [:])
        let mask: CIImage
        do {
            try handler.perform([segmentation])
            if let buffer = segmentation.results?.first?.pixelBuffer {
                let result = CIImage(cvPixelBuffer: buffer)
                mask = result
                    .transformed(by: .init(scaleX: source.width / result.extent.width,
                                          y: source.height / result.extent.height))
                    .transformed(by: .init(translationX: source.minX, y: source.minY))
                    .clampedToExtent()
                    .applyingGaussianBlur(sigma: max(0.5, source.width / 1600))
                    .cropped(to: source)
            } else {
                mask = CIImage(color: .black).cropped(to: source)
            }
        } catch {
            mask = CIImage(color: .black).cropped(to: source)
        }
        return Self.composite(.init(image: request.image, personMask: mask, style: request.style))
    }

    static func composite(_ request: CompositeRequest) -> CIImage {
        let source = request.image.extent
        let style = request.style
        let sourceFrame = style.placement.sourceFrame(sourceAspectRatio: source.width / max(1, source.height))
        guard sourceFrame.width > 0, sourceFrame.height > 0, style.target.width > 0, style.target.height > 0 else {
            return request.image
        }
        let scale = source.width / sourceFrame.width
        let toSource = CGAffineTransform(translationX: -sourceFrame.minX, y: -sourceFrame.minY)
            .concatenating(.init(scaleX: scale, y: scale))
            .concatenating(.init(translationX: source.minX, y: source.minY))
        let panel = style.panel(in: style.target)
        let sourcePanel = panel.applying(toSource)
        let upper = CGRect(x: style.target.minX, y: panel.maxY, width: style.target.width,
                           height: style.target.maxY - panel.maxY).applying(toSource)
        let radius = min(style.cornerRadius * scale, min(sourcePanel.width, sourcePanel.height) / 2)
        let panelMask = CIFilter(name: "CIRoundedRectangleGenerator", parameters: [
            "inputExtent": CIVector(cgRect: sourcePanel),
            "inputRadius": max(0, radius),
            "inputColor": CIColor.white
        ])?.outputImage ?? CIImage(color: .white).cropped(to: sourcePanel)
        let black = CIImage(color: .black).cropped(to: source)
        let mask = panelMask.cropped(to: sourcePanel).composited(over: black)
            .applyingFilter("CIMaximumCompositing", parameters: [
                kCIInputBackgroundImageKey: request.personMask.cropped(to: upper).composited(over: black)
            ])
        return request.image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: source),
            kCIInputMaskImageKey: mask
        ]).cropped(to: source)
    }
}
