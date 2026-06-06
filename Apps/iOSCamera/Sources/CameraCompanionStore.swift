import BlitzRecorderCore
import AVFoundation
import Foundation
import Observation
import UIKit

struct CameraCompanionEnergyPolicy: Equatable {
    var isSceneActive: Bool
    var isPairedWithMac: Bool
    var isCameraRecording: Bool
    var recordingPhase: RemoteCameraRecordingPhase

    var keepsDeviceAwake: Bool {
        isSceneActive && needsHighEnergyMode
    }

    var shouldSuspendCameraSession: Bool {
        !isPairedWithMac && !isCameraRecording && !recordingPhase.needsCameraSession
    }

    private var needsHighEnergyMode: Bool {
        isPairedWithMac || isCameraRecording || recordingPhase.usesActiveDeviceResources
    }
}

private extension RemoteCameraRecordingPhase {
    var usesActiveDeviceResources: Bool {
        switch self {
        case .preparing, .recording, .stopping, .transferring:
            return true
        case .idle, .pendingImport, .failed:
            return false
        }
    }

    var needsCameraSession: Bool {
        switch self {
        case .preparing, .recording, .stopping:
            return true
        case .idle, .transferring, .pendingImport, .failed:
            return false
        }
    }
}

@Observable
@MainActor
final class CameraCompanionStore {
    let camera = CameraCaptureController()

    var connectionState: RemoteCameraConnectionState = .discovering {
        didSet { refreshEnergyPolicy() }
    }
    var pairedMacName: String?
    var recordingPhase: RemoteCameraRecordingPhase = .idle {
        didSet { refreshEnergyPolicy() }
    }
    var activeSettings = RemoteCameraSettings()
    var statusMessage = "Waiting for Mac"
    var elapsedSeconds: Int = 0
    var freeStorageLabel = "Checking space"
    var thermalStateLabel = "Normal"
    var listeningPortLabel = "..."
    var pairingCode = "------"
    var availableLenses: [RemoteCameraLens] = [.wide]
    var pendingRecordingCount = 0
    var pendingRecordings: [CameraPendingRecording] = []
    var pendingRecordingsByteCountLabel = "0 KB"
    var keepsRecordingsAfterMacImport = false {
        didSet {
            guard oldValue != keepsRecordingsAfterMacImport else { return }
            UserDefaults.standard.set(keepsRecordingsAfterMacImport, forKey: Key.keepsRecordingsAfterMacImport)
        }
    }
    var transferProgressLabel = "Ready"
    var previewHealthLabel = "Waiting"
    var hasCompletedPairing: Bool {
        isPairedWithMac
    }
    var isLiveCameraPreviewEnabled: Bool {
        !isScreenshotMode && isPairedWithMac && camera.isPreviewRunning
    }
    /// A bundled face-cam frame shown as the live preview in paired screenshot
    /// variants (connected / recording / transfer); nil otherwise.
    var screenshotPreviewImage: UIImage? { cachedScreenshotPreviewImage }
    /// True when a camera surface fills the screen — the real live preview or
    /// the bundled screenshot preview image used for App Store captures.
    var isCameraSurfaceVisible: Bool {
        isLiveCameraPreviewEnabled || screenshotPreviewImage != nil
    }
    var canRetryConnection: Bool {
        switch connectionState {
        case .degraded, .disconnected, .unavailable:
            return true
        case .discovering, .pairing, .connected:
            return false
        }
    }
    var connectionIssueTitle: String {
        switch connectionState {
        case .unavailable:
            return "Can’t find the Mac"
        case .degraded:
            return "Wi-Fi is weak"
        case .disconnected:
            return "Mac is not connected"
        case .discovering:
            return "Waiting for Mac"
        case .pairing:
            return "Connecting to Mac"
        case .connected:
            return "Connected"
        }
    }
    var connectionIssueRecovery: String {
        switch connectionState {
        case .unavailable:
            return "Put both devices on the same Wi-Fi. Then tap Try again."
        case .degraded:
            return "Move closer to Wi-Fi, then tap Try again."
        case .disconnected:
            return "Open BlitzRecorder on the Mac and select this iPhone again."
        case .discovering:
            return "Open BlitzRecorder on the Mac and choose this iPhone as the camera."
        case .pairing:
            return "Enter the pairing code on the Mac."
        case .connected:
            return "Ready."
        }
    }
    var diagnosticsText: String {
        [
            "Status: \(connectionTitle)",
            "Message: \(statusMessage)",
            "Port: \(listeningPortLabel)",
            "Pairing code: \(pairingCode)",
            "Keep awake: \(UIApplication.shared.isIdleTimerDisabled ? "enabled" : "disabled")",
            "Live view: \(camera.isPreviewRunning ? "on" : "off")",
            "Saved clips: \(pendingRecordingCount)",
            "Free space: \(freeStorageLabel)",
            "Phone temp: \(thermalStateLabel)"
        ].joined(separator: "\n")
    }

