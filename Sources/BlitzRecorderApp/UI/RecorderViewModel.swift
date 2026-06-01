import AppKit
import AVFoundation
import BlitzRecorderCore
import Foundation
import Observation

enum SourceSelection: CaseIterable, Equatable {
    case screen
    case camera
    case microphone
    case systemAudio

    init(source: CaptureSource) {
        switch source {
        case .screen:
            self = .screen
        case .camera:
            self = .camera
        case .microphone:
            self = .microphone
        case .systemAudio:
            self = .systemAudio
        }
    }

    var source: CaptureSource {
        switch self {
        case .screen:
            return .screen
        case .camera:
            return .camera
        case .microphone:
            return .microphone
        case .systemAudio:
            return .systemAudio
        }
    }
}

enum ScreenCaptureAreaSelection: Equatable {
    case fullDisplay
    case activeWindow
    case manualCrop
}

@Observable
@MainActor
final class RecorderViewModel {
    private static let firstRunOnboardingKey = "onboarding.capturePermissions.v1"

    let coordinator: RecorderCoordinator
    let accessController: AccessController

    let previewStage: PreviewStageView
    let micLevels = TrackLevels()
    let sysLevels = TrackLevels()

    var state: RecordingState = .idle
    var settings: RecordingSettings
    var detailMessage: String = ""
    var lastExportedURL: URL?
    var lastExportedSourceTakeURL: URL?
    var lastExportWarning: String?
    var lastRecoveryOutput: RecordingRecoveryOutput?

    var availableDisplays: [SourceOption] = []
    var availableCameras: [SourceOption] = []
    var availableMicrophones: [SourceOption] = []
    var directRemoteCameraHost: String = ""
    var directRemoteCameraPort: String = ""
    let remoteCameraPreviewSurface = CameraPreviewView()
    var hasRemoteCameraPreviewImage = false
    var remoteCameraPreviewAspectRatio: CGFloat = 9.0 / 16.0

    var elapsedSeconds: Int = 0
    var renderProgress: Double = 0
    private var elapsedTimer: Timer?
    private var elapsedAccumulatedSeconds: TimeInterval = 0
    private var currentRecordingSegmentStartedAt: Date?

    var appTab: AppTab = .recorder
    var selectedSource: SourceSelection? = .screen
    var selectedLayer: SceneLayerKind = .camera
    var isCameraCropModeEnabled = false
    var isScreenCropModeEnabled = false
    var cropToolbarFrame: CGRect?
    var showsFirstRunOnboarding: Bool
    var screenAccessAwaitingRestart = false
    var screenCaptureAreaSelection: ScreenCaptureAreaSelection = .fullDisplay
    var targetWindowInfo: TargetWindowInfo?
    var targetWindowStatus: String = "Detecting target..."
    var targetWindowFitScale: CGFloat = 1.0
    private var permissionRefreshToken = 0
    private var remoteCameraRefreshToken = 0

    var idleStatusMessage: String? {
        guard state == .idle,
              lastExportedURL == nil,
              !detailMessage.isEmpty,
              !detailMessage.hasPrefix("Saved:") else { return nil }
        return detailMessage
    }

    var selectedMicrophoneDisplayName: String {
        if let selectedMicrophoneID = settings.selectedMicrophoneID,
           let option = availableMicrophones.first(where: { $0.id == selectedMicrophoneID }) {
            return option.name
        }
        return coordinator.selectedMicrophoneName()
    }

    var selectedCameraDisplayName: String {
        if isRemoteCameraSelected {
            return selectedRemoteCameraName ?? "Remote iPhone"
        }
        if let selectedCameraID = settings.selectedCameraID,
           let option = localCameraOptions.first(where: { $0.id == selectedCameraID }) {
            return option.name
        }
        return "Default camera"
    }

    var selectedRemoteCameraCapabilities: RemoteCameraCapabilities? {
        _ = remoteCameraRefreshToken
        return coordinator.selectedRemoteCameraCapabilities()
    }

