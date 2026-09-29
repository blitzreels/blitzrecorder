import AVFoundation
import CryptoKit
import Foundation

struct HostedVideoDetails: Codable, Equatable, Sendable {
    struct Cue: Codable, Equatable, Sendable {
        let start: Double
        var end: Double
        var text: String
        let speaker: String?
    }
    struct Chapter: Codable, Equatable, Sendable {
        let start: Double
        let title: String
        let summary: String?
    }
    let version: Int
    let summary: String?
    let language: String?
    let recordedAt: String?
    let transcript: [Cue]
    let chapters: [Chapter]

    static let empty = Self(version: 1, summary: nil, language: nil, recordedAt: nil, transcript: [], chapters: [])

    struct Projection {
        let transcript: RecordingTranscript
        let chapters: [RecordingProject.ChapterSnapshot]
        let cuts: [TimelineCut]
        let playbackRate: Double
        let outputDuration: Double
        let recordedAt: Date
    }

    static func project(_ request: Projection) -> Self? {
        guard request.playbackRate.isFinite, (0.5...3).contains(request.playbackRate),
              request.transcript.duration.isFinite, request.transcript.duration > 0 else { return nil }
        let map = TimelineTimeMap(takeDuration: TimelineTimeMap.time(request.transcript.duration),
                                  cuts: request.cuts.filter(\.isEnabled), playbackRate: request.playbackRate)
        guard abs(map.outputDuration.seconds - request.outputDuration) < 0.35 else { return nil }
        let hasWords = !(request.transcript.words ?? []).isEmpty
        let words = hasWords ? request.transcript.words! : request.transcript.segments.map {
            TranscriptWord(text: $0.text, startTime: $0.startTime, endTime: $0.endTime,
                           confidence: $0.confidence, speakerID: $0.speakerID)
        }
        var cues: [Cue] = []
        var rangeIndex = 0
        var priorRange = -1
        for word in words.sorted(by: { $0.startTime < $1.startTime }) {
            guard word.startTime.isFinite, word.endTime.isFinite, word.endTime > word.startTime else { continue }
            while rangeIndex < map.keptRanges.count && map.keptRanges[rangeIndex].takeEnd.seconds <= word.startTime {
                rangeIndex += 1
            }
            guard rangeIndex < map.keptRanges.count else { break }
            let range = map.keptRanges[rangeIndex]
            guard word.startTime >= range.takeStart.seconds, word.endTime <= range.takeEnd.seconds + 0.001 else { continue }
            let text = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let start = map.outputSeconds(forTakeSeconds: word.startTime)
            let end = min(request.outputDuration, map.outputSeconds(forTakeSeconds: word.endTime))
            guard end > start else { continue }
            let speaker = word.speakerID.map { request.transcript.speakerName(for: $0) }
            if hasWords, let prior = cues.last, priorRange == rangeIndex, prior.speaker == speaker,
               start - prior.end < 0.8, end - prior.start < 7, prior.text.count < 180,
               prior.text.last.map({ !".!?…".contains($0) }) == true {
                cues[cues.count - 1].text += (text.first.map { ",.;:!?".contains($0) } == true ? "" : " ") + text
                cues[cues.count - 1].end = end
            } else {
                cues.append(.init(start: start, end: end, text: text, speaker: speaker))
            }
            priorRange = rangeIndex
        }
        let sourceChapters = request.chapters.sorted { $0.time < $1.time }
        var chapters: [Chapter] = []
        for (index, chapter) in sourceChapters.enumerated() {
            let end = chapter.endTime ?? (index + 1 < sourceChapters.count ? sourceChapters[index + 1].time : request.transcript.duration)
            guard let range = map.keptRanges.first(where: { $0.takeEnd.seconds > chapter.time && $0.takeStart.seconds < end }) else { continue }
            let start = map.outputSeconds(forTakeSeconds: max(chapter.time, range.takeStart.seconds))
            guard start < request.outputDuration, chapters.last?.start != start else { continue }
            chapters.append(.init(start: start, title: chapter.title, summary: chapter.summary))
        }
        return .init(version: 1, summary: nil, language: nil,
                     recordedAt: ISO8601DateFormatter().string(from: request.recordedAt), transcript: cues, chapters: chapters)
    }
}

struct HostingExportMetadata: Codable {
    let title: String
    let details: HostedVideoDetails

