import BlitzRecorderCore
import BlitzRecorderTransport
import AVFoundation
import CryptoKit
import Foundation
import Network
import Observation
import Security
import UIKit

struct CameraPendingRecording: Identifiable, Equatable {
    let id: String
    let takeID: UUID?
    let url: URL
    let fileName: String
    let createdAtLabel: String
    let byteCount: Int64
    let byteCountLabel: String
}

@Observable
@MainActor
final class CameraCompanionStore {
    let camera = CameraCaptureController()

    var connectionState: RemoteCameraConnectionState = .discovering
    var pairedMacName: String?
    var recordingPhase: RemoteCameraRecordingPhase = .idle
    var activeSettings = RemoteCameraSettings()
    var statusMessage = "Waiting for Mac pairing"
    var elapsedSeconds: Int = 0
    var freeStorageLabel = "Checking storage"
    var thermalStateLabel = "Nominal"
    var listeningPortLabel = "..."
    var pairingCode = CameraCompanionStore.makePairingCode()
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
    var transferProgressLabel = "Idle"
    var previewHealthLabel = "Waiting"
    var hasCompletedPairing: Bool {
        isPairedWithMac
    }
    var isLiveCameraPreviewEnabled: Bool {
        !isScreenshotMode && isPairedWithMac
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
            return "Discovery is unavailable"
        case .degraded:
            return "Network is waiting"
        case .disconnected:
            return "Mac disconnected"
        case .discovering:
            return "Waiting for Mac"
        case .pairing:
            return "Pairing with Mac"
        case .connected:
            return "Connected"
        }
    }
    var connectionIssueRecovery: String {
        switch connectionState {
        case .unavailable:
            return "Retry discovery, keep both devices on the same Wi-Fi, and make sure Local Network access is allowed."
        case .degraded:
            return "Retry after Wi-Fi stabilizes, or connect the Mac using the port shown here."
        case .disconnected:
            return "Open BlitzRecorder on the Mac and select this iPhone again."
        case .discovering:
            return "Open BlitzRecorder on the Mac and choose this iPhone as the camera."
        case .pairing:
            return "Enter the pairing code on the Mac."
        case .connected:
            return "Ready for Mac control."
        }
    }
    var diagnosticsText: String {
        [
            "Status: \(connectionTitle)",
            "Message: \(statusMessage)",
            "Listening port: \(listeningPortLabel)",
            "Pairing code: \(pairingCode)",
            "Keep awake: \(UIApplication.shared.isIdleTimerDisabled ? "enabled" : "disabled")",
            "Preview: \(camera.isPreviewRunning ? "running" : "not running")",
            "Pending imports: \(pendingRecordingCount)",
            "Storage free: \(freeStorageLabel)",
            "Thermal: \(thermalStateLabel)"
        ].joined(separator: "\n")
    }

    private var timer: Timer?
    private var keepAwakeTimer: Timer?
    private var advertiser: BonjourServiceAdvertiser?
    private var controlConnection: JSONFrameConnection?
    private var activeTakeID: UUID?
    private var activeRecordingURL: URL?
    private var lastRecordingResult: CameraRecordingResult?
    private var activeHostStartTime: UInt64?
    private var activeHostStopTime: UInt64?
    private var activeDeviceStartTime: UInt64?
    private var activeDeviceStopTime: UInt64?
    private var activeStopReason: String?
    private var activeTransferProgress: RemoteCameraTransferProgress?
    private var previewFramesSent: Int64 = 0
    private var previewFramesDropped: Int64 = 0
    private var previewFrameSendInFlight = false
    private var lastPreviewFrameSentAt: Date?
    private let isScreenshotMode: Bool
    private let defaults = UserDefaults.standard
    private let trustedMacStore = RemoteCameraTrustedMacStore()
    private let deviceID: UUID
    private var isPairedWithMac = false
    private var pairingState: RemoteCameraPairingState = .waitingForHello
    private var recordingStateMachine = RemoteCameraRecordingStateMachine()
    private var activeTransferTask: Task<Void, Never>?
    private var transferAckContinuations: [UUID: CheckedContinuation<Int64, Error>] = [:]
    private var discoveryRetryTask: Task<Void, Never>?

    private enum Key {
        static let deviceID = "remoteCamera.deviceID"
        static let keepsRecordingsAfterMacImport = "remoteCamera.keepsRecordingsAfterMacImport"
    }

    init() {
        isScreenshotMode = ProcessInfo.processInfo.environment["BLITZRECORDER_CAMERA_SCREENSHOT_MODE"] == "1"
            || ProcessInfo.processInfo.arguments.contains("--blitzrecorder-camera-screenshot-mode")
        deviceID = Self.loadDeviceID(defaults: UserDefaults.standard)
        keepsRecordingsAfterMacImport = UserDefaults.standard.bool(forKey: Key.keepsRecordingsAfterMacImport)
    }

    var connectionTitle: String {
        switch connectionState {
        case .discovering: return "Discoverable"
        case .pairing: return "Pairing"
        case .connected: return pairedMacName.map { "Connected to \($0)" } ?? "Connected"
        case .degraded: return "Connection degraded"
        case .disconnected: return "Disconnected"
        case .unavailable: return "Unavailable"
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

        setKeepsDeviceAwake(true)
        UIDevice.current.isBatteryMonitoringEnabled = true
        refreshDeviceState()
        await camera.configure()
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
                self?.recordPreviewFrameDropped()
            }
        }
        camera.onRecordingFinishedUnexpectedly = { [weak self] result in
            Task { @MainActor in
                self?.handleUnexpectedRecordingFinish(result)
            }
        }
        if let capabilities = camera.capabilities {
            availableLenses = capabilities.supportedLenses.isEmpty ? [.wide] : capabilities.supportedLenses
            if !availableLenses.contains(activeSettings.lens), let firstLens = availableLenses.first {
                activeSettings.lens = firstLens
            }
        }
        refreshPendingRecordings()
        startAdvertising()
        if camera.isPreviewRunning {
            statusMessage = pendingRecordingCount > 0
                ? "\(pendingRecordingCount) pending recording\(pendingRecordingCount == 1 ? "" : "s") ready for Mac import"
                : "Waiting for Mac pairing"
        } else {
            statusMessage = camera.statusMessage
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

    private func startKeepAwakeHeartbeat() {
        guard keepAwakeTimer == nil else { return }
        keepAwakeTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            Task { @MainActor in
                UIApplication.shared.isIdleTimerDisabled = true
            }
        }
    }

    private func configureForScreenshotMode() {
        refreshDeviceState()
        connectionState = .discovering
        recordingPhase = .idle
        pairedMacName = nil
        elapsedSeconds = 0
        availableLenses = [.wide]
        activeSettings = RemoteCameraSettings(lens: .wide, zoomFactor: 1)
        pendingRecordings = []
        pendingRecordingCount = 0
        pendingRecordingsByteCountLabel = "0 KB"
        transferProgressLabel = "Idle"
        previewHealthLabel = "Waiting"
        listeningPortLabel = "Ready"
        thermalStateLabel = "Nominal"
        statusMessage = "Waiting for Mac pairing"
    }

    func stopFromPhone() {
        guard recordingPhase == .recording else { return }
        recordingPhase = .stopping
        statusMessage = "Stopping on iPhone"
        Task {
            do {
                let result = try await camera.stopRecording()
                finishRecording(result: result)
            } catch {
                finishRecording(error: error)
            }
        }
    }

    func setLens(_ lens: RemoteCameraLens) {
        guard availableLenses.contains(lens) else {
            statusMessage = "\(lens.displayName) unavailable on this iPhone"
            return
        }
        activeSettings.lens = lens
        activeSettings.zoomFactor = 1
        Task {
            await camera.setLens(lens)
            activeSettings.zoomFactor = Double(camera.setZoomFactor(1))
            if let capabilities = camera.capabilities {
                availableLenses = capabilities.supportedLenses.isEmpty ? availableLenses : capabilities.supportedLenses
            }
            sendTelemetry()
        }
    }

    func setZoom(_ zoomFactor: Double) {
        activeSettings.zoomFactor = Double(camera.setZoomFactor(CGFloat(zoomFactor)))
        sendTelemetry()
    }

    func retryPendingImport(_ recording: CameraPendingRecording) {
        guard let takeID = recording.takeID else {
            statusMessage = "This pending recording has no recoverable take ID."
            return
        }
        guard isPairedWithMac else {
            statusMessage = "Reconnect BlitzRecorder before retrying import."
            return
        }

        activeTakeID = takeID
        activeRecordingURL = recording.url
        statusMessage = "Retrying Mac import for \(recording.fileName)"
        announceTransferReady(takeID: takeID)
        sendTelemetry()
    }

    func deletePendingRecording(_ recording: CameraPendingRecording) {
        guard recording.url != activeRecordingURL else {
            statusMessage = "Cannot delete the active recording."
            return
        }
        camera.removeRecording(at: recording.url)
        refreshPendingRecordings()
        refreshDeviceState()
        statusMessage = "Deleted pending recording."
        sendTelemetry()
    }

    func deleteAllPendingRecordings() {
        let removableRecordings = pendingRecordings.filter { $0.url != activeRecordingURL }
        for recording in removableRecordings {
            camera.removeRecording(at: recording.url)
        }
        refreshPendingRecordings()
        refreshDeviceState()
        statusMessage = removableRecordings.isEmpty
            ? "No stored recordings to delete."
            : "Deleted \(removableRecordings.count) stored recording\(removableRecordings.count == 1 ? "" : "s")."
        sendTelemetry()
    }

    func retryConnection() {
        guard !isScreenshotMode else { return }
        discoveryRetryTask?.cancel()
        discoveryRetryTask = nil
        cancelActiveTransfer(reason: "Retrying connection.", notifyMac: false)
        controlConnection?.cancel()
        controlConnection = nil
        isPairedWithMac = false
        pairedMacName = nil
        pairingState = .waitingForHello
        pairingCode = Self.makePairingCode()
        listeningPortLabel = "Starting"
        connectionState = .discovering
        statusMessage = "Restarting discovery"
        startAdvertising()
    }

    private func refreshDeviceState() {
        let thermalState = ProcessInfo.processInfo.thermalState
        thermalStateLabel = String(describing: thermalState).replacingOccurrences(of: "NSProcessInfoThermalState", with: "")

        if let freeBytes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())[.systemFreeSize] as? NSNumber {
            freeStorageLabel = ByteCountFormatter.string(fromByteCount: freeBytes.int64Value, countStyle: .file)
        }
    }

    private func refreshPendingRecordings() {
        pendingRecordings = camera.pendingRecordingURLs().map(Self.makePendingRecording)
        pendingRecordingCount = pendingRecordings.count
        let totalBytes = pendingRecordings.reduce(Int64(0)) { partialResult, recording in
            partialResult + recording.byteCount
        }
        pendingRecordingsByteCountLabel = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
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

    private func startAdvertising() {
        let previousAdvertiser = advertiser
        advertiser = nil
        previousAdvertiser?.stop()

        let newAdvertiser = BonjourServiceAdvertiser(
            serviceName: UIDevice.current.name,
            serviceType: RemoteCameraConstants.bonjourServiceType
        )
        advertiser = newAdvertiser
        newAdvertiser.onStateChanged = { [weak self, weak newAdvertiser] state in
            Task { @MainActor in
                guard let self, let newAdvertiser, self.advertiser === newAdvertiser else { return }
                switch state {
                case .ready:
                    self.discoveryRetryTask?.cancel()
                    self.discoveryRetryTask = nil
                    self.connectionState = .discovering
                    if self.camera.isPreviewRunning {
                        self.statusMessage = "Waiting for Mac pairing"
                    }
                case .waiting(let message):
                    self.connectionState = .degraded
                    self.statusMessage = "Network waiting: \(message)"
                    self.scheduleDiscoveryRetry(reason: "Network waiting.")
                case .failed(let message):
                    self.connectionState = .unavailable
                    self.statusMessage = "Discovery failed: \(message)"
                    self.scheduleDiscoveryRetry(reason: "Discovery failed.")
                case .cancelled:
                    self.connectionState = .disconnected
                    self.scheduleDiscoveryRetry(reason: "Discovery stopped.")
                case .idle:
                    break
                }
            }
        }
        newAdvertiser.onConnectionReceived = { [weak self, weak newAdvertiser] connection in
            Task { @MainActor in
                guard let self, let newAdvertiser, self.advertiser === newAdvertiser else { return }
                self.acceptMacConnection(connection)
            }
        }
        newAdvertiser.onListeningPortChanged = { [weak self, weak newAdvertiser] port in
            Task { @MainActor in
                guard let self, let newAdvertiser, self.advertiser === newAdvertiser else { return }
                self.listeningPortLabel = "\(port)"
            }
        }
        do {
            try newAdvertiser.start()
        } catch {
            if advertiser === newAdvertiser {
                advertiser = nil
            }
            connectionState = .unavailable
            statusMessage = "Discovery failed: \(error.localizedDescription)"
            scheduleDiscoveryRetry(reason: "Discovery could not start.")
        }
    }

    private func scheduleDiscoveryRetry(reason: String) {
        guard !isScreenshotMode,
              !isPairedWithMac,
              discoveryRetryTask == nil else {
            return
        }
        statusMessage = "\(reason) Retrying automatically..."
        discoveryRetryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled, !self.isPairedWithMac else { return }
                self.discoveryRetryTask = nil
                self.retryConnection()
            }
        }
    }

    private func acceptMacConnection(_ connection: NWConnection) {
        discoveryRetryTask?.cancel()
        discoveryRetryTask = nil
        let framedConnection = JSONFrameConnection(connection: connection)
        controlConnection?.cancel()
        controlConnection = framedConnection
        cancelActiveTransfer(reason: "Mac connection replaced.")
        isPairedWithMac = false
        pairingState = .waitingForHello
        connectionState = .pairing
        statusMessage = "Mac connected. Waiting for pairing."

        framedConnection.onStateChanged = { [weak self, weak framedConnection] state in
            Task { @MainActor in
                guard let self, let framedConnection, self.controlConnection === framedConnection else { return }
                switch state {
                case .ready:
                    self.connectionState = .pairing
                    self.statusMessage = "Mac connected. Waiting for handshake."
                case .waiting(let error):
                    self.connectionState = .degraded
                    self.statusMessage = "Mac connection waiting: \(error.localizedDescription)"
                case .failed(let error):
                    self.connectionState = .disconnected
                    self.statusMessage = "Mac disconnected: \(error.localizedDescription)"
                case .cancelled:
                    self.cancelActiveTransfer(reason: "Mac disconnected.")
                    self.connectionState = .disconnected
                    self.statusMessage = self.recordingPhase == .recording
                        ? "Mac disconnected. Recording continues on iPhone."
                        : "Mac disconnected"
                default:
                    break
                }
            }
        }
        framedConnection.onFrameReceived = { [weak self] data in
            do {
                let command = try JSONMessageCodec.decode(RemoteCameraCommand.self, from: data)
                Task { @MainActor in
                    self?.handle(command)
                }
            } catch {
                Task { @MainActor in
                    self?.statusMessage = "Invalid Mac command: \(error.localizedDescription)"
                }
            }
        }
        framedConnection.onFailed = { [weak self] message in
            Task { @MainActor in
                guard let self else { return }
                self.cancelActiveTransfer(reason: "Control channel closed.")
                self.connectionState = self.recordingPhase == .recording ? .degraded : .disconnected
                self.statusMessage = "Control channel closed: \(message)"
            }
        }
        framedConnection.start()
    }

    private func handle(_ command: RemoteCameraCommand) {
        switch command {
        case .hello(let protocolVersion, let macIdentity):
            guard protocolVersion == RemoteCameraConstants.protocolVersion else {
                send(.failed(takeID: nil, reason: "Unsupported protocol \(protocolVersion)"))
                return
            }
            guard RemoteCameraPairingValidator.isValidIdentity(macIdentity) else {
                send(.failed(takeID: nil, reason: "Mac identity fingerprint did not match its public key."))
                return
            }
            let isTrusted = trustedMacStore.isTrusted(macIdentity)
            let challenge = RemoteCameraPairingChallenge(
                deviceID: deviceID,
                deviceName: UIDevice.current.name,
                shortCode: isTrusted ? "" : pairingCode,
                challengeNonce: Self.makeChallengeNonce(),
                requiresShortCode: !isTrusted
            )
            pairingState = .challenging(macIdentity: macIdentity, challenge: challenge, isTrusted: isTrusted)
            connectionState = .pairing
            statusMessage = isTrusted ? "Verifying trusted Mac" : "Enter this code on your Mac"
            send(.pairingChallenge(challenge))
        case .pair(let shortCode, let macIdentity, let proof):
            guard case .challenging(let expectedIdentity, let challenge, let isTrusted) = pairingState else {
                statusMessage = "Pairing proof arrived without a challenge."
                send(.failed(takeID: nil, reason: "Pairing proof arrived without a challenge."))
                return
            }
            guard expectedIdentity == macIdentity else {
                statusMessage = "Mac identity changed during pairing. Try again."
                send(.failed(takeID: nil, reason: "Mac identity changed during pairing."))
                return
            }
            guard RemoteCameraPairingValidator.isValidIdentity(macIdentity),
                  RemoteCameraPairingValidator.verifyProof(
                    proof,
                    identity: macIdentity,
                    challenge: challenge,
                    protocolVersion: RemoteCameraConstants.protocolVersion
                  ) else {
                statusMessage = "Mac pairing signature was invalid. Try again."
                send(.failed(takeID: nil, reason: "Mac pairing signature was invalid."))
                return
            }
            let code = RemoteCameraPairingCode.normalized(shortCode)
            guard !challenge.requiresShortCode || code == pairingCode else {
                pairingCode = Self.makePairingCode()
                statusMessage = "Pairing code did not match. Try the new code."
                send(.failed(takeID: nil, reason: "Pairing code did not match."))
                return
            }
            if !isTrusted {
                trustedMacStore.trust(macIdentity)
            }
            pairingState = .paired(macIdentity)
            completePairing(status: isTrusted ? "Connected to trusted BlitzRecorder Mac" : "Paired with BlitzRecorder")
        case .requestCapabilities:
            guard isCommandAllowed() else { return }
            sendCapabilities()
        case .applySettings(let settings):
            guard isCommandAllowed() else { return }
            Task {
                await applyRemoteSettings(settings)
                sendTelemetry()
            }
        case .prepare(let timeline):
            guard isCommandAllowed() else { return }
            recordingStateMachine.prepare(timeline)
            activeTakeID = timeline.takeID
            activeRecordingURL = nil
            lastRecordingResult = nil
            activeHostStartTime = timeline.hostStartTime
            activeHostStopTime = nil
            activeDeviceStartTime = nil
            activeDeviceStopTime = nil
            activeStopReason = nil
            activeTransferProgress = nil
            transferProgressLabel = "Idle"
            recordingPhase = .preparing
            statusMessage = "Prepared for Mac take"
            send(.prepared(takeID: timeline.takeID, deviceStartTime: DispatchTime.now().uptimeNanoseconds))
            sendTelemetry()
        case .start(let timeline):
            guard isCommandAllowed() else { return }
            startRecording(timeline: timeline)
        case .stop(let timeline):
            guard isCommandAllowed() else { return }
            stopRecording(timeline: timeline)
        case .requestTransfer(let takeID, let resumeOffset):
            guard isCommandAllowed() else { return }
            sendRecordingFile(takeID: takeID, resumeOffset: resumeOffset)
        case .transferAck(let takeID, let receivedByteCount):
            resolveTransferAck(takeID: takeID, receivedByteCount: receivedByteCount)
        case .cancel:
            cancelActiveTransfer(reason: "Mac cancelled remote camera command")
            activeTakeID = nil
            activeRecordingURL = nil
            lastRecordingResult = nil
            activeStopReason = nil
            recordingStateMachine.cancel()
            statusMessage = "Mac cancelled remote camera command"
            sendTelemetry()
        }
    }

    private func completePairing(status: String) {
        guard let macIdentity = pairingState.pairedIdentity ?? trustedMacStore.trustedIdentity() else {
            statusMessage = "Pairing failed: trusted Mac identity unavailable."
            send(.failed(takeID: nil, reason: "Trusted Mac identity unavailable."))
            return
        }
        isPairedWithMac = true
        discoveryRetryTask?.cancel()
        discoveryRetryTask = nil
        connectionState = .connected
        pairedMacName = "BlitzRecorder Mac"
        statusMessage = status
        send(.paired(RemoteCameraPairingTrust(
            deviceID: deviceID,
            deviceName: UIDevice.current.name,
            publicKeyFingerprint: macIdentity.publicKeyFingerprint
        )))
        sendCapabilities()
        sendTelemetry()
    }

    private func isCommandAllowed() -> Bool {
        guard isPairedWithMac else {
            statusMessage = "Pair with BlitzRecorder before using camera controls."
            send(.failed(takeID: nil, reason: "Remote iPhone Camera is not paired."))
            return false
        }
        return true
    }

    private func applyRemoteSettings(_ settings: RemoteCameraSettings) async {
        activeSettings = await camera.apply(settings: settings)
        if let capabilities = camera.capabilities {
            availableLenses = capabilities.supportedLenses.isEmpty ? availableLenses : capabilities.supportedLenses
        }
        sendCapabilities()
        sendTelemetry()
        statusMessage = "Updated camera settings from Mac"
    }

    private func sendCapabilities() {
        if let capabilities = camera.capabilities {
            send(.capabilities(capabilities))
        } else {
            send(.failed(takeID: nil, reason: "Camera capabilities unavailable"))
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
            previewHealth: previewHealth()
        )))
    }

    private func send(_ event: RemoteCameraEvent) {
        controlConnection?.send(event)
    }

    private func sendMonitorFrame(jpegData: Data, width: Int, height: Int) {
        guard let controlConnection else {
            recordPreviewFrameDropped()
            return
        }
        guard !previewFrameSendInFlight, activeTransferProgress == nil else {
            recordPreviewFrameDropped()
            return
        }

        previewFrameSendInFlight = true
        recordPreviewFrameSent()
        controlConnection.send(RemoteCameraEvent.monitorFrame(jpegData: jpegData, width: width, height: height)) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.previewFrameSendInFlight = false
                if error != nil {
                    self.recordPreviewFrameDropped()
                }
            }
        }
    }

    private func sendMonitorVideoFrame(_ frame: RemoteCameraMonitorVideoFrame) {
        guard let controlConnection else {
            recordPreviewFrameDropped()
            return
        }
        guard !previewFrameSendInFlight, activeTransferProgress == nil else {
            recordPreviewFrameDropped()
            return
        }

        previewFrameSendInFlight = true
        recordPreviewFrameSent()
        controlConnection.send(RemoteCameraEvent.monitorVideoFrame(frame)) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.previewFrameSendInFlight = false
                if error != nil {
                    self.recordPreviewFrameDropped()
                }
            }
        }
    }

    private func startRecording(timeline: RemoteCameraTimeline) {
        activeTakeID = timeline.takeID
        activeHostStartTime = timeline.hostStartTime ?? activeHostStartTime

        do {
            activeRecordingURL = try camera.startRecording(takeID: timeline.takeID)
            activeStopReason = nil
            recordingStateMachine.start(
                timeline,
                recordingURL: activeRecordingURL,
                deviceStartTime: DispatchTime.now().uptimeNanoseconds
            )
            recordingPhase = .recording
            elapsedSeconds = 0
            statusMessage = "Recording for BlitzRecorder"
            startTimer()
            let deviceStartTime = recordingStateMachine.deviceStartTime ?? DispatchTime.now().uptimeNanoseconds
            activeDeviceStartTime = deviceStartTime
            send(.started(takeID: timeline.takeID, deviceStartTime: deviceStartTime))
        } catch {
            recordingPhase = .failed
            statusMessage = "Recording failed: \(error.localizedDescription)"
            send(.failed(takeID: timeline.takeID, reason: error.localizedDescription))
        }
        sendTelemetry()
    }

    private func stopRecording(timeline: RemoteCameraTimeline) {
        guard camera.isRecording else {
            finishRecording(error: nil)
            return
        }

        activeTakeID = timeline.takeID
        activeHostStopTime = timeline.hostStopTime
        recordingStateMachine.stop(timeline)
        recordingPhase = .stopping
        statusMessage = "Stopping iPhone recording"
        Task {
            do {
                let result = try await camera.stopRecording()
                finishRecording(result: result)
            } catch {
                finishRecording(error: error)
            }
        }
        sendTelemetry()
    }

    private func finishRecording(result: CameraRecordingResult) {
        activeRecordingURL = result.url
        lastRecordingResult = result
        activeStopReason = result.stopReason
        recordingStateMachine.finish(recordingURL: result.url, stopReason: result.stopReason)
        finishRecording(error: nil)
    }

    private func handleUnexpectedRecordingFinish(_ result: Result<CameraRecordingResult, Error>) {
        guard recordingPhase == .recording || recordingPhase == .stopping else { return }
        switch result {
        case .success(let recordingResult):
            statusMessage = recordingResult.stopReason.map { "Recording stopped by iPhone: \($0)" }
                ?? "Recording stopped by iPhone"
            finishRecording(result: recordingResult)
        case .failure(let error):
            finishRecording(error: error)
        }
    }

    private func finishRecording(error: Error?) {
        stopTimer()
        guard let takeID = activeTakeID else {
            recordingPhase = .idle
            sendTelemetry()
            return
        }

        if let error {
            recordingPhase = .failed
            statusMessage = "Recording failed: \(error.localizedDescription)"
            send(.failed(takeID: takeID, reason: error.localizedDescription))
            sendTelemetry()
            return
        }

        recordingPhase = .pendingImport
        statusMessage = "Stopped. Recording pending Mac import."
        let deviceStopTime = DispatchTime.now().uptimeNanoseconds
        activeDeviceStopTime = deviceStopTime
        recordingStateMachine.markPendingImport(deviceStopTime: deviceStopTime)
        send(.stopped(
            takeID: takeID,
            deviceStopTime: deviceStopTime,
            durationSeconds: Double(elapsedSeconds),
            reason: activeStopReason
        ))
        announceTransferReady(takeID: takeID)
        sendTelemetry()
    }

    private func announceTransferReady(takeID: UUID) {
        let recordingURL = activeRecordingURL ?? camera.existingRecordingURL(takeID: takeID)
        guard let recordingURL,
              let byteCount = (try? FileManager.default.attributesOfItem(atPath: recordingURL.path)[.size] as? NSNumber)?.int64Value else {
            recordingPhase = .failed
            statusMessage = "Recording file is not ready for transfer"
            send(.failed(takeID: takeID, reason: "Recording file is not ready for transfer."))
            return
        }

        recordingPhase = .pendingImport
        statusMessage = "Recording ready for Mac import"
        activeRecordingURL = recordingURL
        refreshPendingRecordings()
        send(.transferReady(
            takeID: takeID,
            fileName: recordingURL.lastPathComponent,
            byteCount: byteCount,
            manifest: makeTransferManifest(
                takeID: takeID,
                recordingURL: recordingURL,
                byteCount: byteCount,
                sha256: nil,
                resumeOffset: 0
            )
        ))
    }

    private func sendRecordingFile(takeID: UUID, resumeOffset: Int64) {
        cancelActiveTransfer(reason: "Superseded by a newer transfer request.", notifyMac: false)
        let recordingURL = activeRecordingURL ?? camera.existingRecordingURL(takeID: takeID)
        guard let recordingURL else {
            recordingPhase = .failed
            statusMessage = "No recording file to transfer"
            send(.failed(takeID: takeID, reason: "No recording file to transfer."))
            sendTelemetry()
            return
        }

        activeRecordingURL = recordingURL
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: recordingURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        let clampedResumeOffset = min(max(0, resumeOffset), fileSize)
        activeTransferProgress = RemoteCameraTransferProgress(
            takeID: takeID,
            transferredByteCount: clampedResumeOffset,
            expectedByteCount: fileSize
        )
        updateTransferProgressLabel()
        recordingPhase = .transferring
        statusMessage = clampedResumeOffset > 0
            ? "Resuming transfer to Mac"
            : "Transferring recording to Mac"
        recordingStateMachine.transfer(takeID: takeID, recordingURL: recordingURL)
        sendTelemetry()

        activeTransferTask = Task.detached(priority: .userInitiated) { [weak self, recordingURL] in
            do {
                let handle = try FileHandle(forReadingFrom: recordingURL)
                defer { try? handle.close() }

                var hasher = SHA256()
                var offset: Int64 = 0
                while true {
                    try Task.checkCancellation()
                    let data = try handle.read(upToCount: 256 * 1024) ?? Data()
                    guard !data.isEmpty else { break }
                    hasher.update(data: data)
                    let chunkOffset = offset
                    offset += Int64(data.count)
                    guard offset > clampedResumeOffset else {
                        continue
                    }
                    let chunkData: Data
                    let sendOffset: Int64
                    if chunkOffset < clampedResumeOffset {
                        let resumeIndex = Int(clampedResumeOffset - chunkOffset)
                        chunkData = data.subdata(in: resumeIndex..<data.count)
                        sendOffset = clampedResumeOffset
                    } else {
                        chunkData = data
                        sendOffset = chunkOffset
                    }
                    let isFinal = offset >= fileSize
                    try await self?.sendTransferChunkAndWaitForAck(
                        takeID: takeID,
                        offset: sendOffset,
                        data: chunkData,
                        isFinal: isFinal
                    )
                }

                let sha256 = hasher.finalize().map { String(format: "%02x", $0) }.joined()
                await self?.finishTransfer(takeID: takeID, recordingURL: recordingURL, byteCount: fileSize, resumeOffset: clampedResumeOffset, sha256: sha256)
            } catch {
                if Self.isIntentionalTransferCancellation(error) {
                    return
                }
                await self?.failTransfer(takeID: takeID, error: error)
            }
        }
    }

    private func sendTransferChunkAndWaitForAck(takeID: UUID, offset: Int64, data: Data, isFinal: Bool) async throws {
        let transferredByteCount = offset + Int64(data.count)
        let expectedByteCount = activeTransferProgress?.expectedByteCount ?? transferredByteCount
        let acknowledgedByteCount = try await withCheckedThrowingContinuation { continuation in
            transferAckContinuations[takeID]?.resume(throwing: CancellationError())
            transferAckContinuations[takeID] = continuation
            send(.transferChunk(takeID: takeID, offset: offset, data: data, isFinal: isFinal))
        }
        guard acknowledgedByteCount >= transferredByteCount else {
            throw CameraCompanionTransferError.invalidAcknowledgement(
                expected: transferredByteCount,
                received: acknowledgedByteCount
            )
        }
        activeTransferProgress = RemoteCameraTransferProgress(
            takeID: takeID,
            transferredByteCount: min(acknowledgedByteCount, expectedByteCount),
            expectedByteCount: expectedByteCount
        )
        updateTransferProgressLabel()
        if isFinal {
            sendTelemetry()
        }
    }

    private func finishTransfer(takeID: UUID, recordingURL: URL, byteCount: Int64, resumeOffset: Int64, sha256: String) {
        activeTransferProgress = RemoteCameraTransferProgress(
            takeID: takeID,
            transferredByteCount: byteCount,
            expectedByteCount: byteCount
        )
        updateTransferProgressLabel()
        activeRecordingURL = nil
        activeTakeID = nil
        lastRecordingResult = nil
        activeTransferTask = nil
        recordingStateMachine.markTransferComplete()
        refreshPendingRecordings()
        recordingPhase = .pendingImport
        statusMessage = "Transfer complete"
        send(.transferComplete(takeID: takeID, byteCount: byteCount, sha256: sha256))
        sendTelemetry()
    }

    private func failTransfer(takeID: UUID, error: Error) {
        activeTransferTask = nil
        transferAckContinuations.removeValue(forKey: takeID)?.resume(throwing: error)
        recordingStateMachine.fail(error.localizedDescription)
        recordingPhase = .failed
        statusMessage = "Transfer failed: \(error.localizedDescription)"
        send(.failed(takeID: takeID, reason: error.localizedDescription))
        sendTelemetry()
    }

    private func resolveTransferAck(takeID: UUID, receivedByteCount: Int64) {
        if let continuation = transferAckContinuations.removeValue(forKey: takeID) {
            continuation.resume(returning: receivedByteCount)
            return
        }

        guard let progress = activeTransferProgress,
              progress.takeID == takeID,
              receivedByteCount >= progress.expectedByteCount else {
            return
        }
        completeMacImport(takeID: takeID)
    }

    private func completeMacImport(takeID: UUID) {
        if !keepsRecordingsAfterMacImport,
           let recordingURL = camera.existingRecordingURL(takeID: takeID) {
            camera.removeRecording(at: recordingURL)
        }
        activeTransferProgress = nil
        activeRecordingURL = nil
        activeTakeID = nil
        lastRecordingResult = nil
        refreshPendingRecordings()
        recordingPhase = .idle
        transferProgressLabel = "Idle"
        statusMessage = keepsRecordingsAfterMacImport
            ? "Imported by Mac. Original kept on iPhone"
            : pendingRecordingCount > 0
            ? "\(pendingRecordingCount) pending recording\(pendingRecordingCount == 1 ? "" : "s") ready for Mac import"
            : "Imported by Mac"
        sendTelemetry()
    }

    private func cancelActiveTransfer(reason: String, notifyMac: Bool = true) {
        activeTransferTask?.cancel()
        activeTransferTask = nil
        let error = CameraCompanionTransferError.cancelled(reason)
        for (_, continuation) in transferAckContinuations {
            continuation.resume(throwing: error)
        }
        transferAckContinuations.removeAll()
        if notifyMac, let takeID = activeTransferProgress?.takeID {
            send(.failed(takeID: takeID, reason: reason))
        }
    }

    nonisolated private static func isIntentionalTransferCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let transferError = error as? CameraCompanionTransferError,
           case .cancelled = transferError {
            return true
        }
        return false
    }

    private func updateTransferProgressLabel() {
        guard let activeTransferProgress else {
            transferProgressLabel = "Idle"
            return
        }
        transferProgressLabel = "\(Int((activeTransferProgress.fraction * 100).rounded()))%"
    }

    private func recordPreviewFrameSent() {
        previewFramesSent += 1
        lastPreviewFrameSentAt = Date()
        updatePreviewHealthLabel()
    }

    private func recordPreviewFrameDropped() {
        previewFramesDropped += 1
        updatePreviewHealthLabel()
    }

    private func updatePreviewHealthLabel() {
        let health = previewHealth()
        if health.framesSent == 0 {
            previewHealthLabel = "Waiting"
        } else if health.isHealthy {
            previewHealthLabel = "\(health.framesSent) ok"
        } else {
            previewHealthLabel = "\(Int((health.droppedFrameRatio * 100).rounded()))% drop"
        }
    }

    private func previewHealth() -> RemoteCameraPreviewHealth {
        RemoteCameraPreviewHealth(
            framesSent: previewFramesSent,
            framesDropped: previewFramesDropped,
            lastFrameAgeSeconds: lastPreviewFrameSentAt.map { Date().timeIntervalSince($0) }
        )
    }

    private func makeTransferManifest(
        takeID: UUID,
        recordingURL: URL,
        byteCount: Int64,
        sha256: String?,
        resumeOffset: Int64
    ) -> RemoteCameraTransferManifest {
        RemoteCameraTransferManifest(
            takeID: takeID,
            recordingID: takeID,
            fileName: recordingURL.lastPathComponent,
            byteCount: byteCount,
            sha256: sha256,
            durationSeconds: Double(elapsedSeconds),
            resumeOffset: resumeOffset,
            settings: activeSettings,
            format: currentFormat(),
            captureProfileID: camera.captureProfileID,
            captureCodecLabel: camera.captureCodecLabel,
            captureFormatLabel: camera.captureFormatLabel,
            deviceStartTime: activeDeviceStartTime,
            deviceStopTime: activeDeviceStopTime,
            hostStartTime: activeHostStartTime,
            hostStopTime: activeHostStopTime,
            stopReason: activeStopReason
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

    private static func makePairingCode() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }

    private static func makeChallengeNonce() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status == errSecSuccess {
            return Data(bytes)
        }
        return Data((0..<32).map { _ in UInt8.random(in: UInt8.min...UInt8.max) })
    }

    private static func makePendingRecording(url: URL) -> CameraPendingRecording {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
        let fileSize = Int64(values?.fileSize ?? 0)
        let createdAt = values?.creationDate
        return CameraPendingRecording(
            id: url.path,
            takeID: takeID(from: url),
            url: url,
            fileName: url.lastPathComponent,
            createdAtLabel: createdAt.map(Self.shortDateTimeLabel) ?? "Unknown time",
            byteCount: fileSize,
            byteCountLabel: ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
        )
    }

    private static func takeID(from url: URL) -> UUID? {
        let fileName = url.deletingPathExtension().lastPathComponent
        let suffix = "-camera"
        guard fileName.hasSuffix(suffix) else { return nil }
        let uuidString = String(fileName.dropLast(suffix.count))
        return UUID(uuidString: uuidString)
    }

    private static func shortDateTimeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func sha256HexDigest(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func loadDeviceID(defaults: UserDefaults) -> UUID {
        if let value = defaults.string(forKey: Key.deviceID),
           let uuid = UUID(uuidString: value) {
            return uuid
        }
        let uuid = UUID()
        defaults.set(uuid.uuidString, forKey: Key.deviceID)
        return uuid
    }
}

