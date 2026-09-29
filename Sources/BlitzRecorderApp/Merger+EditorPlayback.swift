import AVFoundation
import BlitzRecorderCore
import CoreGraphics
import Foundation

extension Merger {
    static func editorPlaybackComposition(
        take: RecordingTake,
        settings: RecordingSettings,
        sceneEvents: [RecordingSceneEvent],
        cuts: [TimelineCut] = []
    ) async throws -> EditorPlaybackComposition {
        let videoSources = try await availableVideoSources(for: take, settings: settings)
        let audioSources = try await readablePlaybackAudioSources(for: take, settings: settings)
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
        let audioTakeDuration = audioSources.map {
            CMTimeAdd($0.source.activeTakeStart, CMTimeMaximum(.zero, CMTimeSubtract($0.duration, $0.source.sourceStart)))
        }.max(by: { CMTimeCompare($0, $1) < 0 }) ?? .zero
        let exportPlan = sourceInputs.isEmpty ? nil : try FinalExportPlanning.plan(
            settings: settings, sceneEvents: sceneEvents, sources: sourceInputs, cuts: cuts
        )
        let takeDuration = exportPlan?.takeDuration ?? audioTakeDuration
        let timeMap = TimelineTimeMap(takeDuration: takeDuration, cuts: cuts)
        let playbackDuration = timeMap.outputDuration.cmTime
        guard CMTimeCompare(playbackDuration, .zero) > 0 else { throw RecorderError.exportUnavailable }

        let composition = AVMutableComposition()
        var compositedSources: [CompositedVideoSource] = []
        var videoAssets: [SceneLayerKind: AVComposition] = [:]
        for source in videoSources {
            guard let input = sourceInputs.first(where: { $0.kind == source.kind }) else { continue }
            let insertions = timeMap.mediaInsertions(.init(
                activeTakeStart: input.activeTakeStart,
                sourceTimeAtActiveStart: input.sourceTimeAtActiveStart,
                sourceEnd: input.duration
            ))
            guard let first = insertions.first, let last = insertions.last else { continue }
            guard let compositionTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw RecorderError.exportUnavailable
            }
            let videoAsset = AVMutableComposition()
            guard let videoTrack = videoAsset.addMutableTrack(
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
                try insertMappedTimeRange(
                    insertion,
                    of: source.track,
                    into: videoTrack
                )
            }
            videoTrack.preferredTransform = source.preferredTransform
            videoAssets[source.kind] = videoAsset
            compositedSources.append(CompositedVideoSource(
                source: source,
                compositionTrack: compositionTrack,
                timeRange: CMTimeRange(start: first.compositionStart.cmTime, end: CMTimeAdd(last.compositionStart.cmTime, last.duration.cmTime))
            ))
        }

        var audioInputs: [EditorPlaybackComposition.AudioInput] = []
        for audioSource in audioSources {
            if let input = addOptionalPlaybackAudio(PlaybackAudioInsertionRequest(
                audioSource: audioSource, composition: composition, timeMap: timeMap
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
            timeMap: timeMap,
            cuts: cuts,
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
    ) async throws -> [ReadablePlaybackAudioSource] {
        var sources: [ReadablePlaybackAudioSource] = []
        for originalSource in playbackAudioSources(for: take, settings: settings) {
            var audioSource = originalSource
            if audioSource.source == .microphone, settings.voiceCleanup.isEnabled {
                audioSource.url = try await VoiceCleanupProcessor.shared.processed(.init(url: audioSource.url, settings: settings.voiceCleanup))
            }
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
        for sidecar in sidecarAudioSources(.init(take: take, settings: settings)) where !includedSources.contains(sidecar.source) {
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
        let insertions = request.timeMap.mediaInsertions(.init(
            activeTakeStart: request.audioSource.source.activeTakeStart,
            sourceTimeAtActiveStart: request.audioSource.source.sourceStart,
            sourceEnd: request.audioSource.duration
        ))
        guard !insertions.isEmpty else {
            request.composition.removeTrack(compositionAudioTrack)
            return nil
        }
        do {
            for insertion in insertions {
                try insertMappedTimeRange(
                    insertion,
                    of: request.audioSource.track,
                    into: compositionAudioTrack
                )
            }
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

    private struct ReadablePlaybackAudioSource {
        let source: ExpectedAudioSource
        let asset: AVURLAsset
        let track: AVAssetTrack
        let duration: CMTime
    }

    private struct PlaybackAudioInsertionRequest {
        let audioSource: ReadablePlaybackAudioSource
        let composition: AVMutableComposition
        let timeMap: TimelineTimeMap
    }
}
