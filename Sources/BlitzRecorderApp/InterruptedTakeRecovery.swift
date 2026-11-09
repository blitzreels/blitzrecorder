import AVFoundation
import CoreMedia
import Foundation

/// Finds takes the app never finished saving and rebuilds each one as a new project. It works on copies in a
/// hidden folder, so a take's original files are never changed and an interrupted recovery simply starts over.
struct InterruptedTakeRecovery {
    enum Outcome: Equatable {
        case recovered(entry: RecordingProjectHistory.Entry, notes: [String])
        case failed(takeDirectory: URL, reason: String)
    }

    struct Request {
        let settings: RecordingSettings
    }

    private struct Marker: Codable {
        let date: Date
        let projectPath: String
        let notes: [String]
    }

    private struct Job {
        let folder: URL
        let root: URL
        let staging: URL
        let settings: RecordingSettings
        let journal: TakeRecoveryJournalContents
    }

    private struct SourceEnd {
        let name: String
        let end: Double
    }

    private struct RecoveredMedia {
        var enabledSources: Set<CaptureSource>
        var offsets: [CaptureSource: CMTime] = [:]
        var ends: [SourceEnd] = []
        var notes: [String] = []
        var hasVideo = false
        var hasAudio = false
    }

    private static let maximumAttempts = 3
    private static let reportedLossSeconds = 0.5
    private static let reportedSilenceSeconds = 0.25
    private static let projectFileName = "project.blitzrecorder.json"
    private static let manifestFileName = "take.json"

    private let store = TakeFileStore()

