import Foundation

struct EditorClipTrimSession: Equatable {
    struct Origin: Equatable {
        let edits: TimelineEdits
        let clip: EditorTimeRange
        let nextClipStart: Double?
        let pixelsPerSecond: CGFloat
        let duration: Double
    }

    struct BeginRequest {
        let origin: Origin
        let displayDuration: Double
    }

    private(set) var origin: Origin?
    private(set) var draft: TimelineEdits?
    private(set) var lockedDisplayDuration: Double?

    var isActive: Bool { origin != nil }

    func edits(committed: TimelineEdits) -> TimelineEdits {
        draft ?? committed
    }

    mutating func beginTrim(_ request: BeginRequest) {
        let origin = request.origin
        guard self.origin == nil, origin.pixelsPerSecond.isFinite, origin.pixelsPerSecond > 0,
            request.displayDuration.isFinite, request.displayDuration > 0 else { return }
        self.origin = origin
        lockedDisplayDuration = request.displayDuration
    }

    mutating func applyTrim(translationWidth: CGFloat) -> EditorTimeRange? {
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
