import AppKit
import AVFoundation
import BlitzRecorderCore
import Foundation
import Observation
import QuartzCore

@Observable
@MainActor
final class RecorderViewModel {
    typealias StudioMode = RecorderStudioMode

    static let firstRunOnboardingKey = "onboarding.capturePermissions.v1"

    let coordinator: RecorderCoordinator
    let accessController: AccessController
    let exports = EditorExportState()
    let canvas = PreviewCanvasState()
    let remoteCameraPreview = RemoteCameraPreviewState()
    let screenSource = ScreenSourceTrackingState()
    let libraryActions = ProjectLibraryActionState()
    let session = RecordingSessionUIState()

    let previewStage: PreviewStageView
    let micLevels = TrackLevels()
    let sysLevels = TrackLevels()
    var transcriptionController: LocalTranscriptionController { coordinator.transcription }

    var state: RecordingState = .idle
    var settings: RecordingSettings
    var detailMessage: String = ""
    var screenWindowFitMessage: String?
    var showsScreenSourcePicker = false
    var isLivePreviewEnabled = LivePreviewPreference().isEnabled
    var lastExportedURL: URL?
    var lastExportedSourceTakeURL: URL?
    var lastExportWarning: String?
    var lastRecoveryOutput: RecordingRecoveryOutput?
    var lastPostRecordingProjectOutput: PostRecordingProjectOutput?
    var lastExportedProject: RecordingProject?
    var studioMode: StudioMode = .projects {
        didSet {
            isShowingSettings = false
            onEditorHistoryChanged?()
            guard oldValue != studioMode else { return }
            cancelCountdown()
            onStudioModeChanged?(studioMode)
        }
    }
    private(set) var isShowingSettings = false
    var selectedSettingsPane: SettingsPane = .recording

    var isEditorVisible: Bool { studioMode == .edit && !isShowingSettings }

    var settingsReturnTitle: String {
        switch studioMode {
        case .record: "Recorder"
        case .projects: "Projects"
        case .edit: "Editor"
        }
    }

    func showSettings(_ pane: SettingsPane?) {
        if let pane { selectedSettingsPane = pane }
        isShowingSettings = true
        onEditorHistoryChanged?()
    }

    func dismissSettings() {
        isShowingSettings = false
        onEditorHistoryChanged?()
    }

    var recentProjects: [RecordingProjectHistory.Entry] {
        get { coordinator.projectLibrary.entries }
        set { coordinator.projectLibrary.entries = newValue }
    }
    var projectLibraryError: String?

    var canShowProjects: Bool {
        !projectTrash.isWorking
    }

    var availableDisplays: [SourceOption] = []
    var availableScreenSources: [ScreenSourceOption] = []
    var availableCameras: [SourceOption] = []
    var availableMicrophones: [SourceOption] = []
    let remoteCameraPreviewSurface = CameraPreviewView()

    var followsActiveWindow = FollowActiveWindowPreference().isEnabled {
        didSet {
            FollowActiveWindowPreference().setEnabled(followsActiveWindow)
            screenSource.pendingFollowKey = nil
            screenSource.suggestedScreenSource = nil
            screenSource.dismissedScreenSuggestion = nil
        }
    }
    var exportProgressLabel: String { "\(Int((exports.exportProgress * 100).rounded()))%" }
    var isExporting: Bool { exports.activeExportProjectURL != nil || exports.isExportingVariants }
    /// This window's wait on the shared library refresh, so callers and tests can await it.
    @ObservationIgnored var projectRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var projectEditedObserver: NSObjectProtocol?
    @ObservationIgnored var isSavingProjectEdit = false
    let elapsedClock = RecordingElapsedClock()

    @ObservationIgnored var onPresentSettings: ((SettingsPane?) -> Void)?
    @ObservationIgnored var onRetryCameraPreview: (() -> Void)?
    var hasSeparateEditorWindow = false
    @ObservationIgnored var onOpenEditorWindow: ((EditorWindowRequest) -> Void)?
    @ObservationIgnored var onRouteEditorProject: ((RecordingProjectHistory.Entry) -> Bool)?
    @ObservationIgnored var onShowRecorder: (() -> Void)?
    @ObservationIgnored var onProjectOpened: (() -> Void)?
    @ObservationIgnored var onFillEditorWindow: (() -> Void)?
    @ObservationIgnored var onStudioModeChanged: ((StudioMode) -> Void)?
    @ObservationIgnored var onLivePreviewChanged: ((Bool) -> Void)?
    @ObservationIgnored var onEditorHistoryChanged: (() -> Void)?
    @ObservationIgnored var automaticTitleTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored var editorHistory = EditorProjectHistory()
    var editorHistoryRevision = 0
    var inspectorSelection: RecorderInspectorSelection = .canvas
    var projectLibraryNavigation = ProjectLibraryNavigationState()
    let projectTrash = ProjectLibraryTrashController(operations: .live)
    var sceneLibraryRevision = 0
    var showsFirstRunOnboarding: Bool
    var screenAccessAwaitingRestart = false
    var screenCaptureAreaSelection: ScreenCaptureAreaSelection = .fullDisplay
    var lastApplicationScreenSourceBinding: ScreenSourceBinding?
    @ObservationIgnored var permissionRequestTask: Task<Void, Never>?
    @ObservationIgnored var permissionRequestID: UUID?
    var isRequestingPermissions = false
    var permissionRefreshToken = 0

