import AVFoundation
import BlitzRecorderCore
import CoreGraphics
import Foundation

struct FinalVideoExportRequest {
    let take: RecordingTake
    let settings: RecordingSettings
    let sceneEvents: [RecordingSceneEvent]
    let backgroundMusic: ExportBackgroundMusic?
    let destinationURL: URL?
    let progressHandler: (@MainActor (Double) -> Void)?
    let timelineEdits: TimelineEdits
    var playbackRate: Double = 1.0

    init(
        take: RecordingTake,
        settings: RecordingSettings,
        sceneEvents: [RecordingSceneEvent],
        backgroundMusic: ExportBackgroundMusic?,
        destinationURL: URL?,
        progressHandler: (@MainActor (Double) -> Void)?,
        timelineEdits: TimelineEdits = .empty,
        playbackRate: Double = 1.0
    ) {
        self.take = take
        self.settings = settings
        self.sceneEvents = sceneEvents
        self.backgroundMusic = backgroundMusic
        self.destinationURL = destinationURL
        self.progressHandler = progressHandler
        self.timelineEdits = timelineEdits
        self.playbackRate = playbackRate
    }
}

enum Merger {
    static func exportFinalVideo(
        take: RecordingTake,
        settings: RecordingSettings,
        sceneEvents: [RecordingSceneEvent] = [],
        progressHandler: (@MainActor (Double) -> Void)? = nil
    ) async throws -> URL {
        try await exportFinalVideo(FinalVideoExportRequest(
            take: take,
            settings: settings,
            sceneEvents: sceneEvents,
            backgroundMusic: nil,
            destinationURL: nil,
            progressHandler: progressHandler
        ))
    }

    static func exportFinalVideo(
        _ request: FinalVideoExportRequest
    ) async throws -> URL {
        try Task.checkCancellation()
        let take = request.take
        let settings = request.settings
        let sceneEvents = request.sceneEvents
        let progressHandler = request.progressHandler
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: take.finalVideoURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let outputURL = request.destinationURL ?? TakeFileStore().uniqueFileURL(take.finalVideoURL)
        let outputDirectory = outputURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        let temporaryDirectory = outputDirectory.appendingPathComponent(
            ".blitzrecorder-export-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }
        let temporaryOutputURL = temporaryDirectory.appendingPathComponent(
            "recording.\(take.outputVideoFormat.fileExtension)"
        )

        let videoSources = try await availableVideoSources(for: take, settings: settings)
        guard !videoSources.isEmpty else {
            throw RecorderError.exportUnavailable
        }
        let sourceInputs = FinalExportPlanning.applyingTimelineTrim(
            FinalExportPlanning.TimelineTrimRequest(
                sources: videoSources.map(\.planningInput),
                offset: take.timelineTrimOffset
            )
        )
        let exportPlan = try FinalExportPlanning.plan(
            settings: settings,
            sceneEvents: sceneEvents,
            sources: sourceInputs,
            cuts: request.timelineEdits.enabledCuts,
            playbackRate: request.playbackRate
        )

        let composition = AVMutableComposition()
        let duration = exportPlan.duration
        let renderSize = exportPlan.renderSize

        var compositedSources: [CompositedVideoSource] = []
        for source in videoSources {
            let insertions = exportPlan.insertions(for: source.kind)
            guard let firstInsertion = insertions.first, let lastInsertion = insertions.last else { continue }
            guard let compositionTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw RecorderError.exportUnavailable
            }

            for insertion in insertions {
                try insertMappedTimeRange(
                    insertion,
                    of: source.track,
                    into: compositionTrack
                )
            }

            compositedSources.append(CompositedVideoSource(
                source: source,
                compositionTrack: compositionTrack,
                timeRange: CMTimeRange(
                    start: firstInsertion.compositionStart,
                    end: CMTimeRangeGetEnd(lastInsertion.timeRange)
                )
            ))
        }

        var expectedAudioSources = expectedAudioSources(for: take, settings: settings)
        for index in expectedAudioSources.indices where expectedAudioSources[index].source == .microphone {
            expectedAudioSources[index].url = try await VoiceCleanupProcessor.shared.processed(.init(
                url: expectedAudioSources[index].url, settings: settings.voiceCleanup))
        }
        var audioMixParameters: [AVMutableAudioMixInputParameters] = []
        for audioSource in expectedAudioSources {
            let parameters = try await addRequiredAudio(
                audioSource,
                to: composition,
                timeMap: exportPlan.timeMap
            )
            audioMixParameters.append(parameters)
        }
        if let backgroundMusic = request.backgroundMusic {
            let parameters = try await addBackgroundMusic(BackgroundMusicInsertionRequest(
                selection: backgroundMusic,
                composition: composition,
                duration: duration
            ))
            if settings.voiceCleanup.ducksMusic {
                var windows: [[SilenceWindow]] = []
                let audible = expectedAudioSources.filter { $0.volume > 0 }
                let microphone = audible.filter { $0.source == .microphone }
                for source in microphone.isEmpty ? audible : microphone {
                    let offset = source.activeTakeStart.seconds - source.sourceStart.seconds
                    let detected = try await SilenceDetection.cachedWindows(.init(audioURL: source.url,
                        takeDuration: exportPlan.takeDuration.seconds, sourceOffset: offset,
                        minimumSilence: 0.3, thresholdDB: -40, previousCuts: []))
                    windows.append(detected)
                }
                let combined = SilenceDetection.combinedWindows(windows)
                let ranges = MusicDucking.ranges(.init(windows: combined.sorted { $0.start < $1.start },
                    threshold: SilenceDetection.suggestedThreshold(combined), timeMap: exportPlan.timeMap))
                MusicDucking.apply(.init(parameters: parameters, ranges: ranges,
                    volume: Float(backgroundMusic.volume), duration: duration.seconds))
            }
            audioMixParameters.append(parameters)
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = metalVideoCompositionInstructions(.init(
            sources: compositedSources,
            renderSegments: exportPlan.renderSegments,
            settings: settings,
            edits: request.timelineEdits,
            timeMap: exportPlan.timeMap,
            cursorTrack: CursorPresentationTrack.load(.init(
                directory: take.scratchDirectory, trimOffset: take.timelineTrimOffset.seconds))
        ))
        videoComposition.customVideoCompositorClass = MetalExportVideoCompositor.self
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(settings.framesPerSecond))

        let outputFileType = take.outputVideoFormat.avFileType
        let audioMix: AVMutableAudioMix?
        if !audioMixParameters.isEmpty {
            let mix = AVMutableAudioMix()
            mix.inputParameters = audioMixParameters
            audioMix = mix
        } else {
            audioMix = nil
        }

        try Task.checkCancellation()
        await progressHandler?(0)
        if exportPlan.engine == .assetExportSession {
            try await exportWithAssetExportSession(
                composition: composition,
                videoComposition: videoComposition,
                audioMix: audioMix,
                outputURL: temporaryOutputURL,
                outputFileType: outputFileType,
                settings: settings,
                progressHandler: progressHandler
            )
        } else {
            try await OptimizedCompositionExporter.export(
                composition: composition,
                videoComposition: videoComposition,
                audioMix: audioMix,
                outputURL: temporaryOutputURL,
                outputFileType: outputFileType,
                renderSize: renderSize,
                settings: settings,
                duration: duration,
                progressHandler: progressHandler
            )
        }
        try await validateExpectedAudio(
            in: temporaryOutputURL,
            expectedAudioSources: expectedAudioSources
        )
        try Task.checkCancellation()
        await progressHandler?(1)
        try Task.checkCancellation()
        try fileManager.moveItem(at: temporaryOutputURL, to: outputURL)

        return outputURL
    }

