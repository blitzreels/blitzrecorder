import AppKit
import CoreImage
import CoreText

struct CaptionRenderRequest: Equatable {
    let text: String
    let style: CaptionStyle
    let size: CaptionSize
    let position: CaptionPosition
    let shadow: Bool
    let canvasSize: CGSize
    let normalizedFrame: CGRect?

    struct Input {
        let cue: CaptionCue
        let track: CaptionTrack
        let canvasSize: CGSize
    }

    init(_ input: Input) {
        text = input.cue.text
        style = input.track.style
        size = input.track.size
        position = input.track.position
        shadow = input.track.shadow
        canvasSize = input.canvasSize
        normalizedFrame = input.track.frame
    }
}

struct CaptionSprite {
    let image: CGImage
    let frame: CGRect

    func compositedImage(canvasSize: CGSize) -> CIImage {
        CIImage(cgImage: image).transformed(by: .init(
            translationX: frame.minX, y: canvasSize.height - frame.maxY))
    }
}

enum CaptionRenderer {
    private static let cache = NSCache<NSString, CGImage>()

    static func sprite(_ request: CaptionRenderRequest) -> CaptionSprite? {
        let canvas = request.canvasSize
        guard canvas.width.isFinite, canvas.height.isFinite, canvas.width >= 16, canvas.height >= 16,
              canvas.width <= 16_384, canvas.height <= 16_384, !request.text.isEmpty else { return nil }
        let key = "\(request.text)|\(request.style)|\(request.size)|\(request.shadow)|\(request.normalizedFrame?.size ?? .zero)|\(canvas)" as NSString
        let image: CGImage
        if let cached = cache.object(forKey: key) { image = cached }
        else {
            guard let rendered = draw(request) else { return nil }
            image = rendered
            cache.totalCostLimit = 32 * 1024 * 1024
            cache.countLimit = 64
            cache.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
        }
        if let frame = request.normalizedFrame {
            return .init(image: image, frame: CGRect(x: frame.minX * canvas.width, y: frame.minY * canvas.height,
                width: CGFloat(image.width), height: CGFloat(image.height)))
        }
        let margin = canvas.height * 0.08
        return .init(image: image, frame: CGRect(
            x: ((canvas.width - CGFloat(image.width)) / 2).rounded(),
            y: (request.position == .bottom ? canvas.height - margin - CGFloat(image.height) : margin).rounded(),
            width: CGFloat(image.width), height: CGFloat(image.height)))
    }

    private static func draw(_ request: CaptionRenderRequest) -> CGImage? {
        let shortSide = min(request.canvasSize.width, request.canvasSize.height)
        let padding = shortSide * 0.012
        let outer = shortSide * 0.01
        let available = request.normalizedFrame.map {
            CGSize(width: max(16, $0.width * request.canvasSize.width), height: max(16, $0.height * request.canvasSize.height))
        } ?? CGSize(width: request.canvasSize.width * 0.86, height: request.canvasSize.height * 0.3)
        let inset = min(padding + outer, min(available.width, available.height) * 0.1)
        let fitted = FittedTextLayout.resolve(.init(text: request.text,
            fontSize: shortSide * request.size.fraction, weight: .semibold, color: .white,
            alignment: .center, bounds: CGSize(width: max(1, available.width - 2 * inset),
                height: max(1, available.height - 2 * inset))))
        let text = fitted.text
        let setter = CTFramesetterCreateWithAttributedString(text)
        let textSize = fitted.size
        let imageSize = CGSize(width: floor(available.width),
            height: request.normalizedFrame == nil ? ceil(textSize.height + 2 * inset) : floor(available.height))
        guard let context = CGContext(data: nil, width: Int(imageSize.width), height: Int(imageSize.height),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        if request.shadow {
            context.setShadow(offset: CGSize(width: 0, height: -shortSide * 0.002),
                blur: shortSide * 0.004, color: CGColor(gray: 0, alpha: 0.7))
        }
        if request.style == .background {
            context.saveGState()
            context.setFillColor(CGColor(gray: 0, alpha: 0.82))
            context.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: imageSize).insetBy(dx: outer, dy: outer),
                cornerWidth: padding * 0.6, cornerHeight: padding * 0.6, transform: nil))
            context.fillPath()
            context.restoreGState()
        }
        let rect = CGRect(x: inset, y: (imageSize.height - textSize.height) / 2, width: textSize.width, height: textSize.height)
        let path = CGPath(rect: rect, transform: nil)
        if request.style == .outline {
            let border = NSMutableAttributedString(attributedString: text)
            border.addAttributes([.strokeWidth: 5, .strokeColor: NSColor.black],
                                 range: NSRange(location: 0, length: border.length))
            let borderSetter = CTFramesetterCreateWithAttributedString(border)
            CTFrameDraw(CTFramesetterCreateFrame(borderSetter, CFRange(), path, nil), context)
            context.setShadow(offset: .zero, blur: 0, color: nil)
        }
        CTFrameDraw(CTFramesetterCreateFrame(setter, CFRange(), path, nil), context)
        return context.makeImage()
    }
}
