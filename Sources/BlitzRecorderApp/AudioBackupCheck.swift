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

/// Builds a finished audio file from the crash-safe backup recorded beside it, which places every segment by its
/// sample timestamps. Both audio file writers join the samples on both sides of a stall, so a stall of any length
/// moves the sound early against the video for the rest of the take, and the microphone file output has reported
/// a normal finish after writing 2 s of a 40 min take. So the file is built from a complete backup after every
/// take, with silence where audio was lost; the writer's file is kept only when the backup itself missed audio
/// and the file is not visibly worse.
enum AudioBackupCheck {
    struct Request {
        let audioURL: URL
        let format: SourceAudioFormat
        let stereoBitrate: Int
        /// Where the file starts on the take timeline, so a rebuilt file lines up like the original.
        let timelineStart: Double
        let backup: AudioRecoverySegmentWriter.Report
    }

    enum Outcome: Equatable {
        /// Built from a backup that matched the file: the usual end of a take.
        case built
        /// Built from the backup because the file lost audio; the backup is kept beside the take.
        case rebuilt(String)
        case kept(String)
        case noBackup
        case rebuildFailed

        var replacedFile: Bool {
            switch self {
            case .built, .rebuilt: return true
            case .kept, .noBackup, .rebuildFailed: return false
            }
        }
    }

    struct Span: Equatable {
        let start: Double
        let duration: Double
        var end: Double { start + duration }
    }

    struct Gap: Equatable {
        let at: Double
        let seconds: Double
    }

    struct Evidence {
        let fileSeconds: Double?
        let backup: [Span]
        let backupIsComplete: Bool
    }

    enum Decision: Equatable {
        case keep(String)
        /// The file and the backup agree; the file is still built from the backup so it follows the timestamps.
        case build
        case rebuild(String)
    }

    /// The file and its backup start and stop a few hundredths apart, and a microphone clock can run up to about
    /// 100 ppm off the system clock, so a file that is only a little shorter with no hole in the backup is kept.
    private static let toleratedShortfallSeconds = 0.25
    private static let toleratedClockShare = 0.0001

    /// Holes between backup segments, where the source delivered no samples while recording.
    static func gaps(_ backup: [Span]) -> [Gap] {
        zip(backup, backup.dropFirst()).compactMap { previous, next in
            let hole = next.start - previous.end
            return hole > AudioSampleContinuity.toleratedJumpSeconds ? Gap(at: previous.end, seconds: hole) : nil
        }
    }

    static func decide(_ evidence: Evidence) -> Decision {
        guard let first = evidence.backup.first, let last = evidence.backup.last else { return .keep("no backup") }
        guard let fileSeconds = evidence.fileSeconds else { return .rebuild("the file is unreadable") }
        let backupSeconds = last.end - first.start
        let shortfall = backupSeconds - fileSeconds
        let tolerance = toleratedShortfallSeconds + backupSeconds * toleratedClockShare
        let lost = gaps(evidence.backup).reduce(0) { $0 + $1.seconds }
        if lost > 0, shortfall > lost / 2 {
            return .rebuild(String(format: "%.2f s of samples missing mid-take", lost))
        }
        if shortfall > tolerance {
            return .rebuild(String(format: "the file is %.2f s shorter than the backup", shortfall))
        }
        guard evidence.backupIsComplete else { return .keep("the backup missed audio") }
        guard shortfall >= -tolerance else {
            return .keep(String(format: "the backup is %.2f s shorter than the file", -shortfall))
        }
        return .build
    }

    static func verify(_ request: Request) async -> Outcome {
        let name = request.audioURL.lastPathComponent
        let directory = TakeRecoveryFiles.audioSegments(audioURL: request.audioURL)
        let segments = AudioRecoverySegment.finished(in: directory)
        guard !segments.isEmpty else {
            CaptureLog.note("\(name): no backup to check the file against")
            return .noBackup
        }
        let backup = segments.map { Span(start: $0.timelineSeconds, duration: seconds(of: $0.url)) }
        let fileSeconds = await MediaFileDuration.playable(.init(url: request.audioURL, mediaType: .audio))
        let backupSeconds = (backup.last?.end ?? 0) - (backup.first?.start ?? 0)
        let holes = gaps(backup)
        let summary = "\(name): file \(fileSeconds.map(format) ?? "unreadable") (\(await details(request.audioURL))), "
            + "backup \(format(backupSeconds)) in \(segments.count) segments"
            + (holes.isEmpty ? "" : ", holes " + holes.prefix(5).map {
                String(format: "%.2f s at %.2f s", $0.seconds, $0.at)
            }.joined(separator: ", ") + (holes.count > 5 ? " and \(holes.count - 5) more" : ""))
        let outcome: Outcome
        switch decide(.init(fileSeconds: fileSeconds, backup: backup, backupIsComplete: request.backup.isComplete)) {
        case .keep(let reason):
            let lost = request.backup.isComplete ? "" : String(
                format: ", backup missed %.2f s in %d chunks", request.backup.lostSeconds, request.backup.lostChunks
            )
            CaptureLog.note("\(summary)\(lost); file kept: \(reason)")
            outcome = .kept(reason)
        case .build:
            CaptureLog.note("\(summary); building the file from the timestamped backup")
            outcome = await rebuild(.init(request: request, directory: directory)) ? .built : .rebuildFailed
        case .rebuild(let reason):
            CaptureLog.note("\(summary); \(reason), rebuilding the file from the backup, which is kept")
            TakeRecoveryFiles.keepAudioSegments(.init(directory: directory, reason: reason))
            outcome = await rebuild(.init(request: request, directory: directory)) ? .rebuilt(reason) : .rebuildFailed
        }
        journal(.init(audioURL: request.audioURL, outcome: outcome, holes: holes))
        return outcome
    }

    private struct JournalRequest {
        let audioURL: URL
        let outcome: Outcome
        let holes: [Gap]
    }

    private static func journal(_ request: JournalRequest) {
        let record = { (kind: TakeSyncJournal.Event.Kind, at: Double?, seconds: Double?, detail: String?) in
            TakeSyncJournal.record(.init(trackURL: request.audioURL, kind: kind, at: at, seconds: seconds, detail: detail))
        }
        for hole in request.holes { record(.audioGap, hole.at, hole.seconds, nil) }
        switch request.outcome {
        case .built: record(.audioBuilt, nil, nil, nil)
        case .rebuilt(let reason): record(.audioRebuilt, nil, nil, reason)
        case .kept(let reason): record(.audioKept, nil, nil, reason)
        case .rebuildFailed: record(.audioRebuildFailed, nil, nil, nil)
        case .noBackup: break
        }
    }

    private struct RebuildRequest {
        let request: Request
        let directory: URL
    }

    private static func rebuild(_ rebuild: RebuildRequest) async -> Bool {
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
                return false
            }
            try? FileManager.default.removeItem(at: audioURL)
            try FileManager.default.moveItem(at: temporaryURL, to: audioURL)
            CaptureLog.note(
                "\(audioURL.lastPathComponent): rebuilt \(format(result.timelineEnd - result.timelineStart)), "
                    + "\(format(result.silenceSeconds)) of gaps, \(result.unreadableSegments) unreadable segments"
            )
            return true
        } catch {
            CaptureLog.note("\(audioURL.lastPathComponent): rebuild failed: \(error.localizedDescription)")
            return false
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