    private static func exportWithAssetExportSession(
        composition: AVComposition,
        videoComposition: AVVideoComposition,
        audioMix: AVAudioMix?,
        outputURL: URL,
        outputFileType: AVFileType,
        settings: RecordingSettings,
        progressHandler: (@MainActor (Double) -> Void)?
    ) async throws {
        let presetName = settings.removesCameraBackgroundAfterRecording
            ? AVAssetExportPresetHighestQuality
            : AVAssetExportPresetHEVCHighestQuality
        guard let exporter = AVAssetExportSession(asset: composition, presetName: presetName) else {
            throw RecorderError.exportUnavailable
        }
        guard exporter.supportedFileTypes.contains(outputFileType) else {
            throw RecorderError.exportUnavailable
        }

        exporter.outputURL = outputURL
        exporter.outputFileType = outputFileType
        exporter.videoComposition = videoComposition
        exporter.audioMix = audioMix
        exporter.audioTimePitchAlgorithm = .spectral
        exporter.shouldOptimizeForNetworkUse = true

        let progressTask = Task { @MainActor in
            while !Task.isCancelled {
                progressHandler?(Double(exporter.progress))
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
        do {
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                try await exporter.export(to: outputURL, as: outputFileType)
            } onCancel: {
                exporter.cancelExport()
            }
            progressTask.cancel()
            await progressTask.value
        } catch {
            progressTask.cancel()
            await progressTask.value
            throw error
        }
    }

    private static func insertMappedTimeRange(
        _ insertion: FinalExportSourceInsertion,
        of sourceTrack: AVAssetTrack,
        into compositionTrack: AVMutableCompositionTrack
    ) throws {
        try insertMappedTimeRange(
            sourceStart: insertion.sourceStart,
            sourceDuration: insertion.sourceDuration,
            compositionStart: insertion.compositionStart,
            outputDuration: insertion.duration,
            of: sourceTrack,
            into: compositionTrack
        )
    }

    static func insertMappedTimeRange(
        _ insertion: TimelineMediaInsertion,
        of sourceTrack: AVAssetTrack,
        into compositionTrack: AVMutableCompositionTrack
    ) throws {
        try insertMappedTimeRange(
            sourceStart: insertion.sourceStart.cmTime,
            sourceDuration: insertion.sourceDuration.cmTime,
            compositionStart: insertion.compositionStart.cmTime,
            outputDuration: insertion.duration.cmTime,
            of: sourceTrack,
            into: compositionTrack
        )
    }

    private static func insertMappedTimeRange(
        sourceStart: CMTime,
        sourceDuration: CMTime,
        compositionStart: CMTime,
        outputDuration: CMTime,
        of sourceTrack: AVAssetTrack,
        into compositionTrack: AVMutableCompositionTrack
    ) throws {
        try compositionTrack.insertTimeRange(
            CMTimeRange(start: sourceStart, duration: sourceDuration),
            of: sourceTrack,
            at: compositionStart
        )
        guard CMTimeCompare(sourceDuration, outputDuration) != 0 else { return }
        compositionTrack.scaleTimeRange(
            CMTimeRange(start: compositionStart, duration: sourceDuration),
            toDuration: outputDuration
        )
    }
}
