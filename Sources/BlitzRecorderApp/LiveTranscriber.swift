import AVFoundation
import FluidAudio
import Foundation

/// Transcribes a take while it records, from the backup audio its recorders already write every few seconds.
/// Audio arrives in pieces; speech that may still be going on at the end of what arrived waits for the next pass,
/// so a sentence is never cut in two.
actor LiveTranscriber {
    static let sampleRate = 16_000.0
    /// Speech must have ended this long before the end of the audio received to be decoded now.
    static let settleSeconds = 0.6

    private struct Pass: Sendable {
        let source: TranscriptWord.Source
        let samples: [Float]
        let timelineStart: Double
        /// Decode everything, as when the take stops or recording paused.
        let isFinal: Bool
        let language: String?
        /// A few seconds of this voice clearly speaking the take's language, or empty.
        let primer: [Float]
    }

    private struct Speech: Sendable {
        let words: [TranscriptWord]
        let samples: [Float]
        /// Take time where `samples` begin.
        let start: Double
    }

    private struct PassResult: Sendable {
        let speech: [Speech]
        /// Seconds from the start of the pass's audio that are done; the rest is decoded with the next audio.
        let consumedSeconds: Double
    }

    private let store = LocalTranscriptionModelStore()
    private var asr: AsrManager?
    private var detector: VadManager?
    private var feeds: [LiveAudioFeed] = []
    private var pending: [TranscriptWord.Source: LiveAudioFeed.Piece] = [:]
    private var primers: [TranscriptWord.Source: [Float]] = [:]
    private var received: [TranscriptWord.Source: Double] = [:]
    private var language: String?
    private var languageSettled = false
    /// Speech decoded before the take's language was known. It is shown once the language is decided, after the
    /// parts that came out in another language are decoded again in it.
    private var undecided: [(source: TranscriptWord.Source, speech: Speech)] = []
    /// Audio is decoded once this much is waiting; speech still going on at its end waits for more.
    static let passSeconds = 1.0
    /// A jump in the backup timeline larger than this is a pause or a stall: the audio before it is decoded alone.
    static let gapSeconds = 0.3
    /// Words needed to decide the take's language; lines are shown from then on.
    static let languageDecisionWords = 12
    /// Without a clear language after this many words the take is mixed, and is shown as heard.
    static let languageGiveUpWords = 250

    nonisolated func isAvailable() -> Bool {
        LocalTranscriptionModelStore().isInstalled(.parakeet)
    }

    /// Starts a new take; `language` is the one chosen in Settings, or nil to find it from the speech.
    func begin(_ begin: Begin) {
        feeds.forEach { $0.close() }
        feeds = begin.tracks.map(LiveAudioFeed.init)
        pending = [:]
        primers = [:]
        received = [:]
        undecided = []
        language = begin.language
        languageSettled = begin.language != nil
    }

    /// Stops listening to the tracks of the take that ended.
    func end() {
        feeds.forEach { $0.close() }
        feeds = []
    }

    struct Begin: Sendable {
        let tracks: [LiveAudioFeed.Track]
        let language: String?
    }

    struct Advance: Sendable {
        let isFinal: Bool
    }

    struct Heard: Sendable {
        let source: TranscriptWord.Source
        let words: [TranscriptWord]
    }

    struct Progress: Sendable {
        let heard: [Heard]
        /// Take time up to which each track's speech is shown; later speech is still being decoded.
        let decodedThrough: [TranscriptWord.Source: Double]
        let language: String?
    }

    /// Reads the audio written since the last call and decodes the speech that is complete.
    func advance(_ advance: Advance) async throws -> Progress {
        for index in feeds.indices {
            let source = feeds[index].source
            for piece in feeds[index].newPieces() {
                if let current = pending[source],
                   piece.timelineStart - current.end > Self.gapSeconds || current.end - piece.timelineStart > Self.gapSeconds {
                    try await decode(.init(source: source, isFinal: true))
                }
                received[source] = piece.end
                if let current = pending[source], abs(piece.timelineStart - current.end) <= Self.gapSeconds {
                    pending[source] = .init(samples: current.samples + piece.samples, timelineStart: current.timelineStart)
                } else {
                    pending[source] = piece
                }
            }
            if let current = pending[source], advance.isFinal || current.duration >= Self.passSeconds {
                try await decode(.init(source: source, isFinal: advance.isFinal))
            }
        }
        try await settleLanguageIfNeeded(force: advance.isFinal)
        let heard = languageSettled ? undecided.map { Heard(source: $0.source, words: $0.speech.words) } : []
        if languageSettled { undecided = [] }
        var decodedThrough: [TranscriptWord.Source: Double] = [:]
        for feed in feeds {
            decodedThrough[feed.source] = languageSettled
                ? pending[feed.source]?.timelineStart ?? received[feed.source] ?? 0 : 0
        }
        return Progress(heard: heard, decodedThrough: decodedThrough, language: language)
    }

    private struct Decode {
        let source: TranscriptWord.Source
        let isFinal: Bool
    }

    private func decode(_ request: Decode) async throws {
        guard let current = pending[request.source] else { return }
        let result = try await transcribe(.init(
            source: request.source, samples: current.samples, timelineStart: current.timelineStart,
            isFinal: request.isFinal, language: language, primer: primers[request.source] ?? []
        ))
        let consumed = min(current.samples.count, Int(result.consumedSeconds * Self.sampleRate))
        pending[request.source] = consumed >= current.samples.count ? nil : .init(
            samples: Array(current.samples[consumed...]),
            timelineStart: current.timelineStart + Double(consumed) / Self.sampleRate
        )
        for speech in result.speech {
            undecided.append((request.source, speech))
            notePrimer(.init(source: request.source, speech: speech))
        }
    }

    private struct PrimerCandidate {
        let source: TranscriptWord.Source
        let speech: Speech
    }

    private func notePrimer(_ candidate: PrimerCandidate) {
        guard let language, candidate.speech.words.count >= TranscriptionLanguageRepair.primerWords,
              TranscriptionLanguageRepair.share(.init(text: candidate.speech.words.map(\.text).joined(separator: " "),
                                                      language: language)) >= TranscriptionLanguageRepair.primerShare
        else { return }
        primers[candidate.source] = Array(candidate.speech.samples.suffix(
            Int(TranscriptionLanguageRepair.primerSeconds * Self.sampleRate)))
    }

    /// Decides the take's language from what was heard so far, then decodes again, in it, the speech that came
    /// out in another language before it was known.
    private func settleLanguageIfNeeded(force: Bool) async throws {
        guard !languageSettled else { return }
        let texts = undecided.map { $0.speech.words.map(\.text).joined(separator: " ") }
        let words = texts.reduce(0) { $0 + $1.split(separator: " ").count }
        guard force || words >= Self.languageDecisionWords else { return }
        language = TranscriptionLanguageRepair.dominantLanguage(texts)
        guard let language, let asr else {
            if force || words >= Self.languageGiveUpWords { languageSettled = true }
            return
        }
        CaptureLog.note("Live transcript: the call is in \(language)")
        for item in undecided { notePrimer(.init(source: item.source, speech: item.speech)) }
        for index in undecided.indices {
            let item = undecided[index]
            let primer = primers[item.source] ?? primers.values.first ?? []
            guard !primer.isEmpty else { continue }
            let repaired = try await recognized(.init(
                audio: item.speech.samples,
                pass: .init(source: item.source, samples: [], timelineStart: 0, isFinal: true,
                            language: language, primer: primer),
                asr: asr
            ))
            guard !repaired.isEmpty, repaired.map(\.text) != item.speech.words.map(\.text) else { continue }
            let start = item.speech.start
            undecided[index].speech = Speech(
                words: repaired.map {
                    TranscriptWord(text: $0.text, startTime: start + $0.startTime, endTime: start + $0.endTime,
                                   confidence: $0.confidence, source: item.source)
                },
                samples: item.speech.samples,
                start: start
            )
        }
        languageSettled = true
    }

    private func transcribe(_ pass: Pass) async throws -> PassResult {
        let duration = Double(pass.samples.count) / Self.sampleRate
        guard duration > 0 else { return PassResult(speech: [], consumedSeconds: 0) }
        let (asr, detector) = try await loaded()
        let segments = try await detector.segmentSpeech(pass.samples, config: .init(
            minSpeechDuration: 0.2, minSilenceDuration: 0.4, maxSpeechDuration: 9, speechPadding: 0.1
        ))
        let track = CallAudioAnalysis.Track(
            source: pass.source, samples: pass.samples,
            windows: segments.map { .init(startTime: $0.startTime, endTime: $0.endTime) }
        )
        let settled = pass.isFinal ? duration : duration - Self.settleSeconds
        var consumed = max(0, settled)
        var speech: [Speech] = []
        for window in track.decodingWindows(.live) {
            guard window.endTime <= settled else {
                consumed = min(consumed, window.startTime)
                break
            }
            try Task.checkCancellation()
            let audio = track.audio(window)
            let words = try await recognized(.init(audio: audio, pass: pass, asr: asr))
            guard !words.isEmpty else { continue }
            speech.append(Speech(
                words: words.map {
                    TranscriptWord(text: $0.text, startTime: pass.timelineStart + window.startTime + $0.startTime,
                                   endTime: pass.timelineStart + window.startTime + $0.endTime,
                                   confidence: $0.confidence, source: pass.source)
                },
                samples: audio,
                start: pass.timelineStart + window.startTime
            ))
        }
        return PassResult(speech: speech, consumedSeconds: consumed)
    }

    private struct Recognition {
        let audio: [Float]
        let pass: Pass
        let asr: AsrManager
    }

    /// Decodes on its own first; speech that comes out in another language than the take's is decoded again
    /// after the primer, and that version is kept when it reads more like the take and lost nothing.
    private func recognized(_ recognition: Recognition) async throws -> [TranscriptWord] {
        let pass = recognition.pass
        let plain = try await LocalTranscriptionEngine.decodeInContext(.init(
            target: recognition.audio, before: [], after: [], language: pass.language, asr: recognition.asr
        ))
        guard let language = pass.language, !pass.primer.isEmpty, !plain.isEmpty else { return plain }
        let text = plain.map(\.text).joined(separator: " ")
        let share = TranscriptionLanguageRepair.share(.init(text: text, language: language))
        guard share < TranscriptionLanguageRepair.offLanguageShare else { return plain }
        let primed = try await LocalTranscriptionEngine.decodeInContext(.init(
            target: recognition.audio, before: pass.primer, after: [], language: language, asr: recognition.asr
        ))
        let primedText = primed.map(\.text).joined(separator: " ")
        guard !primed.isEmpty,
              Double(primed.count) >= Double(plain.count) * TranscriptionLanguageRepair.keptWordShare,
              LocalTranscriptionEngine.average(primed.map(\.confidence))
                >= LocalTranscriptionEngine.average(plain.map(\.confidence)),
              TranscriptionLanguageRepair.share(.init(text: primedText, language: language)) > share
        else { return plain }
        return primed
    }

    private func loaded() async throws -> (AsrManager, VadManager) {
        if asr == nil { asr = try await LocalTranscriptionEngine.loadRecognizer(store) }
        if detector == nil { detector = try LocalTranscriptionEngine.loadSpeechDetector(store) }
        guard let asr, let detector else { throw LocalTranscriptionError.modelNotInstalled }
        return (asr, detector)
    }
}

