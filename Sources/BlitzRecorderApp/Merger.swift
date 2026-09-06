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
        let temporaryOutputURL = outputDirectory.appendingPathComponent(
            ".blitzrecorder-export-\(UUID().uuidString).\(take.outputVideoFormat.fileExtension)"
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
            sources: sourceInputs
        )

        let composition = AVMutableComposition()
        let duration = exportPlan.duration
        let renderSize = exportPlan.renderSize

        var compositedSources: [CompositedVideoSource] = []
        for source in videoSources {
            guard let insertion = exportPlan.insertion(for: source.kind) else { continue }
            guard let compositionTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw RecorderError.exportUnavailable
            }

            try compositionTrack.insertTimeRange(
                CMTimeRange(start: insertion.sourceStart, duration: insertion.duration),
                of: source.track,
                at: insertion.compositionStart
            )

            compositedSources.append(CompositedVideoSource(
                source: source,
                compositionTrack: compositionTrack,
                timeRange: CMTimeRange(start: insertion.compositionStart, duration: insertion.duration)
            ))
        }

        let expectedAudioSources = expectedAudioSources(for: take, settings: settings)
        var audioMixParameters: [AVMutableAudioMixInputParameters] = []
        for audioSource in expectedAudioSources {
            let parameters = try await addRequiredAudio(
                audioSource,
                to: composition,
                duration: duration
            )
            audioMixParameters.append(parameters)
        }
        if let backgroundMusic = request.backgroundMusic {
            let parameters = try await addBackgroundMusic(BackgroundMusicInsertionRequest(
                selection: backgroundMusic,
                composition: composition,
                duration: duration
            ))
            audioMixParameters.append(parameters)
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = metalVideoCompositionInstructions(
            sources: compositedSources,
            renderSegments: exportPlan.renderSegments,
            settings: settings
        )
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

        do {
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
        } catch {
            try? fileManager.removeItem(at: temporaryOutputURL)
            throw error
        }

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

    private static func availableVideoSources(for take: RecordingTake, settings: RecordingSettings) async throws -> [VideoSource] {
        var sources: [VideoSource] = []
        let capturedSources = settings.enabledSources
        let screenAsset = capturedSources.contains(.screen) ? await readableVideoAsset(kind: "screen", url: take.screenURL) : nil
        let cameraAsset = capturedSources.contains(.camera) ? await readableVideoAsset(kind: "camera", url: take.cameraURL) : nil
        let hasScreen = screenAsset != nil
        let hasCamera = cameraAsset != nil
        let dimensions = ScreenCaptureGeometry.outputDimensions(for: settings)
        let renderSize = CGSize(width: dimensions.width, height: dimensions.height)
        let fullCanvasTargetRect = paddedFullCanvasTargetRect(renderSize: renderSize, settings: settings)

        for layer in settings.sceneLayout.layerOrder {
            switch layer {
            case .screen:
                guard let screenAsset else { continue }
                let targetRect = hasCamera
                    ? targetRect(for: .screen, settings: settings, renderSize: renderSize)
                    : fullCanvasTargetRect
                sources.append(try await VideoSource(
                    kind: .screen,
                    asset: screenAsset.asset,
                    track: screenAsset.track,
                    duration: screenAsset.duration,
                    targetRect: targetRect
                ))
            case .camera:
                guard let cameraAsset else { continue }
                let targetRect = hasScreen
                    ? targetRect(for: .camera, settings: settings, renderSize: renderSize)
                    : fullCanvasTargetRect
                let processedTiming = await processedLocalCameraTiming(
                    visibleCameraURL: take.cameraURL,
                    preservesPositiveOffset: hasScreen
                )
                sources.append(try await VideoSource(
                    kind: .camera,
                    asset: cameraAsset.asset,
                    track: cameraAsset.track,
                    duration: cameraAsset.duration,
                    targetRect: targetRect,
                    sourceCropAmount: settings.cameraCropAmount,
                    sourceCropPosition: settings.cameraCropPosition,
                    timelineOffset: processedTiming?.timelineOffset ?? cameraTimelineOffset(
                        for: take.cameraURL,
                        preservesPositiveOffset: hasScreen,
                        screenDuration: screenAsset?.duration,
                        cameraDuration: cameraAsset.duration
                    ),
                    sourceStartOffset: processedTiming?.sourceStartOffset ?? .zero
                ))
            }
        }

        return sources
    }

    private static func processedLocalCameraTiming(
        visibleCameraURL: URL,
        preservesPositiveOffset: Bool
    ) async -> (timelineOffset: CMTime, sourceStartOffset: CMTime)? {
        guard preservesPositiveOffset,
              visibleCameraURL.lastPathComponent.contains("background-removed"),
              let rawCameraURL = rawCameraURL(forProcessedCameraURL: visibleCameraURL),
              FileManager.default.fileExists(atPath: rawCameraURL.path),
              let rawStart = await leadingEmptyVideoDuration(in: rawCameraURL),
              CMTimeCompare(rawStart, .zero) > 0 else {
            return nil
        }
        let start = CMTimeConvertScale(rawStart, timescale: 600, method: .roundHalfAwayFromZero)
        return (timelineOffset: start, sourceStartOffset: start)
    }

    private static func rawCameraURL(forProcessedCameraURL url: URL) -> URL? {
        let baseName = url.deletingPathExtension().lastPathComponent
        guard baseName.hasSuffix("-background-removed") else { return nil }
        let rawBaseName = String(baseName.dropLast("-background-removed".count))
        guard !rawBaseName.isEmpty else { return nil }
        return url
            .deletingLastPathComponent()
            .appendingPathComponent(rawBaseName)
            .appendingPathExtension(url.pathExtension.isEmpty ? "mov" : url.pathExtension)
    }

    private static func leadingEmptyVideoDuration(in url: URL) async -> CMTime? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else {
            return nil
        }
        guard let firstSegment = try? await track.load(.segments).first,
              firstSegment.isEmpty,
              firstSegment.timeMapping.target.duration.isValid else {
            return nil
        }
        return firstSegment.timeMapping.target.duration
    }

    private static func readableVideoAsset(kind: String, url: URL) async -> ReadableVideoAsset? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                return nil
            }
            return ReadableVideoAsset(
                asset: asset,
                track: track,
                duration: try await asset.load(.duration)
            )
        } catch {
            NSLog("Skipping unreadable \(kind) file \(url.path): \(error.localizedDescription)")
            return nil
        }
    }

    private static func cameraTimelineOffset(
        for cameraURL: URL,
        preservesPositiveOffset: Bool,
        screenDuration: CMTime?,
        cameraDuration: CMTime
    ) -> CMTime {
        if let manifestOffset = remoteCameraTimelineOffset(
            for: cameraURL,
            preservesPositiveOffset: preservesPositiveOffset
        ) {
            return manifestOffset
        }
        return inferredLegacyLocalCameraStartupOffset(
            screenDuration: screenDuration,
            cameraDuration: cameraDuration
        )
    }

    private static func remoteCameraTimelineOffset(
        for cameraURL: URL,
        preservesPositiveOffset: Bool
    ) -> CMTime? {
        guard let manifest = remoteCameraManifest(for: cameraURL),
              let timelineStartTime = manifest.hostTimelineStartTime,
              let cameraStartTime = manifest.estimatedHostStartTime ?? manifest.hostStartTime else {
            return nil
        }
        let deltaNanoseconds: Int64
        if cameraStartTime >= timelineStartTime {
            deltaNanoseconds = Int64(min(cameraStartTime - timelineStartTime, UInt64(Int64.max)))
        } else {
            deltaNanoseconds = -Int64(min(timelineStartTime - cameraStartTime, UInt64(Int64.max)))
        }
        let offset = CMTimeConvertScale(
            CMTime(value: deltaNanoseconds, timescale: 1_000_000_000),
            timescale: 600,
            method: .roundHalfAwayFromZero
        )
        if preservesPositiveOffset || CMTimeCompare(offset, .zero) <= 0 {
            return offset
        }
        return .zero
    }

    private static func inferredLegacyLocalCameraStartupOffset(
        screenDuration: CMTime?,
        cameraDuration: CMTime
    ) -> CMTime {
        guard let screenDuration,
              screenDuration.isValid,
              cameraDuration.isValid,
              CMTimeCompare(screenDuration, cameraDuration) > 0 else {
            return .zero
        }
        let offset = CMTimeSubtract(screenDuration, cameraDuration)
        let minimumOffset = CMTime(seconds: 0.1, preferredTimescale: 600)
        let maximumOffset = CMTime(seconds: 2, preferredTimescale: 600)
        guard CMTimeCompare(offset, minimumOffset) >= 0,
              CMTimeCompare(offset, maximumOffset) <= 0 else {
            return .zero
        }
        return CMTimeConvertScale(offset, timescale: 600, method: .roundHalfAwayFromZero)
    }

    private static func remoteCameraManifest(for cameraURL: URL) -> RemoteCameraTransferManifest? {
        let decoder = JSONDecoder()
        for url in remoteCameraManifestCandidates(for: cameraURL) {
            guard let data = try? Data(contentsOf: url),
                  let manifest = try? decoder.decode(RemoteCameraTransferManifest.self, from: data) else {
                continue
            }
            return manifest
        }
        return nil
    }

    private static func remoteCameraManifestCandidates(for cameraURL: URL) -> [URL] {
        let expected = cameraURL
            .deletingPathExtension()
            .appendingPathExtension("remote-camera-manifest.json")
        var candidates = [expected]
        let directory = cameraURL.deletingLastPathComponent()
        if let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) {
            candidates.append(contentsOf: urls.filter {
                $0.lastPathComponent.hasSuffix(".remote-camera-manifest.json")
                    && $0 != expected
            })
        }
        return candidates
    }

    private static func paddedFullCanvasTargetRect(renderSize: CGSize, settings: RecordingSettings) -> CGRect {
        let canvas = CGRect(origin: .zero, size: renderSize)
        return SceneLayoutProjection.padded(canvas, in: canvas, padding: settings.canvasPadding)
    }

    private static func expectedAudioSources(for take: RecordingTake, settings: RecordingSettings) -> [ExpectedAudioSource] {
        var sources: [ExpectedAudioSource] = []
        let sourceStart = { source in
            let sourceTimelineOffset = take.sourceTimelineOffsets[source] ?? .zero
            let offset = CMTimeSubtract(take.timelineTrimOffset, sourceTimelineOffset)
            return CMTimeCompare(offset, .zero) > 0 ? offset : .zero
        }
        if settings.enabledSources.contains(.microphone) {
            sources.append(ExpectedAudioSource(
                source: .microphone,
                url: take.audioURL,
                volume: Float(settings.microphoneGain),
                sourceStart: sourceStart(.microphone)
            ))
        }
        if settings.enabledSources.contains(.systemAudio) {
            sources.append(ExpectedAudioSource(
                source: .systemAudio,
                url: take.systemAudioURL,
                volume: Float(settings.systemAudioGain),
                sourceStart: sourceStart(.systemAudio)
            ))
        }
        return sources
    }

    private static func addRequiredAudio(
        _ audioSource: ExpectedAudioSource,
        to composition: AVMutableComposition,
        duration: CMTime
    ) async throws -> AVMutableAudioMixInputParameters {
        guard FileManager.default.fileExists(atPath: audioSource.url.path) else {
            throw missingExpectedAudio(audioSource, reason: "file was not created")
        }
        let values = try audioSource.url.resourceValues(forKeys: [.fileSizeKey])
        guard (values.fileSize ?? 0) > 0 else {
            throw missingExpectedAudio(audioSource, reason: "file is empty")
        }

        let asset = AVURLAsset(url: audioSource.url)
        let audioTracks: [AVAssetTrack]
        let audioDuration: CMTime
        do {
            audioTracks = try await asset.loadTracks(withMediaType: .audio)
            audioDuration = try await asset.load(.duration)
        } catch {
            throw missingExpectedAudio(audioSource, reason: "file is unreadable: \(error.localizedDescription)")
        }

        guard let audioTrack = audioTracks.first,
              audioDuration.isValid,
              CMTimeCompare(audioDuration, .zero) > 0,
              let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            throw missingExpectedAudio(audioSource, reason: "file has no readable audio samples")
        }

        let remainingAudioDuration = CMTimeSubtract(audioDuration, audioSource.sourceStart)
        let insertDuration = CMTimeMinimum(duration, remainingAudioDuration)
        guard CMTimeCompare(insertDuration, .zero) > 0 else {
            throw missingExpectedAudio(audioSource, reason: "file ends before the synchronized timeline starts")
        }
        try compositionAudioTrack.insertTimeRange(
            CMTimeRange(start: audioSource.sourceStart, duration: insertDuration),
            of: audioTrack,
            at: .zero
        )

        let parameters = AVMutableAudioMixInputParameters(track: compositionAudioTrack)
        parameters.setVolume(max(0, min(2, audioSource.volume)), at: .zero)
        return parameters
    }

    private static func addBackgroundMusic(
        _ request: BackgroundMusicInsertionRequest
    ) async throws -> AVMutableAudioMixInputParameters {
        let asset = AVURLAsset(url: request.selection.url)
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            throw RecorderError.mediaWriteFailed(
                "Background music is unreadable: \(error.localizedDescription)"
            )
        }
        guard let audioTrack = tracks.first,
              let compositionTrack = request.composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            throw RecorderError.mediaWriteFailed("Background music has no readable audio track.")
        }
        let trackTimeRange = try await audioTrack.load(.timeRange)
        guard trackTimeRange.duration.isValid,
              CMTimeCompare(trackTimeRange.duration, .zero) > 0 else {
            throw RecorderError.mediaWriteFailed("Background music has no playable duration.")
        }

        var insertionTime = CMTime.zero
        while CMTimeCompare(insertionTime, request.duration) < 0 {
            let remaining = CMTimeSubtract(request.duration, insertionTime)
            let clipDuration = CMTimeMinimum(trackTimeRange.duration, remaining)
            try compositionTrack.insertTimeRange(
                CMTimeRange(start: trackTimeRange.start, duration: clipDuration),
                of: audioTrack,
                at: insertionTime
            )
            insertionTime = CMTimeAdd(insertionTime, clipDuration)
        }

        let parameters = AVMutableAudioMixInputParameters(track: compositionTrack)
        let volume = Float(min(1, max(0, request.selection.volume)))
        parameters.setVolume(volume, at: .zero)
        let fadeDuration = CMTimeMinimum(
            request.duration,
            CMTime(seconds: 0.75, preferredTimescale: 600)
        )
        let fadeStart = CMTimeSubtract(request.duration, fadeDuration)
        parameters.setVolumeRamp(
            fromStartVolume: volume,
            toEndVolume: 0,
            timeRange: CMTimeRange(start: fadeStart, duration: fadeDuration)
        )
        return parameters
    }

    private static func validateExpectedAudio(
        in outputURL: URL,
        expectedAudioSources: [ExpectedAudioSource]
    ) async throws {
        guard !expectedAudioSources.isEmpty else { return }

        let asset = AVURLAsset(url: outputURL)
        let audioTracks: [AVAssetTrack]
        do {
            audioTracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            throw RecorderError.mediaWriteFailed(
                "Final export could not verify expected audio: \(error.localizedDescription)"
            )
        }

        guard !audioTracks.isEmpty else {
            throw RecorderError.mediaWriteFailed(
                "Final export is missing expected \(audioSourceList(expectedAudioSources)) audio."
            )
        }

        let minimumDuration = CMTime(seconds: 0.05, preferredTimescale: 600)
        for track in audioTracks {
            if let timeRange = try? await track.load(.timeRange),
               timeRange.duration.isValid,
               CMTimeCompare(timeRange.duration, minimumDuration) >= 0 {
                return
            }
        }

        throw RecorderError.mediaWriteFailed(
            "Final export contains an audio track, but it is too short to trust."
        )
    }

    private static func missingExpectedAudio(_ source: ExpectedAudioSource, reason: String) -> RecorderError {
        .mediaWriteFailed("\(source.displayName) audio was expected, but \(reason).")
    }

    private static func audioSourceList(_ sources: [ExpectedAudioSource]) -> String {
        sources.map(\.displayName).joined(separator: " and ")
    }

    private static func targetRect(
        for kind: SceneLayerKind,
        settings: RecordingSettings,
        renderSize: CGSize
    ) -> CGRect {
        SceneRenderGeometry(
            canvas: CGRect(origin: .zero, size: renderSize),
            scene: RecordingScene(settings: settings),
            origin: .upperLeft
        )
        .targetRect(for: kind)
    }

    private static func videoCompositionInstructions(
        sources: [CompositedVideoSource],
        renderSize: CGSize,
        renderSegments: [FinalExportRenderSegment]
    ) -> [AVMutableVideoCompositionInstruction] {
        renderSegments.enumerated().map { index, segment in
            let endScene = renderSegments.indices.contains(index + 1)
                ? renderSegments[index + 1].scene
                : segment.scene
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = segment.timeRange
            instruction.layerInstructions = layerInstructions(
                sources: sources,
                startScene: segment.scene,
                endScene: endScene,
                activeLayerOrder: segment.activeLayerOrder,
                renderSize: renderSize,
                timeRange: segment.timeRange
            ).reversed()
            instruction.backgroundColor = segment.scene.canvasBackgroundStyle.appearance.solidCGColor
            return instruction
        }
    }

    private static func metalVideoCompositionInstructions(
        sources: [CompositedVideoSource],
        renderSegments: [FinalExportRenderSegment],
        settings: RecordingSettings
    ) -> [MetalExportInstruction] {
        let sourceDescriptors = sources.map {
            MetalExportSourceDescriptor(
                kind: $0.kind,
                trackID: $0.compositionTrack.trackID,
                preferredTransform: $0.preferredTransform
            )
        }
        return renderSegments.map { segment in
            MetalExportInstruction(MetalExportInstructionRequest(
                timeRange: segment.timeRange,
                scene: segment.scene,
                settings: settings,
                activeLayerOrder: segment.activeLayerOrder,
                sourceDescriptors: sourceDescriptors
            ))
        }
    }

    private static func layerInstructions(
        sources: [CompositedVideoSource],
        startScene: RecordingScene,
        endScene: RecordingScene,
        activeLayerOrder: [SceneLayerKind],
        renderSize: CGSize,
        timeRange: CMTimeRange
    ) -> [AVMutableVideoCompositionLayerInstruction] {
        let startGeometry = SceneRenderGeometry(
            canvas: CGRect(origin: .zero, size: renderSize),
            scene: startScene,
            origin: .upperLeft
        )
        let endGeometry = SceneRenderGeometry(
            canvas: CGRect(origin: .zero, size: renderSize),
            scene: endScene,
            origin: .upperLeft
        )
        return activeLayerOrder.compactMap { kind -> AVMutableVideoCompositionLayerInstruction? in
            guard let source = sources.first(where: { $0.kind == kind && $0.isActive(during: timeRange) }) else {
                return nil
            }
            let startPlacement = startGeometry.videoPlacement(for: kind)
            let endPlacement = endGeometry.videoPlacement(for: kind)
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: source.compositionTrack)
            let startCropRectangle = startPlacement.pixelAlignedOrientedCropRectangle(
                naturalSize: source.naturalSize,
                preferredTransform: source.preferredTransform
            )
            let endCropRectangle = endPlacement.pixelAlignedOrientedCropRectangle(
                naturalSize: source.naturalSize,
                preferredTransform: source.preferredTransform
            )
            let startSourceCropRectangle = startPlacement.pixelAlignedSourceCropRectangle(
                naturalSize: source.naturalSize,
                preferredTransform: source.preferredTransform
            )
            let endSourceCropRectangle = endPlacement.pixelAlignedSourceCropRectangle(
                naturalSize: source.naturalSize,
                preferredTransform: source.preferredTransform
            )
            switch (startSourceCropRectangle, endSourceCropRectangle) {
            case let (.some(start), .some(end)):
                layer.setCropRectangleRamp(
                    fromStartCropRectangle: start,
                    toEndCropRectangle: end,
                    timeRange: timeRange
                )
            case let (.some(rect), .none), let (.none, .some(rect)):
                layer.setCropRectangle(rect, at: timeRange.start)
            case (.none, .none):
                break
            }
            layer.setOpacityRamp(
                fromStartOpacity: Float(startScene.sourceOpacity(for: kind.source)),
                toEndOpacity: Float(endScene.sourceOpacity(for: kind.source)),
                timeRange: timeRange
            )
            layer.setTransformRamp(
                fromStart: startPlacement.transform(
                    naturalSize: source.naturalSize,
                    preferredTransform: source.preferredTransform,
                    cropRectangle: startCropRectangle
                ),
                toEnd: endPlacement.transform(
                    naturalSize: source.naturalSize,
                    preferredTransform: source.preferredTransform,
                    cropRectangle: endCropRectangle
                ),
                timeRange: timeRange
            )
            return layer
        }
    }

}


