import SwiftUI

enum MediaTimecode {
    struct Request {
        let time: Double
        let duration: Double
    }

    static func label(_ request: Request) -> String {
        let duration = seconds(request.duration)
        let time = min(duration, seconds(request.time))
        if duration >= 3_600 {
            let hourDigits = String(duration / 3_600).count
            return String(format: "%0*d:%02d:%02d", hourDigits, time / 3_600, time / 60 % 60, time % 60)
        }
        return String(format: "%02d:%02d", time / 60, time % 60)
    }

    private static func seconds(_ value: Double) -> Int {
        value.isFinite ? Int(min(9_999_999, max(0, value)).rounded(.down)) : 0
    }
}

struct BlitzTimecode: View {
    let configuration: MediaTimecode.Request

    var body: some View {
        Text(MediaTimecode.label(configuration))
            .monospacedDigit()
            .fixedSize()
    }
}