    var selectedSource: SourceSelection? {
        inspectorSelection.source.map(SourceSelection.init(source:))
    }

    var canUndoEditor: Bool {
        _ = editorHistoryRevision
        if studioMode == .projects && !isShowingSettings { return transcriptUndoManager.canUndo }
        return studioMode == .edit && !isShowingSettings && editorHistory.canUndo
    }

    var canRedoEditor: Bool {
        _ = editorHistoryRevision
        if studioMode == .projects && !isShowingSettings { return transcriptUndoManager.canRedo }
        return studioMode == .edit && !isShowingSettings && editorHistory.canRedo
    }

    var editorUndoTitle: String {
        if studioMode == .projects { return transcriptUndoManager.undoMenuItemTitle }
        return editorHistory.undoTitle
    }

    var editorRedoTitle: String {
        if studioMode == .projects { return transcriptUndoManager.redoMenuItemTitle }
        return editorHistory.redoTitle
    }

    @ObservationIgnored let transcriptUndoManager = UndoManager()

    var selectedLayer: SceneLayerKind {
        inspectorSelection.sceneLayer ?? previewStage.selectedLayer
    }

    var isBackgroundLayerSelected: Bool {
        inspectorSelection == .canvas
    }

    var idleStatusMessage: String? {
        RecorderStudioEditPolicy.idleStatus(
            state: state,
            lastExportedURL: lastExportedURL,
            detailMessage: detailMessage
        )
    }

    var selectedMicrophoneDisplayName: String {
        RecorderStudioLabels.microphone(.init(
            selectedMicrophoneID: settings.selectedMicrophoneID,
            options: availableMicrophones,
            fallbackName: coordinator.selectedMicrophoneName()
        ))
    }

    var selectedCameraDisplayName: String {
        RecorderStudioLabels.camera(.init(
            isRemoteSelected: isRemoteCameraSelected,
            remoteName: selectedRemoteCameraName,
            selectedCameraID: settings.selectedCameraID,
            localOptions: localCameraOptions
        ))
    }

    var selectedScreenSourceDisplayName: String {
        RecorderStudioLabels.screenSource(.init(
            settings: settings,
            hasActiveSelection: coordinator.hasActiveScreenSourceSelection,
            options: availableScreenSources
        ))
    }

    var selectedRemoteCameraCapabilities: RemoteCameraCapabilities? {
        _ = remoteCameraPreview.remoteCameraRefreshToken
        return coordinator.selectedRemoteCameraCapabilities()
    }

    var selectedRemoteCameraTelemetry: RemoteCameraTelemetry? {
        _ = remoteCameraPreview.remoteCameraRefreshToken
        return coordinator.selectedRemoteCameraTelemetry()
    }

    var selectedRemoteCameraRotationDegrees: Int {
        RemoteCameraRotationPolicy.degrees(telemetry: selectedRemoteCameraTelemetry)
    }

    var selectedRemoteCameraUsesAutomaticRotation: Bool {
        RemoteCameraRotationPolicy.usesAutomaticRotation(telemetry: selectedRemoteCameraTelemetry)
    }

    var selectedRemoteCameraSupportedRotationDegrees: [Int] {
        RemoteCameraRotationPolicy.supportedDegrees(capabilities: selectedRemoteCameraCapabilities)
    }

    var selectedRemoteCameraName: String? {
        _ = remoteCameraPreview.remoteCameraRefreshToken
        return coordinator.selectedRemoteCameraName()
    }

    var selectedRemoteCameraStatus: String? {
        _ = remoteCameraPreview.remoteCameraRefreshToken
        return coordinator.selectedRemoteCameraStatus()
    }

    var selectedRemoteCameraDeviceDescription: String {
        _ = remoteCameraPreview.remoteCameraRefreshToken
        return coordinator.selectedRemoteCameraDeviceDescription()
    }

    var selectedRemoteCameraReviewStatus: String {
        RemoteCameraReviewStatus.text(health: selectedRemoteCameraTelemetry?.previewHealth)
    }

    var isRemoteCameraSelected: Bool {
        _ = remoteCameraPreview.remoteCameraRefreshToken
        return coordinator.isRemoteCameraSelected
    }

    var localCameraOptions: [SourceOption] {
        availableCameras.filter { !RemoteCameraProviderID.isRemote($0.id) }
    }