struct EditorPlaybackSceneTimeline {
    let settings: RecordingSettings
    let sceneEvents: [RecordingSceneEvent]
}

struct EditorPlaybackComposition {
    struct AudioInput {
        let source: CaptureSource
        let track: AVCompositionTrack
        let volume: Float
    }

    let composition: AVComposition
    let duration: CMTime
    let renderSize: CGSize
    let frameDuration: CMTime
    let renderSegments: [FinalExportRenderSegment]
    let settings: RecordingSettings
    let sceneEvents: [RecordingSceneEvent]
    let sourceInputs: [FinalExportSourceInput]
    let videoKinds: [SceneLayerKind]
    let sourceAspectRatios: [SceneLayerKind: CGFloat]
    let audioInputs: [AudioInput]
    let videoAssets: [SceneLayerKind: AVComposition]
    fileprivate let makeInstructions: (Set<SceneLayerKind>, [FinalExportRenderSegment]) -> [AVMutableVideoCompositionInstruction]

    func playerItem(
        hiding hiddenKinds: Set<SceneLayerKind> = [],
        muting mutedSources: Set<CaptureSource> = []
    ) -> AVPlayerItem {
        let item = AVPlayerItem(asset: composition)
        if !videoKinds.isEmpty {
            item.videoComposition = videoComposition(hiding: hiddenKinds)
        }
        item.audioMix = audioMix(muting: mutedSources)
        return item
    }