private enum RemoteCameraPairingState: Equatable {
    case waitingForHello
    case challenging(
        macIdentity: RemoteCameraMacIdentity,
        challenge: RemoteCameraPairingChallenge,
        isTrusted: Bool
    )
    case paired(RemoteCameraMacIdentity)

    var pairedIdentity: RemoteCameraMacIdentity? {
        if case .paired(let identity) = self {
            return identity
        }
        return nil
    }
}

private enum RemoteCameraPairingValidator {
    static func isValidIdentity(_ identity: RemoteCameraMacIdentity) -> Bool {
        identity.publicKeyFingerprint == sha256HexDigest(for: identity.publicKeyData)
    }

    static func verifyProof(
        _ proof: RemoteCameraPairingProof,
        identity: RemoteCameraMacIdentity,
        challenge: RemoteCameraPairingChallenge,
        protocolVersion: Int
    ) -> Bool {
        guard proof.challengeNonce == challenge.challengeNonce,
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: identity.publicKeyData) else {
            return false
        }
        let payload = RemoteCameraPairingProofPayload.data(
            protocolVersion: protocolVersion,
            deviceID: challenge.deviceID,
            challengeNonce: challenge.challengeNonce,
            publicKeyFingerprint: identity.publicKeyFingerprint
        )
        return publicKey.isValidSignature(proof.signatureData, for: payload)
    }

    private static func sha256HexDigest(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private final class RemoteCameraTrustedMacStore {
    private let service = "dev.blitzreels.blitzrecorder.camera-companion"
    private let account = "trusted-mac-identity"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func trustedIdentity() -> RemoteCameraMacIdentity? {
        guard let data = loadData(),
              let identity = try? decoder.decode(RemoteCameraMacIdentity.self, from: data),
              RemoteCameraPairingValidator.isValidIdentity(identity) else {
            return nil
        }
        return identity
    }

    func isTrusted(_ identity: RemoteCameraMacIdentity) -> Bool {
        trustedIdentity() == identity
    }

    func trust(_ identity: RemoteCameraMacIdentity) {
        guard RemoteCameraPairingValidator.isValidIdentity(identity),
              let data = try? encoder.encode(identity) else {
            return
        }
        saveData(data)
    }

    private func loadData() -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else {
            return nil
        }
        return item as? Data
    }

    private func saveData(_ data: Data) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)

        var item = query
        item[kSecValueData] = data
        item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}

