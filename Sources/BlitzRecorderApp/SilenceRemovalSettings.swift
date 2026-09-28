import Foundation

struct SilenceRemovalSettings: Codable, Equatable, Sendable {
    var intensity: Double
    var threshold: Double
    var automaticThreshold: Bool
    var minimumDuration: Double
    var paddingBefore: Double
    var paddingAfter: Double
    var linkedPadding: Bool
    var minimumAudio: Double
    var customized: Bool

    static let standard = Self(intensity: 1, threshold: -42, automaticThreshold: true,
        minimumDuration: 0.5, paddingBefore: 0.3, paddingAfter: 0.3,
        linkedPadding: true, minimumAudio: 0, customized: false)

    var sanitized: Self {
        var value = self
        value.intensity = intensity.isFinite ? min(3, max(0, intensity.rounded())) : 1
        value.threshold = threshold.isFinite ? min(-15, max(-70, threshold)) : -42
        value.minimumDuration = minimumDuration.isFinite ? min(3, max(0.1, minimumDuration)) : 0.5
        value.paddingBefore = paddingBefore.isFinite ? min(1, max(0, paddingBefore)) : 0.3
        value.paddingAfter = paddingAfter.isFinite ? min(1, max(0, paddingAfter)) : 0.3
        value.minimumAudio = minimumAudio.isFinite ? min(0.5, max(0, minimumAudio)) : 0
        return value
    }
}
