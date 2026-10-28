import AVFoundation
import Foundation

struct VideoProjectImporter {
    struct Progress: Equatable, Sendable {
        let filename: String
        let stage: String
        let fraction: Double?
    }

    struct Request {
        let url: URL
        let settings: RecordingSettings
        let onProgress: @Sendable (Progress) async -> Void
    }

    struct Metadata: Codable {
        let originalFilename: String
        let initialTitle: String
        let width: Double
        let height: Double
        let framesPerSecond: Double
        let duration: Double

        static func load(for project: RecordingProject) -> Metadata? {
            let url = URL(fileURLWithPath: project.takeDirectoryPath).appendingPathComponent("import.json")
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(Self.self, from: data)
        }
    }

    func importVideo(_ request: Request) async throws -> RecordingProject {
        let sourceAccess = request.url.startAccessingSecurityScopedResource()
        defer { if sourceAccess { request.url.stopAccessingSecurityScopedResource() } }
        let filename = request.url.lastPathComponent
        await request.onProgress(.init(filename: filename, stage: "Checking video", fraction: nil))
        let probe = try await Self.probe(request.url)
        let (width, height, duration, rate) = (probe.width, probe.height, probe.duration, probe.framesPerSecond)
        var settings = Self.importSettings(.init(probe: probe, base: request.settings))
        settings.cameraContentMode = .fit
        settings.sceneLayout.cameraFrame = CGRect(x: 0, y: 0, width: 1, height: 1)
        settings.selectedScenePreset = .webcamFullscreen

        let libraryAccess = OutputDirectoryAccess(locations: [settings.sourceStorage])
        defer { libraryAccess.stop() }
        guard libraryAccess.hasSecurityScopedAccess else {
            throw RecorderError.outputDirectoryUnavailable(TakeFileStore.permissionRecoveryMessage(for: settings.sourceStorage.url))
        }
        let store = TakeFileStore()
        let directory = store.scratchRoot(for: settings).appendingPathComponent("Import-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(at: directory) } }
        try Task.checkCancellation()
        let sourceURL = request.url
        let bookmark = try sourceURL.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil, relativeTo: nil)
        var source = RecordingProject.SourceFile(role: "camera", path: sourceURL.path, exists: true, bookmarkData: bookmark)
        source.resolveExternalReference()
        let audioURL = directory.appendingPathComponent("audio.m4a")
        if probe.hasAudio {
            await request.onProgress(.init(filename: filename, stage: "Preparing audio", fraction: nil))
            try await Self.extractAudio(.init(asset: AVURLAsset(url: sourceURL), destination: audioURL, tracks: .all,
                                              skippedSeconds: 0, onFraction: { fraction in
                await request.onProgress(.init(filename: filename, stage: "Preparing audio", fraction: fraction))
            }))
        }
        try Task.checkCancellation()
        await request.onProgress(.init(filename: filename, stage: "Creating project", fraction: nil))
        try Task.checkCancellation()
        let title = request.url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let initialTitle = title.isEmpty ? "Imported video" : title
        let metadata = Metadata(originalFilename: filename, initialTitle: initialTitle, width: width, height: height,
                                framesPerSecond: rate.isFinite ? rate : 0, duration: duration)
        try JSONEncoder().encode(metadata).write(to: directory.appendingPathComponent("import.json"), options: .atomic)
        let take = RecordingTake(
            scratchDirectory: directory, screenURL: directory.appendingPathComponent("screen.mov"),
            cameraURL: sourceURL, audioURL: audioURL, systemAudioURL: directory.appendingPathComponent("system-audio.m4a"),
            transcriptURL: directory.appendingPathComponent("transcript.txt"),
            finalVideoURL: store.finalVideoURL(slug: initialTitle, settings: settings, outputFormat: .mp4),
            outputVideoFormat: .mp4, titleSlug: initialTitle, sourceReferences: [source])
        try store.writeSourceTakeManifest(for: take, settings: settings, finalVideoURL: nil)
        try store.writeRecordingProject(for: take, settings: settings,
            sceneEvents: [.init(time: 0, scene: RecordingScene(settings: settings))], finalVideoURL: nil)
        let project = try store.loadRecordingProject(at: take.projectURL)
        completed = true
        return project
    }

    /// What an imported file holds, checked before anything is written.
    struct Probe {
        let duration: Double
        let width: Double
        let height: Double
        let framesPerSecond: Double
        let hasAudio: Bool
    }

