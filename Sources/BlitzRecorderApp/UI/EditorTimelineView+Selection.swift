import SwiftUI

extension EditorTimelineView {
    func classifySelectedRanges(_ classification: SilenceClassification) {
        guard let selected = selection?.rangeSelection else { return }
        silence.classifyTogether(selected.ranges.map { .init(range: $0, classification: classification) })
        selection = .silenceRanges(selected)
    }

    private struct ClickTarget {
        let click: EditorTimelineRangeClick
        let ranges: [EditorTimeRange]
    }

    private var currentRangeSelection: SilenceSegmentSelection? {
        selection?.rangeSelection ?? selectedSceneRange.map(SilenceSegmentSelection.init)
    }

    private func selectItem(_ request: ClickTarget) {
        let modifiers = request.click.modifiers
        selection = SilenceSegmentSelection.clickingItems(.init(
            current: currentRangeSelection, target: request.click.range, ranges: request.ranges,
            extending: modifiers.contains(.shift), toggling: modifiers.contains(.command)
        )).map(EditorSelection.ranges)
    }

    func clickTimelineRange(_ click: EditorTimelineRangeClick) {
        let range: EditorTimeRange
        if click.modifiers.contains(.shift), let current = currentRangeSelection {
            range = .init(start: min(current.anchor.start, click.range.start), end: max(current.anchor.end, click.range.end))
        } else {
            range = click.range
        }
        selectItem(.init(click: click, ranges: [range]))
    }

    func clickVideoClip(_ click: EditorTimelineRangeClick) {
        selectItem(.init(click: click, ranges: clipLayout.clips.map(\.range)))
    }

    func segmentRange(at index: Int) -> EditorTimeRange? {
        EditorTimeRange.segment(.init(eventTimes: sceneEvents.map(\.time), index: index, duration: duration))
    }

    var selectedSceneRange: EditorTimeRange? {
        guard case .segment(let index) = selection else { return nil }
        return segmentRange(at: index)
    }

    func clickTranscriptRange(_ click: EditorTimelineRangeClick) {
        selectItem(.init(click: click, ranges: transcriptLayout.items.map { $0.source.range }))
        if click.modifiers.intersection([.shift, .command]).isEmpty {
            seekAndSettle(to: click.range.start)
        }
    }

    func seekAndSettle(to time: Double) {
        onSeek(time)
        onSeekEnded()
    }

    var selectionTint: Color {
        guard let ranges = selection?.rangeSelection?.displayRanges, !ranges.isEmpty else { return BlitzUI.mint }
        let onlySilence = ranges.allSatisfy { range in
            let segments = SilenceTimelineSegments.overlapping(.init(
                segments: silenceSegments, start: range.start, end: range.end,
                includesSegmentStartingAtEnd: false
            ))
            guard let first = segments.first, let last = segments.last,
                first.range.start <= range.start, last.range.end >= range.end else { return false }
            return segments.allSatisfy { $0.classification == .silence }
        }
        return onlySilence ? BlitzUI.recordRed : BlitzUI.mint
    }

    func isPlacedTrack(at y: CGFloat) -> Bool {
        let top = segmentsTrackTop + (showsSegmentsTrack ? segmentsRowHeight + 6 : 0)
        return y >= top && y < top + CGFloat(placedTracks.count) * (placedRowHeight + 6)
    }

    func cancelTimelineDrag() {
        _ = clipTrim.finish()
    }

    func previewClipTrim(_ translationWidth: CGFloat) {
        if let trimmed = clipTrim.applyTrim(translationWidth: translationWidth) {
            selection = .range(trimmed)
        }
    }

    func commitClipTrim() {
        var session = clipTrim
        let edits = session.finish()
        clipTrim = session
        if let edits { onTrimClip(edits) }
    }
}
