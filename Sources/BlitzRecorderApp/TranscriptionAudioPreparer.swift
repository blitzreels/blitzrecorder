import AVFoundation
import Foundation

enum TranscriptionMediaSource: Equatable, Sendable {
    case project(URL)
    case recording(URL)

    var key: String {
        switch self {
        case .project(let url):
            return url.path
        case .recording(let url):
            return url.path
        }
    }
}

struct PreparedTranscriptionTrack: Sendable {
    let source: RecordingTranscriptAssembler.WordSource
    let audioURL: URL
    let duration: TimeInterval
}

struct PreparedTranscriptionAudio: Sendable {
    let mediaPath: String
    let tracks: [PreparedTranscriptionTrack]
    let duration: TimeInterval
    let artifactLocations: TranscriptArtifactStore.Locations
}

struct TranscriptionAudioPreparer {
    private struct AudioInput {
        let source: RecordingTranscriptAssembler.WordSource
        let url: URL
        let trackIndex: Int
        let sourceStart: CMTime
        let timelineStart: CMTime
        let volume: Float
    }

    private struct ExportRequest {
        let inputs: [AudioInput]
        let outputURL: URL
    }

    private let fileStore = TakeFileStore()
    private let artifactStore = TranscriptArtifactStore()

    func prepare(_ source: TranscriptionMediaSource) async throws -> PreparedTranscriptionAudio {
        switch source {
        case .project(let projectURL):
            let project = try fileStore.loadRecordingProject(at: projectURL)
            let inputs = projectAudioInputs(project)
            guard !inputs.isEmpty else {
                throw RecorderError.speechUnavailable
            }
            let tracks = try await exportTracks(inputs)
            return PreparedTranscriptionAudio(
                mediaPath: project.finalVideoPath ?? project.projectPath,
                tracks: tracks,
                duration: tracks.map(\.duration).max() ?? 0,
                artifactLocations: artifactStore.locations(for: project)
            )
        case .recording(let recordingURL):
            let inputs = try await recordingAudioInputs(recordingURL)
            guard !inputs.isEmpty else {
                throw RecorderError.speechUnavailable
            }
            let tracks = try await exportTracks(inputs)
            return PreparedTranscriptionAudio(
                mediaPath: recordingURL.path,
                tracks: tracks,
                duration: tracks.map(\.duration).max() ?? 0,
                artifactLocations: artifactStore.locations(for: recordingURL)
            )
        }
    }

    private func exportTracks(_ inputs: [AudioInput]) async throws -> [PreparedTranscriptionTrack] {
        var tracks: [PreparedTranscriptionTrack] = []
        do {
            for input in inputs {
                let outputURL = try temporaryAudioURL()
                try await export(ExportRequest(inputs: [input], outputURL: outputURL))
                tracks.append(PreparedTranscriptionTrack(
                    source: input.source,
                    audioURL: outputURL,
                    duration: try audioDuration(outputURL)
                ))
            }
            return tracks
        } catch {
            for track in tracks {
                try? FileManager.default.removeItem(at: track.audioURL)
            }
            throw error
        }
    }

    private func projectAudioInputs(_ project: RecordingProject) -> [AudioInput] {
        project.sources.compactMap { source in
            guard source.exists,
                  source.role == "microphone"
                    || source.role == "systemAudio" else {
                return nil
            }
            let url = URL(fileURLWithPath: source.path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                return nil
            }
            let sourceTimelineOffset = project.sourceTimelineOffsetSeconds[source.role] ?? 0
            let sourceStart = max(
                0,
                project.timelineTrimOffsetSeconds - sourceTimelineOffset
            )
            let volume: Float
            if source.role == "microphone" {
                volume = Float(project.settings.microphoneGain ?? 1)
            } else {
                volume = Float(project.settings.systemAudioGain ?? 1)
            }
            return AudioInput(
                source: source.role == "microphone" ? .microphone : .systemAudio,
                url: url,
                trackIndex: 0,
                sourceStart: CMTime(seconds: sourceStart, preferredTimescale: 600),
                timelineStart: CMTime(seconds: max(0, sourceTimelineOffset - project.timelineTrimOffsetSeconds),
                                     preferredTimescale: 600),
                volume: max(0, min(2, volume))
            )
        }
    }