    func videoAsset(for kind: SceneLayerKind) -> AVAsset? {
        videoAssets[kind]
    }

    func updatingSceneTimeline(_ update: EditorPlaybackSceneTimeline) throws -> EditorPlaybackComposition {
        let plan = try FinalExportPlanning.plan(
            settings: update.settings,
            sceneEvents: update.sceneEvents,
            sources: sourceInputs
        )
        guard plan.renderSize == renderSize else {
            throw RecorderError.exportUnavailable
        }
        return EditorPlaybackComposition(
            composition: composition,
            duration: duration,
            renderSize: renderSize,
            frameDuration: frameDuration,
            renderSegments: plan.renderSegments,
            settings: update.settings,
            sceneEvents: update.sceneEvents,
            sourceInputs: sourceInputs,
            videoKinds: videoKinds,
            sourceAspectRatios: sourceAspectRatios,
            audioInputs: audioInputs,
            videoAssets: videoAssets,
            makeInstructions: makeInstructions
        )
    }

    func videoComposition(hiding hiddenKinds: Set<SceneLayerKind>) -> AVVideoComposition {
        videoComposition(hiding: hiddenKinds, renderSegments: renderSegments(hiding: hiddenKinds))
    }

    func duration(hiding hiddenKinds: Set<SceneLayerKind>) -> CMTime {
        previewPlan(hiding: hiddenKinds)?.duration ?? duration
    }

