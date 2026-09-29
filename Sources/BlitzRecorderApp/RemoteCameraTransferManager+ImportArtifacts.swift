import BlitzRecorderCore
import CryptoKit
import Foundation

extension RemoteCameraTransferManager {
    static func importFailureStatusMessage(for error: Error) -> String {
        let reason = error.recorderFailureDescription
        let lowercased = reason.lowercased()
        if lowercased.contains("no video track") || lowercased.contains("no video frames captured") {
            return "iPhone import failed: the iPhone recording has no usable video. Keep the iPhone app open until recording stops, then retry."
        }
        if lowercased.contains("cannot open") || lowercased.contains("operation not permitted") {
            return "iPhone import failed: BlitzRecorder could not open the saved media. Check recording-folder permission, then retry."
        }
        return "iPhone import failed. Keep both devices on the same Wi-Fi, reopen BlitzRecorder Camera, then retry."
    }

    static func sha256HexDigest(for url: URL) throws -> String {
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

    static func writeManifest(
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
