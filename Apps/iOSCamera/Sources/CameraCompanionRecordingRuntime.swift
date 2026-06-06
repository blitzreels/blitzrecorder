import BlitzRecorderCore
import Foundation

struct CameraCompanionRecordingSnapshot: Equatable {
    var phase: RemoteCameraRecordingPhase
    var activeRecordingURL: URL?
    var activeTransferProgress: RemoteCameraTransferProgress?
    var statusMessage: String
}

struct CameraCompanionTransferManifestRequest {
    var takeID: UUID
    var recordingURL: URL
    var byteCount: Int64
    var sha256: String?
    var resumeOffset: Int64
    var durationSeconds: Double
    var deviceStartTime: UInt64?
    var deviceStopTime: UInt64?
    var hostStartTime: UInt64?
    var hostStopTime: UInt64?
    var hostTimelineStartTime: UInt64?
    var stopReason: String?
}

@MainActor
final class CameraCompanionRecordingRuntime {
    typealias SendEvent = @MainActor (RemoteCameraEvent) -> Void
    typealias RequestTelemetry = @MainActor () -> Void
    typealias WaitForSettingsApplication = @MainActor () async -> Void
    typealias EnsureCameraActive = @MainActor () async -> Bool
    typealias WaitForCaptureReadiness = @MainActor (_ timeoutSeconds: Double?) async -> Void
    typealias IsCameraRecording = @MainActor () -> Bool
    typealias StartCameraRecording = @MainActor (_ takeID: UUID) async throws -> CameraRecordingStartResult
    typealias StopCameraRecording = @MainActor () async throws -> CameraRecordingResult
    typealias ExistingRecordingURL = @MainActor (_ takeID: UUID) -> URL?
    typealias RemoveRecording = @MainActor (_ url: URL) -> Void
    typealias RefreshPendingRecordings = @MainActor () -> Void
    typealias KeepsRecordingsAfterMacImport = @MainActor () -> Bool
    typealias ImportCompletedStatus = @MainActor () -> String
    typealias MakeTransferManifest = @MainActor (CameraCompanionTransferManifestRequest) -> RemoteCameraTransferManifest

    var onSnapshotChanged: ((CameraCompanionRecordingSnapshot) -> Void)?
    var onStartElapsedTimer: (() -> Void)?
    var onStopElapsedTimer: (() -> Void)?
    var onResetElapsedSeconds: (() -> Void)?

    private var activeTakeID: UUID?
    private var activeRecordingURL: URL?
    private var lastRecordingResult: CameraRecordingResult?
    private var activeHostStartTime: UInt64?
    private var activeHostStopTime: UInt64?
    private var activeHostTimelineStartTime: UInt64?
    private var activeDeviceStartTime: UInt64?
    private var activeDeviceStopTime: UInt64?
    private var activeStopReason: String?
    private var activeRecordingFailureReason: String?
    private var activeTransferProgress: RemoteCameraTransferProgress?
    private var recordingStateMachine = RemoteCameraRecordingStateMachine()
    private var startRecordingTask: Task<Void, Never>?
    private var queuedStopTimeline: RemoteCameraTimeline?
    private var statusMessage = "Ready"

    private let sendEvent: SendEvent
    private let requestTelemetry: RequestTelemetry
    private let elapsedSeconds: () -> Int
    private let waitForSettingsApplication: WaitForSettingsApplication
    private let ensureCameraActive: EnsureCameraActive
    private let waitForCaptureReadiness: WaitForCaptureReadiness
    private let isCameraRecording: IsCameraRecording
    private let startCameraRecording: StartCameraRecording
    private let stopCameraRecording: StopCameraRecording
    private let existingRecordingURL: ExistingRecordingURL
    private let removeRecording: RemoveRecording
    private let refreshPendingRecordings: RefreshPendingRecordings
    private let keepsRecordingsAfterMacImport: KeepsRecordingsAfterMacImport
    private let importCompletedStatus: ImportCompletedStatus
    private let makeTransferManifest: MakeTransferManifest