    private var timer: Timer?
    private var keepAwakeTimer: Timer?
    private var activeRecordingURL: URL?
    private var activeTransferProgress: RemoteCameraTransferProgress?
    private let isScreenshotMode: Bool
    private let screenshotVariant: String
    @ObservationIgnored private lazy var cachedScreenshotPreviewImage: UIImage? = {
        guard isScreenshotMode,
              ["connected", "recording", "transfer"].contains(screenshotVariant),
              let url = Bundle.main.url(forResource: "ScreenshotPreview", withExtension: "jpg") else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }()
    private var isPairedWithMac = false
    private var settingsApplyTask: Task<Void, Never>?
    private var orientationObserver: NSObjectProtocol?
    private var isSceneActive = true
    @ObservationIgnored private lazy var connectionSession: CompanionConnectionSession = {
        let session = CompanionConnectionSession()
        session.isRecordingOnDisconnect = { [weak self] in
            self?.recordingRuntime.isRecording == true
        }
        session.onSnapshotChanged = { [weak self] snapshot in
            self?.applyConnectionSnapshot(snapshot)
        }
        session.onCommand = { [weak self] command in
            self?.handle(command)
        }
        session.onPairingCompleted = { [weak self] status in
            self?.completePairing(status: status)
        }
        session.onConnectionReplaced = { [weak self] in
            self?.cancelActiveTransfer(reason: "Mac connection replaced.")
        }
        session.onConnectionCancelled = { [weak self] in
            self?.cancelActiveTransfer(reason: "Mac not connected.")
        }
        session.onControlChannelClosed = { [weak self] in
            self?.cancelActiveTransfer(reason: "Mac connection closed.")
        }
        return session
    }()
    @ObservationIgnored private lazy var monitorPreviewPipeline: MonitorPreviewPipeline = {
        let pipeline = MonitorPreviewPipeline()
        pipeline.onHealthChanged = { [weak self] health in
            self?.updatePreviewHealthLabel(health)
        }
        return pipeline
    }()
    @ObservationIgnored private lazy var pendingImportLibrary: CameraPendingImportLibrary = {
        CameraPendingImportLibrary(
            pendingRecordingURLs: { [camera] in
                camera.pendingRecordingURLs()
            },
            removeRecording: { [camera] url in
                camera.removeRecording(at: url)
            }
        )
    }()
    @ObservationIgnored private lazy var recordingRuntime: CameraCompanionRecordingRuntime = {
        let runtime = CameraCompanionRecordingRuntime(
            sendEvent: { [weak self] event in
                self?.send(event)
            },
            requestTelemetry: { [weak self] in
                self?.sendTelemetry()
            },
            elapsedSeconds: { [weak self] in
                self?.elapsedSeconds ?? 0
            },
            waitForSettingsApplication: { [weak self] in
                await self?.settingsApplyTask?.value
            },
            ensureCameraActive: { [weak self] in
                guard let self else { return false }
                return await self.ensureCameraActiveForMac()
            },
            waitForCaptureReadiness: { [weak self] timeoutSeconds in
                guard let self else { return }
                if let timeoutSeconds {
                    await self.camera.waitForCaptureReadiness(timeoutSeconds: timeoutSeconds)
                } else {
                    await self.camera.waitForCaptureReadiness()
                }
            },
            isCameraRecording: { [weak self] in
                self?.camera.isRecording ?? false
            },
            startCameraRecording: { [weak self] takeID in
                guard let self else { throw CameraCompanionRecordingError.cameraUnavailable }
                return try await self.camera.startRecording(takeID: takeID)
            },
            stopCameraRecording: { [weak self] in
                guard let self else { throw CameraCompanionRecordingError.cameraUnavailable }
                return try await self.camera.stopRecording()
            },
            existingRecordingURL: { [weak self] takeID in
                self?.camera.existingRecordingURL(takeID: takeID)
            },
            removeRecording: { [weak self] url in
                self?.camera.removeRecording(at: url)
            },
            refreshPendingRecordings: { [weak self] in
                self?.refreshPendingRecordings()
            },
            keepsRecordingsAfterMacImport: { [weak self] in
                self?.keepsRecordingsAfterMacImport ?? false
            },
            importCompletedStatus: { [weak self] in
                guard let self else { return "Sent to Mac" }
                return self.pendingImportLibrary.importCompletedStatus(pendingCount: self.pendingRecordingCount)
            },
            makeTransferManifest: { [weak self] request in
                guard let self else {
                    return RemoteCameraTransferManifest(
                        takeID: request.takeID,
                        recordingID: request.takeID,
                        fileName: request.recordingURL.lastPathComponent,
                        byteCount: request.byteCount,
                        sha256: request.sha256,
                        durationSeconds: request.durationSeconds,
                        resumeOffset: request.resumeOffset,
                        settings: RemoteCameraSettings()
                    )
                }
                return self.makeTransferManifest(request)
            }
        )
        runtime.onSnapshotChanged = { [weak self] snapshot in
            self?.applyRecordingSnapshot(snapshot)
        }
        runtime.onStartElapsedTimer = { [weak self] in
            self?.startTimer()
        }
        runtime.onStopElapsedTimer = { [weak self] in
            self?.stopTimer()
        }
        runtime.onResetElapsedSeconds = { [weak self] in
            self?.elapsedSeconds = 0
        }
        return runtime
    }()

