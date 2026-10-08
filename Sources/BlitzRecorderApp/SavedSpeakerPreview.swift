import Foundation

struct SavedSpeakerPreview: Codable, Equatable, Sendable {
    let fileName: String
    let sourceTitle: String
    let sourceProjectID: UUID
    let duration: Double
    let text: String
}

extension SpeakerVoiceStore {
    struct RenameRequest: Sendable {
        let id: UUID
        let name: String
    }

    func rename(_ request: RenameRequest) throws {
        let name = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != "You" else { throw PreviewError.invalidName }
        var saved = try profiles()
        guard let index = saved.firstIndex(where: { $0.id == request.id }) else { throw PreviewError.missingProfile }
        saved[index].name = name
        try write(saved)
    }

    struct SavePreviewRequest: Sendable {
        let profileID: UUID
        let sample: SpeakerSampleBuilder.Sample
    }

    func savePreview(_ request: SavePreviewRequest) throws {
        var saved = try profiles()
        guard let index = saved.firstIndex(where: { $0.id == request.profileID }) else { throw PreviewError.missingProfile }
        let previous = saved[index].preview
        let preview = SavedSpeakerPreview(
            fileName: UUID().uuidString + ".m4a", sourceTitle: request.sample.sourceTitle,
            sourceProjectID: request.sample.sourceProjectID, duration: request.sample.duration, text: request.sample.text)
        let destination = previewURL(preview)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contentsOf: request.sample.url).write(to: destination, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        saved[index].preview = preview
        do { try write(saved) }
        catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        if let previous { try? FileManager.default.removeItem(at: previewURL(previous)) }
    }

    func sampleURL(for id: UUID) throws -> URL? {
        guard let preview = try profiles().first(where: { $0.id == id })?.preview else { return nil }
        let sample = previewURL(preview)
        return FileManager.default.isReadableFile(atPath: sample.path) ? sample : nil
    }

    func previewURL(_ preview: SavedSpeakerPreview) -> URL {
        url.deletingLastPathComponent().appendingPathComponent("SpeakerSamples", isDirectory: true)
            .appendingPathComponent(URL(fileURLWithPath: preview.fileName).lastPathComponent)
    }

    enum PreviewError: LocalizedError {
        case invalidName
        case missingProfile
        case missingSample

        var errorDescription: String? {
            switch self {
            case .invalidName: "Enter the speaker’s name instead of You."
            case .missingProfile: "This saved speaker is no longer available."
            case .missingSample: "No clear sample was found. Remember this voice again from a transcript with available audio."
            }
        }
    }
}
