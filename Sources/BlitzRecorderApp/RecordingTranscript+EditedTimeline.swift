import Foundation

extension RecordingTranscript {
    func mappedToEditedTimeline(_ timeMap: TimelineTimeMap) -> RecordingTranscript {
        guard timeMap.hasCuts else { return self }

        let mappedWords = (words ?? []).compactMap { word -> TranscriptSegmentBuilder.SpeakerWord? in
            let midpoint = (word.startTime + word.endTime) / 2
            guard !timeMap.isRemoved(takeTime: midpoint) else { return nil }
            let start = timeMap.outputSeconds(forTakeSeconds: word.startTime)
            let end = timeMap.outputSeconds(forTakeSeconds: word.endTime)
            guard end > start else { return nil }
            let speakerID = word.speakerID ?? speakerID(atTakeTime: midpoint)
            return TranscriptSegmentBuilder.SpeakerWord(
                word: TranscriptWord(
                    text: word.text,
                    startTime: start,
                    endTime: end,
                    confidence: word.confidence,
                    speakerID: speakerID
                ),
                speakerID: speakerID
            )
        }

        let mappedSegments: [Segment]
        if mappedWords.isEmpty {
            mappedSegments = TranscriptSegmentBuilder.coalesced(segments.flatMap { segment in
                Self.keptPieces(of: segment, timeMap: timeMap)
            })
        } else {
            mappedSegments = TranscriptSegmentBuilder.coalesced(TranscriptSegmentBuilder.segments(from: mappedWords))
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
        let ranges = keptOutputRanges(start: segment.startTime, end: segment.endTime, timeMap: timeMap)
        guard let range = ranges.max(by: { ($0.end - $0.start) < ($1.end - $1.start) }) else {
            return []
        }
        return [Segment(
            id: segment.id,
            speakerID: segment.speakerID,
            startTime: range.start,
            endTime: range.end,
            text: segment.text,
            confidence: segment.confidence
        )]
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
}
