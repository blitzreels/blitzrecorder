import Foundation

struct RecordingQualityPresentation {
    let settings: RecordingSettings

    var compactLabel: String {
        "Recording · \(settings.outputResolution.displayName) · \(settings.framesPerSecond) Source FPS"
    }

    var profileSummary: String {
        "\(settings.outputResolution.displayName) · \(settings.framesPerSecond) Source FPS · HEVC sources"
    }

    var sourceEncodingSummary: String {
        "HEVC · Screen \(bitrateLabel(settings.screenBitrate)) · Camera \(bitrateLabel(settings.cameraBitrate))"
    }

    var bitrateOverrideDetail: String {
        let mode = settings.customVideoBitrate == nil ? "Automatic" : "Custom"
        return "\(mode) · Default export \(bitrateLabel(settings.finalVideoBitrate)) · Source bitrates scale automatically"
    }

    private func bitrateLabel(_ bitrate: Int) -> String {
        let megabitsPerSecond = Double(bitrate) / 1_000_000
        if megabitsPerSecond.rounded() == megabitsPerSecond {
            return "\(Int(megabitsPerSecond)) Mbps"
        }
        return String(format: "%.1f Mbps", megabitsPerSecond)
    }
}