private struct RemoteCameraRecordingStateMachine {
    private(set) var phase: RemoteCameraRecordingPhase = .idle
    private(set) var takeID: UUID?
    private(set) var recordingURL: URL?
    private(set) var deviceStartTime: UInt64?
    private(set) var deviceStopTime: UInt64?

    mutating func prepare(_ timeline: RemoteCameraTimeline) {
        phase = .preparing
        takeID = timeline.takeID
        recordingURL = nil
        deviceStartTime = nil
        deviceStopTime = nil
    }

    mutating func start(_ timeline: RemoteCameraTimeline, recordingURL: URL?, deviceStartTime: UInt64) {
        phase = .recording
        takeID = timeline.takeID
        self.recordingURL = recordingURL
        self.deviceStartTime = deviceStartTime
        deviceStopTime = nil
    }

    mutating func stop(_ timeline: RemoteCameraTimeline) {
        phase = .stopping
        takeID = timeline.takeID
    }

    mutating func finish(recordingURL: URL, stopReason: String?) {
        phase = .pendingImport
        self.recordingURL = recordingURL
        _ = stopReason
    }

    mutating func markPendingImport(deviceStopTime: UInt64) {
        phase = .pendingImport
        self.deviceStopTime = deviceStopTime
    }

    mutating func transfer(takeID: UUID, recordingURL: URL) {
        phase = .transferring
        self.takeID = takeID
        self.recordingURL = recordingURL
    }

    mutating func markTransferComplete() {
        phase = .pendingImport
    }

    mutating func fail(_ reason: String) {
        phase = .failed
        _ = reason
    }

    mutating func cancel() {
        phase = .idle
        takeID = nil
        recordingURL = nil
        deviceStartTime = nil
        deviceStopTime = nil
    }
}

private enum CameraCompanionTransferError: LocalizedError {
    case invalidAcknowledgement(expected: Int64, received: Int64)
    case cancelled(String)

    var errorDescription: String? {
        switch self {
        case .invalidAcknowledgement(let expected, let received):
            return "Mac acknowledged \(received) bytes, expected at least \(expected)."
        case .cancelled(let reason):
            return reason
        }
    }
}