    private func recordingAudioInputs(_ url: URL) async throws -> [AudioInput] {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        var inputs: [AudioInput] = []
        for (index, track) in tracks.enumerated() {
            let timeRange = try await track.load(.timeRange)
            inputs.append(AudioInput(
                source: .mixed,
                url: url,
                trackIndex: index,
                sourceStart: timeRange.start,
                timelineStart: timeRange.start,
                volume: 1
            ))
        }
        return inputs
    }

    private func export(_ request: ExportRequest) async throws {
        let composition = AVMutableComposition()
        var mixParameters: [AVMutableAudioMixInputParameters] = []

        for input in request.inputs {
            let asset = AVURLAsset(url: input.url)
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            let duration = try await asset.load(.duration)
            let sourceDuration = CMTimeSubtract(duration, input.sourceStart)
            guard tracks.indices.contains(input.trackIndex),
                  CMTimeCompare(sourceDuration, .zero) > 0,
                  let compositionTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                  ) else {
                continue
            }
            let sourceTrack = tracks[input.trackIndex]
            try compositionTrack.insertTimeRange(
                CMTimeRange(start: input.sourceStart, duration: sourceDuration),
                of: sourceTrack,
                at: input.timelineStart
            )
            let parameters = AVMutableAudioMixInputParameters(track: compositionTrack)
            let headroom = max(1, request.inputs.reduce(Float.zero) { $0 + $1.volume })
            parameters.setVolume(input.volume / headroom, at: .zero)
            mixParameters.append(parameters)
        }

        let tracks = composition.tracks(withMediaType: .audio)
        guard !tracks.isEmpty else {
            throw RecorderError.speechUnavailable
        }
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = mixParameters
        let reader = try AVAssetReader(asset: composition)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1
        ]
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: settings)
        output.audioMix = audioMix
        guard reader.canAdd(output) else { throw RecorderError.speechUnavailable }
        reader.add(output)
        guard reader.startReading(), let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1) else {
            throw reader.error ?? RecorderError.speechUnavailable
        }
        defer { reader.cancelReading() }
        do {
            let file = try AVAudioFile(forWriting: request.outputURL, settings: settings,
                                       commonFormat: .pcmFormatFloat32, interleaved: false)
            while let sample = output.copyNextSampleBuffer() {
                try Task.checkCancellation()
                guard let data = CMSampleBufferGetDataBuffer(sample) else { throw RecorderError.speechUnavailable }
                let count = CMBlockBufferGetDataLength(data) / MemoryLayout<Float>.size
                guard count > 0 else { continue }
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
                      let samples = buffer.floatChannelData?[0] else { throw RecorderError.speechUnavailable }
                buffer.frameLength = AVAudioFrameCount(count)
                let status = CMBlockBufferCopyDataBytes(data, atOffset: 0,
                    dataLength: count * MemoryLayout<Float>.size, destination: samples)
                guard status == kCMBlockBufferNoErr else { throw RecorderError.speechUnavailable }
                let sampleTime = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                guard sampleTime.isFinite, sampleTime >= 0 else { throw RecorderError.speechUnavailable }
                let targetFrame = AVAudioFramePosition((sampleTime * 16_000).rounded())
                while file.framePosition < targetFrame {
                    let gap = AVAudioFrameCount(min(4096, targetFrame - file.framePosition))
                    guard let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: gap) else {
                        throw RecorderError.speechUnavailable
                    }
                    silence.frameLength = gap
                    silence.floatChannelData?[0].initialize(repeating: 0, count: Int(gap))
                    try file.write(from: silence)
                }
                try file.write(from: buffer)
            }
            guard reader.status == .completed else { throw reader.error ?? RecorderError.speechUnavailable }
        } catch {
            try? FileManager.default.removeItem(at: request.outputURL)
            throw error
        }
    }

    private func audioDuration(_ url: URL) throws -> TimeInterval {
        let file = try AVAudioFile(forReading: url)
        return Double(file.length) / file.processingFormat.sampleRate
    }

    private func temporaryAudioURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlitzRecorderTranscription", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("caf")
    }
}
