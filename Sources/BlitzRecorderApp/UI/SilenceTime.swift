import Foundation

enum SilenceTime {
    static func label(_ seconds: Double) -> String {
        let time = max(0, seconds.isFinite ? seconds : 0)
        return String(format: "%d:%04.1f", Int(time) / 60, time.truncatingRemainder(dividingBy: 60))
    }
}