    var selectedRemoteCameraTelemetry: RemoteCameraTelemetry? {
        _ = remoteCameraRefreshToken
        return coordinator.selectedRemoteCameraTelemetry()
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
        guard let health = selectedRemoteCameraTelemetry?.previewHealth,
              health.framesSent > 0 else {
            return "Waiting for iPhone video"
        }
        if health.isHealthy {
            return "Video looks good"
        }
        if let lastFrameAgeSeconds = health.lastFrameAgeSeconds, lastFrameAgeSeconds >= 2 {
            return "Waiting for iPhone video"
        }
        return "iPhone connected"
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

    var isSelectedLayerEnabled: Bool {
        settings.enabledSources.contains(selectedLayer.source)
    }

    var canEditScene: Bool {
        coordinator.allowsSceneChanges
    }

    var canManipulateCanvasItems: Bool {
        coordinator.allowsSceneChanges
    }

    var canEditCameraCrop: Bool {
        coordinator.allowsSceneChanges
    }

    var currentScreenSourceAspectRatio: CGFloat {
        coordinator.currentScreenSourceAspectRatio()
    }

    var currentCameraSourceAspectRatio: CGFloat {
        coordinator.currentCameraSourceAspectRatio()
    }

    var recordingReadiness: RecordingReadiness {
        coordinator.recordingReadiness()
    }

    var currentScenes: [RecordingSceneDefinition] {
        coordinator.scenesForCurrentLayout()
    }

    var selectedSceneID: UUID? {
        coordinator.selectedSceneIDForCurrentLayout()
    }

    var selectedSceneName: String {
        coordinator.selectedSceneName()
    }

    var permissionStatusRows: [PermissionStatusRow] {
        _ = permissionRefreshToken
        let readiness = recordingReadiness
        var rows = CaptureSource.allCases.map { source in
            let isActive = settings.enabledSources.contains(source)
            return PermissionStatusRow(
                title: source.rawValue,
                symbol: source.symbolName,
                status: isActive ? PermissionGate.status(for: source, settings: settings) : "not used by current setup",
                isActive: isActive,
                isBlocked: readiness.blockers.contains { $0.source == source },
                isOptional: false,
                source: source
            )
        }
        let hasAccessibilityAccess = PermissionGate.hasAccessibilityAccess
        rows.append(PermissionStatusRow(
            title: "Accessibility",
            symbol: "accessibility",
            status: hasAccessibilityAccess ? "allowed" : "optional for target-window controls",
            isActive: hasAccessibilityAccess,
            isBlocked: false,
            isOptional: true,
            source: nil
        ))
        return rows
    }

    var permissionIssueCount: Int {
        recordingReadiness.blockers.count
            + (accessController.canRenderExport ? 0 : 1)
    }

    var permissionSetupSummary: String {
        let readiness = recordingReadiness
        if readiness.isReady {
            return "All selected sources are ready."
        }
        if settings.enabledSources.isEmpty {
            return "Choose at least one source before recording."
        }
        return readiness.blockers.first?.sentence ?? readiness.detail
    }

    var primaryPermissionActionTitle: String {
        if shouldSuggestScreenPicker {
            return "Pick Screen"
        }
        if recordingReadiness.blockers.contains(where: { $0.source == .camera || $0.source == .microphone }) {
            return "Request Access"
        }
        if recordingReadiness.blockers.contains(where: { $0.source == .screen || $0.source == .systemAudio }) {
            return "Open Settings"
        }
        return "Check Access"
    }

    var shouldSuggestScreenPicker: Bool {
        recordingReadiness.blockers.contains { $0.source == .screen }
            && settings.enabledSources.contains(.screen)
            && !settings.usesPickedScreenContent
            && !settings.enabledSources.contains(.systemAudio)
    }

    var isPersistentScreenCaptureAccessActive: Bool {
        coordinator.hasScreenCaptureAccess()
    }

    var needsPersistentScreenCaptureAccess: Bool {
        let needsScreen = settings.enabledSources.contains(.screen) && !settings.usesPickedScreenContent
        let needsSystemAudio = settings.enabledSources.contains(.systemAudio)
        return (needsScreen || needsSystemAudio) && !isPersistentScreenCaptureAccessActive
    }

    init(
        coordinator: RecorderCoordinator,
        previewStage: PreviewStageView
    ) {
        self.coordinator = coordinator
        self.accessController = coordinator.accessController
        self.previewStage = previewStage
        self.settings = coordinator.settings
        self.showsFirstRunOnboarding = ProcessInfo.processInfo.environment["BLITZRECORDER_FORCE_ONBOARDING"] == "1"
            || !UserDefaults.standard.bool(forKey: Self.firstRunOnboardingKey)
        syncScreenCaptureAreaSelection()

        remoteCameraPreviewSurface.setMessage("Waiting for iPhone preview")

        previewStage.onLayerSelected = { [weak self] kind in
            self?.selectLayer(kind)
        }
        previewStage.onCropButtonPressed = { [weak self] kind in
            switch kind {
            case .screen:
                self?.beginScreenCropMode()
            case .camera:
                self?.beginCameraCropMode()
            }
        }
        previewStage.onCropToolbarFrameChanged = { [weak self] frame in
            self?.cropToolbarFrame = frame
        }
        previewStage.onSceneLayoutChanged = { [weak self] layout in
            guard let self else { return }
            guard self.canManipulateCanvasItems else {
                self.previewStage.sceneLayout = self.coordinator.settings.sceneLayout
                return
            }
            self.coordinator.setSceneLayout(layout)
            self.settings = self.coordinator.settings
            self.previewStage.sceneLayout = self.coordinator.settings.sceneLayout
        }
        previewStage.onCameraCropChanged = { [weak self] amount, position in
            guard let self else { return }
            self.coordinator.setCameraCropAmount(amount)
            self.coordinator.setCameraCropPosition(position)
            self.settings = self.coordinator.settings
            self.previewStage.cameraCropAmount = self.coordinator.settings.cameraCropAmount
            self.previewStage.cameraCropPosition = self.coordinator.settings.cameraCropPosition
        }
        previewStage.onScreenCropChanged = { [weak self] crop in
            guard let self else { return }
            self.coordinator.setScreenCrop(crop)
            self.coordinator.endScreenCropEditing()
            self.settings = self.coordinator.settings
            self.previewStage.screenCrop = self.coordinator.settings.screenCrop
            self.isScreenCropModeEnabled = false
            self.screenCaptureAreaSelection = self.settings.screenCrop == nil ? .fullDisplay : .manualCrop
        }
    }

    func applyState(_ newState: RecordingState) {
        let previousState = state
        state = newState
        syncPreviewInteractionState()
        switch newState {
        case .starting:
            elapsedAccumulatedSeconds = 0
            elapsedSeconds = 0
            renderProgress = 0
            detailMessage = "Not recording yet. Hang on while BlitzRecorder prepares capture."
            currentRecordingSegmentStartedAt = nil
            lastExportedURL = nil
            lastExportedSourceTakeURL = nil
            lastExportWarning = nil
            lastRecoveryOutput = nil
            stopElapsedTimer()
        case .recording:
            if previousState == .idle || previousState == .starting || previousState == .finishing {
                elapsedAccumulatedSeconds = 0
                elapsedSeconds = 0
                renderProgress = 0
            }
            currentRecordingSegmentStartedAt = Date()
            updateElapsedSeconds()
            startElapsedTimer()
        case .paused:
            updateElapsedSeconds()
            commitCurrentRecordingSegment()
            stopElapsedTimer()
        case .finishing:
            updateElapsedSeconds()
            commitCurrentRecordingSegment()
            stopElapsedTimer()
            renderProgress = 0
        case .idle:
            stopElapsedTimer()
            elapsedAccumulatedSeconds = 0
            currentRecordingSegmentStartedAt = nil
            elapsedSeconds = 0
            renderProgress = 0
        }
    }

    func applyMessage(_ message: String) {
        detailMessage = message
    }

    func applySavedRecordingOutput(_ output: SavedRecordingOutput) {
        lastExportedURL = output.url
        lastExportedSourceTakeURL = output.sourceDirectory
        lastExportWarning = output.warning
        lastRecoveryOutput = nil
    }

    func applyRecoveryOutput(_ output: RecordingRecoveryOutput) {
        lastRecoveryOutput = output
        lastExportedURL = nil
        lastExportedSourceTakeURL = nil
        lastExportWarning = nil
    }

    func applyRenderProgress(_ progress: Double) {
        renderProgress = min(1, max(0, progress))
    }

    func appendAudioLevel(_ level: Float, source: CaptureSource) {
        switch source {
        case .microphone: micLevels.append(level)
        case .systemAudio: sysLevels.append(level)
        case .screen, .camera: break
        }
    }

    func syncSettings() {
        settings = coordinator.settings
        syncScreenCaptureAreaSelection()
        syncSelectedSource()
        syncPreviewInteractionState()
        previewStage.captureLayout = coordinator.settings.layout
        previewStage.sceneLayout = coordinator.settings.sceneLayout
        previewStage.enabledSources = coordinator.settings.visibleSources
        previewStage.screenSourceAspectRatio = coordinator.currentScreenSourceAspectRatio()
        previewStage.screenCrop = coordinator.settings.screenCrop
        previewStage.cameraCropAmount = coordinator.settings.cameraCropAmount
        previewStage.cameraCropPosition = coordinator.settings.cameraCropPosition
        previewStage.showsRuleOfThirdsOverlay = coordinator.settings.showsRuleOfThirdsOverlay
        previewStage.socialSafeZoneOverlay = coordinator.settings.socialSafeZoneOverlay
        previewStage.canvasBackgroundStyle = coordinator.settings.canvasBackgroundStyle
        previewStage.canvasPadding = coordinator.settings.canvasPadding
    }

    func refreshTargetWindow() {
        do {
            targetWindowInfo = try coordinator.targetWindowInfo()
            targetWindowStatus = ""
        } catch {
            targetWindowInfo = nil
            targetWindowStatus = error.localizedDescription
        }
    }

    func refreshSources() async {
        let displays = await coordinator.availableDisplays()
        availableDisplays = displays
        availableCameras = coordinator.availableCameras()
        availableMicrophones = coordinator.availableMicrophones()
    }

    func refreshRemoteCameraState() {
        settings = coordinator.settings
        availableCameras = coordinator.availableCameras()
        remoteCameraRefreshToken += 1
    }

    func startRemoteCameraDiscovery() {
        coordinator.startRemoteCameraDiscoveryIfNeeded()
        refreshRemoteCameraState()
    }

    func toggleSource(_ source: CaptureSource) {
        if source == .screen, !isSourceConfigured(.screen) {
            pickAndEnableScreenSource()
            return
        }

        if isSourceConfigured(source) {
            coordinator.removeSource(source)
        } else {
            coordinator.addSource(source)
        }
        syncSettings()
    }

    func setSourceVisible(_ source: CaptureSource, visible: Bool) {
        if source == .screen,
           visible,
           (!isSourceConfigured(.screen)
            || (!coordinator.settings.usesPickedScreenContent && !coordinator.hasScreenCaptureAccess())) {
            pickAndEnableScreenSource()
            return
        }

        coordinator.setSource(source, enabled: visible)
        syncSettings()
    }

    func removeSource(_ source: CaptureSource) {
        coordinator.removeSource(source)
        syncSettings()
    }

    func isSourceConfigured(_ source: CaptureSource) -> Bool {
        settings.enabledSources.contains(source) || settings.hiddenSources.contains(source)
    }

    func isSourceVisible(_ source: CaptureSource) -> Bool {
        settings.visibleSources.contains(source)
    }

    func setLayout(_ layout: CaptureLayout) {
        coordinator.setLayout(layout)
        syncSettingsAfterSceneChange()
    }

    func selectScene(_ id: UUID) {
        coordinator.selectScene(id: id)
        syncSettingsAfterSceneChange()
    }

    func setScenePreset(_ preset: ScenePreset) {
        if preset.enablesScreenSource,
           !isSourceConfigured(.screen),
           !coordinator.settings.usesPickedScreenContent,
           !coordinator.hasScreenCaptureAccess() {
            Task {
                do {
                    try await coordinator.pickScreenSource()
                    coordinator.applyScenePreset(preset)
                    syncSettingsAfterSceneChange()
                    detailMessage = "Screen selected for this session."
                } catch {
                    detailMessage = "Screen picker failed: \(error.localizedDescription)"
                }
            }
            return
        }

        coordinator.applyScenePreset(preset)
        syncSettingsAfterSceneChange()
    }

    var screenSplitHeight: Double {
        Double(settings.sceneLayout.screenSplitHeight ?? SceneLayout.defaultScreenSplitHeight)
    }

    func setScreenSplitHeight(_ height: Double) {
        coordinator.setScreenSplitHeight(CGFloat(height))
        syncSettingsAfterSceneChange()
    }

    func fitFrontWindowForShorts() {
        coordinator.fitFrontWindowForShorts(scale: targetWindowFitScale)
        syncSettings()
        if settings.screenCrop != nil {
            screenCaptureAreaSelection = .activeWindow
        }
        refreshTargetWindow()
    }

    func fitScreenToAvailableSlot() {
        coordinator.fitScreenToAvailableSlot()
        syncSettingsAfterSceneChange()
    }

    func fitScreenItemToFrontWindow() {
        coordinator.fitScreenItemToFrontWindow()
        syncSettings()
        if settings.screenCrop != nil {
            screenCaptureAreaSelection = .activeWindow
        }
        refreshTargetWindow()
    }

    func fitFrontWindowForShorts(scale: CGFloat) {
        targetWindowFitScale = clampedTargetWindowFitScale(scale)
        coordinator.fitFrontWindowForShorts(scale: targetWindowFitScale)
        syncSettings()
        if settings.screenCrop != nil {
            screenCaptureAreaSelection = .activeWindow
        }
        refreshTargetWindow()
    }

    func setTargetWindowFitScale(_ scale: CGFloat) {
        targetWindowFitScale = clampedTargetWindowFitScale(scale)
    }

    func zoomTargetWindowFit(by delta: CGFloat) {
        fitFrontWindowForShorts(scale: targetWindowFitScale + delta)
    }

    func resizeTargetWindow(widthDelta: CGFloat = 0, heightDelta: CGFloat = 0) {
        coordinator.resizeTargetWindow(widthDelta: widthDelta, heightDelta: heightDelta)
        syncSettings()
    }

    func setTargetWindowSize(width: CGFloat, height: CGFloat) {
        coordinator.setTargetWindowSize(width: width, height: height)
        syncSettings()
    }

    func resetSceneLayout() {
        coordinator.resetSceneLayout()
        syncSettingsAfterSceneChange()
    }

    func setSceneLayerOrder(_ order: [SceneLayerKind]) {
        coordinator.setSceneLayerOrder(order)
        syncSettings()
    }

    private func syncSettingsAfterSceneChange() {
        syncSettings()
        if settings.visibleSources.contains(.screen) {
            refreshTargetWindow()
        }
    }

    private func syncScreenCaptureAreaSelection() {
        guard settings.screenCrop != nil else {
            screenCaptureAreaSelection = .fullDisplay
            return
        }
        if screenCaptureAreaSelection != .activeWindow {
            screenCaptureAreaSelection = .manualCrop
        }
    }

    private func syncPreviewInteractionState() {
        previewStage.allowsLayerInteraction = canManipulateCanvasItems && !isScreenCropModeEnabled && !isCameraCropModeEnabled
        previewStage.allowsCameraCropInteraction = canEditCameraCrop
        if !canEditCameraCrop {
            previewStage.cancelCameraCropEditing()
            isCameraCropModeEnabled = false
            cancelScreenCropMode()
        }
    }

    private func clampedTargetWindowFitScale(_ scale: CGFloat) -> CGFloat {
        min(1.25, max(0.75, scale))
    }

    func selectLayer(_ layer: SceneLayerKind) {
        guard settings.enabledSources.contains(layer.source) else { return }
        selectedLayer = layer
        selectedSource = SourceSelection(source: layer.source)
        previewStage.selectedLayer = layer
    }

    func selectSource(_ source: CaptureSource) {
        guard isSourceConfigured(source) else { return }
        selectedSource = SourceSelection(source: source)
        switch source {
        case .screen:
            selectLayer(.screen)
        case .camera:
            selectLayer(.camera)
        case .microphone, .systemAudio:
            break
        }
    }

    func fitSelectedLayer() {
        coordinator.fitSceneLayer(selectedLayer)
        syncSettings()
    }

    func fitSelectedLayer(scale: CGFloat) {
        coordinator.fitSceneLayer(selectedLayer, scale: scale)
        syncSettings()
    }

    func setCameraCropAmount(_ amount: CGPoint) {
        coordinator.setCameraCropAmount(amount)
        syncSettings()
    }

    func setCameraCropPosition(_ position: CGPoint) {
        coordinator.setCameraCropPosition(position)
        syncSettings()
    }

    func setCameraCropZoom(_ zoom: CGFloat) {
        setCameraCropPreset(
            amount: CGPoint(x: zoom, y: zoom),
            position: settings.cameraCropPosition
        )
    }

    func setCameraCropPanX(_ x: CGFloat) {
        setCameraCropPreset(
            amount: settings.cameraCropAmount,
            position: CGPoint(x: x, y: settings.cameraCropPosition.y)
        )
    }

    func setCameraCropPanY(_ y: CGFloat) {
        setCameraCropPreset(
            amount: settings.cameraCropAmount,
            position: CGPoint(x: settings.cameraCropPosition.x, y: y)
        )
    }

    func setCameraCropPreset(amount: CGPoint, position: CGPoint) {
        if isCameraCropModeEnabled {
            previewStage.updateCameraCropDraft(amount: amount, position: position)
        } else {
            coordinator.setCameraCropAmount(amount)
            coordinator.setCameraCropPosition(position)
            syncSettings()
        }
    }

    func beginCameraCropMode() {
        guard canEditCameraCrop else { return }
        cancelScreenCropMode()
        selectedLayer = .camera
        previewStage.beginCameraCropEditing()
        isCameraCropModeEnabled = true
        syncPreviewInteractionState()
    }

    func applyCameraCropMode() {
        previewStage.commitCameraCropEditing()
        isCameraCropModeEnabled = false
        syncPreviewInteractionState()
    }

    func cancelCameraCropMode() {
        previewStage.cancelCameraCropEditing()
        isCameraCropModeEnabled = false
        syncPreviewInteractionState()
    }

    func centerCameraCrop() {
        if isCameraCropModeEnabled {
            previewStage.updateCameraCropDraft(position: .zero)
        } else {
            setCameraCropPosition(.zero)
        }
    }

    func resetCameraCrop() {
        if isCameraCropModeEnabled {
            previewStage.updateCameraCropDraft(amount: .zero, position: .zero)
        } else {
            coordinator.setCameraCropAmount(.zero)
            coordinator.setCameraCropPosition(.zero)
            syncSettings()
        }
    }

    func beginScreenCropMode() {
        guard canEditScene, isSourceConfigured(.screen) else { return }
        cancelCameraCropMode()
        selectedLayer = .screen
        selectedSource = .screen
        screenCaptureAreaSelection = .manualCrop
        coordinator.beginScreenCropEditing()
        syncSettings()
        previewStage.beginScreenCropEditing(crop: settings.screenCrop)
        isScreenCropModeEnabled = true
        screenCaptureAreaSelection = .manualCrop
        syncPreviewInteractionState()
    }

    func applyScreenCropMode() {
        previewStage.commitScreenCropEditing()
        syncPreviewInteractionState()
    }

    func cancelScreenCropMode() {
        guard isScreenCropModeEnabled || previewStage.isScreenCropEditingEnabled else { return }
        previewStage.cancelScreenCropEditing()
        coordinator.endScreenCropEditing()
        isScreenCropModeEnabled = false
        syncSettings()
        syncPreviewInteractionState()
    }

    func resetScreenCropMode() {
        if isScreenCropModeEnabled {
            previewStage.resetScreenCropDraft()
        } else {
            clearScreenCrop()
        }
    }

    func setCanvasBackgroundStyle(_ style: CanvasBackgroundStyle) {
        coordinator.setCanvasBackgroundStyle(style)
        syncSettings()
    }

    func setCanvasPadding(_ padding: CGFloat) {
        coordinator.setCanvasPadding(padding)
        syncSettings()
    }

    func setResolution(_ resolution: OutputResolution) {
        coordinator.setOutputResolution(resolution)
        syncSettings()
    }

    func setFormat(_ format: OutputVideoFormat) {
        coordinator.setOutputVideoFormat(format)
        syncSettings()
    }

    func setFrameRate(_ fps: Int) {
        coordinator.setFramesPerSecond(fps)
        syncSettings()
    }

    func setCustomVideoBitrate(_ bitrate: Int?) {
        coordinator.setCustomVideoBitrate(bitrate)
        syncSettings()
    }

    func setAudioQuality(_ quality: AudioQuality) {
        coordinator.setAudioQuality(quality)
        syncSettings()
    }

    func setSourceAudioFormat(_ format: SourceAudioFormat) {
        coordinator.setSourceAudioFormat(format)
        syncSettings()
    }

    func setMicrophoneGain(_ gain: Double) {
        coordinator.setMicrophoneGain(gain)
        syncSettings()
    }

    func setSystemAudioGain(_ gain: Double) {
        coordinator.setSystemAudioGain(gain)
        syncSettings()
    }

    func setCameraBackgroundRemovalAfterRecording(_ enabled: Bool) {
        coordinator.setCameraBackgroundRemovalAfterRecording(enabled)
        syncSettings()
    }

    func setSourceFilesSaved(_ enabled: Bool) {
        coordinator.setSourceFilesSaved(enabled)
        syncSettings()
    }

    func setCursorIncluded(_ included: Bool) {
        coordinator.setCursorIncluded(included)
        syncSettings()
    }

    func setRuleOfThirds(_ enabled: Bool) {
        coordinator.setRuleOfThirdsOverlayVisible(enabled)
        syncSettings()
    }

    func setSocialSafeZoneOverlay(_ overlay: SocialVideoSafeZone) {
        coordinator.setSocialSafeZoneOverlay(overlay)
        syncSettings()
    }

    func setDisplay(_ id: String?) {
        coordinator.setDisplay(id: id)
        syncSettings()
    }

    func setCamera(_ id: String?) {
        coordinator.setCamera(id: id)
        syncSettings()
    }

    func applyRemoteCameraPreviewImage(_ image: CGImage) {
        updateRemoteCameraPreviewAspectRatio(width: image.width, height: image.height)
        remoteCameraPreviewSurface.setPreviewImage(image)
        if !hasRemoteCameraPreviewImage {
            hasRemoteCameraPreviewImage = true
        }
    }

    func applyRemoteCameraPreviewSampleBuffer(_ sampleBuffer: CMSampleBuffer, width: Int, height: Int) {
        updateRemoteCameraPreviewAspectRatio(width: width, height: height)
        remoteCameraPreviewSurface.enqueuePreviewSampleBuffer(sampleBuffer, width: width, height: height)
        if !hasRemoteCameraPreviewImage {
            hasRemoteCameraPreviewImage = true
        }
    }

    func clearRemoteCameraPreview(message: String) {
        remoteCameraPreviewSurface.setMessage(message)
        hasRemoteCameraPreviewImage = false
    }

    private func updateRemoteCameraPreviewAspectRatio(width: Int, height: Int) {
        guard width > 0, height > 0 else { return }
        remoteCameraPreviewAspectRatio = max(0.1, CGFloat(width) / CGFloat(height))
    }

    private func syncSelectedSource() {
        if let selectedSource, isSourceConfigured(selectedSource.source) {
            return
        }
        selectedSource = SourceSelection.allCases.first { isSourceConfigured($0.source) }
    }

    func connectDirectRemoteCamera() {
        coordinator.connectDirectRemoteCamera(
            host: directRemoteCameraHost,
            portString: directRemoteCameraPort
        )
        syncSettings()
        availableCameras = coordinator.availableCameras()
    }

    func setMicrophone(_ id: String?) {
        coordinator.setMicrophone(id: id)
        syncSettings()
    }

    func setRemoteCameraLens(_ lens: RemoteCameraLens) {
        coordinator.setRemoteCameraLens(lens)
        syncSettings()
    }

    func setRemoteCameraFormat(id: String?, frameRate: Int) {
        coordinator.setRemoteCameraFormat(id: id, frameRate: frameRate)
        syncSettings()
    }

    func setRemoteCameraCaptureProfile(_ profileID: RemoteCameraCaptureProfileID) {
        coordinator.setRemoteCameraCaptureProfile(profileID)
        syncSettings()
    }

    func setRemoteCameraCinematicVideoEnabled(_ enabled: Bool) {
        coordinator.setRemoteCameraCinematicVideoEnabled(enabled)
        syncSettings()
    }

    func setRemoteCameraCinematicAperture(_ aperture: Double) {
        coordinator.setRemoteCameraCinematicAperture(aperture)
        syncSettings()
    }

    func setRemoteCameraFocusMode(_ mode: RemoteCameraFocusMode) {
        coordinator.setRemoteCameraFocusMode(mode)
        syncSettings()
    }

    func setRemoteCameraFocusPosition(_ position: Double) {
        coordinator.setRemoteCameraFocusPosition(position)
        syncSettings()
    }

    func setRemoteCameraExposureMode(_ mode: RemoteCameraExposureMode) {
        coordinator.setRemoteCameraExposureMode(mode)
        syncSettings()
    }

    func setRemoteCameraExposureBias(_ bias: Double) {
        coordinator.setRemoteCameraExposureBias(bias)
        syncSettings()
    }

    func resetRemoteCameraExposureBias() {
        coordinator.resetRemoteCameraExposureBias()
        syncSettings()
    }

    func setRemoteCameraISO(_ iso: Double?) {
        coordinator.setRemoteCameraISO(iso)
        syncSettings()
    }

    func setRemoteCameraShutterDuration(_ seconds: Double?) {
        coordinator.setRemoteCameraShutterDuration(seconds)
        syncSettings()
    }

    func setRemoteCameraWhiteBalanceMode(_ mode: RemoteCameraWhiteBalanceMode) {
        coordinator.setRemoteCameraWhiteBalanceMode(mode)
        syncSettings()
    }

    func setRemoteCameraWhiteBalance(temperature: Double, tint: Double) {
        coordinator.setRemoteCameraWhiteBalance(temperature: temperature, tint: tint)
        syncSettings()
    }

    func resetRemoteCameraImageSettings() {
        coordinator.resetRemoteCameraImageSettings()
        syncSettings()
    }

    func setRemoteCameraStabilizationMode(_ mode: RemoteCameraStabilizationMode) {
        coordinator.setRemoteCameraStabilizationMode(mode)
        syncSettings()
    }

    func setRemoteCameraRotationDegrees(_ degrees: Int) {
        coordinator.setRemoteCameraRotationDegrees(degrees)
        syncSettings()
    }

    func resetRemoteCameraSettings() {
        coordinator.resetRemoteCameraSettings()
        syncSettings()
    }

    func pickScreen() {
        pickAndEnableScreenSource()
    }

    func dismissFirstRunOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.firstRunOnboardingKey)
        showsFirstRunOnboarding = false
    }

    func chooseScreenFromOnboarding() {
        dismissFirstRunOnboarding()
        pickScreen()
    }

    func openAccessFromOnboarding() {
        dismissFirstRunOnboarding()
        appTab = .permissions
    }

    func startFromCover() {
        dismissFirstRunOnboarding()
        appTab = .recorder
    }

    func requestScreenAccessFromCover() {
        Task {
            let result = await PermissionGate.requestScreenCaptureAccess()
            if result.status == .needsSettings {
                screenAccessAwaitingRestart = true
            }
            detailMessage = result.message
            refreshPermissionStatus()
        }
    }

    func requestCameraAccessFromCover() {
        Task {
            if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
            }
            syncSettings()
            refreshPermissionStatus()
        }
    }

    func requestMicrophoneAccessFromCover() {
        Task {
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
            }
            syncSettings()
            refreshPermissionStatus()
        }
    }

    func allowAllFromCover() {
        Task {
            let needsScreenGrant =
                (settings.enabledSources.contains(.screen) && !settings.usesPickedScreenContent)
                || settings.enabledSources.contains(.systemAudio)
            if needsScreenGrant, !isPersistentScreenCaptureAccessActive {
                let result = await PermissionGate.requestScreenCaptureAccess()
                if result.status == .needsSettings {
                    screenAccessAwaitingRestart = true
                }
            }
            if settings.enabledSources.contains(.camera),
               !isRemoteCameraSelected,
               AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
            }
            if settings.enabledSources.contains(.microphone),
               AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
            }
            syncSettings()
            refreshPermissionStatus()
        }
    }

    func openCameraSettings() {
        PermissionGate.openCameraSettings()
    }

    func openMicrophoneSettings() {
        PermissionGate.openMicrophoneSettings()
    }

    func quitAndReopen() {
        // Screen Recording grants only take effect for a fresh process. Relaunch after this
        // instance exits so the single-instance lock is released before the new one claims it.
        let bundlePath = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; exec /usr/bin/open \"$1\"", "blitzrecorder-relaunch", bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }

    private func pickAndEnableScreenSource() {
        Task {
            do {
                try await coordinator.pickScreenSource()
                syncSettings()
                detailMessage = "Screen selected for this session."
            } catch {
                detailMessage = "Screen picker failed: \(error.localizedDescription)"
            }
        }
    }

    func applyScreenRecordingPermission() {
        Task {
            let result = await PermissionGate.requestScreenCaptureAccess()
            detailMessage = result.message
            refreshPermissionStatus()
        }
    }

    func requestSourcePermissions() {
        Task {
            await coordinator.requestPermissionsForEnabledSources()
            syncSettings()
            let readiness = coordinator.recordingReadiness()
            detailMessage = readiness.isReady ? "Recording permissions ready." : readiness.detail
            refreshPermissionStatus()
        }
    }

    func runPrimaryPermissionAction() {
        if shouldSuggestScreenPicker {
            pickScreen()
            return
        }

        if recordingReadiness.blockers.contains(where: { $0.source == .camera || $0.source == .microphone }) {
            requestSourcePermissions()
            return
        }

        if recordingReadiness.blockers.contains(where: { $0.source == .screen || $0.source == .systemAudio }) {
            openScreenRecordingSettings()
            detailMessage = "Enable Screen & System Audio Recording for BlitzRecorder, then quit and reopen it."
            return
        }

        refreshPermissionStatus()
    }

    func requestAccessibilityPermission() {
        Task {
            let result = await PermissionGate.requestAccessibilityAccessForWindowControls()
            detailMessage = result.message
            refreshPermissionStatus()
        }
    }

    func refreshPermissionStatus(message: String? = nil) {
        if let message {
            detailMessage = message
        }
        permissionRefreshToken += 1
    }

    func openAccessibilitySettings() {
        PermissionGate.openAccessibilitySettings()
    }

    func selectScreenCrop() {
        beginScreenCropMode()
    }

    func clearScreenCrop() {
        cancelScreenCropMode()
        coordinator.clearScreenCrop()
        syncSettings()
        screenCaptureAreaSelection = .fullDisplay
    }

    func openScreenRecordingSettings() {
        PermissionGate.openScreenCaptureSettings()
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = settings.outputDirectory
        panel.prompt = "Choose"
        panel.message = "Pick the folder where recordings will be saved."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.coordinator.setOutputDirectory(url)
            self.syncSettings()
        }
    }

    func revealOutputFolder() {
        NSWorkspace.shared.open(settings.outputDirectory)
    }

    func retryRecoveredExport() {
        guard lastRecoveryOutput?.canRetryExport == true else {
            detailMessage = "This recovery needs the missing source media before export can be retried."
            return
        }
        guard accessController.canRenderExport else {
            detailMessage = "Free exports used. Subscribe for unlimited renders."
            appTab = .creator
            return
        }
        coordinator.mergeLastTake()
    }

    func clearPostRecordingStatus() {
        lastExportedURL = nil
        lastExportedSourceTakeURL = nil
        lastExportWarning = nil
        lastRecoveryOutput = nil
        detailMessage = ""
    }

    func renameLastExportedFile() {
        guard let lastExportedURL else { return }
        let panel = NSSavePanel()
        panel.directoryURL = lastExportedURL.deletingLastPathComponent()
        panel.nameFieldStringValue = lastExportedURL.lastPathComponent
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.prompt = "Rename"
        panel.message = "Choose a new name or folder for the finished recording."
        panel.begin { [weak self] response in
            guard response == .OK, let destination = panel.url, let self else { return }
            guard destination.path != lastExportedURL.path else { return }
            do {
                let target = self.coordinator.uniqueOutputURL(destination)
                try FileManager.default.moveItem(at: lastExportedURL, to: target)
                self.lastExportedURL = target
                self.detailMessage = "Renamed: \(target.lastPathComponent)"
            } catch {
                self.detailMessage = "Rename failed: \(error.localizedDescription)"
            }
        }
    }

    func setSpeechRenameEnabled(_ enabled: Bool) {
        coordinator.setSpeechRenameEnabled(enabled)
        syncSettings()
    }

    func primaryAction() {
        switch state {
        case .idle:
            guard accessController.canRenderExport else {
                detailMessage = "Free exports used. Subscribe for unlimited renders."
                return
            }
            let readiness = coordinator.recordingReadiness()
            guard readiness.isReady else {
                resolveStartBlockers(readiness)
                return
            }
            coordinator.start()
        case .recording, .paused:
            coordinator.stop()
        case .starting, .finishing:
            break
        }
    }

    private func resolveStartBlockers(_ readiness: RecordingReadiness) {
        Task {
            if shouldUseScreenPickerForStart(readiness) {
                do {
                    try await coordinator.pickScreenSource()
                    syncSettings()
                    detailMessage = "Screen selected for this session."
                } catch {
                    detailMessage = "Screen picker failed: \(error.localizedDescription)"
                    return
                }
            }

            await coordinator.requestPermissionsForEnabledSources()
            syncSettings()

            let updatedReadiness = coordinator.recordingReadiness()
            if updatedReadiness.isReady {
                coordinator.start()
            } else {
                detailMessage = updatedReadiness.blockers.first?.sentence ?? updatedReadiness.detail
            }
        }
    }

    private func shouldUseScreenPickerForStart(_ readiness: RecordingReadiness) -> Bool {
        readiness.blockers.contains { $0.source == .screen }
            && settings.enabledSources.contains(.screen)
            && !settings.usesPickedScreenContent
            && !settings.enabledSources.contains(.systemAudio)
    }

    func togglePause() {
        switch state {
        case .recording:
            coordinator.pause()
        case .paused:
            coordinator.resume()
        default:
            break
        }
    }

    var canStartRecording: Bool {
        coordinator.recordingReadiness().isReady && accessController.canRenderExport
    }

    var readinessDetailsTab: AppTab {
        accessController.canRenderExport ? .permissions : .creator
    }

    func openReadinessDetails() {
        appTab = readinessDetailsTab
    }

    var recordingBlockerDetail: String? {
        if !accessController.canRenderExport {
            return "Subscribe for unlimited renders."
        }
        let readiness = coordinator.recordingReadiness()
        return readiness.isReady ? nil : readiness.detail
    }

    var formattedElapsed: String {
        let total = elapsedSeconds
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var renderProgressLabel: String {
        "\(Int((renderProgress * 100).rounded()))%"
    }

    var sessionProgressTitle: String {
        switch state {
        case .starting:
            return "Getting Ready"
        case .finishing:
            if remoteTransferProgress != nil {
                return "Downloading iPhone Media"
            }
            return finishingMessageTitle ?? "Saving Recording"
        case .recording, .paused:
            return state == .paused ? "Paused" : "Recording"
        case .idle:
            return ""
        }
    }

    var sessionProgressValue: Double {
        if state == .finishing,
           let remoteTransferProgress {
            return remoteTransferProgress.fraction
        }
        return renderProgress
    }

    var sessionProgressLabel: String {
        if state == .finishing,
           let remoteTransferProgress {
            return "\(Int((remoteTransferProgress.fraction * 100).rounded()))%"
        }
        return renderProgressLabel
    }

    var sessionProgressDetail: String? {
        if state == .starting {
            return sanitizedProgressMessage ?? "Not recording yet. Hang on while BlitzRecorder prepares capture."
        }
        guard state == .finishing else { return nil }
        if let remoteTransferProgress {
            return byteProgressLabel(remoteTransferProgress)
        }
        return sanitizedProgressMessage
    }

    var screenCropLabel: String {
        guard let crop = settings.screenCrop else {
            return settings.usesPickedScreenContent ? "Picked content" : "Full display"
        }
        let width = Int((crop.width * 100).rounded())
        let height = Int((crop.height * 100).rounded())
        if screenCaptureAreaSelection == .activeWindow {
            return "Active window"
        }
        return "Manual crop · \(width)% x \(height)%"
    }

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateElapsedSeconds()
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func updateElapsedSeconds() {
        let currentSegmentSeconds: TimeInterval
        if let currentRecordingSegmentStartedAt {
            currentSegmentSeconds = Date().timeIntervalSince(currentRecordingSegmentStartedAt)
        } else {
            currentSegmentSeconds = 0
        }
        elapsedSeconds = Int((elapsedAccumulatedSeconds + currentSegmentSeconds).rounded(.down))
    }

    private func commitCurrentRecordingSegment() {
        guard let currentRecordingSegmentStartedAt else { return }
        elapsedAccumulatedSeconds += Date().timeIntervalSince(currentRecordingSegmentStartedAt)
        self.currentRecordingSegmentStartedAt = nil
        elapsedSeconds = Int(elapsedAccumulatedSeconds.rounded(.down))
    }

    private var remoteTransferProgress: RemoteCameraTransferProgress? {
        guard selectedRemoteCameraTelemetry?.phase == .transferring else { return nil }
        return selectedRemoteCameraTelemetry?.transferProgress
    }

    private var sanitizedProgressMessage: String? {
        let message = detailMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty,
              !message.hasPrefix("Saved:"),
              !message.hasPrefix("Recording failed:") else {
            return nil
        }
        return message
    }

    private var finishingMessageTitle: String? {
        guard let message = sanitizedProgressMessage else { return nil }
        if message.localizedCaseInsensitiveContains("download") ||
            message.localizedCaseInsensitiveContains("iphone") {
            return message
        }
        if message.hasSuffix("...") || message.hasSuffix("…") {
            return String(message.dropLast(message.hasSuffix("...") ? 3 : 1))
        }
        return message
    }

    private func byteProgressLabel(_ progress: RemoteCameraTransferProgress) -> String {
        let transferred = ByteCountFormatter.string(
            fromByteCount: progress.transferredByteCount,
            countStyle: .file
        )
        let expected = ByteCountFormatter.string(
            fromByteCount: progress.expectedByteCount,
            countStyle: .file
        )
        return "\(transferred) of \(expected)"
    }

}

