import AVFoundation
import BlitzRecorderCore
import Foundation

extension Merger {
    struct AudioSourcesRequest {
        let take: RecordingTake
        let settings: RecordingSettings
    }

    static func sidecarAudioSources(_ request: AudioSourcesRequest) -> [ExpectedAudioSource] {
        let take = request.take
        let settings = request.settings
        let sourceStart = { (source: CaptureSource) -> CMTime in
            let sourceTimelineOffset = take.sourceTimelineOffsets[source] ?? .zero
            let offset = CMTimeSubtract(take.timelineTrimOffset, sourceTimelineOffset)
            return CMTimeCompare(offset, .zero) > 0 ? offset : .zero
        }
        let activeTakeStart = { (source: CaptureSource) -> CMTime in
            CMTimeMaximum(.zero, CMTimeSubtract(take.sourceTimelineOffsets[source] ?? .zero, take.timelineTrimOffset))
        }
        return [
            ExpectedAudioSource(
                source: .microphone,
                url: take.audioURL,
                volume: Float(settings.microphoneGain),
                sourceStart: sourceStart(.microphone),
                activeTakeStart: activeTakeStart(.microphone)
            ),
            ExpectedAudioSource(
                source: .systemAudio,
                url: take.systemAudioURL,
                volume: Float(settings.systemAudioGain),
                sourceStart: sourceStart(.systemAudio),
                activeTakeStart: activeTakeStart(.systemAudio)
            )
        ]
    }

    static func expectedAudioSources(for take: RecordingTake, settings: RecordingSettings) -> [ExpectedAudioSource] {
        sidecarAudioSources(.init(take: take, settings: settings))
            .filter { settings.enabledSources.contains($0.source) }
    }

    static func addRequiredAudio(
        _ audioSource: ExpectedAudioSource,
        to composition: AVMutableComposition,
        timeMap: TimelineTimeMap
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

        let insertions = timeMap.mediaInsertions(TimelineMediaInsertionRequest(
            activeTakeStart: audioSource.activeTakeStart,
            sourceTimeAtActiveStart: audioSource.sourceStart,
            sourceEnd: audioDuration
        ))
        guard !insertions.isEmpty else {
            throw missingExpectedAudio(audioSource, reason: "file ends before the synchronized timeline starts")
        }
        for insertion in insertions {
            try insertMappedTimeRange(
                insertion,
                of: audioTrack,
                into: compositionAudioTrack
            )
        }

        let parameters = AVMutableAudioMixInputParameters(track: compositionAudioTrack)
        parameters.setVolume(max(0, min(2, audioSource.volume)), at: .zero)
        return parameters
    }

    static func addBackgroundMusic(
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

    static func validateExpectedAudio(
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

    struct ExpectedAudioSource {
        let source: CaptureSource
        var url: URL
        let volume: Float
        var sourceStart: CMTime = .zero
        var activeTakeStart: CMTime = .zero

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

    struct BackgroundMusicInsertionRequest {
        let selection: ExportBackgroundMusic
        let composition: AVMutableComposition
        let duration: CMTime
    }
}