    func videoComposition(
        hiding hiddenKinds: Set<SceneLayerKind>,
        overriding scene: RecordingScene,
        at time: CMTime
    ) -> AVVideoComposition {
        let scene = Self.scene(scene, hiding: hiddenKinds)
        return videoComposition(
            hiding: hiddenKinds,
            renderSegments: renderSegments(hiding: hiddenKinds, overriding: scene, at: time)
        )
    }

    func renderSegments(overriding scene: RecordingScene, at time: CMTime) -> [FinalExportRenderSegment] {
        Self.renderSegments(renderSegments, overriding: scene, at: time)
    }

    func renderSegments(
        hiding hiddenKinds: Set<SceneLayerKind>,
        overriding scene: RecordingScene,
        at time: CMTime
    ) -> [FinalExportRenderSegment] {
        Self.renderSegments(renderSegments(hiding: hiddenKinds), overriding: scene, at: time)
    }

    func renderSegments(hiding hiddenKinds: Set<SceneLayerKind>) -> [FinalExportRenderSegment] {
        guard !hiddenKinds.isEmpty else { return renderSegments }
        return previewPlan(hiding: hiddenKinds)?.renderSegments ?? renderSegments.map { segment in
            FinalExportRenderSegment(
                timeRange: segment.timeRange,
                scene: Self.scene(segment.scene, hiding: hiddenKinds),
                activeLayerOrder: segment.activeLayerOrder.filter { !hiddenKinds.contains($0) }
            )
        }
    }