struct PermissionStatusRow: Identifiable, Equatable {
    var id: String { title }
    let title: String
    let symbol: String
    let status: String
    let isActive: Bool
    let isBlocked: Bool
    let isOptional: Bool
    let source: CaptureSource?

    var isGranted: Bool {
        ["allowed", "authorized", "remote iPhone", "selected with macOS picker"].contains(status)
    }

    var level: PermissionStatusLevel {
        if !isActive {
            return .inactive
        }
        if isGranted {
            return .granted
        }
        if status == "not determined" {
            return .warning
        }
        return isBlocked ? .blocked : .warning
    }
}

enum PermissionStatusLevel: Equatable {
    case granted
    case warning
    case blocked
    case inactive
}

extension CaptureSource {
    var symbolName: String {
        switch self {
        case .screen: return "rectangle.on.rectangle"
        case .camera: return "video.fill"
        case .systemAudio: return "speaker.wave.2.fill"
        case .microphone: return "mic.fill"
        }
    }

    var shortLabel: String {
        switch self {
        case .screen: return "Screen"
        case .camera: return "Camera"
        case .systemAudio: return "Mac Audio"
        case .microphone: return "Mic"
        }
    }

    var onboardingPurpose: String {
        switch self {
        case .screen: return "Capture what's on your display."
        case .camera: return "Add your face cam to the recording."
        case .systemAudio: return "Record sound playing on your Mac."
        case .microphone: return "Record your voice."
        }
    }