    private lazy var transferSender: CameraCompanionTransferSender = {
        let sender = CameraCompanionTransferSender { [weak self] event in
            self?.sendEvent(event)
        }
        sender.onProgressChanged = { [weak self] progress in
            self?.setActiveTransferProgress(progress)
        }
        sender.onFinished = { [weak self] takeID, recordingURL, byteCount, resumeOffset, sha256 in
            self?.finishTransfer(
                takeID: takeID,
                recordingURL: recordingURL,
                byteCount: byteCount,
                resumeOffset: resumeOffset,
                sha256: sha256
            )
        }
        sender.onFailed = { [weak self] takeID, error in
            self?.failTransfer(takeID: takeID, error: error)
        }
        return sender
    }()

    init(
        sendEvent: @escaping SendEvent,
        requestTelemetry: @escaping RequestTelemetry,
        elapsedSeconds: @escaping () -> Int,
        waitForSettingsApplication: @escaping WaitForSettingsApplication,
        ensureCameraActive: @escaping EnsureCameraActive,
        waitForCaptureReadiness: @escaping WaitForCaptureReadiness,
        isCameraRecording: @escaping IsCameraRecording,
        startCameraRecording: @escaping StartCameraRecording,
        stopCameraRecording: @escaping StopCameraRecording,
        existingRecordingURL: @escaping ExistingRecordingURL,
        removeRecording: @escaping RemoveRecording,
        refreshPendingRecordings: @escaping RefreshPendingRecordings,
        keepsRecordingsAfterMacImport: @escaping KeepsRecordingsAfterMacImport,
        importCompletedStatus: @escaping ImportCompletedStatus,
        makeTransferManifest: @escaping MakeTransferManifest
    ) {
        self.sendEvent = sendEvent
        self.requestTelemetry = requestTelemetry
        self.elapsedSeconds = elapsedSeconds
        self.waitForSettingsApplication = waitForSettingsApplication
        self.ensureCameraActive = ensureCameraActive
        self.waitForCaptureReadiness = waitForCaptureReadiness
        self.isCameraRecording = isCameraRecording
        self.startCameraRecording = startCameraRecording
        self.stopCameraRecording = stopCameraRecording
        self.existingRecordingURL = existingRecordingURL
        self.removeRecording = removeRecording
        self.refreshPendingRecordings = refreshPendingRecordings
        self.keepsRecordingsAfterMacImport = keepsRecordingsAfterMacImport
        self.importCompletedStatus = importCompletedStatus
        self.makeTransferManifest = makeTransferManifest
    }

    var isRecording: Bool {
        recordingStateMachine.phase == .recording
    }

    func handle(_ command: RemoteCameraCommand) {
        switch command {
        case .prepare(let timeline):
            prepare(timeline)
        case .start(let timeline):
            start(timeline)
        case .stop(let timeline):
            stop(timeline)
        case .requestTransfer(let takeID, let resumeOffset):
            sendRecordingFile(takeID: takeID, resumeOffset: resumeOffset)
        case .transferAck(let takeID, let receivedByteCount):
            resolveTransferAck(takeID: takeID, receivedByteCount: receivedByteCount)
        case .cancel:
            cancelActiveTransfer(reason: "Mac cancelled remote camera command")
            cancelActiveRecording(reason: "Mac cancelled remote camera command")
        case .hello, .pair, .requestCapabilities, .applySettings:
            break
        }
    }

    func stopFromPhone() {
        guard recordingStateMachine.phase == .recording else { return }
        recordingStateMachine.stop(RemoteCameraTimeline(takeID: activeTakeID ?? UUID()))
        statusMessage = "Stopping"
        publish()
        Task {
            do {
                let result = try await stopCameraRecording()
                finishRecording(result: result)
            } catch {
                finishRecording(error: error)
            }
        }
    }

