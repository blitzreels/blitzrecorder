import AppKit
import AVFoundation
import BlitzRecorderCore
import BlitzRecorderTransport
import Foundation
import ImageIO
import ScreenCaptureKit

@MainActor
final class RecorderCoordinator {
    let accessController: AccessController
    private let defaults: UserDefaults?

    private let screenRecorder = ScreenRecorder()
    private let screenPreviewer = ScreenPreviewer()
    private let screenContentPicker = ScreenContentPicker()
    private let screenCropPicker = ScreenCropPicker()
    private let cameraRecorder = CameraRecorder()
    private let cameraCutoutPreviewer = CameraCutoutPreviewer()
    private let audioRecorder = AudioRecorder()
    private let systemAudioRecorder = SystemAudioRecorder()
    private let takeRecording = TakeRecordingRuntime()
    private let remoteCameraMonitorSampleBufferFactory = RemoteCameraMonitorSampleBufferFactory()
    private let microphoneLevelMonitor = MicrophoneLevelMonitor()
    private let systemAudioLevelMonitor = SystemAudioLevelMonitor()
    private let speechTranscriber = SpeechTranscriber()
    private let titleGenerator = TitleGenerator()
    private let takeFileStore = TakeFileStore()
    private let recordingPrerollSeconds = 3
    private let remoteCameraBrowser = BonjourServiceBrowser(serviceType: RemoteCameraConstants.bonjourServiceType)
    private let remoteCameraControlClient = RemoteCameraControlClient()
    private lazy var remoteCameraRuntime = RemoteCameraSessionRuntime(
        sendCommand: { [weak self] command in
            self?.remoteCameraControlClient.send(command)
        },
        onMessage: { [weak self] message in
            self?.onMessage?(message)
        }
    )
    private var remoteCameraSessionState = RemoteIPhoneCameraState()
    private var remoteCameraReconnectTasks: [String: Task<Void, Never>] = [:]
    private var remoteCameraSettingsSendTasks: [String: Task<Void, Never>] = [:]
    private var remoteCameraPreviewSuppressedUntil: [String: Date] = [:]
    private var isRemoteCameraDiscoveryStarted = false
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

    private(set) var state: RecordingState = .idle {
        didSet { onStateChanged?(state) }
    }
    private(set) var settings: RecordingSettings
    private(set) var lastTake: RecordingTake?
    private var pickedScreenFilter: SCContentFilter?
    private var isEditingScreenCrop = false
    private(set) var screenContentSelectionRevision = 0
    private var outputDirectoryAccess: OutputDirectoryAccess?