    var isAudioSource: Bool {
        self == .microphone || self == .systemAudio
    }
}

enum AppTab: CaseIterable, Equatable {
    case recorder
    case iphone
    case recording
    case creator
    case permissions

    var title: String {
        switch self {
        case .recorder: return "Capture"
        case .iphone: return "iPhone"
        case .recording: return "Export"
        case .creator: return "Plan"
        case .permissions: return "Access"
        }
    }

    var symbolName: String {
        switch self {
        case .recorder: return "record.circle"
        case .iphone: return "iphone.gen3"
        case .recording: return "square.and.arrow.up"
        case .creator: return "creditcard"
        case .permissions: return "lock.shield"
        }
    }
}

extension CaptureLayout {
    var symbolName: String {
        switch self {
        case .vertical: return "rectangle.portrait"
        case .horizontal: return "rectangle"
        }
    }

    var shortLabel: String {
        switch self {
        case .vertical: return "9:16"
        case .horizontal: return "16:9"
        }
    }

    var titleLabel: String {
        switch self {
        case .vertical: return "Shorts"
        case .horizontal: return "YouTube"
        }
    }
}

extension ScenePreset {
    var symbolName: String {
        switch self {
        case .stackedHalves: return "rectangle.split.1x2"
        case .screenTop50: return "rectangle.split.1x2"
        case .screenTop70: return "rectangle.split.1x2"
        case .screenFocus: return "rectangle.inset.filled"
        case .cameraInset: return "pip"
        case .cameraFocus: return "person.crop.rectangle"
        case .webcamLeft: return "rectangle.leadingthird.inset.filled"
        case .screenFullscreen: return "rectangle.fill"
        case .webcamFullscreen: return "video.fill"
        }
    }
}
