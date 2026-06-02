import BlitzRecorderCore
import CryptoKit
import Foundation

@MainActor
final class RemoteCameraTransferManager {
    private struct TransferSession {
        let destinationURL: URL
        let partialURL: URL
        let fileHandle: FileHandle
        var expectedByteCount: Int64
        var manifest: RemoteCameraTransferManifest?
        var receivedByteCount: Int64
        var settings: RecordingSettings?
    }

    private let pendingImportStore: RemoteCameraPendingImportStore
    private let sendCommand: (RemoteCameraCommand) -> Void
    private let onMessage: (String) -> Void
    private let onTransferFinished: (UUID) -> Void

    private var transfers: [UUID: TransferSession] = [:]
    private var continuations: [UUID: CheckedContinuation<MediaWriterCompletion, Error>] = [:]
    private var timeoutTasks: [UUID: Task<Void, Never>] = [:]

    init(
        pendingImportStore: RemoteCameraPendingImportStore = RemoteCameraPendingImportStore(),
        sendCommand: @escaping (RemoteCameraCommand) -> Void,
        onMessage: @escaping (String) -> Void,
        onTransferFinished: @escaping (UUID) -> Void
    ) {
        self.pendingImportStore = pendingImportStore
        self.sendCommand = sendCommand
        self.onMessage = onMessage
        self.onTransferFinished = onTransferFinished
    }

    func registerPendingImport(
        takeID: UUID,
        serviceID: String?,
        take: RecordingTake,
        settings: RecordingSettings
    ) {
        pendingImportStore.upsert(RemoteCameraPendingImport(
            takeID: takeID,
            serviceID: serviceID,
            scratchDirectory: take.scratchDirectory,
            destinationURL: take.cameraURL,
            createdAt: Date(),
            expectedByteCount: nil
        ), settings: settings)
    }

    func removePendingImport(takeID: UUID, settings: RecordingSettings) {
        pendingImportStore.remove(takeID: takeID, settings: settings)
    }

    func takeID(activeTakeID: UUID?, take: RecordingTake, settings: RecordingSettings) -> UUID? {
        RemoteCameraTakeIDResolver.takeID(
            activeTakeID: activeTakeID,
            pendingTransferDestinationURLs: transfers.mapValues(\.destinationURL),
            pendingImports: pendingImportStore.all(settings: settings),
            take: take
        )
    }

