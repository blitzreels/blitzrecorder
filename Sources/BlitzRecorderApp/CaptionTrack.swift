import Foundation

enum CaptionStyle: String, Codable, CaseIterable, Sendable {
    case outline
    case background

    var title: String { self == .outline ? "Outline" : "Dark background" }
}

enum CaptionSize: String, Codable, CaseIterable, Sendable {
    case small, medium, large

    var title: String { rawValue.capitalized }
    var fraction: Double {
        switch self {
        case .small: 0.04
        case .medium: 0.05
        case .large: 0.065
        }
    }
}

enum CaptionPosition: String, Codable, CaseIterable, Sendable {
    case bottom, top
    var title: String { rawValue.capitalized }
}

struct CaptionCue: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let start: Double
    let end: Double
    var text: String
    var words: [TranscriptWord]
}

struct CaptionTrack: Codable, Equatable, Sendable {
    var isEnabled = false
    var style = CaptionStyle.outline
    var size = CaptionSize.medium
    var position = CaptionPosition.bottom
    var shadow = true
    var cues: [CaptionCue] = []

    static let empty = CaptionTrack()
}

enum CaptionGenerator {
    static func cues(_ transcript: RecordingTranscript) -> [CaptionCue] {
        let words = (transcript.words ?? []).filter {
            $0.startTime.isFinite && $0.endTime.isFinite && $0.endTime > max(0, $0.startTime)
                && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.sorted { $0.startTime < $1.startTime }
        if !words.isEmpty { return group(words) }
        return transcript.segments.sorted { $0.startTime < $1.startTime }.flatMap { segment in
            guard segment.startTime.isFinite, segment.endTime.isFinite,
                  segment.endTime > max(0, segment.startTime) else { return [CaptionCue]() }
            let parts = segment.text.split(whereSeparator: \.isWhitespace).map(String.init)
            let count = parts.reduce(0) { $0 + $1.count + 1 }
            guard count > 0 else { return [] }
            let start = max(0, segment.startTime)
            let duration = segment.endTime - start
            var offset = 0
            let approximated = parts.map { text in
                let wordStart = start + duration * Double(offset) / Double(count)
                offset += text.count + 1
                return TranscriptWord(text: text, startTime: wordStart,
                    endTime: start + duration * Double(offset) / Double(count), confidence: segment.confidence,
                    speakerID: segment.speakerID)
            }
            return group(approximated)
        }
    }

    static func text(_ words: [TranscriptWord]) -> String {
        words.reduce("") { result, word in
            let text = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !result.isEmpty else { return text }
            let attached = text.first.map { ".,!?;:…，。！？、".contains($0) } ?? false
            return result + (attached ? "" : " ") + text
        }
    }

    private static func group(_ words: [TranscriptWord]) -> [CaptionCue] {
        var result: [CaptionCue] = []
        var pending: [TranscriptWord] = []
        func flush() {
            guard let first = pending.first, let end = pending.map(\.endTime).max() else { return }
            result.append(.init(id: UUID(), start: max(0, first.startTime), end: end,
                                text: text(pending), words: pending))
            pending = []
        }
        for word in words {
            if let first = pending.first, let last = pending.last,
               word.startTime - last.endTime > 0.55 || word.endTime - first.startTime > 4
                || text(pending + [word]).count > 42 || pending.count >= 8
                || (last.speakerID != nil && word.speakerID != nil && last.speakerID != word.speakerID) {
                flush()
            }
            pending.append(word)
            if word.text.last.map({ ".!?…。！？".contains($0) }) == true { flush() }
        }
        flush()
        return result
    }
}

struct CaptionTimeline: Equatable, Sendable {
    struct Request {
        let track: CaptionTrack
        let cuts: [TimelineCut]
    }

    let cues: [CaptionCue]
    static let empty = CaptionTimeline(.init(track: .empty, cuts: []))

    init(_ request: Request) {
        guard request.track.isEnabled else { cues = []; return }
        let source = request.track.cues.filter {
            $0.start.isFinite && $0.end.isFinite && $0.end > max(0, $0.start)
                && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.sorted { $0.start < $1.start }
        let map = TimelineTimeMap(takeDuration: .init(seconds: source.map(\.end).max() ?? 0), cuts: request.cuts)
        var result: [CaptionCue] = []
        var firstRange = 0
        for cue in source {
            while firstRange < map.keptRanges.count, map.keptRanges[firstRange].takeEnd.seconds <= cue.start {
                firstRange += 1
            }
            for range in map.keptRanges.dropFirst(firstRange) {
                if range.takeStart.seconds >= cue.end { break }
                let start = max(cue.start, range.takeStart.seconds)
                let end = min(cue.end, range.takeEnd.seconds)
                let words = cue.words.filter { $0.endTime > start && $0.startTime < end }
                let text = cue.words.isEmpty ? cue.text : CaptionGenerator.text(words)
                guard end > start, !text.isEmpty else { continue }
                result.append(.init(id: cue.id, start: start, end: end, text: text, words: []))
            }
        }
        let sorted = result.sorted { $0.start < $1.start }
        cues = sorted.enumerated().compactMap { index, cue in
            let end = index + 1 < sorted.count ? min(cue.end, sorted[index + 1].start) : cue.end
            guard end > cue.start else { return nil }
            return .init(id: cue.id, start: cue.start, end: end, text: cue.text, words: [])
        }
    }

    func cue(at time: Double) -> CaptionCue? {
        guard time.isFinite else { return nil }
        var lower = 0
        var upper = cues.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if cues[middle].start <= time { lower = middle + 1 } else { upper = middle }
        }
        guard lower > 0, time < cues[lower - 1].end else { return nil }
        return cues[lower - 1]
    }
}
