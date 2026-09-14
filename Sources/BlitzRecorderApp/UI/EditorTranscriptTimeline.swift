import SwiftUI

struct EditorTranscriptItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case word
        case phrase
        case nonDialogue
    }

    let id: Int
    let range: EditorTimeRange
    let text: String
    let kind: Kind
}

enum EditorTranscriptTimeline {
    struct Request {
        let transcript: RecordingTranscript
        let windows: [SilenceWindow]
        let threshold: Double
        let duration: Double
    }

    static func items(_ request: Request) -> [EditorTranscriptItem] {
        guard request.duration.isFinite, request.duration > 0 else { return [] }
        let transcript = request.transcript
        var items: [EditorTranscriptItem] = []
        if let words = transcript.words, !words.isEmpty {
            for word in words {
                append((range: .init(start: word.startTime, end: word.endTime), text: word.text, kind: .word))
            }
        } else {
            for segment in transcript.segments {
                append((range: .init(start: segment.startTime, end: segment.endTime), text: segment.text, kind: .phrase))
            }
        }
        let speech = merged(items.map(\.range) + (transcript.speechRanges ?? []).map {
            .init(start: $0.startTime, end: $0.endTime)
        }).map { EditorTimeRange(start: max(0, $0.start - 0.15), end: min(request.duration, $0.end + 0.15)) }
        let sounds = merged(request.windows.filter { $0.decibels > request.threshold }.map {
            .init(start: max(0, $0.start - 0.06), end: min(request.duration, $0.end + 0.06))
        })
        var speechIndex = 0
        for sound in sounds {
            var cursor = sound.start
            while speechIndex < speech.count && speech[speechIndex].end <= cursor { speechIndex += 1 }
            for voice in speech.dropFirst(speechIndex) {
                if voice.start >= sound.end { break }
                if voice.start - cursor >= 0.12 {
                    append((range: .init(start: cursor, end: min(sound.end, voice.start)),
                            text: "No detected dialogue", kind: .nonDialogue))
                }
                cursor = max(cursor, voice.end)
                if cursor >= sound.end { break }
            }
            if sound.end - cursor >= 0.12 {
                append((range: .init(start: cursor, end: sound.end), text: "No detected dialogue", kind: .nonDialogue))
            }
        }
        return items.sorted { $0.range.start < $1.range.start }

        func append(_ item: (range: EditorTimeRange, text: String, kind: EditorTranscriptItem.Kind)) {
            let (range, text, kind) = item
            guard let bounded = EditorTimeRange.resolve(.init(
                anchor: range.start, head: range.end, duration: request.duration
            )), bounded.duration > 0, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            items.append(.init(id: items.count, range: bounded, text: text, kind: kind))
        }
    }

    private static func merged(_ ranges: [EditorTimeRange]) -> [EditorTimeRange] {
        var result: [EditorTimeRange] = []
        for range in ranges.filter({ $0.start.isFinite && $0.end.isFinite && $0.end > $0.start })
            .sorted(by: { $0.start < $1.start }) {
            if let last = result.last, range.start <= last.end {
                result[result.count - 1] = .init(start: last.start, end: max(last.end, range.end))
            } else {
                result.append(range)
            }
        }
        return result
    }
}

struct EditorTranscriptStrip: View {
    struct Configuration {
        let items: [EditorTranscriptItem]
        let projection: EditorTimelineProjection
        let viewport: EditorTimelineViewport
        let pixelsPerSecond: CGFloat
        let width: CGFloat
        let height: CGFloat
        let selection: EditorTimeRange?
        let onSelect: (EditorTimeRange) -> Void
    }

    let configuration: Configuration

    var body: some View {
        ZStack(alignment: .leading) {
            Color.white.opacity(0.025)
            ForEach(visibleItems) { item in
                let start = configuration.projection.displayTime(item.range.start)
                let end = configuration.projection.displayTime(item.range.end)
                let width = CGFloat(end - start) * configuration.pixelsPerSecond
                let selected = configuration.selection == item.range
                let tint = item.kind == .nonDialogue ? Color.orange : BlitzUI.mint
                Button { configuration.onSelect(item.range) } label: {
                    Text(item.text)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .frame(width: max(1, width - 1), height: configuration.height - 4, alignment: .leading)
                        .background(tint.opacity(selected ? 0.3 : 0.14), in: RoundedRectangle(cornerRadius: 3))
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(tint.opacity(selected ? 1 : 0.35)))
                        .clipped()
                }
                .buttonStyle(BlitzPressButtonStyle())
                .offset(x: CGFloat(start) * configuration.pixelsPerSecond)
                .accessibilityLabel(item.text)
                .accessibilityValue("\(SilenceTime.label(start)) to \(SilenceTime.label(end))")
                .help(item.text + (item.kind == .phrase
                    ? " · Phrase timing. Generate word timings to cut individual words."
                    : " · Select, listen, then Delete to remove with all tracks in sync. Zoom in to read short words."))
            }
        }
        .frame(width: configuration.width, height: configuration.height, alignment: .leading)
    }

    private var visibleItems: [EditorTranscriptItem] {
        configuration.items.filter {
            let start = CGFloat(configuration.projection.displayTime($0.range.start)) * configuration.pixelsPerSecond
            let end = CGFloat(configuration.projection.displayTime($0.range.end)) * configuration.pixelsPerSecond
            return end > start && end > configuration.viewport.lowerBound && start < configuration.viewport.upperBound
        }
    }
}
