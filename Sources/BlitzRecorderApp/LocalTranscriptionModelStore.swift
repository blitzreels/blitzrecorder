import FluidAudio
import Foundation

enum LocalTranscriptionError: LocalizedError {
    case modelNotInstalled
    case incompleteModel(String)
    case transcriptUnavailable
    case transcriptBusy

    var errorDescription: String? {
        switch self {
        case .modelNotInstalled:
            return "Download the transcription model in Settings."
        case .incompleteModel(let file):
            return "The transcription model is incomplete (\(file)). Download it again in Settings."
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

    let rootDirectory: URL

    init(rootDirectory: URL = Self.defaultRootDirectory) {
        self.rootDirectory = rootDirectory
    }

    private static var defaultRootDirectory: URL {
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

    var speechDetectionDirectory: URL {
        rootDirectory.appendingPathComponent("SpeechDetection", isDirectory: true)
    }

    var speechDetectorURL: URL {
        speechDetectionDirectory.appendingPathComponent(Repo.vad.folderName, isDirectory: true)
            .appendingPathComponent(ModelNames.VAD.sileroVadFile, isDirectory: true)
    }

    func validateSpeechDetector() throws {
        try CompiledTranscriptionModel.validate(speechDetectorURL)
    }

    var whisperDirectory: URL {
        rootDirectory.appendingPathComponent("Whisper", isDirectory: true)
    }

    private var whisperMarkerURL: URL {
        rootDirectory.appendingPathComponent("whisper-medium.txt")
    }

    func whisperDownloadBase(_ model: TranscriptionSpeechModel) -> URL {
        whisperDirectory.appendingPathComponent(model.rawValue, isDirectory: true)
    }

    private func whisperMarkerURL(_ model: TranscriptionSpeechModel) -> URL {
        rootDirectory.appendingPathComponent("whisper-\(model.rawValue).txt")
    }

    func whisperModelFolder(_ model: TranscriptionSpeechModel) -> URL? {
        var markers = [whisperMarkerURL(model)]
        if model == .whisperMedium { markers.append(whisperMarkerURL) }
        for marker in markers {
            guard let path = try? String(contentsOf: marker, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else { continue }
            let folder = URL(fileURLWithPath: path)
            if ["AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc", "TextDecoder.mlmodelc"].allSatisfy({
                (try? CompiledTranscriptionModel.validate(folder.appendingPathComponent($0))) != nil
            }), FileManager.default.fileExists(atPath: folder.appendingPathComponent("config.json").path) { return folder }
        }
        return nil
    }

    var markerURL: URL {
        rootDirectory.appendingPathComponent("installed.json")
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: markerURL.path)
            && AsrModels.modelsExist(at: asrDirectory, version: .v3)
            && (try? validateParakeetModels()) != nil
    }

    func validateParakeetModels() throws {
        for name in ModelNames.ASR.requiredModelsV3().sorted() {
            try CompiledTranscriptionModel.validate(parakeetModelDirectory.appendingPathComponent(name))
        }
    }

    func isInstalled(_ model: TranscriptionSpeechModel) -> Bool {
        (model.whisperVariant == nil ? isInstalled : whisperModelFolder(model) != nil)
            && (try? validateSpeechDetector()) != nil
            && (try? validateDiarizationModels()) != nil
    }

    func validateDiarizationModels() throws {
        let directory = diarizationDirectory.appendingPathComponent(Repo.diarizer.folderName, isDirectory: true)
        for name in [ModelNames.OfflineDiarizer.segmentationPath, ModelNames.OfflineDiarizer.embeddingPath,
                     ModelNames.OfflineDiarizer.fbankPath, ModelNames.OfflineDiarizer.pldaRhoPath] {
            try CompiledTranscriptionModel.validate(directory.appendingPathComponent(name, isDirectory: true))
        }
        let parameters = directory.appendingPathComponent(ModelNames.OfflineDiarizer.pldaParameters)
        guard FileManager.default.isReadableFile(atPath: parameters.path),
              let data = try? Data(contentsOf: parameters), !data.isEmpty else {
            throw LocalTranscriptionError.incompleteModel(parameters.lastPathComponent)
        }
    }

    func installedSize(_ model: TranscriptionSpeechModel) -> Int64 {
        let directory = model.whisperVariant == nil ? parakeetModelDirectory : (whisperModelFolder(model) ?? whisperDownloadBase(model))
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

    func markWhisperInstalled(_ model: TranscriptionSpeechModel, at folder: URL) throws {
        try createRootDirectory()
        try folder.path.write(to: whisperMarkerURL(model), atomically: true, encoding: .utf8)
        if model == .whisperMedium {
            try folder.path.write(to: whisperMarkerURL, atomically: true, encoding: .utf8)
        }
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
        case .whisperMedium, .whisperLargeTurbo, .whisperLarge:
            if let folder = whisperModelFolder(model), FileManager.default.fileExists(atPath: folder.path) {
                try FileManager.default.removeItem(at: folder)
            }
            for marker in [whisperMarkerURL(model), model == .whisperMedium ? whisperMarkerURL : nil].compactMap({ $0 }) {
                if FileManager.default.fileExists(atPath: marker.path) {
                    try FileManager.default.removeItem(at: marker)
                }
            }
        }
    }

    func removeDiarizationModels() throws {
        if FileManager.default.fileExists(atPath: diarizationDirectory.path) {
            try FileManager.default.removeItem(at: diarizationDirectory)
        }
    }
}
