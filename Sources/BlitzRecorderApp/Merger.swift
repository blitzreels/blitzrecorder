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
        let sourceAspectRatios = Dictionary(uniqueKeysWithValues: compositedSources.map {
            ($0.kind, sourceAspectRatio(for: $0))
        })
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
            duration: duration,
            renderSegments: exportPlan.renderSegments,
            sourceAspectRatios: sourceAspectRatios
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

    private static func applyCanvasBackground(
        to videoComposition: AVMutableVideoComposition,
        renderSize: CGSize,
        settings: RecordingSettings,
        sceneEvents: [RecordingSceneEvent],
        duration: CMTime,
        renderSegments: [FinalExportRenderSegment],
        sourceAspectRatios: [SceneLayerKind: CGFloat]
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
        applyRoundedSourceMask(
            to: videoLayer,
            frame: frame,
            segments: segments,
            duration: duration,
            sourceAspectRatios: sourceAspectRatios
        )
        parentLayer.addSublayer(videoLayer)
        addCameraShadowLayer(
            to: parentLayer,
            frame: frame,
            renderSegments: renderSegments,
            duration: duration,
            sourceAspectRatios: sourceAspectRatios
        )
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
        duration: CMTime,
        sourceAspectRatios: [SceneLayerKind: CGFloat]
    ) {
        guard !segments.isEmpty else { return }
        var hasRoundedSegment = false
        let maskPaths = segments.map { segment in
            if let path = roundedSourceMaskPath(
                for: segment.scene,
                frame: frame,
                sourceAspectRatios: sourceAspectRatios
            ) {
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

    private static func addCameraShadowLayer(
        to parentLayer: CALayer,
        frame: CGRect,
        renderSegments: [FinalExportRenderSegment],
        duration: CMTime,
        sourceAspectRatios: [SceneLayerKind: CGFloat]
    ) {
        guard !renderSegments.isEmpty else { return }
        let shadowScenes = renderSegments.map(shadowScene)
        let shadowPaths = shadowScenes.map {
            cameraShadowPath(for: $0, frame: frame, sourceAspectRatios: sourceAspectRatios)
        }
        let clipPaths = shadowScenes.map {
            cameraShadowClipPath(for: $0, frame: frame, sourceAspectRatios: sourceAspectRatios)
        }
        let shadowOpacities = zip(shadowScenes, renderSegments).map { scene, segment in
            cameraShadowOpacity(
                for: scene,
                frame: frame,
                activeLayerOrder: segment.activeLayerOrder,
                sourceAspectRatios: sourceAspectRatios
            )
        }
        guard shadowOpacities.contains(where: { $0 > 0.001 }) else { return }

        let shadowLayer = CALayer()
        shadowLayer.frame = frame
        shadowLayer.shadowColor = CGColor(gray: 0, alpha: 1)
        shadowLayer.shadowRadius = 18
        shadowLayer.shadowOffset = CGSize(width: 0, height: -8)
        shadowLayer.shadowPath = shadowPaths[0]
        shadowLayer.shadowOpacity = shadowOpacities[0]

        let clipLayer = CAShapeLayer()
        clipLayer.frame = frame
        clipLayer.fillColor = CGColor(gray: 1, alpha: 1)
        clipLayer.fillRule = .evenOdd
        clipLayer.path = clipPaths[0]
        shadowLayer.mask = clipLayer

        let durationSeconds = max(0, duration.seconds)
        if renderSegments.count > 1, durationSeconds > 0 {
            let keyTimes = pathKeyTimes(for: renderSegments, durationSeconds: durationSeconds)
            let pathAnimation = CAKeyframeAnimation(keyPath: "shadowPath")
            pathAnimation.beginTime = AVCoreAnimationBeginTimeAtZero
            pathAnimation.duration = durationSeconds
            pathAnimation.keyTimes = keyTimes
            pathAnimation.values = pathValues(shadowPaths, for: renderSegments)
            pathAnimation.calculationMode = .discrete
            pathAnimation.isRemovedOnCompletion = false
            pathAnimation.fillMode = .both
            shadowLayer.add(pathAnimation, forKey: "camera-shadow-path")

            let clipAnimation = CAKeyframeAnimation(keyPath: "path")
            clipAnimation.beginTime = AVCoreAnimationBeginTimeAtZero
            clipAnimation.duration = durationSeconds
            clipAnimation.keyTimes = keyTimes
            clipAnimation.values = pathValues(clipPaths, for: renderSegments)
            clipAnimation.calculationMode = .discrete
            clipAnimation.isRemovedOnCompletion = false
            clipAnimation.fillMode = .both
            clipLayer.add(clipAnimation, forKey: "camera-shadow-clip-path")

            let opacityAnimation = CAKeyframeAnimation(keyPath: "shadowOpacity")
            opacityAnimation.beginTime = AVCoreAnimationBeginTimeAtZero
            opacityAnimation.duration = durationSeconds
            opacityAnimation.keyTimes = keyTimes
            opacityAnimation.values = opacityValues(shadowOpacities, for: renderSegments)
            opacityAnimation.calculationMode = .discrete
            opacityAnimation.isRemovedOnCompletion = false
            opacityAnimation.fillMode = .both
            shadowLayer.add(opacityAnimation, forKey: "camera-shadow-opacity")
        }

        parentLayer.addSublayer(shadowLayer)
    }

    private static func shadowScene(for segment: FinalExportRenderSegment) -> RecordingScene {
        var scene = segment.scene
        scene.enabledSources = Set(segment.activeLayerOrder.map(\.source))
        return scene
    }

    private static func cameraShadowPath(
        for scene: RecordingScene,
        frame: CGRect,
        sourceAspectRatios: [SceneLayerKind: CGFloat]
    ) -> CGPath {
        let geometry = SceneRenderGeometry(canvas: frame, scene: scene, origin: .upperLeft)
        let rect = geometry.visibleSourceRect(for: .camera, sourceAspectRatio: sourceAspectRatios[.camera])
        let radius = geometry.sourceCornerRadius(for: .camera)
        guard rect.width > 0, rect.height > 0 else {
            return CGPath(rect: .zero, transform: nil)
        }
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    private static func cameraShadowClipPath(
        for scene: RecordingScene,
        frame: CGRect,
        sourceAspectRatios: [SceneLayerKind: CGFloat]
    ) -> CGPath {
        let geometry = SceneRenderGeometry(canvas: frame, scene: scene, origin: .upperLeft)
        let rect = geometry.visibleSourceRect(for: .camera, sourceAspectRatio: sourceAspectRatios[.camera])
        let radius = geometry.sourceCornerRadius(for: .camera)
        let path = CGMutablePath()
        path.addRect(frame)
        if rect.width > 0, rect.height > 0 {
            path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
        }
        return path
    }

    private static func cameraShadowOpacity(
        for scene: RecordingScene,
        frame: CGRect,
        activeLayerOrder: [SceneLayerKind],
        sourceAspectRatios: [SceneLayerKind: CGFloat]
    ) -> Float {
        guard scene.cameraShadowEnabled,
              scene.renderedSources.contains(.camera),
              cameraIsTopRenderedLayer(activeLayerOrder),
              scene.sourceOpacity(for: .camera) > 0.001 else {
            return 0
        }
        let geometry = SceneRenderGeometry(canvas: frame, scene: scene, origin: .upperLeft)
        guard !geometry.isVisibleSourceFullCanvas(
            for: .camera,
            sourceAspectRatio: sourceAspectRatios[.camera]
        ) else {
            return 0
        }
        return Float(0.38 * scene.sourceOpacity(for: .camera))
    }

    private static func cameraIsTopRenderedLayer(_ activeLayerOrder: [SceneLayerKind]) -> Bool {
        activeLayerOrder.last == .camera
    }

    private static func roundedSourceMaskPath(
        for scene: RecordingScene,
        frame: CGRect,
        sourceAspectRatios: [SceneLayerKind: CGFloat]
    ) -> CGPath? {
        SceneRenderGeometry(
            canvas: frame,
            scene: scene,
            origin: .upperLeft
        )
        .sourceMaskPath(sourceAspectRatios: sourceAspectRatios)
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

    private static func pathKeyTimes(
        for segments: [FinalExportRenderSegment],
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

    private static func pathValues(
        _ paths: [CGPath],
        for segments: [FinalExportRenderSegment]
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

    private static func opacityValues(
        _ opacities: [Float],
        for segments: [RecordingSceneSegment]
    ) -> [Float] {
        var values = [opacities[0]]
        for (index, _) in segments.enumerated() {
            values.append(opacities[index])
            values.append(opacities[index])
        }
        values.append(opacities.last ?? opacities[0])
        return values
    }

    private static func opacityValues(
        _ opacities: [Float],
        for segments: [FinalExportRenderSegment]
    ) -> [Float] {
        var values = [opacities[0]]
        for (index, _) in segments.enumerated() {
            values.append(opacities[index])
            values.append(opacities[index])
        }
        values.append(opacities.last ?? opacities[0])
        return values
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
        let sourceInputs = videoSources.map(\.planningInput)
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
            compositedSources.append(CompositedVideoSource(
                source: source,
                compositionTrack: compositionTrack,
                timeRange: CMTimeRange(start: insertion.compositionStart, duration: insertion.duration)
            ))
        }

        let audioPlaybackDuration = audioSources.map(\.duration).max(by: { CMTimeCompare($0, $1) < 0 }) ?? .zero
        let playbackDuration = CMTimeMaximum(
            exportPlan?.duration ?? .zero,
            CMTimeMaximum(videoPlaybackDuration, audioPlaybackDuration)
        )
        var audioInputs: [EditorPlaybackComposition.AudioInput] = []
        for audioSource in audioSources {
            if let input = addOptionalPlaybackAudio(
                audioSource,
                to: composition,
                duration: playbackDuration
            ) {
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
        let includedSources = Set(sources.map(\.source))
        let sidecars = [
            ExpectedAudioSource(source: .microphone, url: take.audioURL, volume: Float(settings.microphoneGain)),
            ExpectedAudioSource(source: .systemAudio, url: take.systemAudioURL, volume: Float(settings.systemAudioGain))
        ]
        for sidecar in sidecars where !includedSources.contains(sidecar.source) {
            if FileManager.default.fileExists(atPath: sidecar.url.path) {
                sources.append(sidecar)
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
        _ audioSource: ReadablePlaybackAudioSource,
        to composition: AVMutableComposition,
        duration: CMTime
    ) -> EditorPlaybackComposition.AudioInput? {
        guard let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            return nil
        }
        do {
            try compositionAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: CMTimeMinimum(duration, audioSource.duration)),
                of: audioSource.track,
                at: .zero
            )
        } catch {
            composition.removeTrack(compositionAudioTrack)
            return nil
        }
        return EditorPlaybackComposition.AudioInput(
            source: audioSource.source.source,
            track: compositionAudioTrack,
            volume: max(0, min(2, audioSource.source.volume))
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
