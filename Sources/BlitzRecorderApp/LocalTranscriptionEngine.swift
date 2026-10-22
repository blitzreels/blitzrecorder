import FluidAudio
import CoreML
import Foundation
import WhisperKit

actor LocalTranscriptionEngine: LocalTranscriptionEngineServing {
    struct DownloadRequest: Sendable {
        let model: TranscriptionSpeechModel
        let onUpdate: @Sendable (TranscriptionModelDownloadUpdate) -> Void
    }

    struct TranscribeRequest: Sendable {
        let source: TranscriptionMediaSource
        let model: TranscriptionSpeechModel
        let language: TranscriptionLanguage
        let speakerCount: TranscriptionSpeakerCount
        let onUpdate: @Sendable (TranscriptionEngineUpdate) -> Void
    }

    struct SpeakerFixRequest: Sendable {
        let source: TranscriptionMediaSource
        let speakerCount: TranscriptionSpeakerCount
        let onUpdate: @Sendable (TranscriptionEngineUpdate) -> Void
    }

    private struct DiarizationRequest {
        let tracks: [PreparedTranscriptionTrack]
        let microphone: OfflineDiarizerManager
        let system: OfflineDiarizerManager
        let count: TranscriptionSpeakerCount
        let speech: [CallAudioAnalysis.Track]
        let onUpdate: @Sendable (TranscriptionEngineUpdate) -> Void
    }

    private struct ManagerRequest {
        let model: TranscriptionSpeechModel
        let speakerCount: TranscriptionSpeakerCount
    }

    private struct WhisperLoadRequest {
        let model: TranscriptionSpeechModel
        let folder: URL
    }

    private var asrManager: AsrManager?
    private var whisperManager: WhisperKit?
    private var loadedWhisperModel: TranscriptionSpeechModel?
    private var microphoneDiarizers: [TranscriptionSpeakerCount: OfflineDiarizerManager] = [:]
    private var systemDiarizer: OfflineDiarizerManager?
    private var speechDetector: VadManager?
    private var constrainedDiarizers: [Int: OfflineDiarizerManager] = [:]
    private let workGate = TranscriptionWorkGate()
    private let modelStore = LocalTranscriptionModelStore()
    private let audioPreparer = TranscriptionAudioPreparer()
    private let artifactStore = TranscriptArtifactStore()

    func downloadModels(_ request: DownloadRequest) async throws {
        try await workGate.acquire()
        defer { Task { await workGate.release() } }
        try Task.checkCancellation()
        try modelStore.createRootDirectory()
        var downloadedWhisper: URL?
        switch request.model {
        case .parakeet:
            try await ModelHub.download(
                .parakeetV3,
                to: modelStore.rootDirectory,
                variant: ParakeetEncoderPrecision.int8.rawValue,
                progressHandler: { progress in
                    request.onUpdate(TranscriptionModelDownloadUpdate(
                        fractionCompleted: progress.fractionCompleted * 0.65,
                        phase: Self.phaseLabel(progress.phase)
                    ))
                }
            )
            try await loadParakeet()
        case .whisperMedium, .whisperLargeTurbo, .whisperLarge:
            guard let variant = request.model.whisperVariant else { throw LocalTranscriptionError.modelNotInstalled }
            let base = modelStore.whisperDownloadBase(request.model)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            let folder = try await WhisperKit.download(
                variant: variant,
                downloadBase: base,
                progressCallback: { progress in
                    request.onUpdate(TranscriptionModelDownloadUpdate(
                        fractionCompleted: progress.fractionCompleted * 0.65,
                        phase: "Downloading \(request.model.title)"
                    ))
                }
            )
            request.onUpdate(.init(fractionCompleted: 0.65, phase: "Preparing \(request.model.title)"))
            try await loadWhisper(.init(model: request.model, folder: folder))
            downloadedWhisper = folder
        }

        let diarizerModels = try await OfflineDiarizerModels.load(
            from: modelStore.diarizationDirectory,
            progressHandler: { progress in
                request.onUpdate(TranscriptionModelDownloadUpdate(
                    fractionCompleted: 0.65 + progress.fractionCompleted * 0.35,
                    phase: Self.phaseLabel(progress.phase)
                ))
            }
        )
        for count in [TranscriptionSpeakerCount.automatic, .two] {
            let microphoneDiarizer = OfflineDiarizerManager(config: Self.microphoneDiarizerConfiguration(count))
            microphoneDiarizer.initialize(models: diarizerModels)
            microphoneDiarizers[count] = microphoneDiarizer
        }
        let systemDiarizer = OfflineDiarizerManager(config: Self.systemDiarizerConfiguration)
        systemDiarizer.initialize(models: diarizerModels)
        self.systemDiarizer = systemDiarizer

        try await ModelHub.download(.vad, to: modelStore.speechDetectionDirectory)
        try modelStore.validateSpeechDetector()
        speechDetector = try makeSpeechDetector()
        if request.model == .parakeet {
            try modelStore.markInstalled()
        } else if let downloadedWhisper {
            try modelStore.markWhisperInstalled(request.model, at: downloadedWhisper)
        }
        request.onUpdate(TranscriptionModelDownloadUpdate(
            fractionCompleted: 1,
            phase: "Ready"
        ))
    }

    func transcribe(_ request: TranscribeRequest) async throws -> RecordingTranscript {
        try await workGate.acquire()
        defer { Task { await workGate.release() } }
        try Task.checkCancellation()
        request.onUpdate(TranscriptionEngineUpdate(stage: .preparingAudio))
        let prepared = try await audioPreparer.prepare(request.source)
        defer { for track in prepared.tracks { try? FileManager.default.removeItem(at: track.audioURL) } }
        request.onUpdate(TranscriptionEngineUpdate(stage: .loadingModels))
        let managers = try await loadedManagers(.init(model: request.model, speakerCount: request.speakerCount))
        let speech = try await CallAudioAnalysis.analyze(.init(
            tracks: prepared.tracks, intervals: [], detector: loadedSpeechDetector()
        ))
        let intervals = try await diarizedIntervals(.init(
            tracks: prepared.tracks, microphone: managers.microphone, system: managers.system,
            count: request.speakerCount, speech: speech, onUpdate: request.onUpdate
        ))
        let tracks = CallAudioAnalysis.removingLeakage(.init(tracks: speech, intervals: intervals))
        let languageCodes = try await recognitionLanguages(.init(
            tracks: tracks, requested: request.language, whisper: managers.whisper
        ))
        let profiles = (try? await SpeakerVoiceStore.shared.profiles()) ?? []
        let vocabulary = TranscriptionVocabulary.prompt(profiles.map(\.name))
        let promptTokens = vocabulary.isEmpty ? nil : managers.whisper?.tokenizer.map {
            Array($0.encode(text: vocabulary).suffix(160))
        }
        var words: [TranscriptWord] = []
        var issues: [TranscriptionQuality.Issue] = []
        for (index, track) in tracks.enumerated() {
            let decoding = CallAudioAnalysis.DecodingRequest(track: track, intervals: intervals)
            let voices = Set(CallAudioAnalysis.nativeIntervals(decoding).map(\.speakerID)).count
            for window in CallAudioAnalysis.decodingWindows(decoding) {
                try Task.checkCancellation()
                request.onUpdate(.init(stage: .transcribing))
                let recognized = try await recognizeWindow(.init(
                    track: track, window: window, model: request.model, language: languageCodes[index],
                    promptTokens: promptTokens, asr: managers.asr, whisper: managers.whisper,
                    attempt: .initial, allowsContextExpansion: voices <= 1
                ))
                words.append(contentsOf: recognized.words)
                issues.append(contentsOf: recognized.issues)
            }
        }
        words.sort { $0.startTime < $1.startTime }
        let sources = words.map { $0.source ?? .mixed }
        let recovered = try CallSpeechRecovery.recover(.init(
            tracks: prepared.tracks, words: words, sources: sources, intervals: intervals
        ))
        var assembled = RecordingTranscriptAssembler.assemble(.init(
            mediaPath: prepared.mediaPath, generatedAt: Date(), duration: prepared.duration,
            confidence: Self.average(words.map(\.confidence)), text: "", suggestedTitle: nil,
            words: words, wordSources: recovered.sources, diarizedIntervals: recovered.intervals,
            sourceVoiceLinks: CallAudioAnalysis.voiceLinks(.init(tracks: speech, intervals: intervals)),
            preservesDetectedSpeakers: request.speakerCount == .two
        ))
        assembled.speechRanges = (assembled.speechRanges ?? []) + speech.flatMap(\.windows)
        issues.append(contentsOf: TranscriptionQuality.speakerIssues(.init(
            transcript: assembled, expectedCount: request.speakerCount == .two ? 2 : nil,
            speechBySource: Self.speechBySource(speech)
        )))
        assembled.quality = .init(pipelineVersion: 2, model: request.model.rawValue,
                                  languages: Array(Set(languageCodes.values)).sorted(), issues: issues)
        let previous = try? artifactStore.load(from: prepared.artifactLocations.jsonURL)
        let named = previous.map { SpeakerIdentity.preservingNames(.init(transcript: assembled, previous: $0)) }
            ?? assembled
        let transcript = SpeakerIdentity.suggestingNames(.init(transcript: named, profiles: profiles))
        request.onUpdate(.init(stage: .saving))
        try artifactStore.save(.init(transcript: transcript, locations: prepared.artifactLocations))
        return transcript
    }

    private func makeSpeechDetector() throws -> VadManager {
        try modelStore.validateSpeechDetector()
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        let model = try MLModel(contentsOf: modelStore.speechDetectorURL, configuration: configuration)
        return VadManager(config: VadConfig(defaultThreshold: 0.6), vadModel: model)
    }

    private func loadedSpeechDetector() throws -> VadManager {
        if let speechDetector { return speechDetector }
        let detector = try makeSpeechDetector()
        speechDetector = detector
        return detector
    }

    private func requireInstalledModel() throws {
        guard TranscriptionSpeechModel.allCases.contains(where: { modelStore.isInstalled($0) }) else {
            throw LocalTranscriptionError.modelNotInstalled
        }
    }

    func reassignSpeakers(_ request: SpeakerFixRequest) async throws -> RecordingTranscript {
        try await workGate.acquire()
        defer { Task { await workGate.release() } }
        try Task.checkCancellation()
        try requireInstalledModel()
        request.onUpdate(TranscriptionEngineUpdate(stage: .preparingAudio))
        let preparedAudio = try await audioPreparer.prepare(request.source)
        defer {
            for track in preparedAudio.tracks {
                try? FileManager.default.removeItem(at: track.audioURL)
            }
        }
        let transcript = try artifactStore.load(from: preparedAudio.artifactLocations.jsonURL)
        request.onUpdate(TranscriptionEngineUpdate(stage: .loadingModels))
        let diarizers = try await loadedDiarizers(request.speakerCount)
        let speech = try await CallAudioAnalysis.analyze(.init(
            tracks: preparedAudio.tracks, intervals: [], detector: loadedSpeechDetector()
        ))
        let intervals = try await diarizedIntervals(DiarizationRequest(
            tracks: preparedAudio.tracks,
            microphone: diarizers.microphone,
            system: diarizers.system,
            count: request.speakerCount,
            speech: speech,
            onUpdate: request.onUpdate
        ))
        let words = transcript.words ?? []
        let recovered = try CallSpeechRecovery.recover(.init(
            tracks: preparedAudio.tracks,
            words: words,
            sources: zip(words, RecordingTranscriptAssembler.inferredWordSources(.init(
                words: words, intervals: intervals
            ))).map { $0.source ?? $1 },
            intervals: intervals
        ))
        let assembled = try RecordingTranscriptAssembler.reassignSpeakers(.init(
            transcript: transcript, diarizedIntervals: recovered.intervals, recoveredSources: recovered.sources,
            sourceVoiceLinks: CallAudioAnalysis.voiceLinks(.init(tracks: speech, intervals: intervals)),
            preservesDetectedSpeakers: request.speakerCount == .two
        ))
        let profiles = (try? await SpeakerVoiceStore.shared.profiles()) ?? []
        var reassigned = SpeakerIdentity.suggestingNames(.init(transcript: assembled, profiles: profiles))
        let quality = transcript.quality ?? .init(pipelineVersion: 2, model: "legacy", languages: [],
                                                  issues: [.init(kind: .unverifiedSpeech, startTime: 0,
                                                                 endTime: transcript.duration)])
        let keptIssues = quality.issues.filter {
            ![.uncertainSpeaker, .speakerCountMismatch, .similarVoices, .unstableSpeaker].contains($0.kind)
        }
        reassigned.quality = .init(pipelineVersion: quality.pipelineVersion, model: quality.model,
                                   languages: quality.languages,
                                   issues: keptIssues + TranscriptionQuality.speakerIssues(.init(
                                       transcript: reassigned, expectedCount: request.speakerCount == .two ? 2 : nil,
                                       speechBySource: Self.speechBySource(speech)
                                   )))
        request.onUpdate(TranscriptionEngineUpdate(stage: .saving))
        try artifactStore.save(TranscriptArtifactStore.SaveRequest(
            transcript: reassigned,
            locations: preparedAudio.artifactLocations
        ))
        return reassigned
    }

    func detectVoices(_ request: SpeakerFixRequest) async throws -> RecordingTranscript {
        try await workGate.acquire()
        defer { Task { await workGate.release() } }
        try Task.checkCancellation()
        try requireInstalledModel()
        try Task.checkCancellation()
        request.onUpdate(.init(stage: .preparingAudio))
        let prepared = try await audioPreparer.prepare(request.source)
        defer {
            for track in prepared.tracks { try? FileManager.default.removeItem(at: track.audioURL) }
        }
        try Task.checkCancellation()
        request.onUpdate(.init(stage: .loadingModels))
        let diarizers = try await loadedDiarizers(.automatic)
        let intervals = try await diarizedIntervals(.init(
            tracks: prepared.tracks, microphone: diarizers.microphone, system: diarizers.system,
            count: .automatic, speech: [],
            onUpdate: request.onUpdate
        ))
        try Task.checkCancellation()
        return VoiceDiscoveryAnalysis.transcript(.init(
            intervals: intervals, mediaPath: prepared.mediaPath, duration: prepared.duration
        ))
    }

    private func diarizedIntervals(_ request: DiarizationRequest) async throws -> [DiarizedInterval] {
        request.onUpdate(TranscriptionEngineUpdate(stage: .diarizing))
        let mixedTrackCount = request.tracks.filter { $0.source == .mixed }.count
        var mixedIndex = 0
        var intervals: [DiarizedInterval] = []
        for (index, track) in request.tracks.enumerated() {
            try Task.checkCancellation()
            request.onUpdate(TranscriptionEngineUpdate(.init(stage: .diarizing,
                source: track.source, index: index, total: request.tracks.count)))
            let prefix: String
            var diarizer: OfflineDiarizerManager
            switch track.source {
            case .microphone:
                prefix = RecordingTranscriptAssembler.microphoneSpeakerPrefix
                diarizer = request.microphone
            case .systemAudio:
                prefix = RecordingTranscriptAssembler.systemSpeakerPrefix
                diarizer = request.system
            case .mixed:
                prefix = mixedTrackCount > 1 ? "mix\(mixedIndex)-" : ""
                mixedIndex += 1
                diarizer = request.system
            }
            if let count = CallAudioAnalysis.speakerLimit(.init(
                count: request.count, tracks: request.speech, source: track.source
            )) {
                if constrainedDiarizers[count] == nil {
                    let constrained = OfflineDiarizerManager(config: OfflineDiarizerConfig.default.withSpeakers(exactly: count))
                    constrained.initialize(models: try await OfflineDiarizerModels.load(from: modelStore.diarizationDirectory))
                    constrainedDiarizers[count] = constrained
                }
                if let constrained = constrainedDiarizers[count] { diarizer = constrained }
            }
            do {
                let diarizationResult = try await diarizer.process(track.audioURL)
                try Task.checkCancellation()
                intervals.append(contentsOf: Self.intervals(diarizationResult.segments, prefix: prefix))
            } catch OfflineDiarizationError.noSpeechDetected {
                continue
            }
        }
        return intervals
    }

    func removeModels(_ model: TranscriptionSpeechModel) async throws {
        try await workGate.acquire()
        defer { Task { await workGate.release() } }
        try Task.checkCancellation()
        switch model {
        case .parakeet: asrManager = nil
        case .whisperMedium, .whisperLargeTurbo, .whisperLarge:
            if loadedWhisperModel == model {
                whisperManager = nil
                loadedWhisperModel = nil
            }
        }
        try modelStore.removeModels(model)
        if !TranscriptionSpeechModel.allCases.contains(where: { modelStore.isInstalled($0) }) {
            microphoneDiarizers = [:]
            systemDiarizer = nil
            constrainedDiarizers = [:]
            speechDetector = nil
            try modelStore.removeDiarizationModels()
        }
    }

    private func loadParakeet() async throws {
        try modelStore.validateParakeetModels()
        let asrModels = try await AsrModels.load(from: modelStore.asrDirectory, version: .v3)
        asrManager = AsrManager(config: Self.recognitionConfiguration, models: asrModels)
    }

    private func loadWhisper(_ request: WhisperLoadRequest) async throws {
        if loadedWhisperModel != request.model { whisperManager = nil }
        whisperManager = try await WhisperKit(.init(
            modelFolder: request.folder.path,
            tokenizerFolder: request.folder,
            segmentSeeker: CallWhisperSegmentSeeker(),
            load: true,
            download: false
        ))
        loadedWhisperModel = request.model
    }

    private func loadedManagers(_ request: ManagerRequest) async throws -> (
        asr: AsrManager?,
        whisper: WhisperKit?,
        microphone: OfflineDiarizerManager,
        system: OfflineDiarizerManager
    ) {
        guard modelStore.isInstalled(request.model) else {
            throw LocalTranscriptionError.modelNotInstalled
        }
        if request.model == .parakeet && asrManager == nil {
            try await loadParakeet()
        }
        if request.model.whisperVariant != nil && loadedWhisperModel != request.model {
            whisperManager = nil
            guard let folder = modelStore.whisperModelFolder(request.model) else {
                throw LocalTranscriptionError.modelNotInstalled
            }
            try await loadWhisper(.init(model: request.model, folder: folder))
        }
        let diarizers = try await loadedDiarizers(request.speakerCount)
        return (asrManager, whisperManager, diarizers.microphone, diarizers.system)
    }

    private func loadedDiarizers(_ speakerCount: TranscriptionSpeakerCount) async throws -> (
        microphone: OfflineDiarizerManager,
        system: OfflineDiarizerManager
    ) {
        if microphoneDiarizers[speakerCount] == nil || systemDiarizer == nil {
            let models = try await OfflineDiarizerModels.load(from: modelStore.diarizationDirectory)
            let microphone = OfflineDiarizerManager(
                config: Self.microphoneDiarizerConfiguration(speakerCount)
            )
            microphone.initialize(models: models)
            microphoneDiarizers[speakerCount] = microphone
            if systemDiarizer == nil {
                let system = OfflineDiarizerManager(config: Self.systemDiarizerConfiguration)
                system.initialize(models: models)
                systemDiarizer = system
            }
        }
        guard let microphone = microphoneDiarizers[speakerCount], let systemDiarizer else {
            throw LocalTranscriptionError.modelNotInstalled
        }
        return (microphone, systemDiarizer)
    }

    nonisolated static var recognitionConfiguration: ASRConfig {
        ASRConfig(melChunkContext: false, dualDecodeArbitration: true)
    }

    nonisolated static func microphoneDiarizerConfiguration(
        _ count: TranscriptionSpeakerCount
    ) -> OfflineDiarizerConfig {
        switch count {
        case .automatic: OfflineDiarizerConfig.default.withSpeakers(min: 1, max: 4)
        case .two: OfflineDiarizerConfig.default.withSpeakers(exactly: 2)
        }
    }

    nonisolated static var systemDiarizerConfiguration: OfflineDiarizerConfig {
        OfflineDiarizerConfig.default.withSpeakers(min: 1, max: 8)
    }

    static func intervals(
        _ segments: [TimedSpeakerSegment],
        prefix: String
    ) -> [DiarizedInterval] {
        segments.map { segment in
            DiarizedInterval(
                speakerID: prefix + segment.speakerId,
                startTime: TimeInterval(segment.startTimeSeconds),
                endTime: TimeInterval(segment.endTimeSeconds),
                embedding: segment.embedding
            )
        }
    }

    private static func speechBySource(
        _ speech: [CallAudioAnalysis.Track]
    ) -> [TranscriptWord.Source: [RecordingTranscript.SpeechRange]] {
        Dictionary(grouping: speech, by: \.source).mapValues { $0.flatMap(\.windows) }
    }

    private nonisolated static func phaseLabel(
        _ phase: DownloadPhase
    ) -> String {
        switch phase {
        case .listing:
            return "Checking model files"
        case .downloading(let completedFiles, let totalFiles):
            return "Downloading \(completedFiles) of \(totalFiles)"
        case .compiling:
            return "Preparing model"
        }
    }
}
