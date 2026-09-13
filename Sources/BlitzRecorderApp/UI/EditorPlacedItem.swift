import Foundation

struct EditorPlacedItem: Identifiable, Equatable {
    enum Kind: Hashable { case mask, text, zoom, music }
    struct ID: Hashable {
        let kind: Kind
        let value: UUID
    }
    struct Timing: Equatable {
        var start: Double
        var end: Double

        func previewTime(_ projection: EditorTimelineProjection) -> Double {
            let visibleStart = projection.displayTime(start)
            let visibleDuration = max(0, projection.displayTime(end) - visibleStart)
            return projection.takeTime(visibleStart + min(0.01, visibleDuration / 2))
        }
    }
    let id: ID
    let title: String
    let symbol: String
    let timing: Timing
    let isEnabled: Bool
    var isPoint: Bool { id.kind == .zoom }
    var canChangeTiming: Bool { id.kind != .music }
}

struct EditorPlacedTrack: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
    let items: [EditorPlacedItem]

    struct Music {
        let projectID: UUID
        let path: String?
        let duration: Double
    }

    static func music(_ request: Music) -> Self? {
        guard let path = request.path else { return nil }
        let item = EditorPlacedItem(id: .init(kind: .music, value: request.projectID),
            title: URL(fileURLWithPath: path).lastPathComponent + " · Full export", symbol: "music.note",
            timing: .init(start: 0, end: request.duration), isEnabled: true)
        return Self(id: "music", title: "Music", symbol: item.symbol, items: [item])
    }

    static func resolve(_ edits: TimelineEdits) -> [Self] {
        var rows = edits.privacyMasks.enumerated().map { index, mask in
            let title = "Mask \(index + 1) · \(mask.source.rawValue)"
            let item = EditorPlacedItem(id: .init(kind: .mask, value: mask.id), title: mask.style.rawValue,
                symbol: "eye.slash", timing: .init(start: mask.start, end: mask.end), isEnabled: true)
            return Self(id: mask.id.uuidString, title: title, symbol: item.symbol, items: [item])
        }
        rows += edits.textOverlays.enumerated().map { index, text in
            let item = EditorPlacedItem(id: .init(kind: .text, value: text.id), title: text.text,
                symbol: "textformat", timing: .init(start: text.start, end: text.end), isEnabled: true)
            return Self(id: text.id.uuidString, title: "\(text.style.preset.displayName) \(index + 1)",
                        symbol: item.symbol, items: [item])
        }
        if !edits.zoom.keyframes.isEmpty {
            rows.append(Self(id: "zoom", title: "Zoom", symbol: "plus.magnifyingglass",
                items: edits.zoom.keyframes.map { point in
                    EditorPlacedItem(id: .init(kind: .zoom, value: point.id),
                        title: String(format: "%.1f×", 1 / max(0.25, 1 - point.amount)),
                        symbol: "diamond.fill", timing: .init(start: point.time, end: point.time),
                        isEnabled: edits.zoom.isEnabled)
                }))
        }
        return rows
    }
}

enum EditorPlacedItemEditing {
    enum Gesture { case move, trimStart, trimEnd }
    struct Drag {
        let item: EditorPlacedItem
        let delta: Double
        let gesture: Gesture
        let projection: EditorTimelineProjection
    }
    struct Change {
        let id: EditorPlacedItem.ID
        let timing: EditorPlacedItem.Timing
    }
    struct Mutation {
        let edits: TimelineEdits
        let change: Change
    }
    struct Removal {
        let edits: TimelineEdits
        let id: EditorPlacedItem.ID
    }
    struct Split {
        let edits: TimelineEdits
        let id: EditorPlacedItem.ID
        let time: Double
    }

    static func splitting(_ request: Split) -> TimelineEdits? {
        var edits = request.edits
        let time = request.time
        switch request.id.kind {
        case .mask:
            guard let index = edits.privacyMasks.firstIndex(where: { $0.id == request.id.value }) else { return nil }
            let original = edits.privacyMasks[index]
            guard time > original.start + 0.05, time < original.end - 0.05 else { return nil }
            edits.privacyMasks[index].end = time
            edits.privacyMasks.insert(.init(id: UUID(), source: original.source, frame: original.frame,
                start: time, end: original.end, style: original.style), at: index + 1)
        case .text:
            guard let index = edits.textOverlays.firstIndex(where: { $0.id == request.id.value }) else { return nil }
            let original = edits.textOverlays[index]
            guard time > original.start + 0.05, time < original.end - 0.05 else { return nil }
            edits.textOverlays[index].end = time
            edits.textOverlays.insert(.init(id: UUID(), start: time, end: original.end, text: original.text,
                frame: original.frame, style: original.style, fadeSeconds: original.fadeSeconds), at: index + 1)
        case .zoom, .music: return nil
        }
        return edits
    }

    static func timing(_ request: Drag) -> EditorPlacedItem.Timing {
        let projection = request.projection
        guard request.item.canChangeTiming, request.delta.isFinite, projection.duration > 0 else { return request.item.timing }
        var start = projection.displayTime(request.item.timing.start)
        var end = projection.displayTime(request.item.timing.end)
        if request.item.isPoint {
            let time = projection.takeTime(min(projection.duration, max(0, start + request.delta)))
            return .init(start: time, end: time)
        }
        let minimum = min(0.05, projection.duration)
        switch request.gesture {
        case .move:
            let length = max(minimum, end - start)
            start = min(max(0, start + request.delta), max(0, projection.duration - length))
            end = min(projection.duration, start + length)
        case .trimStart:
            end = max(minimum, end)
            start = min(end - minimum, max(0, start + request.delta))
        case .trimEnd:
            start = min(start, projection.duration - minimum)
            end = max(start + minimum, min(projection.duration, end + request.delta))
        }
        let fragments = projection.visibleFragments(.init(start: start, end: end))
        guard let first = fragments.first, let last = fragments.last else { return request.item.timing }
        return .init(start: first.takeStart, end: last.takeEnd)
    }

    static func changing(_ request: Mutation) -> TimelineEdits? {
        let timing = request.change.timing
        guard timing.start.isFinite, timing.end.isFinite, timing.start >= 0 else { return nil }
        var edits = request.edits
        let id = request.change.id.value
        switch request.change.id.kind {
        case .music: return nil
        case .mask:
            guard timing.end > timing.start, let index = edits.privacyMasks.firstIndex(where: { $0.id == id }) else { return nil }
            edits.privacyMasks[index].start = timing.start
            edits.privacyMasks[index].end = timing.end
        case .text:
            guard timing.end > timing.start, let index = edits.textOverlays.firstIndex(where: { $0.id == id }) else { return nil }
            edits.textOverlays[index].start = timing.start
            edits.textOverlays[index].end = timing.end
        case .zoom:
            guard let index = edits.zoom.keyframes.firstIndex(where: { $0.id == id }) else { return nil }
            edits.zoom.keyframes[index].time = timing.start
            edits.zoom.keyframes.sort { $0.time < $1.time }
        }
        return edits
    }

    static func removing(_ request: Removal) -> TimelineEdits {
        var edits = request.edits
        switch request.id.kind {
        case .music: break
        case .mask: edits.privacyMasks.removeAll { $0.id == request.id.value }
        case .text: edits.textOverlays.removeAll { $0.id == request.id.value }
        case .zoom: edits.zoom.keyframes.removeAll { $0.id == request.id.value }
        }
        return edits
    }
}
