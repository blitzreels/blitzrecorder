import CryptoKit
import Foundation

struct MediaFileFingerprint: Equatable, Sendable {
    let path: String
    let size: Int
    let modified: Date

    init?(url: URL) {
        guard let values = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = values[.size] as? NSNumber,
              let modified = values[.modificationDate] as? Date else { return nil }
        path = url.standardizedFileURL.path
        self.size = size.intValue
        self.modified = modified
    }

    var cacheKey: String {
        let value = "\(path)\u{0}\(size)\u{0}\(modified.timeIntervalSince1970.bitPattern)"
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
