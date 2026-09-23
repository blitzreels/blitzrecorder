import Foundation

struct RecordingTranscript: Codable, Equatable, Identifiable, Sendable {
    struct Speaker: Codable, Equatable, Identifiable, Sendable {
        let id: String
        var name: String
        var context: String

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
            segments: Self.coalesced(relabeledSegments),
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

    private static func coalesced(
        _ segments: [Segment]
    ) -> [Segment] {
        var result: [Segment] = []
        for segment in segments {
            guard let previous = result.last,
                  previous.speakerID == segment.speakerID,
                  segment.startTime - previous.endTime <= 1.2 else {
                result.append(segment)
                continue
            }
            result[result.count - 1] = Segment(
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

    func mappedToEditedTimeline(_ timeMap: TimelineTimeMap) -> RecordingTranscript {
        guard timeMap.hasCuts else { return self }

        let mappedWords = (words ?? []).compactMap { word -> (word: TranscriptWord, speakerID: String)? in
            let midpoint = (word.startTime + word.endTime) / 2
            guard !timeMap.isRemoved(takeTime: midpoint) else { return nil }
            let start = timeMap.outputSeconds(forTakeSeconds: word.startTime)
            let end = timeMap.outputSeconds(forTakeSeconds: word.endTime)
            guard end > start else { return nil }
            let speakerID = word.speakerID ?? speakerID(atTakeTime: midpoint)
            return (
                TranscriptWord(
                    text: word.text,
                    startTime: start,
                    endTime: end,
                    confidence: word.confidence,
                    speakerID: speakerID
                ),
                speakerID
            )
        }

        let mappedSegments: [Segment]
        if mappedWords.isEmpty {
            mappedSegments = Self.coalesced(segments.flatMap { segment in
                Self.keptPieces(of: segment, timeMap: timeMap)
            })
        } else {
            mappedSegments = Self.coalesced(Self.segments(from: mappedWords))
        }

        let remainingSpeakerIDs = Set(mappedSegments.map(\.speakerID))
        let mappedSpeakers = speakers.filter { remainingSpeakerIDs.contains($0.id) }
        let mappedSpeechRanges = (speechRanges ?? []).flatMap { range -> [SpeechRange] in
            Self.keptOutputRanges(
                start: range.startTime,
                end: range.endTime,
                timeMap: timeMap
            ).map { SpeechRange(startTime: $0.start, endTime: $0.end) }
        }

        return RecordingTranscript(
            version: version,
            id: id,
            mediaPath: mediaPath,
            generatedAt: generatedAt,
            duration: timeMap.outputDuration.seconds,
            confidence: confidence,
            text: mappedSegments.map(\.text).joined(separator: " "),
            suggestedTitle: suggestedTitle,
            speakers: mappedSpeakers.isEmpty ? speakers : mappedSpeakers,
            segments: mappedSegments,
            words: words == nil ? nil : mappedWords.map(\.word),
            speechRanges: mappedSpeechRanges
        )
    }

    private func speakerID(atTakeTime time: TimeInterval) -> String {
        segments.last { $0.startTime <= time && time < $0.endTime }?.speakerID
            ?? speakers.first?.id
            ?? "Speaker 1"
    }

    private static func keptPieces(
        of segment: Segment,
        timeMap: TimelineTimeMap
    ) -> [Segment] {
        keptOutputRanges(start: segment.startTime, end: segment.endTime, timeMap: timeMap).map { range in
            Segment(
                id: UUID(),
                speakerID: segment.speakerID,
                startTime: range.start,
                endTime: range.end,
                text: segment.text,
                confidence: segment.confidence
            )
        }
    }

    private static func keptOutputRanges(
        start: TimeInterval,
        end: TimeInterval,
        timeMap: TimelineTimeMap
    ) -> [(start: TimeInterval, end: TimeInterval)] {
        timeMap.keptRanges.compactMap { range in
            let overlapStart = max(start, range.takeStart.seconds)
            let overlapEnd = min(end, range.takeEnd.seconds)
            guard overlapEnd > overlapStart else { return nil }
            let outputStart = timeMap.outputSeconds(forTakeSeconds: overlapStart)
            let outputEnd = timeMap.outputSeconds(forTakeSeconds: overlapEnd)
            guard outputEnd > outputStart else { return nil }
            return (outputStart, outputEnd)
        }
    }

    private static func segments(
        from words: [(word: TranscriptWord, speakerID: String)]
    ) -> [Segment] {
        guard let first = words.first else { return [] }
        var result: [Segment] = []
        var speakerID = first.speakerID
        var current = [first.word]
        for item in words.dropFirst() {
            let previousEnd = current.last?.endTime ?? item.word.startTime
            let continues = item.speakerID == speakerID
                && item.word.startTime - previousEnd <= 1.2
            if continues {
                current.append(item.word)
            } else {
                result.append(segment(speakerID: speakerID, words: current))
                speakerID = item.speakerID
                current = [item.word]
            }
        }
        result.append(segment(speakerID: speakerID, words: current))
        return result
    }

    private static func segment(speakerID: String, words: [TranscriptWord]) -> Segment {
        let confidence = words.isEmpty
            ? 0
            : words.reduce(Float.zero) { $0 + $1.confidence } / Float(words.count)
        return Segment(
            id: UUID(),
            speakerID: speakerID,
            startTime: words.first?.startTime ?? 0,
            endTime: words.last?.endTime ?? 0,
            text: joinedText(words.map(\.text)),
            confidence: confidence
        )
    }

    private static func joinedText(_ words: [String]) -> String {
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

enum RecordingTranscriptAssembler {
    enum WordSource: Equatable, Sendable {
        case microphone
        case systemAudio
        case mixed
    }

    struct Request {
        let mediaPath: String
        let generatedAt: Date
        let duration: TimeInterval
        let confidence: Float
        let text: String
        let suggestedTitle: String?
        let words: [TranscriptWord]
        let wordSources: [WordSource]
        let diarizedIntervals: [DiarizedInterval]

        init(
            mediaPath: String,
            generatedAt: Date,
            duration: TimeInterval,
            confidence: Float,
            text: String,
            suggestedTitle: String?,
            words: [TranscriptWord],
            wordSources: [WordSource] = [],
            diarizedIntervals: [DiarizedInterval]
        ) {
            self.mediaPath = mediaPath
            self.generatedAt = generatedAt
            self.duration = duration
            self.confidence = confidence
            self.text = text
            self.suggestedTitle = suggestedTitle
            self.words = words
            self.wordSources = wordSources
            self.diarizedIntervals = diarizedIntervals
        }
    }

    static let microphoneSpeakerID = "mic"
    static let systemSpeakerPrefix = "sys-"
    static let microphoneSpeakerPrefix = "mic-"

    static func assemble(_ request: Request) -> RecordingTranscript {
        let sources = request.wordSources.count == request.words.count
            ? request.wordSources
            : Array(repeating: WordSource.mixed, count: request.words.count)
        let paired = zip(request.words, sources).sorted { left, right in
            if left.0.startTime == right.0.startTime {
                return left.0.endTime < right.0.endTime
            }
            return left.0.startTime < right.0.startTime
        }
        let mergedIntervals = mergeAcousticDuplicates(request.diarizedIntervals)
        let hostSpeakerID = mergedIntervals.first {
            isMicrophoneSpeaker($0.speakerID)
        }?.speakerID ?? microphoneSpeakerID
        let filtered = paired.compactMap { word, source -> (TranscriptWord, WordSource)? in
            if source == .systemAudio, isMicrophoneEcho(word: word, intervals: mergedIntervals) {
                return nil
            }
            return (word, source)
        }
        let assignedWords = filtered.map { word, source in
            AssignedWord(
                word: word,
                rawSpeakerID: speakerID(SpeakerResolutionRequest(
                    word: word,
                    source: source,
                    hostSpeakerID: hostSpeakerID,
                    intervals: mergedIntervals
                ))
            )
        }
        let hasSeparateTracks = sources.contains { $0 != .mixed }
        let stabilizedWords = hasSeparateTracks
            ? assignedWords
            : stabilizedSpeakerAssignments(assignedWords)
        let normalizedSpeakerIDs = normalizedSpeakerIDs(for: stabilizedWords)
        let normalizedWords = stabilizedWords.map { assignedWord in
            NormalizedWord(
                word: assignedWord.word,
                speakerID: normalizedSpeakerIDs[assignedWord.rawSpeakerID] ?? "Speaker 1"
            )
        }
        let segments = segments(from: normalizedWords)
        let speakers = normalizedSpeakerIDs
            .sorted { speakerNumber($0.value) < speakerNumber($1.value) }
            .map { rawID, displayID in
                RecordingTranscript.Speaker(
                    id: displayID,
                    name: isMicrophoneSpeaker(rawID) ? "You" : "",
                    context: ""
                )
            }

        return RecordingTranscript(
            version: 2,
            id: UUID(),
            mediaPath: request.mediaPath,
            generatedAt: request.generatedAt,
            duration: request.duration,
            confidence: request.confidence,
            text: joinedText(normalizedWords.map(\.word.text)),
            suggestedTitle: request.suggestedTitle,
            speakers: speakers,
            segments: segments,
            words: normalizedWords.map { assigned in
                TranscriptWord(
                    text: assigned.word.text,
                    startTime: assigned.word.startTime,
                    endTime: assigned.word.endTime,
                    confidence: assigned.word.confidence,
                    speakerID: assigned.speakerID
                )
            },
            speechRanges: request.diarizedIntervals.map {
                .init(startTime: $0.startTime, endTime: $0.endTime)
            }
        )
    }

    private struct AssignedWord {
        let word: TranscriptWord
        let rawSpeakerID: String
    }

    private struct NormalizedWord {
        let word: TranscriptWord
        let speakerID: String
    }

    private struct SpeakerResolutionRequest {
        let word: TranscriptWord
        let source: WordSource
        let hostSpeakerID: String
        let intervals: [DiarizedInterval]
    }

    private struct SegmentRequest {
        let speakerID: String
        let words: [TranscriptWord]
    }

    private static func speakerID(_ request: SpeakerResolutionRequest) -> String {
        switch request.source {
        case .microphone:
            return request.hostSpeakerID
        case .systemAudio:
            return speakerID(
                word: request.word,
                intervals: request.intervals.filter { $0.speakerID.hasPrefix(systemSpeakerPrefix) }
            )
        case .mixed:
            return speakerID(word: request.word, intervals: request.intervals)
        }
    }

    private static func speakerID(
        word: TranscriptWord,
        intervals: [DiarizedInterval]
    ) -> String {
        let midpoint = (word.startTime + word.endTime) / 2
        if let containing = intervals.first(where: { interval in
            midpoint >= interval.startTime && midpoint <= interval.endTime
        }) {
            return containing.speakerID
        }

        let bestOverlap = intervals
            .map { interval in
                (
                    interval.speakerID,
                    max(
                        0,
                        min(word.endTime, interval.endTime)
                            - max(word.startTime, interval.startTime)
                    )
                )
            }
            .max { left, right in left.1 < right.1 }

        if let bestOverlap, bestOverlap.1 > 0 {
            return bestOverlap.0
        }
        let nearestInterval = intervals
            .map { interval in
                let distance: TimeInterval
                if word.endTime < interval.startTime {
                    distance = interval.startTime - word.endTime
                } else {
                    distance = word.startTime - interval.endTime
                }
                return (interval.speakerID, max(0, distance))
            }
            .min { left, right in left.1 < right.1 }
        if let nearestInterval, nearestInterval.1 <= 0.5 {
            return nearestInterval.0
        }
        return "undiarized"
    }

    private static func isMicrophoneSpeaker(_ speakerID: String) -> Bool {
        speakerID == microphoneSpeakerID || speakerID.hasPrefix(microphoneSpeakerPrefix)
    }

    private static func isMicrophoneEcho(
        word: TranscriptWord,
        intervals: [DiarizedInterval]
    ) -> Bool {
        let systemIntervals = intervals.filter { $0.speakerID.hasPrefix(systemSpeakerPrefix) }
        if speakerID(word: word, intervals: systemIntervals) != "undiarized" {
            return false
        }
        let microphoneIntervals = intervals.filter { isMicrophoneSpeaker($0.speakerID) }
        return speakerID(word: word, intervals: microphoneIntervals) != "undiarized"
    }

    private static func normalizedSpeakerIDs(
        for words: [AssignedWord]
    ) -> [String: String] {
        var ordered: [String] = []
        for word in words where !ordered.contains(word.rawSpeakerID) {
            ordered.append(word.rawSpeakerID)
        }
        let appearance = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($0.element, $0.offset) })
        ordered.sort { left, right in
            let leftMic = isMicrophoneSpeaker(left)
            let rightMic = isMicrophoneSpeaker(right)
            if leftMic != rightMic { return leftMic }
            return (appearance[left] ?? 0) < (appearance[right] ?? 0)
        }
        var result: [String: String] = [:]
        for speakerID in ordered {
            result[speakerID] = "Speaker \(result.count + 1)"
        }
        if result.isEmpty {
            result["undiarized"] = "Speaker 1"
        }
        return result
    }

    private static func stabilizedSpeakerAssignments(
        _ words: [AssignedWord]
    ) -> [AssignedWord] {
        guard words.count >= 100 else { return words }
        let counts = Dictionary(grouping: words, by: \.rawSpeakerID)
            .mapValues(\.count)
        guard counts.count > 1,
              let dominant = counts.max(by: { $0.value < $1.value }) else {
            return words
        }

        let fragmentSpeakerIDs: Set<String> = Set(counts.compactMap {
            speakerID, count -> String? in
            guard speakerID != dominant.key,
                  Double(count) / Double(words.count) <= 0.03 else {
                return nil
            }
            let durations = turnDurations(for: speakerID, words: words)
            guard durations.max() ?? 0 <= 5,
                  durations.reduce(0, +) <= 45 else {
                return nil
            }
            return speakerID
        })
        guard !fragmentSpeakerIDs.isEmpty else { return words }

        return words.map { assignedWord in
            guard fragmentSpeakerIDs.contains(assignedWord.rawSpeakerID) else {
                return assignedWord
            }
            return AssignedWord(
                word: assignedWord.word,
                rawSpeakerID: dominant.key
            )
        }
    }

    private static func turnDurations(
        for speakerID: String,
        words: [AssignedWord]
    ) -> [TimeInterval] {
        var durations: [TimeInterval] = []
        var turnStart: TimeInterval?
        var turnEnd: TimeInterval?

        for assignedWord in words {
            guard assignedWord.rawSpeakerID == speakerID else {
                if let turnStart, let turnEnd {
                    durations.append(max(0, turnEnd - turnStart))
                }
                turnStart = nil
                turnEnd = nil
                continue
            }
            if let currentEnd = turnEnd,
               assignedWord.word.startTime - currentEnd > 1.2,
               let currentStart = turnStart {
                durations.append(max(0, currentEnd - currentStart))
                turnStart = assignedWord.word.startTime
            } else if turnStart == nil {
                turnStart = assignedWord.word.startTime
            }
            turnEnd = assignedWord.word.endTime
        }

        if let turnStart, let turnEnd {
            durations.append(max(0, turnEnd - turnStart))
        }
        return durations
    }

    private static func segments(
        from words: [NormalizedWord]
    ) -> [RecordingTranscript.Segment] {
        guard let first = words.first else { return [] }

        var result: [RecordingTranscript.Segment] = []
        var currentSpeakerID = first.speakerID
        var currentWords = [first.word]

        for word in words.dropFirst() {
            let previousEnd = currentWords.last?.endTime ?? word.word.startTime
            let continuesSegment = word.speakerID == currentSpeakerID
                && word.word.startTime - previousEnd <= 1.2
            if continuesSegment {
                currentWords.append(word.word)
            } else {
                result.append(segment(
                    SegmentRequest(
                        speakerID: currentSpeakerID,
                        words: currentWords
                    )
                ))
                currentSpeakerID = word.speakerID
                currentWords = [word.word]
            }
        }

        result.append(segment(SegmentRequest(
            speakerID: currentSpeakerID,
            words: currentWords
        )))
        return result
    }

    private static func segment(_ request: SegmentRequest) -> RecordingTranscript.Segment {
        let confidence = request.words.isEmpty
            ? 0
            : request.words.reduce(Float.zero) { $0 + $1.confidence }
                / Float(request.words.count)
        return RecordingTranscript.Segment(
            id: UUID(),
            speakerID: request.speakerID,
            startTime: request.words.first?.startTime ?? 0,
            endTime: request.words.last?.endTime ?? 0,
            text: joinedText(request.words.map(\.text)),
            confidence: confidence
        )
    }

    private static func joinedText(_ words: [String]) -> String {
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

    private static func speakerNumber(_ speakerID: String) -> Int {
        Int(speakerID.split(separator: " ").last ?? "") ?? 0
    }

    static let acousticMergeMaxCosineDistance: Float = 0.12

    static func mergeAcousticDuplicates(
        _ intervals: [DiarizedInterval]
    ) -> [DiarizedInterval] {
        let centroids = speakerCentroids(intervals)
        let speakerIDs = centroids.keys.sorted {
            firstAppearance($0, in: intervals) < firstAppearance($1, in: intervals)
        }
        guard speakerIDs.count > 1 else { return intervals }

        var canonical: [String: String] = [:]
        for speakerID in speakerIDs { canonical[speakerID] = speakerID }

        for i in speakerIDs.indices {
            for j in (i + 1)..<speakerIDs.count {
                let a = speakerIDs[i]
                let b = speakerIDs[j]
                guard resolve(b, in: canonical) != resolve(a, in: canonical),
                      let ea = centroids[a], let eb = centroids[b] else { continue }
                if cosineDistance(ea, eb) <= acousticMergeMaxCosineDistance {
                    let aCanon = resolve(a, in: canonical)
                    let bCanon = resolve(b, in: canonical)
                    if isMicrophoneSpeaker(bCanon) && !isMicrophoneSpeaker(aCanon) {
                        canonical[aCanon] = bCanon
                    } else {
                        canonical[bCanon] = aCanon
                    }
                }
            }
        }

        return intervals.map { interval in
            DiarizedInterval(
                speakerID: resolve(interval.speakerID, in: canonical),
                startTime: interval.startTime,
                endTime: interval.endTime,
                embedding: interval.embedding
            )
        }
    }

    private static func resolve(_ speakerID: String, in canonical: [String: String]) -> String {
        var current = speakerID
        while let next = canonical[current], next != current { current = next }
        return current
    }

    private static func firstAppearance(
        _ speakerID: String,
        in intervals: [DiarizedInterval]
    ) -> TimeInterval {
        intervals.first { $0.speakerID == speakerID }?.startTime ?? .greatestFiniteMagnitude
    }

    private static func speakerCentroids(
        _ intervals: [DiarizedInterval]
    ) -> [String: [Float]] {
        var sums: [String: [Float]] = [:]
        var weights: [String: Float] = [:]
        for interval in intervals {
            guard !interval.embedding.isEmpty else { continue }
            let weight = Float(max(interval.endTime - interval.startTime, 0.001))
            if var sum = sums[interval.speakerID], sum.count == interval.embedding.count {
                for k in sum.indices { sum[k] += interval.embedding[k] * weight }
                sums[interval.speakerID] = sum
                weights[interval.speakerID, default: 0] += weight
            } else if sums[interval.speakerID] == nil {
                sums[interval.speakerID] = interval.embedding.map { $0 * weight }
                weights[interval.speakerID] = weight
            }
        }
        return sums.reduce(into: [:]) { result, entry in
            let total = weights[entry.key] ?? 1
            result[entry.key] = entry.value.map { $0 / total }
        }
    }

    private static func cosineDistance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return .infinity }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for k in a.indices {
            dot += a[k] * b[k]
            normA += a[k] * a[k]
            normB += b[k] * b[k]
        }
        guard normA > 0, normB > 0 else { return .infinity }
        return 1 - dot / (normA.squareRoot() * normB.squareRoot())
    }
}

struct TranscriptArtifactStore {
    struct Locations: Equatable, Sendable {
        let jsonURL: URL
        let textURL: URL
    }

    struct SaveRequest {
        let transcript: RecordingTranscript
        let locations: Locations
    }

    func locations(for project: RecordingProject) -> Locations {
        if let transcriptPath = project.sources.first(where: { $0.role == "transcript" })?.path {
            let textURL = URL(fileURLWithPath: transcriptPath)
            return Locations(
                jsonURL: textURL.deletingPathExtension().appendingPathExtension("json"),
                textURL: textURL
            )
        }
        let directory = URL(fileURLWithPath: project.takeDirectoryPath, isDirectory: true)
        return Locations(
            jsonURL: directory.appendingPathComponent("transcript.json"),
            textURL: directory.appendingPathComponent("transcript.txt")
        )
    }

    func locations(for recordingURL: URL) -> Locations {
        let baseURL = recordingURL.deletingPathExtension()
        return Locations(
            jsonURL: baseURL.appendingPathExtension("transcript.json"),
            textURL: baseURL.appendingPathExtension("transcript.txt")
        )
    }

    func save(_ request: SaveRequest) throws {
        try FileManager.default.createDirectory(
            at: request.locations.jsonURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(request.transcript).write(
            to: request.locations.jsonURL,
            options: .atomic
        )
        try request.transcript.formattedText.write(
            to: request.locations.textURL,
            atomically: true,
            encoding: .utf8
        )
    }

    func load(from url: URL) throws -> RecordingTranscript {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            RecordingTranscript.self,
            from: Data(contentsOf: url)
        )
    }
}
