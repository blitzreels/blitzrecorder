@preconcurrency import AVFoundation
import Foundation

/// Cuts the end off a finished clip without re-encoding, for takes the Mac stopped while out of reach.
enum CameraClipTrimmer {
    struct Request {
        let url: URL
        let seconds: Double
    }

    static func trim(_ request: Request) async throws {
        let asset = AVURLAsset(url: request.url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            return
        }
        let trimmedURL = request.url.deletingPathExtension().appendingPathExtension("trimmed.mov")
        try? FileManager.default.removeItem(at: trimmedURL)
        session.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: request.seconds, preferredTimescale: 600))
        try await session.export(to: trimmedURL, as: .mov)
        _ = try FileManager.default.replaceItemAt(request.url, withItemAt: trimmedURL)
    }
}
