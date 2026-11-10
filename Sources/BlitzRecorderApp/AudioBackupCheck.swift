import AVFoundation
import Foundation

enum MediaFileDuration {
    struct Request {
        let url: URL
        let mediaType: AVMediaType
    }

    /// Seconds the file plays for, or nil when it is missing, unreadable or has no track of that type.
    static func playable(_ request: Request) async -> Double? {
        guard FileManager.default.fileExists(atPath: request.url.path) else { return nil }
        let asset = AVURLAsset(url: request.url)
        guard let tracks = try? await asset.loadTracks(withMediaType: request.mediaType), !tracks.isEmpty,
              let (isPlayable, duration) = try? await asset.load(.isPlayable, .duration),
              isPlayable, duration.isNumeric, duration.seconds > 0 else { return nil }
        return duration.seconds
    }
}

/// Compares a finished audio file with the crash-safe backup recorded beside it and rebuilds the file from the
/// backup when it is missing, unreadable or clearly shorter. The microphone file output has reported a normal
/// finish after writing 2 s of a 40 min take, so a successful finish alone proves nothing.
enum AudioBackupCheck {
    struct Request {
        let audioURL: URL
        let format: SourceAudioFormat
        let stereoBitrate: Int
        /// Where the file starts on the take timeline, so a rebuilt file lines up like the original.
        let timelineStart: Double
    }

    enum Outcome: Equatable {
        case kept, rebuilt, noBackup, rebuildFailed
    }

    private static let toleratedShortfallSeconds = 3.0
    private static let toleratedShortfallShare = 0.05

    static func verify(_ request: Request) async -> Outcome {
        let name = request.audioURL.lastPathComponent
        let directory = TakeRecoveryFiles.audioSegments(audioURL: request.audioURL)
        let segments = AudioRecoverySegment.finished(in: directory)
        guard let first = segments.first, let last = segments.last else {
            CaptureLog.note("\(name): no backup to check the file against")
            return .noBackup
        }
        let backupSeconds = last.timelineSeconds - first.timelineSeconds + seconds(of: last.url)
        let fileSeconds = await MediaFileDuration.playable(.init(url: request.audioURL, mediaType: .audio))
        let summary = "\(name): file \(fileSeconds.map(format) ?? "unreadable") (\(await details(request.audioURL))), "
            + "backup \(format(backupSeconds)) in \(segments.count) segments"
        let allowed = max(toleratedShortfallSeconds, backupSeconds * toleratedShortfallShare)
        if let fileSeconds, backupSeconds - fileSeconds <= allowed {
            CaptureLog.note("\(summary); file kept")
            return .kept
        }
        CaptureLog.note("\(summary); rebuilding the file from the backup")
        return await rebuild(.init(request: request, directory: directory))
    }

    private struct RebuildRequest {
        let request: Request
        let directory: URL
    }

    private static func rebuild(_ rebuild: RebuildRequest) async -> Outcome {
        let audioURL = rebuild.request.audioURL
        let temporaryURL = audioURL.deletingLastPathComponent()
            .appendingPathComponent(".rebuilt-\(UUID().uuidString).\(audioURL.pathExtension)")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        let stitch = AudioRecoveryStitcher.Request(
            directory: rebuild.directory, outputURL: temporaryURL, format: rebuild.request.format,
            stereoBitrate: rebuild.request.stereoBitrate, timelineStart: rebuild.request.timelineStart
        )
        do {
            guard let result = try await Task.detached(priority: .userInitiated, operation: {
                try AudioRecoveryStitcher.stitch(stitch)
            }).value else {
                CaptureLog.note("\(audioURL.lastPathComponent): no backup segment could be read")
                return .rebuildFailed
            }
            try? FileManager.default.removeItem(at: audioURL)
            try FileManager.default.moveItem(at: temporaryURL, to: audioURL)
            CaptureLog.note(
                "\(audioURL.lastPathComponent): rebuilt \(format(result.timelineEnd - result.timelineStart)), "
                    + "\(format(result.silenceSeconds)) of gaps, \(result.unreadableSegments) unreadable segments"
            )
            return .rebuilt
        } catch {
            CaptureLog.note("\(audioURL.lastPathComponent): rebuild failed: \(error.localizedDescription)")
            return .rebuildFailed
        }
    }

    private static func seconds(of url: URL) -> Double {
        guard let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 else { return 0 }
        return Double(file.length) / file.fileFormat.sampleRate
    }

    private static func details(_ url: URL) async -> String {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber
        let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .audio).first
        let codec = (try? await track?.load(.formatDescriptions))?.first.map {
            fourCharacterCode(CMFormatDescriptionGetMediaSubType($0))
        }
        return "\(size?.int64Value ?? 0) bytes, codec \(codec ?? "none")"
    }

    private static func fourCharacterCode(_ code: FourCharCode) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }, encoding: .macOSRoman) ?? "\(code)"
    }

    private static func format(_ seconds: Double) -> String {
        String(format: "%.2f s", seconds)
    }
}
