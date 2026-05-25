import AppKit
import AVFoundation
import BlitzRecorderCore
import Foundation
import Observation

@Observable
@MainActor
final class RecorderViewModel {
    let coordinator: RecorderCoordinator
    let accessController: AccessController

    let previewStage: PreviewStageView
    let micLevels = TrackLevels()
    let sysLevels = TrackLevels()

    var state: RecordingState = .idle
    var settings: RecordingSettings
    var detailMessage: String = ""
    var lastExportedURL: URL?

    var availableDisplays: [SourceOption] = []
    var availableCameras: [SourceOption] = []
    var availableMicrophones: [SourceOption] = []
    var directRemoteCameraHost: String = ""
    var directRemoteCameraPort: String = ""
    let remoteCameraPreviewSurface = CameraPreviewView()
    var hasRemoteCameraPreviewImage = false

    var elapsedSeconds: Int = 0
    var renderProgress: Double = 0
    private var elapsedTimer: Timer?
    private var elapsedAccumulatedSeconds: TimeInterval = 0
    private var currentRecordingSegmentStartedAt: Date?

    var appTab: AppTab = .recorder
    var selectedLayer: SceneLayerKind = .camera
    var isCameraCropModeEnabled = false
    var targetWindowInfo: TargetWindowInfo?
    var targetWindowStatus: String = "Detecting target..."
    var targetWindowFitScale: CGFloat = 1.0

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

    var selectedRemoteCameraCapabilities: RemoteCameraCapabilities? {
        coordinator.selectedRemoteCameraCapabilities()
    }

    var selectedRemoteCameraTelemetry: RemoteCameraTelemetry? {
        coordinator.selectedRemoteCameraTelemetry()
    }

    var selectedRemoteCameraName: String? {
        coordinator.selectedRemoteCameraName()
    }

    var selectedRemoteCameraStatus: String? {
        coordinator.selectedRemoteCameraStatus()
    }

    var selectedRemoteCameraDeviceDescription: String {
        coordinator.selectedRemoteCameraDeviceDescription()
    }

    var selectedRemoteCameraReviewStatus: String {
        guard let health = selectedRemoteCameraTelemetry?.previewHealth,
              health.framesSent > 0 else {
            return "Waiting for review feed"
        }
        if health.isHealthy {
            return "Review feed active"
        }
        if let lastFrameAgeSeconds = health.lastFrameAgeSeconds, lastFrameAgeSeconds >= 2 {
            return "Review feed stale"
        }
        return "Review feed dropping frames"
    }

    var isRemoteCameraSelected: Bool {
        coordinator.isRemoteCameraSelected
    }

    var localCameraOptions: [SourceOption] {
        availableCameras.filter { !RemoteCameraProviderID.isRemote($0.id) }
    }

    var remoteCameraOptions: [SourceOption] {
        availableCameras.filter { RemoteCameraProviderID.isRemote($0.id) }
    }

    var remoteCameraDeviceSummaries: [RemoteCameraDeviceSummary] {
        coordinator.remoteCameraDeviceSummaries()
    }

    var isSelectedLayerEnabled: Bool {
        settings.enabledSources.contains(selectedLayer.source)
    }

    var canEditScene: Bool {
        coordinator.allowsSceneChanges
    }

    var recordingReadiness: RecordingReadiness {
        coordinator.recordingReadiness()
    }

    var permissionStatusRows: [PermissionStatusRow] {
        var rows = CaptureSource.allCases.map { source in
            PermissionStatusRow(
                title: source.rawValue,
                symbol: source.symbolName,
                status: PermissionGate.status(for: source, settings: settings),
                isActive: settings.enabledSources.contains(source),
                isBlocked: recordingReadiness.blockers.contains { $0.source == source },
                source: source
            )
        }
        rows.append(PermissionStatusRow(
            title: "Accessibility",
            symbol: "accessibility",
            status: PermissionGate.accessibilityStatus,
            isActive: true,
            isBlocked: !PermissionGate.hasAccessibilityAccess,
            source: nil
        ))
        return rows
    }

