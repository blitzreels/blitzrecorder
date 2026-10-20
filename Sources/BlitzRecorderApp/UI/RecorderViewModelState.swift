import BlitzRecorderCore
import Foundation
import Observation

/// Holds editor export progress, results, and follow-up state.
@Observable
@MainActor
final class EditorExportState {
    var isEditorExportPresented = false
    var isExportingVariants = false
    var variantExportIndex = 0
    var variantExportTotal = 0
    var variantExportURLs: [URL] = []
    var lastExportError: String?
    var lastExportSucceededURL: URL?
    var exportProgress: Double = 0
    var activeExportProjectURL: URL?
    var renderProgress: Double = 0
    var exportFollowUp: EditorExportFollowUp?
}

/// Holds preview canvas geometry and crop editing state.
@Observable
@MainActor
final class PreviewCanvasState {
    var screenSplitPreviewHeight: Double?
    var sideSplitPreviewWidth: Double?
    var previewCanvasFrame: CGRect = .zero
    var isCameraCropModeEnabled = false
    var isScreenCropModeEnabled = false
    var cropToolbarFrame: CGRect?
    var screenLayerFrame: CGRect?
}

/// Holds remote camera connection fields and preview state.
@Observable
@MainActor
final class RemoteCameraPreviewState {
    var directRemoteCameraHost: String = ""
    var directRemoteCameraPort: String = ""
    var hasRemoteCameraPreviewImage = false
    var remoteCameraPreviewAspectRatio: CGFloat = 9.0 / 16.0
    var remoteCameraPreviewFrameSize: (width: Int, height: Int)?
    var remoteCameraRefreshToken = 0
}

/// Holds screen source availability, suggestions, and target window tracking.
@Observable
@MainActor
final class ScreenSourceTrackingState {
    var unavailableScreenSource: ScreenSourceBinding?
    @ObservationIgnored var screenSourceAvailabilityTracker = ScreenSourceAvailabilityTracker()
    var suggestedScreenSource: ScreenSourceBinding?
    var autoSwitchNotice: ScreenSourceBinding?
    @ObservationIgnored var pendingFollowKey: String?
    @ObservationIgnored var autoSwitchNoticeTask: Task<Void, Never>?
    var dismissedScreenSuggestion: String?
    var targetWindowInfo: TargetWindowInfo?
    var targetWindowStatus: String = "Detecting target..."
    var targetWindowZoom: CGFloat = 1.0
    @ObservationIgnored var targetWindowZoomTask: Task<Void, Never>?
    @ObservationIgnored var pendingTargetWindowFitContext: ScheduledTargetWindowFitContext?
}

/// Holds project folder actions and video import state.
@Observable
@MainActor
final class ProjectLibraryActionState {
    var folderRecordTarget: ProjectFolderRecordTarget?
    var folderExportStatus: String?
    var folderMoveUndo: ProjectFolderMoveUndo?
    var folderPrompt: ProjectFolderPrompt?
    var folderNameDraft = ""
    var videoImportProgress: VideoProjectImporter.Progress?
    var videoImportError: String?
    @ObservationIgnored var videoImportTask: Task<Void, Never>?
}

/// Holds recording session timing, countdown, and capture completion state.
@Observable
@MainActor
final class RecordingSessionUIState {
    var elapsedSeconds: Int = 0
    var captureStopProgress: CaptureStopProgress?
    var finishingStartedAt: Date?
    var countdownRemaining: Int?
    var countdownSeconds = RecordingCountdownPreference().seconds
    var countdownTask: Task<Void, Never>?
    var pendingMicrophoneFallback: MissingPreferredMicrophone?
}
