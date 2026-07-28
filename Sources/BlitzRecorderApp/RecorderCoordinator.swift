import AppKit
import AVFoundation
import BlitzRecorderCore
import BlitzRecorderTransport
import Foundation
import os
import ScreenCaptureKit

let exportLog = Logger(subsystem: "dev.blitzreels.blitzrecorder", category: "export")

@MainActor
final class RecorderCoordinator {
    let accessController: AccessController
    let permissionGate: PermissionGate
    private let defaults: UserDefaults?

    private let screenRecorder = ScreenRecorder()
    private let screenPreviewer = ScreenPreviewer()
    private let screenContentPicker = ScreenContentPicker()
    private let screenSourcePickerRecents: ScreenSourcePickerRecents
    private let screenCropPicker = ScreenCropPicker()
    private let cameraRecorder = CameraRecorder()
    private let cameraCutoutPreviewer = CameraCutoutPreviewer()
    private let audioRecorder = AudioRecorder()
    private let systemAudioRecorder = SystemAudioRecorder()
    private let takeRecording = TakeRecordingRuntime()
    private let microphoneLevelMonitor = MicrophoneLevelMonitor()
    private let systemAudioLevelMonitor = SystemAudioLevelMonitor()
    private let speechTranscriber = SpeechTranscriber()
    private let titleGenerator = TitleGenerator()
    private let takeFileStore = TakeFileStore()
    private let screenSourceSelection = ScreenSourceSelection()
    private let recordingSession = RecordingSession()
    private var idleCaptureResourcesEnabled = true
    private lazy var remoteCamera = RemoteIPhoneCameraSession(
        readSettings: { [weak self] in
            self?.settings ?? RecordingSettings()
        },
        saveSettings: { [weak self] settings in
            self?.settings = settings
            self?.persistSettings()
        },
        screenAspectRatio: { [weak self] in
            self?.currentScreenSourceAspectRatio() ?? SceneLayout.defaultScreenAspectRatio
        },
        canAttemptPendingImports: { [weak self] in
            self?.state == .idle || self?.state == .finishing
        }
    )
    private lazy var takeFinalizer: TakeFinalizer = {
        let finalizer = TakeFinalizer(
            speechTranscriber: speechTranscriber,
            titleGenerator: titleGenerator,
            fileStore: takeFileStore
        )
        finalizer.onMessage = { [weak self] message in
            self?.onMessage?(message)
        }
        finalizer.onRenderProgress = { [weak self] progress in
            self?.onRenderProgress?(progress)
        }
        return finalizer
    }()

    var state: RecordingState { recordingSession.state }
    private(set) var settings: RecordingSettings
    private(set) var sceneLibrary: SceneLibrary
    var lastTake: RecordingTake? { recordingSession.lastTake }
    private var currentPickedScreenSourceAspectRatio: CGFloat?
    private var isEditingScreenCrop = false
    private(set) var screenContentSelectionRevision = 0
    private(set) var screenWindowGeometryRevision = 0
    private var screenWindowFitRevision = 0
    private var activeScreenCaptureConfigurationRevision = 0
    private var activeScreenCaptureConfigurationTask: Task<Void, Never>?
    private var activeScreenPickerTransactionTask: Task<Void, Never>?
    private var activeScreenPickerTransactionID: UUID?
    private var pickerQueuedScreenCaptureConfigurationRevision = 0
    private var committedRecordingSettings: RecordingSettings?
    private var localCameraRuntimeState: LocalCameraRuntimeState = .unchecked

    private struct ScreenSourceActionContext: Equatable {
        let screenWindowFitRevision: Int
        let screenContentSelectionRevision: Int
        let screenSourceBinding: ScreenSourceBinding?
        let usesPickedScreenContent: Bool
    }

    var onStateChanged: ((RecordingState) -> Void)? {
        didSet { recordingSession.onStateChanged = onStateChanged }
    }
    var onMessage: ((String) -> Void)?
    var onSavedRecording: ((SavedRecordingOutput) -> Void)?
    var onPostRecordingProject: ((PostRecordingProjectOutput) -> Void)?
    var onRecordingRecovery: ((RecordingRecoveryOutput) -> Void)?
    var onRenderProgress: ((Double) -> Void)?
    var onExportFailure: ((String?) -> Void)?
    var onRuleOfThirdsOverlayChanged: ((Bool) -> Void)?
    var onSocialSafeZoneOverlayChanged: ((SocialVideoSafeZone) -> Void)?
    var onScreenCaptureConfigurationChanged: (() -> Void)?
    var onCameraConfigurationChanged: (() -> Void)?
    var onRequestForeground: (() -> Void)?
    var onLiveScreenPreviewFrame: ScreenPreviewer.FrameHandler?
    var onLocalCameraPreviewSampleBuffer: ((CMSampleBuffer, Int, Int) -> Void)?
    var onRemoteCameraPreviewFrame: ((CGImage) -> Void)?
    var onRemoteCameraPreviewSampleBuffer: ((CMSampleBuffer, Int, Int) -> Void)?
    var onRemoteCameraPreviewReset: ((String) -> Void)?
    var onRemoteCameraPairingCodeRequested: ((String) -> String?)?
    var onAudioLevel: ((CaptureSource, Float) -> Void)? {
        didSet {
            audioRecorder.levelHandler = { [weak self] level in
                self?.onAudioLevel?(.microphone, level)
            }
            systemAudioRecorder.levelHandler = { [weak self] level in
                self?.onAudioLevel?(.systemAudio, level)
            }
            microphoneLevelMonitor.levelHandler = { [weak self] level in
                self?.onAudioLevel?(.microphone, level)
            }
            systemAudioLevelMonitor.levelHandler = { [weak self] level in
                self?.onAudioLevel?(.systemAudio, level)
            }
        }
    }

    init(accessController: AccessController, defaults: UserDefaults? = nil) {
        self.accessController = accessController
        permissionGate = PermissionGate()
        self.defaults = defaults
        screenSourcePickerRecents = ScreenSourcePickerRecents(defaults: defaults ?? .standard)
        settings = RecordingSettingsStore.load(defaults: defaults)
        sceneLibrary = SceneLibraryStore.load(defaults: defaults, currentSettings: settings)
        if let selectedScene = sceneLibrary.selectedScene(layout: settings.layout) {
            applySceneSnapshot(selectedScene.snapshot)
        }
        accessController.onLicenseStateChanged = { [weak self] in
            self?.reconcileLicenseLimitsForCurrentAccess()
        }
        reconcileLicenseLimitsForCurrentAccess()
        if clearIncompatibleScreenCropForCurrentLayout() {
            persistSettings()
        }
        reconcilePersistentScreenAccessIfNeeded()
        screenSourcePickerRecents.record(settings.screenSourceBinding)
        audioRecorder.failureHandler = { [weak self] error in
            Task { @MainActor [weak self] in
                self?.handleActiveMicrophoneCaptureFailure(error)
            }
        }
        remoteCamera.onMessage = { [weak self] message in
            self?.onMessage?(message)
        }
        remoteCamera.onCameraConfigurationChanged = { [weak self] in
            self?.refitCameraInsetToCurrentCamera()
            self?.onCameraConfigurationChanged?()
        }
        remoteCamera.onPreviewFrame = { [weak self] image in
            self?.onRemoteCameraPreviewFrame?(image)
        }
        remoteCamera.onPreviewSampleBuffer = { [weak self] sampleBuffer, width, height in
            self?.onRemoteCameraPreviewSampleBuffer?(sampleBuffer, width, height)
        }
        remoteCamera.onPreviewReset = { [weak self] message in
            self?.onRemoteCameraPreviewReset?(message)
        }
        remoteCamera.onPairingCodeRequested = { [weak self] deviceName in
            self?.onRemoteCameraPairingCodeRequested?(deviceName)
        }
        takeRecording.setLiveCompositorCameraPreviewHandler { [weak self] sampleBuffer, width, height in
            guard let self,
                  self.state == .starting || self.state == .recording || self.state == .paused,
                  self.settings.visibleSources.contains(.camera) else {
                return
            }
            self.onLocalCameraPreviewSampleBuffer?(sampleBuffer, width, height)
        }
        takeRecording.setLiveCompositorScreenPreviewHandler { [weak self] frame in
            guard let self,
                  self.state == .starting || self.state == .recording || self.state == .paused,
                  self.settings.visibleSources.contains(.screen) else {
                return
            }
            self.noteScreenSourceAspectRatio(frame.sourceAspectRatio)
            self.onLiveScreenPreviewFrame?(frame)
        }
        if RemoteCameraProviderID.isRemote(settings.selectedCameraID) {
            startRemoteCameraDiscoveryIfNeeded()
        }
        if refitCameraInsetFrameForCurrentSource() {
            persistSettings()
        }
    }

    func cameraPreviewLayer() async throws -> AVCaptureVideoPreviewLayer {
        if isRemoteCameraSelected {
            throw RecorderError.remoteCameraPreviewUnavailable
        }
        guard await permissionGate.requestCameraAccess() else {
            throw RecorderError.noCamera
        }
        return try await cameraRecorder.makePreviewLayer(settings: settings)
    }

    func startScreenPreview(frameHandler: @escaping ScreenPreviewer.FrameHandler) async throws {
        guard state != .idle || idleCaptureResourcesEnabled else { return }
        var previewSettings = settings
        if isEditingScreenCrop {
            previewSettings.screenCrop = nil
        }
        try await screenPreviewer.start(
            settings: previewSettings,
            filter: pickedScreenFilter(for: previewSettings),
            frameHandler: { [weak self] frame in
                self?.noteScreenSourceAspectRatio(frame.sourceAspectRatio)
                frameHandler(frame)
            }
        )
    }

    func noteScreenSourceAspectRatio(_ aspectRatio: CGFloat) {
        guard aspectRatio > 0 else { return }
        currentPickedScreenSourceAspectRatio = aspectRatio
    }

    var isScreenPreviewRunning: Bool {
        screenPreviewer.isRunning
    }

    var hasActivePickedScreenContent: Bool {
        screenSourceSelection.hasActivePickedContent
    }

    var activePickedScreenContentKind: ScreenSourceBinding.Kind? {
        screenSourceSelection.activePickedContentKind(for: settings)
    }

    var hasActiveScreenSourceSelection: Bool {
        ScreenPreviewLifecycle.sourceIsAvailable(.init(
            settings: settings,
            hasPersistentScreenCaptureAccess: permissionGate.hasScreenCaptureAccess,
            hasActivePickedContent: screenSourceSelection.hasActivePickedContent
        ))
    }

    func stopScreenPreview() async {
        try? await screenPreviewer.stop()
    }

    func stopCameraPreview() async {
        await cameraRecorder.stopSession()
        await cameraCutoutPreviewer.stop()
    }

    func suspendIdleCaptureResources() async {
        idleCaptureResourcesEnabled = false
        await stopScreenPreview()
        await stopCameraPreview()
        await stopAudioLevelMonitoring()
    }

    func resumeIdleAudioLevelMonitoring() async {
        guard state == .idle else { return }
        idleCaptureResourcesEnabled = true
        await configureAudioLevelMonitoring()
    }

    func startCameraCutoutPreview(frameHandler: @escaping CameraCutoutPreviewer.FrameHandler) async throws {
        if isRemoteCameraSelected {
            throw RecorderError.remoteCameraPreviewUnavailable
        }
        guard await permissionGate.requestCameraAccess() else {
            throw RecorderError.noCamera
        }
        await cameraRecorder.stopSession()
        try await cameraCutoutPreviewer.start(settings: settings, frameHandler: frameHandler)
    }

    func scenesForCurrentLayout() -> [RecordingSceneDefinition] {
        sceneLibrary.scenes(for: settings.layout)
    }

    func scenes(for layout: CaptureLayout) -> [RecordingSceneDefinition] {
        sceneLibrary.scenes(for: layout)
    }

    func layout(ofSceneID id: UUID) -> CaptureLayout? {
        sceneLibrary.layout(ofSceneID: id)
    }

    func selectedSceneIDForCurrentLayout() -> UUID? {
        sceneLibrary.selectedSceneIDsByLayout[settings.layout]
    }

    func selectedSceneName() -> String {
        sceneLibrary.selectedScene(layout: settings.layout)?.name ?? "Scene"
    }

    func selectScene(id: UUID) {
        guard allowsSceneChanges else {
            onMessage?("Scenes are locked while saving.")
            return
        }
        saveCurrentSceneSnapshotIfNeeded()
        guard let scene = sceneLibrary.selectScene(id: id, layout: settings.layout) else { return }
        SceneLibraryStore.save(sceneLibrary, defaults: defaults)
        applySceneSnapshot(scene.snapshot)
        persistSettings(saveSceneSnapshot: false)
        updateRecordingSceneIfNeeded(transition: .sceneSwitch)
        onScreenCaptureConfigurationChanged?()
        if state == .idle {
            onCameraConfigurationChanged?()
        }
        autoFitSelectedScreenWindowToSceneSlot()
    }

    func createSceneFromCurrentSettings(named name: String? = nil) {
        guard state == .idle else {
            onMessage?("Scene library editing is locked while recording.")
            return
        }
        saveCurrentSceneSnapshotIfNeeded()
        let snapshot = currentRecordingSceneSnapshot()
        let scene = sceneLibrary.createScene(
            layout: settings.layout,
            name: name ?? RecordingSceneDefinition.defaultName(for: settings),
            snapshot: snapshot
        )
        SceneLibraryStore.save(sceneLibrary, defaults: defaults)
        applySceneSnapshot(scene.snapshot)
        persistSettings(saveSceneSnapshot: false)
        onScreenCaptureConfigurationChanged?()
        onCameraConfigurationChanged?()
        autoFitSelectedScreenWindowToSceneSlot()
    }

    func duplicateSelectedScene() {
        guard state == .idle else {
            onMessage?("Scene library editing is locked while recording.")
            return
        }
        saveCurrentSceneSnapshotIfNeeded()
        guard let selectedSceneID = sceneLibrary.selectedSceneIDsByLayout[settings.layout],
              let scene = sceneLibrary.duplicateScene(id: selectedSceneID, layout: settings.layout) else {
            return
        }
        SceneLibraryStore.save(sceneLibrary, defaults: defaults)
        applySceneSnapshot(scene.snapshot)
        persistSettings(saveSceneSnapshot: false)
        onScreenCaptureConfigurationChanged?()
        onCameraConfigurationChanged?()
        autoFitSelectedScreenWindowToSceneSlot()
    }

    func renameScene(id: UUID, to name: String) {
        guard state == .idle else {
            onMessage?("Scene library editing is locked while recording.")
            return
        }
        guard sceneLibrary.renameScene(id: id, layout: settings.layout, name: name) else {
            return
        }
        SceneLibraryStore.save(sceneLibrary, defaults: defaults)
    }

    func deleteScene(id: UUID) {
        guard state == .idle else {
            onMessage?("Scene library editing is locked while recording.")
            return
        }
        guard sceneLibrary.deleteScene(id: id, layout: settings.layout) else {
            onMessage?("Keep at least one scene in this canvas format.")
            return
        }
        SceneLibraryStore.save(sceneLibrary, defaults: defaults)
        if let selectedScene = sceneLibrary.selectedScene(layout: settings.layout) {
            applySceneSnapshot(selectedScene.snapshot)
            persistSettings(saveSceneSnapshot: false)
            onScreenCaptureConfigurationChanged?()
            onCameraConfigurationChanged?()
        }
    }

