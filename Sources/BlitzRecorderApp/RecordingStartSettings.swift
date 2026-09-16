import Foundation

enum RecordingStartSettings {
    static func effective(
        _ settings: RecordingSettings,
        hasScreenCaptureAccess: Bool
    ) -> RecordingSettings {
        var recordingSettings = settings
        recordingSettings.savesSourceFiles = true
        if recordingSettings.enabledSources.contains(.systemAudio), !hasScreenCaptureAccess {
            recordingSettings.enabledSources.remove(.systemAudio)
        }
        return recordingSettings
    }
}
