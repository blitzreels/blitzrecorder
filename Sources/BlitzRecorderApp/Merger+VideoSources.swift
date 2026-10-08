import AVFoundation
import BlitzRecorderCore
import CoreGraphics
import Foundation

extension Merger {
    static func availableVideoSources(for take: RecordingTake, settings: RecordingSettings) async throws -> [VideoSource] {
        for source in take.sourceReferences where !source.exists || !FileManager.default.isReadableFile(atPath: source.path) {
            throw RecorderError.mediaWriteFailed("The original video \(URL(fileURLWithPath: source.path).lastPathComponent) is unavailable. Reconnect its drive or restore the file to continue playback and export.")
        }
        var sources: [VideoSource] = []
        let capturedSources = settings.enabledSources
        let screenAsset = capturedSources.contains(.screen) ? await readableVideoAsset(kind: "screen", url: take.screenURL) : nil
        let cameraAsset = capturedSources.contains(.camera) ? await readableVideoAsset(kind: "camera", url: take.cameraURL) : nil
        let hasScreen = screenAsset != nil

        for layer in settings.sceneLayout.layerOrder {
            switch layer {
            case .screen:
                guard let screenAsset else { continue }
                sources.append(try await VideoSource(
                    kind: .screen,
                    asset: screenAsset.asset,
                    track: screenAsset.track,
                    duration: screenAsset.duration
                ))
            case .camera:
                guard let cameraAsset else { continue }
                let processedTiming = await processedLocalCameraTiming(
                    visibleCameraURL: take.cameraURL,
                    preservesPositiveOffset: hasScreen
                )
                sources.append(try await VideoSource(
                    kind: .camera,
                    asset: cameraAsset.asset,
                    track: cameraAsset.track,
                    duration: cameraAsset.duration,
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

    private struct ReadableVideoAsset {
        let asset: AVURLAsset
        let track: AVAssetTrack
        let duration: CMTime
    }

    struct VideoSource {
        let kind: SceneLayerKind
        let asset: AVURLAsset
        let track: AVAssetTrack
        let duration: CMTime
        let naturalSize: CGSize
        let preferredTransform: CGAffineTransform
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
        }
    }

    struct CompositedVideoSource {
        let kind: SceneLayerKind
        let asset: AVAsset
        let sourceStart: CMTime
        let compositionTrack: AVCompositionTrack
        let naturalSize: CGSize
        let preferredTransform: CGAffineTransform
        let timeRange: CMTimeRange

        init(source: VideoSource, compositionTrack: AVCompositionTrack, timeRange: CMTimeRange) {
            kind = source.kind
            asset = source.asset
            sourceStart = compositionTrack.segments.first(where: { !$0.isEmpty })?.timeMapping.source.start ?? .zero
            self.compositionTrack = compositionTrack
            naturalSize = source.naturalSize
            preferredTransform = source.preferredTransform
            self.timeRange = timeRange
        }

        func isActive(during range: CMTimeRange) -> Bool {
            let intersection = CMTimeRangeGetIntersection(timeRange, otherRange: range)
            return intersection.isValid && CMTimeCompare(intersection.duration, .zero) > 0
        }
    }
}