    struct SaveRequest {
        let fileURL: URL
        let project: RecordingProject
        let playbackRate: Double
    }

    static func save(_ request: SaveRequest) async {
        let store = TranscriptArtifactStore()
        let transcript = try? store.load(from: store.locations(for: request.project).jsonURL)
        let duration = try? await AVURLAsset(url: request.fileURL).load(.duration)
        let details = transcript.flatMap { transcript in
            duration.flatMap { duration in
                HostedVideoDetails.project(.init(transcript: transcript, chapters: request.project.chapters,
                    cuts: request.project.edits.cuts, playbackRate: request.playbackRate,
                    outputDuration: duration.seconds, recordedAt: request.project.createdAt))
            }
        } ?? .empty
        let metadata = Self(title: request.project.title, details: details)
        if let url = try? cacheURL(request.fileURL), let data = try? JSONEncoder().encode(metadata) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func load(_ url: URL) -> Self? {
        guard let path = try? cacheURL(url), let data = try? Data(contentsOf: path) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    struct ResolveRequest {
        let fileURL: URL
        let projectPath: String?
    }

    /// Cached details from export time, rebuilt from the project when they are missing or were saved before the
    /// transcript existed.
    static func resolve(_ request: ResolveRequest) async -> Self {
        let cached = load(request.fileURL)
        if let cached, !cached.details.transcript.isEmpty { return cached }
        if let projectPath = request.projectPath,
           let rebuilt = await rebuild(.init(fileURL: request.fileURL, projectPath: projectPath)) {
            if let url = try? cacheURL(request.fileURL), let data = try? JSONEncoder().encode(rebuilt) {
                try? data.write(to: url, options: .atomic)
            }
            return rebuilt
        }
        return cached ?? .init(title: request.fileURL.deletingPathExtension().lastPathComponent, details: .empty)
    }

    private struct RebuildRequest {
        let fileURL: URL
        let projectPath: String
    }

    /// The export speed is not recorded per file, so pick the rate whose edited duration matches the file.
    private static func rebuild(_ request: RebuildRequest) async -> Self? {
        guard let saved = try? TakeFileStore().loadRecordingProject(at: URL(fileURLWithPath: request.projectPath)) else {
            return nil
        }
        let layout = saved.exports.first { $0.path == request.fileURL.path }?.layout
            .flatMap(CaptureLayout.init(rawValue:)) ?? saved.selectedOutputLayout
        let project = saved.outputProject(for: layout)
        let store = TranscriptArtifactStore()
        guard let transcript = try? store.load(from: store.locations(for: project).jsonURL),
              transcript.duration.isFinite, transcript.duration > 0,
              let duration = try? await AVURLAsset(url: request.fileURL).load(.duration).seconds,
              duration.isFinite, duration > 0 else { return nil }
        let cuts = project.edits.cuts.filter(\.isEnabled)
        let takeDuration = TimelineTimeMap.time(transcript.duration)
        let preferred = project.editorState.exportRecipe?.playbackRate ?? ExportPlaybackRate.normal.value
        let rate = ([preferred] + ExportPlaybackRate.all.map(\.value)).min { lhs, rhs in
            let left = abs(TimelineTimeMap(takeDuration: takeDuration, cuts: cuts, playbackRate: lhs).outputDuration.seconds - duration)
            let right = abs(TimelineTimeMap(takeDuration: takeDuration, cuts: cuts, playbackRate: rhs).outputDuration.seconds - duration)
            return left < right
        } ?? preferred
        guard let details = HostedVideoDetails.project(.init(transcript: transcript, chapters: project.chapters, cuts: cuts,
            playbackRate: rate, outputDuration: duration, recordedAt: project.createdAt)) else { return nil }
        return .init(title: project.title, details: details)
    }

    static func fingerprint(_ url: URL) throws -> String {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard let size = values.fileSize, let modified = values.contentModificationDate else {
            throw CocoaError(.fileReadUnknown)
        }
        let input = "\(url.standardizedFileURL.path):\(size):\(modified.timeIntervalSince1970)"
        return SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func cacheURL(_ url: URL) throws -> URL {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true).appendingPathComponent("BlitzRecorder/HostingMetadata", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(try fingerprint(url)).appendingPathExtension("json")
    }
}
