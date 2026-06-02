import BlitzRecorderCore
import Foundation

@MainActor
final class RemoteCameraSessionRuntime {
    private enum SyncPhase: Hashable {
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

    private struct SyncKey: Hashable {
        let takeID: UUID
        let phase: SyncPhase
    }

    private let sendCommand: (RemoteCameraCommand) -> Void
    private let onMessage: (String) -> Void

    private var prepareContinuations: [UUID: CheckedContinuation<UInt64, Error>] = [:]
    private var startContinuations: [UUID: CheckedContinuation<UInt64, Error>] = [:]
    private var timelineStartTimes: [UUID: UInt64] = [:]
    private var startRequestTimes: [UUID: UInt64] = [:]
    private var startResponseTimes: [UUID: UInt64] = [:]
    private var syncTimeoutTasks: [SyncKey: Task<Void, Never>] = [:]
    private lazy var transferManager = RemoteCameraTransferManager(
        sendCommand: { [weak self] command in
            self?.sendCommand(command)
        },
        onMessage: { [weak self] message in
            self?.onMessage(message)
        },
        onTransferFinished: { [weak self] takeID in
            self?.clearTiming(takeID: takeID)
            if self?.activeTakeID == takeID {
                self?.activeTakeID = nil
            }
        }
    )

    private(set) var activeTakeID: UUID?

    init(sendCommand: @escaping (RemoteCameraCommand) -> Void, onMessage: @escaping (String) -> Void) {
        self.sendCommand = sendCommand
        self.onMessage = onMessage
    }

    func beginTake(takeID: UUID, serviceID: String?, take: RecordingTake, settings: RecordingSettings) {
        activeTakeID = takeID
        transferManager.registerPendingImport(
            takeID: takeID,
            serviceID: serviceID,
            take: take,
            settings: settings
        )
    }

    func removePendingImport(takeID: UUID, settings: RecordingSettings) {
        transferManager.removePendingImport(takeID: takeID, settings: settings)
    }

    func cancelCommand() {
        sendCommand(.cancel)
    }

    func abandonTake(takeID: UUID) {
        failSync(takeID: takeID, phase: .prepare, reason: "Recording start failed before prepare completed.")
        failSync(takeID: takeID, phase: .start, reason: "Recording start failed before remote start completed.")
        clearTiming(takeID: takeID)
        if activeTakeID == takeID {
            activeTakeID = nil
        }
    }

    func markTimelineStart(takeID: UUID, hostTimelineStartTime: UInt64) {
        timelineStartTimes[takeID] = hostTimelineStartTime
    }

    func prepare(takeID: UUID, hostStartTime: UInt64) async throws -> UInt64 {
        try await withCheckedThrowingContinuation { continuation in
            replaceSyncContinuation(takeID: takeID, phase: .prepare, continuation: continuation)
            scheduleSyncTimeout(takeID: takeID, phase: .prepare)
            sendCommand(.prepare(RemoteCameraTimeline(
                takeID: takeID,
                hostStartTime: hostStartTime
            )))
        }
    }

    func start(takeID: UUID, hostStartTime: UInt64, hostTimelineStartTime: UInt64?) async throws -> UInt64 {
        startRequestTimes[takeID] = hostStartTime
        return try await withCheckedThrowingContinuation { continuation in
            replaceSyncContinuation(takeID: takeID, phase: .start, continuation: continuation)
            scheduleSyncTimeout(takeID: takeID, phase: .start)
            sendCommand(.start(RemoteCameraTimeline(
                takeID: takeID,
                hostStartTime: hostStartTime,
                hostTimelineStartTime: hostTimelineStartTime
            )))
        }
    }

    func stopAndImport(take: RecordingTake, settings: RecordingSettings) async throws -> MediaWriterCompletion {
        if transferManager.hasCompletedImport(for: take) {
            return .wrote(take.cameraURL)
        }
        guard let takeID = transferManager.takeID(
            activeTakeID: activeTakeID,
            take: take,
            settings: settings
        ) else {
            throw RecorderError.remoteCameraTransferFailed("Missing active remote take.")
        }
        activeTakeID = takeID
        return try await transferManager.waitForStopAndImport(takeID: takeID, take: take, settings: settings)
    }

