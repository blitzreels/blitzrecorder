import Foundation

public enum RemoteCameraTransferChunkDisposition: Equatable, Sendable {
    case append
    case alreadyReceived(acknowledgedByteCount: Int64)
    case gap(expectedOffset: Int64, receivedOffset: Int64)
}

public enum RemoteCameraTransferProtocol {
    public static let defaultChunkSize = 256 * 1024

    public static func clampedResumeOffset(_ resumeOffset: Int64, fileSize: Int64) -> Int64 {
        min(max(0, resumeOffset), max(0, fileSize))
    }

    public static func chunkDisposition(offset: Int64, receivedByteCount: Int64) -> RemoteCameraTransferChunkDisposition {
        if offset == receivedByteCount {
            return .append
        }
        if offset < receivedByteCount {
            return .alreadyReceived(acknowledgedByteCount: receivedByteCount)
        }
        return .gap(expectedOffset: receivedByteCount, receivedOffset: offset)
    }

    public static func isAcknowledgementValid(receivedByteCount: Int64, expectedMinimumByteCount: Int64) -> Bool {
        receivedByteCount >= expectedMinimumByteCount
    }

    public static func progress(takeID: UUID, transferredByteCount: Int64, expectedByteCount: Int64) -> RemoteCameraTransferProgress {
        let expected = max(0, expectedByteCount)
        return RemoteCameraTransferProgress(
            takeID: takeID,
            transferredByteCount: min(max(0, transferredByteCount), expected),
            expectedByteCount: expected
        )
    }

    public static func shouldCompleteImport(receivedByteCount: Int64, expectedByteCount: Int64) -> Bool {
        expectedByteCount > 0 && receivedByteCount >= expectedByteCount
    }
}
