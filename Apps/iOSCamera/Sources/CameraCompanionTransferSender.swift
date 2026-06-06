import BlitzRecorderCore
import CryptoKit
import Foundation

@MainActor
final class CameraCompanionTransferSender {
    private var activeTransferTask: Task<Void, Never>?
    private var transferAckContinuations: [UUID: CheckedContinuation<Int64, Error>] = [:]
    private var activeProgress: RemoteCameraTransferProgress?

    var onProgressChanged: ((RemoteCameraTransferProgress?) -> Void)?
    var onFinished: ((UUID, URL, Int64, Int64, String) -> Void)?
    var onFailed: ((UUID, Error) -> Void)?

    private let sendEvent: (RemoteCameraEvent) -> Void

    init(sendEvent: @escaping (RemoteCameraEvent) -> Void) {
        self.sendEvent = sendEvent
    }

    func sendRecordingFile(takeID: UUID, recordingURL: URL, resumeOffset: Int64) {
        cancel(reason: "Superseded by a newer transfer request.", notifyMac: false)

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: recordingURL.path)[.size] as? NSNumber)?
            .int64Value ?? 0
        let clampedResumeOffset = RemoteCameraTransferProtocol.clampedResumeOffset(resumeOffset, fileSize: fileSize)
        setProgress(RemoteCameraTransferProtocol.progress(
            takeID: takeID,
            transferredByteCount: clampedResumeOffset,
            expectedByteCount: fileSize
        ))

        activeTransferTask = Task.detached(priority: .userInitiated) { [weak self, recordingURL] in
            do {
                let handle = try FileHandle(forReadingFrom: recordingURL)
                defer { try? handle.close() }

                var hasher = SHA256()
                var offset: Int64 = 0
                while true {
                    try Task.checkCancellation()
                    let data = try handle.read(upToCount: RemoteCameraTransferProtocol.defaultChunkSize) ?? Data()
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
                await self?.finishTransfer(
                    takeID: takeID,
                    recordingURL: recordingURL,
                    byteCount: fileSize,
                    resumeOffset: clampedResumeOffset,
                    sha256: sha256
                )
            } catch {
                if Self.isIntentionalTransferCancellation(error) {
                    return
                }
                await self?.failTransfer(takeID: takeID, error: error)
            }
        }
    }

    func resolveAck(takeID: UUID, receivedByteCount: Int64) -> Bool {
        guard let continuation = transferAckContinuations.removeValue(forKey: takeID) else {
            return false
        }
        continuation.resume(returning: receivedByteCount)
        return true
    }

    func cancel(reason: String, notifyMac: Bool = true) {
        activeTransferTask?.cancel()
        activeTransferTask = nil
        let error = CameraCompanionTransferSenderError.cancelled(reason)
        for (_, continuation) in transferAckContinuations {
            continuation.resume(throwing: error)
        }
        transferAckContinuations.removeAll()
        if notifyMac, let takeID = activeProgress?.takeID {
            sendEvent(.failed(takeID: takeID, reason: reason))
        }
    }

    private func sendTransferChunkAndWaitForAck(takeID: UUID, offset: Int64, data: Data, isFinal: Bool) async throws {
        let transferredByteCount = offset + Int64(data.count)
        let expectedByteCount = activeProgress?.expectedByteCount ?? transferredByteCount
        let acknowledgedByteCount = try await withCheckedThrowingContinuation { continuation in
            transferAckContinuations[takeID]?.resume(throwing: CancellationError())
            transferAckContinuations[takeID] = continuation
            sendEvent(.transferChunk(takeID: takeID, offset: offset, data: data, isFinal: isFinal))
        }
        guard RemoteCameraTransferProtocol.isAcknowledgementValid(
            receivedByteCount: acknowledgedByteCount,
            expectedMinimumByteCount: transferredByteCount
        ) else {
            throw CameraCompanionTransferSenderError.invalidAcknowledgement(
                expected: transferredByteCount,
                received: acknowledgedByteCount
            )
        }
        setProgress(RemoteCameraTransferProtocol.progress(
            takeID: takeID,
            transferredByteCount: acknowledgedByteCount,
            expectedByteCount: expectedByteCount
        ))
    }

    private func finishTransfer(takeID: UUID, recordingURL: URL, byteCount: Int64, resumeOffset: Int64, sha256: String) {
        setProgress(RemoteCameraTransferProtocol.progress(
            takeID: takeID,
            transferredByteCount: byteCount,
            expectedByteCount: byteCount
        ))
        activeTransferTask = nil
        onFinished?(takeID, recordingURL, byteCount, resumeOffset, sha256)
    }

    private func failTransfer(takeID: UUID, error: Error) {
        activeTransferTask = nil
        transferAckContinuations.removeValue(forKey: takeID)?.resume(throwing: error)
        onFailed?(takeID, error)
    }

    private func setProgress(_ progress: RemoteCameraTransferProgress?) {
        activeProgress = progress
        onProgressChanged?(progress)
    }

    nonisolated private static func isIntentionalTransferCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let transferError = error as? CameraCompanionTransferSenderError,
           case .cancelled = transferError {
            return true
        }
        return false
    }
}

private enum CameraCompanionTransferSenderError: LocalizedError {
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