    func moveScene(id: UUID, to index: Int) {
        guard state == .idle else {
            onMessage?("Scene library editing is locked while recording.")
            return
        }
        guard sceneLibrary.moveScene(id: id, layout: settings.layout, to: index) else {
            return
        }
        SceneLibraryStore.save(sceneLibrary, defaults: defaults)
    }

    func setLayout(_ layout: CaptureLayout) {
        guard state == .idle else {
            onMessage?("Output aspect ratio is locked while recording.")
            return
        }
        guard settings.layout != layout else {
            if clearIncompatibleScreenCropForCurrentLayout() {
                persistSettings()
                onScreenCaptureConfigurationChanged?()
            }
            return
        }
        let preservedScreenSource = currentScreenSourceSelection()
        saveCurrentSceneSnapshotIfNeeded()
        settings.layout = layout
        sceneLibrary.ensureScenes(for: layout)
        if let scene = sceneLibrary.selectedScene(layout: layout) {
            applySceneSnapshot(scene.snapshot)
        } else {
            settings.screenCrop = nil
            settings.selectedScenePreset = ScenePreset.defaultPreset(for: layout)
            settings.sceneLayout = SceneLayout.defaultLayout(
                for: layout,
                screenAspectRatio: currentScreenSourceAspectRatio(),
                cameraAspectRatio: currentCameraSourceAspectRatio()
            )
        }
        restoreScreenSourceSelection(preservedScreenSource)
        recomputeSelectedPresetLayoutForCurrentSource()
        SceneLibraryStore.save(sceneLibrary, defaults: defaults)
        persistSettings(saveSceneSnapshot: false)
        onScreenCaptureConfigurationChanged?()
        onCameraConfigurationChanged?()
        autoFitSelectedScreenWindowToSceneSlot()
    }

    @discardableResult
    private func clearIncompatibleScreenCropForCurrentLayout() -> Bool {
        guard settings.layout == .horizontal,
              let screenCrop = settings.screenCrop,
              screenCrop.width > 0,
              screenCrop.height > 0,
              screenCrop.width / screenCrop.height < 1 else {
            return false
        }
        settings.screenCrop = nil
        return true
    }

    @discardableResult
    private func enforceLicenseLimits() -> Bool {
        guard !accessController.hasActiveLicense else { return false }
        var changed = false

        if settings.outputResolution == .p2160 {
            settings.outputResolution = .p1080
            changed = true
        }

        if settings.framesPerSecond >= 60 {
            settings.framesPerSecond = 30
            changed = true
        }

        if RemoteCameraProviderID.isRemote(settings.selectedCameraID) {
            settings.selectedCameraID = nil
            changed = true
        }

        return changed
    }

    private func reconcileLicenseLimitsForCurrentAccess() {
        guard !accessController.hasSavedLicenseKey else { return }
        guard enforceLicenseLimits() else { return }
        persistSettings()
        onCameraConfigurationChanged?()
    }

    func setOutputResolution(_ outputResolution: OutputResolution) {
        guard outputResolution != .p2160 || accessController.requirePaidFeature("4K export") else {
            onMessage?("4K export is locked. Get Early Price, then paste your key in Account.")
            return
        }
        settings.outputResolution = outputResolution
        persistSettings()
    }

    func setOutputVideoFormat(_ outputVideoFormat: OutputVideoFormat) {
        settings.outputVideoFormat = outputVideoFormat
        persistSettings()
    }

    func setFramesPerSecond(_ framesPerSecond: Int) {
        guard RecordingSettings.supportedFrameRates.contains(framesPerSecond) else { return }
        guard framesPerSecond < 60 || accessController.requirePaidFeature("60 fps export") else {
            onMessage?("60 fps export is locked. Get Early Price, then paste your key in Account.")
            return
        }
        settings.framesPerSecond = framesPerSecond
        persistSettings()
        onCameraConfigurationChanged?()
    }

    func setCustomVideoBitrate(_ bitrate: Int?) {
        if let bitrate {
            settings.customVideoBitrate = min(
                RecordingSettings.maxCustomVideoBitrate,
                max(RecordingSettings.minCustomVideoBitrate, bitrate)
            )
        } else {
            settings.customVideoBitrate = nil
        }
        persistSettings()
    }

    func setAudioQuality(_ audioQuality: AudioQuality) {
        settings.audioQuality = audioQuality
        persistSettings()
    }

    func setSourceAudioFormat(_ sourceAudioFormat: SourceAudioFormat) {
        settings.sourceAudioFormat = sourceAudioFormat
        persistSettings()
    }

    func setMicrophoneGain(_ microphoneGain: Double) {
        settings.microphoneGain = clampedGain(microphoneGain)
        persistSettings()
    }

    func setSystemAudioGain(_ systemAudioGain: Double) {
        settings.systemAudioGain = clampedGain(systemAudioGain)
        persistSettings()
    }

    func setCameraBackgroundRemovalAfterRecording(_ enabled: Bool) {
        let wasEnabled = settings.removesCameraBackgroundAfterRecording
        settings.removesCameraBackgroundAfterRecording = enabled
        if enabled, !wasEnabled {
            settings.cameraCropAmount = .zero
            settings.cameraCropPosition = .zero
            if settings.enabledSources.contains(.screen) {
                settings.selectedScenePreset = nil
                settings.screenCrop = nil
                settings.sceneLayout.screenFrame = clampedSceneFrame(
                    SceneLayout.canvasFillingFrame(
                        sourceAspectRatio: currentScreenSourceAspectRatio(),
                        canvasAspectRatio: settings.layout.aspectRatio
                    )
                )
                onScreenCaptureConfigurationChanged?()
            }
        }
        persistSettings()
        onCameraConfigurationChanged?()
    }

    func setSourceFilesSaved(_: Bool) {
        settings.savesSourceFiles = true
        persistSettings()
    }

    func setSpeechRenameEnabled(_ enabled: Bool) {
        settings.renamesRecordingsFromSpeech = enabled
        persistSettings()
    }

    func setRuleOfThirdsOverlayVisible(_ visible: Bool) {
        settings.showsRuleOfThirdsOverlay = visible
        persistSettings()
        onRuleOfThirdsOverlayChanged?(visible)
    }

    func setSocialSafeZoneOverlay(_ overlay: SocialVideoSafeZone) {
        settings.socialSafeZoneOverlay = overlay
        persistSettings()
        onSocialSafeZoneOverlayChanged?(overlay)
    }

    func setCursorIncluded(_ included: Bool) {
        settings.includeCursor = included
        persistSettings()
    }

    func setSource(_ source: CaptureSource, enabled: Bool) {
        guard state == .idle || takeRecording.isUsingLiveCompositor else {
            onMessage?("Capture source visibility is locked while recording.")
            return
        }
        if enabled {
            settings.enabledSources.insert(source)
            settings.hiddenSources.remove(source)
        } else if source == .screen || source == .camera {
            settings.enabledSources.insert(source)
            settings.hiddenSources.insert(source)
        } else {
            settings.enabledSources.remove(source)
            settings.hiddenSources.remove(source)
        }
        persistSettings()
        updateRecordingSceneIfNeeded()
        refreshAudioLevelMonitoring()
        if source == .camera {
            onCameraConfigurationChanged?()
        } else if source == .screen {
            onScreenCaptureConfigurationChanged?()
        }
    }

    func addSource(_ source: CaptureSource) {
        guard state == .idle else {
            onMessage?("Capture sources are locked while recording.")
            return
        }
        settings.enabledSources.insert(source)
        settings.hiddenSources.remove(source)
        persistSettings()
        refreshAudioLevelMonitoring()
        if source == .camera {
            onCameraConfigurationChanged?()
        } else if source == .screen {
            onScreenCaptureConfigurationChanged?()
        }
    }

    func removeSource(_ source: CaptureSource) {
        guard state == .idle else {
            onMessage?("Capture sources are locked while recording.")
            return
        }
        settings.enabledSources.remove(source)
        settings.hiddenSources.remove(source)
        persistSettings()
        refreshAudioLevelMonitoring()
        if source == .camera {
            onCameraConfigurationChanged?()
        } else if source == .screen {
            onScreenCaptureConfigurationChanged?()
        }
    }

    func setOutputDirectory(_ url: URL) {
        settings.outputDirectory = url
        settings.outputDirectoryBookmarkData = RecordingSettingsStore.bookmarkData(for: url)
        persistSettings()
    }

    func uniqueOutputURL(_ url: URL) -> URL {
        takeFileStore.uniqueFileURL(url)
    }

    func setDisplay(id: String?) {
        guard state == .idle else {
            onMessage?("Use the recording Screen control to switch sources mid-recording.")
            return
        }
        settings = screenSourceSelection.selectDisplay(
            ScreenSourceSelection.DisplayRequest(id: id, settings: settings)
        )
        currentPickedScreenSourceAspectRatio = nil
        persistSettings()
        refreshAudioLevelMonitoring()
        onScreenCaptureConfigurationChanged?()
    }

    func setScreenSource(_ binding: ScreenSourceBinding, autoFitWindowZoom: CGFloat? = nil) {
        guard state == .idle else {
            onMessage?("Use the recording Screen control to switch sources mid-recording.")
            return
        }
        cancelPendingScreenWindowFits()
        settings = screenSourceSelection.selectBinding(
            ScreenSourceSelection.BindingRequest(binding: binding, settings: settings)
        )
        currentPickedScreenSourceAspectRatio = nil
        settings.enabledSources.insert(.screen)
        settings.hiddenSources.remove(.screen)
        screenSourcePickerRecents.record(binding)
        if state == .idle {
            settings.screenContentMode = .fit
        }
        persistSettings()
        updateRecordingSceneIfNeeded()
        refreshAudioLevelMonitoring()
        onScreenCaptureConfigurationChanged?()
        if let autoFitWindowZoom, binding.kind != .display {
            autoFitScreenSourceWindow(binding, zoom: autoFitWindowZoom)
        }
    }

    func setCamera(id: String?) {
        guard id.map(RemoteCameraProviderID.isRemote) != true || accessController.requirePaidFeature("iPhone camera") else {
            onMessage?("iPhone camera is locked. Get Early Price, then paste your key in Account.")
            return
        }
        remoteCamera.selectCamera(id: id)
    }

    func setMicrophone(id: String?) {
        settings.selectedMicrophoneID = id
        persistSettings()
        refreshAudioLevelMonitoring()
    }

    func setSceneLayer(
        _ kind: SceneLayerKind,
        frame: CGRect,
        transition: RecordingSceneTransition = .cut
    ) {
        guard sceneChangeIsAllowed() else { return }
        settings.selectedScenePreset = nil
        var screenCaptureConfigurationChanged = false
        switch kind {
        case .screen:
            let nextFrame = clampedSceneFrame(frame)
            if settings.sceneLayout.screenFrame != nextFrame, settings.screenCrop != nil {
                settings.screenCrop = nil
                screenCaptureConfigurationChanged = true
            }
            settings.sceneLayout.screenFrame = nextFrame
        case .camera:
            settings.sceneLayout.cameraFrame = clampedSceneFrame(frame)
        }
        persistSettings()
        updateRecordingSceneIfNeeded(transition: transition)
        if screenCaptureConfigurationChanged {
            onScreenCaptureConfigurationChanged?()
        }
    }

    func setCameraCropAmount(_ amount: CGPoint) {
        guard sceneChangeIsAllowed() else { return }
        settings.cameraCropAmount = clampedCropAmount(amount)
        persistSettings()
        updateRecordingSceneIfNeeded()
    }

    func setCameraCropPosition(_ position: CGPoint) {
        guard sceneChangeIsAllowed() else { return }
        settings.cameraCropPosition = clampedCropPosition(position)
        persistSettings()
        updateRecordingSceneIfNeeded()
    }

    func setCanvasBackgroundStyle(_ style: CanvasBackgroundStyle) {
        guard sceneChangeIsAllowed() else { return }
        settings.canvasBackgroundStyle = style
        if !style.supportsBackgroundAnimation {
            settings.canvasBackgroundAnimated = false
        }
        persistSettings()
        updateRecordingSceneIfNeeded()
    }

    func setCanvasBackgroundAnimated(_ animated: Bool) {
        guard sceneChangeIsAllowed() else { return }
        settings.canvasBackgroundAnimated = animated && settings.canvasBackgroundStyle.supportsBackgroundAnimation
        persistSettings()
        updateRecordingSceneIfNeeded()
    }

    func setCanvasPadding(_ padding: CGFloat) {
        guard sceneChangeIsAllowed() else { return }
        settings.canvasPadding = clampedCanvasPadding(padding)
        persistSettings()
        updateRecordingSceneIfNeeded()
        autoFitSelectedScreenWindowToSceneSlot()
    }

    func setCameraContentMode(_ mode: CameraContentMode) {
        guard sceneChangeIsAllowed() else { return }
        settings.cameraContentMode = mode
        persistSettings()
        updateRecordingSceneIfNeeded()
    }

    func setScreenContentMode(_ mode: CameraContentMode) {
        guard sceneChangeIsAllowed() else { return }
        settings.screenContentMode = mode
        persistSettings()
        updateRecordingSceneIfNeeded()
    }

    func setCameraFramePadding(_ padding: CGFloat) {
        guard sceneChangeIsAllowed() else { return }
        settings.cameraFramePadding = 0
        persistSettings()
        updateRecordingSceneIfNeeded()
    }

    func setCameraShadowEnabled(_ enabled: Bool) {
        guard sceneChangeIsAllowed() else { return }
        settings.cameraShadowEnabled = enabled
        persistSettings()
        updateRecordingSceneIfNeeded()
    }

    func connectDirectRemoteCamera(host: String, portString: String) {
        guard accessController.requirePaidFeature("iPhone camera") else {
            onMessage?("iPhone camera is locked. Get Early Price, then paste your key in Account.")
            return
        }
        remoteCamera.connectDirect(host: host, portString: portString)
    }

    func setSceneLayout(_ sceneLayout: SceneLayout) {
        guard sceneChangeIsAllowed() else { return }
        let nextScreenFrame = clampedSceneFrame(sceneLayout.screenFrame)
        let nextCameraFrame = clampedSceneFrame(sceneLayout.cameraFrame)
        let screenCaptureConfigurationChanged = settings.sceneLayout.screenFrame != nextScreenFrame
            && settings.screenCrop != nil
        settings.selectedScenePreset = nil
        if screenCaptureConfigurationChanged {
            settings.screenCrop = nil
        }
        settings.sceneLayout.screenFrame = nextScreenFrame
        settings.sceneLayout.cameraFrame = nextCameraFrame
        settings.sceneLayout.layerOrder = sceneLayout.layerOrder
        persistSettings()
        updateRecordingSceneIfNeeded()
        if screenCaptureConfigurationChanged {
            onScreenCaptureConfigurationChanged?()
        }
    }

    func resetSceneLayout() {
        guard sceneChangeIsAllowed() else { return }
        settings.selectedScenePreset = nil
        settings.sceneLayout = SceneLayout.defaultLayout(
            for: settings.layout,
            screenAspectRatio: currentScreenSourceAspectRatio(),
            cameraAspectRatio: currentCameraSourceAspectRatio()
        )
        persistSettings()
        updateRecordingSceneIfNeeded(transition: .sceneSwitch)
        onScreenCaptureConfigurationChanged?()
        autoFitSelectedScreenWindowToSceneSlot()
    }

