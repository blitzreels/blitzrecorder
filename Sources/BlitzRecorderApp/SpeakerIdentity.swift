import Foundation

struct SpeakerVoice: Codable, Equatable, Sendable {
    let embedding: [Float]
    let duration: TimeInterval
    var model: String = "pyannote-community-1-256-v1"

    var isUsable: Bool {
        duration.isFinite && duration >= 3 && embedding.count == 256
            && embedding.allSatisfy(\.isFinite)
            && embedding.reduce(Float.zero) { $0 + $1 * $1 } > 0
    }
}

struct SpeakerIdentitySuggestion: Codable, Equatable, Sendable {
    let name: String
    let evidence: String
    let voiceSimilarity: Float?
    let profileID: UUID?

    var label: String {
        if let voiceSimilarity, voiceSimilarity.isFinite {
            return "\(Int((min(1, max(0, voiceSimilarity)) * 100).rounded()))% voice match"
        }
        return "Name mentioned in speech"
    }
}

struct SavedSpeakerVoice: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var samples: [SpeakerVoice]
    var preview: SavedSpeakerPreview? = nil
}

enum SpeakerIdentity {
    struct PreservationRequest {
        let transcript: RecordingTranscript
        let previous: RecordingTranscript
    }

    static func preservingNames(_ request: PreservationRequest) -> RecordingTranscript {
        var transcript = request.transcript
        let previousSegments = request.previous.segments.sorted { $0.startTime < $1.startTime }
        var overlaps: [String: [String: Double]] = [:]
        var cursor = 0
        for segment in transcript.segments.sorted(by: { $0.startTime < $1.startTime }) {
            while cursor < previousSegments.count && previousSegments[cursor].endTime <= segment.startTime {
                cursor += 1
            }
            for previous in previousSegments.dropFirst(cursor) {
                if previous.startTime >= segment.endTime { break }
                let overlap = max(0, min(segment.endTime, previous.endTime) - max(segment.startTime, previous.startTime))
                overlaps[segment.speakerID, default: [:]][previous.speakerID, default: 0] += overlap
            }
        }
        var used = Set<String>()
        for index in transcript.speakers.indices {
            let speaker = transcript.speakers[index]
            guard let candidate = overlaps[speaker.id]?.max(by: { $0.value < $1.value }),
                  candidate.value >= transcript.speakingDuration(for: speaker.id) * 0.65,
                  candidate.value >= request.previous.speakingDuration(for: candidate.key) * 0.65,
                  let previous = request.previous.speakers.first(where: { $0.id == candidate.key }),
                  !previous.name.isEmpty, previous.name != "You", used.insert(previous.id).inserted else { continue }
            transcript.speakers[index].name = previous.name
            transcript.speakers[index].context = previous.context
            transcript.speakers[index].savedVoiceID = previous.savedVoiceID
            transcript.speakers[index].identitySuggestion = nil
        }
        return transcript
    }

    struct SuggestionRequest {
        let transcript: RecordingTranscript
        let profiles: [SavedSpeakerVoice]
    }

    static func suggestingNames(_ request: SuggestionRequest) -> RecordingTranscript {
        var transcript = request.transcript
        transcript.speakers = transcript.speakers.map { speaker in
            guard speaker.name.isEmpty || speaker.name == "You" else { return speaker }
            var updated = speaker
            updated.identitySuggestion = speaker.voice.flatMap {
                match(.init(voice: $0, profiles: request.profiles))
            } ?? introduction(.init(speakerID: speaker.id, segments: transcript.segments))
            return updated
        }
        let suggestedIDs = transcript.speakers.compactMap { $0.identitySuggestion?.profileID }
        let duplicated = Set(suggestedIDs.filter { id in suggestedIDs.filter { $0 == id }.count > 1 })
        for index in transcript.speakers.indices {
            if let id = transcript.speakers[index].identitySuggestion?.profileID, duplicated.contains(id) {
                transcript.speakers[index].identitySuggestion = nil
            }
        }
        return transcript
    }