    func retryPendingImport(takeID: UUID, recordingURL: URL, fileName: String) {
        activeTakeID = takeID
        activeRecordingURL = recordingURL
        statusMessage = "Sending again: \(fileName)"
        publish()
        announceTransferReady(takeID: takeID)
        requestTelemetry()
    }

    func handleUnexpectedRecordingFinish(_ result: Result<CameraRecordingResult, Error>) {
        guard recordingStateMachine.phase == .recording || recordingStateMachine.phase == .stopping else { return }
        switch result {
        case .success(let recordingResult):
            statusMessage = recordingResult.stopReason.map { "Recording stopped by iPhone: \($0)" }
                ?? "Recording stopped by iPhone"
            finishRecording(result: recordingResult)
        case .failure(let error):
            finishRecording(error: error)
        }
    }

    func cancelActiveTransfer(reason: String, notifyMac: Bool = true) {
        transferSender.cancel(reason: reason, notifyMac: notifyMac)
        setActiveTransferProgress(nil)
    }

    private func prepare(_ timeline: RemoteCameraTimeline) {
        guard accept(recordingStateMachine.prepareDecision(takeID: timeline.takeID), takeID: timeline.takeID) else {
            return
        }
        recordingStateMachine.prepare(timeline)
        activeTakeID = timeline.takeID
        activeRecordingURL = nil
        lastRecordingResult = nil
        activeHostStartTime = timeline.hostStartTime
        activeHostStopTime = nil
        activeHostTimelineStartTime = timeline.hostTimelineStartTime
        activeDeviceStartTime = nil
        activeDeviceStopTime = nil
        activeStopReason = nil
        activeRecordingFailureReason = nil
        setActiveTransferProgress(nil)
        statusMessage = "Ready for Mac"
        publish()
        prepareRecording(timeline: timeline)
    }

    private func start(_ timeline: RemoteCameraTimeline) {
        guard accept(
            recordingStateMachine.startDecision(
                takeID: timeline.takeID,
                isStartTaskRunning: startRecordingTask != nil
            ),
            takeID: timeline.takeID
        ) else {
            return
        }
        startRecording(timeline: timeline)
    }

    private func stop(_ timeline: RemoteCameraTimeline) {
        guard accept(
            recordingStateMachine.stopDecision(
                takeID: timeline.takeID,
                isStartTaskRunning: startRecordingTask != nil,
                failureReason: activeRecordingFailureReason
            ),
            takeID: timeline.takeID
        ) else {
            return
        }
        stopRecording(timeline: timeline)
    }

    private func accept(_ decision: RemoteCameraRecordingStateMachine.CommandDecision, takeID: UUID?) -> Bool {
        switch decision {
        case .accepted:
            return true
        case .rejected(let reason):
            failCommand(takeID: takeID, reason: reason)
            return false
        }
    }

    private func failCommand(takeID: UUID?, reason: String) {
        statusMessage = reason
        publish()
        sendEvent(.failed(takeID: takeID, reason: reason))
        requestTelemetry()
    }

    private func prepareRecording(timeline: RemoteCameraTimeline) {
        Task {
            await waitForSettingsApplication()
            guard await ensureCameraActive() else {
                failCommand(takeID: timeline.takeID, reason: "Camera not available.")
                return
            }
            await waitForCaptureReadiness(nil)
            guard recordingStateMachine.phase == .preparing, activeTakeID == timeline.takeID else {
                return
            }
            sendEvent(.prepared(takeID: timeline.takeID, deviceStartTime: DispatchTime.now().uptimeNanoseconds))
            requestTelemetry()
        }
    }