/// Reads the backup audio of one track as it is written, as 16 kHz mono with its place on the take timeline.
/// One track's audio as it is recorded, as 16 kHz mono with its place on the take timeline. Chunks come from
/// `LiveAudioTap` as the backup writer receives them; a resampler kept across reads joins them without seams.
final class LiveAudioFeed {
    struct Piece: Sendable {
        let samples: [Float]
        let timelineStart: Double
        var duration: Double { Double(samples.count) / LiveTranscriber.sampleRate }
        var end: Double { timelineStart + duration }
    }

    struct Track: Sendable {
        let source: TranscriptWord.Source
        let audioURL: URL
    }

    /// A chunk starting further than this from where the last one ended starts a new piece: a pause or a stall.
    static let continuitySeconds = 0.3

    let source: TranscriptWord.Source
    let directory: URL
    private let output = AVAudioFormat(standardFormatWithSampleRate: LiveTranscriber.sampleRate, channels: 1)!
    private var converter: AVAudioConverter?
    private var expectedNext: Double?

    init(_ track: Track) {
        source = track.source
        directory = TakeRecoveryFiles.audioSegments(audioURL: track.audioURL)
        LiveAudioTap.shared.subscribe(directory)
    }

    func close() {
        LiveAudioTap.shared.unsubscribe(directory)
    }

