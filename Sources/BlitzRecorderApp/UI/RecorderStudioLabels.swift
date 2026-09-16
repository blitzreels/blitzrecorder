import Foundation

enum RecorderStudioLabels {
    struct CameraRequest {
        let isRemoteSelected: Bool
        let remoteName: String?
        let selectedCameraID: String?
        let localOptions: [SourceOption]
    }

    struct MicrophoneRequest {
        let selectedMicrophoneID: String?
        let options: [SourceOption]
        let fallbackName: String
    }

    struct ScreenSourceRequest {
        let settings: RecordingSettings
        let hasActiveSelection: Bool
        let options: [ScreenSourceOption]
    }

    static func camera(_ request: CameraRequest) -> String {
        if request.isRemoteSelected {
            return request.remoteName ?? "Remote iPhone"
        }
        if let selectedCameraID = request.selectedCameraID,
           let option = request.localOptions.first(where: { $0.id == selectedCameraID }) {
            return option.name
        }
        return "Default camera"
    }

    static func microphone(_ request: MicrophoneRequest) -> String {
        if let selectedMicrophoneID = request.selectedMicrophoneID,
           let option = request.options.first(where: { $0.id == selectedMicrophoneID }) {
            return option.name
        }
        return request.fallbackName
    }

    static func screenSource(_ request: ScreenSourceRequest) -> String {
        let needsPicker = request.settings.enabledSources.contains(.screen)
            || request.settings.enabledSources.contains(.systemAudio)
        if needsPicker, !request.hasActiveSelection {
            return "Choose screen source"
        }
        if request.settings.usesPickedScreenContent {
            return request.settings.screenSourceBinding?.displayName ?? "Picked screen content"
        }
        if let binding = request.settings.screenSourceBinding,
           let option = request.options.first(where: { $0.binding == binding }) {
            return option.title
        }
        return request.settings.screenSourceBinding?.displayName ?? "Display capture"
    }

    static let screenSelectedForSession = "Screen selected for this session."
    static let screenSourceSaved = "Screen source saved."

    static func screenPickerFailed(_ error: Error) -> String {
        "Screen picker failed: \(error.localizedDescription)"
    }

    static func screenSourceActivationMessage(
        usesPickedScreenContent: Bool,
        hasPersistentBinding: Bool
    ) -> String {
        if usesPickedScreenContent, hasPersistentBinding {
            return "Screen source saved. Using picker grant for this session."
        }
        return usesPickedScreenContent ? screenSelectedForSession : screenSourceSaved
    }
}
