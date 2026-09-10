import Foundation

struct EditorTextDraft {
    var text = ""
    var preset = TextOverlayPreset.title
    var startText = "00:00.00"
    var endText = "00:03.00"
    var fades = true
    private(set) var original: TextOverlay?

    struct Position {
        let time: Double
        let duration: Double
    }

    var isEditing: Bool { original != nil }

    func range(_ duration: Double) -> EditorTimeRange? {
        guard let start = time(.init(text: startText, original: original?.start, duration: duration)),
            let end = time(.init(text: endText, original: original?.end, duration: duration)), end > start + 0.05
        else { return nil }
        return .init(start: start, end: end)
    }

    private struct Time {
        let text: String
        let original: Double?
        let duration: Double
    }

    private func time(_ value: Time) -> Double? {
        if let original = value.original, value.text == EditorPlaybackPosition.display(original), original <= value.duration {
            return original
        }
        if value.text == EditorPlaybackPosition.display(value.duration) { return value.duration }
        return EditorPlaybackPosition.parse(.init(text: value.text, duration: value.duration))
    }

    mutating func moveToPlayhead(_ position: Position) {
        let length = range(position.duration)?.duration ?? 3
        let start = min(max(0, position.time), max(0, position.duration - 0.1))
        startText = EditorPlaybackPosition.display(start)
        endText = EditorPlaybackPosition.display(min(position.duration, start + length))
    }

    mutating func edit(_ overlay: TextOverlay) {
        original = overlay
        text = overlay.text
        preset = overlay.style.preset
        startText = EditorPlaybackPosition.display(overlay.start)
        endText = EditorPlaybackPosition.display(overlay.end)
        fades = overlay.fadeSeconds > 0
    }

    func overlay(_ duration: Double) -> TextOverlay? {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, let range = range(duration) else { return nil }
        let existing = original.flatMap { $0.style.preset == preset ? $0 : nil }
        return TextOverlay(
            id: original?.id ?? UUID(), start: range.start, end: range.end,
            text: String(content.prefix(500)),
            frame: existing?.frame ?? TextOverlay.defaultFrame(for: preset),
            style: existing?.style ?? .preset(preset),
            fadeSeconds: fades ? (original.flatMap { $0.fadeSeconds > 0 ? $0.fadeSeconds : nil } ?? 0.25) : 0
        )
    }
}
