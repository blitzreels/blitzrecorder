import AppKit
import AVFoundation
import BlitzRecorderCore
import BlitzRecorderTransport
import CryptoKit
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
    private let liveCompositedRecorder = LiveCompositedRecorder()
    private let remoteCameraMonitorSampleBufferFactory = RemoteCameraMonitorSampleBufferFactory()
    private let microphoneLevelMonitor = MicrophoneLevelMonitor()
    private let systemAudioLevelMonitor = SystemAudioLevelMonitor()
    private let speechTranscriber = SpeechTranscriber()
    private let titleGenerator = TitleGenerator()
    private let takeFileStore = TakeFileStore()
    private let remoteCameraPendingImportStore = RemoteCameraPendingImportStore()
    private let remoteCameraBrowser = BonjourServiceBrowser(serviceType: RemoteCameraConstants.bonjourServiceType)
    private let remoteCameraControlClient = RemoteCameraControlClient()
    private var remoteCameraServices: [DiscoveredBonjourService] = []
    private var remoteCameraConnectionStates: [String: RemoteCameraConnectionState] = [:]
    private var remoteCameraCapabilities: [String: RemoteCameraCapabilities] = [:]
    private var remoteCameraTelemetry: [String: RemoteCameraTelemetry] = [:]
    private var activeRemoteCameraTakeID: UUID?
    private var pendingRemoteCameraTransfers: [UUID: RemoteCameraTransferSession] = [:]
    private var remoteCameraTransferContinuations: [UUID: CheckedContinuation<MediaWriterCompletion, Error>] = [:]
    private var remoteCameraPrepareContinuations: [UUID: CheckedContinuation<UInt64, Error>] = [:]
    private var remoteCameraStartContinuations: [UUID: CheckedContinuation<UInt64, Error>] = [:]
    private var remoteCameraSyncTimeoutTasks: [RemoteCameraSyncKey: Task<Void, Never>] = [:]
    private var remoteCameraTransferTimeoutTasks: [UUID: Task<Void, Never>] = [:]
    private var remoteCameraReconnectTasks: [String: Task<Void, Never>] = [:]
    private var remoteCameraSettingsSendTasks: [String: Task<Void, Never>] = [:]
    private var remoteCameraSettingsRestoreSentForServiceIDs: Set<String> = []
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
    private var isUsingLiveCompositor = false
    private var activeCaptureRun: CaptureSourceRun?
    private var outputDirectoryAccess: OutputDirectoryAccess?
    private var recordingSceneEvents: [RecordingSceneEvent] = []
    private var recordingTimelineSegmentStartedAt: Date?
    private var recordingTimelineAccumulatedSeconds: TimeInterval = 0

    private struct RemoteCameraTransferSession {
        let destinationURL: URL
        let partialURL: URL
        let fileHandle: FileHandle
        let expectedByteCount: Int64
        let expectedSHA256: String?
        let manifest: RemoteCameraTransferManifest?
        var receivedByteCount: Int64
    }

    private enum RemoteCameraSyncPhase: Hashable {
        case prepare
        case start

        var timeoutMessage: String {
            switch self {
            case .prepare:
                "Timed out waiting for iPhone prepare acknowledgement."
            case .start:
                "Timed out waiting for iPhone start acknowledgement."
            }
        }
    }

    private struct RemoteCameraSyncKey: Hashable {
        let takeID: UUID
        let phase: RemoteCameraSyncPhase
    }

    var onStateChanged: ((RecordingState) -> Void)?
    var onMessage: ((String) -> Void)?
    var onRenderProgress: ((Double) -> Void)?
    var onRuleOfThirdsOverlayChanged: ((Bool) -> Void)?
    var onSocialSafeZoneOverlayChanged: ((SocialVideoSafeZone) -> Void)?
    var onScreenCaptureConfigurationChanged: (() -> Void)?
    var onCameraConfigurationChanged: (() -> Void)?
    var onRemoteCameraPreviewFrame: ((CGImage) -> Void)?
    var onRemoteCameraPreviewSampleBuffer: ((CMSampleBuffer, Int, Int) -> Void)?
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
        startRemoteCameraDiscovery()
    }

    func cameraPreviewLayer() async throws -> AVCaptureVideoPreviewLayer {
        if isRemoteCameraSelected {
            throw RecorderError.remoteCameraPreviewUnavailable
        }
        try await requestCameraAccess()
        return try await cameraRecorder.makePreviewLayer(settings: settings)
    }

    func startScreenPreview(frameHandler: @escaping ScreenPreviewer.FrameHandler) async throws {
        try await screenPreviewer.start(settings: settings, filter: pickedScreenFilter, frameHandler: frameHandler)
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
        guard state == .idle || isUsingLiveCompositor else {
            onMessage?("Capture source visibility is locked while recording.")
            return
        }
        if enabled {
            settings.enabledSources.insert(source)
            settings.hiddenSources.remove(source)
        } else {
            settings.enabledSources.remove(source)
            settings.hiddenSources.insert(source)
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
        settings.selectedCameraID = id
        if let serviceID = RemoteCameraProviderID.serviceID(from: id) {
            connectRemoteCamera(serviceID: serviceID)
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
        switch kind {
        case .screen:
            settings.sceneLayout.screenFrame = clampedSceneFrame(frame)
        case .camera:
            settings.sceneLayout.cameraFrame = clampedSceneFrame(frame)
        }
        persistSettings()
        updateRecordingSceneIfNeeded()
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
        if let existingIndex = remoteCameraServices.firstIndex(where: { $0.id == service.id }) {
            remoteCameraServices[existingIndex] = service
        } else {
            remoteCameraServices.insert(service, at: 0)
        }
        settings.selectedCameraID = RemoteCameraProviderID.make(for: service.id)
        persistSettings()
        connectRemoteCamera(serviceID: service.id)
        onCameraConfigurationChanged?()
    }

    func setSceneLayout(_ sceneLayout: SceneLayout) {
        guard sceneChangeIsAllowed() else { return }
        settings.selectedScenePreset = nil
        settings.sceneLayout.screenFrame = clampedSceneFrame(sceneLayout.screenFrame)
        settings.sceneLayout.cameraFrame = clampedSceneFrame(sceneLayout.cameraFrame)
        settings.sceneLayout.layerOrder = sceneLayout.layerOrder
        persistSettings()
        updateRecordingSceneIfNeeded()
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
        settings.selectedScenePreset = preset
        settings.sceneLayout = SceneLayout.presetLayout(
            preset,
            for: settings.layout,
            screenAspectRatio: currentScreenSourceAspectRatio(),
            cameraAspectRatio: currentCameraSourceAspectRatio()
        )
        persistSettings()
        updateRecordingSceneIfNeeded()
        onScreenCaptureConfigurationChanged?()
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
        if settings.usesPickedScreenContent {
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
            for: settings,
            fallback: CGFloat(width) / CGFloat(height)
        )
    }

    func currentCameraSourceAspectRatio() -> CGFloat {
        guard let selectedServiceID = RemoteCameraProviderID.serviceID(from: settings.selectedCameraID),
              let capabilities = remoteCameraCapabilities[selectedServiceID] else {
            return SceneLayout.cameraAspectRatio
        }

        let remoteSettings = remoteCameraSettings(for: selectedServiceID)
        let selectableFormats = Self.remoteCameraFormats(
            capabilities.supportedFormats,
            supportedBy: remoteSettings.captureProfileID,
            profiles: capabilities.supportedCaptureProfiles
        )
        let formatCandidates = selectableFormats.isEmpty ? capabilities.supportedFormats : selectableFormats
        guard let format = formatCandidates.first(where: { $0.id == remoteSettings.formatID })
            ?? formatCandidates.first else {
            return SceneLayout.cameraAspectRatio
        }

        return Self.remoteCameraAspectRatio(
            width: format.width,
            height: format.height,
            rotationDegrees: remoteSettings.rotationDegrees
        )
    }

    func selectScreenCrop() async throws {
        let crop = try await screenCropPicker.pick(displayID: settings.selectedDisplayID)
        guard !crop.isNull, crop.width > 0, crop.height > 0 else {
            throw ScreenCropPickerError.selectionTooSmall
        }

        pickedScreenFilter = nil
        settings.usesPickedScreenContent = false
        settings.screenCrop = clampedNormalizedRect(crop)
        persistSettings()
        onScreenCaptureConfigurationChanged?()
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
        PermissionGate.readiness(for: settings)
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
        onMessage?("Starting recording...")

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
                    try requireRemoteCameraConnection()
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
                    activeRemoteCameraTakeID = remoteTakeID
                    remoteCameraPendingImportStore.upsert(RemoteCameraPendingImport(
                        takeID: remoteTakeID,
                        serviceID: RemoteCameraProviderID.serviceID(from: settings.selectedCameraID),
                        scratchDirectory: take.scratchDirectory,
                        destinationURL: take.cameraURL,
                        createdAt: Date(),
                        expectedByteCount: nil
                    ), settings: settings)
                    sendRemoteCameraSettings()
                    _ = try await prepareRemoteCamera(takeID: remoteTakeID, hostStartTime: DispatchTime.now().uptimeNanoseconds)
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
                    try await liveCompositedRecorder.start(take: take, settings: settings, filter: pickedScreenFilter)
                    isUsingLiveCompositor = true
                    startRecordingSceneTimeline()
                    if let remoteTakeID {
                        remoteStartCommandSent = true
                        _ = try await startRemoteCamera(takeID: remoteTakeID, hostStartTime: DispatchTime.now().uptimeNanoseconds)
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
                    timelineStartTime: CMClockGetTime(CMClockGetHostTimeClock()),
                    screenRecorder: screenRecorder,
                    cameraRecorder: cameraRecorder,
                    audioRecorder: audioRecorder,
                    systemAudioRecorder: systemAudioRecorder
                )
                activeCaptureRun = captureRun
                try await captureRun.start()
                if let remoteTakeID {
                    remoteStartCommandSent = true
                    _ = try await startRemoteCamera(takeID: remoteTakeID, hostStartTime: DispatchTime.now().uptimeNanoseconds)
                }
                lastTake = take
                startRecordingSceneTimeline()
                state = .recording
                onMessage?("Recording...")
            } catch {
                remoteCameraControlClient.send(.cancel)
                if let activeRemoteCameraTakeID, !remoteStartCommandSent {
                    remoteCameraPendingImportStore.remove(takeID: activeRemoteCameraTakeID, settings: settings)
                }
                if let activeRemoteCameraTakeID {
                    failRemoteCameraSync(
                        takeID: activeRemoteCameraTakeID,
                        phase: .prepare,
                        reason: "Recording start failed before prepare completed."
                    )
                    failRemoteCameraSync(
                        takeID: activeRemoteCameraTakeID,
                        phase: .start,
                        reason: "Recording start failed before remote start completed."
                    )
                }
                activeRemoteCameraTakeID = nil
                _ = await activeCaptureRun?.stop()
                activeCaptureRun = nil
                _ = try? await liveCompositedRecorder.stop()
                isUsingLiveCompositor = false
                resetRecordingSceneTimeline()
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

    func pause() {
        guard state == .recording else { return }
        pauseRecordingSceneTimeline()
        if isUsingLiveCompositor {
            liveCompositedRecorder.pause()
            state = .paused
            return
        }
        activeCaptureRun?.pause()
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        resumeRecordingSceneTimeline()
        if isUsingLiveCompositor {
            liveCompositedRecorder.resume()
            state = .recording
            return
        }
        activeCaptureRun?.resume()
        state = .recording
    }

    func stop() {
        guard state == .recording || state == .paused else { return }
        pauseRecordingSceneTimeline()
        let sceneEventsForFinalization = recordingSceneEvents
        state = .finishing
        onRenderProgress?(0)
        onMessage?("Stopping recording...")

        Task {
            do {
                let takeToFinalize = lastTake
                if isUsingLiveCompositor {
                    onMessage?("Saving recording...")
                    let completion = try await liveCompositedRecorder.stop()
                    onRenderProgress?(1)
                    try? await Task.sleep(for: .milliseconds(250))
                    if completion.wroteMedia, let finalURL = completion.url {
                        accessController.recordSuccessfulExportIfNeeded()
                        if let takeToFinalize {
                            takeFileStore.cleanupIntermediateFiles(for: takeToFinalize, settings: settings)
                        }
                        outputDirectoryAccess?.stop()
                        outputDirectoryAccess = nil
                        onMessage?("Saved: \(finalURL.path)")
                    } else if let takeToFinalize {
                        outputDirectoryAccess?.stop()
                        outputDirectoryAccess = nil
                        onMessage?("Recording failed: No video frames captured. Recovery files: \(takeToFinalize.scratchDirectory.path)")
                    } else {
                        outputDirectoryAccess?.stop()
                        outputDirectoryAccess = nil
                        onMessage?("Recording failed: No video frames captured.")
                    }
                    lastTake = nil
                    isUsingLiveCompositor = false
                    resetRecordingSceneTimeline()
                    state = .idle
                    refreshAudioLevelMonitoring()
                    return
                }
                var captureSummary = await activeCaptureRun?.stop()
                    ?? CaptureSourceRunSummary(completions: [:])
                var stopWarnings: [String] = []
                if let warning = captureSummary.stopFailureWarning {
                    stopWarnings.append(warning)
                }
                activeCaptureRun = nil
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
                        resetRecordingSceneTimeline()
                        refreshAudioLevelMonitoring()
                        onMessage?(
                            "Recording failed: Remote iPhone import did not finish: \(error.recorderFailureDescription). "
                                + "The take is waiting for the iPhone master recording. Keep both devices on the same Wi-Fi, reopen BlitzRecorder Camera, then retry the pending import. Recovery files: \(takeToFinalize.scratchDirectory.path)"
                        )
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
                    resetRecordingSceneTimeline()
                    refreshAudioLevelMonitoring()
                    switch outcome {
                    case .saved:
                        let stopWarning = stopWarnings.isEmpty ? nil : stopWarnings.joined(separator: ". ")
                        if let stopWarning {
                            onMessage?("\(stopWarning). \(outcome.userMessage)")
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
                        onMessage?("Recording failed: \(message)")
                    }
                } else {
                    outputDirectoryAccess?.stop()
                    outputDirectoryAccess = nil
                    state = .idle
                    resetRecordingSceneTimeline()
                    refreshAudioLevelMonitoring()
                }
            } catch {
                if isUsingLiveCompositor {
                    _ = try? await liveCompositedRecorder.stop()
                    isUsingLiveCompositor = false
                }
                _ = await activeCaptureRun?.stop()
                activeCaptureRun = nil
                outputDirectoryAccess?.stop()
                outputDirectoryAccess = nil
                state = .idle
                resetRecordingSceneTimeline()
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
                onMessage?("Final video: \(url.path)")
            } catch {
                onMessage?("Final video export failed: \(error.recorderFailureDescription)")
            }
        }
    }

    func zoomIn() {
        guard !isUsingLiveCompositor else { return }
        screenRecorder.zoomIn()
    }

    func zoomOut() {
        guard !isUsingLiveCompositor else { return }
        screenRecorder.zoomOut()
    }

    func resetZoom() {
        guard !isUsingLiveCompositor else { return }
        screenRecorder.resetZoom()
    }

    func openOutputFolder() {
        NSWorkspace.shared.open(settings.outputDirectory)
    }

    private var shouldUseLiveCompositor: Bool {
        !settings.savesSourceFiles
            && !settings.removesCameraBackgroundAfterRecording
            && !isRemoteCameraSelected
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
        if isUsingLiveCompositor {
            liveCompositedRecorder.updateScene(scene)
        }
        appendRecordingSceneEventIfNeeded(scene)
    }

    private func startRecordingSceneTimeline() {
        recordingTimelineAccumulatedSeconds = 0
        recordingTimelineSegmentStartedAt = Date()
        recordingSceneEvents = [
            RecordingSceneEvent(time: 0, scene: RecordingScene(settings: settings))
        ]
    }

    private func pauseRecordingSceneTimeline() {
        guard let recordingTimelineSegmentStartedAt else { return }
        recordingTimelineAccumulatedSeconds += Date().timeIntervalSince(recordingTimelineSegmentStartedAt)
        self.recordingTimelineSegmentStartedAt = nil
    }

    private func resumeRecordingSceneTimeline() {
        guard recordingTimelineSegmentStartedAt == nil else { return }
        recordingTimelineSegmentStartedAt = Date()
    }

    private func resetRecordingSceneTimeline() {
        recordingSceneEvents = []
        recordingTimelineSegmentStartedAt = nil
        recordingTimelineAccumulatedSeconds = 0
    }

    private func appendRecordingSceneEventIfNeeded(_ scene: RecordingScene) {
        guard state == .recording || state == .paused else { return }
        if recordingSceneEvents.last?.scene == scene { return }

        let eventTime = currentRecordingSceneTime()
        let event = RecordingSceneEvent(time: eventTime, scene: scene)
        if let last = recordingSceneEvents.last,
           abs(last.time - eventTime) < 0.05 {
            recordingSceneEvents[recordingSceneEvents.count - 1] = event
        } else {
            recordingSceneEvents.append(event)
        }
    }

    private func currentRecordingSceneTime() -> TimeInterval {
        guard let recordingTimelineSegmentStartedAt else {
            return recordingTimelineAccumulatedSeconds
        }
        return recordingTimelineAccumulatedSeconds + Date().timeIntervalSince(recordingTimelineSegmentStartedAt)
    }

    private func persistSettings() {
        RecordingSettingsStore.save(settings, defaults: defaults)
    }

    private func localCaptureSettings(usesRemoteCamera: Bool) -> RecordingSettings {
        guard usesRemoteCamera else { return settings }
        var localSettings = settings
        localSettings.enabledSources.remove(.camera)
        return localSettings
    }

    var isRemoteCameraSelected: Bool {
        RemoteCameraProviderID.isRemote(settings.selectedCameraID)
    }

    func selectedRemoteCameraName() -> String? {
        guard let selectedServiceID = RemoteCameraProviderID.serviceID(from: settings.selectedCameraID) else {
            return nil
        }
        return remoteCameraServices.first(where: { $0.id == selectedServiceID })?.name
            ?? remoteCameraCapabilities[selectedServiceID]?.deviceName
    }

    func selectedRemoteCameraStatus() -> String? {
        guard let selectedServiceID = RemoteCameraProviderID.serviceID(from: settings.selectedCameraID) else {
            return nil
        }
        if let telemetry = remoteCameraTelemetry[selectedServiceID] {
            if let previewHealth = telemetry.previewHealth,
               previewHealth.framesSent > 0,
               !previewHealth.isHealthy {
                return Self.previewHealthStatus(previewHealth)
            }
            return "\(telemetry.phase.rawValue) · \(Int(telemetry.elapsedSeconds))s"
        }
        if remoteCameraCapabilities[selectedServiceID] != nil {
            return "Ready"
        }
        switch remoteCameraConnectionStates[selectedServiceID] {
        case .pairing:
            return "Connecting"
        case .connected:
            return "Connected"
        case .degraded:
            return "Connection degraded"
        case .disconnected:
            return "Disconnected"
        case .discovering:
            return "Discovered"
        case .unavailable:
            return "Unavailable"
        case nil:
            return "Waiting for monitor preview"
        }
    }

    func selectedRemoteCameraConnectionState() -> RemoteCameraConnectionState? {
        guard let selectedServiceID = RemoteCameraProviderID.serviceID(from: settings.selectedCameraID) else {
            return nil
        }
        return remoteCameraConnectionStates[selectedServiceID]
    }

    func selectedRemoteCameraDeviceDescription() -> String {
        guard let selectedServiceID = RemoteCameraProviderID.serviceID(from: settings.selectedCameraID) else {
            return selectedRemoteCameraName() ?? "No iPhone selected"
        }
        guard let capabilities = remoteCameraCapabilities[selectedServiceID] else {
            return selectedRemoteCameraName() ?? "No iPhone selected"
        }
        if let modelName = Self.iPhoneMarketingName(for: capabilities.deviceModelIdentifier) {
            return "\(capabilities.deviceName) - \(modelName)"
        }
        return capabilities.deviceName
    }

    func selectedRemoteCameraCapabilities() -> RemoteCameraCapabilities? {
        guard let selectedServiceID = RemoteCameraProviderID.serviceID(from: settings.selectedCameraID) else {
            return nil
        }
        return remoteCameraCapabilities[selectedServiceID]
    }

    func selectedRemoteCameraTelemetry() -> RemoteCameraTelemetry? {
        guard let selectedServiceID = RemoteCameraProviderID.serviceID(from: settings.selectedCameraID) else {
            return nil
        }
        guard var telemetry = remoteCameraTelemetry[selectedServiceID] else {
            return nil
        }
        if let savedSettings = settings.remoteCameraSettingsByServiceID[selectedServiceID] {
            telemetry.activeSettings = normalizedRemoteCameraSettings(savedSettings, for: selectedServiceID)
        }
        return telemetry
    }

    func remoteCameraDeviceSummaries() -> [RemoteCameraDeviceSummary] {
        remoteCameraServices.map { service in
            let capabilities = remoteCameraCapabilities[service.id]
            let telemetry = remoteCameraTelemetry[service.id]
            let state = remoteCameraConnectionStates[service.id]
            let cameraID = RemoteCameraProviderID.make(for: service.id)
            let isSelected = settings.selectedCameraID == cameraID
            let isTrusted = settings.trustedRemoteCameraServiceIDs.contains(service.id)
            let modelName = Self.iPhoneMarketingName(for: capabilities?.deviceModelIdentifier)
            let status: String
            if let telemetry {
                if let previewHealth = telemetry.previewHealth,
                   previewHealth.framesSent > 0,
                   !previewHealth.isHealthy {
                    status = Self.previewHealthStatus(previewHealth)
                } else {
                    status = telemetry.phase.rawValue.capitalized
                }
            } else {
                switch state {
                case .pairing:
                    status = "Pairing"
                case .connected:
                    status = capabilities == nil ? "Loading controls" : "Ready"
                case .degraded:
                    status = "Connection issue"
                case .disconnected:
                    status = "Disconnected"
                case .discovering:
                    status = "Found"
                case .unavailable:
                    status = "Unavailable"
                case nil:
                    status = isTrusted ? "Known iPhone" : "Needs pairing"
                }
            }

            let detail: String
            if let modelName {
                detail = modelName
            } else if capabilities != nil {
                detail = "iPhone camera"
            } else if isTrusted {
                detail = "Trusted BlitzRecorder Camera"
            } else {
                detail = "BlitzRecorder Camera app"
            }

            return RemoteCameraDeviceSummary(
                id: service.id,
                cameraID: cameraID,
                name: capabilities?.deviceName ?? service.name,
                detail: detail,
                status: status,
                isSelected: isSelected,
                isReady: capabilities != nil,
                isTrusted: isTrusted,
                lensCount: capabilities?.supportedLenses.count
            )
        }
    }

    func setRemoteCameraLens(_ lens: RemoteCameraLens) {
        applyRemoteCameraSettingsOverride { settings in
            settings.lens = lens
            settings.zoomFactor = 1
        }
    }

    func setRemoteCameraZoom(_ zoomFactor: Double) {
        applyRemoteCameraSettingsOverride { settings in
            settings.zoomFactor = min(15, max(1, zoomFactor))
        }
    }

    func setRemoteCameraTorchEnabled(_ enabled: Bool) {
        applyRemoteCameraSettingsOverride { settings in
            settings.torchEnabled = enabled
        }
    }

    func setRemoteCameraFormat(id: String?, frameRate: Int) {
        applyRemoteCameraSettingsOverride { settings in
            settings.formatID = id
            settings.frameRate = frameRate
        }
    }

    func setRemoteCameraCaptureProfile(_ profileID: RemoteCameraCaptureProfileID) {
        applyRemoteCameraSettingsOverride { settings in
            settings.captureProfileID = profileID
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
        remoteCameraServices.map { service in
            return SourceOption(
                id: RemoteCameraProviderID.make(for: service.id),
                name: remoteCameraCapabilities[service.id]?.deviceName ?? service.name
            )
        }
    }

    private func startRemoteCameraDiscovery() {
        remoteCameraControlClient.onStateChanged = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self,
                      let serviceID = RemoteCameraProviderID.serviceID(from: self.settings.selectedCameraID) else {
                    return
                }
                self.remoteCameraConnectionStates[serviceID] = state
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
                let previousServiceIDs = Set(self.remoteCameraServices.map(\.id))
                self.remoteCameraServices = services
                if let selectedServiceID = RemoteCameraProviderID.serviceID(from: self.settings.selectedCameraID),
                   services.contains(where: { $0.id == selectedServiceID }) {
                    let wasRediscovered = !previousServiceIDs.contains(selectedServiceID)
                    self.connectRemoteCamera(serviceID: selectedServiceID, forceReconnect: wasRediscovered)
                }
                self.onCameraConfigurationChanged?()
            }
        }
        remoteCameraBrowser.start()
    }

    private func connectRemoteCamera(serviceID: String, forceReconnect: Bool = false) {
        guard let service = remoteCameraServices.first(where: { $0.id == serviceID }) else {
            remoteCameraConnectionStates[serviceID] = .discovering
            return
        }
        remoteCameraConnectionStates[serviceID] = .pairing
        if forceReconnect || remoteCameraControlClient.connectedServiceID != serviceID {
            remoteCameraSettingsRestoreSentForServiceIDs.remove(serviceID)
        }
        remoteCameraControlClient.connect(to: service, forceReconnect: forceReconnect)
    }

    private func scheduleRemoteCameraReconnect(serviceID: String) {
        guard settings.selectedCameraID == RemoteCameraProviderID.make(for: serviceID),
              remoteCameraReconnectTasks[serviceID] == nil,
              remoteCameraServices.contains(where: { $0.id == serviceID }) else {
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
                self.connectRemoteCamera(serviceID: serviceID)
            }
        }
    }

    private func requireRemoteCameraConnection() throws {
        guard let selectedServiceID = RemoteCameraProviderID.serviceID(from: settings.selectedCameraID),
              remoteCameraConnectionStates[selectedServiceID] == .connected else {
            throw RecorderError.remoteCameraNotConnected
        }
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
        let activeTelemetry = remoteCameraTelemetry[selectedServiceID]
        return normalizedRemoteCameraSettings(
            settings.remoteCameraSettingsByServiceID[selectedServiceID]
                ?? activeTelemetry?.activeSettings
                ?? RemoteCameraSettings(),
            for: selectedServiceID
        )
    }

    private static func previewHealthStatus(_ health: RemoteCameraPreviewHealth) -> String {
        if let lastFrameAgeSeconds = health.lastFrameAgeSeconds, lastFrameAgeSeconds >= 2 {
            return "Preview feed stale"
        }
        return "Preview dropping frames - \(Int((health.droppedFrameRatio * 100).rounded()))% drop"
    }

    private func updateRemoteCameraTelemetry(for selectedServiceID: String, activeSettings: RemoteCameraSettings) {
        remoteCameraTelemetry[selectedServiceID] = RemoteCameraTelemetry(
            phase: remoteCameraTelemetry[selectedServiceID]?.phase ?? .idle,
            elapsedSeconds: remoteCameraTelemetry[selectedServiceID]?.elapsedSeconds ?? 0,
            batteryLevel: remoteCameraTelemetry[selectedServiceID]?.batteryLevel,
            thermalState: remoteCameraTelemetry[selectedServiceID]?.thermalState ?? "unknown",
            storageFreeBytes: remoteCameraTelemetry[selectedServiceID]?.storageFreeBytes,
            activeSettings: activeSettings,
            transferProgress: remoteCameraTelemetry[selectedServiceID]?.transferProgress,
            previewHealth: remoteCameraTelemetry[selectedServiceID]?.previewHealth
        )
    }

    private func normalizedRemoteCameraSettings(
        _ proposedSettings: RemoteCameraSettings,
        for selectedServiceID: String
    ) -> RemoteCameraSettings {
        let capabilities = remoteCameraCapabilities[selectedServiceID]
        var remoteSettings = proposedSettings
        let supportedLenses = capabilities?.supportedLenses ?? []
        let lens = remoteSettings.lens
        let supportedProfiles = capabilities?.supportedCaptureProfiles ?? [
            RemoteCameraCaptureProfile(id: .automatic)
        ]
        if !supportedProfiles.contains(where: { $0.id == remoteSettings.captureProfileID && $0.isAvailable }) {
            remoteSettings.captureProfileID = .automatic
        }
        let selectableFormats = Self.remoteCameraFormats(
            capabilities?.supportedFormats ?? [],
            supportedBy: remoteSettings.captureProfileID,
            profiles: supportedProfiles
        )
        let formatCandidates = selectableFormats.isEmpty ? (capabilities?.supportedFormats ?? []) : selectableFormats
        let format = formatCandidates.first { format in
            format.id == remoteSettings.formatID && format.frameRates.contains(remoteSettings.frameRate)
        } ?? formatCandidates.first { format in
            format.frameRates.contains(settings.framesPerSecond)
        } ?? formatCandidates.first
        remoteSettings.lens = supportedLenses.contains(lens) ? lens : (supportedLenses.first ?? .wide)
        remoteSettings.formatID = format?.id
        remoteSettings.frameRate = format?.frameRates.contains(remoteSettings.frameRate) == true
            ? remoteSettings.frameRate
            : (format?.frameRates.contains(settings.framesPerSecond) == true
                ? settings.framesPerSecond
                : (format?.frameRates.first ?? settings.framesPerSecond))
        let minimumZoom = capabilities?.minimumZoomFactor ?? 1
        let maximumZoom = max(minimumZoom, capabilities?.maximumZoomFactor ?? 1)
        remoteSettings.zoomFactor = min(maximumZoom, max(minimumZoom, remoteSettings.zoomFactor))
        remoteSettings.focusPosition = min(1, max(0, remoteSettings.focusPosition))
        if let capabilities {
            if !capabilities.supportsTorch {
                remoteSettings.torchEnabled = false
            }
            if remoteSettings.focusMode == .locked, !capabilities.supportsFocusLock {
                remoteSettings.focusMode = .continuousAuto
            }
            if remoteSettings.focusMode == .manual, !capabilities.supportsManualFocus {
                remoteSettings.focusMode = .continuousAuto
            }
            if remoteSettings.exposureMode == .locked, !capabilities.supportsExposureLock {
                remoteSettings.exposureMode = .continuousAuto
            }
            if remoteSettings.exposureMode == .manual, !capabilities.supportsManualExposure {
                remoteSettings.exposureMode = .continuousAuto
                remoteSettings.iso = nil
                remoteSettings.shutterDurationSeconds = nil
            }
            if remoteSettings.whiteBalanceMode == .locked, !capabilities.supportsWhiteBalanceLock {
                remoteSettings.whiteBalanceMode = .continuousAuto
            }
            if remoteSettings.whiteBalanceMode == .manual, !capabilities.supportsManualWhiteBalance {
                remoteSettings.whiteBalanceMode = .continuousAuto
            }
            if remoteSettings.exposureMode == .continuousAuto {
                remoteSettings.exposureBias = 0
            } else if capabilities.minimumExposureBias < capabilities.maximumExposureBias {
                remoteSettings.exposureBias = min(
                    capabilities.maximumExposureBias,
                    max(capabilities.minimumExposureBias, remoteSettings.exposureBias)
                )
            }
            if let minimumISO = capabilities.minimumISO,
               let maximumISO = capabilities.maximumISO,
               let iso = remoteSettings.iso {
                remoteSettings.iso = min(maximumISO, max(minimumISO, iso))
            }
            if let minimumShutter = capabilities.minimumShutterDurationSeconds,
               let maximumShutter = capabilities.maximumShutterDurationSeconds,
               let shutterDuration = remoteSettings.shutterDurationSeconds {
                remoteSettings.shutterDurationSeconds = min(maximumShutter, max(minimumShutter, shutterDuration))
            }
            if !capabilities.supportedStabilizationModes.contains(remoteSettings.stabilizationMode) {
                remoteSettings.stabilizationMode = capabilities.supportedStabilizationModes.first ?? .off
            }
            if !capabilities.supportedRotationDegrees.contains(remoteSettings.rotationDegrees) {
                remoteSettings.rotationDegrees = capabilities.supportedRotationDegrees.first ?? 0
            }
        }
        return remoteSettings
    }

    private static func remoteCameraFormats(
        _ formats: [RemoteCameraFormat],
        supportedBy profileID: RemoteCameraCaptureProfileID,
        profiles: [RemoteCameraCaptureProfile]
    ) -> [RemoteCameraFormat] {
        guard let profile = profiles.first(where: { $0.id == profileID }),
              !profile.supportedFormatIDs.isEmpty else {
            return formats
        }
        let supportedIDs = Set(profile.supportedFormatIDs)
        return formats.filter { supportedIDs.contains($0.id) }
    }

    private static func remoteCameraAspectRatio(width: Int, height: Int, rotationDegrees: Int) -> CGFloat {
        let width = CGFloat(max(1, width))
        let height = CGFloat(max(1, height))
        let landscapeAspectRatio = max(width, height) / min(width, height)
        switch RemoteCameraSettings.normalizedRotationDegrees(rotationDegrees) {
        case 0, 180:
            return 1 / landscapeAspectRatio
        default:
            return landscapeAspectRatio
        }
    }

    private func prepareRemoteCamera(takeID: UUID, hostStartTime: UInt64) async throws -> UInt64 {
        try await withCheckedThrowingContinuation { continuation in
            replaceRemoteCameraSyncContinuation(
                takeID: takeID,
                phase: .prepare,
                continuation: continuation
            )
            scheduleRemoteCameraSyncTimeout(takeID: takeID, phase: .prepare)
            remoteCameraControlClient.send(.prepare(RemoteCameraTimeline(
                takeID: takeID,
                hostStartTime: hostStartTime
            )))
        }
    }

    private func startRemoteCamera(takeID: UUID, hostStartTime: UInt64) async throws -> UInt64 {
        try await withCheckedThrowingContinuation { continuation in
            replaceRemoteCameraSyncContinuation(
                takeID: takeID,
                phase: .start,
                continuation: continuation
            )
            scheduleRemoteCameraSyncTimeout(takeID: takeID, phase: .start)
            remoteCameraControlClient.send(.start(RemoteCameraTimeline(
                takeID: takeID,
                hostStartTime: hostStartTime
            )))
        }
    }

    private func replaceRemoteCameraSyncContinuation(
        takeID: UUID,
        phase: RemoteCameraSyncPhase,
        continuation: CheckedContinuation<UInt64, Error>
    ) {
        failRemoteCameraSync(takeID: takeID, phase: phase, reason: "Superseded by a newer sync request.")
        switch phase {
        case .prepare:
            remoteCameraPrepareContinuations[takeID] = continuation
        case .start:
            remoteCameraStartContinuations[takeID] = continuation
        }
    }

    private func scheduleRemoteCameraSyncTimeout(takeID: UUID, phase: RemoteCameraSyncPhase) {
        let key = RemoteCameraSyncKey(takeID: takeID, phase: phase)
        remoteCameraSyncTimeoutTasks[key]?.cancel()
        remoteCameraSyncTimeoutTasks[key] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return }
                self.failRemoteCameraSync(
                    takeID: takeID,
                    phase: phase,
                    reason: phase.timeoutMessage
                )
            }
        }
    }

    private func resolveRemoteCameraSync(takeID: UUID, phase: RemoteCameraSyncPhase, deviceTime: UInt64) {
        let key = RemoteCameraSyncKey(takeID: takeID, phase: phase)
        remoteCameraSyncTimeoutTasks.removeValue(forKey: key)?.cancel()
        switch phase {
        case .prepare:
            remoteCameraPrepareContinuations.removeValue(forKey: takeID)?.resume(returning: deviceTime)
        case .start:
            remoteCameraStartContinuations.removeValue(forKey: takeID)?.resume(returning: deviceTime)
        }
    }

    private func failRemoteCameraSync(takeID: UUID, phase: RemoteCameraSyncPhase, reason: String) {
        let key = RemoteCameraSyncKey(takeID: takeID, phase: phase)
        remoteCameraSyncTimeoutTasks.removeValue(forKey: key)?.cancel()
        let error = RecorderError.remoteCameraSynchronizationFailed(reason)
        switch phase {
        case .prepare:
            remoteCameraPrepareContinuations.removeValue(forKey: takeID)?.resume(throwing: error)
        case .start:
            remoteCameraStartContinuations.removeValue(forKey: takeID)?.resume(throwing: error)
        }
    }

    private func stopRemoteCameraAndImport(take: RecordingTake) async throws -> MediaWriterCompletion {
        guard let takeID = activeRemoteCameraTakeID else {
            throw RecorderError.remoteCameraTransferFailed("Missing active remote take.")
        }
        return try await withCheckedThrowingContinuation { continuation in
            remoteCameraTransferContinuations[takeID] = continuation
            onMessage?("Stopping iPhone recording...")
            remoteCameraControlClient.send(.stop(RemoteCameraTimeline(
                takeID: takeID,
                hostStopTime: DispatchTime.now().uptimeNanoseconds
            )))
            let resumeOffset = beginRemoteCameraTransfer(
                takeID: takeID,
                destinationURL: take.cameraURL,
                expectedByteCount: 0,
                expectedSHA256: nil
            )
            if resumeOffset > 0 {
                onMessage?("iPhone media download will resume when the recording is ready.")
            }
        }
    }

    @discardableResult
    private func beginRemoteCameraTransfer(
        takeID: UUID,
        destinationURL: URL,
        expectedByteCount: Int64,
        expectedSHA256: String?
    ) -> Int64 {
        do {
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let partialURL = destinationURL.appendingPathExtension("partial")
            if !FileManager.default.fileExists(atPath: partialURL.path) {
                FileManager.default.createFile(atPath: partialURL.path, contents: nil)
            }
            let resumeOffset = (try? FileManager.default
                .attributesOfItem(atPath: partialURL.path)[.size] as? NSNumber)?
                .int64Value ?? 0
            let handle = try FileHandle(forWritingTo: partialURL)
            try handle.seek(toOffset: UInt64(resumeOffset))
            pendingRemoteCameraTransfers[takeID] = RemoteCameraTransferSession(
                destinationURL: destinationURL,
                partialURL: partialURL,
                fileHandle: handle,
                expectedByteCount: expectedByteCount,
                expectedSHA256: expectedSHA256,
                manifest: nil,
                receivedByteCount: resumeOffset
            )
            scheduleRemoteCameraTransferTimeout(
                takeID: takeID,
                reason: "Timed out waiting for iPhone recording transfer."
            )
            onMessage?(resumeOffset > 0
                ? "Resuming iPhone media download..."
                : "Downloading iPhone media...")
            return resumeOffset
        } catch {
            finishRemoteCameraTransfer(takeID: takeID, result: .failure(error))
            return 0
        }
    }

    private func writeRemoteCameraChunk(takeID: UUID, offset: Int64, data: Data, isFinal: Bool) {
        guard var transfer = pendingRemoteCameraTransfers[takeID] else {
            finishRemoteCameraTransfer(takeID: takeID, result: .failure(RecorderError.remoteCameraTransferFailed("Transfer was not initialized.")))
            return
        }
        do {
            guard offset == transfer.receivedByteCount else {
                if offset < transfer.receivedByteCount {
                    remoteCameraControlClient.send(.transferAck(
                        takeID: takeID,
                        receivedByteCount: transfer.receivedByteCount
                    ))
                    return
                }
                throw RecorderError.remoteCameraTransferFailed(
                    "Expected chunk at offset \(transfer.receivedByteCount), received \(offset)."
                )
            }
            try transfer.fileHandle.seek(toOffset: UInt64(offset))
            try transfer.fileHandle.write(contentsOf: data)
            transfer.receivedByteCount = max(transfer.receivedByteCount, offset + Int64(data.count))
            pendingRemoteCameraTransfers[takeID] = transfer
            remoteCameraControlClient.send(.transferAck(
                takeID: takeID,
                receivedByteCount: transfer.receivedByteCount
            ))
            scheduleRemoteCameraTransferTimeout(
                takeID: takeID,
                reason: "Timed out while receiving iPhone recording data."
            )
            _ = isFinal
        } catch {
            finishRemoteCameraTransfer(takeID: takeID, result: .failure(error))
        }
    }

    private func scheduleRemoteCameraTransferTimeout(takeID: UUID, reason: String) {
        remoteCameraTransferTimeoutTasks.removeValue(forKey: takeID)?.cancel()
        remoteCameraTransferTimeoutTasks[takeID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return }
                self.remoteCameraTransferTimeoutTasks.removeValue(forKey: takeID)
                guard self.pendingRemoteCameraTransfers[takeID] != nil
                    || self.remoteCameraTransferContinuations[takeID] != nil else {
                    return
                }
                self.finishRemoteCameraTransfer(
                    takeID: takeID,
                    result: .failure(RecorderError.remoteCameraTransferFailed(reason))
                )
            }
        }
    }

    private func finishRemoteCameraTransfer(takeID: UUID, result: Result<MediaWriterCompletion, Error>) {
        remoteCameraTransferTimeoutTasks.removeValue(forKey: takeID)?.cancel()
        if var transfer = pendingRemoteCameraTransfers.removeValue(forKey: takeID) {
            try? transfer.fileHandle.close()
            transfer.receivedByteCount = 0
        }
        activeRemoteCameraTakeID = nil
        guard let continuation = remoteCameraTransferContinuations.removeValue(forKey: takeID) else {
            return
        }
        switch result {
        case .success(let completion):
            continuation.resume(returning: completion)
        case .failure(let error):
            remoteCameraControlClient.send(.cancel)
            continuation.resume(throwing: error)
        }
    }

    private func finishCompletedRemoteCameraTransfer(
        takeID: UUID,
        transfer: RemoteCameraTransferSession,
        byteCount: Int64,
        sha256: String?
    ) {
        remoteCameraTransferTimeoutTasks.removeValue(forKey: takeID)?.cancel()
        do {
            try transfer.fileHandle.synchronize()
            try transfer.fileHandle.close()
            pendingRemoteCameraTransfers.removeValue(forKey: takeID)
            let importedByteCount = (try FileManager.default
                .attributesOfItem(atPath: transfer.partialURL.path)[.size] as? NSNumber)?
                .int64Value ?? 0
            guard importedByteCount == byteCount else {
                throw RecorderError.remoteCameraTransferFailed("Expected \(byteCount) bytes, imported \(importedByteCount).")
            }
            if let sha256 {
                let importedSHA256 = try sha256HexDigest(for: transfer.partialURL)
                guard importedSHA256 == sha256 else {
                    throw RecorderError.remoteCameraTransferFailed("Checksum mismatch.")
                }
            }
            if FileManager.default.fileExists(atPath: transfer.destinationURL.path) {
                try FileManager.default.removeItem(at: transfer.destinationURL)
            }
            try FileManager.default.moveItem(at: transfer.partialURL, to: transfer.destinationURL)
            try writeRemoteCameraTransferManifest(transfer.manifest, destinationURL: transfer.destinationURL, sha256: sha256)
            remoteCameraPendingImportStore.remove(takeID: takeID, settings: settings)
            remoteCameraControlClient.send(.transferAck(takeID: takeID, receivedByteCount: byteCount))
            activeRemoteCameraTakeID = nil
            guard let continuation = remoteCameraTransferContinuations.removeValue(forKey: takeID) else {
                onMessage?("Recovered Remote iPhone camera import: \(transfer.destinationURL.path)")
                return
            }
            continuation.resume(returning: .wrote(transfer.destinationURL))
        } catch {
            pendingRemoteCameraTransfers.removeValue(forKey: takeID)
            activeRemoteCameraTakeID = nil
            if let continuation = remoteCameraTransferContinuations.removeValue(forKey: takeID) {
                continuation.resume(throwing: error)
            }
        }
    }

    private func sha256HexDigest(for url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            guard !data.isEmpty else { break }
            hasher.update(data: data)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func writeRemoteCameraTransferManifest(
        _ manifest: RemoteCameraTransferManifest?,
        destinationURL: URL,
        sha256: String?
    ) throws {
        guard var manifest else { return }
        manifest.sha256 = sha256 ?? manifest.sha256
        let sidecarURL = destinationURL
            .deletingPathExtension()
            .appendingPathExtension("remote-camera-manifest.json")
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: sidecarURL, options: [.atomic])
    }

    private func handleRemoteCameraEvent(_ event: RemoteCameraEvent) {
        guard let serviceID = RemoteCameraProviderID.serviceID(from: settings.selectedCameraID) else {
            return
        }
        switch event {
        case .pairingChallenge(let challenge):
            remoteCameraConnectionStates[serviceID] = .pairing
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
            remoteCameraConnectionStates[serviceID] = .connected
            onMessage?("Paired \(trust.deviceName) as Remote iPhone Camera.")
            remoteCameraControlClient.send(.requestCapabilities)
            attemptPendingRemoteCameraImports(serviceID: serviceID)
            onCameraConfigurationChanged?()
        case .capabilities(let capabilities):
            remoteCameraCapabilities[serviceID] = capabilities
            remoteCameraConnectionStates[serviceID] = .connected
            onMessage?("Remote iPhone ready: \(capabilities.supportedLenses.map(\.displayName).joined(separator: ", "))")
            if settings.selectedCameraID == RemoteCameraProviderID.make(for: serviceID),
               settings.selectedScenePreset?.supports(settings.layout) == true {
                refreshSelectedScenePresetLayoutIfNeeded()
                persistSettings()
            }
            if settings.remoteCameraSettingsByServiceID[serviceID] != nil,
               !remoteCameraSettingsRestoreSentForServiceIDs.contains(serviceID) {
                let remoteSettings = remoteCameraSettings(for: serviceID)
                updateRemoteCameraTelemetry(for: serviceID, activeSettings: remoteSettings)
                remoteCameraSettingsRestoreSentForServiceIDs.insert(serviceID)
                remoteCameraControlClient.send(.applySettings(remoteSettings))
            }
            attemptPendingRemoteCameraImports(serviceID: serviceID)
            onCameraConfigurationChanged?()
        case .telemetry(let telemetry):
            remoteCameraTelemetry[serviceID] = telemetry
            onCameraConfigurationChanged?()
        case .failed(let failedTakeID, let reason):
            remoteCameraConnectionStates[serviceID] = .degraded
            onMessage?("Remote iPhone error: \(reason)")
            if let syncTakeID = failedTakeID ?? activeRemoteCameraTakeID {
                failRemoteCameraSync(takeID: syncTakeID, phase: .prepare, reason: reason)
                failRemoteCameraSync(takeID: syncTakeID, phase: .start, reason: reason)
            }
            if let takeID = activeRemoteCameraTakeID,
               pendingRemoteCameraTransfers[takeID] != nil || remoteCameraTransferContinuations[takeID] != nil {
                finishRemoteCameraTransfer(takeID: takeID, result: .failure(RecorderError.remoteCameraTransferFailed(reason)))
            }
        case .transferReady(let takeID, _, let byteCount, let manifest):
            if var transfer = pendingRemoteCameraTransfers[takeID] {
                if transfer.receivedByteCount > byteCount {
                    try? transfer.fileHandle.truncate(atOffset: 0)
                    try? transfer.fileHandle.seek(toOffset: 0)
                    transfer.receivedByteCount = 0
                }
                pendingRemoteCameraTransfers[takeID] = RemoteCameraTransferSession(
                    destinationURL: transfer.destinationURL,
                    partialURL: transfer.partialURL,
                    fileHandle: transfer.fileHandle,
                    expectedByteCount: byteCount,
                    expectedSHA256: transfer.expectedSHA256,
                    manifest: manifest,
                    receivedByteCount: transfer.receivedByteCount
                )
                remoteCameraPendingImportStore.updateExpectedByteCount(
                    takeID: takeID,
                    expectedByteCount: byteCount,
                    settings: settings
                )
                scheduleRemoteCameraTransferTimeout(
                    takeID: takeID,
                    reason: "Timed out while receiving iPhone recording data."
                )
                let size = ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
                onMessage?("Downloading iPhone media (\(size))...")
                remoteCameraControlClient.send(.requestTransfer(takeID: takeID, resumeOffset: transfer.receivedByteCount))
            }
            onCameraConfigurationChanged?()
        case .monitorFrame(let jpegData, _, _):
            if let image = Self.makeCGImage(fromJPEGData: jpegData) {
                onRemoteCameraPreviewFrame?(image)
            }
        case .monitorVideoFrame(let frame):
            if let sampleBuffer = remoteCameraMonitorSampleBufferFactory.makeSampleBuffer(from: frame) {
                onRemoteCameraPreviewSampleBuffer?(sampleBuffer, frame.width, frame.height)
            }
        case .transferChunk(let takeID, let offset, let data, let isFinal):
            writeRemoteCameraChunk(takeID: takeID, offset: offset, data: data, isFinal: isFinal)
            onCameraConfigurationChanged?()
        case .transferComplete(let takeID, let byteCount, let sha256):
            if let transfer = pendingRemoteCameraTransfers[takeID] {
                finishCompletedRemoteCameraTransfer(
                    takeID: takeID,
                    transfer: transfer,
                    byteCount: byteCount,
                    sha256: sha256
                )
            }
            onCameraConfigurationChanged?()
        case .prepared(let takeID, let deviceStartTime):
            resolveRemoteCameraSync(takeID: takeID, phase: .prepare, deviceTime: deviceStartTime)
            onCameraConfigurationChanged?()
        case .started(let takeID, let deviceStartTime):
            resolveRemoteCameraSync(takeID: takeID, phase: .start, deviceTime: deviceStartTime)
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
        for pendingImport in remoteCameraPendingImportStore.all(settings: settings) {
            guard pendingImport.serviceID == nil || pendingImport.serviceID == serviceID else { continue }
            guard pendingRemoteCameraTransfers[pendingImport.takeID] == nil else { continue }
            let resumeOffset = beginRemoteCameraTransfer(
                takeID: pendingImport.takeID,
                destinationURL: pendingImport.destinationURL,
                expectedByteCount: pendingImport.expectedByteCount ?? 0,
                expectedSHA256: nil
            )
            remoteCameraControlClient.send(.requestTransfer(takeID: pendingImport.takeID, resumeOffset: resumeOffset))
        }
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
