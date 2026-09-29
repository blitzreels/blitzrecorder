import Foundation

struct TranscriptArtifactStore {
    struct Locations: Equatable, Sendable {
        let jsonURL: URL
        let textURL: URL
    }

    struct SaveRequest {
        let transcript: RecordingTranscript
        let locations: Locations
    }

    func locations(for project: RecordingProject) -> Locations {
        if let transcriptPath = project.sources.first(where: { $0.role == "transcript" })?.path {
            let textURL = URL(fileURLWithPath: transcriptPath)
            return Locations(
                jsonURL: textURL.deletingPathExtension().appendingPathExtension("json"),
                textURL: textURL
            )
        }
        let directory = URL(fileURLWithPath: project.takeDirectoryPath, isDirectory: true)
        return Locations(
            jsonURL: directory.appendingPathComponent("transcript.json"),
            textURL: directory.appendingPathComponent("transcript.txt")
        )
    }

    func locations(for recordingURL: URL) -> Locations {
        let baseURL = recordingURL.deletingPathExtension()
        return Locations(
            jsonURL: baseURL.appendingPathExtension("transcript.json"),
            textURL: baseURL.appendingPathExtension("transcript.txt")
        )
    }

    func save(_ request: SaveRequest) throws {
        try FileManager.default.createDirectory(
            at: request.locations.jsonURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(request.transcript).write(
            to: request.locations.jsonURL,
            options: .atomic
        )
        try request.transcript.formattedText.write(
            to: request.locations.textURL,
            atomically: true,
            encoding: .utf8
        )
    }

    func load(from url: URL) throws -> RecordingTranscript {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            RecordingTranscript.self,
            from: Data(contentsOf: url)
        )
    }
}