    func applyScenePreset(_ preset: ScenePreset) {
        guard sceneChangeIsAllowed() else { return }
        guard preset.supports(settings.layout) else { return }
        let cameraWasVisible = settings.enabledSources.contains(.camera)
            && !settings.hiddenSources.contains(.camera)
        settings.selectedScenePreset = preset
        settings.sceneLayout = SceneLayout.presetLayout(
            preset,
            for: settings.layout,
            screenAspectRatio: currentScreenSourceAspectRatio(),
            cameraAspectRatio: currentCameraSourceAspectRatio()
        )
        settings.enabledSources.insert(.screen)
        settings.enabledSources.insert(.camera)
        if preset == .webcamFullscreen {
            settings.hiddenSources.remove(.camera)
            settings.hiddenSources.insert(.screen)
            settings.screenCrop = nil
        } else if preset == .screenFullscreen {
            settings.hiddenSources.remove(.screen)
            settings.hiddenSources.insert(.camera)
            settings.screenCrop = nil
        } else {
            settings.hiddenSources.remove(.screen)
            settings.hiddenSources.remove(.camera)
        }
        persistSettings()
        updateRecordingSceneIfNeeded(transition: .sceneSwitch)
        onScreenCaptureConfigurationChanged?()
        let cameraIsVisible = settings.enabledSources.contains(.camera)
            && !settings.hiddenSources.contains(.camera)
        if cameraWasVisible != cameraIsVisible {
            onCameraConfigurationChanged?()
        }
        autoFitSelectedScreenWindowToSceneSlot()
    }

    func setScreenSplitHeight(_ height: CGFloat) {
        guard sceneChangeIsAllowed() else { return }
        guard settings.layout == .vertical else { return }
        let cameraWasVisible = settings.enabledSources.contains(.camera)
            && !settings.hiddenSources.contains(.camera)
        settings.selectedScenePreset = .screenTop50
        settings.sceneLayout = SceneLayout.screenSplitLayout(
            screenHeight: height,
            screenAspectRatio: currentScreenSourceAspectRatio()
        )
        settings.screenCrop = nil
        settings.enabledSources.insert(.screen)
        settings.enabledSources.insert(.camera)
        settings.hiddenSources.remove(.screen)
        settings.hiddenSources.remove(.camera)
        persistSettings()
        updateRecordingSceneIfNeeded(transition: .sceneSwitch)
        onScreenCaptureConfigurationChanged?()
        if !cameraWasVisible {
            onCameraConfigurationChanged?()
        }
        autoFitSelectedScreenWindowToSceneSlot()
    }

    func setCameraInset(
        alignment: CameraInsetAlignment,
        shape: CameraInsetShape,
        size: CGFloat
    ) {
        guard sceneChangeIsAllowed() else { return }
        let screenWasVisible = settings.enabledSources.contains(.screen)
            && !settings.hiddenSources.contains(.screen)
        let cameraWasVisible = settings.enabledSources.contains(.camera)
            && !settings.hiddenSources.contains(.camera)
        let nextScreenFrame = SceneLayout.canvasFillingFrame(
            sourceAspectRatio: currentScreenSourceAspectRatio(),
            canvasAspectRatio: settings.layout.aspectRatio
        )
        let screenCaptureConfigurationChanged = settings.sceneLayout.screenFrame != nextScreenFrame
            && settings.screenCrop != nil

        settings.selectedScenePreset = nil
        settings.sceneLayout.screenFrame = nextScreenFrame
        settings.sceneLayout.cameraFrame = SceneLayout.cameraInsetFrame(
            for: settings.layout,
            alignment: alignment,
            shape: shape,
            size: size,
            sourceAspectRatio: currentCameraSourceAspectRatio()
        )
        settings.sceneLayout.layerOrder = [.screen, .camera]
        settings.enabledSources.insert(.screen)
        settings.enabledSources.insert(.camera)
        settings.hiddenSources.remove(.screen)
        settings.hiddenSources.remove(.camera)
        if screenCaptureConfigurationChanged {
            settings.screenCrop = nil
        }

        persistSettings()
        updateRecordingSceneIfNeeded()
        if screenCaptureConfigurationChanged || !screenWasVisible {
            onScreenCaptureConfigurationChanged?()
        }
        if !cameraWasVisible {
            onCameraConfigurationChanged?()
        }
        autoFitSelectedScreenWindowToSceneSlot()
    }

    func targetWindowInfo() throws -> TargetWindowInfo {
        try ShortsWindowArranger.frontWindowInfo(displayID: settings.selectedDisplayID)
    }

    func fitFrontWindowForShorts() {
        fitFrontWindowForShorts(zoom: 1)
    }

    @discardableResult
    func fitScreenToAvailableSlot() -> CGRect {
        guard sceneChangeIsAllowed() else { return settings.sceneLayout.screenFrame }
        let screenSlot = SceneSlotGeometry.screenSlot(
            in: settings.sceneLayout,
            enabledSources: settings.enabledSources
        )
        settings.selectedScenePreset = nil
        settings.sceneLayout.screenFrame = clampedSceneFrame(screenSlot)
        settings.screenCrop = nil
        persistSettings()
        updateRecordingSceneIfNeeded(transition: .sceneSwitch)
        onScreenCaptureConfigurationChanged?()
        return settings.sceneLayout.screenFrame
    }

    func fitScreenItemToFrontWindow() {
        guard sceneChangeIsAllowed() else { return }
        guard ensureAccessibilityForWindowControls() else { return }

        do {
            let arrangement = try ShortsWindowArranger.screenItemForFrontWindow(
                displayID: settings.selectedDisplayID
            )
            settings.screenCrop = clampedNormalizedRect(arrangement.screenCrop)
            persistSettings()
            updateRecordingSceneIfNeeded()
            onScreenCaptureConfigurationChanged?()
            onMessage?(arrangement.screenItemMessage)
        } catch {
            onMessage?(error.localizedDescription)
        }
    }

    func fitFrontWindowForShorts(zoom: CGFloat) {
        guard sceneChangeIsAllowed() else { return }

        cancelPendingScreenWindowFits()
        guard ensureAccessibilityForWindowControls() else { return }

        do {
            let arrangement = try ShortsWindowArranger.fitFrontWindow(
                displayID: settings.selectedDisplayID,
                captureLayout: settings.layout,
                sceneLayout: settings.sceneLayout,
                enabledSources: settings.enabledSources,
                canvasPadding: settings.canvasPadding,
                zoom: zoom
            )
            settings.screenCrop = clampedNormalizedRect(arrangement.screenCrop)
            persistSettings()
            updateRecordingSceneIfNeeded()
            onScreenCaptureConfigurationChanged?()
            onMessage?(arrangement.message)
        } catch {
            onMessage?(error.localizedDescription)
        }
    }

    func fitScreenSourceWindow(_ binding: ScreenSourceBinding, zoom: CGFloat) {
        guard sceneChangeIsAllowed() else { return }
        guard ensureAccessibilityForWindowControls() else { return }
        let revision = beginScreenWindowFit()

        Task { [weak self, binding] in
            guard let self else { return }
            do {
                guard let arrangement = try await self.screenSourceWindowArrangement(
                    for: binding,
                    zoom: zoom,
                    revision: revision
                ) else { return }
                self.applyFittedScreenWindowArrangement(arrangement, shouldUpdateCapture: true)
                self.onMessage?(arrangement.resizedMessage)
            } catch {
                guard self.isCurrentScreenSourceWindowFit(revision, binding: binding) else { return }
                self.onMessage?(error.localizedDescription)
            }
        }
    }

    func fitPickedScreenWindowToSlot(zoom: CGFloat) {
        guard sceneChangeIsAllowed() else { return }
        guard settings.usesPickedScreenContent,
              let pickedScreenFilter = screenSourceSelection.pickedContentFilter else {
            onMessage?("Pick a screen source before resizing its window.")
            return
        }
        guard settings.screenSourceBinding?.kind != .display else {
            onMessage?("A display has no source window to resize. Use Screen framing instead.")
            return
        }
        guard ensureAccessibilityForWindowControls() else { return }
        let revision = beginScreenWindowFit()

        Task { [weak self, pickedScreenFilter] in
            guard let self else { return }
            _ = await self.fitPickedScreenWindow(
                pickedScreenFilter,
                zoom: zoom,
                shouldUpdateCapture: true,
                revision: revision
            )
        }
    }

    func zoomScreenSourceContent(_ direction: AppContentZoomDirection) {
        guard ensureAccessibilityForWindowControls() else { return }
        let context = screenSourceActionContext()

        Task { [weak self] in
            guard let self else { return }
            guard let processID = await self.targetProcessIDForScreenContentZoom() else {
                self.onMessage?("Select an app or window before changing app content size.")
                return
            }
            guard self.screenSourceActionContext() == context else { return }

            guard AppContentZoomer.apply(AppContentZoomer.Request(
                direction: direction,
                processID: processID
            )) else {
                self.onMessage?("Could not map the app content shortcut for this keyboard.")
                return
            }
            self.onMessage?("\(direction.messageVerb) selected app content.")
        }
    }

    private func autoFitScreenSourceWindow(_ binding: ScreenSourceBinding, zoom: CGFloat) {
        guard permissionGate.hasAccessibilityAccess else { return }
        let revision = beginScreenWindowFit()
        Task { [weak self, binding] in
            guard let self else { return }
            do {
                guard let arrangement = try await ScreenWindowFitRetry.run({
                    try await self.screenSourceWindowArrangement(
                        for: binding,
                        zoom: zoom,
                        revision: revision
                    )
                }) else { return }
                self.applyFittedScreenWindowArrangement(arrangement, shouldUpdateCapture: true)
                self.onMessage?(arrangement.resizedMessage)
            } catch {
                guard self.isCurrentScreenSourceWindowFit(revision, binding: binding) else { return }
                self.onMessage?(error.localizedDescription)
            }
        }
    }

    private func autoFitSelectedScreenWindowToSceneSlot() {
        guard settings.visibleSources.contains(.screen) else { return }
        guard permissionGate.hasAccessibilityAccess else { return }

        if settings.usesPickedScreenContent {
            guard let filter = screenSourceSelection.pickedContentFilter,
                  let sourceKind = activePickedScreenContentKind,
                  sourceKind == .application || sourceKind == .window else {
                return
            }
            Task { [weak self, filter] in
                await self?.autoFitPickedScreenWindow(filter)
            }
            return
        }

        guard let binding = settings.screenSourceBinding,
              binding.kind != .display else {
            return
        }
        autoFitScreenSourceWindow(binding, zoom: settings.screenWindowZoom)
    }

    private func screenSourceWindowArrangement(
        for binding: ScreenSourceBinding,
        zoom: CGFloat,
        revision: Int
    ) async throws -> ShortsWindowArrangement? {
        let displayID = targetDisplayID(for: binding)
        if binding.kind == .application {
            if let target = await ScreenCaptureGeometry.applicationWindowTarget(for: binding) {
                guard isCurrentScreenSourceWindowFit(revision, binding: binding) else {
                    return nil
                }
                return try ShortsWindowArranger.fitWindow(
                    ownerPID: target.pid,
                    bounds: target.bounds,
                    title: target.title,
                    appName: target.appName ?? binding.applicationName ?? "Application",
                    displayID: target.displayID ?? displayID,
                    captureLayout: settings.layout,
                    sceneLayout: settings.sceneLayout,
                    enabledSources: settings.enabledSources,
                    canvasPadding: settings.canvasPadding,
                    zoom: zoom
                )
            }

            if let processID = processID(forApplicationBinding: binding) {
                guard isCurrentScreenSourceWindowFit(revision, binding: binding) else {
                    return nil
                }
                return try ShortsWindowArranger.fitAppWindow(
                    ownerPID: processID,
                    appName: binding.applicationName ?? "Application",
                    displayID: displayID,
                    captureLayout: settings.layout,
                    sceneLayout: settings.sceneLayout,
                    enabledSources: settings.enabledSources,
                    canvasPadding: settings.canvasPadding,
                    zoom: zoom
                )
            }
        }

        guard let target = await ScreenCaptureGeometry.windowTarget(for: binding) else {
            throw ShortsWindowArrangerError.noWindowFound
        }
        guard isCurrentScreenSourceWindowFit(revision, binding: binding) else {
            return nil
        }

        return try ShortsWindowArranger.fitWindow(
            ownerPID: target.pid,
            bounds: target.bounds,
            title: target.title,
            appName: target.appName ?? "",
            displayID: target.displayID ?? displayID,
            captureLayout: settings.layout,
            sceneLayout: settings.sceneLayout,
            enabledSources: settings.enabledSources,
            canvasPadding: settings.canvasPadding,
            zoom: zoom
        )
    }

    private func beginScreenWindowFit() -> Int {
        screenWindowFitRevision += 1
        return screenWindowFitRevision
    }

    private func cancelPendingScreenWindowFits() {
        screenWindowFitRevision += 1
    }

    private func isCurrentScreenSourceWindowFit(
        _ revision: Int,
        binding: ScreenSourceBinding
    ) -> Bool {
        revision == screenWindowFitRevision
            && settings.screenSourceBinding == binding
            && !settings.usesPickedScreenContent
    }

    private func isCurrentPickedScreenWindowFit(_ revision: Int) -> Bool {
        revision == screenWindowFitRevision && settings.usesPickedScreenContent
    }

    private func screenSourceActionContext() -> ScreenSourceActionContext {
        ScreenSourceActionContext(
            screenWindowFitRevision: screenWindowFitRevision,
            screenContentSelectionRevision: screenContentSelectionRevision,
            screenSourceBinding: settings.screenSourceBinding,
            usesPickedScreenContent: settings.usesPickedScreenContent
        )
    }

    private func processID(forApplicationBinding binding: ScreenSourceBinding) -> pid_t? {
        if let processID = binding.processID,
           let application = NSRunningApplication(processIdentifier: processID),
           applicationMatchesBinding(application, binding: binding) {
            return processID
        }
        if let bundleIdentifier = binding.bundleIdentifier {
            let applications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            return (applications.first(where: { $0.activationPolicy == .regular }) ?? applications.first)?
                .processIdentifier
        }
        if let applicationName = binding.applicationName {
            return NSWorkspace.shared.runningApplications
                .first { $0.localizedName == applicationName && $0.activationPolicy == .regular }?
                .processIdentifier
        }
        return nil
    }

    private func targetProcessIDForScreenContentZoom() async -> pid_t? {
        await AppContentZoomTargetResolver.processID(
            settings: settings,
            pickedWindowProcessID: { [weak self] in
                guard let filter = self?.screenSourceSelection.pickedContentFilter else { return nil }
                return await ScreenCaptureGeometry.pickedWindowTarget(for: filter)?.pid
            },
            applicationProcessID: { [weak self] binding in
                self?.processID(forApplicationBinding: binding)
            },
            windowProcessID: { binding in
                await ScreenCaptureGeometry.windowTarget(for: binding)?.pid
            },
            frontWindowProcessID: { [weak self] displayID in
                self?.frontWindowProcessIDForScreenContentZoom(displayID: displayID)
            }
        )
    }

    private func frontWindowProcessIDForScreenContentZoom(displayID: String?) -> pid_t? {
        try? ShortsWindowArranger.frontWindowInfo(displayID: displayID).processID
    }

    private func applicationMatchesBinding(
        _ application: NSRunningApplication,
        binding: ScreenSourceBinding
    ) -> Bool {
        if let bundleIdentifier = binding.bundleIdentifier,
           application.bundleIdentifier != bundleIdentifier {
            return false
        }
        if let applicationName = binding.applicationName,
           let localizedName = application.localizedName,
           localizedName != applicationName {
            return false
        }
        return true
    }

    private func targetDisplayID(for binding: ScreenSourceBinding) -> String? {
        binding.displayID ?? settings.selectedDisplayID
    }

