import BlitzRecorderCore
import AVFoundation
import Foundation
import Observation
import UIKit

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
    var pairingStep = CompanionPairingStep.waitingForMac
    var availableLenses: [RemoteCameraLens] = [.wide]
    var pendingRecordingCount = 0
    var pendingRecordings: [CameraPendingRecording] = []
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
    var hasPairedMac: Bool {
        isPairedWithMac || connectionSession.hasTrustedMac
    }
    /// The preview stays on through a take even if the Mac drops: attaching a new preview layer to the session
    /// mid-take ends the recording.
    var isLiveCameraPreviewEnabled: Bool {
        (isPairedWithMac || isTakeInProgress) && camera.isPreviewRunning
    }
    var isTakeInProgress: Bool {
        switch recordingPhase {
        case .preparing, .recording, .stopping: true
        case .idle, .transferring, .pendingImport, .failed: false
        }
    }
    var transferFraction: Double? {
        activeTransferProgress?.fraction
    }
    private var timer: Timer?
    private var keepAwakeTimer: Timer?
    private var previewHealthTimer: Timer?
    private var activeRecordingURL: URL?
    private var activeTransferProgress: RemoteCameraTransferProgress?
    private var isPairedWithMac = false
    private var settingsApplyTask: Task<Void, Never>?
    private var lastTelemeteredPreviewHealthState: CameraPreviewHealthTelemetryState?
    private var isSceneActive = true
    private var lastTelemetrySentAt = Date.distantPast
    @ObservationIgnored private var backgroundObserver: NSObjectProtocol?
    private var isAsleep = false
    @ObservationIgnored private let automaticRotation = CameraAutomaticRotationMonitor()
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
            self?.previewHealthLabel = CameraDeviceStatus.previewHealthLabel(for: health)
            self?.camera.adaptMonitorPreview(to: health)
            self?.sendPreviewHealthTelemetryIfNeeded(health)
        }
        pipeline.onPublishAvailabilityChanged = { [weak self] canPublish in
            self?.camera.setMonitorPreviewDeliverySuspended(!canPublish)
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
        let runtime = CameraCompanionRecordingRuntime(dependencies: CameraCompanionRecordingDependencies(
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
            currentConfiguration: { [weak self] in
                guard let self else {
                    return CameraCompanionRecordingConfigurationSnapshot(
                        settings: RemoteCameraSettings(),
                        format: nil,
                        captureProfileID: .automatic,
                        captureCodecLabel: nil,
                        captureFormatLabel: nil
                    )
                }
                return self.currentRecordingConfiguration
            },
            startCameraRecording: { [weak self] takeID, expectedSettings in
                guard let self else { throw CameraCompanionRecordingError.cameraUnavailable }
                return try await self.camera.startRecording(
                    takeID: takeID,
                    expectedSettings: expectedSettings
                )
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
                        settings: RemoteCameraSettings(),
                        recordingDiagnostics: request.recordingDiagnostics
                    )
                }
                return self.makeTransferManifest(request)
            }
        ))
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
        keepsRecordingsAfterMacImport = UserDefaults.standard.bool(forKey: Key.keepsRecordingsAfterMacImport)
    }

    func start() async {
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.tellMacGoingToSleep() }
        }
        UIDevice.current.isBatteryMonitoringEnabled = true
        automaticRotation.onOrientationChanged = { [weak self] in
            self?.scheduleAutomaticRotationUpdate()
        }
        automaticRotation.start()
        camera.onLevelRotationChanged = { [weak self] in
            self?.scheduleAutomaticRotationUpdate()
        }
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
        camera.onCaptureWarningChanged = { [weak self] _ in
            self?.sendTelemetry()
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
        if active, isAsleep {
            isAsleep = false
            connectionSession.retry()
        }
        refreshEnergyPolicy()
        refreshPreviewHealthHeartbeat()
    }

    /// Lets the Mac say "iPhone locked" instead of guessing. iOS gives a moment of background time to send it.
    func tellMacGoingToSleep() {
        // A clip on its way to the Mac keeps the connection for as long as iOS allows.
        guard activeTransferProgress == nil else { return }
        isAsleep = true
        guard isPairedWithMac else {
            connectionSession.goDark()
            return
        }
        let task = UIApplication.shared.beginBackgroundTask(withName: "Tell Mac") {}
        connectionSession.send(.goingToSleep) { [weak self] _ in
            Task { @MainActor in
                self?.connectionSession.goDark()
                UIApplication.shared.endBackgroundTask(task)
            }
        }
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

    private var energyPolicy: CameraCompanionEnergyPolicy {
        CameraCompanionEnergyPolicy(
            isSceneActive: isSceneActive,
            isPairedWithMac: isPairedWithMac,
            isCameraRecording: camera.isRecording,
            recordingPhase: recordingPhase
        )
    }

    private func refreshEnergyPolicy() {
        let policy = energyPolicy
        setKeepsDeviceAwake(policy.keepsDeviceAwake)
        if policy.shouldSuspendCameraSession {
            Task { @MainActor in
                await suspendCameraSessionIfIdle()
            }
        }
    }

    private func suspendCameraSessionIfIdle() async {
        guard energyPolicy.shouldSuspendCameraSession else { return }
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

    private func refreshPreviewHealthHeartbeat() {
        guard isPairedWithMac, isSceneActive else {
            stopPreviewHealthHeartbeat()
            return
        }
        startPreviewHealthHeartbeat()
    }

    private func startPreviewHealthHeartbeat() {
        guard previewHealthTimer == nil else { return }
        previewHealthTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.monitorPreviewPipeline.refreshHealth()
            }
        }
    }

    private func stopPreviewHealthHeartbeat() {
        previewHealthTimer?.invalidate()
        previewHealthTimer = nil
        lastTelemeteredPreviewHealthState = nil
    }

    func stopFromPhone() {
        recordingRuntime.stopFromPhone()
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

    func approvePendingMac() {
        connectionSession.approvePendingMac()
    }

    func pairPendingMacWithCode() {
        connectionSession.pairPendingMacWithCode()
    }

    func declinePendingMac() {
        connectionSession.declinePendingMac()
    }

    func retryConnection() {
        cancelActiveTransfer(reason: "Retrying connection.", notifyMac: false)
        connectionSession.retry()
    }

    private func refreshDeviceState() {
        let thermalState = ProcessInfo.processInfo.thermalState
        thermalStateLabel = CameraDeviceStatus.phoneHeatLabel(for: thermalState)

        if let freeBytes = CameraDeviceStatus.freeStorageBytes() {
            freeStorageLabel = ByteCountFormatter.string(fromByteCount: freeBytes, countStyle: .file)
        }
    }

    private func refreshPendingRecordings() {
        applyPendingImportSnapshot(pendingImportLibrary.refresh())
    }

    private func applyPendingImportSnapshot(_ snapshot: CameraPendingImportSnapshot) {
        pendingRecordings = snapshot.recordings
        pendingRecordingCount = snapshot.count
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
        pairingStep = snapshot.pairingStep
        isPairedWithMac = snapshot.isPairedWithMac
        refreshEnergyPolicy()
        refreshPreviewHealthHeartbeat()
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
            enqueueSettingsApplication {
                await self.applyRemoteSettings(settings)
                self.sendTelemetry()
            }
        case .prepare, .start, .stop, .requestTransfer:
            guard isCommandAllowed() else { return }
            recordingRuntime.handle(command)
        case .transferAck, .cancel:
            recordingRuntime.handle(command)
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

    /// A camera restarted while the Mac was away comes back on its defaults; putting the last settings back first
    /// keeps what the Mac is told true, so the Mac can skip re-sending settings it already has.
    private func completePairing(status: String) {
        enqueueSettingsApplication {
            let wasRunning = self.camera.isPreviewRunning && self.camera.capabilities != nil
            if await self.ensureCameraActiveForMac() {
                if !wasRunning, self.recordingPhase == .idle {
                    self.activeSettings = await self.camera.apply(settings: self.activeSettings)
                }
                self.statusMessage = status
                self.sendCapabilities()
            }
            self.sendTelemetry()
        }
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
        } else {
            automaticRotation.setWarning(nil)
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

    private func enqueueSettingsApplication(_ operation: @escaping @MainActor () async -> Void) {
        let previousSettingsApplyTask = settingsApplyTask
        settingsApplyTask = Task {
            await previousSettingsApplyTask?.value
            await operation()
        }
    }

    private func scheduleAutomaticRotationUpdate() {
        guard activeSettings.usesAutomaticRotation else { return }
        guard recordingPhase == .idle || recordingPhase == .preparing else { return }
        enqueueSettingsApplication {
            await self.applyAutomaticRotationIfNeeded(sendTelemetryWhenChanged: true)
        }
    }

    private func applyAutomaticRotationIfNeeded(sendTelemetryWhenChanged: Bool) async {
        guard activeSettings.usesAutomaticRotation else {
            if automaticRotation.setWarning(nil), sendTelemetryWhenChanged {
                sendTelemetry()
            }
            return
        }
        guard let rotationDegrees = camera.levelRotationDegrees
                ?? CameraAutomaticRotationMonitor.currentDeviceRotationDegrees() else {
            if automaticRotation.setWarning("Auto orientation needs the iPhone upright"), sendTelemetryWhenChanged {
                sendTelemetry()
            }
            return
        }

        let didChangeWarning = automaticRotation.setWarning(nil)
        guard activeSettings.rotationDegrees != rotationDegrees else {
            if sendTelemetryWhenChanged, didChangeWarning {
                sendTelemetry()
            }
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

    private var currentCaptureWarning: String? {
        if let captureWarning = camera.captureWarning, !captureWarning.isEmpty {
            return captureWarning
        }
        return automaticRotation.warning
    }

    func focusCinematic(at focusPoint: CameraPreviewFocusPoint, lockFocus: Bool) {
        Task { @MainActor in
            let didApply = await camera.focusCinematic(at: focusPoint, lockFocus: lockFocus)
            if didApply {
                sendTelemetry()
            }
        }
    }

    private func sendTelemetry() {
        lastTelemetrySentAt = Date()
        refreshDeviceState()
        let batteryLevel = UIDevice.current.batteryLevel >= 0 ? Double(UIDevice.current.batteryLevel) : nil
        send(.telemetry(RemoteCameraTelemetry(
            phase: recordingPhase,
            elapsedSeconds: Double(elapsedSeconds),
            batteryLevel: batteryLevel,
            thermalState: thermalStateLabel,
            storageFreeBytes: CameraDeviceStatus.freeStorageBytes(),
            activeSettings: activeSettings,
            transferProgress: activeTransferProgress,
            previewHealth: monitorPreviewPipeline.health,
            captureWarning: currentCaptureWarning
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

    /// Also a heartbeat: the Mac treats an iPhone that has been silent for a few seconds as gone.
    private func sendPreviewHealthTelemetryIfNeeded(_ health: RemoteCameraPreviewHealth) {
        let state = CameraPreviewHealthTelemetryState(health: health)
        let isHeartbeatDue = Date().timeIntervalSince(lastTelemetrySentAt) >= 2
        guard state != lastTelemeteredPreviewHealthState || isHeartbeatDue else { return }
        lastTelemeteredPreviewHealthState = state
        sendTelemetry()
    }

    private func makeTransferManifest(_ request: CameraCompanionTransferManifestRequest) -> RemoteCameraTransferManifest {
        var request = request
        if let captureWarning = currentCaptureWarning {
            var recordingDiagnostics = request.recordingDiagnostics ?? RemoteCameraRecordingDiagnostics()
            recordingDiagnostics.captureWarning = RemoteCameraRecordingWarningAccumulator.mergedWarning(
                recordingDiagnostics.captureWarning,
                captureWarning
            )
            request.recordingDiagnostics = recordingDiagnostics
        }
        return request.manifest(defaults: currentRecordingConfiguration)
    }

    private var currentRecordingConfiguration: CameraCompanionRecordingConfigurationSnapshot {
        CameraCompanionRecordingConfigurationSnapshot(
            settings: activeSettings,
            format: currentFormat(),
            captureProfileID: camera.captureProfileID,
            captureCodecLabel: camera.captureCodecLabel,
            captureFormatLabel: camera.captureFormatLabel
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
}
