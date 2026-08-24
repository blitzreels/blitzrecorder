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
    private var diarizerManager: OfflineDiarizerManager?
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
            config: ASRConfig(melChunkContext: false),
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
        let diarizerManager = OfflineDiarizerManager()
        diarizerManager.initialize(models: diarizerModels)
        self.diarizerManager = diarizerManager

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
            try? FileManager.default.removeItem(at: preparedAudio.temporaryURL)
        }

        let managers = try await loadedManagers()
        request.onUpdate(TranscriptionEngineUpdate(stage: .transcribing))
        var decoderState = TdtDecoderState.make(
            decoderLayers: await managers.asr.decoderLayerCount
        )
        let asrResult = try await managers.asr.transcribe(
            preparedAudio.audioURL,
            decoderState: &decoderState
        )

        request.onUpdate(TranscriptionEngineUpdate(stage: .diarizing))
        let diarizedIntervals: [DiarizedInterval]
        do {
            let diarizationResult = try await managers.diarizer.process(
                preparedAudio.audioURL
            )
            diarizedIntervals = Self.intervals(diarizationResult.segments)
        } catch OfflineDiarizationError.noSpeechDetected {
            diarizedIntervals = []
        }
        let transcript = RecordingTranscriptAssembler.assemble(
            RecordingTranscriptAssembler.Request(
                mediaPath: preparedAudio.mediaPath,
                generatedAt: Date(),
                duration: asrResult.duration,
                confidence: asrResult.confidence,
                text: asrResult.text,
                suggestedTitle: nil,
                words: Self.words(asrResult.tokenTimings ?? []),
                diarizedIntervals: diarizedIntervals
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
        diarizerManager = nil
        try modelStore.removeModels()
    }

    private func loadedManagers() async throws -> (
        asr: AsrManager,
        diarizer: OfflineDiarizerManager
    ) {
        guard modelStore.isInstalled else {
            throw LocalTranscriptionError.modelNotInstalled
        }
        if let asrManager, let diarizerManager {
            return (asrManager, diarizerManager)
        }

        let asrModels = try await AsrModels.load(
            from: modelStore.asrDirectory,
            version: .v3
        )
        let loadedASR = AsrManager(
            config: ASRConfig(melChunkContext: false),
            models: asrModels
        )

        let diarizerModels = try await OfflineDiarizerModels.load(
            from: modelStore.diarizationDirectory
        )
        let loadedDiarizer = OfflineDiarizerManager()
        loadedDiarizer.initialize(models: diarizerModels)

        asrManager = loadedASR
        diarizerManager = loadedDiarizer
        return (loadedASR, loadedDiarizer)
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
        _ segments: [TimedSpeakerSegment]
    ) -> [DiarizedInterval] {
        segments.map { segment in
            DiarizedInterval(
                speakerID: segment.speakerId,
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
