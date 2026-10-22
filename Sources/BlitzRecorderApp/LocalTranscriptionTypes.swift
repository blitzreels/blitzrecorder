import Foundation

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

protocol LocalTranscriptionEngineServing: Sendable {
    func downloadModels(
        _ request: LocalTranscriptionEngine.DownloadRequest
    ) async throws
    func transcribe(
        _ request: LocalTranscriptionEngine.TranscribeRequest
    ) async throws -> RecordingTranscript
    func reassignSpeakers(
        _ request: LocalTranscriptionEngine.SpeakerFixRequest
    ) async throws -> RecordingTranscript
    func removeModels(_ model: TranscriptionSpeechModel) async throws
}

protocol LocalTranscriptionModelStoring: Sendable {
    func isInstalled(_ model: TranscriptionSpeechModel) -> Bool
    func installedSize(_ model: TranscriptionSpeechModel) -> Int64
}

enum TranscriptionSpeechModel: String, CaseIterable, Sendable {
    case parakeet
    case whisperMedium
    case whisperLargeTurbo
    case whisperLarge

    /// WhisperKit repo id. Nil for the Parakeet ASR model.
    var whisperVariant: String? {
        switch self {
        case .parakeet: nil
        case .whisperMedium: "openai_whisper-medium"
        case .whisperLargeTurbo: "openai_whisper-large-v3_turbo"
        case .whisperLarge: "openai_whisper-large-v3"
        }
    }

    var title: String {
        switch self {
        case .parakeet: "Parakeet v3"
        case .whisperMedium: "Whisper Medium"
        case .whisperLargeTurbo: "Whisper Large Turbo"
        case .whisperLarge: "Whisper Large"
        }
    }

    var detail: String {
        switch self {
        case .parakeet: "Fast, multilingual; supports a language lock"
        case .whisperMedium: "Multilingual; supports a language lock"
        case .whisperLargeTurbo: "Large-v3 accuracy, faster than full Large"
        case .whisperLarge: "Highest accuracy on long calls"
        }
    }

    var plainDetail: String {
        switch self {
        case .parakeet: "Fastest. Detects the language or uses your choice."
        case .whisperMedium: "Clearer. Lets you pick the language."
        case .whisperLargeTurbo: "Much more accurate. Large download, still practical."
        case .whisperLarge: "Most accurate. Largest download and the slowest pass."
        }
    }
}

enum TranscriptionLanguage: String, CaseIterable, Sendable {
    case automatic
    case french
    case english

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .french: "French"
        case .english: "English"
        }
    }

    var whisperCode: String? {
        switch self {
        case .automatic: nil
        case .french: "fr"
        case .english: "en"
        }
    }
}

enum TranscriptionSpeakerCount: String, CaseIterable, Sendable {
    case automatic
    case two

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .two: "2 speakers"
        }
    }
}

enum TranscriptionModelState: Equatable {
    case notDownloaded
    case downloading(progress: Double, phase: String)
    case ready(size: Int64)
    case failed(String)

    var isReady: Bool {
        if case .ready = self {
            return true
        }
        return false
    }
}

enum TranscriptionJobStatus: Equatable {
    case notGenerated
    case noAudio
    case waitingForModel
    case queued
    case preparingAudio
    case loadingModels
    case transcribing
    case diarizing
    case saving
    case ready(URL)
    case failed(String)

    var label: String {
        switch self {
        case .notGenerated:
            return "Generate transcript"
        case .noAudio:
            return "No audio track"
        case .waitingForModel:
            return "Model required"
        case .queued:
            return "Queued"
        case .preparingAudio:
            return "Preparing audio"
        case .loadingModels:
            return "Loading speech model"
        case .transcribing:
            return "Transcribing"
        case .diarizing:
            return "Finding speakers"
        case .saving:
            return "Saving transcript"
        case .ready:
            return "Transcript ready"
        case .failed:
            return "Transcript failed"
        }
    }

    var isRunning: Bool {
        switch self {
        case .queued, .preparingAudio, .loadingModels, .transcribing, .diarizing, .saving:
            return true
        case .notGenerated, .noAudio, .waitingForModel, .ready, .failed:
            return false
        }
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

enum SpeakerFixProgress {
    static func label(_ update: TranscriptionEngineUpdate) -> String {
        let stage: String
        switch update.stage {
        case .preparingAudio: stage = TranscriptionJobStatus.preparingAudio.label
        case .loadingModels: stage = "Loading speaker model"
        case .transcribing, .diarizing: stage = TranscriptionJobStatus.diarizing.label
        case .saving: stage = TranscriptionJobStatus.saving.label
        }
        guard let detail = update.detail else { return stage }
        return "\(stage) · \(detail)"
    }
}

struct CompletedTranscription {
    let source: TranscriptionMediaSource
    let transcript: RecordingTranscript
}
