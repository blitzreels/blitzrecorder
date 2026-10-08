import Foundation

struct RecordingTranscript: Codable, Equatable, Identifiable, Sendable {
    struct Speaker: Codable, Equatable, Identifiable, Sendable {
        let id: String
        var name: String
        var context: String
        var voice: SpeakerVoice? = nil
        var identitySuggestion: SpeakerIdentitySuggestion? = nil
        var savedVoiceID: UUID? = nil

        var displayName: String {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? id : trimmed
        }
    }

    struct Segment: Codable, Equatable, Identifiable, Sendable {
        let id: UUID
        let speakerID: String
        let startTime: TimeInterval
        let endTime: TimeInterval
        let text: String
        let confidence: Float
    }

    let version: Int
    let id: UUID
    let mediaPath: String
    let generatedAt: Date
    let duration: TimeInterval
    let confidence: Float
    let text: String
    let suggestedTitle: String?
    var speakers: [Speaker]
    let segments: [Segment]
    var words: [TranscriptWord]? = nil
    var speechRanges: [SpeechRange]? = nil

    struct SpeechRange: Codable, Equatable, Sendable {
        let startTime: Double
        let endTime: Double
    }

    var wordCount: Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    var silenceProtectedRanges: [SpeechRange] {
        let spoken: [SpeechRange]
        if let words, !words.isEmpty {
            spoken = words.map { .init(startTime: $0.startTime, endTime: $0.endTime) }
        } else {
            spoken = segments.map { .init(startTime: $0.startTime, endTime: $0.endTime) }
        }
        return spoken + (speechRanges ?? [])
    }

    var segmentCount: Int {
        segments.count
    }

    var speakerCount: Int {
        speakers.count
    }

    var wordsPerMinute: Int {
        guard duration > 0 else { return 0 }
        return Int((Double(wordCount) / (duration / 60)).rounded())
    }

    func speakerName(for id: String) -> String {
        speakers.first(where: { $0.id == id })?.displayName ?? id
    }

    func wordCount(for speakerID: String) -> Int {
        segments
            .filter { $0.speakerID == speakerID }
            .reduce(into: 0) { count, segment in
                count += segment.text.split(whereSeparator: \.isWhitespace).count
            }
    }

    func speakingDuration(for speakerID: String) -> TimeInterval {
        segments
            .filter { $0.speakerID == speakerID }
            .reduce(into: 0) { duration, segment in
                duration += max(0, segment.endTime - segment.startTime)
            }
    }

    func mergingSpeaker(
        _ request: TranscriptSpeakerMergeRequest
    ) -> RecordingTranscript {
        guard request.sourceSpeakerID != request.targetSpeakerID,
              speakers.contains(where: { $0.id == request.sourceSpeakerID }),
              speakers.contains(where: { $0.id == request.targetSpeakerID }) else {
            return self
        }

        let relabeledSegments = segments.map { segment in
            guard segment.speakerID == request.sourceSpeakerID else {
                return segment
            }
            return Segment(
                id: segment.id,
                speakerID: request.targetSpeakerID,
                startTime: segment.startTime,
                endTime: segment.endTime,
                text: segment.text,
                confidence: segment.confidence
            )
        }

        return RecordingTranscript(
            version: version,
            id: id,
            mediaPath: mediaPath,
            generatedAt: generatedAt,
            duration: duration,
            confidence: confidence,
            text: text,
            suggestedTitle: suggestedTitle,
            speakers: speakers.filter { $0.id != request.sourceSpeakerID },
            segments: TranscriptSegmentBuilder.coalesced(relabeledSegments),
            words: words,
            speechRanges: speechRanges
        )
    }

    var formattedText: String {
        guard !segments.isEmpty else { return text }
        return segments.map { segment in
            let timestamp = Self.timestamp(segment.startTime)
            return "[\(timestamp)] \(speakerName(for: segment.speakerID)): \(segment.text)"
        }
        .joined(separator: "\n\n")
    }

    var markdownText: String {
        markdownText(title: defaultMarkdownTitle)
    }

    func markdownText(title rawTitle: String) -> String {
        let resolvedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = Self.markdownEscaped(
            resolvedTitle.isEmpty ? defaultMarkdownTitle : resolvedTitle
        )
        var sections = ["# \(title)"]

        let contextualSpeakers = speakers.filter {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !$0.context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if !contextualSpeakers.isEmpty {
            let speakerLines = contextualSpeakers.map { speaker in
                let name = Self.markdownEscaped(speaker.displayName)
                let context = speaker.context.trimmingCharacters(in: .whitespacesAndNewlines)
                return context.isEmpty
                    ? "- **\(name)**"
                    : "- **\(name)** — \(context)"
            }
            sections.append("## Speakers\n\n\(speakerLines.joined(separator: "\n"))")
        }

        let transcriptBody: String
        if segments.isEmpty {
            transcriptBody = text
        } else {
            transcriptBody = segments.map { segment in
                let timestamp = Self.timestamp(segment.startTime)
                let speaker = Self.markdownEscaped(speakerName(for: segment.speakerID))
                return "**[\(timestamp)] \(speaker):** \(segment.text)"
            }
            .joined(separator: "\n\n")
        }
        sections.append("## Transcript\n\n\(transcriptBody)")
        return sections.joined(separator: "\n\n")
    }

    private var defaultMarkdownTitle: String {
        let rawTitle = suggestedTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let rawTitle, !rawTitle.isEmpty {
            return rawTitle
        }
        let mediaURL = URL(fileURLWithPath: mediaPath)
        if mediaURL.pathExtension == "blitzrecorder" {
            return "Recording transcript"
        }
        let mediaTitle = mediaURL.deletingPathExtension().lastPathComponent
        return mediaTitle.isEmpty ? "Transcript" : mediaTitle
    }

    private static func timestamp(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let remainingSeconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    private static func markdownEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "_", with: "\\_")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }
}

struct TranscriptSpeakerRenameRequest {
    let speakerID: String
    let name: String
    var voiceMemory: VoiceMemoryAction = .unchanged
    var profileID: UUID? = nil

    enum VoiceMemoryAction: Sendable {
        case unchanged
        case remember
        case forget
    }
}

extension RecordingTranscript {
    func renamingSpeaker(_ request: TranscriptSpeakerRenameRequest) -> RecordingTranscript {
        guard speakers.contains(where: { $0.id == request.speakerID }) else { return self }
        var transcript = self
        transcript.speakers = speakers.map { speaker in
            guard speaker.id == request.speakerID else { return speaker }
            var renamed = speaker
            renamed.name = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
            renamed.identitySuggestion = nil
            return renamed
        }
        return transcript
    }
}

struct TranscriptSpeakerMergeRequest {
    let sourceSpeakerID: String
    let targetSpeakerID: String
}

struct TranscriptWord: Codable, Equatable, Sendable {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Float
    var speakerID: String? = nil
}

struct DiarizedInterval: Equatable, Sendable {
    let speakerID: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let embedding: [Float]

    init(
        speakerID: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        embedding: [Float] = []
    ) {
        self.speakerID = speakerID
        self.startTime = startTime
        self.endTime = endTime
        self.embedding = embedding
    }
}