    var permissionIssueCount: Int {
        recordingReadiness.blockers.count
            + (PermissionGate.hasAccessibilityAccess ? 0 : 1)
            + (accessController.canRenderExport ? 0 : 1)
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

        remoteCameraPreviewSurface.setMessage("Waiting for iPhone preview")

        previewStage.onLayerSelected = { [weak self] kind in
            self?.selectedLayer = kind
        }
        previewStage.onSceneLayoutChanged = { [weak self] layout in
            guard let self else { return }
            guard self.canEditScene else {
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
    }

    func applyState(_ newState: RecordingState) {
        let previousState = state
        state = newState
        switch newState {
        case .starting:
            elapsedAccumulatedSeconds = 0
            elapsedSeconds = 0
            renderProgress = 0
            currentRecordingSegmentStartedAt = nil
            lastExportedURL = nil
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
        if message.hasPrefix("Saved: ") {
            let path = String(message.dropFirst("Saved: ".count))
                .components(separatedBy: ". Source take:").first ?? String(message.dropFirst("Saved: ".count))
            lastExportedURL = URL(fileURLWithPath: path)
        }
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
        previewStage.captureLayout = coordinator.settings.layout
        previewStage.sceneLayout = coordinator.settings.sceneLayout
        previewStage.enabledSources = coordinator.settings.enabledSources
        previewStage.screenSourceAspectRatio = coordinator.currentScreenSourceAspectRatio()
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
        if source == .screen, visible {
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

    func setLayout(_ layout: CaptureLayout) {
        coordinator.setLayout(layout)
        syncSettingsAndFitTargetWindowToScene()
    }

    func setScenePreset(_ preset: ScenePreset) {
        coordinator.applyScenePreset(preset)
        syncSettingsAndFitTargetWindowToScene()
    }

    func fitFrontWindowForShorts() {
        coordinator.fitFrontWindowForShorts(scale: targetWindowFitScale)
        syncSettings()
        refreshTargetWindow()
    }

    func fitScreenToAvailableSlot() {
        coordinator.fitScreenToAvailableSlot()
        syncSettingsAndFitTargetWindowToScene()
    }

    func fitScreenItemToFrontWindow() {
        coordinator.fitScreenItemToFrontWindow()
        syncSettings()
        refreshTargetWindow()
    }

    func fitFrontWindowForShorts(scale: CGFloat) {
        targetWindowFitScale = clampedTargetWindowFitScale(scale)
        coordinator.fitFrontWindowForShorts(scale: targetWindowFitScale)
        syncSettings()
        refreshTargetWindow()
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
        syncSettingsAndFitTargetWindowToScene()
    }

    func setSceneLayerOrder(_ order: [SceneLayerKind]) {
        coordinator.setSceneLayerOrder(order)
        syncSettings()
    }

    private func syncSettingsAndFitTargetWindowToScene() {
        syncSettings()
        guard settings.enabledSources.contains(.screen) else { return }
        coordinator.fitFrontWindowForShorts(scale: targetWindowFitScale)
        syncSettings()
        refreshTargetWindow()
    }

    private func clampedTargetWindowFitScale(_ scale: CGFloat) -> CGFloat {
        min(1.25, max(0.75, scale))
    }

    func selectLayer(_ layer: SceneLayerKind) {
        guard settings.enabledSources.contains(layer.source) else { return }
        selectedLayer = layer
        previewStage.selectedLayer = layer
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

    func beginCameraCropMode() {
        selectedLayer = .camera
        previewStage.beginCameraCropEditing()
        isCameraCropModeEnabled = true
    }

    func applyCameraCropMode() {
        previewStage.commitCameraCropEditing()
        isCameraCropModeEnabled = false
    }

    func cancelCameraCropMode() {
        previewStage.cancelCameraCropEditing()
        isCameraCropModeEnabled = false
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
        remoteCameraPreviewSurface.setPreviewImage(image)
        if !hasRemoteCameraPreviewImage {
            hasRemoteCameraPreviewImage = true
        }
    }

    func applyRemoteCameraPreviewSampleBuffer(_ sampleBuffer: CMSampleBuffer, width: Int, height: Int) {
        remoteCameraPreviewSurface.enqueuePreviewSampleBuffer(sampleBuffer, width: width, height: height)
        if !hasRemoteCameraPreviewImage {
            hasRemoteCameraPreviewImage = true
        }
    }

    func clearRemoteCameraPreview(message: String) {
        remoteCameraPreviewSurface.setMessage(message)
        hasRemoteCameraPreviewImage = false
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

    func setRemoteCameraZoom(_ zoomFactor: Double) {
        coordinator.setRemoteCameraZoom(zoomFactor)
        syncSettings()
    }

    func setRemoteCameraTorchEnabled(_ enabled: Bool) {
        coordinator.setRemoteCameraTorchEnabled(enabled)
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
        }
    }

    func requestSourcePermissions() {
        Task {
            await coordinator.requestPermissionsForEnabledSources()
            syncSettings()
            let readiness = coordinator.recordingReadiness()
            detailMessage = readiness.isReady ? "Recording permissions ready." : readiness.detail
        }
    }

    func requestAccessibilityPermission() {
        Task {
            let result = await PermissionGate.requestAccessibilityAccessForWindowControls()
            detailMessage = result.message
        }
    }

    func openAccessibilitySettings() {
        PermissionGate.openAccessibilitySettings()
    }

    func selectScreenCrop() {
        Task {
            do {
                try await coordinator.selectScreenCrop()
                syncSettings()
            } catch {
                detailMessage = "Screen region picker failed: \(error.localizedDescription)"
            }
        }
    }

    func clearScreenCrop() {
        coordinator.clearScreenCrop()
        syncSettings()
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

    func primaryAction() {
        switch state {
        case .idle:
            guard accessController.canRenderExport else {
                detailMessage = "Free exports used. Subscribe for unlimited renders."
                return
            }
            let readiness = coordinator.recordingReadiness()
            guard readiness.isReady else {
                detailMessage = readiness.blockers.first?.sentence ?? readiness.detail
                return
            }
            coordinator.start()
        case .recording, .paused:
            coordinator.stop()
        case .starting, .finishing:
            break
        }
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
            return "Starting"
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
        let x = Int((crop.minX * 100).rounded())
        let y = Int((crop.minY * 100).rounded())
        let width = Int((crop.width * 100).rounded())
        let height = Int((crop.height * 100).rounded())
        return "Crop \(width)% x \(height)% at \(x)%, \(y)%"
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
    let source: CaptureSource?

    var isGranted: Bool {
        ["allowed", "authorized", "remote iPhone", "selected with macOS picker"].contains(status)
    }
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
        case .screenFocus: return "rectangle.inset.filled"
        case .cameraInset: return "pip"
        case .cameraFocus: return "person.crop.rectangle"
        case .webcamFullscreen: return "video.fill"
        }
    }
}
