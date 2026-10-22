import AppKit
import AVFoundation
import BlitzRecorderCore
import Foundation
import QuartzCore

extension RecorderViewModel {
    func setLivePreviewEnabled(_ enabled: Bool) {
        guard state == .idle, isLivePreviewEnabled != enabled else { return }
        isLivePreviewEnabled = enabled
        LivePreviewPreference().setEnabled(enabled)
        if !enabled {
            micLevels.clear()
            sysLevels.clear()
        }
        onLivePreviewChanged?(enabled)
        NotificationCenter.default.post(name: .livePreviewChanged, object: nil)
    }

    func applyExportProject(_ url: URL?) {
        exports.activeExportProjectURL = url
        if url != nil {
            exports.exportProgress = 0
            exports.lastExportError = nil
            exports.lastExportSucceededURL = nil
        }
    }

    func applyState(_ newState: RecordingState) {
        let previousState = state
        state = newState
        elapsedClock.applyState(newState, previousState: previousState)
        syncPreviewInteractionState()
        switch newState {
        case .starting:
            exports.isEditorExportPresented = false
            exports.renderProgress = 0
            detailMessage = RecordingStartCopy.preparing
            resetLastRecordingOutputs()
        case .recording:
            if previousState == .idle || previousState == .starting || previousState == .finishing {
                exports.renderProgress = 0
            }
        case .paused:
            break
        case .finishing:
            if previousState != .finishing { session.finishingStartedAt = Date() }
            session.captureStopProgress = nil
            exports.renderProgress = 0
        case .idle:
            session.finishingStartedAt = nil
            session.captureStopProgress = nil
            exports.renderProgress = 0
        }
    }

    func applyMessage(_ message: String) {
        detailMessage = message
    }

    func applySavedRecordingOutput(_ output: SavedRecordingOutput) {
        if exports.activeExportProjectURL?.deletingLastPathComponent() == output.sourceDirectory {
            exports.lastExportError = nil
            exports.lastExportSucceededURL = output.url
            refreshProjectsInBackground()
            if lastExportedSourceTakeURL == output.sourceDirectory {
                lastExportedURL = output.url
                refreshLastExportedProject()
            }
            return
        }
        let keepsEditorOpen = studioMode == .edit
        exports.lastExportError = nil
        exports.lastExportSucceededURL = output.url
        lastExportedURL = output.url
        lastExportedSourceTakeURL = output.sourceDirectory
        lastExportWarning = output.warning
        lastRecoveryOutput = nil
        lastPostRecordingProjectOutput = nil
        refreshRecentProjects()
        refreshLastExportedProject()
        if !keepsEditorOpen {
            clearEditorHistory()
            studioMode = .record
        }
    }

    func applyPostRecordingProjectOutput(_ output: PostRecordingProjectOutput) {
        lastPostRecordingProjectOutput = output
        lastExportedURL = nil
        lastExportedSourceTakeURL = output.sourceDirectory
        lastExportWarning = output.warning
        lastRecoveryOutput = nil
        refreshRecentProjects()
        refreshLastExportedProject()
        transcriptionController.enqueueProject(output.projectURL)
        clearEditorHistory()
        studioMode = .record
    }

    func applyRecoveryOutput(_ output: RecordingRecoveryOutput) {
        lastRecoveryOutput = output
        lastExportedURL = nil
        lastExportedSourceTakeURL = nil
        lastExportWarning = nil
        lastPostRecordingProjectOutput = nil
        lastExportedProject = nil
        clearEditorHistory()
        studioMode = .record
        refreshRecentProjects()
    }

    func applyRenderProgress(_ progress: Double) {
        exports.renderProgress = min(1, max(0, progress))
    }

