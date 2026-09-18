import Foundation

struct EditorClipTrimSession: Equatable {
    struct Origin: Equatable {
        let edits: TimelineEdits
        let clip: EditorTimeRange
        let nextClipStart: Double?
        let pixelsPerSecond: CGFloat
        let duration: Double
    }

    private(set) var origin: Origin?
    private(set) var draft: TimelineEdits?
    private(set) var lockedDisplayDuration: Double?

    var isActive: Bool { origin != nil || lockedDisplayDuration != nil }

    func edits(committed: TimelineEdits) -> TimelineEdits {
        draft ?? committed
    }

    mutating func preview(_ edits: TimelineEdits?, currentDisplayDuration: Double) {
        if lockedDisplayDuration == nil {
            lockedDisplayDuration = currentDisplayDuration
        }
        draft = edits
    }

    mutating func beginExpand(_ origin: Origin, currentDisplayDuration: Double) {
        guard self.origin == nil else { return }
        self.origin = origin
        if lockedDisplayDuration == nil {
            lockedDisplayDuration = currentDisplayDuration
        }
    }

    mutating func applyExpand(translationWidth: CGFloat) -> EditorTimeRange? {
        guard let origin else { return nil }
        let dragged = EditorClipSpine.dragRight(.init(
            edits: origin.edits, clip: origin.clip, nextClipStart: origin.nextClipStart,
            duration: origin.duration, delta: Double(translationWidth / origin.pixelsPerSecond)
        ))
        draft = dragged.edits
        return dragged.selection
    }

    mutating func finish() -> TimelineEdits? {
        let result = draft
        origin = nil
        draft = nil
        lockedDisplayDuration = nil
        return result
    }
}
