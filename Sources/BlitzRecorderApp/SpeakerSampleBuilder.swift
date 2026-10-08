import AVFoundation
import Foundation

actor SpeakerSampleBuilder {
    static let shared = SpeakerSampleBuilder()

    struct Sample: Sendable {
        let url: URL
        let sourceTitle: String
        let sourceProjectID: UUID
        let duration: Double
        let text: String
    }

    struct Request {
        let project: RecordingProject
        let transcript: RecordingTranscript
        let speakerID: String
    }

    struct RangeRequest {
        let transcript: RecordingTranscript
        let speakerID: String
    }

    struct Range: Equatable {
        let start: Double
        let end: Double
        let text: String
    }

    nonisolated static func ranges(_ request: RangeRequest) -> [Range] {
        let others = request.transcript.segments.filter { $0.speakerID != request.speakerID }
        let candidates: [Range] = request.transcript.segments.filter {
            $0.speakerID == request.speakerID && $0.startTime.isFinite && $0.endTime.isFinite
                && $0.startTime >= 0 && $0.endTime - $0.startTime >= 3 && $0.confidence >= 0.65
        }.sorted { $0.startTime < $1.startTime }.compactMap { segment in
            let end = min(segment.startTime + 12, segment.endTime, request.transcript.duration)
            guard end - segment.startTime >= 3,
                  !others.contains(where: { min($0.endTime, end) - max($0.startTime, segment.startTime) > 0.1 }) else {
                return nil
            }
            return Range(start: segment.startTime, end: end, text: segment.text)
        }
        return candidates.sorted {
            let leftIsLong = $0.end - $0.start >= 8
            let rightIsLong = $1.end - $1.start >= 8
            return leftIsLong == rightIsLong ? $0.start < $1.start : leftIsLong
        }
    }

    struct FindRequest {
        let profile: SavedSpeakerVoice
        let projects: [RecordingProjectHistory.Entry]
    }

    func find(_ request: FindRequest) async throws -> Sample {
        let artifacts = TranscriptArtifactStore()
        for entry in request.projects {
            try Task.checkCancellation()
            guard let project = try? TakeFileStore().loadRecordingProject(at: URL(fileURLWithPath: entry.projectPath)),
                  let transcript = try? artifacts.load(from: artifacts.locations(for: project).jsonURL) else { continue }
            for speaker in transcript.speakers {
                let isReference = speaker.voice.map { request.profile.samples.contains($0) } ?? false
                guard speaker.savedVoiceID == request.profile.id || isReference else { continue }
                if let sample = try? await make(.init(project: project, transcript: transcript, speakerID: speaker.id)) {
                    return Sample(url: sample.url, sourceTitle: entry.title, sourceProjectID: sample.sourceProjectID,
                                  duration: sample.duration, text: sample.text)
                }
            }
        }
        throw SpeakerVoiceStore.PreviewError.missingSample
    }

    func make(_ request: Request) async throws -> Sample {
        for range in Self.ranges(.init(transcript: request.transcript, speakerID: request.speakerID)).prefix(8) {
            try Task.checkCancellation()
            if let sample = try? await export(.init(project: request.project, range: range)) { return sample }
        }
        throw SpeakerVoiceStore.PreviewError.missingSample
    }

    private struct ExportRequest {
        let project: RecordingProject
        let range: Range
    }

    private func export(_ request: ExportRequest) async throws -> Sample {
        let composition = AVMutableComposition()
        let primary = request.project.sources.filter { ["microphone", "systemAudio"].contains($0.role) }
        let sources = primary.isEmpty ? request.project.sources.filter { ["screen", "camera"].contains($0.role) } : primary
        var parameters: [AVMutableAudioMixInputParameters] = []
        for source in sources {
            let asset = AVURLAsset(url: URL(fileURLWithPath: source.path))
            guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
                  let duration = try? await asset.load(.duration).seconds, duration.isFinite else { continue }
            let offset = (request.project.sourceTimelineOffsetSeconds[source.role] ?? 0)
                - request.project.timelineTrimOffsetSeconds
            let start = max(request.range.start, offset)
            let end = min(request.range.end, offset + duration)
            guard end - start >= 0.1,
                  let target = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                continue
            }
            try target.insertTimeRange(CMTimeRange(
                start: CMTime(seconds: start - offset, preferredTimescale: 48_000),
                duration: CMTime(seconds: end - start, preferredTimescale: 48_000)), of: track,
                at: CMTime(seconds: start - request.range.start, preferredTimescale: 48_000))
            parameters.append(AVMutableAudioMixInputParameters(track: target))
        }
        guard !parameters.isEmpty,
              let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw SpeakerVoiceStore.PreviewError.missingSample
        }
        for parameter in parameters { parameter.setVolume(1 / Float(parameters.count), at: .zero) }
        let mix = AVMutableAudioMix()
        mix.inputParameters = parameters
        exporter.audioMix = mix
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        do {
            try await exporter.export(to: output, as: .m4a)
            try Task.checkCancellation()
            let file = try AVAudioFile(forReading: output)
            let duration = Double(file.length) / file.processingFormat.sampleRate
            guard duration >= 3, duration <= 12.2, try hasAudibleContent(file) else {
                throw SpeakerVoiceStore.PreviewError.missingSample
            }
            return Sample(url: output, sourceTitle: request.project.title, sourceProjectID: request.project.id,
                          duration: duration, text: request.range.text)
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }

    private func hasAudibleContent(_ file: AVAudioFile) throws -> Bool {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4_096) else { return false }
        while file.framePosition < file.length {
            try file.read(into: buffer)
            guard buffer.frameLength > 0, let channels = buffer.floatChannelData else { return false }
            for channel in 0..<Int(file.processingFormat.channelCount) {
                let samples = UnsafeBufferPointer(start: channels[channel], count: Int(buffer.frameLength))
                let energy = samples.reduce(Float.zero) { $0 + $1 * $1 } / Float(samples.count)
                if energy > 0.000_01 { return true }
            }
        }
        return false
    }
}