    func applyExportFailure(_ message: String?) {
        exports.lastExportError = message
        if message != nil {
            exports.lastExportSucceededURL = nil
        }
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
        let sceneID = coordinator.selectedSceneIDForCurrentLayout()
        if previewStage.sceneID != sceneID || previewStage.captureLayout != settings.layout {
            canvas.isCameraCropModeEnabled = false
            canvas.isScreenCropModeEnabled = false
            previewStage.cancelCanvasInteraction()
            previewStage.sceneID = sceneID
            coordinator.endScreenCropEditing()
        }
        previewStage.sceneID = sceneID
        screenSource.targetWindowZoom = coordinator.settings.screenWindowZoom
        syncScreenCaptureAreaSelection()
        syncSelectedSource()
        syncPreviewInteractionState()
        previewStage.captureLayout = coordinator.settings.layout
        previewStage.sceneLayout = canvas.screenSplitPreviewHeight.map {
            SceneLayout.screenSplitLayout(screenHeight: CGFloat($0))
        } ?? sideSplitPreviewLayout ?? coordinator.settings.sceneLayout
        previewStage.enabledSources = coordinator.settings.visibleSources
        previewStage.fillsCanvasWhenOnlyVideoSource =
            coordinator.settings.enabledSources.intersection([.screen, .camera]).count == 1
        previewStage.applySettingsAspectRatio(coordinator.currentScreenSourceAspectRatio())
        previewStage.screenFillsSceneFrame = ScreenSourceGeometry.fillsSceneFrame(for: coordinator.settings)
        previewStage.screenCrop = coordinator.settings.screenCrop
        previewStage.cameraCropAmount = coordinator.settings.cameraCropAmount
        previewStage.cameraCropPosition = coordinator.settings.cameraCropPosition
        previewStage.showsRuleOfThirdsOverlay = coordinator.settings.showsRuleOfThirdsOverlay
        previewStage.socialSafeZoneOverlay = coordinator.settings.socialSafeZoneOverlay
        previewStage.canvasBackgroundStyle = coordinator.settings.canvasBackgroundStyle
        previewStage.canvasBackgroundAnimated = coordinator.settings.canvasBackgroundAnimated
        previewStage.canvasPadding = coordinator.settings.canvasPadding
        previewStage.screenContentMode = coordinator.settings.screenContentMode
        previewStage.cameraContentMode = coordinator.settings.cameraContentMode
        previewStage.cameraFramePadding = coordinator.settings.cameraFramePadding
        previewStage.cameraShadowEnabled = coordinator.settings.cameraShadowEnabled
        previewStage.screenCornerRadius = coordinator.settings.screenCornerRadius
        previewStage.screenShadowEnabled = coordinator.settings.screenShadowEnabled
        previewStage.cameraCornerRadius = coordinator.settings.cameraCornerRadius
        previewStage.isBackgroundLayerSelected = isBackgroundLayerSelected
    }

    func refreshTargetWindow() {
        do {
            screenSource.targetWindowInfo = try coordinator.targetWindowInfo()
            screenSource.targetWindowStatus = ""
        } catch {
            screenSource.targetWindowInfo = nil
            screenSource.targetWindowStatus = error.localizedDescription
        }
    }

    func refreshSources() async {
        availableCameras = coordinator.availableCameras()
        // Continuity Camera means an iPhone is right here; look for it in BlitzRecorder Camera too.
        if isSourceConfigured(.camera), selectedContinuityCamera != nil { startRemoteCameraDiscovery() }
        availableMicrophones = coordinator.availableMicrophones()
        if state == .idle, settings.selectedMicrophoneName == nil, let id = settings.selectedMicrophoneID,
           availableMicrophones.contains(where: { $0.id == id }) {
            setMicrophone(id)
        }
        async let displays = coordinator.availableDisplays()
        async let screenSources = coordinator.availableScreenSources()
        availableDisplays = await displays
        availableScreenSources = await screenSources
        refreshScreenSourceAvailability()
    }

    func screenSourceThumbnail(_ binding: ScreenSourceBinding) async -> NSImage? {
        await coordinator.screenSourceThumbnail(binding)
    }

    func refreshRemoteCameraState() {
        settings = coordinator.settings
        availableCameras = coordinator.availableCameras()
        remoteCameraPreview.remoteCameraRefreshToken += 1
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
        if source == .systemAudio,
           !isSourceConfigured(.systemAudio),
           !coordinator.hasActiveScreenSourceSelection {
            pickAndEnableSystemAudioSource()
            return
        }

        if isSourceConfigured(source) {
            coordinator.removeSource(source)
        } else {
            coordinator.addSource(source)
        }
        syncSettings()
        if isSourceConfigured(source) {
            selectSource(source)
        }
    }

