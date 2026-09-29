import Foundation

extension RecordingTranscriptAssembler {
    struct DuplicateFilterRequest {
        let paired: [(TranscriptWord, WordSource)]
        let intervals: [DiarizedInterval]
        let trackIntervals: TrackIntervals
    }

    /// Speech heard on both tracks is kept once, on the track that carries that voice:
    /// your voice echoed into call audio keeps the microphone copy, and the call voice
    /// picked up by your microphone keeps the call-audio copy.
    static func withoutCrossTrackDuplicates(
        _ request: DuplicateFilterRequest
    ) -> [(TranscriptWord, WordSource)] {
        let voices = request.trackIntervals
        let rawIntervals = request.intervals
        let microphoneWords = request.paired.compactMap { word, source in
            source == .microphone ? word : nil
        }
        let echoingIndices = echoingSystemWords(.init(
            paired: request.paired,
            microphoneWords: microphoneWords,
            intervals: rawIntervals
        ))
        let keepsSystemWord = request.paired.enumerated().map { index, item in
            let (word, source) = item
            guard source == .systemAudio else { return true }
            let heardOnMicrophone = echoingIndices.contains(index)
                || isMicrophoneEcho(word: word, intervals: rawIntervals)
                || matchesWords(.init(word: word, candidates: microphoneWords))
            return !heardOnMicrophone || voices.isCallVoice(systemWord: word)
        }
        let keptSystemWords = zip(request.paired, keepsSystemWord).compactMap { item, kept in
            item.1 == .systemAudio && kept ? item.0 : nil
        }
        return zip(request.paired, keepsSystemWord).compactMap { item, kept in
            guard kept else { return nil }
            if item.1 == .microphone,
               voices.isCallVoiceHeardOnSystem(.init(word: item.0, systemWords: keptSystemWords)) {
                return nil
            }
            return item
        }
    }

    static func isMicrophoneEcho(
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

    private struct TimedToken {
        let text: String
        let center: TimeInterval
    }

    private struct IndexedSystemWord {
        let index: Int
        let word: TranscriptWord
        let speakerID: String
    }

    struct EchoDetectionRequest {
        let paired: [(TranscriptWord, WordSource)]
        let microphoneWords: [TranscriptWord]
        let intervals: [DiarizedInterval]
    }

    struct WordMatchRequest {
        let word: TranscriptWord
        let candidates: [TranscriptWord]
    }

    private struct NearbyWordRequest {
        let word: TranscriptWord
        let microphoneWords: [TranscriptWord]
        let tolerance: TimeInterval
    }

    static func echoingSystemWords(
        _ request: EchoDetectionRequest
    ) -> Set<Int> {
        let systemIntervals = request.intervals.filter { $0.speakerID.hasPrefix(systemSpeakerPrefix) }
        let systemWords = request.paired.enumerated().compactMap { index, item -> IndexedSystemWord? in
            let (word, source) = item
            guard source == .systemAudio else { return nil }
            return IndexedSystemWord(
                index: index,
                word: word,
                speakerID: speakerID(word: word, intervals: systemIntervals)
            )
        }
        let grouped = Dictionary(grouping: systemWords, by: \.speakerID)
        var echoIndices: Set<Int> = []

        for (speakerID, words) in grouped where speakerID != "undiarized" {
            let matches = words.filter { matchesWords(
                .init(word: $0.word, candidates: request.microphoneWords)
            ) }.count
            let nearMicrophone = words.filter { hasNearbyMicrophoneWord(
                .init(word: $0.word, microphoneWords: request.microphoneWords, tolerance: 0.5)
            ) }.count
            let isEchoSpeaker = words.count >= 20
                && Double(matches) / Double(words.count) >= 0.4
                && Double(nearMicrophone) / Double(words.count) >= 0.75

            var turn: [IndexedSystemWord] = []
            func finishTurn() {
                guard turn.count >= 4 else { turn = []; return }
                let matching = turn.filter { matchesWords(
                    .init(word: $0.word, candidates: request.microphoneWords)
                ) }.count
                if Double(matching) / Double(turn.count) >= 0.5 {
                    echoIndices.formUnion(turn.map(\.index))
                }
                turn = []
            }
            for item in words {
                if let previous = turn.last,
                   item.word.startTime - previous.word.endTime > 2.5 {
                    finishTurn()
                }
                turn.append(item)
                if isEchoSpeaker,
                   hasNearbyMicrophoneWord(
                    .init(word: item.word, microphoneWords: request.microphoneWords, tolerance: 2.5)
                   ) {
                    echoIndices.insert(item.index)
                }
            }
            finishTurn()
        }
        return echoIndices
    }

    private static func hasNearbyMicrophoneWord(
        _ request: NearbyWordRequest
    ) -> Bool {
        request.microphoneWords.contains {
            $0.startTime <= request.word.endTime + request.tolerance
                && $0.endTime >= request.word.startTime - request.tolerance
        }
    }

    static func matchesWords(
        _ request: WordMatchRequest
    ) -> Bool {
        let tokens = timedTokens(from: [request.word])
        guard !tokens.isEmpty else { return false }
        let nearbyWords = request.candidates.filter {
            $0.startTime <= request.word.endTime + 0.5
                && $0.endTime >= request.word.startTime - 0.5
        }
        let candidateTokens = timedTokens(from: nearbyWords)
        var nextIndex = candidateTokens.startIndex
        for token in tokens {
            guard let match = candidateTokens.indices.dropFirst(nextIndex).first(where: { index in
                let candidate = candidateTokens[index]
                return candidate.text == token.text
                    && abs(candidate.center - token.center) <= 0.5
            }) else {
                return false
            }
            nextIndex = match + 1
        }
        return true
    }

    private static func timedTokens(from words: [TranscriptWord]) -> [TimedToken] {
        words.flatMap { word in
            let tokens = word.text.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "fr")
            ).split { !$0.isLetter && !$0.isNumber }
            return tokens.enumerated().map { index, token in
                TimedToken(
                    text: String(token),
                    center: word.startTime + (word.endTime - word.startTime)
                        * (Double(index) + 0.5) / Double(tokens.count)
                )
            }
        }
    }
}

extension RecordingTranscriptAssembler.TrackIntervals {
    struct HeardOnSystemRequest {
        let word: TranscriptWord
        let systemWords: [TranscriptWord]
    }

    /// The microphone track decides whose voice it is: it hears you clearly, while call
    /// audio can carry your echo under the remote speaker's label.
    func isCallVoice(systemWord word: TranscriptWord) -> Bool {
        let voice = voice(of: word, in: microphone) ?? voice(of: word, in: system)
        return voice?.hasPrefix(RecordingTranscriptAssembler.systemSpeakerPrefix) ?? false
    }

    func isCallVoiceHeardOnSystem(_ request: HeardOnSystemRequest) -> Bool {
        guard let voice = voice(of: request.word, in: microphone),
              voice.hasPrefix(RecordingTranscriptAssembler.systemSpeakerPrefix) else { return false }
        let overlapsSameVoice = system.contains { interval in
            interval.speakerID == voice
                && interval.startTime < request.word.endTime
                && interval.endTime > request.word.startTime
        }
        return overlapsSameVoice || RecordingTranscriptAssembler.matchesWords(
            .init(word: request.word, candidates: request.systemWords)
        )
    }

    private func voice(of word: TranscriptWord, in intervals: [DiarizedInterval]) -> String? {
        let voice = RecordingTranscriptAssembler.speakerID(word: word, intervals: intervals)
        return voice == "undiarized" ? nil : voice
    }
}
