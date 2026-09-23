import FluidAudio
import Foundation

struct TranscriptionModelDownloadUpdate: Sendable {
    let fractionCompleted: Double
    let phase: String
}

struct TranscriptionEngineUpdate: Sendable {
    enum Stage: Sendable {
        case preparingAudio
        case transcribing
        case diarizing
        case saving
    }

    let stage: Stage
}

actor LocalTranscriptionEngine: LocalTranscriptionEngineServing {
    struct DownloadRequest: Sendable {
        let onUpdate: @Sendable (TranscriptionModelDownloadUpdate) -> Void
    }

    struct TranscribeRequest: Sendable {
        let source: TranscriptionMediaSource
        let onUpdate: @Sendable (TranscriptionEngineUpdate) -> Void
    }

    private var asrManager: AsrManager?
    private var microphoneDiarizer: OfflineDiarizerManager?
    private var systemDiarizer: OfflineDiarizerManager?
    private let modelStore = LocalTranscriptionModelStore()
    private let audioPreparer = TranscriptionAudioPreparer()
    private let artifactStore = TranscriptArtifactStore()

    func downloadModels(_ request: DownloadRequest) async throws {
        try modelStore.createRootDirectory()
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
        let asrManager = AsrManager(
            config: Self.recognitionConfiguration,
            models: asrModels
        )
        self.asrManager = asrManager

        let diarizerModels = try await OfflineDiarizerModels.load(
            from: modelStore.diarizationDirectory,
            progressHandler: { progress in
                request.onUpdate(TranscriptionModelDownloadUpdate(
                    fractionCompleted: 0.65 + progress.fractionCompleted * 0.35,
                    phase: Self.phaseLabel(progress.phase)
                ))
            }
        )
        let microphoneDiarizer = OfflineDiarizerManager(config: Self.microphoneDiarizerConfiguration)
        microphoneDiarizer.initialize(models: diarizerModels)
        self.microphoneDiarizer = microphoneDiarizer
        let systemDiarizer = OfflineDiarizerManager(config: Self.systemDiarizerConfiguration)
        systemDiarizer.initialize(models: diarizerModels)
        self.systemDiarizer = systemDiarizer

        try modelStore.markInstalled()
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

        let managers = try await loadedManagers()
        var words: [TranscriptWord] = []
        var wordSources: [RecordingTranscriptAssembler.WordSource] = []
        var intervals: [DiarizedInterval] = []
        var confidences: [Float] = []

        request.onUpdate(TranscriptionEngineUpdate(stage: .transcribing))
        for track in preparedAudio.tracks {
            var decoderState = TdtDecoderState.make(
                decoderLayers: await managers.asr.decoderLayerCount
            )
            let asrResult = try await managers.asr.transcribe(
                track.audioURL,
                decoderState: &decoderState
            )
            let trackWords = Self.words(asrResult.tokenTimings ?? [])
            words.append(contentsOf: trackWords)
            wordSources.append(contentsOf: Array(repeating: track.source, count: trackWords.count))
            confidences.append(asrResult.confidence)
        }

        request.onUpdate(TranscriptionEngineUpdate(stage: .diarizing))
        let mixedTrackCount = preparedAudio.tracks.filter { $0.source == .mixed }.count
        var mixedIndex = 0
        for track in preparedAudio.tracks {
            let prefix: String
            let diarizer: OfflineDiarizerManager
            switch track.source {
            case .microphone:
                prefix = RecordingTranscriptAssembler.microphoneSpeakerPrefix
                diarizer = managers.microphone
            case .systemAudio:
                prefix = RecordingTranscriptAssembler.systemSpeakerPrefix
                diarizer = managers.system
            case .mixed:
                prefix = mixedTrackCount > 1 ? "mix\(mixedIndex)-" : ""
                mixedIndex += 1
                diarizer = managers.system
            }
            do {
                let diarizationResult = try await diarizer.process(track.audioURL)
                intervals.append(contentsOf: Self.intervals(diarizationResult.segments, prefix: prefix))
            } catch OfflineDiarizationError.noSpeechDetected {
                continue
            }
        }

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

    func removeModels() async throws {
        asrManager = nil
        microphoneDiarizer = nil
        systemDiarizer = nil
        try modelStore.removeModels()
    }

    private func loadedManagers() async throws -> (
        asr: AsrManager,
        microphone: OfflineDiarizerManager,
        system: OfflineDiarizerManager
    ) {
        guard modelStore.isInstalled else {
            throw LocalTranscriptionError.modelNotInstalled
        }
        if let asrManager, let microphoneDiarizer, let systemDiarizer {
            return (asrManager, microphoneDiarizer, systemDiarizer)
        }

        let asrModels = try await AsrModels.load(
            from: modelStore.asrDirectory,
            version: .v3
        )
        let loadedASR = AsrManager(
            config: Self.recognitionConfiguration,
            models: asrModels
        )

        let diarizerModels = try await OfflineDiarizerModels.load(
            from: modelStore.diarizationDirectory
        )
        let loadedMicrophone = OfflineDiarizerManager(config: Self.microphoneDiarizerConfiguration)
        loadedMicrophone.initialize(models: diarizerModels)
        let loadedSystem = OfflineDiarizerManager(config: Self.systemDiarizerConfiguration)
        loadedSystem.initialize(models: diarizerModels)

        asrManager = loadedASR
        microphoneDiarizer = loadedMicrophone
        systemDiarizer = loadedSystem
        return (loadedASR, loadedMicrophone, loadedSystem)
    }

    nonisolated static var recognitionConfiguration: ASRConfig {
        ASRConfig(melChunkContext: false, dualDecodeArbitration: true)
    }

    nonisolated static var microphoneDiarizerConfiguration: OfflineDiarizerConfig {
        OfflineDiarizerConfig.default.withSpeakers(exactly: 1)
    }

    nonisolated static var systemDiarizerConfiguration: OfflineDiarizerConfig {
        OfflineDiarizerConfig.default.withSpeakers(min: 1, max: 8)
    }

    private static func words(_ timings: [TokenTiming]) -> [TranscriptWord] {
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

    private static func intervals(
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

    var errorDescription: String? {
        switch self {
        case .modelNotInstalled:
            return "Download the transcription model in Settings."
        case .transcriptUnavailable:
            return "The transcript is unavailable."
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

    var diarizationDirectory: URL {
        rootDirectory.appendingPathComponent("Diarization", isDirectory: true)
    }

    var markerURL: URL {
        rootDirectory.appendingPathComponent("installed.json")
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: markerURL.path)
            && AsrModels.modelsExist(at: asrDirectory, version: .v3)
    }

    var installedSize: Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: rootDirectory,
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

    func removeModels() throws {
        guard FileManager.default.fileExists(atPath: rootDirectory.path) else {
            return
        }
        try FileManager.default.removeItem(at: rootDirectory)
    }
}