    func resizeTargetWindow(widthDelta: CGFloat, heightDelta: CGFloat) {
        guard ensureAccessibilityForWindowControls() else { return }

        clearCustomScreenCrop()
        do {
            let arrangement = try ShortsWindowArranger.resizeFrontWindow(
                displayID: settings.selectedDisplayID,
                widthDelta: widthDelta,
                heightDelta: heightDelta
            )
            onMessage?(arrangement.resizedMessage)
        } catch {
            onMessage?(error.localizedDescription)
        }
    }

    func setTargetWindowSize(width: CGFloat, height: CGFloat) {
        guard ensureAccessibilityForWindowControls() else { return }

        clearCustomScreenCrop()
        do {
            let arrangement = try ShortsWindowArranger.setFrontWindowSize(
                displayID: settings.selectedDisplayID,
                width: width,
                height: height
            )
            onMessage?(arrangement.resizedMessage)
        } catch {
            onMessage?(error.localizedDescription)
        }
    }

    private func ensureAccessibilityForWindowControls() -> Bool {
        if permissionGate.hasAccessibilityAccess {
            return true
        }

        Task { _ = await permissionGate.requestAccessibilityAccessForWindowControls() }
        if permissionGate.hasAccessibilityAccess {
            return true
        }

        permissionGate.openAccessibilitySettings()
        onMessage?("Enable Accessibility for BlitzRecorder to resize target windows.")
        return false
    }

    func setSceneLayerOrder(_ order: [SceneLayerKind]) {
        guard sceneChangeIsAllowed() else { return }
        guard Set(order) == Set(SceneLayerKind.allCases),
              order.count == SceneLayerKind.allCases.count else {
            return
        }
        settings.selectedScenePreset = nil
        settings.sceneLayout.layerOrder = order
        persistSettings()
        updateRecordingSceneIfNeeded(transition: .sceneSwitch)
    }

    func fitSceneLayer(_ kind: SceneLayerKind, scale: CGFloat = 1) {
        let sourceAspectRatio: CGFloat
        switch kind {
        case .screen:
            sourceAspectRatio = currentScreenSourceAspectRatio()
        case .camera:
            sourceAspectRatio = currentCameraSourceAspectRatio()
        }
        let frame: CGRect
        if kind == .screen, shouldConstrainScreenFillToCameraSlot {
            frame = SceneSlotGeometry.screenSlot(
                in: settings.sceneLayout,
                enabledSources: settings.visibleSources
            )
        } else {
            frame = canvasFillingSceneFrame(sourceAspectRatio: sourceAspectRatio)
        }
        setSceneLayer(kind, frame: scaledSceneFrame(frame, scale: scale), transition: .sceneSwitch)
    }

    private var shouldConstrainScreenFillToCameraSlot: Bool {
        guard settings.visibleSources.contains(.screen),
              settings.visibleSources.contains(.camera),
              !settings.removesCameraBackgroundAfterRecording else {
            return false
        }

        let cameraFrame = SceneLayerResizing.clamped(settings.sceneLayout.cameraFrame.standardized)
        let epsilon: CGFloat = 0.001
        let spansCanvasWidth = cameraFrame.minX <= epsilon
            && cameraFrame.maxX >= 1 - epsilon
            && cameraFrame.height < 0.95
        let spansCanvasHeight = cameraFrame.minY <= epsilon
            && cameraFrame.maxY >= 1 - epsilon
            && cameraFrame.width < 0.95

        return spansCanvasWidth || spansCanvasHeight
    }

    private func canvasFillingSceneFrame(sourceAspectRatio: CGFloat) -> CGRect {
        SceneLayout.canvasFillingFrame(
            sourceAspectRatio: sourceAspectRatio,
            canvasAspectRatio: settings.layout.aspectRatio
        )
    }

    private func scaledSceneFrame(_ frame: CGRect, scale: CGFloat) -> CGRect {
        let scale = min(1, max(0.1, scale))
        let width = frame.width * scale
        let height = frame.height * scale
        return CGRect(
            x: frame.midX - width / 2,
            y: frame.midY - height / 2,
            width: width,
            height: height
        )
    }

    func currentScreenSourceAspectRatio() -> CGFloat {
        if !isEditingScreenCrop,
           settings.screenSourceBinding?.kind != .display,
           let currentPickedScreenSourceAspectRatio,
           currentPickedScreenSourceAspectRatio > 0 {
            return currentPickedScreenSourceAspectRatio
        }
        if settings.usesPickedScreenContent && !isEditingScreenCrop {
            if let currentPickedScreenSourceAspectRatio,
               currentPickedScreenSourceAspectRatio > 0 {
                return currentPickedScreenSourceAspectRatio
            }
            if let filter = screenSourceSelection.pickedContentFilter {
                return ScreenCaptureGeometry.pickedContentAspectRatio(for: filter)
            }
            return SceneLayout.defaultScreenAspectRatio
        }

        let displayID: CGDirectDisplayID
        if let selectedDisplayID = settings.selectedDisplayID,
           let numericID = UInt32(selectedDisplayID) {
            displayID = numericID
        } else {
            displayID = CGMainDisplayID()
        }

        let width = CGDisplayPixelsWide(displayID)
        let height = CGDisplayPixelsHigh(displayID)
        guard width > 0, height > 0 else {
            return SceneLayout.defaultScreenAspectRatio
        }
        return ScreenCaptureGeometry.screenSourceAspectRatio(
            for: isEditingScreenCrop ? screenSettingsWithoutCrop() : settings,
            fallback: CGFloat(width) / CGFloat(height)
        )
    }

    func beginScreenCropEditing() {
        guard sceneChangeIsAllowed() else { return }
        if clearIncompatibleScreenCropForCurrentLayout() {
            persistSettings()
        }
        isEditingScreenCrop = true
        onScreenCaptureConfigurationChanged?()
    }

    func endScreenCropEditing() {
        guard isEditingScreenCrop else { return }
        isEditingScreenCrop = false
        onScreenCaptureConfigurationChanged?()
    }

    func setScreenCrop(_ crop: CGRect?) {
        guard sceneChangeIsAllowed() else { return }
        if let crop {
            let clampedCrop = clampedNormalizedRect(crop)
            settings.screenCrop = isEffectivelyFullDisplayCrop(clampedCrop) ? nil : clampedCrop
        } else {
            settings.screenCrop = nil
        }
        persistSettings()
        updateRecordingSceneIfNeeded()
        onScreenCaptureConfigurationChanged?()
    }

    func setScreenWindowZoom(_ zoom: CGFloat) {
        guard sceneChangeIsAllowed() else { return }
        let zoom = ScreenSourceZoomGeometry.clamped(zoom)
        guard abs(settings.screenWindowZoom - zoom) > 0.0001 else { return }
        settings.screenWindowZoom = zoom
        persistSettings()
    }

    func setScreenSourceZoom(_ zoom: CGFloat) {
        setScreenWindowZoom(zoom)
    }

    func currentCameraSourceAspectRatio() -> CGFloat {
        knownCameraSourceAspectRatio() ?? SceneLayout.cameraAspectRatio
    }

    private func knownCameraSourceAspectRatio() -> CGFloat? {
        if RemoteCameraProviderID.serviceID(from: settings.selectedCameraID) != nil {
            let unknown: CGFloat = -1
            let aspectRatio = remoteCamera.currentCameraSourceAspectRatio(fallback: unknown)
            return aspectRatio > 0 ? aspectRatio : nil
        }
        if let device = LocalCameraSessionConfiguration.selectedCamera(settings: settings, fallbackToDefault: true) {
            let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
            if dimensions.width > 0, dimensions.height > 0 {
                return CGFloat(dimensions.width) / CGFloat(dimensions.height)
            }
        }
        return nil
    }

    func refitCameraInsetToCurrentCamera() {
        guard state == .idle, allowsSceneChanges else { return }
        guard refitCameraInsetFrameForCurrentSource() else { return }
        persistSettings()
        updateRecordingSceneIfNeeded()
    }

    @discardableResult
    private func refitCameraInsetFrameForCurrentSource() -> Bool {
        guard let sourceAspectRatio = knownCameraSourceAspectRatio() else { return false }
        let frame = settings.sceneLayout.cameraFrame
        guard SceneLayout.isCameraInsetFrame(frame) else { return false }
        let next = SceneLayout.cameraInsetFrame(
            for: settings.layout,
            alignment: SceneLayout.cameraInsetAlignment(for: frame),
            shape: SceneLayout.cameraInsetShape(for: frame, in: settings.layout),
            size: SceneLayout.cameraInsetSize(for: frame, in: settings.layout),
            sourceAspectRatio: sourceAspectRatio
        )
        let epsilon: CGFloat = 0.0005
        guard abs(next.minX - frame.minX) > epsilon
            || abs(next.minY - frame.minY) > epsilon
            || abs(next.width - frame.width) > epsilon
            || abs(next.height - frame.height) > epsilon else { return false }
        settings.sceneLayout.cameraFrame = next
        return true
    }

    func selectScreenCrop() async throws {
        let crop = try await screenCropPicker.pick(
            displayID: settings.selectedDisplayID,
            initialCrop: settings.screenCrop
        )
        guard !crop.isNull, crop.width > 0, crop.height > 0 else {
            throw ScreenCropPickerError.selectionTooSmall
        }

        let clampedCrop = clampedNormalizedRect(crop)
        settings.screenCrop = isEffectivelyFullDisplayCrop(clampedCrop) ? nil : clampedCrop
        persistSettings()
        updateRecordingSceneIfNeeded()
        onScreenCaptureConfigurationChanged?()
    }

    private func screenSettingsWithoutCrop() -> RecordingSettings {
        var settings = settings
        settings.screenCrop = nil
        return settings
    }

    func clearScreenCrop() {
        settings.screenCrop = nil
        persistSettings()
        updateRecordingSceneIfNeeded()
        onScreenCaptureConfigurationChanged?()
    }

    private func clearCustomScreenCrop() {
        guard settings.screenCrop != nil else { return }
        settings.screenCrop = nil
        persistSettings()
        updateRecordingSceneIfNeeded()
        onScreenCaptureConfigurationChanged?()
    }

    func availableDisplays() async -> [SourceOption] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var displays = Array(repeating: CGDirectDisplayID(), count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)