    func normalizedLayerFrames(
        scene: RecordingScene,
        activeLayerOrder: [SceneLayerKind]? = nil,
        hiding hiddenKinds: Set<SceneLayerKind>
    ) -> [(kind: SceneLayerKind, frame: CGRect)] {
        Self.normalizedLayerFrames(
            scene: scene,
            renderSize: renderSize,
            activeLayerOrder: activeLayerOrder,
            hiding: hiddenKinds,
            sourceAspectRatios: sourceAspectRatios
        )
    }

    static func renderSegments(
        _ renderSegments: [FinalExportRenderSegment],
        overriding scene: RecordingScene,
        at time: CMTime
    ) -> [FinalExportRenderSegment] {
        let index = renderSegments.firstIndex {
            CMTimeRangeContainsTime($0.timeRange, time: time)
        } ?? renderSegments.firstIndex {
            CMTimeCompare($0.timeRange.start, time) == 0
        } ?? renderSegments.firstIndex {
            CMTimeCompare(CMTimeRangeGetEnd($0.timeRange), time) == 0
        }
        guard let index else {
            return renderSegments
        }
        var segments = renderSegments
        let segment = segments[index]
        segments[index] = FinalExportRenderSegment(
            timeRange: segment.timeRange,
            scene: scene,
            activeLayerOrder: segment.activeLayerOrder
        )
        return segments
    }

    static func normalizedLayerFrames(
        scene: RecordingScene,
        renderSize: CGSize,
        activeLayerOrder: [SceneLayerKind]? = nil,
        hiding hiddenKinds: Set<SceneLayerKind>,
        sourceAspectRatios: [SceneLayerKind: CGFloat]
    ) -> [(kind: SceneLayerKind, frame: CGRect)] {
        guard renderSize.width > 0, renderSize.height > 0 else { return [] }
        let scene = Self.scene(scene, hiding: hiddenKinds)
        let canvas = CGRect(origin: .zero, size: renderSize)
        let geometry = SceneRenderGeometry(canvas: canvas, scene: scene, origin: .upperLeft)
        let layerOrder = activeLayerOrder?.filter { !hiddenKinds.contains($0) } ?? geometry.activeLayerOrder
        return layerOrder
            .compactMap { kind in
                let rect = visibleRect(
                    for: kind,
                    scene: scene,
                    geometry: geometry,
                    sourceAspectRatios: sourceAspectRatios
                )
                guard rect.width > 0, rect.height > 0 else { return nil }
                return (kind, CGRect(
                    x: rect.minX / renderSize.width,
                    y: rect.minY / renderSize.height,
                    width: rect.width / renderSize.width,
                    height: rect.height / renderSize.height
                ))
            }
    }

