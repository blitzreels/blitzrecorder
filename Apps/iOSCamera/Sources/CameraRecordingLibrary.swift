import Foundation

struct CameraRecordingLibrary {
    func recordingURL(takeID: UUID) throws -> URL {
        try recordingsDirectory().appendingPathComponent("\(takeID.uuidString)-camera.mov")
    }

    func existingRecordingURL(takeID: UUID) -> URL? {
        guard let url = try? recordingURL(takeID: takeID),
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    func pendingRecordingURLs() -> [URL] {
        guard let directory = try? recordingsDirectory(),
              let urls = try? FileManager.default.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
                  options: [.skipsHiddenFiles]
              ) else {
            return []
        }
        return urls
            .filter { $0.pathExtension.lowercased() == "mov" && keepsAsPending($0) }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return lhsDate > rhsDate
            }
    }

    /// A take that never wrote a byte holds nothing to import. Left in place it would be offered to the Mac
    /// forever and stall every later transfer, so once it is clearly abandoned it is removed.
    private func keepsAsPending(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard (values?.fileSize ?? 0) == 0 else { return true }
        let modified = values?.contentModificationDate ?? .distantPast
        if Date().timeIntervalSince(modified) > 600 {
            removeRecording(at: url)
        }
        return false
    }

    func removeRecording(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    func hasRecoverableMedia(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
              let byteCount = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value else {
            return false
        }
        return byteCount > 0
    }

    private func recordingsDirectory() throws -> URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RemoteCameraRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
