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

    static func sliderValue(_ request: Request) -> Double {
        log2(clamp(request))
    }

    static func scale(_ request: Request) -> Double {
        clamp(.init(value: pow(2, request.value), duration: request.duration))
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
