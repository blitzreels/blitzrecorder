import Foundation

enum ScreenPreviewLifecycleAction: Equatable {
    case preserveHidden
    case reusePreserved
    case restart
}

struct ScreenPreviewSourceAvailabilityRequest {
    let settings: RecordingSettings
    let hasPersistentScreenCaptureAccess: Bool
    let hasActivePickedContent: Bool
}

enum ScreenPreviewLifecycle {
    static func sourceIsAvailable(
        _ request: ScreenPreviewSourceAvailabilityRequest
    ) -> Bool {
        if request.settings.usesPickedScreenContent,
           request.hasActivePickedContent {
            return true
        }
        return request.hasPersistentScreenCaptureAccess
            && !request.settings.usesPickedScreenContent
            && request.settings.screenSourceBinding?.isConcreteSelection == true
    }

    static func action(
        settings: RecordingSettings,
        previewIsRunning: Bool,
        preservedSelectionRevision: Int?,
        currentSelectionRevision: Int
    ) -> ScreenPreviewLifecycleAction {
        let screenEnabled = settings.enabledSources.contains(.screen)
        let screenHidden = settings.hiddenSources.contains(.screen)

        if screenHidden {
            return .preserveHidden
        }

        if screenEnabled,
           previewIsRunning,
           preservedSelectionRevision == currentSelectionRevision {
            return .reusePreserved
        }

        return .restart
    }
}

enum ScreenPreviewFailureMessage {
    static func detailMessage(for error: Error, settings: RecordingSettings) -> String {
        let source = settings.screenSourceBinding?.displayName ?? "selected screen source"
        return "\(title(for: error, settings: settings)): \(source). \(error.localizedDescription)"
    }

    private static func title(for error: Error, settings: RecordingSettings) -> String {
        if case RecorderError.screenCapturePermissionRequired = error {
            return "Screen Recording permission required"
        }

        if case RecorderError.noDisplay = error {
            return "Selected display unavailable"
        }

        if case RecorderError.screenSourceUnavailable = error {
            switch settings.screenSourceBinding?.kind {
            case .application:
                return "Selected app unavailable"
            case .window:
                return "Selected window unavailable"
            case .display, .none:
                return "Screen source unavailable"
            }
        }

        return "Screen preview failed"
    }
}