    var onStateChanged: ((RecordingState) -> Void)?
    var onMessage: ((String) -> Void)?
    var onSavedRecording: ((SavedRecordingOutput) -> Void)?
    var onRecordingRecovery: ((RecordingRecoveryOutput) -> Void)?
    var onRenderProgress: ((Double) -> Void)?
    var onRuleOfThirdsOverlayChanged: ((Bool) -> Void)?
    var onSocialSafeZoneOverlayChanged: ((SocialVideoSafeZone) -> Void)?
    var onScreenCaptureConfigurationChanged: (() -> Void)?
    var onCameraConfigurationChanged: (() -> Void)?
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
        self.defaults = defaults
        settings = RecordingSettingsStore.load(defaults: defaults)
        if clearIncompatibleScreenCropForCurrentLayout() {
            persistSettings()
        }
        remoteCameraControlClient.onMessage = { [weak self] message in
            self?.onMessage?(message)
        }
        takeRecording.liveCompositedRecorder.onCameraPreviewSampleBuffer = { [weak self] sampleBuffer, width, height in
            guard let self,
                  self.state == .starting || self.state == .recording || self.state == .paused,
                  self.settings.visibleSources.contains(.camera) else {
                return
            }
            self.onLocalCameraPreviewSampleBuffer?(sampleBuffer, width, height)
        }
        if RemoteCameraProviderID.isRemote(settings.selectedCameraID) {
            startRemoteCameraDiscoveryIfNeeded()
        }
    }

    func cameraPreviewLayer() async throws -> AVCaptureVideoPreviewLayer {
        if isRemoteCameraSelected {
            throw RecorderError.remoteCameraPreviewUnavailable
        }
        try await requestCameraAccess()
        return try await cameraRecorder.makePreviewLayer(settings: settings)
    }

    func startScreenPreview(frameHandler: @escaping ScreenPreviewer.FrameHandler) async throws {
        var previewSettings = settings
        if isEditingScreenCrop {
            previewSettings.screenCrop = nil
            previewSettings.usesPickedScreenContent = false
        }
        try await screenPreviewer.start(settings: previewSettings, filter: isEditingScreenCrop ? nil : pickedScreenFilter, frameHandler: frameHandler)
    }

    var isScreenPreviewRunning: Bool {
        screenPreviewer.isRunning
    }

    func stopScreenPreview() async {
        try? await screenPreviewer.stop()
    }

    func stopCameraPreview() async {
        await cameraRecorder.stopSession()
        await cameraCutoutPreviewer.stop()
    }

    func startCameraCutoutPreview(frameHandler: @escaping CameraCutoutPreviewer.FrameHandler) async throws {
        if isRemoteCameraSelected {
            throw RecorderError.remoteCameraPreviewUnavailable
        }
        try await requestCameraAccess()
        await cameraRecorder.stopSession()
        try await cameraCutoutPreviewer.start(settings: settings, frameHandler: frameHandler)
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
        settings.layout = layout
        settings.screenCrop = nil
        let preset: ScenePreset
        if let saved = settings.selectedScenePreset, saved.supports(layout) {
            preset = saved
        } else {
            preset = ScenePreset.defaultPreset(for: layout)
            settings.selectedScenePreset = preset
        }
        settings.sceneLayout = SceneLayout.presetLayout(
            preset,
            for: layout,
            screenAspectRatio: currentScreenSourceAspectRatio(),
            cameraAspectRatio: currentCameraSourceAspectRatio()
        )
        persistSettings()
        onScreenCaptureConfigurationChanged?()
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

    func setOutputResolution(_ outputResolution: OutputResolution) {
        settings.outputResolution = outputResolution
        persistSettings()
    }

    func setOutputVideoFormat(_ outputVideoFormat: OutputVideoFormat) {
        settings.outputVideoFormat = outputVideoFormat
        persistSettings()
    }

    func setFramesPerSecond(_ framesPerSecond: Int) {
        guard RecordingSettings.supportedFrameRates.contains(framesPerSecond) else { return }
        settings.framesPerSecond = framesPerSecond
        persistSettings()
        onCameraConfigurationChanged?()
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
        if enabled, !wasEnabled, settings.enabledSources.contains(.screen) {
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
        persistSettings()
        onCameraConfigurationChanged?()
    }

    func setSourceFilesSaved(_ enabled: Bool) {
        settings.savesSourceFiles = enabled
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
        settings.selectedDisplayID = id
        pickedScreenFilter = nil
        settings.usesPickedScreenContent = false
        settings.screenCrop = nil
        persistSettings()
        refreshAudioLevelMonitoring()
        onScreenCaptureConfigurationChanged?()
    }

    func setCamera(id: String?) {
        let isRetryingSelectedRemoteCamera = id == settings.selectedCameraID
            && RemoteCameraProviderID.isRemote(id)
        settings.selectedCameraID = id
        if let serviceID = RemoteCameraProviderID.serviceID(from: id) {
            startRemoteCameraDiscoveryIfNeeded()
            connectRemoteCamera(serviceID: serviceID, forceReconnect: isRetryingSelectedRemoteCamera)
        } else {
            remoteCameraControlClient.disconnect()
        }
        persistSettings()
        onCameraConfigurationChanged?()
    }

    func setMicrophone(id: String?) {
        settings.selectedMicrophoneID = id
        persistSettings()
        refreshAudioLevelMonitoring()
    }

    func setSceneLayer(_ kind: SceneLayerKind, frame: CGRect) {
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
        updateRecordingSceneIfNeeded()
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
        persistSettings()
        updateRecordingSceneIfNeeded()
    }

    func setCanvasPadding(_ padding: CGFloat) {
        guard sceneChangeIsAllowed() else { return }
        settings.canvasPadding = clampedCanvasPadding(padding)
        persistSettings()
        updateRecordingSceneIfNeeded()
    }

    func connectDirectRemoteCamera(host: String, portString: String) {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPort = portString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty,
              let port = UInt16(trimmedPort),
              port > 0 else {
            onMessage?("Enter the iPhone IP address and the port shown in the companion app.")
            return
        }

        let service = DiscoveredBonjourService.directTCP(host: trimmedHost, port: port)
        remoteCameraSessionState.upsertDirectService(service)
        settings.selectedCameraID = RemoteCameraProviderID.make(for: service.id)
        persistSettings()
        connectRemoteCamera(serviceID: service.id)
        onCameraConfigurationChanged?()
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
        updateRecordingSceneIfNeeded()
        onScreenCaptureConfigurationChanged?()
    }

    func applyScenePreset(_ preset: ScenePreset) {
        guard sceneChangeIsAllowed() else { return }
        guard preset.supports(settings.layout) else { return }
        let enabledSourcesBeforePreset = settings.enabledSources
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
        updateRecordingSceneIfNeeded()
        onScreenCaptureConfigurationChanged?()
        if enabledSourcesBeforePreset.contains(.camera) != settings.enabledSources.contains(.camera) {
            onCameraConfigurationChanged?()
        }
    }

    func setScreenSplitHeight(_ height: CGFloat) {
        guard sceneChangeIsAllowed() else { return }
        guard settings.layout == .vertical else { return }
        let enabledSourcesBeforePreset = settings.enabledSources
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
        updateRecordingSceneIfNeeded()
        onScreenCaptureConfigurationChanged?()
        if enabledSourcesBeforePreset.contains(.camera) != settings.enabledSources.contains(.camera) {
            onCameraConfigurationChanged?()
        }
    }

    func targetWindowInfo() throws -> TargetWindowInfo {
        try ShortsWindowArranger.frontWindowInfo(displayID: settings.selectedDisplayID)
    }

    func fitFrontWindowForShorts() {
        fitFrontWindowForShorts(scale: 1)
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
        updateRecordingSceneIfNeeded()
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

    func fitFrontWindowForShorts(scale: CGFloat) {
        guard sceneChangeIsAllowed() else { return }
        guard ensureAccessibilityForWindowControls() else { return }

        let screenSlot = SceneSlotGeometry.targetWindowSlot(
            in: settings.sceneLayout,
            enabledSources: settings.enabledSources
        )

        do {
            let arrangement = try ShortsWindowArranger.fitFrontWindow(
                displayID: settings.selectedDisplayID,
                captureLayout: settings.layout,
                screenSlot: screenSlot,
                scale: scale
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
        if PermissionGate.hasAccessibilityAccess {
            return true
        }

        PermissionGate.requestAccessibilityAccess()
        if PermissionGate.hasAccessibilityAccess {
            return true
        }

        PermissionGate.openAccessibilitySettings()
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
        updateRecordingSceneIfNeeded()
    }

    func fitSceneLayer(_ kind: SceneLayerKind, scale: CGFloat = 1) {
        let sourceAspectRatio: CGFloat
        switch kind {
        case .screen:
            sourceAspectRatio = currentScreenSourceAspectRatio()
        case .camera:
            sourceAspectRatio = currentCameraSourceAspectRatio()
        }
        let frame = SceneLayout.canvasFillingFrame(
            sourceAspectRatio: sourceAspectRatio,
            canvasAspectRatio: settings.layout.aspectRatio
        )
        setSceneLayer(kind, frame: scaledSceneFrame(frame, scale: scale))
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
        if settings.usesPickedScreenContent && !isEditingScreenCrop {
            if let pickedScreenFilter {
                return ScreenCaptureGeometry.pickedContentAspectRatio(for: pickedScreenFilter)
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
        pickedScreenFilter = nil
        settings.usesPickedScreenContent = false
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

    func currentCameraSourceAspectRatio() -> CGFloat {
        guard let selectedServiceID = RemoteCameraProviderID.serviceID(from: settings.selectedCameraID),
              let capabilities = remoteCameraSessionState.capabilities[selectedServiceID] else {
            return SceneLayout.cameraAspectRatio
        }

        let remoteSettings = remoteCameraSettings(for: selectedServiceID)
        let selectableFormats = RemoteCameraSettingsResolver.formats(
            capabilities.supportedFormats,
            supportedBy: remoteSettings.captureProfileID,
            profiles: capabilities.supportedCaptureProfiles
        )
        let formatCandidates = selectableFormats.isEmpty ? capabilities.supportedFormats : selectableFormats
        guard let format = formatCandidates.first(where: { $0.id == remoteSettings.formatID })
            ?? formatCandidates.first else {
            return SceneLayout.cameraAspectRatio
        }

        return CGFloat(RemoteCameraSettingsResolver.aspectRatio(format: format, rotationDegrees: remoteSettings.rotationDegrees))
    }

    func selectScreenCrop() async throws {
        let crop = try await screenCropPicker.pick(
            displayID: settings.selectedDisplayID,
            initialCrop: settings.screenCrop
        )
        guard !crop.isNull, crop.width > 0, crop.height > 0 else {
            throw ScreenCropPickerError.selectionTooSmall
        }

        pickedScreenFilter = nil
        settings.usesPickedScreenContent = false
        let clampedCrop = clampedNormalizedRect(crop)
        settings.screenCrop = isEffectivelyFullDisplayCrop(clampedCrop) ? nil : clampedCrop
        persistSettings()
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
        onScreenCaptureConfigurationChanged?()
    }

    private func clearCustomScreenCrop() {
        guard settings.screenCrop != nil else { return }
        settings.screenCrop = nil
        persistSettings()
        onScreenCaptureConfigurationChanged?()
    }

    func availableDisplays() async -> [SourceOption] {
        if hasScreenCaptureAccess(),
           let content = try? await SCShareableContent.current,
           !content.displays.isEmpty {
            return content.displays.map { display in
                SourceOption(id: "\(display.displayID)", name: "Display \(display.displayID) (\(display.width)x\(display.height))")
            }
        }

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

    func hasScreenCaptureAccess() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    func requestScreenCaptureAccessIfNeeded() -> Bool {
        PermissionGate.requestScreenCaptureAccessIfNeeded()
    }

    func hasRequiredPermissions() -> Bool {
        recordingReadiness().isReady
    }

    func missingPermissionNames() -> [String] {
        PermissionGate.blockers(for: settings).map(\.permission)
    }

    func recordingReadiness() -> RecordingReadiness {
        let readiness = PermissionGate.readiness(for: settings)
        guard let remoteBlocker = remoteCameraConnectionBlocker() else {
            return readiness
        }

        let blockers = readiness.blockers + [remoteBlocker]
        return RecordingReadiness(
            isReady: false,
            title: readiness.title,
            detail: "Start disabled: \(readiness.statusLine) | Camera: \(remoteBlocker.status)",
            blockers: blockers,
            statusLine: "\(readiness.statusLine) | Camera: \(remoteBlocker.status)"
        )
    }

    func pickScreenContent() async throws {
        try await pickScreenContent(activatingScreenSource: false)
    }

    func pickScreenSource() async throws {
        try await pickScreenContent(activatingScreenSource: true)
    }

    private func pickScreenContent(activatingScreenSource: Bool) async throws {
        let filter = try await screenContentPicker.pick()
        pickedScreenFilter = filter
        screenContentSelectionRevision += 1
        settings.usesPickedScreenContent = true
        settings.screenCrop = nil
        if activatingScreenSource {
            settings.enabledSources.insert(.screen)
            settings.hiddenSources.remove(.screen)
        }
        persistSettings()
        updateRecordingSceneIfNeeded()
        onScreenCaptureConfigurationChanged?()
    }

    func requestPermissionsForEnabledSources() async {
        let needsScreenRecordingGrant =
            (settings.enabledSources.contains(.screen) && !settings.usesPickedScreenContent)
            || settings.enabledSources.contains(.systemAudio)
        if needsScreenRecordingGrant {
            _ = await PermissionGate.requestScreenCaptureAccess()
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
                cameraSortKey(lhs) < cameraSortKey(rhs)
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

        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .deskViewCamera, .external],
            mediaType: .video,
            position: .unspecified
        ).devices
            .filter { $0.isConnected && !$0.isSuspended }
            .sorted { lhs, rhs in
                cameraSortKey(lhs) < cameraSortKey(rhs)
            }

        return devices.first
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
            ?? AVCaptureDevice.default(for: .video)
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
            onMessage?("Free exports used. Subscribe for unlimited renders.")
            return
        }
        let readiness = recordingReadiness()
        guard readiness.isReady else {
            onMessage?(startBlockedMessage(readiness))
            return
        }
        do {
            outputDirectoryAccess?.stop()
            outputDirectoryAccess = try takeFileStore.prepareOutputDirectory(settings: settings)
        } catch {
            onMessage?("Start failed: \(error.localizedDescription)")
            return
        }
        state = .starting
        onMessage?("Not recording yet. Hang on while BlitzRecorder prepares capture.")

        Task {
            var createdTake: RecordingTake?
            var remoteStartCommandSent = false
            do {
                await stopAudioLevelMonitoring()
                guard !settings.enabledSources.isEmpty else {
                    throw RecorderError.noSourcesSelected
                }
                let usesRemoteCamera = settings.enabledSources.contains(.camera) && isRemoteCameraSelected
                if usesRemoteCamera {
                    try await requireRemoteCameraConnection()
                }
                if settings.enabledSources.contains(.camera), !usesRemoteCamera {
                    try await requestCameraAccess()
                    await cameraCutoutPreviewer.stop()
                }
                if settings.enabledSources.contains(.microphone) {
                    try await requestMicrophoneAccess()
                }
                if settings.enabledSources.contains(.systemAudio) {
                    guard hasScreenCaptureAccess() else {
                        throw RecorderError.screenCapturePermissionRequired
                    }
                }
                let take = try takeFileStore.createTake(settings: settings)
                createdTake = take
                let remoteTakeID = usesRemoteCamera ? UUID() : nil
                if let remoteTakeID {
                    remoteCameraRuntime.beginTake(
                        takeID: remoteTakeID,
                        serviceID: RemoteCameraProviderID.serviceID(from: settings.selectedCameraID),
                        take: take,
                        settings: settings
                    )
                    sendRemoteCameraSettings()
                    _ = try await remoteCameraRuntime.prepare(
                        takeID: remoteTakeID,
                        hostStartTime: DispatchTime.now().uptimeNanoseconds
                    )
                }
                if shouldUseLiveCompositor {
                    if settings.enabledSources.contains(.screen) || settings.enabledSources.contains(.systemAudio) {
                        guard settings.usesPickedScreenContent || hasScreenCaptureAccess() else {
                            throw RecorderError.screenCapturePermissionRequired
                        }
                    }
                    if settings.enabledSources.contains(.camera) {
                        await cameraRecorder.stopSession()
                    }
                    try await takeRecording.liveCompositedRecorder.start(
                        take: take,
                        settings: settings,
                        filter: pickedScreenFilter,
                        prerollSeconds: recordingPrerollSeconds
                    ) { [weak self] remaining in
                        self?.onMessage?(Self.recordingPrerollMessage(remaining: remaining))
                    }
                    takeRecording.markLiveCompositorStarted()
                    takeRecording.startSceneTimeline(settings: settings)
                    if let remoteTakeID {
                        remoteStartCommandSent = true
                        let hostStartTime = DispatchTime.now().uptimeNanoseconds
                        remoteCameraRuntime.markTimelineStart(takeID: remoteTakeID, hostTimelineStartTime: hostStartTime)
                        _ = try await remoteCameraRuntime.start(
                            takeID: remoteTakeID,
                            hostStartTime: hostStartTime,
                            hostTimelineStartTime: hostStartTime
                        )
                    }
                    lastTake = take
                    state = .recording
                    onMessage?("Recording with live compositor...")
                    return
                }
                if settings.enabledSources.contains(.screen) {
                    guard settings.usesPickedScreenContent || hasScreenCaptureAccess() else {
                        throw RecorderError.screenCapturePermissionRequired
                    }
                }
                let captureRun = CaptureSourceRun(
                    take: take,
                    settings: localCaptureSettings(usesRemoteCamera: usesRemoteCamera),
                    pickedScreenFilter: pickedScreenFilter,
                    screenRecorder: screenRecorder,
                    cameraRecorder: cameraRecorder,
                    audioRecorder: audioRecorder,
                    systemAudioRecorder: systemAudioRecorder
                )
                takeRecording.setActiveCaptureRun(captureRun)
                if let remoteTakeID {
                    remoteStartCommandSent = true
                    _ = try await remoteCameraRuntime.start(
                        takeID: remoteTakeID,
                        hostStartTime: DispatchTime.now().uptimeNanoseconds,
                        hostTimelineStartTime: nil
                    )
                }
                let captureStart = try await captureRun.start(
                    prerollSeconds: recordingPrerollSeconds
                ) { [weak self] remaining in
                    self?.onMessage?(Self.recordingPrerollMessage(remaining: remaining))
                }
                if let remoteTakeID {
                    remoteCameraRuntime.markTimelineStart(
                        takeID: remoteTakeID,
                        hostTimelineStartTime: captureStart.hostTimelineStartTime
                    )
                }
                lastTake = take
                takeRecording.startSceneTimeline(settings: settings)
                state = .recording
                onMessage?("Recording...")
            } catch {
                remoteCameraRuntime.cancelCommand()
                if let activeRemoteCameraTakeID = remoteCameraRuntime.activeTakeID, !remoteStartCommandSent {
                    remoteCameraRuntime.removePendingImport(takeID: activeRemoteCameraTakeID, settings: settings)
                }
                if let activeRemoteCameraTakeID = remoteCameraRuntime.activeTakeID {
                    remoteCameraRuntime.abandonTake(takeID: activeRemoteCameraTakeID)
                }
                await takeRecording.stopAnyActiveRecording()
                if let createdTake, !remoteStartCommandSent {
                    takeFileStore.cleanupIntermediateFiles(for: createdTake, settings: settings)
                }
                outputDirectoryAccess?.stop()
                outputDirectoryAccess = nil
                lastTake = nil
                state = .idle
                refreshAudioLevelMonitoring()
                onMessage?("Start failed: \(error.localizedDescription)")
            }
        }
    }

    private func startBlockedMessage(_ readiness: RecordingReadiness) -> String {
        if settings.enabledSources.isEmpty {
            return "Start failed: Select at least one source before recording."
        }
        if readiness.blockers.isEmpty {
            return "Start failed: \(readiness.detail)"
        }
        return "Start failed: \(readiness.blockers.map(\.sentence).joined(separator: " "))"
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
        guard state == .recording else { return }
        takeRecording.pause()
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        takeRecording.resume()
        state = .recording
    }

    func stop() {
        guard state == .recording || state == .paused else { return }
        takeRecording.pauseSceneTimeline()
        let sceneEventsForFinalization = takeRecording.sceneEvents
        state = .finishing
        onRenderProgress?(0)
        onMessage?("Stopping recording...")

        Task {
            do {
                let takeToFinalize = lastTake
                if takeRecording.isUsingLiveCompositor {
                    onMessage?("Saving recording...")
                    let completion = try await takeRecording.stopLiveCompositor()
                    onRenderProgress?(1)
                    try? await Task.sleep(for: .milliseconds(250))
                    if completion.wroteMedia, let finalURL = completion.url {
                        let savedURL: URL
                        if let takeToFinalize {
                            savedURL = await renameLiveCompositedOutputIfPossible(
                                outputURL: finalURL,
                                take: takeToFinalize,
                                settings: settings
                            )
                        } else {
                            savedURL = finalURL
                        }
                        accessController.recordSuccessfulExportIfNeeded()
                        if let takeToFinalize {
                            takeFileStore.cleanupIntermediateFiles(for: takeToFinalize, settings: settings)
                        }
                        outputDirectoryAccess?.stop()
                        outputDirectoryAccess = nil
                        let savedOutput = SavedRecordingOutput(url: savedURL, sourceDirectory: nil, warning: nil)
                        onSavedRecording?(savedOutput)
                        onMessage?(savedOutput.userMessage)
                    } else if let takeToFinalize {
                        outputDirectoryAccess?.stop()
                        outputDirectoryAccess = nil
                        let recovery = RecordingRecoveryOutput(
                            takeDirectory: takeToFinalize.scratchDirectory,
                            reason: "No video frames captured",
                            canRetryExport: false
                        )
                        onRecordingRecovery?(recovery)
                        onMessage?("Recording failed: \(recovery.userMessage)")
                    } else {
                        outputDirectoryAccess?.stop()
                        outputDirectoryAccess = nil
                        onMessage?("Recording failed: No video frames captured.")
                    }
                    lastTake = nil
                    state = .idle
                    refreshAudioLevelMonitoring()
                    return
                }
                var captureSummary = await takeRecording.stopCaptureRun()
                var stopWarnings: [String] = []
                if let warning = captureSummary.stopFailureWarning {
                    stopWarnings.append(warning)
                }
                if settings.enabledSources.contains(.camera), isRemoteCameraSelected, let takeToFinalize {
                    do {
                        onMessage?("Waiting for iPhone media...")
                        let remoteCompletion = try await stopRemoteCameraAndImport(take: takeToFinalize)
                        var completions = captureSummary.completions
                        completions[.camera] = remoteCompletion
                        captureSummary = CaptureSourceRunSummary(
                            completions: completions,
                            stopFailures: captureSummary.stopFailures
                        )
                    } catch {
                        lastTake = takeToFinalize
                        outputDirectoryAccess?.stop()
                        outputDirectoryAccess = nil
                        state = .idle
                        onRenderProgress?(0)
                        takeRecording.resetSceneTimeline()
                        refreshAudioLevelMonitoring()
                        onRecordingRecovery?(RecordingRecoveryOutput(
                            takeDirectory: takeToFinalize.scratchDirectory,
                            reason: "Remote iPhone import did not finish: \(error.recorderFailureDescription)",
                            canRetryExport: false
                        ))
                        onMessage?(remoteCameraImportFailureMessage(error: error, take: takeToFinalize))
                        return
                    }
                }

                if let takeToFinalize {
                    let outcome = await takeFinalizer.finalize(
                        take: takeToFinalize,
                        settings: settings,
                        captureSummary: captureSummary,
                        sceneEvents: sceneEventsForFinalization
                    )
                    if case .saved = outcome {
                        accessController.recordSuccessfulExportIfNeeded()
                        lastTake = nil
                    } else if case .recoveryFiles(let recoveryTake, _) = outcome {
                        lastTake = recoveryTake
                    }
                    outputDirectoryAccess?.stop()
                    outputDirectoryAccess = nil
                    state = .idle
                    takeRecording.resetSceneTimeline()
                    refreshAudioLevelMonitoring()
                    switch outcome {
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
                        let message = if let stopWarning {
                            "\(stopWarning). \(outcome.userMessage)"
                        } else {
                            outcome.userMessage
                        }
                        if let recovery = outcome.recoveryOutput() {
                            onRecordingRecovery?(recovery)
                        }
                        onMessage?("Recording failed: \(message)")
                    }
                } else {
                    outputDirectoryAccess?.stop()
                    outputDirectoryAccess = nil
                    state = .idle
                    takeRecording.resetSceneTimeline()
                    refreshAudioLevelMonitoring()
                }
            } catch {
                await takeRecording.stopAnyActiveRecording()
                outputDirectoryAccess?.stop()
                outputDirectoryAccess = nil
                state = .idle
                takeRecording.resetSceneTimeline()
                onRenderProgress?(0)
                refreshAudioLevelMonitoring()
                onMessage?("Recording failed: Stop failed: \(error.recorderFailureDescription)")
            }
        }
    }

    func refreshAudioLevelMonitoring() {
        guard state == .idle else { return }
        Task {
            await configureAudioLevelMonitoring()
        }
    }

    func mergeLastTake() {
        guard let lastTake else {
            onMessage?("No take to merge yet.")
            return
        }
        guard accessController.canRenderExport else {
            onMessage?("Free exports used. Subscribe for unlimited renders.")
            return
        }

        Task {
            do {
                let outputAccess = try takeFileStore.prepareOutputDirectory(settings: settings)
                defer { outputAccess.stop() }
                let url = try await Merger.exportFinalVideo(take: lastTake, settings: settings)
                accessController.recordSuccessfulExportIfNeeded()
                let sourceDirectory = lastTake.scratchDirectory
                self.lastTake = nil
                let savedOutput = SavedRecordingOutput(url: url, sourceDirectory: sourceDirectory, warning: nil)
                onSavedRecording?(savedOutput)
                onMessage?(savedOutput.userMessage)
            } catch {
                onMessage?("Final video export failed: \(error.recorderFailureDescription)")
            }
        }
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

    private func updateRecordingSceneIfNeeded() {
        let scene = RecordingScene(settings: settings)
        takeRecording.updateScene(scene)
        takeRecording.appendSceneEventIfNeeded(scene, state: state)
        synchronizeActiveCaptureSourcesIfNeeded()
    }

    private func synchronizeActiveCaptureSourcesIfNeeded() {
        guard !takeRecording.isUsingLiveCompositor,
              let activeCaptureRun = takeRecording.activeCaptureRun,
              state == .recording || state == .paused else {
            return
        }
        if settings.enabledSources.contains(.screen),
           !settings.usesPickedScreenContent,
           !hasScreenCaptureAccess() {
            onMessage?("Pick a screen or enable Screen Recording before adding screen capture to this recording.")
            return
        }
        if settings.enabledSources.contains(.systemAudio), !hasScreenCaptureAccess() {
            onMessage?("Enable Screen & System Audio Recording before adding system audio to this recording.")
            return
        }

        let localSettings = localCaptureSettings(
            usesRemoteCamera: settings.enabledSources.contains(.camera) && isRemoteCameraSelected
        )
        let pickedScreenFilter = pickedScreenFilter
        Task { [weak self, activeCaptureRun, localSettings, pickedScreenFilter] in
            do {
                try await activeCaptureRun.startEnabledSources(
                    settings: localSettings,
                    pickedScreenFilter: pickedScreenFilter
                )
            } catch {
                self?.onMessage?("Source could not be added to recording: \(error.localizedDescription)")
            }
        }
    }

    private func persistSettings() {
        RecordingSettingsStore.save(settings, defaults: defaults)
    }

    private func localCaptureSettings(usesRemoteCamera: Bool) -> RecordingSettings {
        takeRecording.localCaptureSettings(settings, usesRemoteCamera: usesRemoteCamera)
    }

    var isRemoteCameraSelected: Bool {
        RemoteCameraProviderID.isRemote(settings.selectedCameraID)
    }

    func selectedRemoteCameraName() -> String? {
        remoteCameraSessionState.selectedName(settings: settings)
    }

    func selectedRemoteCameraStatus() -> String? {
        remoteCameraSessionState.selectedStatus(
            settings: settings,
            previewHealthStatus: Self.previewHealthStatus
        )
    }

    func selectedRemoteCameraConnectionState() -> RemoteCameraConnectionState? {
        guard let selectedServiceID = RemoteCameraProviderID.serviceID(from: settings.selectedCameraID) else {
            return nil
        }
        return remoteCameraSessionState.connectionState(for: selectedServiceID)
    }

    func selectedRemoteCameraDeviceDescription() -> String {
        remoteCameraSessionState.selectedDeviceDescription(
            settings: settings,
            marketingName: Self.iPhoneMarketingName
        )
    }

    func selectedRemoteCameraCapabilities() -> RemoteCameraCapabilities? {
        guard let selectedServiceID = RemoteCameraProviderID.serviceID(from: settings.selectedCameraID) else {
            return nil
        }
        return remoteCameraSessionState.capabilities(for: selectedServiceID)
    }

    func selectedRemoteCameraTelemetry() -> RemoteCameraTelemetry? {
        remoteCameraSessionState.selectedTelemetry(
            settings: settings,
            normalizedSettings: { [weak self] proposedSettings, serviceID in
                guard let self else { return proposedSettings }
                return self.normalizedRemoteCameraSettings(proposedSettings, for: serviceID)
            }
        )
    }

    func remoteCameraDeviceSummaries() -> [RemoteCameraDeviceSummary] {
        remoteCameraSessionState.deviceSummaries(
            settings: settings,
            marketingName: Self.iPhoneMarketingName,
            previewHealthStatus: Self.previewHealthStatus
        )
    }

    func setRemoteCameraLens(_ lens: RemoteCameraLens) {
        applyRemoteCameraSettingsOverride { settings in
            settings.lens = lens
            settings.zoomFactor = 1
            settings.torchEnabled = false
        }
    }

    func setRemoteCameraFormat(id: String?, frameRate: Int) {
        applyRemoteCameraSettingsOverride { settings in
            settings.formatID = id
            settings.frameRate = frameRate
        }
    }

    func setRemoteCameraCaptureProfile(_ profileID: RemoteCameraCaptureProfileID) {
        if let selectedServiceID = RemoteCameraProviderID.serviceID(from: settings.selectedCameraID),
           let capabilities = remoteCameraSessionState.capabilities[selectedServiceID],
           let profile = capabilities.supportedCaptureProfiles.first(where: { $0.id == profileID }),
           !profile.isAvailable {
            onMessage?(profile.unavailableReason ?? "\(profile.displayName) is unavailable for this iPhone camera setting.")
            return
        }
        applyRemoteCameraSettingsOverride { settings in
            settings.captureProfileID = profileID
        }
    }

    func setRemoteCameraCinematicVideoEnabled(_ enabled: Bool) {
        applyRemoteCameraSettingsOverride { settings in
            settings.cinematicVideoEnabled = enabled
            if enabled,
               let selectedServiceID = RemoteCameraProviderID.serviceID(from: self.settings.selectedCameraID),
               let capabilities = self.remoteCameraSessionState.capabilities[selectedServiceID] {
                settings.cinematicAperture = settings.cinematicAperture
                    ?? capabilities.defaultCinematicAperture
                    ?? capabilities.minimumCinematicAperture
            } else {
                settings.cinematicAperture = nil
            }
        }
    }

    func setRemoteCameraCinematicAperture(_ aperture: Double) {
        applyRemoteCameraSettingsOverride { settings in
            settings.cinematicVideoEnabled = true
            settings.cinematicAperture = aperture
        }
    }

    func setRemoteCameraFocusMode(_ mode: RemoteCameraFocusMode) {
        applyRemoteCameraSettingsOverride { settings in
            settings.focusMode = mode
        }
    }

    func setRemoteCameraFocusPosition(_ position: Double) {
        applyRemoteCameraSettingsOverride { settings in
            settings.focusPosition = min(1, max(0, position))
        }
    }

    func setRemoteCameraExposureMode(_ mode: RemoteCameraExposureMode) {
        applyRemoteCameraSettingsOverride { settings in
            settings.exposureMode = mode
            if mode == .continuousAuto {
                settings.exposureBias = 0
                settings.iso = nil
                settings.shutterDurationSeconds = nil
            }
        }
    }

    func setRemoteCameraExposureBias(_ bias: Double) {
        applyRemoteCameraSettingsOverride { settings in
            settings.exposureBias = bias
        }
    }

    func resetRemoteCameraExposureBias() {
        applyRemoteCameraSettingsOverride { settings in
            settings.exposureMode = .continuousAuto
            settings.exposureBias = 0
            settings.iso = nil
            settings.shutterDurationSeconds = nil
        }
    }

    func setRemoteCameraISO(_ iso: Double?) {
        applyRemoteCameraSettingsOverride { settings in
            settings.iso = iso
        }
    }

    func setRemoteCameraShutterDuration(_ seconds: Double?) {
        applyRemoteCameraSettingsOverride { settings in
            settings.shutterDurationSeconds = seconds
        }
    }

    func setRemoteCameraWhiteBalanceMode(_ mode: RemoteCameraWhiteBalanceMode) {
        applyRemoteCameraSettingsOverride { settings in
            settings.whiteBalanceMode = mode
            if mode == .continuousAuto {
                settings.whiteBalanceTemperature = 5_500
                settings.whiteBalanceTint = 0
            }
        }
    }

    func setRemoteCameraWhiteBalance(temperature: Double, tint: Double) {
        applyRemoteCameraSettingsOverride { settings in
            settings.whiteBalanceTemperature = temperature
            settings.whiteBalanceTint = tint
        }
    }

    func setRemoteCameraStabilizationMode(_ mode: RemoteCameraStabilizationMode) {
        applyRemoteCameraSettingsOverride { settings in
            settings.stabilizationMode = mode
        }
    }

    func setRemoteCameraRotationDegrees(_ degrees: Int) {
        applyRemoteCameraSettingsOverride { settings in
            settings.rotationDegrees = RemoteCameraSettings.normalizedRotationDegrees(degrees)
        }
    }

    func resetRemoteCameraImageSettings() {
        applyRemoteCameraSettingsOverride { settings in
            settings.focusMode = .continuousAuto
            settings.focusPosition = 0.5
            settings.exposureMode = .continuousAuto
            settings.exposureBias = 0
            settings.iso = nil
            settings.shutterDurationSeconds = nil
            settings.whiteBalanceMode = .continuousAuto
            settings.whiteBalanceTemperature = 5_500
            settings.whiteBalanceTint = 0
        }
    }

    func resetRemoteCameraSettings() {
        guard let selectedServiceID = RemoteCameraProviderID.serviceID(from: settings.selectedCameraID) else {
            return
        }
        let resetSettings = normalizedRemoteCameraSettings(
            RemoteCameraSettings(frameRate: settings.framesPerSecond),
            for: selectedServiceID
        )
        settings.remoteCameraSettingsByServiceID[selectedServiceID] = resetSettings
        persistSettings()
        updateRemoteCameraTelemetry(for: selectedServiceID, activeSettings: resetSettings)
        remoteCameraSettingsSendTasks[selectedServiceID]?.cancel()
        remoteCameraSettingsSendTasks[selectedServiceID] = nil
        remoteCameraControlClient.send(.applySettings(resetSettings))
        onCameraConfigurationChanged?()
    }

    private func remoteCameraOptions() -> [SourceOption] {
        remoteCameraSessionState.cameraOptions()
    }

    func startRemoteCameraDiscoveryIfNeeded() {
        guard !isRemoteCameraDiscoveryStarted else { return }
        isRemoteCameraDiscoveryStarted = true

        remoteCameraControlClient.onStateChanged = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self,
                      let serviceID = RemoteCameraProviderID.serviceID(from: self.settings.selectedCameraID) else {
                    return
                }
                self.remoteCameraSessionState.setConnectionState(state, for: serviceID)
                switch state {
                case .connected, .pairing:
                    self.remoteCameraReconnectTasks[serviceID]?.cancel()
                    self.remoteCameraReconnectTasks[serviceID] = nil
                case .disconnected, .degraded:
                    self.scheduleRemoteCameraReconnect(serviceID: serviceID)
                default:
                    break
                }
                self.onCameraConfigurationChanged?()
            }
        }
        remoteCameraControlClient.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleRemoteCameraEvent(event)
            }
        }
        remoteCameraBrowser.onStateChanged = { [weak self] state in
            if case .failed(let message) = state {
                Task { @MainActor [weak self] in
                    self?.onMessage?("Remote iPhone discovery failed: \(message)")
                }
            }
        }
		remoteCameraBrowser.onServicesChanged = { [weak self] services in
			Task { @MainActor [weak self] in
				guard let self else { return }
				let previousServiceIDs = self.remoteCameraSessionState.replaceDiscoveredServices(services)
				if let selectedServiceID = RemoteCameraProviderID.serviceID(from: self.settings.selectedCameraID),
				   let service = self.bestMatchingRemoteCameraService(for: selectedServiceID, services: services) {
					if service.id != selectedServiceID {
						self.settings.selectedCameraID = RemoteCameraProviderID.make(for: service.id)
						self.persistSettings()
					}
					let wasRediscovered = !previousServiceIDs.contains(service.id)
					self.connectRemoteCamera(serviceID: service.id, forceReconnect: wasRediscovered)
				}
				self.onCameraConfigurationChanged?()
			}
		}
		remoteCameraBrowser.start()
	}

	private func bestMatchingRemoteCameraService(
		for selectedServiceID: String,
		services: [DiscoveredBonjourService]
	) -> DiscoveredBonjourService? {
		if let exactMatch = services.first(where: { $0.id == selectedServiceID }) {
			return exactMatch
		}
		let selectedName = selectedServiceID
			.split(separator: ".")
			.first
			.map(String.init)?
			.removingPercentEncoding
		if let selectedName,
		   let nameMatch = services.first(where: { $0.name == selectedName }) {
			return nameMatch
		}
		return services.count == 1 ? services[0] : nil
	}

	private func connectRemoteCamera(serviceID: String, forceReconnect: Bool = false) {
        guard let service = remoteCameraSessionState.service(id: serviceID) else {
            remoteCameraSessionState.setConnectionState(.discovering, for: serviceID)
            return
        }
        remoteCameraSessionState.setConnectionState(.pairing, for: serviceID)
        if forceReconnect || remoteCameraControlClient.connectedServiceID != serviceID {
            remoteCameraSessionState.clearSettingsRestoreMarker(for: serviceID)
        }
        remoteCameraControlClient.connect(to: service, forceReconnect: forceReconnect)
    }

    private func scheduleRemoteCameraReconnect(serviceID: String) {
        guard settings.selectedCameraID == RemoteCameraProviderID.make(for: serviceID),
              remoteCameraReconnectTasks[serviceID] == nil,
              remoteCameraSessionState.containsService(id: serviceID) else {
            return
        }
        remoteCameraReconnectTasks[serviceID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run { [weak self] in
                guard let self,
                      !Task.isCancelled,
                      self.settings.selectedCameraID == RemoteCameraProviderID.make(for: serviceID) else {
                    return
                }
                self.remoteCameraReconnectTasks[serviceID] = nil
                self.connectRemoteCamera(serviceID: serviceID, forceReconnect: true)
            }
        }
    }

    private func requireRemoteCameraConnection() async throws {
        guard let selectedServiceID = RemoteCameraProviderID.serviceID(from: settings.selectedCameraID) else {
            throw RecorderError.remoteCameraNotConnected
        }
        if remoteCameraIsConnected(serviceID: selectedServiceID) {
            return
        }

        if remoteCameraSessionState.containsService(id: selectedServiceID) {
            connectRemoteCamera(serviceID: selectedServiceID, forceReconnect: true)
        }

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if remoteCameraIsConnected(serviceID: selectedServiceID) {
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }

        throw RecorderError.remoteCameraNotConnected
    }

    private func remoteCameraIsConnected(serviceID: String) -> Bool {
        remoteCameraSessionState.connectionStates[serviceID] == .connected
            && remoteCameraControlClient.connectedServiceID == serviceID
            && remoteCameraControlClient.isConnected
    }

    private func remoteCameraConnectionBlocker() -> PermissionBlocker? {
        guard settings.enabledSources.contains(.camera),
              let selectedServiceID = RemoteCameraProviderID.serviceID(from: settings.selectedCameraID),
              !remoteCameraIsConnected(serviceID: selectedServiceID) else {
            return nil
        }

        if remoteCameraSessionState.containsService(id: selectedServiceID),
           remoteCameraSessionState.connectionStates[selectedServiceID] != .pairing {
            scheduleRemoteCameraReconnect(serviceID: selectedServiceID)
        }

        return PermissionBlocker(
            source: .camera,
            permission: "Remote iPhone",
            status: selectedRemoteCameraStatus() ?? "not connected",
            recovery: "Keep the iPhone camera app open and wait for it to reconnect."
        )
    }

    private func sendRemoteCameraSettings() {
        guard let selectedServiceID = RemoteCameraProviderID.serviceID(from: settings.selectedCameraID) else {
            return
        }
        remoteCameraSettingsSendTasks[selectedServiceID]?.cancel()
        remoteCameraSettingsSendTasks[selectedServiceID] = nil
        remoteCameraControlClient.send(.applySettings(remoteCameraSettings(for: selectedServiceID)))
    }

    private func applyRemoteCameraSettingsOverride(_ update: (inout RemoteCameraSettings) -> Void) {
        guard let selectedServiceID = RemoteCameraProviderID.serviceID(from: settings.selectedCameraID) else {
            return
        }
        var remoteSettings = remoteCameraSettings(for: selectedServiceID)
        update(&remoteSettings)
        remoteSettings = normalizedRemoteCameraSettings(remoteSettings, for: selectedServiceID)
        settings.remoteCameraSettingsByServiceID[selectedServiceID] = remoteSettings
        suppressRemoteCameraPreview(serviceID: selectedServiceID, message: "Updating iPhone camera...")
        refreshSelectedScenePresetLayoutIfNeeded()
        persistSettings()
        updateRemoteCameraTelemetry(for: selectedServiceID, activeSettings: remoteSettings)
        scheduleRemoteCameraSettingsSend(remoteSettings, serviceID: selectedServiceID)
        onCameraConfigurationChanged?()
    }

    private func refreshSelectedScenePresetLayoutIfNeeded() {
        guard let preset = settings.selectedScenePreset,
              preset.supports(settings.layout) else {
            return
        }
        settings.sceneLayout = SceneLayout.presetLayout(
            preset,
            for: settings.layout,
            screenAspectRatio: currentScreenSourceAspectRatio(),
            cameraAspectRatio: currentCameraSourceAspectRatio()
        )
    }

    private func scheduleRemoteCameraSettingsSend(_ remoteSettings: RemoteCameraSettings, serviceID: String) {
        remoteCameraSettingsSendTasks[serviceID]?.cancel()
        remoteCameraSettingsSendTasks[serviceID] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            await MainActor.run { [weak self] in
                guard let self,
                      !Task.isCancelled,
                      self.settings.selectedCameraID == RemoteCameraProviderID.make(for: serviceID) else {
                    return
                }
                self.remoteCameraSettingsSendTasks[serviceID] = nil
                self.remoteCameraControlClient.send(.applySettings(remoteSettings))
            }
        }
    }

    private func remoteCameraSettings(for selectedServiceID: String) -> RemoteCameraSettings {
        let activeTelemetry = remoteCameraSessionState.telemetry[selectedServiceID]
        return normalizedRemoteCameraSettings(
            settings.remoteCameraSettingsByServiceID[selectedServiceID]
                ?? activeTelemetry?.activeSettings
                ?? RemoteCameraSettings(),
            for: selectedServiceID
        )
    }

    private static func previewHealthStatus(_ health: RemoteCameraPreviewHealth) -> String {
        if let lastFrameAgeSeconds = health.lastFrameAgeSeconds, lastFrameAgeSeconds >= 2 {
            return "Waiting for live view"
        }
        return "iPhone connected"
    }

    private func suppressRemoteCameraPreview(serviceID: String, message: String) {
        remoteCameraPreviewSuppressedUntil[serviceID] = Date().addingTimeInterval(1.25)
        onRemoteCameraPreviewReset?(message)
    }

    private func isRemoteCameraPreviewSuppressed(serviceID: String) -> Bool {
        guard let suppressedUntil = remoteCameraPreviewSuppressedUntil[serviceID] else {
            return false
        }
        if Date() < suppressedUntil {
            return true
        }
        remoteCameraPreviewSuppressedUntil.removeValue(forKey: serviceID)
        return false
    }

    private func updateRemoteCameraTelemetry(for selectedServiceID: String, activeSettings: RemoteCameraSettings) {
        remoteCameraSessionState.updateTelemetrySettings(for: selectedServiceID, activeSettings: activeSettings)
    }

    private func normalizedRemoteCameraSettings(
        _ proposedSettings: RemoteCameraSettings,
        for selectedServiceID: String
    ) -> RemoteCameraSettings {
        RemoteCameraSettingsResolver.normalized(
            proposedSettings,
            capabilities: remoteCameraSessionState.capabilities[selectedServiceID],
            preferredFrameRate: settings.framesPerSecond
        )
    }

    private func stopRemoteCameraAndImport(take: RecordingTake) async throws -> MediaWriterCompletion {
        try await remoteCameraRuntime.stopAndImport(take: take, settings: settings)
    }

    private func remoteCameraImportFailureMessage(error: Error, take: RecordingTake) -> String {
        let reason = error.recorderFailureDescription
        let lowercasedReason = reason.lowercased()
        let failedBeforeSavingMedia = lowercasedReason.contains("failed before stop")
            || lowercasedReason.contains("empty file")
            || lowercasedReason.contains("while failed")

        if failedBeforeSavingMedia {
            return "Recording failed: iPhone camera did not save usable media: \(reason). "
                + "Screen/source files are in \(take.scratchDirectory.path)."
        }

        return "Recording failed: Remote iPhone import did not finish: \(reason). "
            + "The take is waiting for the iPhone master recording. Keep both devices on the same Wi-Fi, reopen BlitzRecorder Camera, then retry the pending import. Recovery files: \(take.scratchDirectory.path)"
    }

    private func handleRemoteCameraEvent(_ event: RemoteCameraEvent) {
        guard let serviceID = RemoteCameraProviderID.serviceID(from: settings.selectedCameraID) else {
            return
        }
        switch event {
        case .pairingChallenge(let challenge):
            remoteCameraSessionState.setConnectionState(.pairing, for: serviceID)
            if !challenge.requiresShortCode {
                remoteCameraControlClient.pair(shortCode: "", challenge: challenge)
                onMessage?("Verifying trusted Remote iPhone Camera...")
                onCameraConfigurationChanged?()
                return
            }
            guard let code = requestRemoteCameraPairingCode(for: challenge) else {
                remoteCameraControlClient.send(.cancel)
                onMessage?("Remote iPhone pairing cancelled.")
                onCameraConfigurationChanged?()
                return
            }
            remoteCameraControlClient.pair(shortCode: code, challenge: challenge)
            onMessage?("Pairing \(challenge.deviceName)...")
            onCameraConfigurationChanged?()
        case .paired(let trust):
            settings.trustedRemoteCameraServiceIDs.insert(serviceID)
            persistSettings()
            remoteCameraSessionState.setConnectionState(.connected, for: serviceID)
            onMessage?("Paired \(trust.deviceName) as Remote iPhone Camera.")
            remoteCameraControlClient.send(.requestCapabilities)
            attemptPendingRemoteCameraImports(serviceID: serviceID)
            onCameraConfigurationChanged?()
        case .capabilities(let capabilities):
            remoteCameraSessionState.setCapabilities(capabilities, for: serviceID)
            remoteCameraSessionState.setConnectionState(.connected, for: serviceID)
            onMessage?("Remote iPhone ready: \(capabilities.supportedLenses.map(\.displayName).joined(separator: ", "))")
            if settings.selectedCameraID == RemoteCameraProviderID.make(for: serviceID),
               settings.selectedScenePreset?.supports(settings.layout) == true {
                refreshSelectedScenePresetLayoutIfNeeded()
                persistSettings()
            }
            if settings.remoteCameraSettingsByServiceID[serviceID] != nil,
               !remoteCameraSessionState.hasSentSettingsRestore(for: serviceID) {
                let remoteSettings = remoteCameraSettings(for: serviceID)
                updateRemoteCameraTelemetry(for: serviceID, activeSettings: remoteSettings)
                remoteCameraSessionState.markSettingsRestoreSent(for: serviceID)
                suppressRemoteCameraPreview(serviceID: serviceID, message: "Updating iPhone camera...")
                remoteCameraControlClient.send(.applySettings(remoteSettings))
            }
            attemptPendingRemoteCameraImports(serviceID: serviceID)
            onCameraConfigurationChanged?()
        case .telemetry(let telemetry):
            remoteCameraSessionState.setTelemetry(telemetry, for: serviceID)
            onCameraConfigurationChanged?()
        case .failed(let failedTakeID, let reason):
            remoteCameraSessionState.setConnectionState(.degraded, for: serviceID)
            onMessage?("Remote iPhone error: \(reason)")
            remoteCameraRuntime.handleFailed(takeID: failedTakeID, reason: reason)
        case .transferReady(let takeID, _, let byteCount, let manifest):
            remoteCameraRuntime.applyTransferReady(
                takeID: takeID,
                byteCount: byteCount,
                manifest: manifest,
                settings: settings
            )
            onCameraConfigurationChanged?()
        case .monitorFrame(let jpegData, _, _):
            guard !isRemoteCameraPreviewSuppressed(serviceID: serviceID) else { return }
            if let image = Self.makeCGImage(fromJPEGData: jpegData) {
                onRemoteCameraPreviewFrame?(image)
            }
        case .monitorVideoFrame(let frame):
            guard !isRemoteCameraPreviewSuppressed(serviceID: serviceID) else { return }
            if let sampleBuffer = remoteCameraMonitorSampleBufferFactory.makeSampleBuffer(from: frame) {
                onRemoteCameraPreviewSampleBuffer?(sampleBuffer, frame.width, frame.height)
            }
        case .transferChunk(let takeID, let offset, let data, let isFinal):
            remoteCameraRuntime.writeChunk(takeID: takeID, offset: offset, data: data, isFinal: isFinal)
            onCameraConfigurationChanged?()
        case .transferComplete(let takeID, let byteCount, let sha256):
            remoteCameraRuntime.completeTransfer(
                takeID: takeID,
                byteCount: byteCount,
                sha256: sha256,
                settings: settings
            )
            onCameraConfigurationChanged?()
        case .prepared(let takeID, let deviceStartTime):
            remoteCameraRuntime.resolvePrepared(takeID: takeID, deviceStartTime: deviceStartTime)
            onCameraConfigurationChanged?()
        case .started(let takeID, let deviceStartTime):
            remoteCameraRuntime.resolveStarted(takeID: takeID, deviceStartTime: deviceStartTime)
            onCameraConfigurationChanged?()
        case .stopped(_, _, _, let reason):
            if let reason, !reason.isEmpty {
                onMessage?("Remote iPhone stopped recording: \(reason)")
            }
            onCameraConfigurationChanged?()
        }
    }

    private func attemptPendingRemoteCameraImports(serviceID: String) {
        guard state == .idle || state == .finishing else { return }
        remoteCameraRuntime.requestPendingImports(serviceID: serviceID, settings: settings)
    }

    private func requestRemoteCameraPairingCode(for challenge: RemoteCameraPairingChallenge) -> String? {
        guard let rawCode = onRemoteCameraPairingCodeRequested?(challenge.deviceName) else {
            return nil
        }
        let code = RemoteCameraPairingCode.normalized(rawCode)
        return RemoteCameraPairingCode.isValid(code) ? code : nil
    }

    private static func makeCGImage(fromJPEGData data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func configureAudioLevelMonitoring() async {
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
            guard hasScreenCaptureAccess() else {
                try? await systemAudioLevelMonitor.stop()
                onAudioLevel?(.systemAudio, 0)
                return
            }
            do {
                try await systemAudioLevelMonitor.start(settings: settings)
            } catch {
                try? await systemAudioLevelMonitor.stop()
            }
        } else {
            try? await systemAudioLevelMonitor.stop()
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

    private func requestCameraAccess() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted { throw RecorderError.noCamera }
        default:
            throw RecorderError.noCamera
        }
    }

    private func requestMicrophoneAccess() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted { throw RecorderError.microphoneUnavailable }
        default:
            throw RecorderError.microphoneUnavailable
        }
    }

    private func cameraSortKey(_ device: AVCaptureDevice) -> String {
        let priority: String
        if device.isContinuityCamera {
            priority = "0"
        } else if device.deviceType == .external {
            priority = "1"
        } else if device.deviceType == .deskViewCamera {
            priority = "2"
        } else {
            priority = "3"
        }
        return "\(priority)-\(device.localizedName)"
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
