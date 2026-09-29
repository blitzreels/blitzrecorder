import Foundation

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
        let labels = voiceClusterLabels(request.diarizedIntervals)
        let trackIntervals = TrackIntervals(.init(intervals: request.diarizedIntervals, labels: labels))
        return voiceGroupedTranscript(VoiceGroupingRequest(
            metadata: .init(request),
            words: withoutCrossTrackDuplicates(.init(
                paired: paired,
                intervals: request.diarizedIntervals,
                trackIntervals: trackIntervals
            )),
            intervals: request.diarizedIntervals,
            trackIntervals: trackIntervals
        ))
    }

    struct VoiceGroupingRequest {
        let metadata: TranscriptMetadata
        let words: [(TranscriptWord, WordSource)]
        let intervals: [DiarizedInterval]
        let trackIntervals: TrackIntervals
    }

    static func voiceGroupedTranscript(_ request: VoiceGroupingRequest) -> RecordingTranscript {
        assignedTranscript(AssignmentRequest(
            metadata: request.metadata,
            words: request.words.map { word, source in
                AssignedWord(
                    word: word,
                    rawSpeakerID: request.trackIntervals.speakerID(.init(word: word, source: source))
                )
            },
            hasSeparateTracks: request.words.contains { $0.1 != .mixed },
            speechRanges: request.intervals.map {
                .init(startTime: $0.startTime, endTime: $0.endTime)
            }
        ))
    }

    struct TranscriptMetadata {
        let id: UUID
        let mediaPath: String
        let generatedAt: Date
        let duration: TimeInterval
        let confidence: Float
        let suggestedTitle: String?

        init(_ request: Request) {
            id = UUID()
            mediaPath = request.mediaPath
            generatedAt = request.generatedAt
            duration = request.duration
            confidence = request.confidence
            suggestedTitle = request.suggestedTitle
        }

        init(_ transcript: RecordingTranscript) {
            id = transcript.id
            mediaPath = transcript.mediaPath
            generatedAt = transcript.generatedAt
            duration = transcript.duration
            confidence = transcript.confidence
            suggestedTitle = transcript.suggestedTitle
        }
    }

    struct AssignmentRequest {
        let metadata: TranscriptMetadata
        let words: [AssignedWord]
        let hasSeparateTracks: Bool
        let speechRanges: [RecordingTranscript.SpeechRange]
    }

    static func assignedTranscript(_ request: AssignmentRequest) -> RecordingTranscript {
        let assignedWords = request.words
        let stabilizedWords = request.hasSeparateTracks
            ? stabilizedPerTrack(assignedWords)
            : stabilizedSpeakerAssignments(.init(words: assignedWords, minimumWords: 100))
        let normalizedSpeakerIDs = normalizedSpeakerIDs(for: stabilizedWords)
        let normalizedWords = stabilizedWords.map { assignedWord in
            TranscriptSegmentBuilder.SpeakerWord(
                word: assignedWord.word,
                speakerID: normalizedSpeakerIDs[assignedWord.rawSpeakerID] ?? "Speaker 1"
            )
        }
        let segments = TranscriptSegmentBuilder.segments(from: normalizedWords)
        let microphoneSpeakerCount = normalizedSpeakerIDs.keys.filter(isMicrophoneSpeaker).count
        let speakers = normalizedSpeakerIDs
            .sorted { speakerNumber($0.value) < speakerNumber($1.value) }
            .map { rawID, displayID in
                RecordingTranscript.Speaker(
                    id: displayID,
                    name: microphoneSpeakerCount == 1 && isMicrophoneSpeaker(rawID) ? "You" : "",
                    context: ""
                )
            }

        return RecordingTranscript(
            version: 2,
            id: request.metadata.id,
            mediaPath: request.metadata.mediaPath,
            generatedAt: request.metadata.generatedAt,
            duration: request.metadata.duration,
            confidence: request.metadata.confidence,
            text: TranscriptSegmentBuilder.joinedText(normalizedWords.map(\.word.text)),
            suggestedTitle: request.metadata.suggestedTitle,
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
            speechRanges: request.speechRanges
        )
    }

    struct AssignedWord {
        let word: TranscriptWord
        let rawSpeakerID: String
    }

    static func speakerID(
        word: TranscriptWord,
        intervals: [DiarizedInterval]
    ) -> String {
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

    static func isMicrophoneSpeaker(_ speakerID: String) -> Bool {
        speakerID == microphoneSpeakerID || speakerID.hasPrefix(microphoneSpeakerPrefix)
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

    private static func stabilizedPerTrack(_ words: [AssignedWord]) -> [AssignedWord] {
        var result = words
        for isMicrophone in [true, false] {
            let indices = words.indices.filter { isMicrophoneSpeaker(words[$0].rawSpeakerID) == isMicrophone }
            let stabilized = stabilizedSpeakerAssignments(.init(words: indices.map { words[$0] }, minimumWords: 40))
            for (index, word) in zip(indices, stabilized) { result[index] = word }
        }
        return result
    }

    private struct StabilizationRequest {
        let words: [AssignedWord]
        let minimumWords: Int
    }

    private static func stabilizedSpeakerAssignments(
        _ request: StabilizationRequest
    ) -> [AssignedWord] {
        let words = request.words
        guard words.count >= request.minimumWords else { return words }
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

    private static func speakerNumber(_ speakerID: String) -> Int {
        Int(speakerID.split(separator: " ").last ?? "") ?? 0
    }
}
