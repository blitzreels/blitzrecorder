import Foundation

struct TranscriptionQuality: Codable, Equatable, Sendable {
    struct Issue: Codable, Equatable, Sendable, Identifiable {
        enum Kind: String, Codable, Sendable {
            case uncertainSpeaker
            case unsupportedSpeech
            case languageMismatch
            case missingSpeech
            case speakerCountMismatch
            case similarVoices
            case unverifiedSpeech
            case unstableSpeaker
        }

        let kind: Kind
        let startTime: Double
        let endTime: Double

        var id: String { "\(kind.rawValue)-\(startTime)-\(endTime)" }

        var label: String {
            switch kind {
            case .uncertainSpeaker: "Speaker needs review"
            case .unsupportedSpeech: "Speech could not be confirmed"
            case .languageMismatch: "Language needs review"
            case .missingSpeech: "Speech was not transcribed"
            case .speakerCountMismatch: "Speaker count needs review"
            case .similarVoices: "Similar voices need speaker review"
            case .unverifiedSpeech: "Words need a fresh transcription"
            case .unstableSpeaker: "Speaker change needs review"
            }
        }
    }

    let pipelineVersion: Int
    let model: String
    let languages: [String]
    let issues: [Issue]

    var needsReview: Bool { !issues.isEmpty }

    struct SpeakerRequest {
        let transcript: RecordingTranscript
        let expectedCount: Int?
        let speechBySource: [TranscriptWord.Source: [RecordingTranscript.SpeechRange]]
    }

    static func speakerIssues(_ request: SpeakerRequest) -> [Issue] {
        let transcript = request.transcript
        var issues = transcript.segments.filter { $0.speakerID == RecordingTranscript.Speaker.unassignedID }.map {
            Issue(kind: .uncertainSpeaker, startTime: $0.startTime, endTime: $0.endTime)
        }
        if let expected = request.expectedCount, transcript.speakerCount != expected,
           !(transcript.words ?? []).isEmpty {
            issues.append(.init(kind: .speakerCountMismatch, startTime: 0, endTime: transcript.duration))
        }
        var sources: [String: Set<TranscriptWord.Source>] = [:]
        for word in transcript.words ?? [] {
            if let id = word.speakerID, let source = word.source { sources[id, default: []].insert(source) }
        }
        for left in transcript.speakers.indices {
            for right in transcript.speakers.indices where right > left {
                let a = transcript.speakers[left]
                let b = transcript.speakers[right]
                guard let voiceA = a.voice, let voiceB = b.voice, voiceA.isUsable, voiceB.isUsable,
                      !(sources[a.id] ?? []).intersection(sources[b.id] ?? []).isEmpty,
                      RecordingTranscriptAssembler.cosineDistance(voiceA.embedding, voiceB.embedding) < 0.15 else { continue }
                let affected = transcript.segments.filter { $0.speakerID == a.id || $0.speakerID == b.id }
                if let start = affected.map(\.startTime).min(), let end = affected.map(\.endTime).max() {
                    issues.append(.init(kind: .similarVoices, startTime: start, endTime: end))
                }
            }
        }
        for (source, ranges) in request.speechBySource {
            var continuous: [RecordingTranscript.SpeechRange] = []
            for range in ranges.sorted(by: { $0.startTime < $1.startTime }) {
                if let previous = continuous.last, range.startTime - previous.endTime <= 0.75,
                   range.endTime - previous.startTime <= 25 {
                    continuous[continuous.count - 1] = .init(startTime: previous.startTime,
                                                             endTime: max(previous.endTime, range.endTime))
                } else { continuous.append(range) }
            }
            for range in continuous {
                let identities = Set((transcript.words ?? []).filter {
                    $0.source == source && $0.startTime < range.endTime && $0.endTime >= range.startTime
                }.compactMap(\.speakerID)).subtracting([RecordingTranscript.Speaker.unassignedID])
                if identities.count > 1 {
                    issues.append(.init(kind: .unstableSpeaker, startTime: range.startTime, endTime: range.endTime))
                }
            }
        }
        return issues
    }
}
