import CoreGraphics
import Foundation

enum EditorSourceZoom {
    static func value(draft: Double?, amount: CGPoint) -> Double {
        draft ?? Double(max(amount.x, amount.y))
    }

    static func clamped(_ zoom: Double) -> Double {
        min(0.75, max(0, zoom))
    }

    static func amount(_ zoom: Double) -> CGPoint {
        CGPoint(x: zoom, y: zoom)
    }

    static func label(_ zoom: Double) -> String {
        let visibleFraction = max(0.25, 1 - zoom)
        return "\(Int((100 / visibleFraction).rounded()))%"
    }
}
