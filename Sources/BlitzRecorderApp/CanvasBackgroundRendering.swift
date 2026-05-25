import AppKit
import CoreImage
import QuartzCore

extension CanvasBackgroundStyle {
    var gradientStartPoint: CGPoint {
        CGPoint(x: 0.08, y: 0.02)
    }

    var gradientEndPoint: CGPoint {
        CGPoint(x: 0.92, y: 1)
    }

    var previewColors: [CGColor] {
        gradientStops.map { $0.cgColor }
    }

    var previewLocations: [NSNumber] {
        let count = gradientStops.count
        guard count > 1 else { return [0] }
        return (0..<count).map { index in
            NSNumber(value: Double(index) / Double(count - 1))
        }
    }

    var solidCGColor: CGColor {
        gradientStops.last?.cgColor ?? NSColor.black.cgColor
    }

    func ciImage(in rect: CGRect) -> CIImage {
        guard rect.width > 0, rect.height > 0 else {
            return CIImage(color: CIColor(cgColor: solidCGColor)).cropped(to: rect)
        }

        let width = max(1, Int(rect.width.rounded(.up)))
        let height = max(1, Int(rect.height.rounded(.up)))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return CIImage(color: CIColor(cgColor: solidCGColor)).cropped(to: rect)
        }

        context.setFillColor(solidCGColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        if let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: previewColors as CFArray,
            locations: previewLocations.map { CGFloat(truncating: $0) }
        ) {
            let start = CGPoint(
                x: CGFloat(width) * gradientStartPoint.x,
                y: CGFloat(height) * gradientStartPoint.y
            )
            let end = CGPoint(
                x: CGFloat(width) * gradientEndPoint.x,
                y: CGFloat(height) * gradientEndPoint.y
            )
            context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }

        guard let cgImage = context.makeImage() else {
            return CIImage(color: CIColor(cgColor: solidCGColor)).cropped(to: rect)
        }
        return CIImage(cgImage: cgImage)
            .transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
            .cropped(to: rect)
    }

    private var gradientStops: [NSColor] {
        switch self {
        case .black:
            return [
                NSColor(calibratedWhite: 0.0, alpha: 1),
                NSColor(calibratedWhite: 0.0, alpha: 1)
            ]
        case .graphite:
            return [
                NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.07, alpha: 1),
                NSColor(calibratedRed: 0.15, green: 0.17, blue: 0.21, alpha: 1),
                NSColor(calibratedRed: 0.34, green: 0.37, blue: 0.42, alpha: 1),
                NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.11, alpha: 1),
                NSColor(calibratedRed: 0.52, green: 0.57, blue: 0.62, alpha: 1)
            ]
        case .aurora:
            return [
                NSColor(calibratedRed: 0.02, green: 0.07, blue: 0.10, alpha: 1),
                NSColor(calibratedRed: 0.12, green: 0.10, blue: 0.30, alpha: 1),
                NSColor(calibratedRed: 0.25, green: 0.16, blue: 0.48, alpha: 1),
                NSColor(calibratedRed: 0.04, green: 0.40, blue: 0.36, alpha: 1),
                NSColor(calibratedRed: 0.18, green: 0.82, blue: 0.65, alpha: 1),
                NSColor(calibratedRed: 0.03, green: 0.13, blue: 0.16, alpha: 1)
            ]
        case .ocean:
            return [
                NSColor(calibratedRed: 0.01, green: 0.06, blue: 0.14, alpha: 1),
                NSColor(calibratedRed: 0.02, green: 0.16, blue: 0.30, alpha: 1),
                NSColor(calibratedRed: 0.04, green: 0.38, blue: 0.56, alpha: 1),
                NSColor(calibratedRed: 0.08, green: 0.62, blue: 0.74, alpha: 1),
                NSColor(calibratedRed: 0.02, green: 0.08, blue: 0.18, alpha: 1)
            ]
        case .sunset:
            return [
                NSColor(calibratedRed: 0.08, green: 0.04, blue: 0.12, alpha: 1),
                NSColor(calibratedRed: 0.28, green: 0.08, blue: 0.18, alpha: 1),
                NSColor(calibratedRed: 0.68, green: 0.18, blue: 0.25, alpha: 1),
                NSColor(calibratedRed: 0.94, green: 0.42, blue: 0.22, alpha: 1),
                NSColor(calibratedRed: 0.98, green: 0.66, blue: 0.30, alpha: 1),
                NSColor(calibratedRed: 0.06, green: 0.05, blue: 0.14, alpha: 1)
            ]
        case .silver:
            return [
                NSColor(calibratedRed: 0.30, green: 0.35, blue: 0.42, alpha: 1),
                NSColor(calibratedRed: 0.68, green: 0.72, blue: 0.78, alpha: 1),
                NSColor(calibratedRed: 0.92, green: 0.94, blue: 0.96, alpha: 1),
                NSColor(calibratedRed: 0.50, green: 0.57, blue: 0.66, alpha: 1),
                NSColor(calibratedRed: 0.98, green: 0.99, blue: 1.0, alpha: 1)
            ]
        }
    }
}
