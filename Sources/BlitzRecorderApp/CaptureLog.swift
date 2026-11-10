import Foundation

/// Capture events kept in Library/Logs/BlitzRecorder/capture.log (inside the app container), so a take that went
/// wrong can be explained afterwards. The system log drops most of them within hours.
enum CaptureLog {
    private static let queue = DispatchQueue(label: "blitzrecorder.capture-log", qos: .utility)
    private static let maximumBytes: UInt64 = 5 << 20

    static let url: URL = {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return library.appendingPathComponent("Logs/BlitzRecorder/capture.log")
    }()

    private static let timeStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .current)

    static func note(_ message: String) {
        NSLog("%@", message)
        let line = "\(Date().formatted(timeStyle)) \(message)\n"
        queue.async { append(line) }
    }

    private static func append(_ line: String) {
        let manager = FileManager.default
        try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? manager.attributesOfItem(atPath: url.path))?[.size] as? UInt64, size > maximumBytes {
            let previous = url.deletingLastPathComponent().appendingPathComponent("capture.previous.log")
            try? manager.removeItem(at: previous)
            try? manager.moveItem(at: url, to: previous)
        }
        let data = Data(line.utf8)
        guard let handle = try? FileHandle(forWritingTo: url) else {
            try? data.write(to: url)
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}