    func requestPendingImports(serviceID: String, settings: RecordingSettings) {
        transferManager.requestPendingImports(serviceID: serviceID, settings: settings)
    }

    func handleFailed(takeID failedTakeID: UUID?, reason: String) {
        if let syncTakeID = failedTakeID ?? activeTakeID {
            failSync(takeID: syncTakeID, phase: .prepare, reason: reason)
            failSync(takeID: syncTakeID, phase: .start, reason: reason)
        }
        if let takeID = activeTakeID {
            transferManager.failInFlightTransfer(takeID: takeID, reason: reason)
        }
    }

    func applyTransferReady(
        takeID: UUID,
        byteCount: Int64,
        manifest: RemoteCameraTransferManifest,
        settings: RecordingSettings
    ) {
        transferManager.applyTransferReady(
            takeID: takeID,
            byteCount: byteCount,
            manifest: manifest,
            settings: settings,
            hostTimelineStartTime: timelineStartTimes[takeID],
            estimatedHostStartTime: estimatedHostStartTime(takeID: takeID)
        )
    }

    func writeChunk(takeID: UUID, offset: Int64, data: Data, isFinal: Bool) {
        transferManager.writeChunk(takeID: takeID, offset: offset, data: data, isFinal: isFinal)
    }

    func completeTransfer(takeID: UUID, byteCount: Int64, sha256: String?, settings: RecordingSettings) {
        transferManager.completeTransfer(takeID: takeID, byteCount: byteCount, sha256: sha256, settings: settings)
    }

    func resolvePrepared(takeID: UUID, deviceStartTime: UInt64) {
        resolveSync(takeID: takeID, phase: .prepare, deviceTime: deviceStartTime)
    }

    func resolveStarted(takeID: UUID, deviceStartTime: UInt64) {
        startResponseTimes[takeID] = DispatchTime.now().uptimeNanoseconds
        resolveSync(takeID: takeID, phase: .start, deviceTime: deviceStartTime)
    }

    private func replaceSyncContinuation(
        takeID: UUID,
        phase: SyncPhase,
        continuation: CheckedContinuation<UInt64, Error>
    ) {
        failSync(takeID: takeID, phase: phase, reason: "Superseded by a newer sync request.")
        switch phase {
        case .prepare:
            prepareContinuations[takeID] = continuation
        case .start:
            startContinuations[takeID] = continuation
        }
    }

    private func scheduleSyncTimeout(takeID: UUID, phase: SyncPhase) {
        let key = SyncKey(takeID: takeID, phase: phase)
        syncTimeoutTasks[key]?.cancel()
        syncTimeoutTasks[key] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return }
                self.failSync(takeID: takeID, phase: phase, reason: phase.timeoutMessage)
            }
        }
    }

    private func resolveSync(takeID: UUID, phase: SyncPhase, deviceTime: UInt64) {
        let key = SyncKey(takeID: takeID, phase: phase)
        syncTimeoutTasks.removeValue(forKey: key)?.cancel()
        switch phase {
        case .prepare:
            prepareContinuations.removeValue(forKey: takeID)?.resume(returning: deviceTime)
        case .start:
            startContinuations.removeValue(forKey: takeID)?.resume(returning: deviceTime)
        }
    }

    private func failSync(takeID: UUID, phase: SyncPhase, reason: String) {
        let key = SyncKey(takeID: takeID, phase: phase)
        syncTimeoutTasks.removeValue(forKey: key)?.cancel()
        let error = RecorderError.remoteCameraSynchronizationFailed(reason)
        switch phase {
        case .prepare:
            prepareContinuations.removeValue(forKey: takeID)?.resume(throwing: error)
        case .start:
            startContinuations.removeValue(forKey: takeID)?.resume(throwing: error)
        }
    }

    private func estimatedHostStartTime(takeID: UUID) -> UInt64? {
        guard let requestTime = startRequestTimes[takeID] else { return nil }
        guard let responseTime = startResponseTimes[takeID], responseTime >= requestTime else {
            return requestTime
        }
        return requestTime + ((responseTime - requestTime) / 2)
    }

    private func clearTiming(takeID: UUID) {
        timelineStartTimes.removeValue(forKey: takeID)
        startRequestTimes.removeValue(forKey: takeID)
        startResponseTimes.removeValue(forKey: takeID)
    }
}