    func recoverAll(_ request: Request) async -> [Outcome] {
        var outcomes: [Outcome] = []
        for location in request.settings.projectLibraries {
            let access = OutputDirectoryAccess(locations: [location])
            defer { access.stop() }
            guard access.hasSecurityScopedAccess else { continue }
            var settings = request.settings
            settings.projectLibrary = location
            let root = store.scratchRoot(for: settings)
            let folders = (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            )) ?? []
            for folder in folders.sorted(by: { $0.path < $1.path }) {
                if let outcome = await recoverIfInterrupted(.init(folder: folder, root: root, settings: settings)) {
                    outcomes.append(outcome)
                }
            }
        }
        return outcomes
    }

    private struct Candidate {
        let folder: URL
        let root: URL
        let settings: RecordingSettings
    }

    private func recoverIfInterrupted(_ candidate: Candidate) async -> Outcome? {
        let folder = candidate.folder
        let fileManager = FileManager.default
        let journalURL = TakeRecoveryFiles.journal(takeDirectory: folder)
        guard fileManager.fileExists(atPath: journalURL.path),
              !fileManager.fileExists(atPath: TakeRecoveryFiles.recoveredMarker(takeDirectory: folder).path),
              let journal = try? TakeRecoveryJournalContents(url: journalURL),
              let lock = TakeRecoveryLock(.init(journalURL: journalURL, ownerProcessID: journal.processID)) else {
            return nil
        }
        defer { withExtendedLifetime(lock) {} }
        guard registerAttempt(folder: folder) else { return nil }
        let staging = candidate.root.appendingPathComponent(".recovering-\(folder.lastPathComponent)", isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }
        do {
            return try await recover(.init(
                folder: folder, root: candidate.root, staging: staging, settings: candidate.settings, journal: journal
            ))
        } catch {
            NSLog("Recovery of %@ failed: %@", folder.path, error.localizedDescription)
            return .failed(takeDirectory: folder, reason: error.recorderFailureDescription)
        }
    }

    private func registerAttempt(folder: URL) -> Bool {
        let url = TakeRecoveryFiles.attempts(takeDirectory: folder)
        let attempts = (try? String(contentsOf: url, encoding: .utf8)).flatMap { Int($0) } ?? 0
        guard attempts < Self.maximumAttempts else { return false }
        try? String(attempts + 1).write(to: url, atomically: true, encoding: .utf8)
        return true
    }

    private func recover(_ job: Job) async throws -> Outcome? {
        let fileManager = FileManager.default
        let original = try store.loadRecordingProject(at: job.folder.appendingPathComponent(Self.projectFileName))
        var settings = store.recordingSettings(
            from: original, baseSettings: job.settings, outputFormat: job.settings.outputVideoFormat
        )
        let originalTake = store.recordingTake(from: original, settings: settings, outputFormat: settings.outputVideoFormat)
        try? fileManager.removeItem(at: job.staging)
        try fileManager.createDirectory(at: job.staging, withIntermediateDirectories: true)
        try copyTakeFiles(job)
        let stagingTake = Self.relocated(.init(take: originalTake, directory: job.staging))

        var media = RecoveredMedia(enabledSources: settings.enabledSources)
        try await recoverAudio(.init(take: originalTake, stagingTake: stagingTake, settings: settings), into: &media)
        await checkVideo(stagingTake, into: &media)
        guard media.hasVideo else {
            guard media.hasAudio else { return nil }
            throw RecorderError.mediaWriteFailed("No video from this recording could be read.")
        }
        settings.enabledSources = media.enabledSources

        let directory = store.uniqueDirectory(job.root.appendingPathComponent("\(job.folder.lastPathComponent)-recovered", isDirectory: true))
        try fileManager.moveItem(at: job.staging, to: directory)
        do {
            var take = Self.relocated(.init(take: stagingTake, directory: directory))
            take.titleSlug = RecordingProjectDisplayTitle.isUntitled(original.title)
                ? "Recovered recording" : "\(original.title) (Recovered)"
            take.timelineTrimOffset = CMTime(seconds: max(0, job.journal.timelineTrimOffsetSeconds ?? 0), preferredTimescale: 600)
            take.sourceTimelineOffsets = media.offsets
            let events = store.sceneEvents(from: job.journal.sceneEvents.isEmpty ? original.sceneEvents : job.journal.sceneEvents)
            try store.writeSourceTakeManifest(for: take, settings: settings, finalVideoURL: nil)
            try store.writeRecordingProject(for: take, settings: settings, sceneEvents: events, finalVideoURL: nil)
            let notes = media.notes + Self.lossNotes(media.ends)
            let project = try store.loadRecordingProject(at: take.projectURL)
            try writeMarker(.init(date: Date(), projectPath: project.projectPath, notes: notes), folder: job.folder)
            store.hideRecoveredOriginal(.init(project: original, settings: job.settings))
            return .recovered(entry: .init(project), notes: notes)
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }

    private func copyTakeFiles(_ job: Job) throws {
        let skipped: Set<String> = ["recovery", Self.projectFileName, Self.manifestFileName]
        let items = try FileManager.default.contentsOfDirectory(at: job.folder, includingPropertiesForKeys: nil)
        for item in items where !skipped.contains(item.lastPathComponent) {
            try FileManager.default.copyItem(at: item, to: job.staging.appendingPathComponent(item.lastPathComponent))
        }
    }

    private func writeMarker(_ marker: Marker, folder: URL) throws {
        try TakeFileStore.projectEncoder().encode(marker)
            .write(to: TakeRecoveryFiles.recoveredMarker(takeDirectory: folder), options: .atomic)
    }

    private struct AudioJob {
        let take: RecordingTake
        let stagingTake: RecordingTake
        let settings: RecordingSettings
    }

    private struct StitchJob {
        let name: String
        let captureURL: URL
        let stagingURL: URL
        let settings: RecordingSettings
    }

    private struct StitchedAudio {
        let timelineOffset: CMTime
        let timelineEnd: Double
    }

    private func recoverAudio(_ job: AudioJob, into media: inout RecoveredMedia) async throws {
        let enabled = job.settings.enabledSources
        let system = try await stitch(.init(
            name: CaptureSource.systemAudio.rawValue, captureURL: job.take.systemAudioURL,
            stagingURL: job.stagingTake.systemAudioURL, settings: job.settings
        ), into: &media)
        note(.init(source: .systemAudio, audio: system, isEnabled: enabled.contains(.systemAudio)), into: &media)

        let microphone: StitchedAudio?
        if job.take.microphoneTrackFiles.isEmpty {
            microphone = try await stitch(.init(
                name: CaptureSource.microphone.rawValue, captureURL: job.take.audioURL,
                stagingURL: job.stagingTake.audioURL, settings: job.settings
            ), into: &media)
        } else {
            microphone = try await recoverMicrophoneTracks(job, into: &media)
        }
        note(.init(source: .microphone, audio: microphone, isEnabled: enabled.contains(.microphone)), into: &media)
    }

    private struct AudioNote {
        let source: CaptureSource
        let audio: StitchedAudio?
        let isEnabled: Bool
    }

    private func note(_ note: AudioNote, into media: inout RecoveredMedia) {
        if let audio = note.audio {
            media.hasAudio = true
            if CMTimeCompare(audio.timelineOffset, .zero) > 0 { media.offsets[note.source] = audio.timelineOffset }
        } else if note.isEnabled {
            media.enabledSources.remove(note.source)
            media.notes.append("\(note.source.rawValue) could not be recovered.")
        }
    }

    private func recoverMicrophoneTracks(_ job: AudioJob, into media: inout RecoveredMedia) async throws -> StitchedAudio? {
        var inputs: [MicrophoneMixdown.Input] = []
        var end = 0.0
        for (index, pair) in zip(job.take.microphoneTrackFiles, job.stagingTake.microphoneTrackFiles).enumerated() {
            guard let audio = try await stitch(.init(
                name: NumberedSourceTracks.microphones.displayName(index: index), captureURL: pair.0.url,
                stagingURL: pair.1.url, settings: job.settings
            ), into: &media) else { continue }
            inputs.append(.init(url: pair.1.url, timelineOffset: audio.timelineOffset))
            end = max(end, audio.timelineEnd)
        }
        guard let first = inputs.first else { return nil }
        try? FileManager.default.removeItem(at: job.stagingTake.audioURL)
        guard inputs.count > 1 else {
            try MicrophoneMixdown.copy(first.url, to: job.stagingTake.audioURL)
            return .init(timelineOffset: first.timelineOffset, timelineEnd: end)
        }
        let offset = try await MicrophoneMixdown.mix(.init(
            inputs: inputs, outputURL: job.stagingTake.audioURL, format: job.settings.effectiveSourceAudioFormat,
            bitrate: job.settings.finalAudioBitrate, onProgress: { _ in }
        ))
        return .init(timelineOffset: offset, timelineEnd: end)
    }

    /// Prefers the finished segments. Without any, a copied file is kept only if it is complete enough to play.
    private func stitch(_ job: StitchJob, into media: inout RecoveredMedia) async throws -> StitchedAudio? {
        let fileManager = FileManager.default
        let temporaryURL = job.stagingURL.deletingLastPathComponent()
            .appendingPathComponent(".stitched-\(UUID().uuidString).\(job.stagingURL.pathExtension)")
        defer { try? fileManager.removeItem(at: temporaryURL) }
        let format: SourceAudioFormat = job.stagingURL.pathExtension == SourceAudioFormat.wav.fileExtension ? .wav : .aac
        if let result = try AudioRecoveryStitcher.stitch(.init(
            directory: TakeRecoveryFiles.audioSegments(audioURL: job.captureURL), outputURL: temporaryURL,
            format: format, stereoBitrate: job.settings.finalAudioBitrate
        )) {
            try? fileManager.removeItem(at: job.stagingURL)
            try fileManager.moveItem(at: temporaryURL, to: job.stagingURL)
            media.ends.append(.init(name: job.name, end: result.timelineEnd))
            if result.silenceSeconds >= Self.reportedSilenceSeconds {
                media.notes.append("\(job.name) has \(Self.seconds(result.silenceSeconds)) of silence where sound could not be saved.")
            }
            if result.unreadableSegments > 0 {
                media.notes.append("\(job.name) lost \(result.unreadableSegments) damaged audio segment(s).")
            }
            return .init(
                timelineOffset: CMTime(seconds: result.timelineStart, preferredTimescale: 48_000),
                timelineEnd: result.timelineEnd
            )
        }
        guard let duration = await Self.playableDuration(.init(url: job.stagingURL, mediaType: .audio)) else {
            try? fileManager.removeItem(at: job.stagingURL)
            return nil
        }
        media.ends.append(.init(name: job.name, end: duration))
        return .init(timelineOffset: .zero, timelineEnd: duration)
    }

    private func checkVideo(_ take: RecordingTake, into media: inout RecoveredMedia) async {
        let enabled = media.enabledSources
        var sources: [(name: String, url: URL, source: CaptureSource?)] = [
            (CaptureSource.screen.rawValue, take.screenURL, .screen),
            (CaptureSource.camera.rawValue, take.cameraURL, .camera)
        ]
        sources += take.cameraAngleFiles.enumerated().map {
            (NumberedSourceTracks.cameraAngles.displayName(index: $0.offset), $0.element.url, nil)
        }
        for item in sources {
            if let duration = await Self.playableDuration(.init(url: item.url, mediaType: .video)) {
                media.hasVideo = true
                media.ends.append(.init(name: item.name, end: duration))
                continue
            }
            let wasRecorded = FileManager.default.fileExists(atPath: item.url.path)
            try? FileManager.default.removeItem(at: item.url)
            if let source = item.source, enabled.contains(source) {
                media.enabledSources.remove(source)
                media.notes.append("\(item.name) could not be recovered.")
            } else if item.source == nil, wasRecorded {
                media.notes.append("\(item.name) could not be recovered.")
            }
        }
    }

    private struct PlayableRequest {
        let url: URL
        let mediaType: AVMediaType
    }

    private static func playableDuration(_ request: PlayableRequest) async -> Double? {
        guard FileManager.default.fileExists(atPath: request.url.path) else { return nil }
        let asset = AVURLAsset(url: request.url)
        guard let tracks = try? await asset.loadTracks(withMediaType: request.mediaType), !tracks.isEmpty,
              let (isPlayable, duration) = try? await asset.load(.isPlayable, .duration),
              isPlayable, duration.isNumeric, duration.seconds > 0 else { return nil }
        return duration.seconds
    }

    private static func lossNotes(_ ends: [SourceEnd]) -> [String] {
        guard let takeEnd = ends.map(\.end).max() else { return [] }
        return ends.filter { takeEnd - $0.end >= reportedLossSeconds }.map {
            "\($0.name) stops \(seconds(takeEnd - $0.end)) before the end."
        }
    }

    private static func seconds(_ value: Double) -> String {
        value < 60 ? "\(max(1, Int(value.rounded()))) s" : ClockDuration.label(value)
    }

    private struct Relocation {
        let take: RecordingTake
        let directory: URL
    }

    private static func relocated(_ relocation: Relocation) -> RecordingTake {
        let take = relocation.take
        let moved = { (url: URL) in relocation.directory.appendingPathComponent(url.lastPathComponent) }
        let movedTracks = { (files: [SourceTrackFile]) in files.map { SourceTrackFile(role: $0.role, url: moved($0.url)) } }
        var result = RecordingTake(
            scratchDirectory: relocation.directory, screenURL: moved(take.screenURL), cameraURL: moved(take.cameraURL),
            audioURL: moved(take.audioURL), systemAudioURL: moved(take.systemAudioURL), transcriptURL: moved(take.transcriptURL),
            finalVideoURL: take.finalVideoURL, outputVideoFormat: take.outputVideoFormat, titleSlug: take.titleSlug
        )
        result.cameraAngleFiles = movedTracks(take.cameraAngleFiles)
        result.microphoneTrackFiles = movedTracks(take.microphoneTrackFiles)
        return result
    }
}
