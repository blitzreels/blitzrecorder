import Foundation

struct EditorClipTrimSession: Equatable {
    enum Edge: String { case left, right }

    struct Origin: Equatable {
        let edits: TimelineEdits
        let clip: EditorTimeRange
        let nextClipStart: Double?
        let pixelsPerSecond: CGFloat
        let duration: Double
        var edge: Edge = .right
        var previousClipEnd: Double? = nil
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
        let delta = Double(translationWidth / origin.pixelsPerSecond)
        let dragged = origin.edge == .left ? EditorClipSpine.dragLeft(.init(
            edits: origin.edits, clip: origin.clip, previousClipEnd: origin.previousClipEnd,
            duration: origin.duration, delta: delta
        )) : EditorClipSpine.dragRight(.init(
            edits: origin.edits, clip: origin.clip, nextClipStart: origin.nextClipStart,
            duration: origin.duration, delta: delta
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