    private func startRecording(timeline: RemoteCameraTimeline) {
        activeTakeID = timeline.takeID
        activeHostStartTime = timeline.hostStartTime ?? activeHostStartTime
        activeHostTimelineStartTime = timeline.hostTimelineStartTime ?? activeHostTimelineStartTime

        startRecordingTask = Task {
            do {
                guard await ensureCameraActive() else {
                    throw CameraCompanionRecordingError.cameraUnavailable
                }
                await waitForCaptureReadiness(0.5)
                guard !Task.isCancelled,
                      activeTakeID == timeline.takeID,
                      recordingStateMachine.phase == .preparing || recordingStateMachine.phase == .stopping else {
                    startRecordingTask = nil
                    return
                }

                let recordingStart = try await startCameraRecording(timeline.takeID)
                let recordingURL = recordingStart.url
                guard !Task.isCancelled,
                      activeTakeID == timeline.takeID else {
                    _ = try? await stopCameraRecording()
                    removeRecording(recordingURL)
                    startRecordingTask = nil
                    clearActiveRecordingState()
                    recordingStateMachine.cancel()
                    statusMessage = "Mac stopped the camera"
                    publish()
                    requestTelemetry()
                    return
                }

                activeRecordingURL = recordingURL
                activeStopReason = nil
                let deviceStartTime = recordingStart.deviceStartTime
                recordingStateMachine.start(
                    timeline,
                    recordingURL: activeRecordingURL,
                    deviceStartTime: deviceStartTime
                )
                onResetElapsedSeconds?()
                statusMessage = "Recording for your Mac"
                onStartElapsedTimer?()
                activeDeviceStartTime = deviceStartTime
                publish()
                sendEvent(.started(takeID: timeline.takeID, deviceStartTime: deviceStartTime))
                startRecordingTask = nil
                if let stopTimeline = queuedStopTimeline,
                   stopTimeline.takeID == timeline.takeID {
                    queuedStopTimeline = nil
                    stopRecording(timeline: stopTimeline)
                    return
                }
            } catch {
                startRecordingTask = nil
                queuedStopTimeline = nil
                activeRecordingFailureReason = error.localizedDescription
                recordingStateMachine.fail(error.localizedDescription)
                statusMessage = "Recording failed: \(error.localizedDescription)"
                publish()
                sendEvent(.failed(takeID: timeline.takeID, reason: error.localizedDescription))
            }
            requestTelemetry()
        }
    }

    private func stopRecording(timeline: RemoteCameraTimeline) {
        guard recordingStateMachine.phase != .stopping else {
            requestTelemetry()
            return
        }
        if startRecordingTask != nil, !isCameraRecording() {
            queuedStopTimeline = timeline
            activeTakeID = timeline.takeID
            activeHostStopTime = timeline.hostStopTime
            recordingStateMachine.stop(timeline)
            statusMessage = "Stopping"
            publish()
            requestTelemetry()
            return
        }
        guard isCameraRecording() else {
            finishRecording(error: CameraCompanionRecordingError.notRecording)
            return
        }

        activeTakeID = timeline.takeID
        activeHostStopTime = timeline.hostStopTime
        recordingStateMachine.stop(timeline)
        statusMessage = "Stopping"
        publish()
        Task {
            do {
                let result = try await stopCameraRecording()
                finishRecording(result: result)
            } catch {
                finishRecording(error: error)
            }
        }
        requestTelemetry()
    }

    private func cancelActiveRecording(reason: String) {
        startRecordingTask?.cancel()
        queuedStopTimeline = nil
        let startTask = startRecordingTask
        let cancelledTakeID = activeTakeID

        guard startTask != nil || isCameraRecording() else {
            clearActiveRecordingState()
            recordingStateMachine.cancel()
            statusMessage = reason
            publish()
            requestTelemetry()
            return
        }

        recordingStateMachine.stop(RemoteCameraTimeline(takeID: activeTakeID ?? UUID()))
        statusMessage = reason
        onStopElapsedTimer?()
        publish()
        requestTelemetry()

        Task {
            if let startTask {
                await startTask.value
            } else if isCameraRecording() {
                if let result = try? await stopCameraRecording() {
                    removeRecording(result.url)
                }
            }

            guard cancelledTakeID == nil || activeTakeID == nil || activeTakeID == cancelledTakeID else {
                return
            }
            startRecordingTask = nil
            clearActiveRecordingState()
            recordingStateMachine.cancel()
            statusMessage = reason
            publish()
            requestTelemetry()
        }
    }