    func setSourceVisible(_ source: CaptureSource, visible: Bool) {
        if source == .screen,
           visible,
           (!isSourceConfigured(.screen) || !coordinator.hasActiveScreenSourceSelection) {
            pickAndEnableScreenSource()
            return
        }
        if source == .systemAudio,
           visible,
           !coordinator.hasActiveScreenSourceSelection {
            pickAndEnableSystemAudioSource()
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

    var screenSplitHeight: Double {
        canvas.screenSplitPreviewHeight
            ?? Double(settings.sceneLayout.screenSplitHeight ?? SceneSplitPolicy.inferredHeight(from: settings.sceneLayout) ?? SceneLayout.defaultScreenSplitHeight)
    }

    var activeScenePreset: ScenePreset? {
        showsScreenSplitControl ? .screenTop50 : settings.selectedScenePreset
    }

    var isCameraInsetLayout: Bool {
        SceneLayout.isCameraInsetFrame(settings.sceneLayout.cameraFrame)
    }

    var cameraFloats: Bool {
        settings.sceneLayout.cameraFloats(visibleSources: settings.visibleSources)
    }

    var cameraInsetAlignment: CameraInsetAlignment {
        SceneLayout.cameraInsetAlignment(for: settings.sceneLayout.cameraFrame)
    }

    var cameraInsetShape: CameraInsetShape {
        settings.sceneLayout.cameraInsetShape(in: settings.layout)
    }

    var cameraInsetSize: Double {
        Double(settings.sceneLayout.cameraInsetSize(in: settings.layout))
    }

    var cameraInsetSizeRange: ClosedRange<Double> {
        Double(SceneLayout.minimumCameraInsetSize)...Double(SceneLayout.maximumCameraInsetSize(for: settings.layout))
    }

    var showsScreenSplitControl: Bool {
        SceneSplitPolicy.showsControl(
            captureLayout: settings.layout,
            visibleSources: settings.visibleSources,
            sceneLayout: settings.sceneLayout,
            selectedPreset: settings.selectedScenePreset
        )
    }

    func isScenePresetActive(_ preset: ScenePreset) -> Bool {
        activeScenePreset == preset
    }

    func setScreenSplitHeight(_ height: Double) {
        canvas.screenSplitPreviewHeight = nil
        coordinator.setScreenSplitHeight(CGFloat(height))
        syncSettingsAfterSceneChange()
    }

    func previewScreenSplitHeight(_ height: Double) {
        guard canEditScene, showsScreenSplitControl else { return }
        let height = Double(SceneLayout.clampedScreenSplitHeight(CGFloat(height)))
        canvas.screenSplitPreviewHeight = height
        let layout = SceneLayout.screenSplitLayout(screenHeight: CGFloat(height))
        showSceneLayoutPreview(layout)
    }

    func commitScreenSplitPreview() {
        guard let height = canvas.screenSplitPreviewHeight else { return }
        guard canEditScene, showsScreenSplitControl else {
            cancelScreenSplitPreview()
            return
        }
        setScreenSplitHeight(height)
    }

    func cancelScreenSplitPreview() {
        guard canvas.screenSplitPreviewHeight != nil else { return }
        canvas.screenSplitPreviewHeight = nil
        showSceneLayoutPreview(coordinator.settings.sceneLayout)
    }

    var showsSideSplitControl: Bool {
        settings.layout != .vertical
            && settings.visibleSources.isSuperset(of: [.screen, .camera])
            && settings.sceneLayout.cameraSide != nil
    }

    var sideSplitCameraWidth: Double {
        canvas.sideSplitPreviewWidth ?? Double(settings.sceneLayout.sideBySideCameraWidth
            ?? SceneLayout.defaultSideBySideCameraWidth(for: settings.layout))
    }

    var sideSplitCameraIsLeft: Bool {
        settings.sceneLayout.cameraSide != .right
    }

    private var sideSplitPreviewLayout: SceneLayout? {
        guard let width = canvas.sideSplitPreviewWidth, let side = coordinator.settings.sceneLayout.cameraSide else { return nil }
        return SceneLayout.sideBySideLayout(.init(cameraWidth: CGFloat(width), cameraSide: side))
    }

    func showSceneLayoutPreview(_ layout: SceneLayout) {
        previewStage.sceneLayout = layout
        coordinator.previewSceneLayout(layout)
    }

    func setSideSplitCameraWidth(_ width: Double) {
        canvas.sideSplitPreviewWidth = nil
        guard let side = settings.sceneLayout.cameraSide else { return }
        coordinator.setSideBySideLayout(.init(cameraWidth: CGFloat(width), cameraSide: side))
        syncSettingsAfterSceneChange()
    }

    var sideSplitCameraSide: SceneCameraSide {
        settings.sceneLayout.cameraSide ?? .left
    }

    func setSideSplitCameraSide(_ side: SceneCameraSide) {
        cancelSideSplitPreview()
        coordinator.setSideBySideLayout(.init(cameraWidth: CGFloat(sideSplitCameraWidth), cameraSide: side))
        syncSettingsAfterSceneChange()
    }

    func previewSideSplitCameraWidth(_ width: Double) {
        guard canEditScene, showsSideSplitControl else { return }
        canvas.sideSplitPreviewWidth = Double(SceneLayout.clampedSideBySideCameraWidth(CGFloat(width)))
        guard let layout = sideSplitPreviewLayout else { return }
        showSceneLayoutPreview(layout)
    }

    func commitSideSplitPreview() {
        guard let width = canvas.sideSplitPreviewWidth else { return }
        guard canEditScene, showsSideSplitControl else {
            cancelSideSplitPreview()
            return
        }
        setSideSplitCameraWidth(width)
    }

    func cancelSideSplitPreview() {
        guard canvas.sideSplitPreviewWidth != nil else { return }
        canvas.sideSplitPreviewWidth = nil
        showSceneLayoutPreview(coordinator.settings.sceneLayout)
    }

    func setCamera(_ id: String?) {
        coordinator.setCamera(id: id)
        syncSettings()
    }

    func setMicrophone(_ id: String?) {
        coordinator.setMicrophone(id: id)
        syncSettings()
    }
}