    private enum Key {
        static let keepsRecordingsAfterMacImport = "remoteCamera.keepsRecordingsAfterMacImport"
    }

    init() {
        isScreenshotMode = ProcessInfo.processInfo.environment["BLITZRECORDER_CAMERA_SCREENSHOT_MODE"] == "1"
            || ProcessInfo.processInfo.arguments.contains("--blitzrecorder-camera-screenshot-mode")
        screenshotVariant = Self.resolveScreenshotVariant()
        keepsRecordingsAfterMacImport = UserDefaults.standard.bool(forKey: Key.keepsRecordingsAfterMacImport)
    }

    var connectionTitle: String {
        switch connectionState {
        case .discovering: return "Ready to connect"
        case .pairing: return "Connecting"
        case .connected: return pairedMacName.map { "Connected to \($0)" } ?? "Connected"
        case .degraded: return "Weak connection"
        case .disconnected: return "Not connected"
        case .unavailable: return "Not available"
        }
    }

    var elapsedLabel: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func start() async {
        if isScreenshotMode {
            configureForScreenshotMode()
            return
        }

        UIDevice.current.isBatteryMonitoringEnabled = true
        startDeviceOrientationMonitoring()
        refreshDeviceState()
        camera.onMonitorFrame = { [weak self] data, width, height in
            Task { @MainActor in
                guard self?.isPairedWithMac == true else { return }
                self?.sendMonitorFrame(jpegData: data, width: width, height: height)
            }
        }
        camera.onMonitorVideoFrame = { [weak self] frame in
            Task { @MainActor in
                guard self?.isPairedWithMac == true else { return }
                self?.sendMonitorVideoFrame(frame)
            }
        }
        camera.onMonitorFrameDropped = { [weak self] in
            Task { @MainActor in
                self?.monitorPreviewPipeline.recordCaptureDroppedFrame()
            }
        }
        camera.onRecordingFinishedUnexpectedly = { [weak self] result in
            Task { @MainActor in
                self?.recordingRuntime.handleUnexpectedRecordingFinish(result)
            }
        }
        refreshPendingRecordings()
        connectionSession.start()
        statusMessage = pendingRecordingCount > 0
            ? pendingImportLibrary.pendingImportStatus(pendingCount: pendingRecordingCount)
            : "Waiting for Mac"
        refreshEnergyPolicy()
    }

    func setSceneActive(_ active: Bool) {
        isSceneActive = active
        refreshEnergyPolicy()
    }

