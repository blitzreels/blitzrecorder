import Foundation

struct ProjectTranscriptMatch: Equatable, Identifiable, Sendable {
    let id: UUID
    let time: Double
    let text: String
}

actor ProjectTranscriptSearch {
    struct Request: Sendable {
        let query: String
        let projects: [RecordingProjectHistory.Entry]
    }

    private struct CachedTranscript {
        let fingerprint: MediaFileFingerprint
        let transcript: RecordingTranscript
    }

    private var cache: [String: CachedTranscript] = [:]

    func search(_ request: Request) throws -> [UUID: [ProjectTranscriptMatch]] {
        let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [:] }
        var matches: [UUID: [ProjectTranscriptMatch]] = [:]
        let activePaths = Set(request.projects.map(\.projectPath))
        cache = cache.filter { activePaths.contains($0.key) }
        for entry in request.projects {
            try Task.checkCancellation()
            guard let project = try? TakeFileStore().loadRecordingProject(at: URL(fileURLWithPath: entry.projectPath)) else { continue }
            let store = TranscriptArtifactStore()
            let url = store.locations(for: project).jsonURL
            guard let fingerprint = MediaFileFingerprint(url: url) else { continue }
            let transcript: RecordingTranscript
            if let cached = cache[entry.projectPath], cached.fingerprint == fingerprint {
                transcript = cached.transcript
            } else if let loaded = try? store.load(from: url) {
                transcript = loaded
                cache[entry.projectPath] = CachedTranscript(fingerprint: fingerprint, transcript: loaded)
            } else {
                continue
            }
            let found = Self.matches(.init(query: query, transcript: transcript))
            if !found.isEmpty { matches[entry.id] = found }
        }
        return matches
    }

    struct MatchRequest {
        let query: String
        let transcript: RecordingTranscript
    }

    static func matches(_ request: MatchRequest) -> [ProjectTranscriptMatch] {
        let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        if request.transcript.segments.isEmpty {
            return request.transcript.text.localizedStandardContains(query)
                ? [.init(id: request.transcript.id, time: 0, text: request.transcript.text)] : []
        }
        return request.transcript.segments.compactMap { segment in
            guard segment.text.localizedStandardContains(query) else { return nil }
            return .init(id: segment.id, time: segment.startTime, text: segment.text)
        }
    }
}
