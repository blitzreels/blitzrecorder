import FluidAudio
import Foundation
import WhisperKit

struct TranscriptionModelDownloadUpdate: Sendable {
    let fractionCompleted: Double
    let phase: String
}

struct TranscriptionEngineUpdate: Sendable {
    enum Stage: Sendable {
        case preparingAudio
        case loadingModels
        case transcribing
        case diarizing
        case saving
    }

    let stage: Stage
    let detail: String?

    init(stage: Stage) {
        self.stage = stage
        detail = nil
    }

    struct Track {
        let stage: Stage
        let source: RecordingTranscriptAssembler.WordSource
        let index: Int
        let total: Int
    }

    init(_ track: Track) {
        stage = track.stage
        let source: String
        switch track.source {
        case .microphone: source = "Microphone"
        case .systemAudio: source = "Mac audio"
        case .mixed: source = "Audio"
        }
        detail = "\(source) · Track \(track.index + 1) of \(track.total)"
    }
}

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
        let onUpdate: @Sendable (TranscriptionEngineUpdate) -> Void
    }

    private struct ManagerRequest {
        let model: TranscriptionSpeechModel
        let speakerCount: TranscriptionSpeakerCount
    }

    private var asrManager: AsrManager?
    private var whisperManager: WhisperKit?
    private var whisperModelFolder: URL?
    private var microphoneDiarizers: [TranscriptionSpeakerCount: OfflineDiarizerManager] = [:]
    private var systemDiarizer: OfflineDiarizerManager?
    private let modelStore = LocalTranscriptionModelStore()
    private let audioPreparer = TranscriptionAudioPreparer()
    private let artifactStore = TranscriptArtifactStore()

    func downloadModels(_ request: DownloadRequest) async throws {
        try modelStore.createRootDirectory()
        switch request.model {
        case .parakeet:
            let asrModels = try await AsrModels.downloadAndLoad(
                to: modelStore.asrDirectory,
                version: .v3,
                progressHandler: { progress in
                    request.onUpdate(TranscriptionModelDownloadUpdate(
                        fractionCompleted: progress.fractionCompleted * 0.65,
                        phase: Self.phaseLabel(progress.phase)
                    ))
                }
            )
            asrManager = AsrManager(config: Self.recognitionConfiguration, models: asrModels)
        case .whisperMedium:
            let folder = try await WhisperKit.download(
                variant: "openai_whisper-medium",
                downloadBase: modelStore.whisperDirectory,
                progressCallback: { progress in
                    request.onUpdate(TranscriptionModelDownloadUpdate(
                        fractionCompleted: progress.fractionCompleted * 0.65,
                        phase: "Downloading Whisper"
                    ))
                }
            )
            request.onUpdate(.init(fractionCompleted: 0.65, phase: "Preparing Whisper"))
            whisperManager = try await WhisperKit(.init(
                modelFolder: folder.path,
                tokenizerFolder: modelStore.whisperDirectory,
                load: true,
                download: false
            ))
            whisperModelFolder = folder
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
        let microphoneDiarizer = OfflineDiarizerManager(
            config: Self.microphoneDiarizerConfiguration(.automatic)
        )
        microphoneDiarizer.initialize(models: diarizerModels)
        microphoneDiarizers[.automatic] = microphoneDiarizer
        let twoSpeakerDiarizer = OfflineDiarizerManager(
            config: Self.microphoneDiarizerConfiguration(.two)
        )
        twoSpeakerDiarizer.initialize(models: diarizerModels)
        microphoneDiarizers[.two] = twoSpeakerDiarizer
        let systemDiarizer = OfflineDiarizerManager(config: Self.systemDiarizerConfiguration)
        systemDiarizer.initialize(models: diarizerModels)
        self.systemDiarizer = systemDiarizer

        if request.model == .parakeet {
            try modelStore.markInstalled()
        } else if let whisperModelFolder {
            try modelStore.markWhisperInstalled(at: whisperModelFolder)
        }
        request.onUpdate(TranscriptionModelDownloadUpdate(
            fractionCompleted: 1,
            phase: "Ready"
        ))
    }

    func transcribe(_ request: TranscribeRequest) async throws -> RecordingTranscript {
        request.onUpdate(TranscriptionEngineUpdate(stage: .preparingAudio))
        let preparedAudio = try await audioPreparer.prepare(request.source)
        defer {
            for track in preparedAudio.tracks {
                try? FileManager.default.removeItem(at: track.audioURL)
            }
        }

        request.onUpdate(TranscriptionEngineUpdate(stage: .loadingModels))
        let managers = try await loadedManagers(.init(
            model: request.model,
            speakerCount: request.speakerCount
        ))
        var words: [TranscriptWord] = []
        var wordSources: [RecordingTranscriptAssembler.WordSource] = []
        var confidences: [Float] = []

        for (index, track) in preparedAudio.tracks.enumerated() {
            request.onUpdate(TranscriptionEngineUpdate(.init(stage: .transcribing,
                source: track.source, index: index, total: preparedAudio.tracks.count)))
            let trackWords: [TranscriptWord]
            let confidence: Float
            switch request.model {
            case .parakeet:
                guard let asr = managers.asr else { throw LocalTranscriptionError.modelNotInstalled }
                var decoderState = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
                let result = try await asr.transcribe(track.audioURL, decoderState: &decoderState)
                trackWords = Self.words(result.tokenTimings ?? [])
                confidence = result.confidence
            case .whisperMedium:
                guard let whisper = managers.whisper else { throw LocalTranscriptionError.modelNotInstalled }
                let results = try await whisper.transcribe(
                    audioPath: track.audioURL.path,
                    decodeOptions: DecodingOptions(
                        language: request.language.whisperCode,
                        wordTimestamps: true,
                        chunkingStrategy: .vad
                    )
                )
                trackWords = results.flatMap(\.allWords).map {
                    TranscriptWord(
                        text: $0.word.trimmingCharacters(in: .whitespacesAndNewlines),
                        startTime: TimeInterval($0.start),
                        endTime: TimeInterval($0.end),
                        confidence: $0.probability
                    )
                }.filter { !$0.text.isEmpty && !Self.isNonSpeechPlaceholder($0.text) }
                confidence = Self.average(trackWords.map(\.confidence))
            }
            words.append(contentsOf: trackWords)
            wordSources.append(contentsOf: Array(repeating: track.source, count: trackWords.count))
            confidences.append(confidence)
        }

        let intervals = try await diarizedIntervals(DiarizationRequest(
            tracks: preparedAudio.tracks,
            microphone: managers.microphone,
            system: managers.system,
            onUpdate: request.onUpdate
        ))

        let transcript = RecordingTranscriptAssembler.assemble(
            RecordingTranscriptAssembler.Request(
                mediaPath: preparedAudio.mediaPath,
                generatedAt: Date(),
                duration: preparedAudio.duration,
                confidence: Self.average(confidences),
                text: words.map(\.text).joined(separator: " "),
                suggestedTitle: nil,
                words: words,
                wordSources: wordSources,
                diarizedIntervals: intervals
            )
        )

        request.onUpdate(TranscriptionEngineUpdate(stage: .saving))
        try artifactStore.save(TranscriptArtifactStore.SaveRequest(
            transcript: transcript,
            locations: preparedAudio.artifactLocations
        ))
        return transcript
    }

    func reassignSpeakers(_ request: SpeakerFixRequest) async throws -> RecordingTranscript {
        guard modelStore.isInstalled(.parakeet) || modelStore.isInstalled(.whisperMedium) else {
            throw LocalTranscriptionError.modelNotInstalled
        }
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
        let intervals = try await diarizedIntervals(DiarizationRequest(
            tracks: preparedAudio.tracks,
            microphone: diarizers.microphone,
            system: diarizers.system,
            onUpdate: request.onUpdate
        ))
        let reassigned = try RecordingTranscriptAssembler.reassignSpeakers(.init(
            transcript: transcript,
            diarizedIntervals: intervals
        ))
        request.onUpdate(TranscriptionEngineUpdate(stage: .saving))
        try artifactStore.save(TranscriptArtifactStore.SaveRequest(
            transcript: reassigned,
            locations: preparedAudio.artifactLocations
        ))
        return reassigned
    }

    private func diarizedIntervals(_ request: DiarizationRequest) async throws -> [DiarizedInterval] {
        request.onUpdate(TranscriptionEngineUpdate(stage: .diarizing))
        let mixedTrackCount = request.tracks.filter { $0.source == .mixed }.count
        var mixedIndex = 0
        var intervals: [DiarizedInterval] = []
        for (index, track) in request.tracks.enumerated() {
            request.onUpdate(TranscriptionEngineUpdate(.init(stage: .diarizing,
                source: track.source, index: index, total: request.tracks.count)))
            let prefix: String
            let diarizer: OfflineDiarizerManager
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
            do {
                let diarizationResult = try await diarizer.process(track.audioURL)
                intervals.append(contentsOf: Self.intervals(diarizationResult.segments, prefix: prefix))
            } catch OfflineDiarizationError.noSpeechDetected {
                continue
            }
        }
        return intervals
    }

    func removeModels(_ model: TranscriptionSpeechModel) async throws {
        switch model {
        case .parakeet: asrManager = nil
        case .whisperMedium: whisperManager = nil
        }
        try modelStore.removeModels(model)
        if !modelStore.isInstalled(.parakeet) && !modelStore.isInstalled(.whisperMedium) {
            microphoneDiarizers = [:]
            systemDiarizer = nil
            try modelStore.removeDiarizationModels()
        }
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
            let asrModels = try await AsrModels.load(from: modelStore.asrDirectory, version: .v3)
            asrManager = AsrManager(config: Self.recognitionConfiguration, models: asrModels)
        }
        if request.model == .whisperMedium && whisperManager == nil {
            guard let folder = modelStore.whisperModelFolder else {
                throw LocalTranscriptionError.modelNotInstalled
            }
            whisperManager = try await WhisperKit(.init(
                modelFolder: folder.path,
                tokenizerFolder: modelStore.whisperDirectory,
                load: true,
                download: false
            ))
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

    private static func average(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        return values.reduce(Float.zero, +) / Float(values.count)
    }

    private static func isNonSpeechPlaceholder(_ text: String) -> Bool {
        let normalized = text.lowercased().trimmingCharacters(in: .punctuationCharacters)
        return ["silence", "music", "noise", "applause", "inaudible"].contains(normalized)
            && (text.first == "[" || text.first == "(")
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

enum LocalTranscriptionError: LocalizedError {
    case modelNotInstalled
    case transcriptUnavailable
    case transcriptBusy

    var errorDescription: String? {
        switch self {
        case .modelNotInstalled:
            return "Download the transcription model in Settings."
        case .transcriptUnavailable:
            return "The transcript is unavailable."
        case .transcriptBusy:
            return "This transcript is already being updated. Try again when it finishes."
        }
    }
}

struct LocalTranscriptionModelStore: LocalTranscriptionModelStoring {
    private struct Marker: Codable {
        let version: Int
        let installedAt: Date
        let asrModel: String
        let diarizationModel: String
    }

    var rootDirectory: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return applicationSupport
            .appendingPathComponent("BlitzRecorder", isDirectory: true)
            .appendingPathComponent("TranscriptionModels", isDirectory: true)
    }

    var asrDirectory: URL {
        rootDirectory.appendingPathComponent("ASR", isDirectory: true)
    }

    var parakeetModelDirectory: URL {
        rootDirectory.appendingPathComponent("parakeet-tdt-0.6b-v3", isDirectory: true)
    }

    var diarizationDirectory: URL {
        rootDirectory.appendingPathComponent("Diarization", isDirectory: true)
    }

    var whisperDirectory: URL {
        rootDirectory.appendingPathComponent("Whisper", isDirectory: true)
    }

    private var whisperMarkerURL: URL {
        rootDirectory.appendingPathComponent("whisper-medium.txt")
    }

    var whisperModelFolder: URL? {
        guard let path = try? String(contentsOf: whisperMarkerURL, encoding: .utf8) else {
            return nil
        }
        let folder = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: folder.path) ? folder : nil
    }

    var markerURL: URL {
        rootDirectory.appendingPathComponent("installed.json")
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: markerURL.path)
            && AsrModels.modelsExist(at: asrDirectory, version: .v3)
    }

    func isInstalled(_ model: TranscriptionSpeechModel) -> Bool {
        switch model {
        case .parakeet: isInstalled
        case .whisperMedium: whisperModelFolder != nil
        }
    }

    func installedSize(_ model: TranscriptionSpeechModel) -> Int64 {
        let directory = model == .parakeet ? parakeetModelDirectory : whisperDirectory
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        return enumerator.reduce(into: Int64.zero) { total, item in
            guard let url = item as? URL,
                  let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                return
            }
            total += Int64(size)
        }
    }

    func createRootDirectory() throws {
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
    }

    func markInstalled() throws {
        try createRootDirectory()
        let marker = Marker(
            version: 1,
            installedAt: Date(),
            asrModel: "parakeet-tdt-0.6b-v3-coreml",
            diarizationModel: "speaker-diarization-community-1-coreml"
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(marker).write(to: markerURL, options: .atomic)
    }

    func markWhisperInstalled(at folder: URL) throws {
        try createRootDirectory()
        try folder.path.write(to: whisperMarkerURL, atomically: true, encoding: .utf8)
    }

    func removeModels(_ model: TranscriptionSpeechModel) throws {
        switch model {
        case .parakeet:
            if FileManager.default.fileExists(atPath: parakeetModelDirectory.path) {
                try FileManager.default.removeItem(at: parakeetModelDirectory)
            }
            if FileManager.default.fileExists(atPath: markerURL.path) {
                try FileManager.default.removeItem(at: markerURL)
            }
        case .whisperMedium:
            if FileManager.default.fileExists(atPath: whisperDirectory.path) {
                try FileManager.default.removeItem(at: whisperDirectory)
            }
            if FileManager.default.fileExists(atPath: whisperMarkerURL.path) {
                try FileManager.default.removeItem(at: whisperMarkerURL)
            }
        }
    }

    func removeDiarizationModels() throws {
        if FileManager.default.fileExists(atPath: diarizationDirectory.path) {
            try FileManager.default.removeItem(at: diarizationDirectory)
        }
    }
}
