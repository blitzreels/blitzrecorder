import Foundation

struct EditorTimelineWrite {
    var edits: TimelineEdits
    var actionName: String
    var seek: Double? = nil
    var nextSelection: EditorSelection? = nil
    var clearSelection: Bool = false
    var usesOutputText: Bool = false
    var clearPrivacy: Bool = false

    static func cuttingTogether(
        ranges: [EditorTimeRange],
        edits: TimelineEdits,
        takeDuration: Double
    ) -> Self? {
        guard let next = EditorTimeRange.removingTogether(.init(
            ranges: ranges, kind: .manual, edits: edits, takeDuration: takeDuration
        )), let seek = ranges.map(\.start).min() else { return nil }
        return Self(edits: next, actionName: "Cut Range", seek: seek, clearSelection: true)
    }

    static func restoringTogether(
        ranges: [EditorTimeRange],
        edits: TimelineEdits,
        takeDuration: Double
    ) -> Self? {
        guard let next = EditorTimeRange.restoringTogether(.init(
            ranges: ranges, kind: .manual, edits: edits, takeDuration: takeDuration
        )), let seek = ranges.map(\.start).min() else { return nil }
        return Self(edits: next, actionName: "Restore Range", seek: seek, clearSelection: true)
    }

    static func splittingClip(
        edits: TimelineEdits,
        time: Double,
        duration: Double,
        silenceCuts: [TimelineCut]
    ) -> (write: Self?, selection: EditorSelection?) {
        guard let next = EditorClipSpine.splitting(.init(
            edits: edits, time: time, duration: duration, silenceCuts: silenceCuts
        )) else { return (nil, nil) }
        let selection = EditorClipSpine.range(.init(
            edits: next, time: time, duration: duration, silenceCuts: silenceCuts
        )).map(EditorSelection.range)
        if next == edits {
            return (nil, selection)
        }
        return (Self(edits: next, actionName: "Split Clip", nextSelection: selection), selection)
    }
}