        return displays.map { displayID in
            let width = CGDisplayPixelsWide(displayID)
            let height = CGDisplayPixelsHigh(displayID)
            return SourceOption(id: "\(displayID)", name: "Display \(displayID) (\(width)x\(height))")
        }
    }

    func availableScreenSources() async -> [ScreenSourceOption] {
        guard permissionGate.hasScreenCaptureAccess,
              let content = try? await SCShareableContent.current else {
            return []
        }

        let ownProcessID = getpid()
        let displayOptions = content.displays.enumerated().map { index, display in
            ScreenSourceOption(
                binding: .display(id: String(display.displayID)),
                title: "Display \(index + 1)",
                subtitle: "\(display.width) × \(display.height)",
                systemImage: "display",
                icon: nil
            )
        }
        let recentBundleIdentifiers = screenSourcePickerRecents.bundleIdentifiers()
        var applicationKeys: Set<String> = []
        let applicationOptions = content.applications.compactMap { application -> ScreenSourceOption? in
            let applicationName = Self.readableScreenApplicationName(application.applicationName)
            guard application.processID != ownProcessID,
                  !Self.isIgnoredScreenApplication(
                    bundleIdentifier: application.bundleIdentifier,
                    applicationName: applicationName
                  ),
                  let applicationName else {
                return nil
            }
            let key = Self.screenApplicationKey(
                bundleIdentifier: application.bundleIdentifier,
                processID: application.processID,
                applicationName: applicationName
            )
            guard applicationKeys.insert(key).inserted else { return nil }
            let primaryWindow = content.windows
                .filter {
                    $0.isOnScreen
                        && $0.frame.width > 0
                        && $0.frame.height > 0
                        && $0.owningApplication?.processID == application.processID
                }
                .max {
                    $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
                }
            let binding = ScreenSourceBinding(
                kind: .application,
                displayID: primaryWindow.flatMap {
                    displayID(for: $0, displays: content.displays)
                },
                bundleIdentifier: application.bundleIdentifier,
                applicationName: applicationName,
                processID: application.processID,
                windowID: nil,
                windowTitle: nil
            )
            return ScreenSourceOption(
                binding: binding,
                title: applicationName,
                subtitle: "Main window",
                systemImage: "macwindow.on.rectangle",
                icon: Self.appIcon(
                    bundleIdentifier: application.bundleIdentifier,
                    processID: application.processID
                ),
                pickerPlacement: ScreenSourcePickerOrganization.placement(
                    ScreenSourcePickerPlacementRequest(
                        binding: binding,
                        recentBundleIdentifiers: recentBundleIdentifiers
                    )
                )
            )
        }
        let sortedApplicationOptions = ScreenSourcePickerOrganization.sorted(applicationOptions)

        let windowOptions = content.windows.compactMap { window -> ScreenSourceOption? in
            let application = window.owningApplication
            let applicationName = Self.readableScreenApplicationName(application?.applicationName)
            guard window.isOnScreen,
                  window.frame.width >= 240,
                  window.frame.height >= 160,
                  application?.processID != ownProcessID,
                  !Self.isIgnoredScreenWindow(
                    bundleIdentifier: application?.bundleIdentifier,
                    applicationName: applicationName,
                    title: window.title
                  ) else {
                return nil
            }
            let windowTitle = Self.readableScreenWindowTitle(window.title)
            let title = windowTitle ?? applicationName.map { "\($0) window" } ?? "Window"
            let binding = ScreenSourceBinding(
                kind: .window,
                displayID: displayID(for: window, displays: content.displays),
                bundleIdentifier: application?.bundleIdentifier,
                applicationName: applicationName,
                processID: application?.processID,
                windowID: window.windowID,
                windowTitle: window.title
            )
            return ScreenSourceOption(
                binding: binding,
                title: title,
                subtitle: applicationName ?? "Window",
                systemImage: "app.window",
                icon: Self.appIcon(
                    bundleIdentifier: application?.bundleIdentifier,
                    processID: application?.processID
                ),
                pickerPlacement: ScreenSourcePickerOrganization.placement(
                    ScreenSourcePickerPlacementRequest(
                        binding: binding,
                        recentBundleIdentifiers: recentBundleIdentifiers
                    )
                )
            )
        }
        .sorted { lhs, rhs in
            let lhsLabel = "\(lhs.subtitle) \(lhs.title)"
            let rhsLabel = "\(rhs.subtitle) \(rhs.title)"
            return lhsLabel.localizedCaseInsensitiveCompare(rhsLabel) == .orderedAscending
        }

        return displayOptions + sortedApplicationOptions + windowOptions
    }

    func screenSourceThumbnails(for bindings: [ScreenSourceBinding]) async -> [String: NSImage] {
        [:]
    }

    static func readableScreenApplicationName(_ name: String?) -> String? {
        guard let name else { return nil }
        let collapsed = name
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return nil }

        let genericNames = [
            "Application",
            "Window"
        ]
        guard !genericNames.contains(where: { collapsed.localizedCaseInsensitiveCompare($0) == .orderedSame }) else {
            return nil
        }
        return collapsed
    }

    static func screenApplicationKey(
        bundleIdentifier: String?,
        processID: pid_t?,
        applicationName: String?
    ) -> String {
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return "bundle:\(bundleIdentifier)"
        }
        if let processID {
            return "pid:\(processID)"
        }
        return "name:\(readableScreenApplicationName(applicationName) ?? "unknown")"
    }

    static func isIgnoredScreenApplication(
        bundleIdentifier: String?,
        applicationName: String?
    ) -> Bool {
        let ignoredBundleIdentifiers: Set<String> = [
            "com.apple.AirDropUIAgent",
            "com.apple.controlcenter",
            "com.apple.dock",
            "com.apple.loginwindow",
            "com.apple.notificationcenterui",
            "com.apple.ScreenContinuity",
            "com.apple.Siri",
            "com.apple.Spotlight",
            "com.apple.systemuiserver",
            "com.apple.TextInputMenuAgent",
            "com.apple.WindowManager",
            "com.apple.wallpaper"
        ]
        if let bundleIdentifier,
           ignoredBundleIdentifiers.contains(bundleIdentifier) {
            return true
        }

        guard let applicationName = readableScreenApplicationName(applicationName) else {
            return true
        }
        let ignoredExactNames: Set<String> = [
            "Accessibility",
            "AirDrop",
            "Control Center",
            "Dock",
            "Notification Center",
            "SystemUIServer",
            "TextInputMenuAgent",
            "WindowManager"
        ]
        if ignoredExactNames.contains(applicationName) {
            return true
        }

        let ignoredNameFragments = [
            "AutoFill",
            "Display Backstop",
            "Helper",
            "LifecycleKeepalive",
            "StatusIndicator",
            "underbelly"
        ]
        return ignoredNameFragments.contains { applicationName.localizedCaseInsensitiveContains($0) }
    }

    static func isIgnoredScreenWindow(
        bundleIdentifier: String?,
        applicationName: String?,
        title: String?
    ) -> Bool {
        let ignoredBundleIdentifiers: Set<String> = [
            "com.apple.AirDropUIAgent",
            "com.apple.controlcenter",
            "com.apple.dock",
            "com.apple.loginwindow",
            "com.apple.notificationcenterui",
            "com.apple.ScreenContinuity",
            "com.apple.Siri",
            "com.apple.Spotlight",
            "com.apple.systemuiserver",
            "com.apple.TextInputMenuAgent",
            "com.apple.WindowManager",
            "com.apple.wallpaper"
        ]
        if let bundleIdentifier,
           ignoredBundleIdentifiers.contains(bundleIdentifier) {
            return true
        }

        if isIgnoredScreenApplication(bundleIdentifier: bundleIdentifier, applicationName: applicationName) {
            return true
        }

        let ignoredApplicationNames: Set<String> = [
            "Accessibility",
            "Control Center",
            "Dock",
            "Notification Center",
            "StatusIndicator",
            "SystemUIServer",
            "TextInputMenuAgent",
            "WindowManager",
            "underbelly"
        ]
        if let applicationName,
           ignoredApplicationNames.contains(applicationName) {
            return true
        }

        let ignoredTitleFragments = [
            "Display Backstop",
            "Item-0",
            "LifecycleKeepalive",
            "StatusItem",
            "StatusIndicator",
            "Menubar",
            "Menu Bar",
            "underbelly"
        ]
        let title = title ?? ""
        return ignoredTitleFragments.contains { title.localizedCaseInsensitiveContains($0) }
    }

    private static func appIcon(bundleIdentifier: String?, processID: pid_t?) -> NSImage? {
        if let processID,
           let icon = NSRunningApplication(processIdentifier: processID)?.icon {
            return icon
        }
        if let bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
    }

    static func readableScreenWindowTitle(_ title: String?) -> String? {
        guard let title else { return nil }
        let collapsed = title
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return nil }

        let genericTitles = [
            "Untitled",
            "Untitled window",
            "Window",
            "New Window"
        ]
        guard !genericTitles.contains(where: { collapsed.localizedCaseInsensitiveCompare($0) == .orderedSame }) else {
            return nil
        }
        return collapsed
    }

    private func displayID(for window: SCWindow, displays: [SCDisplay]) -> String? {
        let display = displays.max { lhs, rhs in
            overlapArea(lhs.frame, window.frame) < overlapArea(rhs.frame, window.frame)
        }
        return display.map { "\($0.displayID)" }
    }

    private func overlapArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    func hasScreenCaptureAccess() -> Bool {
        permissionGate.hasScreenCaptureAccess
    }

    @discardableResult
    func reconcilePersistentScreenAccessIfNeeded() -> Bool {
        let result = screenSourceSelection.reconcile(
            ScreenSourceSelection.ReconciliationRequest(
                settings: settings,
                hasPersistentAccess: permissionGate.hasScreenCaptureAccess
            )
        )
        guard result.changed else { return false }
        settings = result.settings
        persistSettings()
        onScreenCaptureConfigurationChanged?()
        return true
    }

    func hasRequiredPermissions() -> Bool {
        recordingReadiness().isReady
    }

    func missingPermissionNames() -> [String] {
        recordingReadiness().blockers.map(\.permission)
    }

    func recordingReadiness() -> RecordingReadiness {
        var readiness = permissionGate.readiness(for: settings)
        let needsPicker = (
            settings.enabledSources.contains(.screen)
                && !hasActiveScreenSourceSelection
        ) || (
            settings.enabledSources.contains(.systemAudio)
                && !hasActiveScreenSourceSelection
        )
        if needsPicker {
            let source: CaptureSource = settings.enabledSources.contains(.screen) ? .screen : .systemAudio
            let blocker = PermissionBlocker(
                source: source,
                permission: "Screen source",
                status: "not selected for this session",
                recovery: "Choose a display or window with the macOS picker."
            )
            let blockers = readiness.blockers.filter {
                $0.source != .screen && $0.source != .systemAudio
            } + [blocker]
            let statusLine = "\(readiness.statusLine) | Screen source: not selected"
            readiness = RecordingReadiness(
                isReady: false,
                title: readiness.title,
                detail: "Start disabled: \(statusLine)",
                blockers: blockers,
                statusLine: statusLine
            )
        }
        if let remoteBlocker = remoteCameraConnectionBlocker() {
            let blockers = readiness.blockers + [remoteBlocker]
            return RecordingReadiness(
                isReady: false,
                title: readiness.title,
                detail: "Start disabled: \(readiness.statusLine) | Camera: \(remoteBlocker.status)",
                blockers: blockers,
                statusLine: "\(readiness.statusLine) | Camera: \(remoteBlocker.status)"
            )
        }

        return localCameraRuntimeState.applying(.init(
            readiness: readiness,
            settings: settings,
            isRemoteCameraSelected: isRemoteCameraSelected
        ))
    }

    func setLocalCameraRuntimeState(_ state: LocalCameraRuntimeState) {
        localCameraRuntimeState = state
    }

    func pickScreenContent() async throws {
        try await pickScreenContent(.init(
            activatesScreenSource: false,
            selectionPolicy: .anyScreenContent
        ))
    }

    func pickScreenSource() async throws {
        try await pickScreenContent(.init(
            activatesScreenSource: true,
            selectionPolicy: .appWindow
        ))
    }

    func pickFullScreenSource() async throws {
        try await pickScreenContent(.init(
            activatesScreenSource: true,
            selectionPolicy: .fullScreen
        ))
    }

    private struct PickScreenContentRequest {
        let activatesScreenSource: Bool
        let selectionPolicy: ScreenContentPickerSelectionPolicy
    }

    private func pickScreenContent(_ request: PickScreenContentRequest) async throws {
        let previousPickerTransactionTask = activeScreenPickerTransactionTask
        let pendingConfigurationTask: Task<Void, Never>?
        if state == .recording || state == .paused {
            pendingConfigurationTask = activeScreenCaptureConfigurationTask
        } else {
            pendingConfigurationTask = nil
        }

        let transactionID = UUID()
        let transactionTask = Task { @MainActor [weak self] in
            await previousPickerTransactionTask?.value
            await pendingConfigurationTask?.value
            guard let self,
                  self.state.allowsScreenContentPickerPresentation else {
                throw RecorderError.screenSelectionCancelled
            }
            try await self.performScreenContentPick(request)
        }
        let barrierTask = Task { @MainActor in
            _ = try? await transactionTask.value
        }
        activeScreenPickerTransactionID = transactionID
        activeScreenPickerTransactionTask = barrierTask
        defer {
            if activeScreenPickerTransactionID == transactionID {
                activeScreenPickerTransactionID = nil
                activeScreenPickerTransactionTask = nil
            }
        }
        try await transactionTask.value
    }

    private func performScreenContentPick(_ request: PickScreenContentRequest) async throws {
        let pickedFilter = try await screenContentPicker.pick(.init(
            activeStream: takeRecording.activeScreenCaptureStream,
            selectionPolicy: request.selectionPolicy
        ))
        let persistentBinding = await ScreenCaptureGeometry.persistentBinding(forPickedContent: pickedFilter)
        screenSourcePickerRecents.record(persistentBinding)
        guard state.allowsScreenContentPickerPresentation else {
            throw RecorderError.screenSelectionCancelled
        }
        guard request.selectionPolicy.accepts(persistentBinding?.kind) else {
            throw RecorderError.screenWindowRequired
        }
        let filter = ScreenCaptureGeometry.normalizedPickedFilter(pickedFilter)
        let pickedAspectRatio = ScreenCaptureGeometry.pickedContentAspectRatio(for: filter)
        let previousSettings = settings
        let previousSelectionState = screenSourceSelection.runtimeState()
        let previousPickedScreenSourceAspectRatio = currentPickedScreenSourceAspectRatio
        cancelPendingScreenWindowFits()
        screenContentSelectionRevision += 1
        settings.screenCrop = nil
        if request.activatesScreenSource {
            settings.enabledSources.insert(.screen)
            settings.hiddenSources.remove(.screen)
        }

        settings = screenSourceSelection.selectPickedContent(
            ScreenSourceSelection.PickedContentRequest(
                filter: filter,
                persistentBinding: persistentBinding,
                fallbackSourceKind: request.selectionPolicy.fallbackSourceKind,
                settings: settings
            )
        )
        settings.screenSourceAspectRatio = pickedAspectRatio
        currentPickedScreenSourceAspectRatio = pickedAspectRatio
        if request.activatesScreenSource, state == .idle {
            settings.screenContentMode = .fit
        }

        let updatesActiveRecording = state == .recording || state == .paused
        if updatesActiveRecording {
            do {
                let localSettings = localCaptureSettings(
                    usesRemoteCamera: settings.enabledSources.contains(.camera) && isRemoteCameraSelected
                )
                try await takeRecording.updateScreenCapture(
                    settings: localSettings,
                    pickedScreenFilter: filter
                )
                committedRecordingSettings = settings
            } catch {
                settings = previousSettings
                screenSourceSelection.restoreRuntimeState(previousSelectionState)
                currentPickedScreenSourceAspectRatio = previousPickedScreenSourceAspectRatio
                if let retargetFailure = error as? CaptureSourceRetargetFailure,
                   retargetFailure.rollbackFailed {
                    stop()
                    onRequestForeground?()
                    onMessage?("Source switch failed. Recording stopped to protect the take.")
                }
                throw error
            }
        }

        persistSettings()
        if updatesActiveRecording {
            updateRecordingSceneTimeline(transition: .cut)
        } else {
            updateRecordingSceneIfNeeded()
        }
        onScreenCaptureConfigurationChanged?()
        onRequestForeground?()
        if request.selectionPolicy.shouldAutoFitPickedWindow {
            await autoFitPickedScreenWindow(filter)
        }
    }

    private func autoFitPickedScreenWindow(_ filter: SCContentFilter) async {
        guard state.allowsScreenContentPickerPresentation,
              permissionGate.hasAccessibilityAccess else {
            return
        }
        let revision = beginScreenWindowFit()
        _ = await fitPickedScreenWindow(
            filter,
            zoom: settings.screenWindowZoom,
            shouldUpdateCapture: true,
            revision: revision
        )
    }

    @discardableResult
    private func fitPickedScreenWindow(
        _ filter: SCContentFilter,
        zoom: CGFloat,
        shouldUpdateCapture: Bool,
        revision: Int
    ) async -> Bool {
        guard isCurrentPickedScreenWindowFit(revision) else {
            return false
        }

        do {
            let arrangement = try await ScreenWindowFitRetry.run {
                guard self.isCurrentPickedScreenWindowFit(revision) else {
                    throw CancellationError()
                }
                if let binding = self.settings.screenSourceBinding,
                   let processID = binding.processID,
                   binding.kind == .window {
                    return try ShortsWindowArranger.fitWindow(
                        ownerPID: processID,
                        bounds: filter.contentRect,
                        title: binding.windowTitle,
                        appName: binding.applicationName ?? "Application",
                        displayID: binding.displayID ?? self.settings.selectedDisplayID,
                        captureLayout: self.settings.layout,
                        sceneLayout: self.settings.sceneLayout,
                        enabledSources: self.settings.enabledSources,
                        canvasPadding: self.settings.canvasPadding,
                        zoom: zoom
                    )
                }
                if let binding = self.settings.screenSourceBinding,
                   let processID = binding.processID,
                   binding.kind == .application {
                    return try ShortsWindowArranger.fitAppWindow(
                        ownerPID: processID,
                        appName: binding.applicationName ?? "Application",
                        displayID: binding.displayID ?? self.settings.selectedDisplayID,
                        captureLayout: self.settings.layout,
                        sceneLayout: self.settings.sceneLayout,
                        enabledSources: self.settings.enabledSources,
                        canvasPadding: self.settings.canvasPadding,
                        zoom: zoom
                    )
                }
                guard let target = await ScreenCaptureGeometry.pickedWindowTarget(for: filter) else {
                    throw ShortsWindowArrangerError.noWindowFound
                }
                guard self.isCurrentPickedScreenWindowFit(revision) else {
                    throw CancellationError()
                }
                return try ShortsWindowArranger.fitWindow(
                    ownerPID: target.pid,
                    bounds: target.bounds,
                    title: target.title,
                    appName: target.appName ?? "",
                    displayID: target.displayID ?? self.settings.selectedDisplayID,
                    captureLayout: self.settings.layout,
                    sceneLayout: self.settings.sceneLayout,
                    enabledSources: self.settings.enabledSources,
                    canvasPadding: self.settings.canvasPadding,
                    zoom: zoom
                )
            }
            guard isCurrentPickedScreenWindowFit(revision) else {
                return false
            }
            applyFittedScreenWindowArrangement(arrangement, shouldUpdateCapture: false)
            if shouldUpdateCapture {
                onScreenCaptureConfigurationChanged?()
                onMessage?(arrangement.resizedMessage)
            }
            return true
        } catch {
            guard isCurrentPickedScreenWindowFit(revision) else {
                return false
            }
            if shouldUpdateCapture {
                onMessage?(error.localizedDescription)
            }
            return false
        }
    }

    private func applyFittedScreenWindowArrangement(
        _ arrangement: ShortsWindowArrangement,
        shouldUpdateCapture: Bool
    ) {
        screenWindowGeometryRevision += 1
        if arrangement.frame.width > 0, arrangement.frame.height > 0 {
            let aspectRatio = arrangement.frame.width / arrangement.frame.height
            settings.screenSourceAspectRatio = aspectRatio
            noteScreenSourceAspectRatio(aspectRatio)
            persistSettings()
        }
        updateRecordingSceneIfNeeded()
        if shouldUpdateCapture {
            onScreenCaptureConfigurationChanged?()
        }
    }

    func requestPermissionsForEnabledSources() async {
        let needsScreenRecordingGrant =
            (settings.enabledSources.contains(.screen)
                && !settings.usesPickedScreenContent)
            || settings.enabledSources.contains(.systemAudio)
        if needsScreenRecordingGrant {
            _ = await permissionGate.requestScreenCaptureAccess()
        }

        if settings.enabledSources.contains(.camera), !isRemoteCameraSelected {
            _ = await permissionGate.requestCameraAccess()
        }

        if settings.enabledSources.contains(.microphone) {
            _ = await permissionGate.requestMicrophoneAccess()
        }

    }

    func availableCameras() -> [SourceOption] {
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .deskViewCamera, .external],
            mediaType: .video,
            position: .unspecified
        ).devices

        let localOptions = devices
            .filter { $0.isConnected && !$0.isSuspended }
            .sorted { lhs, rhs in
                LocalCameraSessionConfiguration.cameraSortKey(lhs) < LocalCameraSessionConfiguration.cameraSortKey(rhs)
            }
            .map { SourceOption(id: $0.uniqueID, name: cameraDisplayName(for: $0)) }
        return remoteCameraOptions() + localOptions
    }

    private func selectedCamera() -> AVCaptureDevice? {
        if isRemoteCameraSelected {
            return nil
        }
        if let selectedCameraID = settings.selectedCameraID,
           let device = AVCaptureDevice(uniqueID: selectedCameraID) {
            return device
        }

        return LocalCameraSessionConfiguration.selectedCamera(settings: settings)
    }

    func availableMicrophones() -> [SourceOption] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices.map { SourceOption(id: $0.uniqueID, name: $0.localizedName) }
    }

    func selectedMicrophoneName() -> String {
        if let selectedMicrophoneID = settings.selectedMicrophoneID,
           let device = AVCaptureDevice(uniqueID: selectedMicrophoneID) {
            return device.localizedName
        }
        if let device = AVCaptureDevice.default(for: .audio) {
            return device.localizedName
        }
        return "Default microphone"
    }

    func start() {
        guard state == .idle else { return }
        guard accessController.canRenderExport else {
            onMessage?("Recording is unavailable.")
            return
        }
        let readiness = recordingReadiness()
        guard readiness.isReady else {
            onMessage?(startBlockedMessage(readiness))
            return
        }
        screenContentPicker.cancel()
        cancelPendingScreenWindowFits()
        do {
            let outputDirectoryAccess = try takeFileStore.prepareOutputDirectory(settings: settings)
            guard recordingSession.beginPreparation(
                RecordingSession.PreparationRequest(outputDirectoryAccess: outputDirectoryAccess)
            ) else {
                outputDirectoryAccess.stop()
                return
            }
        } catch {
            onMessage?("Start failed: \(error.localizedDescription)")
            return
        }
        onMessage?("Not recording yet. Hang on while BlitzRecorder prepares capture.")

        Task {
            var createdTake: RecordingTake?
            var remoteStartCommandSent = false
            do {
                await stopAudioLevelMonitoring()
                guard !settings.enabledSources.isEmpty else {
                    throw RecorderError.noSourcesSelected
                }
                await prepareScreenSourceWindowForRecording()
                let recordingSettings = effectiveRecordingSettingsForStart()
                let recordingScreenFilter = try await resolvedScreenFilter(for: recordingSettings)
                let initialRecordingScene = recordingScene(
                    settings: recordingSettings,
                    screenFilter: recordingScreenFilter
                )
                let skippedSystemAudio = settings.enabledSources.contains(.systemAudio)
                    && !recordingSettings.enabledSources.contains(.systemAudio)
                let startPlan = TakeStartPlan.make(settings: recordingSettings, isRemoteCameraSelected: isRemoteCameraSelected)
                if startPlan.usesRemoteCamera {
                    try await requireRemoteCameraConnection()
                }
                if recordingSettings.enabledSources.contains(.camera), !startPlan.usesRemoteCamera {
                    guard await permissionGate.requestCameraAccess() else {
                        throw RecorderError.noCamera
                    }
                    await cameraCutoutPreviewer.stop()
                }
                if recordingSettings.enabledSources.contains(.microphone) {
                    guard await permissionGate.requestMicrophoneAccess() else {
                        throw RecorderError.microphoneUnavailable
                    }
                }
                let take = try takeFileStore.createTake(settings: recordingSettings)
                createdTake = take
                recordingSession.noteActiveTake(
                    RecordingSessionActiveTake(take: take, settings: recordingSettings)
                )
                let remoteTakeID = startPlan.usesRemoteCamera && startPlan.usesLiveCompositor ? UUID() : nil
                if let remoteTakeID {
                    remoteCamera.beginTake(
                        takeID: remoteTakeID,
                        take: take
                    )
                    remoteCamera.sendSettings()
                    _ = try await remoteCamera.prepare(
                        takeID: remoteTakeID,
                        hostStartTime: DispatchTime.now().uptimeNanoseconds
                    )
                }
                if startPlan.usesLiveCompositor {
                    if recordingSettings.enabledSources.contains(.screen) {
                        guard recordingSettings.usesPickedScreenContent || hasScreenCaptureAccess() else {
                            throw RecorderError.screenCapturePermissionRequired
                        }
                    }
                    if recordingSettings.enabledSources.contains(.camera) {
                        await cameraRecorder.stopSession()
                    }
                    if recordingSettings.enabledSources.contains(.screen) {
                        await stopScreenPreview()
                    }
                    let hostStartTime = try await takeRecording.startLiveCompositedTake(
                        take: take,
                        settings: recordingSettings,
                        initialScene: initialRecordingScene,
                        pickedScreenFilter: recordingScreenFilter,
                        prerollSeconds: 0
                    ) { [weak self] remaining in
                        self?.onMessage?(Self.recordingPrerollMessage(remaining: remaining))
                    }
                    if let remoteTakeID {
                        remoteStartCommandSent = true
                        remoteCamera.markTimelineStart(takeID: remoteTakeID, hostTimelineStartTime: hostStartTime)
                        _ = try await remoteCamera.start(
                            takeID: remoteTakeID,
                            hostStartTime: hostStartTime,
                            hostTimelineStartTime: hostStartTime
                        )
                    }
                    recordingSession.markRecordingStarted()
                    committedRecordingSettings = settings
                    onMessage?(skippedSystemAudio
                        ? "Recording - Mac audio off (needs Screen Recording)"
                        : "Recording with live compositor...")
                    return
                }
                if recordingSettings.enabledSources.contains(.screen) {
                    guard recordingSettings.usesPickedScreenContent || hasScreenCaptureAccess() else {
                        throw RecorderError.screenCapturePermissionRequired
                    }
                }
                try await takeRecording.startSourceFileTake(
                    take: take,
                    settings: startPlan.localCaptureSettings,
                    sceneTimelineSettings: startPlan.sceneTimelineSettings,
                    initialScene: initialRecordingScene,
                    pickedScreenFilter: recordingScreenFilter,
                    prerollSeconds: 0,
                    screenRecorder: screenRecorder,
                    cameraRecorder: cameraRecorder,
                    remoteCameraRecorder: startPlan.usesRemoteCamera ? remoteCamera : nil,
                    audioRecorder: audioRecorder,
                    systemAudioRecorder: systemAudioRecorder
                ) { [weak self] remaining in
                    self?.onMessage?(Self.recordingPrerollMessage(remaining: remaining))
                }
                recordingSession.markRecordingStarted()
                committedRecordingSettings = settings
                onMessage?(skippedSystemAudio
                    ? "Recording - Mac audio off (needs Screen Recording)"
                    : "Recording...")
            } catch {
                remoteCamera.cancelCommand()
                if let activeRemoteCameraTakeID = remoteCamera.activeTakeID, !remoteStartCommandSent {
                    remoteCamera.removePendingImport(takeID: activeRemoteCameraTakeID)
                }
                if let activeRemoteCameraTakeID = remoteCamera.activeTakeID {
                    remoteCamera.abandonTake(takeID: activeRemoteCameraTakeID)
                }
                await takeRecording.stopAnyActiveRecording()
                if let createdTake, !remoteStartCommandSent {
                    takeFileStore.cleanupIntermediateFiles(for: createdTake, settings: settings)
                }
                recordingSession.failPreparation()
                committedRecordingSettings = nil
                refreshAudioLevelMonitoring()
                onMessage?(startFailedMessage(for: error))
            }
        }
    }

    private func prepareScreenSourceWindowForRecording() async {
        guard settings.visibleSources.contains(.screen),
              permissionGate.hasAccessibilityAccess else {
            return
        }

        if settings.usesPickedScreenContent {
            guard let filter = screenSourceSelection.pickedContentFilter,
                  let sourceKind = activePickedScreenContentKind,
                  sourceKind == .application || sourceKind == .window else {
                return
            }
            let revision = beginScreenWindowFit()
            _ = await fitPickedScreenWindow(
                filter,
                zoom: settings.screenWindowZoom,
                shouldUpdateCapture: false,
                revision: revision
            )
            return
        }

        guard let binding = settings.screenSourceBinding,
              binding.kind != .display else {
            return
        }
        let revision = beginScreenWindowFit()
        do {
            guard let arrangement = try await screenSourceWindowArrangement(
                for: binding,
                zoom: settings.screenWindowZoom,
                revision: revision
            ) else {
                return
            }
            applyFittedScreenWindowArrangement(arrangement, shouldUpdateCapture: false)
        } catch {
            guard isCurrentScreenSourceWindowFit(revision, binding: binding) else { return }
            onMessage?("Window fit skipped: \(error.localizedDescription)")
        }
    }

    private func startBlockedMessage(_ readiness: RecordingReadiness) -> String {
        if settings.enabledSources.isEmpty {
            return "Start failed: Select at least one source before recording."
        }
        return "Start failed: Selected sources are not ready."
    }

    private func startFailedMessage(for error: Error) -> String {
        if case RecorderError.screenCapturePermissionRequired = error {
            return "Start failed: Selected sources are not ready."
        }
        return "Start failed: \(error.localizedDescription)"
    }

    private func effectiveRecordingSettingsForStart() -> RecordingSettings {
        var recordingSettings = settings
        recordingSettings.savesSourceFiles = true
        if recordingSettings.enabledSources.contains(.systemAudio), !hasScreenCaptureAccess() {
            recordingSettings.enabledSources.remove(.systemAudio)
        }
        return recordingSettings
    }

    private func renameLiveCompositedOutputIfPossible(
        outputURL: URL,
        take: RecordingTake,
        settings: RecordingSettings
    ) async -> URL {
        guard settings.enabledSources.contains(.microphone),
              settings.renamesRecordingsFromSpeech else {
            return outputURL
        }

        do {
            onMessage?("Transcribing audio...")
            try await extractAudioForTranscription(from: outputURL, to: take.audioURL)
            let transcript = try await speechTranscriber.transcribe(audioURL: take.audioURL)
            let slug = await titleGenerator.titleSlug(for: transcript)
            let datedSlug = takeFileStore.datedSlug(for: take, slug: slug)
            let transcriptURL = take.scratchDirectory.appendingPathComponent("\(datedSlug)-transcript.txt")
            try transcript.write(to: transcriptURL, atomically: true, encoding: .utf8)

            guard let slug, !slug.isEmpty else {
                onMessage?("Renamed: \(datedSlug)")
                return outputURL
            }

            let targetURL = takeFileStore.finalVideoURL(
                slug: datedSlug,
                settings: settings,
                outputFormat: take.outputVideoFormat
            )
            guard targetURL.path != outputURL.path else {
                onMessage?("Renamed: \(datedSlug)")
                return outputURL
            }

            let renamedURL = takeFileStore.uniqueFileURL(targetURL)
            try FileManager.default.moveItem(at: outputURL, to: renamedURL)
            onMessage?("Renamed: \(datedSlug)")
            return renamedURL
        } catch {
            onMessage?("Rename skipped: \(error.recorderFailureDescription)")
            return outputURL
        }
    }

    private func extractAudioForTranscription(from videoURL: URL, to audioURL: URL) async throws {
        try? FileManager.default.removeItem(at: audioURL)
        let asset = AVURLAsset(url: videoURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw RecorderError.speechUnavailable
        }

        let duration = try await asset.load(.duration)
        let composition = AVMutableComposition()
        for track in audioTracks {
            guard let compositionTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw RecorderError.exportUnavailable
            }
            try compositionTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: track,
                at: .zero
            )
        }

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw RecorderError.exportUnavailable
        }
        try await exporter.export(to: audioURL, as: .m4a)
    }

    private static func recordingPrerollMessage(remaining: Int) -> String {
        let unit = remaining == 1 ? "second" : "seconds"
        return "Loading scene. Recording starts in \(remaining) \(unit)..."
    }

    func pause() {
        guard recordingSession.pause() else { return }
        takeRecording.pause()
    }

    func resume() {
        guard recordingSession.resume() else { return }
        takeRecording.resume()
    }

    func stop() {
        guard let stopContext = recordingSession.beginFinishing() else { return }
        screenContentPicker.cancel()
        cancelPendingScreenWindowFits()
        let pendingScreenPickerTransactionTask = activeScreenPickerTransactionTask
        let pendingScreenCaptureConfigurationTask = activeScreenCaptureConfigurationTask
        takeRecording.pauseSceneTimeline()
        onRenderProgress?(0)
        onMessage?("Stopping recording...")

        Task {
            do {
                await pendingScreenPickerTransactionTask?.value
                await pendingScreenCaptureConfigurationTask?.value
                let sceneEventsForFinalization = takeRecording.sceneEvents
                committedRecordingSettings = nil
                let takeToFinalize = stopContext.take
                let takeSettings = stopContext.settings ?? settings
                let stopOutcome = try await takeRecording.stop()
                switch stopOutcome {
                case .liveComposited(let completion, let warning):
                    onMessage?("Saving recording...")
                    onRenderProgress?(1)
                    try? await Task.sleep(for: .milliseconds(250))
                    if completion.wroteMedia, let finalURL = completion.url {
                        let savedURL = finalURL
                        accessController.recordSuccessfulExportIfNeeded()
                        if let takeToFinalize {
                            takeFileStore.cleanupIntermediateFiles(for: takeToFinalize, settings: takeSettings)
                        }
                        let savedOutput = SavedRecordingOutput(url: savedURL, sourceDirectory: nil, warning: warning)
                        onSavedRecording?(savedOutput)
                        onMessage?(savedOutput.userMessage)
                    } else if let takeToFinalize {
                        let recovery = RecordingRecoveryOutput(
                            takeDirectory: takeToFinalize.scratchDirectory,
                            reason: "No video frames captured",
                            canRetryExport: false
                        )
                        onRecordingRecovery?(recovery)
                        onMessage?("Recording needs recovery: \(recovery.userMessage)")
                    } else {
                        onMessage?("Recording failed: No video frames captured.")
                    }
                    recordingSession.finish(with: nil)
                    refreshAudioLevelMonitoring()
                    return
                case .sourceFiles(let captureSummary):
                    var stopWarnings: [String] = []
                    if let warning = captureSummary.stopFailureWarning {
                        stopWarnings.append(warning)
                    }

                    if let takeToFinalize {
                        let outcome = await takeFinalizer.finalize(
                            take: takeToFinalize,
                            settings: takeSettings,
                            captureSummary: captureSummary,
                            sceneEvents: sceneEventsForFinalization
                        )
                        let retainedTake: RecordingTake?
                        if case .saved = outcome {
                            accessController.recordSuccessfulExportIfNeeded()
                            retainedTake = nil
                        } else if case .projectReady(let projectTake) = outcome {
                            retainedTake = projectTake
                        } else if case .projectReadyWithWarning(let projectTake, _) = outcome {
                            retainedTake = projectTake
                        } else if case .recoveryFiles(let recoveryTake, _) = outcome {
                            retainedTake = recoveryTake
                        } else {
                            retainedTake = nil
                        }
                        recordingSession.finish(with: retainedTake)
                        takeRecording.resetSceneTimeline()
                        refreshAudioLevelMonitoring()
                        switch outcome {
                        case .projectReady, .projectReadyWithWarning:
                            if let projectOutput = outcome.projectOutput(warning: captureSummary.savedRecordingStopWarning) {
                                onPostRecordingProject?(projectOutput)
                                onMessage?(projectOutput.userMessage)
                            } else {
                                onMessage?(outcome.userMessage)
                            }
                        case .saved:
                            let savedOutput = outcome.savedOutput(warning: captureSummary.savedRecordingStopWarning)
                            if let savedOutput {
                                onSavedRecording?(savedOutput)
                                onMessage?(savedOutput.userMessage)
                            } else {
                                onMessage?(outcome.userMessage)
                            }
                        case .recoveryFiles:
                            let stopWarning = stopWarnings.isEmpty ? nil : stopWarnings.joined(separator: ". ")
                            let recoveryReason = Self.recoveryReason(
                                outcome: outcome,
                                stopWarning: stopWarning,
                                settings: settings
                            )
                            if let recovery = outcome.recoveryOutput(reason: recoveryReason) {
                                onRecordingRecovery?(recovery)
                                onMessage?("Recording needs recovery: \(recovery.userMessage)")
                            } else {
                                onMessage?("Recording needs recovery: \(outcome.userMessage)")
                            }
                        }
                    } else {
                        recordingSession.finish(with: nil)
                        takeRecording.resetSceneTimeline()
                        refreshAudioLevelMonitoring()
                    }
                case .none:
                    recordingSession.finish(with: nil)
                    refreshAudioLevelMonitoring()
                }
            } catch {
                await takeRecording.stopAnyActiveRecording()
                recordingSession.finish(with: nil)
                takeRecording.resetSceneTimeline()
                onRenderProgress?(0)
                refreshAudioLevelMonitoring()
                onMessage?("Recording failed: Stop failed: \(error.recorderFailureDescription)")
            }
        }
    }

    private func handleActiveMicrophoneCaptureFailure(_ error: Error) {
        guard state == .recording || state == .paused else { return }
        stop()
        onRequestForeground?()
        onMessage?(
            "Microphone capture failed. Recording stopped to protect the take: "
                + error.recorderFailureDescription
        )
    }

    func refreshAudioLevelMonitoring() {
        guard state == .idle, idleCaptureResourcesEnabled else { return }
        Task {
            await configureAudioLevelMonitoring()
        }
    }

    private static func recoveryReason(
        outcome: TakeFinalizationOutcome,
        stopWarning: String?,
        settings: RecordingSettings
    ) -> String {
        let baseReason: String
        if case .recoveryFiles(_, let reason) = outcome {
            baseReason = reason
        } else {
            baseReason = outcome.userMessage
        }

        guard let stopWarning, !stopWarning.isEmpty else {
            return baseReason
        }

        if RemoteCameraProviderID.isRemote(settings.selectedCameraID),
           stopWarning.lowercased().contains("iphone") {
            return "\(baseReason). iPhone camera did not save usable video. Keep BlitzRecorder Camera open until recording stops, then retry."
        }

        return "\(baseReason). \(stopWarning)"
    }

    func mergeLastTake() {
        guard let lastTake else {
            onMessage?("No take to merge yet.")
            return
        }
        guard accessController.canRenderExport else {
            onMessage?("Export is unavailable.")
            return
        }

        onExportFailure?(nil)
        Task {
            do {
                let outputAccess = try takeFileStore.prepareOutputDirectory(settings: settings)
                defer { outputAccess.stop() }
                let url = try await Merger.exportFinalVideo(take: lastTake, settings: settings)
                accessController.recordSuccessfulExportIfNeeded()
                let sourceDirectory = lastTake.scratchDirectory
                self.recordingSession.clearLastTake()
                let savedOutput = SavedRecordingOutput(url: url, sourceDirectory: sourceDirectory, warning: nil)
                onSavedRecording?(savedOutput)
                onMessage?(savedOutput.userMessage)
            } catch {
                exportLog.error("Final video export failed: \(error.recorderFailureDescription, privacy: .public) | \(String(describing: error), privacy: .public)")
                onMessage?("Final video export failed: \(error.recorderFailureDescription)")
                onExportFailure?("Final video export failed. \(error.recorderFailureDescription)")
            }
        }
    }

    func exportProject(_ request: ProjectExportRequest) {
        guard accessController.canRenderExport else {
            onMessage?("Export is unavailable.")
            return
        }
        guard recordingSession.beginExport() else {
            onMessage?("Wait for the current recording task to finish before exporting.")
            return
        }

        onRenderProgress?(0)
        onExportFailure?(nil)
        onMessage?("Exporting \(request.outputFormat.displayName)...")

        Task {
            let destinationAccessStarted = request.destinationURL.startAccessingSecurityScopedResource()
            let musicAccessStarted = request.backgroundMusic?.url.startAccessingSecurityScopedResource() ?? false
            defer {
                if destinationAccessStarted {
                    request.destinationURL.stopAccessingSecurityScopedResource()
                }
                if musicAccessStarted {
                    request.backgroundMusic?.url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let project = try takeFileStore.loadRecordingProject(at: request.projectURL)
                let exportSettings = takeFileStore.recordingSettings(
                    from: project,
                    baseSettings: settings,
                    outputFormat: request.outputFormat
                )
                let outputAccess = try takeFileStore.prepareOutputDirectory(settings: exportSettings)
                defer { outputAccess.stop() }

                let take = takeFileStore.recordingTake(
                    from: project,
                    settings: exportSettings,
                    outputFormat: request.outputFormat
                )
                let sceneEvents = takeFileStore.sceneEvents(from: project)

                var renderSettings = request.performanceProfile.applying(to: exportSettings)
                if request.mutedAudioSources.contains(.microphone) {
                    renderSettings.microphoneGain = 0
                }
                if request.mutedAudioSources.contains(.systemAudio) {
                    renderSettings.systemAudioGain = 0
                }
                let hiddenCaptureSources = Set(request.hiddenVideoSources.map(\.source))
                var renderSceneEvents = sceneEvents
                if !hiddenCaptureSources.isEmpty {
                    renderSettings.enabledSources.subtract(hiddenCaptureSources)
                    renderSceneEvents = sceneEvents.map { event in
                        var scene = event.scene
                        scene.enabledSources.subtract(hiddenCaptureSources)
                        return RecordingSceneEvent(
                            time: event.time,
                            scene: scene,
                            transition: event.transition
                        )
                    }
                }
                renderSceneEvents = renderSceneEvents.map { event in
                    RecordingSceneEvent(
                        time: event.time,
                        scene: request.performanceProfile.applying(to: event.scene),
                        transition: event.transition
                    )
                }

                let renderedURL = try await Merger.exportFinalVideo(FinalVideoExportRequest(
                    take: take,
                    settings: renderSettings,
                    sceneEvents: renderSceneEvents,
                    backgroundMusic: request.backgroundMusic,
                    destinationURL: request.destinationURL,
                    progressHandler: { [weak self] progress in
                        self?.onRenderProgress?(progress)
                    }
                ))
                let url = renderedURL

                try takeFileStore.writeSourceTakeManifest(
                    for: take,
                    settings: renderSettings,
                    finalVideoURL: url
                )
                try takeFileStore.writeRecordingProject(
                    for: take,
                    settings: renderSettings,
                    sceneEvents: sceneEvents,
                    finalVideoURL: url,
                    chapters: project.chapters,
                    editorTimeline: project.editorTimeline
                )
                accessController.recordSuccessfulExportIfNeeded()
                onRenderProgress?(1)
                let savedOutput = SavedRecordingOutput(
                    url: url,
                    sourceDirectory: take.scratchDirectory,
                    warning: nil
                )
                onSavedRecording?(savedOutput)
                onMessage?(savedOutput.userMessage)
            } catch {
                exportLog.error("Project export failed (destination \(request.destinationURL.path, privacy: .public)): \(error.recorderFailureDescription, privacy: .public) | \(String(describing: error), privacy: .public)")
                onMessage?("Project export failed: \(error.recorderFailureDescription)")
                onExportFailure?(error.recorderFailureDescription)
            }
            recordingSession.finishExport()
            refreshAudioLevelMonitoring()
        }
    }

    func updateProjectScene(
        at projectURL: URL,
        eventIndex: Int,
        correction: RecordingProjectSceneCorrection
    ) throws -> RecordingProject {
        guard state == .idle else {
            throw RecorderError.mediaWriteFailed("Wait for the current recording task to finish before editing the project.")
        }
        let project = try takeFileStore.updateProjectSceneEvent(
            at: projectURL,
            eventIndex: eventIndex,
            correction: correction,
            baseSettings: settings
        )
        onMessage?("Updated project source segment.")
        return project
    }

    func updateProjectScene(
        at projectURL: URL,
        eventIndex: Int,
        mutate: (inout RecordingScene) -> Void
    ) throws -> RecordingProject {
        guard state == .idle else {
            throw RecorderError.mediaWriteFailed("Wait for the current recording task to finish before editing the project.")
        }
        return try takeFileStore.updateProjectScene(
            at: projectURL,
            eventIndex: eventIndex,
            baseSettings: settings,
            mutate: mutate
        )
    }

    func insertProjectSceneEvent(at projectURL: URL, time: Double) throws -> RecordingProject {
        guard state == .idle else {
            throw RecorderError.mediaWriteFailed("Wait for the current recording task to finish before editing the project.")
        }
        return try takeFileStore.insertProjectSceneEvent(
            at: projectURL,
            time: time,
            baseSettings: settings
        )
    }

    func removeProjectSceneEvent(at projectURL: URL, eventIndex: Int) throws -> RecordingProject {
        guard state == .idle else {
            throw RecorderError.mediaWriteFailed("Wait for the current recording task to finish before editing the project.")
        }
        return try takeFileStore.removeProjectSceneEvent(
            at: projectURL,
            eventIndex: eventIndex,
            baseSettings: settings
        )
    }

    func zoomIn() {
        guard !takeRecording.isUsingLiveCompositor else { return }
        screenRecorder.zoomIn()
    }

    func zoomOut() {
        guard !takeRecording.isUsingLiveCompositor else { return }
        screenRecorder.zoomOut()
    }

    func resetZoom() {
        guard !takeRecording.isUsingLiveCompositor else { return }
        screenRecorder.resetZoom()
    }

    func openOutputFolder() {
        NSWorkspace.shared.open(settings.outputDirectory)
    }

    private var shouldUseLiveCompositor: Bool {
        TakeRecordingRuntime.shouldUseLiveCompositor(
            settings: settings,
            isRemoteCameraSelected: isRemoteCameraSelected
        )
    }

    var allowsSceneChanges: Bool {
        state == .idle || state == .recording || state == .paused
    }

    private func sceneChangeIsAllowed() -> Bool {
        guard allowsSceneChanges else {
            onMessage?("Scene layout is locked while saving.")
            return false
        }
        return true
    }

    private func updateRecordingSceneIfNeeded(transition: RecordingSceneTransition = .cut) {
        let screenFilter = settings.usesPickedScreenContent
            ? screenSourceSelection.pickedContentFilter
            : nil
        let scene = recordingScene(settings: settings, screenFilter: screenFilter)
        takeRecording.updateScene(scene, transition: transition)
        if (state == .recording || state == .paused),
           settings.enabledSources.contains(.screen) {
            let pendingEvent = takeRecording.pendingSceneEvent(
                scene: scene,
                transition: transition
            )
            updateActiveScreenCaptureConfigurationIfNeeded(pendingEvent: pendingEvent)
        } else {
            takeRecording.appendSceneEventIfNeeded(scene, state: state, transition: transition)
            if state == .recording || state == .paused {
                committedRecordingSettings = settings
            }
        }
        synchronizeActiveCaptureSourcesIfNeeded()
    }

    @discardableResult
    private func updateRecordingSceneTimeline(transition: RecordingSceneTransition) -> RecordingScene {
        let screenFilter = settings.usesPickedScreenContent
            ? screenSourceSelection.pickedContentFilter
            : nil
        let scene = recordingScene(
            settings: settings,
            screenFilter: screenFilter
        )
        takeRecording.updateScene(scene, transition: transition)
        takeRecording.appendSceneEventIfNeeded(scene, state: state, transition: transition)
        return scene
    }

    private func recordingScene(
        settings: RecordingSettings,
        screenFilter: SCContentFilter?
    ) -> RecordingScene {
        var scene = RecordingScene(settings: settings)
        guard settings.enabledSources.contains(.screen), let screenFilter else {
            return scene
        }
        var geometry = ScreenCaptureGeometry.screenSourceGeometry(
            for: settings,
            pickedFilter: screenFilter
        )
        geometry.usesPickedContent = settings.usesPickedScreenContent
        geometry.fillsSceneFrame = ScreenSourceGeometry.fillsSceneFrame(for: settings)
        scene.screenSourceGeometry = geometry
        return scene
    }

    private func updateActiveScreenCaptureConfigurationIfNeeded(
        pendingEvent: PendingRecordingSceneEvent
    ) {
        guard state == .recording || state == .paused,
              settings.enabledSources.contains(.screen) else {
            return
        }

        let requestedSettings = settings
        activeScreenCaptureConfigurationRevision += 1
        let generation = activeScreenCaptureConfigurationRevision
        let previousTask = activeScreenCaptureConfigurationTask
        let pickerTransactionTask = activeScreenPickerTransactionTask
        let pickerQueuedRevision: Int?
        if pickerTransactionTask == nil {
            pickerQueuedRevision = nil
        } else {
            pickerQueuedScreenCaptureConfigurationRevision += 1
            pickerQueuedRevision = pickerQueuedScreenCaptureConfigurationRevision
        }
        let task = Task {
            [
                weak self,
                previousTask,
                pickerTransactionTask,
                generation,
                pendingEvent,
                pickerQueuedRevision,
                requestedSettings
            ] in
            await pickerTransactionTask?.value
            await previousTask?.value
            guard let self,
                  self.shouldApplyActiveScreenCaptureConfiguration(generation: generation) else {
                return
            }
            if let pickerQueuedRevision,
               pickerQueuedRevision != self.pickerQueuedScreenCaptureConfigurationRevision {
                return
            }
            let effectiveSettings = pickerTransactionTask == nil
                ? requestedSettings
                : self.settings
            let effectiveEvent: PendingRecordingSceneEvent
            if pickerTransactionTask == nil {
                effectiveEvent = pendingEvent
            } else {
                let currentFilter = effectiveSettings.usesPickedScreenContent
                    ? self.screenSourceSelection.pickedContentFilter
                    : nil
                let currentScene = self.recordingScene(
                    settings: effectiveSettings,
                    screenFilter: currentFilter
                )
                effectiveEvent = pendingEvent.resolving(scene: currentScene)
            }
            let captureSettings = self.localCaptureSettings(
                usesRemoteCamera: effectiveSettings.enabledSources.contains(.camera)
                    && self.isRemoteCameraSelected
            )
            do {
                let pickedScreenFilter = try await self.resolvedScreenFilter(for: captureSettings)
                try await self.takeRecording.updateScreenCapture(
                    settings: captureSettings,
                    pickedScreenFilter: pickedScreenFilter
                )
                let resolvedScene = self.recordingScene(
                    settings: effectiveSettings,
                    screenFilter: pickedScreenFilter
                )
                self.takeRecording.appendPendingSceneEvent(
                    effectiveEvent.resolving(scene: resolvedScene),
                    state: self.state
                )
                self.committedRecordingSettings = effectiveSettings
            } catch {
                self.reportActiveScreenCaptureConfigurationFailure(error, generation: generation)
            }
        }
        activeScreenCaptureConfigurationTask = task
    }

    private func cancelPendingActiveScreenCaptureConfigurationUpdate() {
        activeScreenCaptureConfigurationRevision += 1
        activeScreenCaptureConfigurationTask?.cancel()
        activeScreenCaptureConfigurationTask = nil
    }

    private func shouldApplyActiveScreenCaptureConfiguration(generation: Int) -> Bool {
        !Task.isCancelled
            && activeScreenCaptureConfigurationRevision == generation
            && (state == .recording || state == .paused || state == .finishing)
    }

    private func reportActiveScreenCaptureConfigurationFailure(_ error: Error, generation: Int) {
        if let retargetFailure = error as? CaptureSourceRetargetFailure,
           retargetFailure.rollbackFailed {
            cancelPendingActiveScreenCaptureConfigurationUpdate()
            stop()
            onRequestForeground?()
            onMessage?("Screen capture update failed. Recording stopped to protect the take.")
            return
        }
        guard activeScreenCaptureConfigurationRevision == generation else { return }
        cancelPendingActiveScreenCaptureConfigurationUpdate()
        if let committedRecordingSettings {
            settings = committedRecordingSettings
            persistSettings()
            if let committedScene = takeRecording.sceneEvents.last?.scene {
                takeRecording.updateScene(committedScene, transition: .cut)
            }
            onScreenCaptureConfigurationChanged?()
        }
        onMessage?("Screen capture update failed: \(error.recorderFailureDescription)")
    }

    private func synchronizeActiveCaptureSourcesIfNeeded() {
        guard !takeRecording.isUsingLiveCompositor,
              state == .recording || state == .paused else {
            return
        }
        if settings.enabledSources.contains(.screen),
           !settings.usesPickedScreenContent,
           !hasScreenCaptureAccess() {
            onMessage?("Pick a screen or enable Screen Recording before adding screen capture to this recording.")
            return
        }
        let localSettings = localCaptureSettings(
            usesRemoteCamera: settings.enabledSources.contains(.camera) && isRemoteCameraSelected
        )
        Task { [weak self, localSettings] in
            do {
                let pickedScreenFilter = try await self?.resolvedScreenFilter(for: localSettings)
                try await self?.takeRecording.startEnabledSources(
                    settings: localSettings,
                    pickedScreenFilter: pickedScreenFilter
                )
            } catch {
                self?.onMessage?("Source could not be added to recording: \(error.localizedDescription)")
            }
        }
    }

    private func pickedScreenFilter(for settings: RecordingSettings) -> SCContentFilter? {
        screenSourceSelection.activeFilter(for: settings)
    }

    private func resolvedScreenFilter(for settings: RecordingSettings) async throws -> SCContentFilter? {
        guard settings.enabledSources.contains(.screen)
                || settings.enabledSources.contains(.systemAudio) else {
            return nil
        }
        if let pickedFilter = pickedScreenFilter(for: settings) {
            return pickedFilter
        }
        guard permissionGate.hasScreenCaptureAccess,
              settings.screenSourceBinding?.isConcreteSelection == true else {
            return nil
        }
        let content = try await SCShareableContent.current
        return try ScreenCaptureGeometry.screenSource(for: settings, content: content).filter
    }

    private func persistSettings(saveSceneSnapshot: Bool = true) {
        if saveSceneSnapshot {
            saveCurrentSceneSnapshotIfNeeded()
        }
        RecordingSettingsStore.save(settings, defaults: defaults)
    }

    private func saveCurrentSceneSnapshotIfNeeded() {
        guard state == .idle else { return }
        sceneLibrary.updateSelectedScene(
            layout: settings.layout,
            snapshot: currentRecordingSceneSnapshot()
        )
        SceneLibraryStore.save(sceneLibrary, defaults: defaults)
    }

    private func applySceneSnapshot(_ snapshot: RecordingSceneSnapshot) {
        let audioSources = settings.enabledSources.subtracting([.screen, .camera])
        let hiddenAudioSources = settings.hiddenSources.subtracting([.screen, .camera])

        settings.enabledSources = audioSources.union(snapshot.enabledVideoSources)
        settings.hiddenSources = hiddenAudioSources.union(snapshot.hiddenVideoSources)
        settings.sceneLayout = snapshot.sceneLayout
        settings.canvasBackgroundStyle = snapshot.canvasBackgroundStyle
        settings.canvasBackgroundAnimated = snapshot.canvasBackgroundAnimated
            && snapshot.canvasBackgroundStyle.supportsBackgroundAnimation
        settings.canvasPadding = snapshot.canvasPadding
        settings.screenCornerRadius = snapshot.screenCornerRadius
        settings.screenShadowEnabled = snapshot.screenShadowEnabled
        settings.screenContentMode = snapshot.screenContentMode
        settings.cameraContentMode = snapshot.cameraContentMode
        settings.cameraFramePadding = 0
        settings.cameraShadowEnabled = snapshot.cameraShadowEnabled
        settings.selectedScenePreset = snapshot.selectedScenePreset
        settings.cameraCropAmount = snapshot.cameraCropAmount
        settings.cameraCropPosition = snapshot.cameraCropPosition
        settings.selectedCameraID = snapshot.selectedCameraID
        settings = screenSourceSelection.restore(
            ScreenSourceSelection.RestoreRequest(
                snapshot: ScreenSourceSelectionSnapshot(
                    usesPickedContent: snapshot.usesPickedScreenContent,
                    binding: snapshot.screenSourceBinding,
                    selectedDisplayID: snapshot.selectedDisplayID,
                    crop: snapshot.screenCrop,
                    pickedContentSelectionID: snapshot.pickedScreenContentSelectionID
                ),
                settings: settings
            )
        )
        settings.screenSourceAspectRatio = snapshot.screenSourceAspectRatio
        refitCameraInsetFrameForCurrentSource()
    }

    private func currentScreenSourceSelection() -> ScreenSourceSelectionSnapshot {
        screenSourceSelection.snapshot(from: settings)
    }

    private func currentRecordingSceneSnapshot() -> RecordingSceneSnapshot {
        var snapshot = RecordingSceneSnapshot(settings: settings)
        snapshot.pickedScreenContentSelectionID = settings.usesPickedScreenContent
            ? screenSourceSelection.pickedContentSelectionID
            : nil
        return snapshot
    }

    private func restoreScreenSourceSelection(_ selection: ScreenSourceSelectionSnapshot) {
        settings = screenSourceSelection.restore(
            ScreenSourceSelection.RestoreRequest(snapshot: selection, settings: settings)
        )
        if clearIncompatibleScreenCropForCurrentLayout() {
            settings.screenCrop = nil
        }
    }

    private func recomputeSelectedPresetLayoutForCurrentSource() {
        guard let preset = settings.selectedScenePreset,
              preset.supports(settings.layout) else { return }
        settings.sceneLayout = SceneLayout.presetLayout(
            preset,
            for: settings.layout,
            screenAspectRatio: currentScreenSourceAspectRatio(),
            cameraAspectRatio: currentCameraSourceAspectRatio()
        )
    }

    private func localCaptureSettings(usesRemoteCamera: Bool) -> RecordingSettings {
        takeRecording.localCaptureSettings(settings, usesRemoteCamera: usesRemoteCamera)
    }

    var isRemoteCameraSelected: Bool {
        remoteCamera.isRemoteCameraSelected()
    }

    func selectedRemoteCameraName() -> String? {
        remoteCamera.selectedName()
    }

    func selectedRemoteCameraStatus() -> String? {
        remoteCamera.selectedStatus()
    }

    func selectedRemoteCameraConnectionState() -> RemoteCameraConnectionState? {
        remoteCamera.selectedConnectionState()
    }

    func selectedRemoteCameraDeviceDescription() -> String {
        remoteCamera.selectedDeviceDescription()
    }

    func selectedRemoteCameraCapabilities() -> RemoteCameraCapabilities? {
        remoteCamera.selectedCapabilities()
    }

    func selectedRemoteCameraTelemetry() -> RemoteCameraTelemetry? {
        remoteCamera.selectedTelemetry()
    }

    func remoteCameraDeviceSummaries() -> [RemoteCameraDeviceSummary] {
        remoteCamera.deviceSummaries()
    }

    func setRemoteCameraLens(_ lens: RemoteCameraLens) {
        remoteCamera.applySettingsIntent(.lens(lens))
    }

    func setRemoteCameraFormat(id: String?, frameRate: Int) {
        remoteCamera.applySettingsIntent(.format(id: id, frameRate: frameRate))
    }

    func setRemoteCameraCaptureProfile(_ profileID: RemoteCameraCaptureProfileID) {
        remoteCamera.applySettingsIntent(.captureProfile(profileID))
    }

    func setRemoteCameraColorMode(_ colorMode: RemoteCameraColorMode) {
        remoteCamera.applySettingsIntent(.colorMode(colorMode))
    }

    func setRemoteCameraCinematicVideoEnabled(_ enabled: Bool) {
        remoteCamera.applySettingsIntent(.cinematicVideoEnabled(enabled))
    }

    func setRemoteCameraCinematicAperture(_ aperture: Double) {
        remoteCamera.applySettingsIntent(.cinematicAperture(aperture))
    }

    func setRemoteCameraFocusMode(_ mode: RemoteCameraFocusMode) {
        remoteCamera.applySettingsIntent(.focusMode(mode))
    }

    func setRemoteCameraFocusPosition(_ position: Double) {
        remoteCamera.applySettingsIntent(.focusPosition(position))
    }

    func setRemoteCameraExposureMode(_ mode: RemoteCameraExposureMode) {
        remoteCamera.applySettingsIntent(.exposureMode(mode))
    }

    func setRemoteCameraExposureBias(_ bias: Double) {
        remoteCamera.applySettingsIntent(.exposureBias(bias))
    }

    func resetRemoteCameraExposureBias() {
        remoteCamera.applySettingsIntent(.resetExposureBias)
    }

    func setRemoteCameraISO(_ iso: Double?) {
        remoteCamera.applySettingsIntent(.iso(iso))
    }

    func setRemoteCameraShutterDuration(_ seconds: Double?) {
        remoteCamera.applySettingsIntent(.shutterDuration(seconds))
    }

    func setRemoteCameraWhiteBalanceMode(_ mode: RemoteCameraWhiteBalanceMode) {
        remoteCamera.applySettingsIntent(.whiteBalanceMode(mode))
    }

    func setRemoteCameraWhiteBalance(temperature: Double, tint: Double) {
        remoteCamera.applySettingsIntent(.whiteBalance(temperature: temperature, tint: tint))
    }

    func setRemoteCameraStabilizationMode(_ mode: RemoteCameraStabilizationMode) {
        remoteCamera.applySettingsIntent(.stabilizationMode(mode))
    }

    func setRemoteCameraAutomaticRotation(_ enabled: Bool) {
        remoteCamera.applySettingsIntent(.automaticRotation(enabled))
    }

    func setRemoteCameraRotationDegrees(_ degrees: Int) {
        remoteCamera.applySettingsIntent(.rotationDegrees(degrees))
    }

    func resetRemoteCameraImageSettings() {
        remoteCamera.applySettingsIntent(.resetImageSettings)
    }

    func resetRemoteCameraSettings() {
        remoteCamera.resetSettings()
    }

    private func remoteCameraOptions() -> [SourceOption] {
        remoteCamera.cameraOptions()
    }

    func startRemoteCameraDiscoveryIfNeeded() {
        remoteCamera.startDiscoveryIfNeeded()
    }

    private func requireRemoteCameraConnection() async throws {
        try await remoteCamera.requireConnection()
    }

    private func remoteCameraConnectionBlocker() -> PermissionBlocker? {
        remoteCamera.connectionBlocker()
    }

    private func configureAudioLevelMonitoring() async {
        guard state != .idle || idleCaptureResourcesEnabled else {
            await stopAudioLevelMonitoring()
            return
        }
        if settings.enabledSources.contains(.microphone) {
            do {
                try microphoneLevelMonitor.start(settings: settings)
            } catch {
                microphoneLevelMonitor.stop()
            }
        } else {
            microphoneLevelMonitor.stop()
        }

        if settings.enabledSources.contains(.systemAudio) {
            let pickedScreenFilter = try? await resolvedScreenFilter(for: settings)
            guard pickedScreenFilter != nil else {
                try? await systemAudioLevelMonitor.stop()
                onAudioLevel?(.systemAudio, 0)
                return
            }
            guard state != .idle || idleCaptureResourcesEnabled else {
                await stopAudioLevelMonitoring()
                return
            }
            do {
                try await systemAudioLevelMonitor.start(.init(
                    settings: settings,
                    pickedScreenFilter: pickedScreenFilter
                ))
            } catch {
                try? await systemAudioLevelMonitor.stop()
            }
        } else {
            try? await systemAudioLevelMonitor.stop()
        }
        if state == .idle, !idleCaptureResourcesEnabled {
            await stopAudioLevelMonitoring()
        }
    }

    private func stopAudioLevelMonitoring() async {
        microphoneLevelMonitor.stop()
        try? await systemAudioLevelMonitor.stop()
    }

    private func clampedSceneFrame(_ frame: CGRect) -> CGRect {
        SceneLayerResizing.clamped(frame)
    }

    private func clampedNormalizedRect(_ rect: CGRect) -> CGRect {
        let rect = rect.standardized
        let x = min(1, max(0, rect.minX))
        let y = min(1, max(0, rect.minY))
        let maxX = min(1, max(x, rect.maxX))
        let maxY = min(1, max(y, rect.maxY))
        return CGRect(x: x, y: y, width: maxX - x, height: maxY - y)
    }

    private func isEffectivelyFullDisplayCrop(_ rect: CGRect) -> Bool {
        rect.minX <= 0.005
            && rect.minY <= 0.005
            && rect.width >= 0.99
            && rect.height >= 0.99
    }

    private func clampedCropAmount(_ amount: CGPoint) -> CGPoint {
        CGPoint(
            x: min(0.75, max(0, amount.x)),
            y: min(0.75, max(0, amount.y))
        )
    }

    private func clampedCropPosition(_ position: CGPoint) -> CGPoint {
        CGPoint(
            x: min(1, max(-1, position.x)),
            y: min(1, max(-1, position.y))
        )
    }

    private func clampedCanvasPadding(_ padding: CGFloat) -> CGFloat {
        min(0.16, max(0, padding))
    }

    private func clampedGain(_ gain: Double) -> Double {
        min(2.0, max(0.0, gain))
    }

    private func cameraDisplayName(for device: AVCaptureDevice) -> String {
        if device.isContinuityCamera {
            return "\(device.localizedName) (Continuity)"
        }
        if device.deviceType == .deskViewCamera {
            return "\(device.localizedName) (Desk View)"
        }
        return device.localizedName
    }

    private static func iPhoneMarketingName(for identifier: String?) -> String? {
        guard let identifier else { return nil }
        return [
            "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus",
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone17,3": "iPhone 16",
            "iPhone17,4": "iPhone 16 Plus",
            "iPhone17,1": "iPhone 16 Pro",
            "iPhone17,2": "iPhone 16 Pro Max"
        ][identifier]
    }

}

struct RemoteCameraDeviceSummary: Equatable, Identifiable {
    var id: String
    var cameraID: String
    var name: String
    var detail: String
    var status: String
    var isSelected: Bool
    var isReady: Bool
    var isTrusted: Bool
    var lensCount: Int?
}