    private static func scene(_ scene: RecordingScene, hiding hiddenKinds: Set<SceneLayerKind>) -> RecordingScene {
        guard !hiddenKinds.isEmpty else { return scene }
        var scene = scene
        scene.enabledSources.subtract(Set(hiddenKinds.map(\.source)))
        return scene
    }

    private func previewPlan(hiding hiddenKinds: Set<SceneLayerKind>) -> FinalExportPlan? {
        guard !hiddenKinds.isEmpty else {
            return FinalExportPlan(
                duration: duration,
                renderSize: renderSize,
                engine: .assetExportSession,
                sourceInsertions: [],
                renderSegments: renderSegments
            )
        }
        var settings = settings
        let hiddenSources = Set(hiddenKinds.map(\.source))
        settings.enabledSources.subtract(hiddenSources)
        let sceneEvents = sceneEvents.map { event in
            var scene = event.scene
            scene.enabledSources.subtract(hiddenSources)
            return RecordingSceneEvent(time: event.time, scene: scene, transition: event.transition)
        }
        return try? FinalExportPlanning.plan(
            settings: settings,
            sceneEvents: sceneEvents,
            sources: sourceInputs
        )
    }

    private static func visibleRect(
        for kind: SceneLayerKind,
        scene: RecordingScene,
        geometry: SceneRenderGeometry,
        sourceAspectRatios: [SceneLayerKind: CGFloat]
    ) -> CGRect {
        guard kind == .camera,
              scene.cameraContentMode == .fit,
              let sourceAspectRatio = sourceAspectRatios[.camera] else {
            return geometry.targetRect(for: kind)
        }
        return geometry.visibleSourceRect(for: .camera, sourceAspectRatio: sourceAspectRatio)
    }

    private func videoComposition(
        hiding hiddenKinds: Set<SceneLayerKind>,
        renderSegments: [FinalExportRenderSegment]
    ) -> AVVideoComposition {
        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = makeInstructions(hiddenKinds, renderSegments)
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = frameDuration
        return videoComposition
    }

    func audioMix(muting mutedSources: Set<CaptureSource>) -> AVAudioMix? {
        guard !audioInputs.isEmpty else { return nil }
        let mix = AVMutableAudioMix()
        mix.inputParameters = audioInputs.map { input in
            let parameters = AVMutableAudioMixInputParameters(track: input.track)
            parameters.setVolume(mutedSources.contains(input.source) ? 0 : input.volume, at: .zero)
            return parameters
        }
        return mix
    }
}

