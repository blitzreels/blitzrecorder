import AVFoundation
import CoreMedia
import Foundation

/// Level meters for the extra microphones while the studio is idle. During a take each microphone's own
/// recorder reports its level instead.
@MainActor
final class MicrophoneTrackMonitors {
    private var monitors: [String: MicrophoneLevelMonitor] = [:]
    var levelHandler: ((String, Float) -> Void)?

    func start(deviceIDs: [String], settings: RecordingSettings) {
        stop(keeping: Set(deviceIDs))
        for deviceID in deviceIDs where monitors[deviceID] == nil {
            guard MicrophoneDeviceSelection.microphone(id: deviceID) != nil else { continue }
            let monitor = MicrophoneLevelMonitor()
            monitor.levelHandler = { [weak self] level in self?.levelHandler?(deviceID, level) }
            do {
                try monitor.start(settings: settings.microphoneTrackSettings(deviceID: deviceID))
                monitors[deviceID] = monitor
            } catch {
                monitor.stop()
            }
        }
    }

    func stop(keeping deviceIDs: Set<String> = []) {
        for (deviceID, monitor) in monitors where !deviceIDs.contains(deviceID) {
            monitor.stop()
            monitors[deviceID] = nil
            levelHandler?(deviceID, 0)
        }
    }

    func run(take: RecordingTake, settings: RecordingSettings) -> MicrophoneTrackRun {
        let deviceIDs = settings.recordedExtraMicrophoneIDs
        let files = take.microphoneTrackFiles.dropFirst()
        let tracks = zip(deviceIDs, files).enumerated().map { index, pair in
            let recorder = AudioRecorder(keepsRecordingOnFailure: true)
            let deviceID = pair.0
            recorder.levelHandler = { [weak self] level in self?.levelHandler?(deviceID, level) }
            return MicrophoneTrackRun.Track(
                name: NumberedSourceTracks.microphones.displayName(index: index + 1),
                deviceID: deviceID,
                file: pair.1,
                recorder: recorder,
                settings: settings.microphoneTrackSettings(deviceID: deviceID)
            )
        }
        return MicrophoneTrackRun(take: take, settings: settings, tracks: tracks)
    }
}

/// Records a take's extra microphones on the take timeline, then mixes every microphone into the take's
/// microphone track (`audio.m4a`). Each microphone's own file stays in the take. An extra microphone that fails
/// never fails the take.
@MainActor
final class MicrophoneTrackRun {
    struct Track {
        let name: String
        let deviceID: String
        let file: SourceTrackFile
        let recorder: AudioRecorder
        let settings: RecordingSettings
    }

    struct Recorded {
        let name: String
        let file: SourceTrackFile
        let timelineOffset: CMTime
    }

    private let take: RecordingTake?
    private let settings: RecordingSettings
    private let tracks: [Track]
    private var recordingTracks: [Track] = []
    private var recorded: [Recorded] = []
    private var failures: [String] = []

    init(take: RecordingTake?, settings: RecordingSettings, tracks: [Track]) {
        self.take = take
        self.settings = settings
        self.tracks = tracks
    }

    static var none: MicrophoneTrackRun { MicrophoneTrackRun(take: nil, settings: RecordingSettings(), tracks: []) }

    func start(timelineStartTime: CMTime) async {
        let startups = tracks.map { track in
            (track, Task { @MainActor in
                guard MicrophoneDeviceSelection.microphone(id: track.deviceID) != nil else {
                    throw RecorderError.microphoneUnavailable
                }
                try await track.recorder.start(
                    url: track.file.url,
                    settings: track.settings,
                    timelineStartTime: timelineStartTime
                )
            })
        }
        for (track, startup) in startups {
            do {
                try await startup.value
                track.recorder.failureHandler = { [weak self] error in
                    Task { @MainActor [weak self] in
                        self?.noteFailure(name: track.name, reason: "stopped early (\(error.recorderFailureDescription)); what it recorded is kept")
                    }
                }
                recordingTracks.append(track)
            } catch {
                noteFailure(name: track.name, reason: error.recorderFailureDescription)
                _ = try? await track.recorder.stop()
            }
        }
    }

    func pause() {
        recordingTracks.forEach { $0.recorder.pause() }
    }

    func resume() {
        recordingTracks.forEach { $0.recorder.resume() }
    }

    /// Ends one microphone early, keeping what it recorded, when its device is unplugged.
    func stopTrack(deviceID: String) async {
        guard let track = recordingTracks.first(where: { $0.deviceID == deviceID }) else { return }
        recordingTracks.removeAll { $0.deviceID == deviceID }
        await finish(track)
    }

    /// Stops every extra microphone and corrects each one's clock drift.
    func stop() async {
        let tracks = recordingTracks
        recordingTracks = []
        for track in tracks {
            await finish(track)
        }
    }

    private func finish(_ track: Track) async {
        do {
            guard try await track.recorder.stop().wroteMedia else {
                noteFailure(name: track.name, reason: "No audio was captured from this microphone.")
                return
            }
            try await track.recorder.finalizeSynchronization()
            recorded.append(Recorded(name: track.name, file: track.file, timelineOffset: track.recorder.recordingTimelineOffset))
        } catch {
            noteFailure(name: track.name, reason: error.recorderFailureDescription)
        }
    }

    private func noteFailure(name: String, reason: String) {
        failures.append("\(name): \(reason)")
    }

    /// Writes the mix of every microphone that recorded to the take's microphone track and points the summary at it.
    func mergeIntoTake(
        _ summary: CaptureSourceRunSummary,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async -> CaptureSourceRunSummary {
        guard let take, let mainFile = take.microphoneTrackFiles.first else { return summary }
        var summary = summary
        var inputs: [MicrophoneMixdown.Input] = []
        if summary.completions[.microphone]?.wroteMedia == true,
           FileManager.default.fileExists(atPath: mainFile.url.path) {
            inputs.append(.init(url: mainFile.url, timelineOffset: summary.sourceTimelineOffsets[.microphone] ?? .zero))
        }
        inputs += recorded
            .filter { FileManager.default.fileExists(atPath: $0.file.url.path) }
            .map { .init(url: $0.file.url, timelineOffset: $0.timelineOffset) }
        defer { failures = [] }
        guard let first = inputs.first else {
            summary.microphoneTrackFailures = failures
            return summary
        }
        let placement: MicrophoneMixdown.Input
        do {
            if inputs.count == 1 {
                try MicrophoneMixdown.copy(first.url, to: take.audioURL)
                placement = first
            } else {
                let offset = try await MicrophoneMixdown.mix(.init(
                    inputs: inputs,
                    outputURL: take.audioURL,
                    format: settings.effectiveSourceAudioFormat,
                    bitrate: settings.finalAudioBitrate,
                    onProgress: onProgress
                ))
                placement = .init(url: take.audioURL, timelineOffset: offset)
            }
        } catch {
            failures.append("Microphones could not be mixed (\(error.recorderFailureDescription)). "
                + "The take uses one microphone; each microphone is still saved on its own.")
            guard (try? MicrophoneMixdown.copy(first.url, to: take.audioURL)) != nil else {
                summary.microphoneTrackFailures = failures
                return summary
            }
            placement = first
        }
        summary.completions[.microphone] = .wrote(take.audioURL)
        summary.sourceTimelineOffsets[.microphone] = CMTimeCompare(placement.timelineOffset, .zero) > 0
            ? placement.timelineOffset
            : nil
        summary.microphoneTrackFailures = failures
        return summary
    }
}
