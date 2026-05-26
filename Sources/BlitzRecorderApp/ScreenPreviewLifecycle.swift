import Foundation

enum ScreenPreviewLifecycleAction: Equatable {
    case preserveHidden
    case reusePreserved
    case restart
}

enum ScreenPreviewLifecycle {
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