    var remoteCameraOptions: [SourceOption] {
        availableCameras.filter { RemoteCameraProviderID.isRemote($0.id) }
    }

    var remoteCameraDeviceSummaries: [RemoteCameraDeviceSummary] {
        _ = remoteCameraPreview.remoteCameraRefreshToken
        return coordinator.remoteCameraDeviceSummaries()
    }

    func stopObservingProjectEdits() {
        projectEditedObserver.map(NotificationCenter.default.removeObserver)
        projectEditedObserver = nil
    }

    init(
        coordinator: RecorderCoordinator,
        previewStage: PreviewStageView
    ) {
        self.coordinator = coordinator
        self.accessController = coordinator.accessController
        self.previewStage = previewStage
        self.settings = coordinator.settings
        self.inspectorSelection = RecorderInspectorSelection.initial(settings: coordinator.settings)
        self.screenSource.targetWindowZoom = coordinator.settings.screenWindowZoom
        previewStage.sceneID = coordinator.selectedSceneIDForCurrentLayout()
        self.showsFirstRunOnboarding = ProcessInfo.processInfo.environment["BLITZRECORDER_FORCE_ONBOARDING"] == "1"
            || !UserDefaults.standard.bool(forKey: Self.firstRunOnboardingKey)
        transcriptionController.addCompletionHandler(.init(owner: self) { [weak self] completion in
            self?.generateAutomaticProjectTitle(completion)
        })
        projectEditedObserver = NotificationCenter.default.addObserver(
            forName: .recordingProjectEdited, object: nil, queue: .main
        ) { [weak self] notification in
            guard let edit = notification.object as? RecordingProjectEdited else { return }
            MainActor.assumeIsolated { self?.adoptEditSavedElsewhere(edit) }
        }
        refreshRecentProjects()
        syncScreenCaptureAreaSelection()
        elapsedClock.onElapsedSecondsChanged = { [weak self] elapsedSeconds in
            self?.session.elapsedSeconds = elapsedSeconds
        }

        remoteCameraPreviewSurface.setMessage("Waiting for iPhone preview")
        if let selectedLayer = inspectorSelection.sceneLayer {
            previewStage.selectedLayer = selectedLayer
        }

        previewStage.onLayerSelected = { [weak self] kind in
            self?.selectLayer(kind)
        }
        previewStage.onBackgroundSelected = { [weak self] in
            self?.selectBackgroundLayer()
        }
        previewStage.onCropToolbarFrameChanged = { [weak self] frame in
            self?.canvas.cropToolbarFrame = frame
        }
        previewStage.onScreenLayerFrameChanged = { [weak self] frame in
            self?.canvas.screenLayerFrame = frame
        }
        previewStage.onCanvasFrameChanged = { [weak self] frame in
            self?.canvas.previewCanvasFrame = frame
        }
        previewStage.onSceneLayoutChanged = { [weak self] layout in
            guard let self else { return }
            guard self.canApplyCanvasEdit else {
                self.previewStage.cancelCanvasInteraction()
                self.previewStage.sceneLayout = self.coordinator.settings.sceneLayout
                return
            }
            self.coordinator.previewSceneLayout(layout)
        }
        previewStage.onSceneLayoutEditingEnded = { [weak self] layout in
            guard let self, self.canApplyCanvasEdit else { return }
            self.coordinator.setSceneLayout(layout)
            self.settings = self.coordinator.settings
            self.previewStage.sceneLayout = self.coordinator.settings.sceneLayout
        }
        previewStage.onLayerResizeEnded = { [weak self] layer in
            guard let self, self.canApplyCanvasEdit else { return }
            self.finishSceneLayerResize(layer)
        }
        previewStage.onCameraCropChanged = { [weak self] crop in
            guard let self, self.canApplyCanvasEdit else { return }
            self.coordinator.setCameraCrop(crop)
            self.settings = self.coordinator.settings
            self.previewStage.cameraContentMode = self.coordinator.settings.cameraContentMode
            self.previewStage.cameraCropAmount = self.coordinator.settings.cameraCropAmount
            self.previewStage.cameraCropPosition = self.coordinator.settings.cameraCropPosition
        }
        previewStage.onScreenCropChanged = { [weak self] crop in
            guard let self, self.canApplyCanvasEdit else { return }
            self.coordinator.setScreenCrop(crop)
            self.coordinator.endScreenCropEditing()
            self.settings = self.coordinator.settings
            self.previewStage.screenCrop = self.coordinator.settings.screenCrop
            self.canvas.isScreenCropModeEnabled = false
            self.screenCaptureAreaSelection = self.settings.screenCrop == nil ? .fullDisplay : .manualCrop
        }
        previewStage.onScreenCropPanRequested = { [weak self] in
            guard let self, self.canApplyCanvasEdit else { return }
            self.beginScreenCropMode()
        }
    }

}
