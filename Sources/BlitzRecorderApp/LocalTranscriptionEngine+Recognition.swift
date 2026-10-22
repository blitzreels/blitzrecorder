import FluidAudio
import Foundation
import NaturalLanguage
import WhisperKit

extension LocalTranscriptionEngine {
    struct WhisperDecodingRequest {
        let language: TranscriptionLanguage
        let promptTokens: [Int]?
    }

    nonisolated static func whisperDecodingOptions(_ request: WhisperDecodingRequest) -> DecodingOptions {
        DecodingOptions(
            task: .transcribe,
            language: request.language.whisperCode,
            temperatureFallbackCount: 0,
            detectLanguage: request.language == .automatic,
            skipSpecialTokens: true,
            wordTimestamps: true,
            promptTokens: request.promptTokens,
            suppressBlank: true,
            chunkingStrategy: .vad
        )
    }

    struct LanguageRequest {
        let tracks: [CallAudioAnalysis.Track]
        let requested: TranscriptionLanguage
        let whisper: WhisperKit?
    }

    func recognitionLanguages(_ request: LanguageRequest) async throws -> [Int: String] {
        if let code = request.requested.whisperCode {
            return Dictionary(uniqueKeysWithValues: request.tracks.enumerated().map { ($0.offset, code) })
        }
        guard let whisper = request.whisper else { return [:] }
        var evidence: [(index: Int, code: String, score: Float)] = []
        for (index, track) in request.tracks.enumerated() where !track.windows.isEmpty {
            try Task.checkCancellation()
            let detected = try await whisper.detectLangauge(audioArray: track.languageSample)
            evidence.append((index, detected.language, detected.langProbs[detected.language] ?? -.infinity))
        }
        guard let best = evidence.max(by: { $0.score < $1.score }) else { return [:] }
        return Dictionary(uniqueKeysWithValues: evidence.map {
            ($0.index, $0.score < -1 ? best.code : $0.code)
        })
    }

    struct RecognitionWindowRequest {
        enum Attempt { case initial, recovery }
        let track: CallAudioAnalysis.Track
        let window: RecordingTranscript.SpeechRange
        let model: TranscriptionSpeechModel
        let language: String?
        let promptTokens: [Int]?
        let asr: AsrManager?
        let whisper: WhisperKit?
        let attempt: Attempt
        let allowsContextExpansion: Bool
    }

    struct RecognizedWindow {
        let words: [TranscriptWord]
        let issues: [TranscriptionQuality.Issue]
    }

