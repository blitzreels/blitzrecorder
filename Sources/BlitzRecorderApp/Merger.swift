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
        let exportPlan = try FinalExportPlanning.plan(
            settings: settings,
            sceneEvents: sceneEvents,
            sources: videoSources.map(\.planningInput)
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

        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = videoCompositionInstructions(
            sources: compositedSources,
            renderSize: renderSize,
            renderSegments: exportPlan.renderSegments
        )
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(settings.framesPerSecond))
        applyCanvasBackground(
            to: videoComposition,
            renderSize: renderSize,
            settings: settings,
            sceneEvents: sceneEvents,
            duration: duration
        )

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
            await progressHandler?(1)
        } catch {
            try? fileManager.removeItem(at: temporaryOutputURL)
            throw error
        }

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
        exporter.shouldOptimizeForNetworkUse = true

        let progressTask = Task { @MainActor in
            while !Task.isCancelled {
                progressHandler?(Double(exporter.progress))
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
        do {
            try await exporter.export(to: outputURL, as: outputFileType)
            progressTask.cancel()
            await progressTask.value
        } catch {
            progressTask.cancel()
            await progressTask.value
            throw error
        }
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
                sources.append(try await VideoSource(
                    kind: .camera,
                    asset: cameraAsset.asset,
                    track: cameraAsset.track,
                    duration: cameraAsset.duration,
                    targetRect: targetRect,
                    sourceCropAmount: settings.cameraCropAmount,
                    sourceCropPosition: settings.cameraCropPosition,
                    timelineOffset: remoteCameraTimelineOffset(for: take.cameraURL, preservesPositiveOffset: hasScreen)
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

    private static func remoteCameraTimelineOffset(
        for cameraURL: URL,
        preservesPositiveOffset: Bool
    ) -> CMTime {
        guard let manifest = remoteCameraManifest(for: cameraURL),
              let timelineStartTime = manifest.hostTimelineStartTime,
              let cameraStartTime = manifest.estimatedHostStartTime ?? manifest.hostStartTime else {
            return .zero
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

    private static func applyCanvasBackground(
        to videoComposition: AVMutableVideoComposition,
        renderSize: CGSize,
        settings: RecordingSettings,
        sceneEvents: [RecordingSceneEvent],
        duration: CMTime
    ) {
        let frame = CGRect(origin: .zero, size: renderSize)
        let parentLayer = CALayer()
        parentLayer.frame = frame

        let videoLayer = CALayer()
        videoLayer.frame = frame

        let fallbackScene = RecordingScene(settings: settings)
        let segments = RecordingSceneTimeline.segments(
            sceneEvents: sceneEvents,
            fallbackScene: fallbackScene,
            duration: duration,
            transitionSampleInterval: FinalExportPlanning.transitionSampleInterval(for: settings)
        )
        addCanvasBackgroundLayers(to: parentLayer, frame: frame, segments: segments, duration: duration)
        applyRoundedSourceMask(to: videoLayer, frame: frame, segments: segments, duration: duration)
        parentLayer.addSublayer(videoLayer)
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
    }

    private static func addCanvasBackgroundLayers(
        to parentLayer: CALayer,
        frame: CGRect,
        segments: [RecordingSceneSegment],
        duration: CMTime
    ) {
        guard !segments.isEmpty else { return }
        let durationSeconds = max(0, duration.seconds)
        if segments.count == 1 || durationSeconds <= 0 {
            let scene = segments[0].scene
            parentLayer.addSublayer(canvasBackgroundLayer(
                style: scene.canvasBackgroundStyle,
                animated: scene.canvasBackgroundAnimated,
                frame: frame
            ))
            return
        }

        for segment in segments {
            let layer = canvasBackgroundLayer(
                style: segment.scene.canvasBackgroundStyle,
                animated: segment.scene.canvasBackgroundAnimated,
                frame: frame
            )
            layer.opacity = CMTimeCompare(segment.timeRange.start, .zero) == 0 ? 1 : 0
            let start = max(0, min(1, segment.timeRange.start.seconds / durationSeconds))
            let end = max(start, min(1, CMTimeGetSeconds(CMTimeRangeGetEnd(segment.timeRange)) / durationSeconds))
            let animation = CAKeyframeAnimation(keyPath: "opacity")
            animation.beginTime = AVCoreAnimationBeginTimeAtZero
            animation.duration = durationSeconds
            animation.keyTimes = opacityKeyTimes(start: start, end: end)
            animation.values = opacityValues(start: start, end: end)
            animation.calculationMode = .discrete
            animation.isRemovedOnCompletion = false
            animation.fillMode = .both
            layer.add(animation, forKey: "scene-opacity")
            parentLayer.addSublayer(layer)
        }
    }

    private static func applyRoundedSourceMask(
        to videoLayer: CALayer,
        frame: CGRect,
        segments: [RecordingSceneSegment],
        duration: CMTime
    ) {
        guard !segments.isEmpty else { return }
        var hasRoundedSegment = false
        let maskPaths = segments.map { segment in
            if let path = roundedSourceMaskPath(for: segment.scene, frame: frame) {
                hasRoundedSegment = true
                return path
            }
            return CGPath(rect: frame, transform: nil)
        }
        guard hasRoundedSegment else { return }

        let maskLayer = CAShapeLayer()
        maskLayer.frame = frame
        maskLayer.fillColor = CGColor(gray: 1, alpha: 1)
        maskLayer.path = maskPaths[0]

        let durationSeconds = max(0, duration.seconds)
        if segments.count > 1, durationSeconds > 0 {
            let animation = CAKeyframeAnimation(keyPath: "path")
            animation.beginTime = AVCoreAnimationBeginTimeAtZero
            animation.duration = durationSeconds
            animation.keyTimes = pathKeyTimes(for: segments, durationSeconds: durationSeconds)
            animation.values = pathValues(maskPaths, for: segments)
            animation.calculationMode = .discrete
            animation.isRemovedOnCompletion = false
            animation.fillMode = .both
            maskLayer.add(animation, forKey: "scene-path")
        }

        videoLayer.mask = maskLayer
    }

    private static func roundedSourceMaskPath(for scene: RecordingScene, frame: CGRect) -> CGPath? {
        SceneRenderGeometry(canvas: frame, scene: scene, origin: .upperLeft).sourceMaskPath()
    }

    private static func pathKeyTimes(
        for segments: [RecordingSceneSegment],
        durationSeconds: Double
    ) -> [NSNumber] {
        var keyTimes = [NSNumber(value: 0)]
        for segment in segments {
            let start = max(0, min(1, segment.timeRange.start.seconds / durationSeconds))
            let end = max(start, min(1, CMTimeGetSeconds(CMTimeRangeGetEnd(segment.timeRange)) / durationSeconds))
            keyTimes.append(NSNumber(value: start))
            keyTimes.append(NSNumber(value: end))
        }
        keyTimes.append(NSNumber(value: 1))
        return keyTimes
    }

    private static func pathValues(
        _ paths: [CGPath],
        for segments: [RecordingSceneSegment]
    ) -> [CGPath] {
        var values = [paths[0]]
        for (index, _) in segments.enumerated() {
            values.append(paths[index])
            values.append(paths[index])
        }
        values.append(paths.last ?? paths[0])
        return values
    }

    private static func canvasBackgroundLayer(style: CanvasBackgroundStyle, animated: Bool, frame: CGRect) -> CALayer {
        guard animated && style.supportsBackgroundAnimation else {
            // `frame` is already in output pixels, so render at scale 1.
            return style.appearance.backgroundLayer(frame: frame, scale: 1)
        }
        let layer = CALayer()
        layer.frame = frame
        layer.contentsGravity = .resize
        layer.masksToBounds = true
        layer.backgroundColor = style.appearance.solidCGColor
        attachBackgroundDriftAnimation(to: layer, style: style, frame: frame)
        return layer
    }

    /// Drive the background layer's `contents` through one prebaked loop of mesh
    /// frames, repeated across the export. Frames are rendered at a capped
    /// resolution (the mesh is soft, so upscaling to output is invisible) to keep
    /// the held image set small. Discrete keyframes — images can't interpolate —
    /// and the motion model is seamless (last frame → first frame).
    private static func attachBackgroundDriftAnimation(to layer: CALayer, style: CanvasBackgroundStyle, frame: CGRect) {
        let frameCount = 48
        let cap: CGFloat = 1024
        let longEdge = max(frame.width, frame.height)
        let scale = longEdge > cap ? cap / longEdge : 1
        let width = max(1, Int((frame.width * scale).rounded(.up)))
        let height = max(1, Int((frame.height * scale).rounded(.up)))
        let frames = style.appearance.animationFrames(pixelWidth: width, pixelHeight: height, count: frameCount)
        guard frames.count == frameCount else {
            layer.contents = frames.first ?? style.appearance.renderCGImage(pixelWidth: width, pixelHeight: height)
            return
        }

        layer.contents = frames[0]
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = frames
        animation.keyTimes = (0..<frameCount).map { NSNumber(value: Double($0) / Double(frameCount)) }
        animation.calculationMode = .discrete
        animation.duration = CanvasAppearance.animationLoopDuration
        animation.repeatCount = .greatestFiniteMagnitude
        animation.beginTime = AVCoreAnimationBeginTimeAtZero
        animation.isRemovedOnCompletion = false
        animation.fillMode = .both
        layer.add(animation, forKey: "background-drift")
    }

    private static func opacityKeyTimes(start: Double, end: Double) -> [NSNumber] {
        if start <= 0 {
            return [NSNumber(value: 0), NSNumber(value: end), NSNumber(value: 1)]
        }
        if end >= 1 {
            return [NSNumber(value: 0), NSNumber(value: start), NSNumber(value: 1)]
        }
        return [NSNumber(value: 0), NSNumber(value: start), NSNumber(value: end), NSNumber(value: 1)]
    }

    private static func opacityValues(start: Double, end: Double) -> [Float] {
        if start <= 0 {
            return [1, 0, 0]
        }
        if end >= 1 {
            return [0, 1, 1]
        }
        return [0, 1, 0, 0]
    }

    private static func expectedAudioSources(for take: RecordingTake, settings: RecordingSettings) -> [ExpectedAudioSource] {
        var sources: [ExpectedAudioSource] = []
        if settings.enabledSources.contains(.microphone) {
            sources.append(ExpectedAudioSource(
                source: .microphone,
                url: take.audioURL,
                volume: Float(settings.microphoneGain)
            ))
        }
        if settings.enabledSources.contains(.systemAudio) {
            sources.append(ExpectedAudioSource(
                source: .systemAudio,
                url: take.systemAudioURL,
                volume: Float(settings.systemAudioGain)
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

        let insertDuration = CMTimeMinimum(duration, audioDuration)
        try compositionAudioTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: insertDuration),
            of: audioTrack,
            at: .zero
        )

        let parameters = AVMutableAudioMixInputParameters(track: compositionAudioTrack)
        parameters.setVolume(max(0, min(2, audioSource.volume)), at: .zero)
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

private struct ReadableVideoAsset {
    let asset: AVURLAsset
    let track: AVAssetTrack
    let duration: CMTime
}

private struct ExpectedAudioSource {
    let source: CaptureSource
    let url: URL
    let volume: Float

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

private struct VideoSource {
    let kind: SceneLayerKind
    let asset: AVURLAsset
    let track: AVAssetTrack
    let duration: CMTime
    let naturalSize: CGSize
    let preferredTransform: CGAffineTransform
    let placement: VideoRenderPlacement
    let timelineOffset: CMTime

    var planningInput: FinalExportSourceInput {
        FinalExportSourceInput(kind: kind, duration: duration, timelineOffset: timelineOffset)
    }

    init(
        kind: SceneLayerKind,
        asset: AVURLAsset,
        track: AVAssetTrack,
        duration: CMTime,
        targetRect: CGRect,
        sourceCropAmount: CGPoint = .zero,
        sourceCropPosition: CGPoint = .zero,
        timelineOffset: CMTime = .zero
    ) async throws {
        self.kind = kind
        self.asset = asset
        self.track = track
        self.duration = duration
        self.timelineOffset = timelineOffset
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