extension Merger {
    static func editorPlaybackComposition(
        take: RecordingTake,
        settings: RecordingSettings,
        sceneEvents: [RecordingSceneEvent]
    ) async throws -> EditorPlaybackComposition {
        let videoSources = try await availableVideoSources(for: take, settings: settings)
        let audioSources = await readablePlaybackAudioSources(for: take, settings: settings)
        guard !videoSources.isEmpty || !audioSources.isEmpty else {
            throw RecorderError.exportUnavailable
        }
        let sourceInputs = FinalExportPlanning.applyingTimelineTrim(
            FinalExportPlanning.TimelineTrimRequest(
                sources: videoSources.map(\.planningInput),
                offset: take.timelineTrimOffset
            )
        )
        let outputDimensions = ScreenCaptureGeometry.outputDimensions(for: settings)
        let fallbackRenderSize = CGSize(width: outputDimensions.width, height: outputDimensions.height)
        let exportPlan: FinalExportPlan?
        let videoPlaybackDuration: CMTime
        let playbackInsertionByKind: [SceneLayerKind: FinalExportSourceInsertion]
        if sourceInputs.isEmpty {
            exportPlan = nil
            videoPlaybackDuration = .zero
            playbackInsertionByKind = [:]
        } else {
            let plan = try FinalExportPlanning.plan(
                settings: settings,
                sceneEvents: sceneEvents,
                sources: sourceInputs
            )
            exportPlan = plan
            videoPlaybackDuration = sourceInputs
                .map { CMTimeAdd($0.timelineOffset, $0.duration) }
                .reduce(CMTimeAdd(sourceInputs[0].timelineOffset, sourceInputs[0].duration)) { CMTimeMaximum($0, $1) }
            playbackInsertionByKind = Dictionary(uniqueKeysWithValues: sourceInputs.map {
                ($0.kind, FinalExportPlanning.sourceInsertion(for: $0, compositionDuration: videoPlaybackDuration))
            })
        }

        let composition = AVMutableComposition()
        var compositedSources: [CompositedVideoSource] = []
        var videoAssets: [SceneLayerKind: AVComposition] = [:]
        for source in videoSources {
            guard let insertion = playbackInsertionByKind[source.kind],
                  CMTimeCompare(insertion.duration, .zero) > 0 else { continue }
            guard let compositionTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw RecorderError.exportUnavailable
            }
            try compositionTrack.insertTimeRange(
                CMTimeRange(start: insertion.sourceStart, duration: insertion.duration),
                of: source.track,
                at: insertion.compositionStart
            )
            let videoAsset = AVMutableComposition()
            guard let videoTrack = videoAsset.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw RecorderError.exportUnavailable
            }
            try videoTrack.insertTimeRange(
                CMTimeRange(start: insertion.sourceStart, duration: insertion.duration),
                of: source.track,
                at: insertion.compositionStart
            )
            videoTrack.preferredTransform = source.preferredTransform
            videoAssets[source.kind] = videoAsset
            compositedSources.append(CompositedVideoSource(
                source: source,
                compositionTrack: compositionTrack,
                timeRange: CMTimeRange(start: insertion.compositionStart, duration: insertion.duration)
            ))
        }

        let audioPlaybackDuration = audioSources.map {
            CMTimeMaximum(.zero, CMTimeSubtract($0.duration, $0.source.sourceStart))
        }.max(by: { CMTimeCompare($0, $1) < 0 }) ?? .zero
        let playbackDuration = CMTimeMaximum(
            exportPlan?.duration ?? .zero,
            CMTimeMaximum(videoPlaybackDuration, audioPlaybackDuration)
        )
        var audioInputs: [EditorPlaybackComposition.AudioInput] = []
        for audioSource in audioSources {
            let videoInsertion: FinalExportSourceInsertion?
            switch audioSource.source.source {
            case .screen:
                videoInsertion = playbackInsertionByKind[.screen]
            case .camera:
                videoInsertion = playbackInsertionByKind[.camera]
            case .microphone, .systemAudio:
                videoInsertion = nil
            }
            if let input = addOptionalPlaybackAudio(PlaybackAudioInsertionRequest(
                audioSource: audioSource,
                composition: composition,
                duration: playbackDuration,
                videoInsertion: videoInsertion
            )) {
                audioInputs.append(input)
            }
        }

        let renderSize = exportPlan?.renderSize ?? fallbackRenderSize
        let renderSegments = exportPlan?.renderSegments ?? [
            FinalExportRenderSegment(
                timeRange: CMTimeRange(start: .zero, duration: playbackDuration),
                scene: RecordingScene(settings: settings),
                activeLayerOrder: []
            )
        ]
        return EditorPlaybackComposition(
            composition: composition,
            duration: playbackDuration,
            renderSize: renderSize,
            frameDuration: CMTime(value: 1, timescale: CMTimeScale(settings.framesPerSecond)),
            renderSegments: renderSegments,
            settings: settings,
            sceneEvents: sceneEvents,
            sourceInputs: sourceInputs,
            videoKinds: compositedSources.map(\.kind),
            sourceAspectRatios: Dictionary(uniqueKeysWithValues: compositedSources.map {
                ($0.kind, sourceAspectRatio(for: $0))
            }),
            audioInputs: audioInputs,
            videoAssets: videoAssets,
            makeInstructions: { hiddenKinds, renderSegments in
                videoCompositionInstructions(
                    sources: compositedSources.filter { !hiddenKinds.contains($0.kind) },
                    renderSize: renderSize,
                    renderSegments: renderSegments
                )
            }
        )
    }

    private static func readablePlaybackAudioSources(
        for take: RecordingTake,
        settings: RecordingSettings
    ) async -> [ReadablePlaybackAudioSource] {
        var sources: [ReadablePlaybackAudioSource] = []
        for audioSource in playbackAudioSources(for: take, settings: settings) {
            guard FileManager.default.fileExists(atPath: audioSource.url.path) else { continue }
            let asset = AVURLAsset(url: audioSource.url)
            let tracks: [AVAssetTrack]
            let duration: CMTime
            do {
                tracks = try await asset.loadTracks(withMediaType: .audio)
                duration = try await asset.load(.duration)
            } catch {
                continue
            }
            guard let track = tracks.first,
                  duration.isValid,
                  CMTimeCompare(duration, .zero) > 0 else { continue }
            let trackTimeRange = (try? await track.load(.timeRange)) ?? .invalid
            let trackDuration = trackTimeRange.duration
            let playableDuration = trackDuration.isValid && CMTimeCompare(trackDuration, .zero) > 0
                ? trackDuration
                : duration
            sources.append(ReadablePlaybackAudioSource(
                source: audioSource,
                asset: asset,
                track: track,
                duration: playableDuration
            ))
        }
        return sources
    }

    private static func playbackAudioSources(for take: RecordingTake, settings: RecordingSettings) -> [ExpectedAudioSource] {
        var sources = expectedAudioSources(for: take, settings: settings)
        var includedSources = Set(sources.map(\.source))
        let sourceStart = { source in
            let sourceTimelineOffset = take.sourceTimelineOffsets[source] ?? .zero
            let offset = CMTimeSubtract(take.timelineTrimOffset, sourceTimelineOffset)
            return CMTimeCompare(offset, .zero) > 0 ? offset : .zero
        }
        let sidecars = [
            ExpectedAudioSource(
                source: .microphone,
                url: take.audioURL,
                volume: Float(settings.microphoneGain),
                sourceStart: sourceStart(.microphone)
            ),
            ExpectedAudioSource(
                source: .systemAudio,
                url: take.systemAudioURL,
                volume: Float(settings.systemAudioGain),
                sourceStart: sourceStart(.systemAudio)
            )
        ]
        for sidecar in sidecars where !includedSources.contains(sidecar.source) {
            if FileManager.default.fileExists(atPath: sidecar.url.path) {
                sources.append(sidecar)
                includedSources.insert(sidecar.source)
            }
        }
        let embeddedVideoAudio = [
            ExpectedAudioSource(
                source: .screen,
                url: take.screenURL,
                volume: 1,
                sourceStart: take.timelineTrimOffset
            ),
            ExpectedAudioSource(
                source: .camera,
                url: take.cameraURL,
                volume: 1,
                sourceStart: take.timelineTrimOffset
            )
        ]
        for embedded in embeddedVideoAudio where settings.enabledSources.contains(embedded.source) {
            if FileManager.default.fileExists(atPath: embedded.url.path) {
                sources.append(embedded)
            }
        }
        return sources
    }

    private static func sourceAspectRatio(for source: CompositedVideoSource) -> CGFloat {
        let orientedRect = CGRect(origin: .zero, size: source.naturalSize)
            .applying(source.preferredTransform)
            .standardized
        let width = abs(orientedRect.width)
        let height = abs(orientedRect.height)
        guard width > 0, height > 0 else {
            return source.kind == .camera ? SceneLayout.cameraAspectRatio : SceneLayout.defaultScreenAspectRatio
        }
        return width / height
    }

    private static func addOptionalPlaybackAudio(
        _ request: PlaybackAudioInsertionRequest
    ) -> EditorPlaybackComposition.AudioInput? {
        guard let compositionAudioTrack = request.composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            return nil
        }
        let sourceStart = request.videoInsertion?.sourceStart ?? request.audioSource.source.sourceStart
        let compositionStart = request.videoInsertion?.compositionStart ?? .zero
        let remainingCompositionDuration = CMTimeSubtract(request.duration, compositionStart)
        let remainingSourceDuration = CMTimeSubtract(request.audioSource.duration, sourceStart)
        let insertDuration = CMTimeMinimum(remainingCompositionDuration, remainingSourceDuration)
        guard CMTimeCompare(insertDuration, .zero) > 0 else {
            request.composition.removeTrack(compositionAudioTrack)
            return nil
        }
        do {
            try compositionAudioTrack.insertTimeRange(
                CMTimeRange(start: sourceStart, duration: insertDuration),
                of: request.audioSource.track,
                at: compositionStart
            )
        } catch {
            request.composition.removeTrack(compositionAudioTrack)
            return nil
        }
        return EditorPlaybackComposition.AudioInput(
            source: request.audioSource.source.source,
            track: compositionAudioTrack,
            volume: max(0, min(2, request.audioSource.source.volume))
        )
    }
}

