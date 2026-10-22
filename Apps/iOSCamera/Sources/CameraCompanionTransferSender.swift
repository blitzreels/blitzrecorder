import BlitzRecorderCore
import BlitzRecorderTransport
import CryptoKit
import Foundation

@MainActor
final class CameraCompanionTransferSender {
    private var activeTransferTask: Task<Void, Never>?
    private var transferAckContinuations: [UUID: CheckedContinuation<Int64, Error>] = [:]
    private var activeProgress: RemoteCameraTransferProgress?
    private let channel = RawFileTransferServer()
    private var channelToken: String?
    private var channelOutcome: CheckedContinuation<RawFileTransferServer.Outcome, Never>?
    private var channelStarted: CheckedContinuation<Bool, Never>?
    /// How long the Mac has to open the file channel before the clip goes over the control connection instead.
    private static let channelConnectTimeout: Duration = .seconds(10)

    var onProgressChanged: ((RemoteCameraTransferProgress?) -> Void)?
    var onFinished: ((UUID, URL, Int64, Int64, String) -> Void)?
    var onFailed: ((UUID, Error) -> Void)?

    private let sendEvent: (RemoteCameraEvent) -> Void

    init(sendEvent: @escaping (RemoteCameraEvent) -> Void) {
        self.sendEvent = sendEvent
        channel.onStarted = { [weak self] token in
            Task { @MainActor in self?.channelDidStart(token: token) }
        }
        channel.onProgress = { [weak self] token, sentByteCount in
            Task { @MainActor in self?.channelDidSend(.init(token: token, sentByteCount: sentByteCount)) }
        }
        channel.onFinished = { [weak self] token, outcome in
            Task { @MainActor in self?.channelDidFinish(.init(token: token, outcome: outcome)) }
        }
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

        activeTransferTask = Task { [weak self] in
            guard let self else { return }
            let request = FileRequest(takeID: takeID, recordingURL: recordingURL, fileSize: fileSize,
                                      resumeOffset: clampedResumeOffset)
            if await self.sendThroughChannel(request) { return }
            guard !Task.isCancelled else { return }
            self.sendInChunks(request)
        }
    }

    private struct FileRequest: Sendable {
        let takeID: UUID
        let recordingURL: URL
        let fileSize: Int64
        let resumeOffset: Int64
    }

    /// Sends the clip as raw bytes on its own connection. Returns false when the Mac never opened the channel,
    /// so the caller can fall back to chunks on the control connection.
    private func sendThroughChannel(_ request: FileRequest) async -> Bool {
        guard let port = try? await channel.start(), !Task.isCancelled else { return false }
        let token = channel.offer(.init(fileURL: request.recordingURL, offset: request.resumeOffset))
        channelToken = token
        let hashTask = Task.detached(priority: .userInitiated) { [url = request.recordingURL] in
            try Self.sha256(of: url)
        }
        sendEvent(.transferChannel(takeID: request.takeID, port: port, token: token,
                                   offset: request.resumeOffset, byteCount: request.fileSize))
        let started = await withCheckedContinuation { continuation in
            channelStarted = continuation
            Task { [weak self] in
                try? await Task.sleep(for: Self.channelConnectTimeout)
                self?.resolveChannelStarted(false)
            }
        }
        guard started else {
            channel.revoke(token)
            channelToken = nil
            hashTask.cancel()
            return false
        }
        let outcome = await withCheckedContinuation { channelOutcome = $0 }
        channelToken = nil
        guard !Task.isCancelled else {
            hashTask.cancel()
            return true
        }
        switch outcome {
        case .sent:
            do {
                let sha256 = try await hashTask.value
                finishTransfer(takeID: request.takeID, recordingURL: request.recordingURL, byteCount: request.fileSize,
                               resumeOffset: request.resumeOffset, sha256: sha256)
            } catch {
                failTransfer(takeID: request.takeID, error: error)
            }
        case .failed(let reason):
            hashTask.cancel()
            failTransfer(takeID: request.takeID, error: CameraCompanionTransferSenderError.cancelled(reason))
        }
        return true
    }

    private func resolveChannelStarted(_ started: Bool) {
        channelStarted?.resume(returning: started)
        channelStarted = nil
    }

    private func channelDidStart(token: String) {
        guard token == channelToken else { return }
        resolveChannelStarted(true)
    }

    private struct ChannelProgress {
        let token: String
        let sentByteCount: Int64
    }

    private func channelDidSend(_ progress: ChannelProgress) {
        guard progress.token == channelToken, let active = activeProgress else { return }
        setProgress(RemoteCameraTransferProtocol.progress(
            takeID: active.takeID,
            transferredByteCount: progress.sentByteCount,
            expectedByteCount: active.expectedByteCount
        ))
    }

    private struct ChannelResult {
        let token: String
        let outcome: RawFileTransferServer.Outcome
    }

    private func channelDidFinish(_ result: ChannelResult) {
        guard result.token == channelToken else { return }
        channelOutcome?.resume(returning: result.outcome)
        channelOutcome = nil
    }

    nonisolated private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 4 * 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func sendInChunks(_ request: FileRequest) {
        let takeID = request.takeID
        let fileSize = request.fileSize
        let clampedResumeOffset = request.resumeOffset
        activeTransferTask = Task.detached(priority: .userInitiated) { [weak self, recordingURL = request.recordingURL] in
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
        if let channelToken { channel.revoke(channelToken) }
        channelToken = nil
        resolveChannelStarted(false)
        channelOutcome?.resume(returning: .failed(reason))
        channelOutcome = nil
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
