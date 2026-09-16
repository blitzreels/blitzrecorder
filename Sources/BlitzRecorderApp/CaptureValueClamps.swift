import CoreGraphics

enum CaptureValueClamps {
    static func gain(_ gain: Double) -> Double {
        min(2.0, max(0.0, gain))
    }

    static func canvasPadding(_ padding: CGFloat) -> CGFloat {
        min(0.16, max(0, padding))
    }

    static func normalizedRect(_ rect: CGRect) -> CGRect {
        let rect = rect.standardized
        let x = min(1, max(0, rect.minX))
        let y = min(1, max(0, rect.minY))
        let maxX = min(1, max(x, rect.maxX))
        let maxY = min(1, max(y, rect.maxY))
        return CGRect(x: x, y: y, width: maxX - x, height: maxY - y)
    }

    static func isEffectivelyFullDisplayCrop(_ rect: CGRect) -> Bool {
        rect.minX <= 0.005
            && rect.minY <= 0.005
            && rect.width >= 0.99
            && rect.height >= 0.99
    }

    static func persistedScreenCrop(_ crop: CGRect) -> CGRect? {
        let clamped = normalizedRect(crop)
        return isEffectivelyFullDisplayCrop(clamped) ? nil : clamped
    }
}
