import AVFoundation
import Foundation

extension EditorPlaybackController {
    typealias AudioMixTrack = (
        source: CaptureSource, track: AVCompositionTrack, baseVolume: Float, version: EditorMicrophoneVersion?
    )

    struct ProjectSettings {
        let outputFormat: OutputVideoFormat
        let settings: RecordingSettings

        init(project: RecordingProject, baseSettings: RecordingSettings) {
            outputFormat = project.outputVideoFormat(fallback: baseSettings.outputVideoFormat)
            settings = TakeFileStore().recordingSettings(
                from: project,
                baseSettings: baseSettings,
                outputFormat: outputFormat
            )
        }
    }

    struct ExportedAssetInfo {
        let duration: CMTime
        let size: CGSize
    }

    static func exportedAssetInfo(_ asset: AVURLAsset) async throws -> ExportedAssetInfo {
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { return ExportedAssetInfo(duration: duration, size: .zero) }
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let rect = CGRect(origin: .zero, size: naturalSize).applying(transform).standardized
        return ExportedAssetInfo(duration: duration, size: CGSize(width: abs(rect.width), height: abs(rect.height)))
    }

    static func makePlayer(_ item: AVPlayerItem) -> AVPlayer {
        item.audioTimePitchAlgorithm = .timeDomain
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = false
        return player
    }

    static func longestPlayer(among candidates: [AVPlayer]) async -> AVPlayer? {
        var durations: [Double] = []
        for player in candidates {
            let duration = try? await player.currentItem?.asset.load(.duration)
            durations.append(duration?.seconds ?? 0)
        }
        guard let index = EditorPlaybackClockSelection.index(for: durations) else { return nil }
        return candidates[index]
    }

    static func audioComposition(
        for inputs: [EditorPlaybackComposition.AudioInput]
    ) -> (composition: AVMutableComposition, tracks: [AudioMixTrack])? {
        guard !inputs.isEmpty else { return nil }
        let composition = AVMutableComposition()
        var mixTracks: [AudioMixTrack] = []
        for input in inputs {
            guard let track = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { continue }
            let range = input.track.timeRange
            guard CMTimeCompare(range.duration, .zero) > 0 else { continue }
            try? track.insertTimeRange(range, of: input.track, at: range.start)
            mixTracks.append((input.source, track, input.volume, input.version))
        }
        guard !mixTracks.isEmpty else { return nil }
        return (composition, mixTracks)
    }

    /// Music ducking only affects export, so it never needs new preview audio.
    static func playbackVoiceCleanup(_ settings: VoiceCleanupSettings) -> VoiceCleanupSettings {
        guard settings.isEnabled else { return .disabled }
        var playback = settings
        playback.ducksMusic = false
        return playback
    }
}
