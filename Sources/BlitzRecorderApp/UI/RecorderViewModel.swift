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

    let previewStage: PreviewStageView
    let micLevels = TrackLevels()
    let sysLevels = TrackLevels()
    let transcriptionController = LocalTranscriptionController()

    var state: RecordingState = .idle
    var settings: RecordingSettings
    var detailMessage: String = ""
    var isExportingVariants = false
    var variantExportIndex = 0
    var variantExportTotal = 0
    var variantExportURLs: [URL] = []
    var lastExportError: String?
    var lastExportSucceededURL: URL?
    var lastExportedURL: URL?
    var lastExportedSourceTakeURL: URL?
    var lastExportWarning: String?
    var lastRecoveryOutput: RecordingRecoveryOutput?
    var lastPostRecordingProjectOutput: PostRecordingProjectOutput?
    var lastExportedProject: RecordingProject?
    var studioMode: StudioMode = .record {
        didSet {
            isShowingSettings = false
            guard oldValue != studioMode else { return }
            onStudioModeChanged?(studioMode)
        }
    }
    private(set) var isShowingSettings = false
    var selectedSettingsPane: SettingsPane = .recording

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

    var recentProjects: [RecordingProjectHistory.Entry] = []
    var projectLibraryError: String?

    var canShowProjects: Bool {
        state == .idle && (!recentProjects.isEmpty || projectTrash.canRestore)
    }

    var availableDisplays: [SourceOption] = []
    var availableScreenSources: [ScreenSourceOption] = []
    var availableCameras: [SourceOption] = []
    var availableMicrophones: [SourceOption] = []
    var directRemoteCameraHost: String = ""
    var directRemoteCameraPort: String = ""
    let remoteCameraPreviewSurface = CameraPreviewView()
    var hasRemoteCameraPreviewImage = false
    var remoteCameraPreviewAspectRatio: CGFloat = 9.0 / 16.0
    var remoteCameraPreviewFrameSize: (width: Int, height: Int)?

    var elapsedSeconds: Int = 0
    var renderProgress: Double = 0
    let elapsedClock = RecordingElapsedClock()

    @ObservationIgnored var onPresentSettings: ((SettingsPane?) -> Void)?
    @ObservationIgnored var onProjectOpened: (() -> Void)?
    @ObservationIgnored var onFillEditorWindow: (() -> Void)?
    @ObservationIgnored var onStudioModeChanged: ((StudioMode) -> Void)?
    @ObservationIgnored var onEditorHistoryChanged: (() -> Void)?
    @ObservationIgnored var automaticTitleTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored var editorHistory = EditorProjectHistory()
    var editorHistoryRevision = 0
    var inspectorSelection: RecorderInspectorSelection = .canvas
    var projectLibraryNavigation = ProjectLibraryNavigationState()
    let projectTrash = ProjectLibraryTrashController(operations: .live)
    var screenSplitPreviewHeight: Double?
    var previewCanvasFrame: CGRect = .zero
    var isCameraCropModeEnabled = false
    var isScreenCropModeEnabled = false
    var sceneLibraryRevision = 0
    var cropToolbarFrame: CGRect?
    var screenLayerFrame: CGRect?
    var showsFirstRunOnboarding: Bool
    var screenAccessAwaitingRestart = false
    var screenCaptureAreaSelection: ScreenCaptureAreaSelection = .fullDisplay
    var lastApplicationScreenSourceBinding: ScreenSourceBinding?
    var targetWindowInfo: TargetWindowInfo?
    var targetWindowStatus: String = "Detecting target..."
    var targetWindowZoom: CGFloat = 1.0
    @ObservationIgnored var targetWindowZoomTask: Task<Void, Never>?
    var permissionRefreshToken = 0
    var remoteCameraRefreshToken = 0

    var selectedSource: SourceSelection? {
        inspectorSelection.source.map(SourceSelection.init(source:))
    }

    var canUndoEditor: Bool {
        _ = editorHistoryRevision
        return studioMode == .edit && !isShowingSettings && editorHistory.canUndo
    }

    var canRedoEditor: Bool {
        _ = editorHistoryRevision
        return studioMode == .edit && !isShowingSettings && editorHistory.canRedo
    }

    var editorUndoTitle: String {
        editorHistory.undoTitle
    }

    var editorRedoTitle: String {
        editorHistory.redoTitle
    }

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
        _ = remoteCameraRefreshToken
        return coordinator.selectedRemoteCameraCapabilities()
    }

    var selectedRemoteCameraTelemetry: RemoteCameraTelemetry? {
        _ = remoteCameraRefreshToken
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
        _ = remoteCameraRefreshToken
        return coordinator.selectedRemoteCameraName()
    }

    var selectedRemoteCameraStatus: String? {
        _ = remoteCameraRefreshToken
        return coordinator.selectedRemoteCameraStatus()
    }

    var selectedRemoteCameraDeviceDescription: String {
        _ = remoteCameraRefreshToken
        return coordinator.selectedRemoteCameraDeviceDescription()
    }

    var selectedRemoteCameraReviewStatus: String {
        RemoteCameraReviewStatus.text(health: selectedRemoteCameraTelemetry?.previewHealth)
    }

    var isRemoteCameraSelected: Bool {
        _ = remoteCameraRefreshToken
        return coordinator.isRemoteCameraSelected
    }

    var localCameraOptions: [SourceOption] {
        availableCameras.filter { !RemoteCameraProviderID.isRemote($0.id) }
    }

    var remoteCameraOptions: [SourceOption] {
        availableCameras.filter { RemoteCameraProviderID.isRemote($0.id) }
    }

    var remoteCameraDeviceSummaries: [RemoteCameraDeviceSummary] {
        _ = remoteCameraRefreshToken
        return coordinator.remoteCameraDeviceSummaries()
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
        self.targetWindowZoom = coordinator.settings.screenWindowZoom
        previewStage.sceneID = coordinator.selectedSceneIDForCurrentLayout()
        self.showsFirstRunOnboarding = ProcessInfo.processInfo.environment["BLITZRECORDER_FORCE_ONBOARDING"] == "1"
            || !UserDefaults.standard.bool(forKey: Self.firstRunOnboardingKey)
        transcriptionController.onTranscriptionCompleted = { [weak self] completion in
            self?.generateAutomaticProjectTitle(completion)
        }
        refreshRecentProjects()
        syncScreenCaptureAreaSelection()
        elapsedClock.onElapsedSecondsChanged = { [weak self] elapsedSeconds in
            self?.elapsedSeconds = elapsedSeconds
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
            self?.cropToolbarFrame = frame
        }
        previewStage.onScreenLayerFrameChanged = { [weak self] frame in
            self?.screenLayerFrame = frame
        }
        previewStage.onCanvasFrameChanged = { [weak self] frame in
            self?.previewCanvasFrame = frame
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
        previewStage.onCameraCropChanged = { [weak self] amount, position in
            guard let self, self.canApplyCanvasEdit else { return }
            self.coordinator.setCameraCropAmount(amount)
            self.coordinator.setCameraCropPosition(position)
            self.settings = self.coordinator.settings
            self.previewStage.cameraCropAmount = self.coordinator.settings.cameraCropAmount
            self.previewStage.cameraCropPosition = self.coordinator.settings.cameraCropPosition
        }
        previewStage.onScreenCropChanged = { [weak self] crop in
            guard let self, self.canApplyCanvasEdit else { return }
            self.coordinator.setScreenCrop(crop)
            self.coordinator.endScreenCropEditing()
            self.settings = self.coordinator.settings
            self.previewStage.screenCrop = self.coordinator.settings.screenCrop
            self.isScreenCropModeEnabled = false
            self.screenCaptureAreaSelection = self.settings.screenCrop == nil ? .fullDisplay : .manualCrop
        }
        previewStage.onScreenCropPanRequested = { [weak self] in
            guard let self, self.canApplyCanvasEdit else { return }
            self.beginScreenCropMode()
        }
    }

}