    func hasCompletedImport(for take: RecordingTake) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: take.cameraURL.path),
              let size = attributes[.size] as? NSNumber else {
            return false
        }
        return size.int64Value > 0
    }

    func waitForStopAndImport(takeID: UUID, take: RecordingTake, settings: RecordingSettings) async throws -> MediaWriterCompletion {
        try await withCheckedThrowingContinuation { continuation in
            continuations[takeID] = continuation
            pendingImportStore.updatePhase(takeID: takeID, phase: .waitingForStop, settings: settings)
            if transfers[takeID] != nil {
                onMessage("Waiting for iPhone media download...")
                scheduleTimeout(
                    takeID: takeID,
                    reason: "Timed out while receiving iPhone recording data."
                )
                return
            }

            onMessage("Stopping iPhone recording...")
            sendCommand(.stop(RemoteCameraTimeline(
                takeID: takeID,
                hostStopTime: DispatchTime.now().uptimeNanoseconds
            )))
            let resumeOffset = beginTransfer(
                takeID: takeID,
                destinationURL: take.cameraURL,
                expectedByteCount: 0,
                settings: settings
            )
            guard let resumeOffset else { return }
            if resumeOffset > 0 {
                onMessage("iPhone media download will resume when the recording is ready.")
            }
        }
    }

    @discardableResult
    func beginTransfer(
        takeID: UUID,
        destinationURL: URL,
        expectedByteCount: Int64,
        settings: RecordingSettings? = nil
    ) -> Int64? {
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
            transfers[takeID] = TransferSession(
                destinationURL: destinationURL,
                partialURL: partialURL,
                fileHandle: handle,
                expectedByteCount: expectedByteCount,
                manifest: nil,
                receivedByteCount: resumeOffset,
                settings: settings
            )
            if let settings {
                pendingImportStore.updatePhase(takeID: takeID, phase: .transferring, settings: settings)
            }
            scheduleTimeout(
                takeID: takeID,
                reason: "Timed out waiting for iPhone recording transfer."
            )
            onMessage(resumeOffset > 0
                ? "Resuming iPhone media download..."
                : "Downloading iPhone media...")
            return resumeOffset
        } catch {
            finish(takeID: takeID, result: .failure(error))
            return nil
        }
    }

    func applyTransferReady(
        takeID: UUID,
        byteCount: Int64,
        manifest: RemoteCameraTransferManifest,
        settings: RecordingSettings,
        hostTimelineStartTime: UInt64?,
        estimatedHostStartTime: UInt64?
    ) {
        guard var transfer = transfers[takeID] else { return }
        var manifest = manifest
        manifest.hostTimelineStartTime = manifest.hostTimelineStartTime ?? hostTimelineStartTime
        manifest.estimatedHostStartTime = manifest.estimatedHostStartTime ?? estimatedHostStartTime

        if transfer.receivedByteCount > byteCount {
            try? transfer.fileHandle.truncate(atOffset: 0)
            try? transfer.fileHandle.seek(toOffset: 0)
            transfer.receivedByteCount = 0
        }

        transfer.expectedByteCount = byteCount
        transfer.manifest = manifest
        transfers[takeID] = transfer
        pendingImportStore.updatePhase(takeID: takeID, phase: .ready, settings: settings)
        pendingImportStore.updateExpectedByteCount(
            takeID: takeID,
            expectedByteCount: byteCount,
            settings: settings
        )
        scheduleTimeout(
            takeID: takeID,
            reason: "Timed out while receiving iPhone recording data."
        )
        let size = ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
        onMessage("Downloading iPhone media (\(size))...")
        sendCommand(.requestTransfer(takeID: takeID, resumeOffset: transfer.receivedByteCount))
    }

    func writeChunk(takeID: UUID, offset: Int64, data: Data, isFinal: Bool) {
        guard var transfer = transfers[takeID] else {
            finish(takeID: takeID, result: .failure(RecorderError.remoteCameraTransferFailed("Transfer was not initialized.")))
            return
        }
        do {
            switch RemoteCameraTransferProtocol.chunkDisposition(
                offset: offset,
                receivedByteCount: transfer.receivedByteCount
            ) {
            case .append:
                break
            case .alreadyReceived(let acknowledgedByteCount):
                sendCommand(.transferAck(
                    takeID: takeID,
                    receivedByteCount: acknowledgedByteCount
                ))
                return
            case .gap(let expectedOffset, let receivedOffset):
                throw RecorderError.remoteCameraTransferFailed(
                    "Expected chunk at offset \(expectedOffset), received \(receivedOffset)."
                )
            }
            try transfer.fileHandle.seek(toOffset: UInt64(offset))
            try transfer.fileHandle.write(contentsOf: data)
            transfer.receivedByteCount = max(transfer.receivedByteCount, offset + Int64(data.count))
            transfers[takeID] = transfer
            sendCommand(.transferAck(
                takeID: takeID,
                receivedByteCount: transfer.receivedByteCount
            ))
            scheduleTimeout(
                takeID: takeID,
                reason: "Timed out while receiving iPhone recording data."
            )
            _ = isFinal
        } catch {
            finish(takeID: takeID, result: .failure(error))
        }
    }

    func completeTransfer(takeID: UUID, byteCount: Int64, sha256: String?, settings: RecordingSettings) {
        guard let transfer = transfers[takeID] else { return }
        finishCompletedTransfer(takeID: takeID, transfer: transfer, byteCount: byteCount, sha256: sha256, settings: settings)
    }

    func failInFlightTransfer(takeID: UUID, reason: String) {
        guard transfers[takeID] != nil || continuations[takeID] != nil else { return }
        finish(takeID: takeID, result: .failure(RecorderError.remoteCameraTransferFailed(reason)))
    }

    func requestPendingImports(serviceID: String, settings: RecordingSettings) {
        for pendingImport in pendingImportStore.all(settings: settings) {
            guard pendingImport.serviceID == nil || pendingImport.serviceID == serviceID else { continue }
            guard transfers[pendingImport.takeID] == nil else { continue }
            guard let resumeOffset = beginTransfer(
                takeID: pendingImport.takeID,
                destinationURL: pendingImport.destinationURL,
                expectedByteCount: pendingImport.expectedByteCount ?? 0,
                settings: settings
            ) else { continue }
            sendCommand(.requestTransfer(takeID: pendingImport.takeID, resumeOffset: resumeOffset))
        }
    }

    private func scheduleTimeout(takeID: UUID, reason: String) {
        timeoutTasks.removeValue(forKey: takeID)?.cancel()
        timeoutTasks[takeID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return }
                self.timeoutTasks.removeValue(forKey: takeID)
                guard self.transfers[takeID] != nil || self.continuations[takeID] != nil else {
                    return
                }
                self.finish(
                    takeID: takeID,
                    result: .failure(RecorderError.remoteCameraTransferFailed(reason))
                )
            }
        }
    }

    private func finish(takeID: UUID, result: Result<MediaWriterCompletion, Error>) {
        timeoutTasks.removeValue(forKey: takeID)?.cancel()
        if let transfer = transfers.removeValue(forKey: takeID) {
            if let settings = transfer.settings {
                pendingImportStore.updatePhase(takeID: takeID, phase: .failedRecoverable, settings: settings)
            }
            try? transfer.fileHandle.close()
        }
        onTransferFinished(takeID)
        guard let continuation = continuations.removeValue(forKey: takeID) else {
            return
        }
        switch result {
        case .success(let completion):
            continuation.resume(returning: completion)
        case .failure(let error):
            sendCommand(.cancel)
            continuation.resume(throwing: error)
        }
    }

    private func finishCompletedTransfer(
        takeID: UUID,
        transfer: TransferSession,
        byteCount: Int64,
        sha256: String?,
        settings: RecordingSettings
    ) {
        timeoutTasks.removeValue(forKey: takeID)?.cancel()
        do {
            try transfer.fileHandle.synchronize()
            try transfer.fileHandle.close()
            transfers.removeValue(forKey: takeID)
            let importedByteCount = (try FileManager.default
                .attributesOfItem(atPath: transfer.partialURL.path)[.size] as? NSNumber)?
                .int64Value ?? 0
            guard importedByteCount == byteCount else {
                throw RecorderError.remoteCameraTransferFailed("Expected \(byteCount) bytes, imported \(importedByteCount).")
            }
            if let sha256 {
                let importedSHA256 = try Self.sha256HexDigest(for: transfer.partialURL)
                guard importedSHA256 == sha256 else {
                    throw RecorderError.remoteCameraTransferFailed("Checksum mismatch.")
                }
            }
            if FileManager.default.fileExists(atPath: transfer.destinationURL.path) {
                try FileManager.default.removeItem(at: transfer.destinationURL)
            }
            try FileManager.default.moveItem(at: transfer.partialURL, to: transfer.destinationURL)
            try Self.writeManifest(transfer.manifest, destinationURL: transfer.destinationURL, sha256: sha256)
            pendingImportStore.updatePhase(takeID: takeID, phase: .complete, settings: settings)
            pendingImportStore.remove(takeID: takeID, settings: settings)
            sendCommand(.transferAck(takeID: takeID, receivedByteCount: byteCount))
            onTransferFinished(takeID)
            guard let continuation = continuations.removeValue(forKey: takeID) else {
                onMessage("Recovered Remote iPhone camera import: \(transfer.destinationURL.path)")
                return
            }
            continuation.resume(returning: .wrote(transfer.destinationURL))
        } catch {
            pendingImportStore.updatePhase(takeID: takeID, phase: .failedRecoverable, settings: settings)
            transfers.removeValue(forKey: takeID)
            onTransferFinished(takeID)
            if let continuation = continuations.removeValue(forKey: takeID) {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func sha256HexDigest(for url: URL) throws -> String {
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

    private static func writeManifest(
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
}
