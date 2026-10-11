import AppKit
import CoreImage
import CoreText

struct TimelineOverlayImageRequest: Equatable {
    let overlay: TextOverlay
    let size: CGSize
}

struct TimelineSceneRequest {
    let scene: RecordingScene
    let edits: TimelineEdits
    let time: Double
}

enum TimelineOverlayRenderer {
    private static let images = NSCache<NSString, CGImage>()

    static func scene(_ request: TimelineSceneRequest) -> RecordingScene {
        guard request.edits.zoom.isActive else { return request.scene }
        var scene = request.scene
        let zoom = request.edits.zoom.sample(at: request.time)
        scene.screenCropAmount = CGPoint(x: zoom.amount, y: zoom.amount)
        scene.screenCropPosition = zoom.position
        if request.edits.cameraFollowsZoom {
            scene = CameraZoomMotion.scene(.init(scene: scene, zoom: zoom, intensity: request.edits.zoom.intensity))
        }
        return scene
    }

    static func image(_ request: TimelineOverlayImageRequest) -> CGImage? {
        let overlay = request.overlay
        let size = request.size
        guard size.width > 0, size.height > 0, !overlay.text.isEmpty else { return nil }
        let key = "\(size)|\(overlay.text)|\(overlay.frame)|\(overlay.style)" as NSString
        if let image = images.object(forKey: key) { return image }
        guard let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let frame = CGRect(
            x: overlay.frame.minX * size.width,
            y: (1 - overlay.frame.maxY) * size.height,
            width: overlay.frame.width * size.width,
            height: overlay.frame.height * size.height
        )
        if overlay.style.background != .none {
            context.setFillColor(CGColor(gray: 0.04, alpha: 0.82))
            let radius = overlay.style.background == .pill ? min(frame.height / 3, 24) : 6
            context.addPath(CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.fillPath()
        }
        let weight: NSFont.Weight = switch overlay.style.weight {
        case .black: .black
        case .bold: .bold
        case .semibold: .semibold
        case .regular: .regular
        }
        let hex = UInt32(overlay.style.colorHex.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0xFFFFFF
        let color = NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                            green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
        let inset = frame.insetBy(dx: min(12, frame.width * 0.06), dy: min(4, frame.height * 0.06))
        let alignment: NSTextAlignment = switch overlay.style.alignment {
        case .leading: .left
        case .center: .center
        case .trailing: .right
        }
        let fitted = FittedTextLayout.resolve(.init(text: overlay.text,
            fontSize: min(size.height * overlay.style.size, frame.height * 0.55), weight: weight,
            color: color, alignment: alignment, bounds: inset.size))
        let setter = CTFramesetterCreateWithAttributedString(fitted.text)
        let textRect = CGRect(x: inset.minX, y: inset.midY - fitted.size.height / 2,
            width: inset.width, height: fitted.size.height)
        context.setShadow(offset: CGSize(width: 0, height: -2), blur: 4, color: CGColor(gray: 0, alpha: 0.6))
        let textFrame = CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: textRect, transform: nil), nil)
        CTFrameDraw(textFrame, context)
        guard let image = context.makeImage() else { return nil }
        images.totalCostLimit = 64 * 1024 * 1024
        images.setObject(image, forKey: key, cost: Int(size.width * size.height * 4))
        return image
    }
}
