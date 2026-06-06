import Foundation

struct CameraPendingRecording: Identifiable, Equatable {
    let id: String
    let takeID: UUID?
    let url: URL
    let fileName: String
    let createdAtLabel: String
    let byteCount: Int64
    let byteCountLabel: String
}

struct CameraPendingImportSnapshot: Equatable {
    var recordings: [CameraPendingRecording]
    var byteCountLabel: String

    var count: Int {
        recordings.count
    }

    static let empty = CameraPendingImportSnapshot(recordings: [], byteCountLabel: "0 KB")
}

struct CameraPendingImportRetryRequest: Equatable {
    var takeID: UUID
    var recordingURL: URL
    var fileName: String
}

enum CameraPendingImportRetryResult: Equatable {
    case success(CameraPendingImportRetryRequest)
    case failure(String)
}

struct CameraPendingImportMutationResult: Equatable {
    var snapshot: CameraPendingImportSnapshot
    var statusMessage: String
}

struct CameraPendingImportLibrary {
    typealias PendingRecordingURLs = () -> [URL]
    typealias RemoveRecording = (URL) -> Void

    private let pendingRecordingURLs: PendingRecordingURLs
    private let removeRecording: RemoveRecording

    init(
        pendingRecordingURLs: @escaping PendingRecordingURLs,
        removeRecording: @escaping RemoveRecording
    ) {
        self.pendingRecordingURLs = pendingRecordingURLs
        self.removeRecording = removeRecording
    }

    func refresh() -> CameraPendingImportSnapshot {
        makeSnapshot(recordings: pendingRecordingURLs().map(Self.makePendingRecording))
    }

    func retryRequest(
        for recording: CameraPendingRecording,
        isPairedWithMac: Bool
    ) -> CameraPendingImportRetryResult {
        guard let takeID = recording.takeID else {
            return .failure("This pending recording has no recoverable take ID.")
        }
        guard isPairedWithMac else {
            return .failure("Reconnect BlitzRecorder before retrying import.")
        }
        return .success(CameraPendingImportRetryRequest(
            takeID: takeID,
            recordingURL: recording.url,
            fileName: recording.fileName
        ))
    }

    func delete(
        _ recording: CameraPendingRecording,
        activeRecordingURL: URL?
    ) -> CameraPendingImportMutationResult {
        guard recording.url != activeRecordingURL else {
            return CameraPendingImportMutationResult(
                snapshot: refresh(),
                statusMessage: "Cannot delete the active recording."
            )
        }
        removeRecording(recording.url)
        return CameraPendingImportMutationResult(
            snapshot: refresh(),
            statusMessage: "Deleted pending recording."
        )
    }

    func deleteAll(activeRecordingURL: URL?) -> CameraPendingImportMutationResult {
        let recordings = refresh().recordings
        let removableRecordings = recordings.filter { $0.url != activeRecordingURL }
        for recording in removableRecordings {
            removeRecording(recording.url)
        }
        return CameraPendingImportMutationResult(
            snapshot: refresh(),
            statusMessage: removableRecordings.isEmpty
                ? "No clips to delete."
                : "Deleted \(removableRecordings.count) clip\(removableRecordings.count == 1 ? "" : "s")."
        )
    }

    func importCompletedStatus(pendingCount: Int) -> String {
        pendingCount > 0
            ? "\(pendingCount) clip\(pendingCount == 1 ? "" : "s") ready to send to Mac"
            : "Sent to Mac"
    }

    func pendingImportStatus(pendingCount: Int) -> String {
        "\(pendingCount) clip\(pendingCount == 1 ? "" : "s") ready to send to Mac"
    }

    private func makeSnapshot(recordings: [CameraPendingRecording]) -> CameraPendingImportSnapshot {
        let totalBytes = recordings.reduce(Int64(0)) { partialResult, recording in
            partialResult + recording.byteCount
        }
        return CameraPendingImportSnapshot(
            recordings: recordings,
            byteCountLabel: ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        )
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
            createdAtLabel: createdAt.map(shortDateTimeLabel) ?? "Unknown time",
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
}