    /// Audio received since the last call, in order, split where it does not follow on.
    func newPieces() -> [Piece] {
        var pieces: [Piece] = []
        var run: [LiveAudioTap.Chunk] = []
        func flush() {
            guard let first = run.first, let samples = converted(run), !samples.isEmpty else { return }
            pieces.append(Piece(samples: samples, timelineStart: first.seconds))
        }
        for chunk in LiveAudioTap.shared.drain(directory) {
            if let expectedNext, abs(chunk.seconds - expectedNext) > Self.continuitySeconds {
                flush()
                run = []
                converter = nil
            }
            if let current = converter, current.inputFormat != chunk.buffer.format {
                flush()
                run = []
                converter = nil
            }
            run.append(chunk)
            expectedNext = chunk.seconds + chunk.duration
        }
        flush()
        return pieces
    }

    private func converted(_ chunks: [LiveAudioTap.Chunk]) -> [Float]? {
        guard let format = chunks.first?.buffer.format else { return nil }
        if converter == nil {
            converter = AVAudioConverter(from: format, to: output)
            converter?.downmix = true
        }
        guard let converter else { return nil }
        let frames = chunks.reduce(0.0) { $0 + Double($1.buffer.frameLength) }
        let capacity = AVAudioFrameCount(frames * output.sampleRate / format.sampleRate) + 4_096
        guard let buffer = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return nil }
        var index = 0
        var error: NSError?
        let status = converter.convert(to: buffer, error: &error) { _, inputStatus in
            guard index < chunks.count else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            defer { index += 1 }
            inputStatus.pointee = .haveData
            return chunks[index].buffer
        }
        guard status != .error, let channel = buffer.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }
}