    static func probe(_ url: URL) async throws -> Probe {
        guard ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased()) else {
            throw RecorderError.mediaWriteFailed("Choose an MP4, MOV, or M4V video.")
        }
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable),
              let video = try await asset.loadTracks(withMediaType: .video).first else {
            throw RecorderError.mediaWriteFailed("\(url.lastPathComponent) has no playable video track.")
        }
        let duration = try await asset.load(.duration).seconds
        let size = try await video.load(.naturalSize)
        let transform = try await video.load(.preferredTransform)
        let bounds = CGRect(origin: .zero, size: size).applying(transform)
        let width = abs(bounds.width)
        let height = abs(bounds.height)
        guard duration.isFinite, duration > 0, width.isFinite, height.isFinite, width > 0, height > 0 else {
            throw RecorderError.mediaWriteFailed("\(url.lastPathComponent) has an invalid duration or frame size.")
        }
        let rate = Double(try await video.load(.nominalFrameRate))
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        return Probe(duration: duration, width: width, height: height,
                     framesPerSecond: rate.isFinite ? rate : 0, hasAudio: !audioTracks.isEmpty)
    }

    struct SettingsRequest {
        let probe: Probe
        let base: RecordingSettings
    }

    /// Fresh settings for a project made from a file: only where projects are kept comes from the app's settings,
    /// and the canvas, resolution and frame rate follow the file.
    static func importSettings(_ request: SettingsRequest) -> RecordingSettings {
        let probe = request.probe
        var settings = RecordingSettings()
        settings.outputDirectory = request.base.outputDirectory
        settings.outputDirectoryBookmarkData = request.base.outputDirectoryBookmarkData
        settings.projectLibrary = request.base.projectLibrary
        settings.additionalProjectLibraries = request.base.additionalProjectLibraries
        settings.outputVideoFormat = .mp4
        settings.enabledSources = probe.hasAudio ? [.camera, .microphone] : [.camera]
        settings.layout = abs(probe.width / probe.height - 1) < 0.05 ? .square : probe.width > probe.height ? .horizontal : .vertical
        settings.outputResolution = OutputResolution.allCases.last {
            Double($0.height) <= min(probe.width, probe.height) + 1
        } ?? .p720
        settings.framesPerSecond = probe.framesPerSecond > 0 ? max(1, Int(probe.framesPerSecond.rounded())) : 30
        return settings
    }

    struct AudioRequest {
        enum Tracks {
            /// Every audio track, mixed: a file's tracks are usually one recording split across channels.
            case all
            /// The first track only: an iPhone's second track is spatial audio of the same sound.
            case first
        }

        let asset: AVURLAsset
        let destination: URL
        let tracks: Tracks
        /// Leading seconds left out, for a file that started before the project's timeline.
        let skippedSeconds: Double
        let onFraction: @Sendable (Double) async -> Void
    }

    static func extractAudio(_ request: AudioRequest) async throws {
        let composition = AVMutableComposition()
        let allTracks = try await request.asset.loadTracks(withMediaType: .audio)
        let tracks = request.tracks == .first ? Array(allTracks.prefix(1)) : allTracks
        let skipped = CMTime(seconds: max(0, request.skippedSeconds), preferredTimescale: 48_000)
        for track in tracks {
            guard let destination = composition.addMutableTrack(withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid) else { throw RecorderError.writerNotReady }
            var range = try await track.load(.timeRange)
            if CMTimeCompare(skipped, .zero) > 0 {
                let start = CMTimeAdd(range.start, skipped)
                range = CMTimeRange(start: start, end: CMTimeMaximum(start, range.end))
            }
            try destination.insertTimeRange(range, of: track, at: CMTimeSubtract(range.start, skipped))
        }
        let compatible = await AVAssetExportSession.compatibility(ofExportPreset: AVAssetExportPresetPassthrough,
            with: composition, outputFileType: .m4a)
        guard let session = AVAssetExportSession(asset: composition,
            presetName: compatible && tracks.count == 1 ? AVAssetExportPresetPassthrough : AVAssetExportPresetAppleM4A) else {
            throw RecorderError.mediaWriteFailed("This video's audio could not be prepared for editing.")
        }
        let progress = Task {
            for await state in session.states(updateInterval: 0.25) {
                if case .exporting(let progress) = state { await request.onFraction(progress.fractionCompleted) }
            }
        }
        defer { progress.cancel() }
        try await withTaskCancellationHandler {
            try await session.export(to: request.destination, as: .m4a)
        } onCancel: {
            session.cancelExport()
        }
    }
}
