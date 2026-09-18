import Foundation

enum EditorVideoCuts {
    typealias Request = EditorClipSpine.BladeRequest
    typealias ExtendRequest = EditorClipSpine.ExtendRequest

    static func splitting(_ request: Request) -> TimelineEdits? {
        EditorClipSpine.splitting(request)
    }

    static func range(_ request: Request) -> EditorTimeRange? {
        EditorClipSpine.range(request)
    }

    static func rightExpandLimit(_ request: ExtendRequest) -> Double? {
        EditorClipSpine.rightExpandLimit(request)
    }

    static func extendingRight(_ request: ExtendRequest) -> TimelineEdits? {
        EditorClipSpine.extendingRight(request)
    }

    static func dragRight(_ request: ExtendRequest) -> EditorClipSpine.DragRightResult {
        EditorClipSpine.dragRight(request)
    }
}