    private func clearActiveRecordingState() {
        activeTakeID = nil
        activeRecordingURL = nil
        lastRecordingResult = nil
        activeHostStartTime = nil
        activeHostStopTime = nil
        activeHostTimelineStartTime = nil
        activeDeviceStartTime = nil
        activeDeviceStopTime = nil
        activeStopReason = nil
        activeRecordingFailureReason = nil
    }

    private func finishRecording(result: CameraRecordingResult) {
        activeRecordingURL = result.url
        lastRecordingResult = result
        activeStopReason = result.stopReason
        recordingStateMachine.finish(recordingURL: result.url, stopReason: result.stopReason)
        finishRecording(error: nil)
    }

    private func finishRecording(error: Error?) {
        onStopElapsedTimer?()
        guard let takeID = activeTakeID else {
            recordingStateMachine.cancel()
            publish()
            requestTelemetry()
            return
        }

        if let error {
            activeRecordingFailureReason = error.localizedDescription
            recordingStateMachine.fail(error.localizedDescription)
            statusMessage = "Recording failed: \(error.localizedDescription)"
            publish()
            sendEvent(.failed(takeID: takeID, reason: error.localizedDescription))
            requestTelemetry()
            return
        }

        statusMessage = "Saved. Ready to send."
        let deviceStopTime = DispatchTime.now().uptimeNanoseconds
        activeDeviceStopTime = deviceStopTime
        recordingStateMachine.markPendingImport(deviceStopTime: deviceStopTime)
        publish()
        sendEvent(.stopped(
            takeID: takeID,
            deviceStopTime: deviceStopTime,
            durationSeconds: Double(elapsedSeconds()),
            reason: activeStopReason
        ))
        announceTransferReady(takeID: takeID)
        requestTelemetry()
    }

    private func announceTransferReady(takeID: UUID) {
        let recordingURL = activeRecordingURL ?? existingRecordingURL(takeID)
        guard let recordingURL,
              let byteCount = Self.fileSize(at: recordingURL) else {
            recordingStateMachine.fail("Clip is still saving.")
            statusMessage = "Clip is still saving"
            publish()
            sendEvent(.failed(takeID: takeID, reason: "Clip is still saving."))
            return
        }
        guard byteCount > 0 else {
            let reason = "iPhone recording saved an empty file. Check iPhone storage, camera permission, and recording settings."
            activeRecordingFailureReason = reason
            recordingStateMachine.fail(reason)
            statusMessage = reason
            publish()
            sendEvent(.failed(takeID: takeID, reason: reason))
            return
        }

        recordingStateMachine.markPendingImport(deviceStopTime: activeDeviceStopTime ?? DispatchTime.now().uptimeNanoseconds)
        statusMessage = "Ready to send to Mac"
        activeRecordingURL = recordingURL
        refreshPendingRecordings()
        publish()
        sendEvent(.transferReady(
            takeID: takeID,
            fileName: recordingURL.lastPathComponent,
            byteCount: byteCount,
            manifest: makeManifest(
                takeID: takeID,
                recordingURL: recordingURL,
                byteCount: byteCount,
                sha256: nil,
                resumeOffset: 0
            )
        ))
    }

    private func sendRecordingFile(takeID: UUID, resumeOffset: Int64) {
        let recordingURL = activeRecordingURL ?? existingRecordingURL(takeID)
        guard let recordingURL else {
            recordingStateMachine.fail("Clip missing.")
            statusMessage = "Clip missing"
            publish()
            sendEvent(.failed(takeID: takeID, reason: "Clip missing."))
            requestTelemetry()
            return
        }

        activeRecordingURL = recordingURL
        let fileSize = Self.fileSize(at: recordingURL) ?? 0
        let clampedResumeOffset = RemoteCameraTransferProtocol.clampedResumeOffset(resumeOffset, fileSize: fileSize)
        recordingStateMachine.transfer(takeID: takeID, recordingURL: recordingURL)
        statusMessage = clampedResumeOffset > 0
            ? "Sending again to Mac"
            : "Sending clip to Mac"
        publish()
        transferSender.sendRecordingFile(takeID: takeID, recordingURL: recordingURL, resumeOffset: clampedResumeOffset)
        requestTelemetry()
    }

