import AVFoundation
import BlitzRecorderCore
import CoreGraphics
import Foundation
import QuartzCore

enum Merger {
    static func exportFinalVideo(
        take: RecordingTake,
        settings: RecordingSettings,
        sceneEvents: [RecordingSceneEvent] = [],
        progressHandler: (@MainActor (Double) -> Void)? = nil
    ) async throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: take.finalVideoURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let outputURL = uniqueFileURL(take.finalVideoURL)
        let temporaryOutputURL = uniqueFileURL(
            take.scratchDirectory
                .appendingPathComponent(".final-export-\(UUID().uuidString).\(take.outputVideoFormat.fileExtension)")
        )

        let videoSources = try await availableVideoSources(for: take, settings: settings)
        guard !videoSources.isEmpty else {
            throw RecorderError.exportUnavailable
        }

        let composition = AVMutableComposition()
        let duration = videoSources
            .map(\.duration)
            .reduce(videoSources[0].duration) { CMTimeMinimum($0, $1) }

        let renderDimensions = ScreenCaptureGeometry.outputDimensions(for: settings)
        let renderSize = CGSize(width: renderDimensions.width, height: renderDimensions.height)

        var compositedSources: [CompositedVideoSource] = []
        for source in videoSources {
            guard let compositionTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw RecorderError.exportUnavailable
            }

