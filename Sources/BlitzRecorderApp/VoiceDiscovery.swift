import Foundation

struct DetectedVoice: Identifiable {
    struct Observation {
        let project: RecordingProjectHistory.Entry
        let transcript: RecordingTranscript
        let speakerID: String
        let voice: SpeakerVoice
    }

    let id = UUID()
    let number: Int
    var observations: [Observation]

    var title: String { "Unknown voice \(number)" }
    var recordingCount: Int { Set(observations.map { $0.project.id }).count }
    var reference: Observation { observations[0] }
    var nameHint: String {
        let name = reference.transcript.speakers.first { $0.id == reference.speakerID }?.name ?? ""
        return name == "You" ? "" : name
    }
}

struct VoiceDiscoveryIndex {
    private(set) var voices: [DetectedVoice] = []
    private(set) var knownCount = 0
    private(set) var insufficientCount = 0

    struct Request {
        let project: RecordingProjectHistory.Entry
        let transcript: RecordingTranscript
        let profiles: [SavedSpeakerVoice]
    }

    mutating func include(_ request: Request) {
        for speaker in request.transcript.speakers {
            guard let voice = speaker.voice, voice.isUsable else {
                insufficientCount += 1
                continue
            }
            if request.profiles.contains(where: { $0.id == speaker.savedVoiceID || $0.samples.contains(voice) })
                || SpeakerIdentity.match(.init(voice: voice, profiles: request.profiles)) != nil {
                knownCount += 1
                continue
            }
            guard !SpeakerSampleBuilder.ranges(.init(transcript: request.transcript, speakerID: speaker.id)).isEmpty else {
                insufficientCount += 1
                continue
            }
            let observation = DetectedVoice.Observation(
                project: request.project, transcript: request.transcript, speakerID: speaker.id, voice: voice
            )
            let ranked = voices.indices.compactMap { index -> (Int, Float)? in
                let group = voices[index]
                guard !group.observations.contains(where: { $0.project.id == request.project.id }),
                      group.observations.allSatisfy({ $0.voice.model == voice.model }) else { return nil }
                let similarity = group.observations.map {
                    1 - RecordingTranscriptAssembler.cosineDistance($0.voice.embedding, voice.embedding)
                }.min() ?? 0
                return (index, similarity)
            }.sorted { $0.1 > $1.1 }
            if let best = ranked.first, best.1 >= 0.86,
               ranked.count == 1 || best.1 - ranked[1].1 >= 0.06 {
                voices[best.0].observations.append(observation)
            } else {
                voices.append(.init(number: voices.count + 1, observations: [observation]))
            }
        }
    }
}

enum VoiceDiscoveryAnalysis {
    struct Request {
        let intervals: [DiarizedInterval]
        let mediaPath: String
        let duration: Double
    }

    static func transcript(_ request: Request) -> RecordingTranscript {
        let intervals = request.intervals.filter {
            $0.startTime.isFinite && $0.endTime.isFinite && $0.startTime >= 0
                && $0.endTime > $0.startTime && $0.startTime < request.duration
        }.sorted { $0.startTime < $1.startTime }
        let labels = RecordingTranscriptAssembler.voiceClusterLabels(intervals)
        let groups = Dictionary(grouping: intervals) { labels[$0.speakerID] ?? $0.speakerID }
        let speakers = groups.keys.sorted().map { id in
            RecordingTranscript.Speaker(id: id, name: "", context: "",
                                        voice: RecordingTranscriptAssembler.speakerVoice(groups[id] ?? []))
        }
        let segments = intervals.map {
            RecordingTranscript.Segment(id: UUID(), speakerID: labels[$0.speakerID] ?? $0.speakerID,
                                        startTime: $0.startTime, endTime: min($0.endTime, request.duration),
                                        text: "", confidence: 1)
        }
        return RecordingTranscript(version: 2, id: UUID(), mediaPath: request.mediaPath, generatedAt: Date(),
                                   duration: request.duration, confidence: 0, text: "", suggestedTitle: nil,
                                   speakers: speakers, segments: TranscriptSegmentBuilder.coalesced(segments))
    }
}
