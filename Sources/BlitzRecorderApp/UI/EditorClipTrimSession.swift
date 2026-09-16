import Foundation

struct EditorClipTrimSession: Equatable {
    private(set) var draft: TimelineEdits?
    private(set) var lockedDisplayDuration: Double?

    var isActive: Bool { lockedDisplayDuration != nil }

    func edits(committed: TimelineEdits) -> TimelineEdits {
        draft ?? committed
    }

    mutating func preview(_ edits: TimelineEdits?, currentDisplayDuration: Double) {
        if lockedDisplayDuration == nil {
            lockedDisplayDuration = currentDisplayDuration
        }
        draft = edits
    }

    mutating func finish() {
        draft = nil
        lockedDisplayDuration = nil
    }
}