            try compositionTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: source.track,
                at: .zero
            )

            compositedSources.append(CompositedVideoSource(source: source, compositionTrack: compositionTrack))
        }

        var audioMixParameters: [AVMutableAudioMixInputParameters] = []
        if let parameters = try await addAudioIfPresent(
            from: take.audioURL,
            to: composition,
            duration: duration,
            volume: Float(settings.microphoneGain)
        ) {
            audioMixParameters.append(parameters)
        }
        if let parameters = try await addAudioIfPresent(
            from: take.systemAudioURL,
            to: composition,
            duration: duration,
            volume: Float(settings.systemAudioGain)
        ) {
            audioMixParameters.append(parameters)
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = videoCompositionInstructions(
            sources: compositedSources,
            duration: duration,
            renderSize: renderSize,
            settings: settings,
            sceneEvents: sceneEvents
        )
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(settings.framesPerSecond))
        applyCanvasBackground(to: videoComposition, renderSize: renderSize, settings: settings)

        let presetName = settings.removesCameraBackgroundAfterRecording
            ? AVAssetExportPresetHighestQuality
            : AVAssetExportPresetHEVCHighestQuality
        guard let exporter = AVAssetExportSession(asset: composition, presetName: presetName) else {
            throw RecorderError.exportUnavailable
        }
        let outputFileType = take.outputVideoFormat.avFileType
        guard exporter.supportedFileTypes.contains(outputFileType) else {
            throw RecorderError.exportUnavailable
        }

        exporter.outputURL = temporaryOutputURL
        exporter.outputFileType = outputFileType
        exporter.videoComposition = videoComposition
        if !audioMixParameters.isEmpty {
            let audioMix = AVMutableAudioMix()
            audioMix.inputParameters = audioMixParameters
            exporter.audioMix = audioMix
        }
        exporter.shouldOptimizeForNetworkUse = true

        let progressTask = Task { @MainActor in
            progressHandler?(0)
            while !Task.isCancelled {
                progressHandler?(Double(exporter.progress))
                try? await Task.sleep(for: .milliseconds(120))
            }
        }

        do {
            try await exporter.export(to: temporaryOutputURL, as: outputFileType)
            progressTask.cancel()
            await progressTask.value
            await progressHandler?(1)
        } catch {
            progressTask.cancel()
            await progressTask.value
            try? fileManager.removeItem(at: temporaryOutputURL)
            throw error
        }

        try fileManager.moveItem(at: temporaryOutputURL, to: outputURL)
        return outputURL
    }

    private static func uniqueFileURL(_ url: URL) -> URL {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            return url
        }

        let directory = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        let pathExtension = url.pathExtension
        var index = 2
        while true {
            let candidate = directory.appendingPathComponent("\(baseName)-\(index).\(pathExtension)")
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    private static func availableVideoSources(for take: RecordingTake, settings: RecordingSettings) async throws -> [VideoSource] {
        var sources: [VideoSource] = []
        let screenAsset = await readableVideoAsset(kind: "screen", url: take.screenURL)
        let cameraAsset = await readableVideoAsset(kind: "camera", url: take.cameraURL)
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
                sources.append(try await VideoSource(
                    kind: .camera,
                    asset: cameraAsset.asset,
                    track: cameraAsset.track,
                    duration: cameraAsset.duration,
                    targetRect: targetRect,
                    sourceCropAmount: settings.cameraCropAmount,
                    sourceCropPosition: settings.cameraCropPosition
                ))
            }
        }

        return sources
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

    private static func paddedFullCanvasTargetRect(renderSize: CGSize, settings: RecordingSettings) -> CGRect {
        let canvas = CGRect(origin: .zero, size: renderSize)
        return SceneLayoutProjection.padded(canvas, in: canvas, padding: settings.canvasPadding)
    }

    private static func applyCanvasBackground(
        to videoComposition: AVMutableVideoComposition,
        renderSize: CGSize,
        settings: RecordingSettings
    ) {
        let frame = CGRect(origin: .zero, size: renderSize)
        let parentLayer = CALayer()
        parentLayer.frame = frame

        let backgroundLayer = CAGradientLayer()
        backgroundLayer.frame = frame
        backgroundLayer.colors = settings.canvasBackgroundStyle.previewColors
        backgroundLayer.locations = settings.canvasBackgroundStyle.previewLocations
        backgroundLayer.startPoint = CGPoint(x: 0.08, y: 0.02)
        backgroundLayer.endPoint = CGPoint(x: 0.92, y: 1)
        backgroundLayer.backgroundColor = settings.canvasBackgroundStyle.solidCGColor

        let videoLayer = CALayer()
        videoLayer.frame = frame

        parentLayer.addSublayer(backgroundLayer)
        parentLayer.addSublayer(videoLayer)
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
    }

    private static func addAudioIfPresent(
        from url: URL,
        to composition: AVMutableComposition,
        duration: CMTime,
        volume: Float
    ) async throws -> AVMutableAudioMixInputParameters? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard (values.fileSize ?? 0) > 0 else { return nil }

        let asset = AVURLAsset(url: url)
        let audioTracks: [AVAssetTrack]
        let audioDuration: CMTime
        do {
            audioTracks = try await asset.loadTracks(withMediaType: .audio)
            audioDuration = try await asset.load(.duration)
        } catch {
            NSLog("Skipping unreadable audio file \(url.path): \(error.localizedDescription)")
            return nil
        }

        guard let audioTrack = audioTracks.first,
              audioDuration.isValid,
              CMTimeCompare(audioDuration, .zero) > 0,
              let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            return nil
        }

        let insertDuration = CMTimeMinimum(duration, audioDuration)
        try compositionAudioTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: insertDuration),
            of: audioTrack,
            at: .zero
        )

        let parameters = AVMutableAudioMixInputParameters(track: compositionAudioTrack)
        parameters.setVolume(max(0, min(2, volume)), at: .zero)
        return parameters
    }

    private static func targetRect(
        for kind: SceneLayerKind,
        settings: RecordingSettings,
        renderSize: CGSize
    ) -> CGRect {
        let canvas = CGRect(origin: .zero, size: renderSize)
        return SceneLayoutProjection.padded(
            SceneLayoutProjection.denormalized(
                SceneLayoutProjection.normalizedFrame(for: kind, in: settings.sceneLayout),
                in: canvas,
                origin: .upperLeft
            ),
            in: canvas,
            padding: settings.canvasPadding
        )
    }

    private static func targetRect(
        for kind: SceneLayerKind,
        scene: RecordingScene,
        availableKinds: Set<SceneLayerKind>,
        renderSize: CGSize
    ) -> CGRect {
        let canvas = CGRect(origin: .zero, size: renderSize)
        let visibleAvailableKinds = Set(
            SceneLayerKind.allCases.filter { availableKinds.contains($0) && scene.enabledSources.contains($0.source) }
        )
        let normalizedFrame = visibleAvailableKinds == [kind]
            ? SceneLayoutProjection.fullFrame
            : SceneLayoutProjection.normalizedFrame(for: kind, in: scene.sceneLayout)
        return SceneLayoutProjection.padded(
            SceneLayoutProjection.denormalized(normalizedFrame, in: canvas, origin: .upperLeft),
            in: canvas,
            padding: scene.canvasPadding
        )
    }

    private static func videoCompositionInstructions(
        sources: [CompositedVideoSource],
        duration: CMTime,
        renderSize: CGSize,
        settings: RecordingSettings,
        sceneEvents: [RecordingSceneEvent]
    ) -> [AVMutableVideoCompositionInstruction] {
        let fallbackScene = RecordingScene(settings: settings)
        let availableKinds = Set(sources.map(\.kind))
        return sceneSegments(sceneEvents: sceneEvents, fallbackScene: fallbackScene, duration: duration).map { segment in
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = segment.timeRange
            instruction.layerInstructions = layerInstructions(
                sources: sources,
                scene: segment.scene,
                availableKinds: availableKinds,
                renderSize: renderSize,
                at: segment.timeRange.start
            ).reversed()
            instruction.backgroundColor = CGColor(gray: 0, alpha: 0)
            return instruction
        }
    }

    private static func layerInstructions(
        sources: [CompositedVideoSource],
        scene: RecordingScene,
        availableKinds: Set<SceneLayerKind>,
        renderSize: CGSize,
        at time: CMTime
    ) -> [AVMutableVideoCompositionLayerInstruction] {
        scene.sceneLayout.layerOrder.compactMap { kind in
            guard scene.enabledSources.contains(kind.source),
                  let source = sources.first(where: { $0.kind == kind }) else {
                return nil
            }
            let placement = VideoRenderPlacement(
                kind: kind,
                targetRect: targetRect(for: kind, scene: scene, availableKinds: availableKinds, renderSize: renderSize),
                sourceCropAmount: kind == .camera ? scene.cameraCropAmount : .zero,
                sourceCropPosition: kind == .camera ? scene.cameraCropPosition : .zero
            )
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: source.compositionTrack)
            if let cropRectangle = placement.cropRectangle(naturalSize: source.naturalSize) {
                layer.setCropRectangle(cropRectangle, at: time)
            }
            layer.setTransform(
                placement.transform(
                    naturalSize: source.naturalSize,
                    preferredTransform: source.preferredTransform
                ),
                at: time
            )
            return layer
        }
    }

    private static func sceneSegments(
        sceneEvents: [RecordingSceneEvent],
        fallbackScene: RecordingScene,
        duration: CMTime
    ) -> [(timeRange: CMTimeRange, scene: RecordingScene)] {
        let durationSeconds = max(0, duration.seconds)
        var events = sceneEvents
            .filter { $0.time.isFinite }
            .sorted { $0.time < $1.time }

        if events.first?.time ?? .infinity > 0 {
            events.insert(RecordingSceneEvent(time: 0, scene: fallbackScene), at: 0)
        }
        if events.isEmpty {
            events = [RecordingSceneEvent(time: 0, scene: fallbackScene)]
        }

        var segments: [(CMTimeRange, RecordingScene)] = []
        for index in events.indices {
            let startSeconds = min(max(0, events[index].time), durationSeconds)
            let endSeconds: TimeInterval
            if index < events.index(before: events.endIndex) {
                endSeconds = min(max(startSeconds, events[events.index(after: index)].time), durationSeconds)
            } else {
                endSeconds = durationSeconds
            }
            guard endSeconds > startSeconds else { continue }
            let start = CMTime(seconds: startSeconds, preferredTimescale: 600)
            let end = CMTime(seconds: endSeconds, preferredTimescale: 600)
            segments.append((CMTimeRange(start: start, duration: CMTimeSubtract(end, start)), events[index].scene))
        }

        if segments.isEmpty {
            return [(CMTimeRange(start: .zero, duration: duration), fallbackScene)]
        }
        return segments
    }
}

private struct ReadableVideoAsset {
    let asset: AVURLAsset
    let track: AVAssetTrack
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

    init(
        kind: SceneLayerKind,
        asset: AVURLAsset,
        track: AVAssetTrack,
        duration: CMTime,
        targetRect: CGRect,
        sourceCropAmount: CGPoint = .zero,
        sourceCropPosition: CGPoint = .zero
    ) async throws {
        self.kind = kind
        self.asset = asset
        self.track = track
        self.duration = duration
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

    init(source: VideoSource, compositionTrack: AVCompositionTrack) {
        kind = source.kind
        self.compositionTrack = compositionTrack
        naturalSize = source.naturalSize
        preferredTransform = source.preferredTransform
    }
}