    func setKeepsDeviceAwake(_ enabled: Bool) {
        UIApplication.shared.isIdleTimerDisabled = enabled
        if enabled {
            startKeepAwakeHeartbeat()
        } else {
            keepAwakeTimer?.invalidate()
            keepAwakeTimer = nil
        }
    }

    private func refreshEnergyPolicy() {
        let policy = CameraCompanionEnergyPolicy(
            isSceneActive: isSceneActive,
            isPairedWithMac: isPairedWithMac,
            isCameraRecording: camera.isRecording,
            recordingPhase: recordingPhase
        )
        setKeepsDeviceAwake(policy.keepsDeviceAwake)
        if policy.shouldSuspendCameraSession {
            Task { @MainActor in
                await suspendCameraSessionIfIdle()
            }
        }
    }

    private var shouldSuspendCameraSession: Bool {
        CameraCompanionEnergyPolicy(
            isSceneActive: isSceneActive,
            isPairedWithMac: isPairedWithMac,
            isCameraRecording: camera.isRecording,
            recordingPhase: recordingPhase
        ).shouldSuspendCameraSession
    }

    private func suspendCameraSessionIfIdle() async {
        guard shouldSuspendCameraSession else { return }
        await camera.stopSessionIfIdle()
    }

    private func startKeepAwakeHeartbeat() {
        guard keepAwakeTimer == nil else { return }
        keepAwakeTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            Task { @MainActor in
                UIApplication.shared.isIdleTimerDisabled = true
            }
        }
    }

    /// Resolves the App Store screenshot variant from the launch environment.
    /// `BLITZRECORDER_CAMERA_SCREENSHOT_VARIANT` (set by the capture script) or a
    /// `--blitzrecorder-camera-screenshot-variant=<name>` argument; defaults to pairing.
    private static func resolveScreenshotVariant() -> String {
        let env = ProcessInfo.processInfo.environment
        if let value = env["BLITZRECORDER_CAMERA_SCREENSHOT_VARIANT"], !value.isEmpty {
            return value.lowercased()
        }
        let prefix = "--blitzrecorder-camera-screenshot-variant="
        if let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }) {
            return String(arg.dropFirst(prefix.count)).lowercased()
        }
        return "pairing"
    }

    private func configureForScreenshotMode() {
        refreshDeviceState()
        // Shared, deterministic baseline so captures are reproducible.
        availableLenses = [.wide]
        activeSettings = RemoteCameraSettings(lens: .wide, zoomFactor: 1)
        applyPendingImportSnapshot(.empty)
        previewHealthLabel = "Waiting"
        listeningPortLabel = "Ready"
        thermalStateLabel = "Normal"
        pairingCode = "428913"

        switch screenshotVariant {
        case "connected":
            isPairedWithMac = true
            pairedMacName = "BlitzRecorder"
            connectionState = .connected
            recordingPhase = .idle
            elapsedSeconds = 0
            transferProgressLabel = "Ready"
            statusMessage = "Ready"
        case "recording":
            isPairedWithMac = true
            pairedMacName = "BlitzRecorder"
            connectionState = .connected
            recordingPhase = .recording
            elapsedSeconds = 47
            transferProgressLabel = "Live"
            statusMessage = "Recording for your Mac"
        case "transfer":
            isPairedWithMac = true
            pairedMacName = "BlitzRecorder"
            connectionState = .connected
            recordingPhase = .transferring
            elapsedSeconds = 0
            transferProgressLabel = "Sending 100%"
            statusMessage = "Sending clip to Mac"
        default: // "pairing"
            isPairedWithMac = false
            pairedMacName = nil
            connectionState = .discovering
            recordingPhase = .idle
            elapsedSeconds = 0
            transferProgressLabel = "Ready"
            statusMessage = "Waiting for Mac"
        }
    }

    func stopFromPhone() {
        recordingRuntime.stopFromPhone()
    }

    func setLens(_ lens: RemoteCameraLens) {
        guard availableLenses.contains(lens) else {
            statusMessage = "\(lens.displayName) not available on this iPhone"
            return
        }
        activeSettings.lens = lens
        activeSettings.zoomFactor = 1
        Task {
            guard await ensureCameraActiveForMac() else { return }
            await camera.setLens(lens)
            activeSettings.zoomFactor = Double(await camera.setZoomFactor(1))
            if let capabilities = camera.capabilities {
                availableLenses = capabilities.supportedLenses.isEmpty ? availableLenses : capabilities.supportedLenses
            }
            sendTelemetry()
        }
    }

    func retryPendingImport(_ recording: CameraPendingRecording) {
        switch pendingImportLibrary.retryRequest(for: recording, isPairedWithMac: isPairedWithMac) {
        case .success(let request):
            recordingRuntime.retryPendingImport(
                takeID: request.takeID,
                recordingURL: request.recordingURL,
                fileName: request.fileName
            )
        case .failure(let message):
            statusMessage = message
        }
    }

    func deletePendingRecording(_ recording: CameraPendingRecording) {
        let result = pendingImportLibrary.delete(recording, activeRecordingURL: activeRecordingURL)
        applyPendingImportSnapshot(result.snapshot)
        refreshDeviceState()
        statusMessage = result.statusMessage
        sendTelemetry()
    }

    func deleteAllPendingRecordings() {
        let result = pendingImportLibrary.deleteAll(activeRecordingURL: activeRecordingURL)
        applyPendingImportSnapshot(result.snapshot)
        refreshDeviceState()
        statusMessage = result.statusMessage
        sendTelemetry()
    }

    func retryConnection() {
        guard !isScreenshotMode else { return }
        cancelActiveTransfer(reason: "Retrying connection.", notifyMac: false)
        connectionSession.retry()
    }

    private func refreshDeviceState() {
        let thermalState = ProcessInfo.processInfo.thermalState
        thermalStateLabel = Self.phoneHeatLabel(for: thermalState)

        if let freeBytes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())[.systemFreeSize] as? NSNumber {
            freeStorageLabel = ByteCountFormatter.string(fromByteCount: freeBytes.int64Value, countStyle: .file)
        }
    }

    private static func phoneHeatLabel(for thermalState: ProcessInfo.ThermalState) -> String {
        switch thermalState {
        case .nominal:
            return "Normal"
        case .fair:
            return "Warm"
        case .serious:
            return "Needs a break"
        case .critical:
            return "Needs a break"
        @unknown default:
            return "Unknown"
        }
    }

    private func refreshPendingRecordings() {
        applyPendingImportSnapshot(pendingImportLibrary.refresh())
    }

    private func applyPendingImportSnapshot(_ snapshot: CameraPendingImportSnapshot) {
        pendingRecordings = snapshot.recordings
        pendingRecordingCount = snapshot.count
        pendingRecordingsByteCountLabel = snapshot.byteCountLabel
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.elapsedSeconds += 1
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func applyConnectionSnapshot(_ snapshot: CompanionConnectionSnapshot) {
        connectionState = snapshot.connectionState
        pairedMacName = snapshot.pairedMacName
        if !snapshot.isPairedWithMac,
           pendingRecordingCount > 0,
           snapshot.statusMessage == "Waiting for Mac" {
            statusMessage = pendingImportLibrary.pendingImportStatus(pendingCount: pendingRecordingCount)
        } else {
            statusMessage = snapshot.statusMessage
        }
        listeningPortLabel = snapshot.listeningPortLabel
        pairingCode = snapshot.pairingCode
        isPairedWithMac = snapshot.isPairedWithMac
        refreshEnergyPolicy()
    }

    private func applyRecordingSnapshot(_ snapshot: CameraCompanionRecordingSnapshot) {
        recordingPhase = snapshot.phase
        activeRecordingURL = snapshot.activeRecordingURL
        activeTransferProgress = snapshot.activeTransferProgress
        monitorPreviewPipeline.setTransferActive(snapshot.activeTransferProgress != nil)
        updateTransferProgressLabel()
        statusMessage = snapshot.statusMessage
    }

    private func handle(_ command: RemoteCameraCommand) {
        switch command {
        case .hello, .pair:
            break
        case .requestCapabilities:
            guard isCommandAllowed() else { return }
            sendCapabilities()
        case .applySettings(let settings):
            guard isCommandAllowed() else { return }
            let previousSettingsApplyTask = settingsApplyTask
            settingsApplyTask = Task {
                await previousSettingsApplyTask?.value
                await applyRemoteSettings(settings)
                sendTelemetry()
            }
        case .prepare, .start, .stop, .requestTransfer:
            guard isCommandAllowed() else { return }
            recordingRuntime.handle(command)
        case .transferAck, .cancel:
            recordingRuntime.handle(command)
        }
    }

    private func completePairing(status: String) {
        Task {
            if await ensureCameraActiveForMac() {
                statusMessage = status
                sendCapabilities()
            }
            sendTelemetry()
        }
    }

    private func isCommandAllowed() -> Bool {
        guard isPairedWithMac else {
            statusMessage = "Connect to BlitzRecorder before using camera controls."
            send(.failed(takeID: nil, reason: "Remote iPhone Camera is not paired."))
            return false
        }
        return true
    }

    private func applyRemoteSettings(_ settings: RemoteCameraSettings) async {
        guard await ensureCameraActiveForMac() else {
            send(.failed(takeID: nil, reason: "Camera not available."))
            sendTelemetry()
            return
        }
        activeSettings = await camera.apply(settings: settings)
        if activeSettings.usesAutomaticRotation {
            await applyAutomaticRotationIfNeeded(sendTelemetryWhenChanged: false)
        }
        if let capabilities = camera.capabilities {
            availableLenses = capabilities.supportedLenses.isEmpty ? availableLenses : capabilities.supportedLenses
        }
        sendCapabilities()
        sendTelemetry()
        statusMessage = "Camera updated"
    }

    private func sendCapabilities() {
        if let capabilities = camera.capabilities {
            send(.capabilities(capabilities))
        } else {
            Task {
                if await ensureCameraActiveForMac(), let capabilities = camera.capabilities {
                    send(.capabilities(capabilities))
                } else {
                    send(.failed(takeID: nil, reason: "Camera details not available"))
                }
            }
        }
    }

    @discardableResult
    private func ensureCameraActiveForMac() async -> Bool {
        if camera.isPreviewRunning, camera.capabilities != nil {
            refreshAvailableLenses()
            return true
        }
        statusMessage = "Getting camera ready"
        await camera.configure()
        refreshAvailableLenses()
        if camera.isPreviewRunning, camera.capabilities != nil {
            return true
        }
        statusMessage = camera.statusMessage
        return false
    }

    private func refreshAvailableLenses() {
        guard let capabilities = camera.capabilities else { return }
        availableLenses = capabilities.supportedLenses.isEmpty ? [.wide] : capabilities.supportedLenses
        if !availableLenses.contains(activeSettings.lens), let firstLens = availableLenses.first {
            activeSettings.lens = firstLens
        }
    }

    private func startDeviceOrientationMonitoring() {
        guard orientationObserver == nil else { return }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: UIDevice.current,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.scheduleAutomaticRotationUpdate()
            }
        }
        Task { @MainActor in
            await scheduleAutomaticRotationUpdate()
        }
    }

    private func scheduleAutomaticRotationUpdate() async {
        guard activeSettings.usesAutomaticRotation else { return }
        guard recordingPhase == .idle || recordingPhase == .preparing else { return }
        let previousSettingsApplyTask = settingsApplyTask
        settingsApplyTask = Task {
            await previousSettingsApplyTask?.value
            await applyAutomaticRotationIfNeeded(sendTelemetryWhenChanged: true)
        }
    }

    private func applyAutomaticRotationIfNeeded(sendTelemetryWhenChanged: Bool) async {
        guard activeSettings.usesAutomaticRotation,
              let rotationDegrees = Self.currentDeviceRotationDegrees(),
              activeSettings.rotationDegrees != rotationDegrees else {
            return
        }

        activeSettings.rotationDegrees = rotationDegrees
        if camera.isPreviewRunning {
            activeSettings.rotationDegrees = await camera.setRotationDegrees(rotationDegrees)
        }
        if sendTelemetryWhenChanged {
            sendTelemetry()
        }
    }

    private static func currentDeviceRotationDegrees() -> Int? {
        if let rotation = rotationDegrees(for: UIDevice.current.orientation) {
            return rotation
        }
        return UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.interfaceOrientation }
            .compactMap { Self.rotationDegrees(for: $0) }
            .first
    }

    private static func rotationDegrees(for orientation: UIDeviceOrientation) -> Int? {
        switch orientation {
        case .portrait:
            return 0
        case .portraitUpsideDown:
            return 180
        case .landscapeLeft:
            return 90
        case .landscapeRight:
            return 270
        case .unknown, .faceUp, .faceDown:
            return nil
        @unknown default:
            return nil
        }
    }

    private static func rotationDegrees(for orientation: UIInterfaceOrientation) -> Int? {
        switch orientation {
        case .portrait:
            return 0
        case .portraitUpsideDown:
            return 180
        case .landscapeRight:
            return 90
        case .landscapeLeft:
            return 270
        case .unknown:
            return nil
        @unknown default:
            return nil
        }
    }

    private func sendTelemetry() {
        refreshDeviceState()
        let batteryLevel = UIDevice.current.batteryLevel >= 0 ? Double(UIDevice.current.batteryLevel) : nil
        send(.telemetry(RemoteCameraTelemetry(
            phase: recordingPhase,
            elapsedSeconds: Double(elapsedSeconds),
            batteryLevel: batteryLevel,
            thermalState: thermalStateLabel,
            storageFreeBytes: freeStorageBytes(),
            activeSettings: activeSettings,
            transferProgress: activeTransferProgress,
            previewHealth: monitorPreviewPipeline.health,
            captureWarning: camera.captureWarning
        )))
    }

    private func send(_ event: RemoteCameraEvent) {
        connectionSession.send(event)
    }

    private func sendMonitorFrame(jpegData: Data, width: Int, height: Int) {
        monitorPreviewPipeline.sendJPEGFrame(data: jpegData, width: width, height: height) { [weak self] event, completion in
            self?.connectionSession.send(event, completion: completion) ?? false
        }
    }

    private func sendMonitorVideoFrame(_ frame: RemoteCameraMonitorVideoFrame) {
        monitorPreviewPipeline.sendVideoFrame(frame) { [weak self] event, completion in
            self?.connectionSession.send(event, completion: completion) ?? false
        }
    }

    private func cancelActiveTransfer(reason: String, notifyMac: Bool = true) {
        recordingRuntime.cancelActiveTransfer(reason: reason, notifyMac: notifyMac)
    }

    private func updateTransferProgressLabel() {
        guard let activeTransferProgress else {
            transferProgressLabel = "Ready"
            return
        }
        transferProgressLabel = "\(Int((activeTransferProgress.fraction * 100).rounded()))%"
    }

    private func updatePreviewHealthLabel(_ health: RemoteCameraPreviewHealth) {
        if health.framesSent == 0 {
            previewHealthLabel = "Waiting"
        } else if health.isHealthy {
            previewHealthLabel = "\(health.framesSent) ok"
        } else {
            previewHealthLabel = "\(Int((health.droppedFrameRatio * 100).rounded()))% drop"
        }
    }

    private func makeTransferManifest(_ request: CameraCompanionTransferManifestRequest) -> RemoteCameraTransferManifest {
        RemoteCameraTransferManifest(
            takeID: request.takeID,
            recordingID: request.takeID,
            fileName: request.recordingURL.lastPathComponent,
            byteCount: request.byteCount,
            sha256: request.sha256,
            durationSeconds: request.durationSeconds,
            resumeOffset: request.resumeOffset,
            settings: activeSettings,
            format: currentFormat(),
            captureProfileID: camera.captureProfileID,
            captureCodecLabel: camera.captureCodecLabel,
            captureFormatLabel: camera.captureFormatLabel,
            deviceStartTime: request.deviceStartTime,
            deviceStopTime: request.deviceStopTime,
            hostStartTime: request.hostStartTime,
            hostStopTime: request.hostStopTime,
            hostTimelineStartTime: request.hostTimelineStartTime,
            stopReason: request.stopReason
        )
    }

    private func currentFormat() -> RemoteCameraFormat? {
        guard let capabilities = camera.capabilities else { return nil }
        if let formatID = activeSettings.formatID,
           let format = capabilities.supportedFormats.first(where: { $0.id == formatID }) {
            return format
        }
        return capabilities.supportedFormats.first
    }

    private func freeStorageBytes() -> Int64? {
        guard let freeBytes = try? FileManager.default
            .attributesOfFileSystem(forPath: NSHomeDirectory())[.systemFreeSize] as? NSNumber else {
            return nil
        }
        return freeBytes.int64Value
    }

}