    private func finishTransfer(takeID: UUID, recordingURL: URL, byteCount: Int64, resumeOffset: Int64, sha256: String) {
        setActiveTransferProgress(RemoteCameraTransferProgress(
            takeID: takeID,
            transferredByteCount: byteCount,
            expectedByteCount: byteCount
        ))
        activeRecordingURL = nil
        activeTakeID = nil
        lastRecordingResult = nil
        recordingStateMachine.markTransferComplete()
        refreshPendingRecordings()
        statusMessage = "Sent to Mac"
        publish()
        sendEvent(.transferComplete(takeID: takeID, byteCount: byteCount, sha256: sha256))
        requestTelemetry()
    }

    private func failTransfer(takeID: UUID, error: Error) {
        recordingStateMachine.fail(error.localizedDescription)
        activeRecordingFailureReason = error.localizedDescription
        statusMessage = "Couldn’t send: \(error.localizedDescription)"
        publish()
        sendEvent(.failed(takeID: takeID, reason: error.localizedDescription))
        requestTelemetry()
    }

    private func resolveTransferAck(takeID: UUID, receivedByteCount: Int64) {
        if transferSender.resolveAck(takeID: takeID, receivedByteCount: receivedByteCount) {
            return
        }

        guard let progress = activeTransferProgress,
              progress.takeID == takeID,
              RemoteCameraTransferProtocol.shouldCompleteImport(
                receivedByteCount: receivedByteCount,
                expectedByteCount: progress.expectedByteCount
              ) else {
            return
        }
        completeMacImport(takeID: takeID)
    }

    private func completeMacImport(takeID: UUID) {
        let keepsRecording = keepsRecordingsAfterMacImport()
        if !keepsRecording, let recordingURL = existingRecordingURL(takeID) {
            removeRecording(recordingURL)
        }
        setActiveTransferProgress(nil)
        activeRecordingURL = nil
        activeTakeID = nil
        lastRecordingResult = nil
        refreshPendingRecordings()
        recordingStateMachine.cancel()
        statusMessage = keepsRecording
            ? "Sent to Mac. Kept on iPhone."
            : importCompletedStatus()
        publish()
        requestTelemetry()
    }

    private func setActiveTransferProgress(_ progress: RemoteCameraTransferProgress?) {
        activeTransferProgress = progress
        publish()
    }

    private func publish() {
        onSnapshotChanged?(CameraCompanionRecordingSnapshot(
            phase: recordingStateMachine.phase,
            activeRecordingURL: activeRecordingURL,
            activeTransferProgress: activeTransferProgress,
            statusMessage: statusMessage
        ))
    }

    private func makeManifest(
        takeID: UUID,
        recordingURL: URL,
        byteCount: Int64,
        sha256: String?,
        resumeOffset: Int64
    ) -> RemoteCameraTransferManifest {
        makeTransferManifest(CameraCompanionTransferManifestRequest(
            takeID: takeID,
            recordingURL: recordingURL,
            byteCount: byteCount,
            sha256: sha256,
            resumeOffset: resumeOffset,
            durationSeconds: Double(elapsedSeconds()),
            deviceStartTime: activeDeviceStartTime,
            deviceStopTime: activeDeviceStopTime,
            hostStartTime: activeHostStartTime,
            hostStopTime: activeHostStopTime,
            hostTimelineStartTime: activeHostTimelineStartTime,
            stopReason: activeStopReason
        ))
    }

    private static func fileSize(at url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }
}