    struct MatchRequest {
        let voice: SpeakerVoice
        let profiles: [SavedSpeakerVoice]
    }

    static func match(_ request: MatchRequest) -> SpeakerIdentitySuggestion? {
        guard request.voice.isUsable else { return nil }
        let ranked = request.profiles.compactMap { profile -> (SavedSpeakerVoice, Float)? in
            let similarities = profile.samples.filter {
                $0.isUsable && $0.model == request.voice.model
            }.map {
                1 - RecordingTranscriptAssembler.cosineDistance(request.voice.embedding, $0.embedding)
            }.filter(\.isFinite)
            guard let best = similarities.max() else { return nil }
            return (profile, best)
        }.sorted { $0.1 > $1.1 }
        guard let best = ranked.first, best.1 >= 0.8,
              ranked.count == 1 || best.1 - ranked[1].1 >= 0.08 else { return nil }
        return SpeakerIdentitySuggestion(
            name: best.0.name,
            evidence: "Similar to a voice you saved on this Mac. Similarity is not a probability of correct identity.",
            voiceSimilarity: best.1,
            profileID: best.0.id
        )
    }

    struct IntroductionRequest {
        let speakerID: String
        let segments: [RecordingTranscript.Segment]
    }

    static func introduction(_ request: IntroductionRequest) -> SpeakerIdentitySuggestion? {
        let pattern = #"(?:^|[.!?]\s+)(?:(?i:hi|hello|bonjour|salut)[,!.]?\s+)?(?i:my name is|je m['’]appelle|moi c['’]est)\s+([\p{Lu}][\p{L}'’-]{1,30})(?=[\s,.!?]|$)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        var names: [String: String] = [:]
        for segment in request.segments where segment.speakerID == request.speakerID && segment.confidence >= 0.75 {
            let text = segment.text
            for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range(at: 1), in: text) else { continue }
                names[String(text[range])] = text
            }
        }
        guard names.count == 1, let candidate = names.first else { return nil }
        return .init(name: candidate.key, evidence: candidate.value, voiceSimilarity: nil, profileID: nil)
    }
}

actor SpeakerVoiceStore {
    static let shared = SpeakerVoiceStore(url: FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
    )[0].appendingPathComponent("BlitzRecorder/SpeakerVoices.json"))

    let url: URL

    init(url: URL) {
        self.url = url
    }

    func profiles() throws -> [SavedSpeakerVoice] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([SavedSpeakerVoice].self, from: Data(contentsOf: url))
    }

    struct RememberRequest: Sendable {
        let name: String
        let voice: SpeakerVoice
        let profileID: UUID?
    }

    func remember(_ request: RememberRequest) throws -> UUID {
        let name = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != "You", request.voice.isUsable else {
            throw VoiceMemoryError.insufficientSpeech
        }
        var saved = try profiles()
        let id: UUID
        if let index = saved.firstIndex(where: { $0.id == request.profileID }) {
            id = saved[index].id
            saved[index].name = name
            if !saved[index].samples.contains(request.voice) {
                saved[index].samples.append(request.voice)
                saved[index].samples = Array(saved[index].samples.suffix(5))
            }
        } else {
            id = UUID()
            saved.append(.init(id: id, name: name, samples: [request.voice]))
        }
        try write(saved)
        return id
    }

    func forget(_ id: UUID) throws {
        let saved = try profiles()
        let preview = saved.first { $0.id == id }?.preview
        try write(saved.filter { $0.id != id })
        if let preview { try? FileManager.default.removeItem(at: previewURL(preview)) }
    }

    func write(_ profiles: [SavedSpeakerVoice]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(profiles).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    enum VoiceMemoryError: LocalizedError {
        case insufficientSpeech

        var errorDescription: String? {
            "Enter a name and run Fix speakers to collect at least three seconds of this voice."
        }
    }
}
