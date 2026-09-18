import CoreGraphics
import Foundation

enum EditorTimelineZoom {
    struct Request {
        let value: Double
        let duration: Double
    }

    static let minimum = 0.25

    static func maximum(for duration: Double) -> Double {
        guard duration.isFinite else { return 16 }
        return max(16, min(16_384, duration * 2))
    }

    static func clamp(_ request: Request) -> Double {
        min(max(request.value.isFinite ? request.value : 1, minimum), maximum(for: request.duration))
    }

    static func stepped(_ request: Request, factor: Double) -> Double {
        clamp(.init(value: request.value * factor, duration: request.duration))
    }

    static func sliderValue(_ request: Request) -> Double {
        log2(clamp(request))
    }

    static func scale(_ request: Request) -> Double {
        clamp(.init(value: pow(2, request.value), duration: request.duration))
    }

    static func applying(_ command: EditorKeyboardCommand, value: Double, duration: Double) -> Double? {
        switch command {
        case .zoomIn:
            return stepped(.init(value: value, duration: duration), factor: 1.5)
        case .zoomOut:
            return stepped(.init(value: value, duration: duration), factor: 1 / 1.5)
        case .fit:
            return 1
        default:
            return nil
        }
    }

    static func fitDuration(anchor: Double, zoom: Double, current: Double) -> Double {
        if zoom > 1, anchor.isFinite, anchor > 0 { return anchor }
        return current.isFinite && current > 0 ? current : 0.5
    }

    static func anchoredFitDuration(currentAnchor: Double, oldDuration: Double, zoom: Double) -> Double {
        if zoom > 1, !(currentAnchor.isFinite && currentAnchor > 0),
            oldDuration.isFinite, oldDuration > 0
        {
            return oldDuration
        }
        return currentAnchor
    }
}

enum EditorTimelineScroll {
    static func clamped(offset: CGFloat, contentWidth: CGFloat, viewportWidth: CGFloat) -> CGFloat {
        guard offset.isFinite, contentWidth.isFinite, viewportWidth.isFinite else { return 0 }
        return min(max(0, offset), max(0, contentWidth - max(0, viewportWidth)))
    }

    static func centered(
        on displayTime: Double,
        pixelsPerSecond: CGFloat,
        contentWidth: CGFloat,
        viewportWidth: CGFloat
    ) -> CGFloat {
        let time = displayTime.isFinite ? displayTime : 0
        let pps = pixelsPerSecond.isFinite ? pixelsPerSecond : 0
        return clamped(
            offset: CGFloat(time) * pps - viewportWidth / 2,
            contentWidth: contentWidth,
            viewportWidth: viewportWidth
        )
    }
}

enum EditorTimelineRuler {
    struct LabelRequest {
        let time: Double
        let interval: Double
    }

    static func interval(for pixelsPerSecond: Double) -> Double {
        let intervals: [Double] = [
            0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1_800, 3_600,
        ]
        return intervals.first { $0 * pixelsPerSecond >= 80 } ?? 3_600
    }

    static func label(_ request: LabelRequest) -> String {
        let milliseconds = Int((max(0, request.time) * 1_000).rounded())
        let whole = String(format: "%02d:%02d", milliseconds / 60_000, milliseconds / 1_000 % 60)
        guard request.interval < 1 else { return whole }
        let digits = request.interval < 0.1 ? 2 : 1
        let fraction = milliseconds % 1_000 / (digits == 2 ? 10 : 100)
        return whole + String(format: ".%0*d", digits, fraction)
    }
}
