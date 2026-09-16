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
        let spoken = items.map(\.range)
        let speechSource = spoken.isEmpty
            ? (transcript.speechRanges ?? []).map { EditorTimeRange(start: $0.startTime, end: $0.endTime) }
            : spoken
        let speech = merged(speechSource).map {
            EditorTimeRange(start: max(0, $0.start - 0.15), end: min(request.duration, $0.end + 0.15))
        }
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
                            text: "Silence", kind: .nonDialogue))
                }
                cursor = max(cursor, voice.end)
                if cursor >= sound.end { break }
            }
            if sound.end - cursor >= 0.12 {
                append((range: .init(start: cursor, end: sound.end), text: "Silence", kind: .nonDialogue))
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

    struct RemainingSilence {
        let cuts: [TimelineCut]
        let projection: EditorTimelineProjection
    }

    static func remainingSilence(_ request: RemainingSilence) -> [TimelineCut] {
        request.cuts.filter {
            request.projection.displayTime($0.end) - request.projection.displayTime($0.start) >= 1.0 / 600
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
        let layout: EditorTranscriptLayout
        let viewport: EditorTimelineViewport
        let pixelsPerSecond: CGFloat
        let width: CGFloat
        let height: CGFloat
        let selections: [EditorTimeRange]
        let onSelect: (EditorTimelineRangeClick) -> Void
    }

    let configuration: Configuration

    var body: some View {
        let runs = configuration.layout.runs(.init(
            viewport: configuration.viewport, pixelsPerSecond: configuration.pixelsPerSecond))
        let selectedRanges = SilenceSegmentSelection.coalesced(configuration.selections)
        Canvas { context, size in
            for run in runs {
                var lower = 0
                var upper = selectedRanges.count
                while lower < upper {
                    let middle = (lower + upper) / 2
                    if selectedRanges[middle].start <= run.item.source.range.start { lower = middle + 1 }
                    else { upper = middle }
                }
                let selected = lower > 0 && selectedRanges[lower - 1].end >= run.item.source.range.end
                let tint = run.item.source.kind == .nonDialogue ? BlitzUI.secondaryText : BlitzUI.mint
                let rect = CGRect(x: run.x, y: 6, width: max(1, run.width - 1), height: size.height - 12)
                let path = Path(roundedRect: rect, cornerRadius: run.width >= 4 ? 3 : 0)
                context.fill(path, with: .color(tint.opacity(selected ? 0.25 : 0.1)))
                if selected {
                    context.stroke(path, with: .color(.white.opacity(0.8)), lineWidth: 1)
                }
                if run.width >= 28 {
                    let label = context.resolve(Text(run.item.source.text).font(.system(size: 11, weight: .medium))
                        .foregroundStyle(selected ? .white : tint))
                    if label.measure(in: CGSize(width: .infinity, height: rect.height)).width <= rect.width - 8 {
                        var clipped = context
                        clipped.clip(to: path)
                        clipped.draw(label, at: CGPoint(x: rect.minX + 4, y: rect.midY), anchor: .leading)
                        continue
                    }
                }
            }
        }
        .frame(width: configuration.viewport.width, height: configuration.height)
        .offset(x: configuration.viewport.lowerBound)
        .frame(width: configuration.width, height: configuration.height, alignment: .leading)
        .background(Color.white.opacity(0.025))
        .contentShape(.rect)
        .pointingHandCursor()
        .gesture(SpatialTapGesture().onEnded { event in
            if let item = configuration.layout.item(at: Double(event.location.x / configuration.pixelsPerSecond)) {
                configuration.onSelect(.init(range: item.source.range, modifiers: NSEvent.modifierFlags))
            }
        })
        .overlay(alignment: .topLeading) {
            ForEach(runs.filter { $0.width >= 28 }) { run in
                accessibleWord(run)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Transcript")
        .accessibilityValue("\(configuration.selections.count) items selected")
        .help("Click to select. Shift-click selects every item between two clicks. ⌘-click toggles an item. Zoom in to read.")
    }

    private func accessibleWord(_ run: EditorTranscriptLayout.Run) -> some View {
                Button {
                    configuration.onSelect(.init(range: run.item.source.range, modifiers: NSEvent.modifierFlags))
                } label: {
                    Color.clear
                        .frame(width: run.width, height: configuration.height)
                        .contentShape(.rect)
                }
                .buttonStyle(BlitzPressButtonStyle())
                .offset(x: configuration.viewport.lowerBound + run.x)
                .accessibilityLabel(run.item.source.text)
                .accessibilityValue("\(SilenceTime.label(run.item.start)) to \(SilenceTime.label(run.item.end))")
                .accessibilityAction(named: "Extend selection") {
                    configuration.onSelect(.init(range: run.item.source.range, modifiers: .shift))
                }
                .accessibilityAction(named: "Toggle selection") {
                    configuration.onSelect(.init(range: run.item.source.range, modifiers: .command))
                }
    }
}
