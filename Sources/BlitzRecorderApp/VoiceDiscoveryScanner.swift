import CryptoKit
import Foundation

actor VoiceDiscoveryScanner {
    struct Failure: Identifiable {
        let project: RecordingProjectHistory.Entry
        let message: String
        var id: UUID { project.id }
    }

    struct Update {
        let index: VoiceDiscoveryIndex
        let checked: Int
        let total: Int
        let currentTitle: String?
        let failures: [Failure]
    }

    struct Request {
        let projects: [RecordingProjectHistory.Entry]
        let profiles: [SavedSpeakerVoice]
        let onUpdate: @Sendable (Update) async -> Void
    }

    struct Configuration {
        let cacheDirectory: URL
        let analyze: @Sendable (URL) async throws -> RecordingTranscript
    }

    private let configuration: Configuration

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    static func local() -> VoiceDiscoveryScanner {
        let engine = LocalTranscriptionEngine()
        return VoiceDiscoveryScanner(configuration: .init(
            cacheDirectory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("BlitzRecorder/VoiceDiscovery", isDirectory: true),
            analyze: { url in
                try await engine.detectVoices(.init(source: .project(url), speakerCount: .automatic, onUpdate: { _ in }))
            }
        ))
    }

    func scan(_ request: Request) async throws {
        var index = VoiceDiscoveryIndex()
        var checked = 0
        var failures: [Failure] = []
        var pending: [(RecordingProjectHistory.Entry, RecordingProject)] = []
        let projects = request.projects.reduce(into: [RecordingProjectHistory.Entry]()) { result, entry in
            if !result.contains(where: { $0.id == entry.id }) { result.append(entry) }
        }
        let artifacts = TranscriptArtifactStore()
        for entry in projects {
            try Task.checkCancellation()
            do {
                let project = try TakeFileStore().loadRecordingProject(at: URL(fileURLWithPath: entry.projectPath))
                let transcript = try? artifacts.load(from: artifacts.locations(for: project).jsonURL)
                if let transcript, transcript.speakers.contains(where: { $0.voice != nil }) {
                    index.include(.init(project: entry, transcript: transcript, profiles: request.profiles))
                    checked += 1
                } else {
                    pending.append((entry, project))
                }
            } catch {
                failures.append(.init(project: entry, message: error.localizedDescription))
                checked += 1
            }
            await request.onUpdate(.init(index: index, checked: checked, total: projects.count,
                                         currentTitle: "Checking saved analysis", failures: failures))
        }
        for (entry, project) in pending {
            try Task.checkCancellation()
            await request.onUpdate(.init(index: index, checked: checked, total: projects.count,
                                         currentTitle: entry.displayTitle, failures: failures))
            do {
                let url = try cacheURL(project)
                let transcript: RecordingTranscript
                if let cached = try? artifacts.load(from: url) {
                    transcript = cached
                } else {
                    transcript = try await configuration.analyze(URL(fileURLWithPath: entry.projectPath))
                    try Task.checkCancellation()
                    try artifacts.save(.init(transcript: transcript, locations: .init(
                        jsonURL: url, textURL: url.deletingPathExtension().appendingPathExtension("txt")
                    )))
                }
                index.include(.init(project: entry, transcript: transcript, profiles: request.profiles))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Task.isCancelled { throw CancellationError() }
                failures.append(.init(project: entry, message: error.localizedDescription))
            }
            checked += 1
            await request.onUpdate(.init(index: index, checked: checked, total: projects.count,
                                         currentTitle: nil, failures: failures))
        }
    }

    private func cacheURL(_ project: RecordingProject) throws -> URL {
        var components = ["v1", project.id.uuidString, String(project.timelineTrimOffsetSeconds)]
        for source in project.sources where ["microphone", "systemAudio", "screen", "camera"].contains(source.role) {
            let attributes = try? FileManager.default.attributesOfItem(atPath: source.path)
            components.append(contentsOf: [source.role, source.path,
                String(describing: attributes?[.size]), String(describing: attributes?[.modificationDate]),
                String(project.sourceTimelineOffsetSeconds[source.role] ?? 0)])
        }
        let hash = SHA256.hash(data: Data(components.joined(separator: "\n").utf8))
            .map { String(format: "%02x", $0) }.joined()
        return configuration.cacheDirectory.appendingPathComponent(hash + ".json")
    }
}
