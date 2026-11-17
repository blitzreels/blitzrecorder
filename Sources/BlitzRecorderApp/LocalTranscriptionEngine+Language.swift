import FluidAudio
import Foundation
import NaturalLanguage

/// Parakeet picks the language for each window on its own, and its language hint only filters the alphabet, so
/// French and English are never told apart by it. A short French reply ("Donc la deuxième chose") is too little
/// sound to decide on and often comes out as English words ("Don't live the deuxième chose"). The take's language
/// is decided from everything said, and every window that came out in another language is decoded again with the
/// same voice's speech in that language around it, which is enough for the model to stay in it.
enum TranscriptionLanguageRepair {
    static let primerSeconds = 6.0
    static let followerSeconds = 3.0
    static let gapSeconds = 0.5
    /// A decode that keeps fewer words than this share of the first one lost speech, so it is not used; one that
    /// is less sure of its words than the first decode is not used either.
    static let keptWordShare = 0.5
    /// Below this share the take is treated as mixed and no window is changed.
    static let dominantShare = 0.7
    /// A window counts as off-language when its language reads less likely than this.
    static let offLanguageShare = 0.5
    /// Speech that primes a decode must read clearly in the take's language.
    static let primerShare = 0.9
    static let primerWords = 6

    static let candidates: [NLLanguage] = Language.allCases.map { NLLanguage(rawValue: $0.rawValue) }

    struct LanguageQuery {
        let text: String
        let language: String
    }

    static func share(_ query: LanguageQuery) -> Double {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = candidates
        recognizer.processString(query.text)
        return recognizer.languageHypotheses(withMaximum: candidates.count)[NLLanguage(rawValue: query.language)] ?? 0
    }

    /// The language most of the take is in, or nil when no language clearly leads. Each window votes with its
    /// word count: the recognizer reads mostly the start of a long text, so one long text would follow whatever
    /// was said first.
    static func dominantLanguage(_ windowTexts: [String]) -> String? {
        var votes: [String: Int] = [:]
        for text in windowTexts {
            let words = text.split(separator: " ").count
            guard words >= 4 else { continue }
            let recognizer = NLLanguageRecognizer()
            recognizer.languageConstraints = candidates
            recognizer.processString(text)
            guard let language = recognizer.dominantLanguage else { continue }
            votes[language.rawValue, default: 0] += words
        }
        let total = votes.values.reduce(0, +)
        guard total > 0, let best = votes.max(by: { $0.value < $1.value }),
              Double(best.value) / Double(total) >= dominantShare else { return nil }
        return best.key
    }
}

extension LocalTranscriptionEngine {
    struct WindowRecognition {
        let trackIndex: Int
        let window: RecordingTranscript.SpeechRange
        var recognized: RecognizedWindow
    }

    struct LanguageRepairRequest {
        let recognitions: [WindowRecognition]
        let tracks: [CallAudioAnalysis.Track]
        let language: String
        let asr: AsrManager
    }

    struct LanguageRepair {
        let recognitions: [WindowRecognition]
        let repaired: Int
    }

    func repairingLanguage(_ request: LanguageRepairRequest) async throws -> LanguageRepair {
        var recognitions = request.recognitions
        let texts = recognitions.map { $0.recognized.words.map(\.text).joined(separator: " ") }
        let shares = texts.map { TranscriptionLanguageRepair.share(.init(text: $0, language: request.language)) }
        var repaired = 0
        for index in recognitions.indices where !texts[index].isEmpty
            && shares[index] < TranscriptionLanguageRepair.offLanguageShare {
            try Task.checkCancellation()
            let primers = recognitions.indices.filter {
                $0 != index && shares[$0] >= TranscriptionLanguageRepair.primerShare
                    && recognitions[$0].recognized.words.count >= TranscriptionLanguageRepair.primerWords
            }
            guard let words = try await primedWords(.init(
                target: recognitions[index], recognitions: recognitions, primers: primers,
                tracks: request.tracks, language: request.language, asr: request.asr
            )) else { continue }
            let text = words.map(\.text).joined(separator: " ")
            let original = recognitions[index].recognized.words
            guard !words.isEmpty,
                  Double(words.count) >= Double(original.count) * TranscriptionLanguageRepair.keptWordShare,
                  Self.average(words.map(\.confidence)) >= Self.average(original.map(\.confidence)),
                  TranscriptionLanguageRepair.share(.init(text: text, language: request.language)) > shares[index]
            else { continue }
            recognitions[index].recognized = RecognizedWindow(words: words, issues: recognitions[index].recognized.issues)
            repaired += 1
        }
        return LanguageRepair(recognitions: recognitions, repaired: repaired)
    }