private struct ReadableVideoAsset {
    let asset: AVURLAsset
    let track: AVAssetTrack
    let duration: CMTime
}

private struct ReadablePlaybackAudioSource {
    let source: ExpectedAudioSource
    let asset: AVURLAsset
    let track: AVAssetTrack
    let duration: CMTime
}

private struct PlaybackAudioInsertionRequest {
    let audioSource: ReadablePlaybackAudioSource
    let composition: AVMutableComposition
    let duration: CMTime
    let videoInsertion: FinalExportSourceInsertion?
}

private struct ExpectedAudioSource {
    let source: CaptureSource
    let url: URL
    let volume: Float
    var sourceStart: CMTime = .zero

    var displayName: String {
        switch source {
        case .microphone:
            "Microphone"
        case .systemAudio:
            "System audio"
        case .screen, .camera:
            source.rawValue
        }
    }
}

private struct BackgroundMusicInsertionRequest {
    let selection: ExportBackgroundMusic
    let composition: AVMutableComposition
    let duration: CMTime
}

private struct VideoSource {
    let kind: SceneLayerKind
    let asset: AVURLAsset
    let track: AVAssetTrack
    let duration: CMTime
    let naturalSize: CGSize
    let preferredTransform: CGAffineTransform
    let placement: VideoRenderPlacement
    let timelineOffset: CMTime
    let sourceStartOffset: CMTime

    var planningInput: FinalExportSourceInput {
        FinalExportSourceInput(
            kind: kind,
            duration: duration,
            timelineOffset: timelineOffset,
            sourceStartOffset: sourceStartOffset
        )
    }

    init(
        kind: SceneLayerKind,
        asset: AVURLAsset,
        track: AVAssetTrack,
        duration: CMTime,
        targetRect: CGRect,
        sourceCropAmount: CGPoint = .zero,
        sourceCropPosition: CGPoint = .zero,
        timelineOffset: CMTime = .zero,
        sourceStartOffset: CMTime = .zero
    ) async throws {
        self.kind = kind
        self.asset = asset
        self.track = track
        self.duration = duration
        self.timelineOffset = timelineOffset
        self.sourceStartOffset = sourceStartOffset
        self.naturalSize = try await track.load(.naturalSize)
        self.preferredTransform = try await track.load(.preferredTransform)
        self.placement = VideoRenderPlacement(
            kind: kind,
            targetRect: targetRect,
            sourceCropAmount: sourceCropAmount,
            sourceCropPosition: sourceCropPosition
        )
    }
}

private struct CompositedVideoSource {
    let kind: SceneLayerKind
    let compositionTrack: AVCompositionTrack
    let naturalSize: CGSize
    let preferredTransform: CGAffineTransform
    let timeRange: CMTimeRange

    init(source: VideoSource, compositionTrack: AVCompositionTrack, timeRange: CMTimeRange) {
        kind = source.kind
        self.compositionTrack = compositionTrack
        naturalSize = source.naturalSize
        preferredTransform = source.preferredTransform
        self.timeRange = timeRange
    }

    func isActive(at time: CMTime) -> Bool {
        CMTimeCompare(time, timeRange.start) >= 0
            && CMTimeCompare(time, CMTimeRangeGetEnd(timeRange)) < 0
    }

    func isActive(during range: CMTimeRange) -> Bool {
        let intersection = CMTimeRangeGetIntersection(timeRange, otherRange: range)
        return intersection.isValid && CMTimeCompare(intersection.duration, .zero) > 0
    }
}
