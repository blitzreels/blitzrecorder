import Foundation

enum TranscriptSegmentBuilder {
    struct SpeakerWord {
        let word: TranscriptWord
        let speakerID: String
    }

    struct SegmentRequest {
        let speakerID: String
        let words: [TranscriptWord]
    }

    static func segments(
        from words: [SpeakerWord]
    ) -> [RecordingTranscript.Segment] {
        guard let first = words.first else { return [] }
        var result: [RecordingTranscript.Segment] = []
        var speakerID = first.speakerID
        var current = [first.word]
        for item in words.dropFirst() {
            let previousEnd = current.last?.endTime ?? item.word.startTime
            let continues = item.speakerID == speakerID
                && item.word.startTime - previousEnd <= 2.5
                && !endsSentence(current.last?.text ?? "")
            if continues {
                current.append(item.word)
            } else {
                result.append(segment(SegmentRequest(speakerID: speakerID, words: current)))
                speakerID = item.speakerID
                current = [item.word]
            }
        }
        result.append(segment(SegmentRequest(speakerID: speakerID, words: current)))
        return result
    }

    static func segment(_ request: SegmentRequest) -> RecordingTranscript.Segment {
        let confidence = request.words.isEmpty
            ? 0
            : request.words.reduce(Float.zero) { $0 + $1.confidence } / Float(request.words.count)
        return RecordingTranscript.Segment(
            id: UUID(),
            speakerID: request.speakerID,
            startTime: request.words.first?.startTime ?? 0,
            endTime: request.words.last?.endTime ?? 0,
            text: joinedText(request.words.map(\.text)),
            confidence: confidence
        )
    }

    static func coalesced(
        _ segments: [RecordingTranscript.Segment]
    ) -> [RecordingTranscript.Segment] {
        var result: [RecordingTranscript.Segment] = []
        for segment in segments {
            guard let previous = result.last,
                  previous.speakerID == segment.speakerID,
                  segment.startTime - previous.endTime <= 2.5,
                  !endsSentence(previous.text) else {
                result.append(segment)
                continue
            }
            result[result.count - 1] = RecordingTranscript.Segment(
                id: previous.id,
                speakerID: previous.speakerID,
                startTime: previous.startTime,
                endTime: max(previous.endTime, segment.endTime),
                text: "\(previous.text) \(segment.text)",
                confidence: (previous.confidence + segment.confidence) / 2
            )
        }
        return result
    }

    static func joinedText(_ words: [String]) -> String {
        words.reduce(into: "") { result, word in
            let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let attachesToPrevious = trimmed.first.map {
                ".,!?;:%)]}".contains($0)
            } ?? false
            if result.isEmpty || attachesToPrevious {
                result += trimmed
            } else {
                result += " \(trimmed)"
            }
        }
    }

    static func endsSentence(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .last.map { ".!?".contains($0) } ?? false
    }
}