    func recognizeWindow(_ request: RecognitionWindowRequest) async throws -> RecognizedWindow {
        let samples = request.track.audio(request.window)
        let duration = Double(samples.count) / 16_000
        let raw: [TranscriptWord]
        if request.model == .parakeet {
            guard let asr = request.asr else { throw LocalTranscriptionError.modelNotInstalled }
            var state = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
            let result = try await asr.transcribe(samples, decoderState: &state,
                                                 language: request.language.flatMap(Language.init(rawValue:)))
            raw = Self.words(result.tokenTimings ?? [])
        } else {
            guard let whisper = request.whisper else { throw LocalTranscriptionError.modelNotInstalled }
            let results = try await whisper.transcribe(audioArray: samples, decodeOptions: DecodingOptions(
                task: .transcribe, language: request.language,
                temperatureFallbackCount: request.attempt == .initial ? 0 : 2,
                detectLanguage: request.language == nil, skipSpecialTokens: true, wordTimestamps: true,
                windowClipTime: 0, promptTokens: request.promptTokens, suppressBlank: true, concurrentWorkerCount: 1
            ))
            raw = results.flatMap(\.allWords).map {
                .init(text: $0.word.trimmingCharacters(in: .whitespacesAndNewlines),
                      startTime: Double($0.start), endTime: Double($0.end), confidence: $0.probability)
            }
        }
        var words: [TranscriptWord] = []
        for word in raw {
            guard !word.text.isEmpty, !Self.isNonSpeechPlaceholder(word.text),
                  word.startTime.isFinite, word.endTime.isFinite, word.startTime >= 0,
                  word.endTime >= word.startTime, word.startTime < duration,
                  word.confidence.isFinite, word.confidence >= 0.2 else { continue }
            words.append(.init(text: word.text,
                               startTime: request.window.startTime + word.startTime,
                               endTime: request.window.startTime + min(duration, word.endTime),
                               confidence: word.confidence, source: request.track.source))
        }
        var issues: [TranscriptionQuality.Issue] = []
        if words.isEmpty && duration >= 1 {
            issues.append(.init(kind: .missingSpeech, startTime: request.window.startTime, endTime: request.window.endTime))
        }
        let rejected = raw.count - words.count
        if !words.isEmpty && (rejected >= 2 && rejected * 4 >= raw.count
                             || Self.average(words.map(\.confidence)) < 0.4) {
            issues.append(.init(kind: .unsupportedSpeech, startTime: request.window.startTime, endTime: request.window.endTime))
        }
        if let expected = request.language, words.count >= 8 {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(words.map(\.text).joined(separator: " "))
            if let actual = recognizer.dominantLanguage?.rawValue, actual != expected {
                issues.append(.init(kind: .languageMismatch, startTime: request.window.startTime,
                                    endTime: request.window.endTime))
            }
        }
        if request.attempt == .initial, !issues.isEmpty {
            let trackDuration = Double(request.track.samples.count) / 16_000
            let padding = request.allowsContextExpansion ? 1.0 : 0
            let window = RecordingTranscript.SpeechRange(startTime: max(0, request.window.startTime - padding),
                                                         endTime: min(trackDuration, request.window.endTime + padding))
            let recovery = try await recognizeWindow(.init(
                track: request.track, window: window, model: request.model, language: request.language,
                promptTokens: nil, asr: request.asr, whisper: request.whisper, attempt: .recovery,
                allowsContextExpansion: request.allowsContextExpansion
            ))
            if recovery.issues.count < issues.count || words.isEmpty && !recovery.words.isEmpty { return recovery }
        }
        return RecognizedWindow(words: words, issues: issues)
    }

    static func words(_ timings: [TokenTiming]) -> [TranscriptWord] {
        guard !timings.isEmpty else { return [] }

        var result: [TranscriptWord] = []
        var currentText = ""
        var currentStartTime: TimeInterval?
        var currentEnd: TimeInterval = 0
        var confidences: [Float] = []

        for timing in timings {
            let startsWord = timing.token.first?.isWhitespace == true
            if startsWord, !currentText.isEmpty, let segmentStartTime = currentStartTime {
                result.append(TranscriptWord(
                    text: currentText,
                    startTime: segmentStartTime,
                    endTime: currentEnd,
                    confidence: average(confidences)
                ))
                currentText = ""
                confidences = []
                currentStartTime = nil
            }

            if currentStartTime == nil {
                currentStartTime = timing.startTime
            }
            currentText += timing.token.trimmingCharacters(in: .whitespacesAndNewlines)
            currentEnd = timing.endTime
            confidences.append(timing.confidence)
        }

        if !currentText.isEmpty, let segmentStartTime = currentStartTime {
            result.append(TranscriptWord(
                text: currentText,
                startTime: segmentStartTime,
                endTime: currentEnd,
                confidence: average(confidences)
            ))
        }
        return result
    }

    static func average(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        return values.reduce(Float.zero, +) / Float(values.count)
    }

    private static func isNonSpeechPlaceholder(_ text: String) -> Bool {
        let normalized = text.lowercased().trimmingCharacters(in: .punctuationCharacters)
        return ["silence", "music", "noise", "applause", "inaudible"].contains(normalized)
            && (text.first == "[" || text.first == "(")
    }
}
