import AppKit
import CoreImage
import QuartzCore

extension CanvasBackgroundStyle {
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
        let stops = gradientStops
        guard stops.count >= 2 else {
            return CIImage(color: CIColor(cgColor: solidCGColor)).cropped(to: rect)
        }

        var image = linearGradient(
            rect: rect,
            start: CGPoint(x: rect.minX, y: rect.minY),
            end: CGPoint(x: rect.maxX, y: rect.maxY),
            startColor: CIColor(cgColor: stops[0].cgColor),
            endColor: CIColor(cgColor: stops[1].cgColor)
        )

        guard stops.count > 2 else { return image }

        for (index, stop) in stops.dropFirst(2).enumerated() {
            let opacity = max(0.14, 0.46 - CGFloat(index) * 0.08)
            let start = index.isMultiple(of: 2)
                ? CGPoint(x: rect.minX, y: rect.maxY)
                : CGPoint(x: rect.maxX, y: rect.minY)
            let end = index.isMultiple(of: 2)
                ? CGPoint(x: rect.maxX, y: rect.minY)
                : CGPoint(x: rect.minX, y: rect.maxY)
            let accent = linearGradient(
                rect: rect,
                start: start,
                end: end,
                startColor: CIColor(cgColor: stop.withAlphaComponent(opacity).cgColor),
                endColor: CIColor(red: 0, green: 0, blue: 0, alpha: 0)
            )
            image = accent.composited(over: image)
        }

        if let glowColor = stops.last {
            let glow = radialGradient(
                rect: rect,
                center: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.78),
                radius: max(rect.width, rect.height) * 0.84,
                color: CIColor(cgColor: glowColor.withAlphaComponent(0.28).cgColor)
            )
            image = glow.composited(over: image)
        }

        return image.cropped(to: rect)
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

    private func linearGradient(
        rect: CGRect,
        start: CGPoint,
        end: CGPoint,
        startColor: CIColor,
        endColor: CIColor
    ) -> CIImage {
        guard let filter = CIFilter(name: "CILinearGradient") else {
            return CIImage(color: startColor).cropped(to: rect)
        }
        filter.setValue(CIVector(cgPoint: start), forKey: "inputPoint0")
        filter.setValue(CIVector(cgPoint: end), forKey: "inputPoint1")
        filter.setValue(startColor, forKey: "inputColor0")
        filter.setValue(endColor, forKey: "inputColor1")
        return filter.outputImage?.cropped(to: rect) ?? CIImage(color: startColor).cropped(to: rect)
    }

    private func radialGradient(rect: CGRect, center: CGPoint, radius: CGFloat, color: CIColor) -> CIImage {
        guard let filter = CIFilter(name: "CIRadialGradient") else {
            return CIImage(color: color).cropped(to: rect)
        }
        filter.setValue(CIVector(cgPoint: center), forKey: "inputCenter")
        filter.setValue(max(1, radius * 0.06), forKey: "inputRadius0")
        filter.setValue(max(1, radius), forKey: "inputRadius1")
        filter.setValue(color, forKey: "inputColor0")
        filter.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: 0), forKey: "inputColor1")
        return filter.outputImage?.cropped(to: rect) ?? CIImage(color: color).cropped(to: rect)
    }
}