    private struct PrimedRequest {
        let target: WindowRecognition
        let recognitions: [WindowRecognition]
        let primers: [Int]
        let tracks: [CallAudioAnalysis.Track]
        let language: String
        let asr: AsrManager
    }

    /// Decodes the window after the nearest clear speech before it, preferring the same voice, and keeps only the
    /// words that fall inside the window. Speech after the window is used only when nothing comes before it:
    /// context on both sides changes how the window's last words are cut.
    private func primedWords(_ request: PrimedRequest) async throws -> [TranscriptWord]? {
        let target = request.target
        let sameTrack = request.primers.filter { request.recognitions[$0].trackIndex == target.trackIndex }
        let pool = sameTrack.isEmpty ? request.primers : sameTrack
        let beforeIndex = pool.filter { request.recognitions[$0].window.endTime <= target.window.startTime }
            .max { request.recognitions[$0].window.endTime < request.recognitions[$1].window.endTime }
        let afterIndex = beforeIndex != nil ? nil : pool.filter { request.recognitions[$0].window.startTime >= target.window.endTime }
            .min { request.recognitions[$0].window.startTime < request.recognitions[$1].window.startTime }
        guard beforeIndex != nil || afterIndex != nil else { return nil }

        var before: [Float] = []
        if let index = beforeIndex {
            let primer = request.recognitions[index]
            let start = max(primer.window.startTime, primer.window.endTime - TranscriptionLanguageRepair.primerSeconds)
            before = request.tracks[primer.trackIndex].audio(.init(startTime: start, endTime: primer.window.endTime))
        }
        var after: [Float] = []
        if let index = afterIndex {
            let follower = request.recognitions[index]
            let end = min(follower.window.endTime, follower.window.startTime + TranscriptionLanguageRepair.followerSeconds)
            after = request.tracks[follower.trackIndex].audio(.init(startTime: follower.window.startTime, endTime: end))
        }
        let source = request.tracks[target.trackIndex].source
        return try await Self.decodeInContext(.init(
            target: request.tracks[target.trackIndex].audio(target.window), before: before, after: after,
            language: request.language, asr: request.asr
        )).map { word in
            TranscriptWord(text: word.text, startTime: target.window.startTime + word.startTime,
                           endTime: target.window.startTime + word.endTime, confidence: word.confidence, source: source)
        }
    }
}

extension LocalTranscriptionEngine {
    struct ContextDecode {
        let target: [Float]
        let before: [Float]
        let after: [Float]
        /// The language to keep, or nil while it is not known yet.
        let language: String?
        let asr: AsrManager
    }

    /// Decodes speech with other speech placed before and after it, separated by silence, and keeps only the
    /// words inside it. Times are relative to the start of the target.
    nonisolated static func decodeInContext(_ request: ContextDecode) async throws -> [TranscriptWord] {
        let rate = 16_000.0
        let gap = [Float](repeating: 0, count: Int(TranscriptionLanguageRepair.gapSeconds * rate))
        var samples: [Float] = []
        if !request.before.isEmpty { samples += request.before + gap }
        let offset = Double(samples.count) / rate
        samples += request.target
        let targetEnd = Double(samples.count) / rate
        if !request.after.isEmpty { samples += gap + request.after }
        let minimum = ASRConstants.minimumRequiredSamples(forSampleRate: 16_000)
        if samples.count < minimum { samples += [Float](repeating: 0, count: minimum - samples.count) }
        var state = TdtDecoderState.make(decoderLayers: await request.asr.decoderLayerCount)
        let result = try await request.asr.transcribe(samples, decoderState: &state,
                                                      language: request.language.flatMap(Language.init(rawValue:)))
        return words(result.tokenTimings ?? []).compactMap { word in
            guard word.startTime >= offset, word.startTime < targetEnd,
                  word.confidence.isFinite, word.confidence >= 0.2 else { return nil }
            let start = max(0, word.startTime - offset)
            let end = min(targetEnd - offset, max(start, word.endTime - offset))
            return TranscriptWord(text: word.text, startTime: start, endTime: end, confidence: word.confidence)
        }
    }
}
