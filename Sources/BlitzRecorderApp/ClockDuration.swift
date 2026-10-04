import Foundation

enum ClockDuration {
    static func label(_ seconds: Double) -> String {
        let total = max(0, Int((seconds.isFinite ? seconds : 0).rounded()))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remainder = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%d:%02d", minutes, remainder)
    }
}
