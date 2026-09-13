import AppKit
import Observation
import SwiftUI

private let timelineContentSpace = "EditorTimelineContent"

@MainActor
@Observable
private final class EditorTimelineScrollOffset {
    var value: CGFloat = 0
}

private struct EditorTimelinePinnedRuler<Content: View>: View {
    struct Configuration {
        let scrollOffset: EditorTimelineScrollOffset
        let viewportWidth: CGFloat
        let content: Content
    }

    let configuration: Configuration

    var body: some View {
        configuration.content
            .offset(x: -configuration.scrollOffset.value)
            .frame(width: configuration.viewportWidth, alignment: .leading)
            .clipped()
    }
}

struct EditorTimelineTrackDuration {
    struct Request {
        let rawDuration: Double?
        let playbackDuration: Double
    }

    static func resolve(_ request: Request) -> Double {
        let playbackDuration = request.playbackDuration.isFinite
            ? max(0, request.playbackDuration)
            : 0
        guard let rawDuration = request.rawDuration, rawDuration.isFinite else {
            return playbackDuration
        }
        return min(max(0, rawDuration), playbackDuration)
    }
}

@MainActor
struct EditorTimelineView: View {
    let project: RecordingProject?
    let assets: [EditorAsset]
    let library: EditorMediaLibrary
    let draftScene: RecordingScene?
    let draftSceneEventIndex: Int?
    let duration: Double
    let playbackTime: Double
    let liveTime: () -> Double
    let isPlaying: Bool
    let playbackRate: EditorPlaybackRate
    @Binding var playbackVolume: Double
    let hasPlaybackAudio: Bool
    let onTogglePlaybackMute: () -> Void
    @Binding var selection: EditorSelection?
    let onSeek: (Double) -> Void
    let onSeekEnded: () -> Void
    let onPrevious: () -> Void
    let onTogglePlayback: () -> Void
    let onNext: () -> Void
    let onPlaybackRateChange: (EditorPlaybackRate) -> Void
    let isInteractive: Bool
    let hiddenAssetIDs: Set<String>
    let mutedAssetIDs: Set<String>
    let toggleableAssetIDs: Set<String>
    let onToggleTrack: (EditorAsset) -> Void
    let onSplit: () -> Void
    let onDeleteSegment: () -> Void
    let canDeleteSegment: Bool
    let onJoinSegment: () -> Void
    let onCutRange: () -> Void
    let onRestoreRange: () -> Void
    let onMarkIn: () -> Void
    let onMarkOut: () -> Void
    @Binding var zoomLevel: Double
    @Binding var showsShortcuts: Bool
    let silence: SilenceEditingSession
    let isEditingSilence: Bool
    let onOpenSilence: () -> Void
    let onChangePlacedItem: (EditorPlacedItemEditing.Change) -> Void
    let onRemovePlacedItem: (EditorPlacedItem.ID) -> Void

    @State private var projection = EditorTimelineProjection(.init(duration: 0, cuts: []))
    @State private var scrollOffset: CGFloat = 0
    @State private var trackScrollWidth: CGFloat = 0
    @State private var rulerScrollOffset = EditorTimelineScrollOffset()
    @State private var scrollPosition = ScrollPosition(x: 0)
    @State private var silenceSegments: [SilenceTimelineSegment] = []
    @State private var selectableSilenceSegments: [SilenceTimelineSegment] = []
    @State private var hoveredSilenceRange: EditorTimeRange?
    @State private var selectionFocusTime: Double?
    @State private var stripDragSelection: SilenceSegmentSelection?
    @State private var isDraggingStrip = false
    @State private var addsDraggedSegments = false

    private let gutterWidth: CGFloat = 210
    private let rulerHeight: CGFloat = 30
    private let chaptersRowHeight: CGFloat = 32
    private let segmentsRowHeight: CGFloat = 38
    private let videoRowHeight: CGFloat = 54
    private let audioRowHeight: CGFloat = 44
    private let silenceRowHeight: CGFloat = 38
    private let placedRowHeight: CGFloat = 38

    private var placedTracks: [EditorPlacedTrack] {
        var tracks = EditorPlacedTrack.resolve(project?.edits ?? .empty)
        if let project, let music = EditorPlacedTrack.music(.init(projectID: project.id,
            path: project.editorState.backgroundMusicPath, duration: duration)) { tracks.append(music) }
        return tracks
    }
    private var selectedPlacedItem: EditorPlacedItem.ID? {
        if case .placed(let id) = selection { return id }
        return nil
    }
    private var canSplitSelection: Bool {
        guard let id = selectedPlacedItem else { return true }
        guard let item = placedTracks.flatMap(\.items).first(where: { $0.id == id }) else { return false }
        return item.canChangeTiming && !item.isPoint
            && playbackTime > item.timing.start + 0.05 && playbackTime < item.timing.end - 0.05
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let selected = silenceControlSelection {
                silenceToolbar(selected)
            } else if let range = selection?.timeRange {
                rangeToolbar(range)
            } else if silence.canClassify {
                silenceToolbar(nil)
            }
            Rectangle()
                .fill(BlitzUI.separator)
                .frame(height: 1)
            GeometryReader { proxy in
                timelineBody(viewportWidth: proxy.size.width)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .background(BlitzUI.projectLibraryBackground)
        .onChange(of: EditorTimelineProjection.Request(duration: duration, cuts: project?.edits.cuts ?? []), initial: true) {
            projection = EditorTimelineProjection(.init(duration: duration, cuts: project?.edits.cuts ?? []))
        }
        .onChange(of: SilenceTimelineSegments.Request(duration: duration, cuts: silence.cuts), initial: true) {
            silenceSegments = SilenceTimelineSegments.resolve(.init(duration: duration, cuts: silence.cuts))
            hoveredSilenceRange = nil
        }
        .onChange(of: SilenceTimelineSegments.SelectableRequest(segments: silenceSegments, projection: projection), initial: true) {
            selectableSilenceSegments = SilenceTimelineSegments.selectable(
                .init(segments: silenceSegments, projection: projection))
        }
    }

    private var header: some View {
        HStack(spacing: 20) {
            HStack(spacing: 2) {
                TimelineActionButton(
                    title: "Split", systemName: "scissors",
                    isDisabled: !isInteractive || !canSplitSelection, action: onSplit
                )
                .help(selectedPlacedItem == nil ? "Split all tracks together at the playhead (⌘B)"
                      : "Split the selected item at the playhead (⌘B)")
                TimelineActionButton(
                    title: "Range", systemName: "rectangle.dashed",
                    isDisabled: !isInteractive, action: onMarkIn
                )
                .help("Mark a range from the playhead (I). Drag a track to select a range.")
                if let selected = silenceControlSelection {
                    TimelineActionButton(
                        title: "Switch", systemName: "arrow.triangle.2.circlepath",
                        isDisabled: !isInteractive || !silence.canClassify
                    ) {
                        silence.toggleRanges(selected.ranges)
                        selection = .silenceRanges(selected)
                    }
                    .help("Switch selected sections between silence and sound (Delete)")
                } else {
                    TimelineActionButton(
                        title: "Delete", systemName: "trash",
                        isDisabled: !isInteractive || (!canDeleteSegment && selectedPlacedItem == nil)
                    ) {
                        if let id = selectedPlacedItem { onRemovePlacedItem(id) }
                        else { onDeleteSegment() }
                    }
                    .help(selectedPlacedItem == nil
                          ? "Delete this segment from all tracks and close the gap (Delete). Undo with ⌘Z."
                          : "Remove the selected item. Undo with ⌘Z.")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            EditorPlaybackControls(configuration: .init(
                time: projection.displayTime(playbackTime),
                duration: projection.duration,
                isPlaying: isPlaying,
                isEnabled: isInteractive,
                rate: playbackRate,
                onSeek: {
                    onSeek(projection.takeTime($0))
                    onSeekEnded()
                },
                onTogglePlayback: onTogglePlayback,
                onPreviousScene: onPrevious,
                onNextScene: onNext,
                onRateChange: onPlaybackRateChange
            ))
            .fixedSize()

            HStack(spacing: 10) {
                BlitzPlaybackVolumeControl(configuration: .init(
                    volume: $playbackVolume,
                    sliderWidth: 110,
                    onToggleMute: onTogglePlaybackMute
                ))
                .disabled(!isInteractive || !hasPlaybackAudio)
                Rectangle().fill(BlitzUI.separator).frame(width: 1, height: 24)
                    .padding(.horizontal, 4)
                BlitzSymbol(configuration: .init(name: "plus.magnifyingglass", size: 14))
                    .foregroundStyle(BlitzUI.secondaryText)
                Slider(
                    value: logarithmicZoom,
                    in: log2(EditorTimelineZoom.minimum)...log2(EditorTimelineZoom.maximum(for: projection.duration))
                )
                    .controlSize(.small)
                    .tint(BlitzUI.mint)
                    .frame(width: 150)
                    .accessibilityLabel("Timeline zoom")
                    .accessibilityValue(String(format: "%.2f×", zoomLevel))
                    .help("Timeline zoom (− / +). Fit with F.")
                TimelineActionButton(
                    title: "Fit", systemName: "arrow.left.and.right", isDisabled: zoomLevel == 1
                ) { zoomLevel = 1 }
                .help("Fit the full recording in the timeline (F)")
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .blitzWorkspaceToolbar()
        .controlSize(.large)
        .contextMenu { timelineContextMenu }
        .popover(isPresented: $showsShortcuts, arrowEdge: .bottom) {
            EditorShortcutHelp()
        }
    }

    private var logarithmicZoom: Binding<Double> {
        Binding(
            get: { EditorTimelineZoom.sliderValue(.init(value: zoomLevel, duration: projection.duration)) },
            set: { zoomLevel = EditorTimelineZoom.scale(.init(value: $0, duration: projection.duration)) }
        )
    }

    private func rangeToolbar(_ range: EditorTimeRange) -> some View {
        HStack(spacing: 12) {
            Label("Range", systemImage: "rectangle.dashed")
                .foregroundStyle(BlitzUI.mint)
            Text("\(rangeTime(projection.displayTime(range.start))) – \(rangeTime(projection.displayTime(range.end)))")
                .monospacedDigit()
                .foregroundStyle(BlitzUI.primaryText)
            Text(String(format: "%.2f s selected", (projection.displayTime(range.end) - projection.displayTime(range.start))))
                .monospacedDigit()
                .foregroundStyle(BlitzUI.secondaryText)
            Spacer(minLength: 4)
            BlitzToolbarButton(configuration: .init(
                title: "Mark in", symbolName: "selection.pin.in.out", showsTitle: true, action: onMarkIn
            ))
            .help("Set range start at the playhead (I)")
            BlitzToolbarButton(configuration: .init(
                title: "Mark out", symbolName: "selection.pin.in.out", showsTitle: true, action: onMarkOut
            ))
            .help("Set range end at the playhead (O)")
            Button(action: onRestoreRange) { Label("Restore range", systemImage: "arrow.uturn.backward") }
                .blitzButton(.secondary)
                .disabled(!isInteractive || !(project?.edits.enabledCuts.contains {
                    $0.start < range.end && $0.end > range.start
                } ?? false))
                .help("Keep removed footage inside this range on all tracks (Shift Delete).")
            Button(action: onCutRange) { Label("Cut range", systemImage: "scissors") }
                .blitzButton(.accent)
                .disabled(!isInteractive || !range.canCut)
                .help("Remove this time range from all tracks in preview and export (Delete). Undo with ⌘Z.")
            BlitzToolbarButton(configuration: .init(
                title: "Clear range", symbolName: "xmark", showsTitle: false, action: { selection = nil }
            ))
            .help("Clear selection (Esc)")
        }
        .font(.system(size: 11, weight: .medium))
        .blitzWorkspaceToolbar()
    }

    private func rangeTime(_ time: Double) -> String {
        let value = time.isFinite ? min(projection.duration, max(0, time)) : 0
        let label = MediaTimecode.label(.init(time: value, duration: projection.duration))
        return label + String(format: ".%02d", Int((value * 100).rounded(.down)) % 100)
    }

    private func silenceToolbar(_ selected: SilenceSegmentSelection?) -> some View {
        HStack(spacing: 12) {
            if let selected {
                silenceSelectionControls(selected)
            } else {
                Text("Click to select · ⌘-click to add · Shift-click or drag to select several")
                    .foregroundStyle(BlitzUI.secondaryText)
                Spacer(minLength: 4)
            }
            SilencePreviewToggle(session: silence)
                .fixedSize()
        }
        .font(.system(size: 11, weight: .medium))
        .blitzWorkspaceToolbar()
    }

    private func silenceSelectionControls(_ selected: SilenceSegmentSelection) -> some View {
        let range = selected.bounds
        let classification = silence.classification(range)
        let previous = SilenceTimelineSegments.neighbor(.init(
            segments: selectableSilenceSegments, selection: range, direction: .previous
        ))
        let next = SilenceTimelineSegments.neighbor(.init(
            segments: selectableSilenceSegments, selection: range, direction: .next
        ))
        return Group {
            HStack(spacing: 0) {
                Button {
                    if let previous {
                        selectSilenceRange(previous.range)
                        selectionFocusTime = (previous.range.start + previous.range.end) / 2
                    }
                } label: { Image(systemName: "chevron.left") }
                .blitzButton(.quiet)
                .disabled(previous == nil)
                .accessibilityLabel("Previous sound or silence segment")
                .help("Select the previous segment, including very short sections.")
                Button {
                    if let next {
                        selectSilenceRange(next.range)
                        selectionFocusTime = (next.range.start + next.range.end) / 2
                    }
                } label: { Image(systemName: "chevron.right") }
                .blitzButton(.quiet)
                .disabled(next == nil)
                .accessibilityLabel("Next sound or silence segment")
                .help("Select the next segment, including very short sections.")
            }
            if selected.ranges.count > 1 {
                Label("\(selected.ranges.count) segments", systemImage: "rectangle.stack")
                    .foregroundStyle(.white)
                Text(String(format: "%.2f s selected", selected.duration))
                    .monospacedDigit()
                    .foregroundStyle(BlitzUI.secondaryText)
            } else {
                Label(
                    classification == .silence ? "Silence · remove" : "Sound · keep",
                    systemImage: classification == .silence ? "waveform.slash" : "waveform"
                )
                .foregroundStyle(classification == .silence ? Color.red : BlitzUI.mint)
                Text("\(rangeTime(projection.displayTime(range.start))) – \(rangeTime(projection.displayTime(range.end)))")
                    .monospacedDigit()
                    .foregroundStyle(BlitzUI.secondaryText)
            }
            Button("Mark as sound", systemImage: "waveform") {
                classifySelectedRanges(.sound)
            }
            .blitzButton(.secondary)
            .help("Keep selected sections and protect them from silence removal. Undo together with ⌘Z.")
            Button("Mark as silence", systemImage: "waveform.slash") {
                classifySelectedRanges(.silence)
            }
            .blitzButton(.secondary)
            .help("Include selected sections in silence removal. Undo together with ⌘Z.")
            Button {
                let start = projection.displayTime(range.start)
                let end = projection.displayTime(range.end)
                selectionFocusTime = (range.start + range.end) / 2
                zoomLevel = EditorTimelineZoom.clamp(.init(
                    value: projection.duration / max(1, (end - start) * 2), duration: projection.duration
                ))
            } label: { Image(systemName: "viewfinder") }
            .blitzButton(.quiet)
            .accessibilityLabel("Zoom to selection")
            .help("Enlarge the selected sections.")
            BlitzToolbarButton(configuration: .init(
                title: "Clear selection", symbolName: "xmark", showsTitle: false, action: { selection = nil }
            ))
            Spacer(minLength: 4)
        }
        .controlSize(.small)
        .disabled(!isInteractive || !silence.canClassify)
    }

    private func classifySelection(_ change: SilenceEditingSession.ClassificationRequest) {
        if selection?.silenceSelection?.ranges.contains(change.range) == true {
            classifySelectedRanges(change.classification)
        } else {
            silence.classify(change)
            selection = .silenceRange(change.range)
        }
    }

    private func classifySelectedRanges(_ classification: SilenceClassification) {
        guard let selected = classificationSelection else { return }
        silence.classifyTogether(selected.ranges.map { .init(range: $0, classification: classification) })
        selection = .silenceRanges(selected)
    }

    private func selectSilenceRange(_ range: EditorTimeRange) {
        selection = .silenceRange(range)
        onSeek(range.start)
        onSeekEnded()
    }

    private func clickSilenceRange(_ range: EditorTimeRange) {
        let modifiers = NSEvent.modifierFlags
        let selected = SilenceSegmentSelection.clicking(.init(
            current: selection?.silenceSelection, target: range, segments: selectableSilenceSegments,
            extending: modifiers.contains(.shift), toggling: modifiers.contains(.command)
        ))
        selection = selected.map(EditorSelection.silenceRanges)
        if !modifiers.contains(.shift), !modifiers.contains(.command) {
            onSeek(range.start)
            onSeekEnded()
        }
    }

    private func toggleSilenceRange(_ range: EditorTimeRange) {
        selection = SilenceSegmentSelection.clicking(.init(
            current: selection?.silenceSelection, target: range, segments: selectableSilenceSegments,
            extending: false, toggling: true
        )).map(EditorSelection.silenceRanges)
    }

    private var classificationSelection: SilenceSegmentSelection? {
        selection?.silenceSelection ?? selection?.timeRange.map(SilenceSegmentSelection.init)
    }

    private var silenceControlSelection: SilenceSegmentSelection? {
        if let selected = selection?.silenceSelection { return selected }
        if isEditingSilence, let range = selection?.timeRange { return SilenceSegmentSelection(range) }
        return nil
    }

    private var selectedSilenceRanges: [EditorTimeRange] {
        selection?.silenceSelection?.ranges ?? []
    }

    private func timelineBody(viewportWidth: CGFloat) -> some View {
        let trackViewport = max(trackScrollWidth > 0 ? trackScrollWidth - 16 : viewportWidth - gutterWidth - 24, 40)
        let pxPerSecond = trackViewport / CGFloat(max(projection.duration, 0.5)) * CGFloat(EditorTimelineZoom.clamp(.init(value: zoomLevel, duration: projection.duration)))
        let contentWidth = max(CGFloat(projection.duration) * pxPerSecond, trackViewport)
        let viewport = EditorTimelineViewport.resolve(.init(
            offset: scrollOffset,
            viewportWidth: trackViewport,
            contentWidth: contentWidth
        ))

        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                gutterHeading
                EditorTimelinePinnedRuler(configuration: .init(
                    scrollOffset: rulerScrollOffset,
                    viewportWidth: trackViewport + 16,
                    content: ZStack(alignment: .topLeading) {
                        ruler(.init(pxPerSecond: pxPerSecond, width: contentWidth, viewport: viewport))
                        if duration > 0 {
                            playhead(.init(pxPerSecond: pxPerSecond, showsHandle: true))
                        }
                    }
                    .frame(width: contentWidth, height: rulerHeight, alignment: .topLeading)
                    .coordinateSpace(name: timelineContentSpace)
                    .padding(.horizontal, 8)
                ))
            }
            .frame(height: rulerHeight)
            .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 8) {
                    gutterColumn

                    ScrollView(.horizontal) {
                        ZStack(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 6) {
                                if duration > 0 {
                                    if showsSilenceTrack {
                                        SilenceSegmentStrip(configuration: .init(
                                            segments: selectableSilenceSegments,
                                            projection: projection, pixelsPerSecond: pxPerSecond, viewport: viewport,
                                            width: contentWidth, height: silenceRowHeight,
                                            selections: selectedSilenceRanges, hoveredRange: hoveredSilenceRange,
                                            onSelect: clickSilenceRange, onToggleSelection: toggleSilenceRange,
                                            onHover: { hoveredSilenceRange = $0 },
                                            onClassify: classifySelection
                                        ))
                                        .disabled(!isInteractive || !silence.canClassify)
                                    }
                                    if showsChaptersTrack {
                                        chaptersTrack(pxPerSecond: pxPerSecond, contentWidth: contentWidth)
                                    }
                                    if showsSegmentsTrack {
                                        segmentsTrack(pxPerSecond: pxPerSecond, contentWidth: contentWidth)
                                    }
                                    ForEach(placedTracks) { track in
                                        placedTrack(.init(track: track, pixelsPerSecond: pxPerSecond,
                                                          contentWidth: contentWidth, viewport: viewport))
                                    }
                                    ForEach(trackAssets) { asset in
                                        assetTrack(.init(asset: asset, pxPerSecond: pxPerSecond, contentWidth: contentWidth, viewport: viewport))
                                    }
                                    if !showsSegmentsTrack && trackAssets.isEmpty {
                                        emptyHint
                                    }
                                }
                            }
                            .contentShape(.rect)
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 5, coordinateSpace: .named(timelineContentSpace))
                                    .onChanged { value in
                                        guard !isPlacedTrack(at: value.startLocation.y),
                                            let range = EditorTimeRange.resolve(.init(
                                                anchor: projection.takeTime(Double(value.startLocation.x / pxPerSecond)),
                                                head: projection.takeTime(Double(value.location.x / pxPerSecond)), duration: duration
                                            ))
                                        else { return }
                                        if showsSilenceTrack, value.startLocation.y < silenceRowHeight {
                                            if !isDraggingStrip {
                                                stripDragSelection = selection?.silenceSelection
                                                addsDraggedSegments = NSEvent.modifierFlags.contains(.command)
                                                isDraggingStrip = true
                                            }
                                            selection = SilenceSegmentSelection.dragging(.init(
                                                current: stripDragSelection,
                                                anchorTime: projection.takeTime(Double(value.startLocation.x / pxPerSecond)),
                                                headTime: projection.takeTime(Double(value.location.x / pxPerSecond)),
                                                segments: selectableSilenceSegments, additive: addsDraggedSegments
                                            )).map(EditorSelection.silenceRanges)
                                        } else {
                                            selection = isEditingSilence || isSilenceTrack(at: value.startLocation.y)
                                                ? .silenceRange(range) : .range(range)
                                        }
                                    }
                                    .onEnded { _ in
                                        isDraggingStrip = false
                                        stripDragSelection = nil
                                    },
                                isEnabled: isInteractive
                            )

                            if duration > 0 {
                                linkedSegmentOverlay(pxPerSecond)
                                if let range = hoveredSilenceRange, !selectedSilenceRanges.contains(range) {
                                    hoverOverlay(.init(range: range, pxPerSecond: pxPerSecond))
                                }
                                if !selectedSilenceRanges.isEmpty {
                                    ForEach(SilenceSegmentSelection.coalesced(selectedSilenceRanges), id: \.start) { range in
                                        rangeOverlay(.init(range: range, pxPerSecond: pxPerSecond))
                                    }
                                } else if let range = selection?.timeRange {
                                    rangeOverlay(.init(range: range, pxPerSecond: pxPerSecond))
                                }
                                playhead(.init(pxPerSecond: pxPerSecond, showsHandle: false))
                            }
                        }
                        .frame(width: contentWidth, alignment: .topLeading)
                        .coordinateSpace(name: timelineContentSpace)
                        .padding(.horizontal, 8)
                    }
                    .scrollPosition($scrollPosition)
                    .onChange(of: [zoomLevel, projection.duration, selectionFocusTime ?? -1]) {
                        let focusTime = selectionFocusTime ?? playbackTime
                        let playheadX = CGFloat(projection.displayTime(focusTime)) * pxPerSecond
                        let offset = min(max(0, contentWidth - trackViewport), max(0, playheadX - trackViewport / 2))
                        scrollPosition.scrollTo(x: offset)
                    }
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        geometry.contentOffset.x
                    } action: { _, offset in
                        rulerScrollOffset.value = offset
                        scrollOffset = floor(max(0, offset - 8) / 128) * 128
                    }
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        geometry.containerSize.width
                    } action: { _, width in
                        trackScrollWidth = width
                    }
                }
                .frame(height: contentHeight)
                .padding(.top, 6)
                .padding(.bottom, 14)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private struct RangeOverlayRequest {
        let range: EditorTimeRange
        let pxPerSecond: CGFloat
    }

    private struct PlacedTrackRequest {
        let track: EditorPlacedTrack
        let pixelsPerSecond: CGFloat
        let contentWidth: CGFloat
        let viewport: EditorTimelineViewport
    }

    private func placedTrack(_ request: PlacedTrackRequest) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.025))
            ForEach(request.track.items.filter { item in
                let start = CGFloat(projection.displayTime(item.timing.start)) * request.pixelsPerSecond
                let end = CGFloat(projection.displayTime(item.timing.end)) * request.pixelsPerSecond
                return end + 16 >= request.viewport.lowerBound && start - 16 <= request.viewport.upperBound
            }) { item in
                EditorPlacedItemClip(configuration: .init(
                    item: item, projection: projection, pixelsPerSecond: request.pixelsPerSecond,
                    height: placedRowHeight, isSelected: selection == .placed(item.id), isInteractive: isInteractive,
                    select: { selection = .placed($0) }, change: onChangePlacedItem, remove: onRemovePlacedItem
                ))
            }
        }
        .frame(width: request.contentWidth, height: placedRowHeight, alignment: .leading)
    }

    private func isPlacedTrack(at y: CGFloat) -> Bool {
        let top = (showsSilenceTrack ? silenceRowHeight + 6 : 0)
            + (showsChaptersTrack ? chaptersRowHeight + 6 : 0)
            + (showsSegmentsTrack ? segmentsRowHeight + 6 : 0)
        return y >= top && y < top + CGFloat(placedTracks.count) * (placedRowHeight + 6)
    }

    private func linkedSegmentOverlay(_ pxPerSecond: CGFloat) -> some View {
        let top = (showsSilenceTrack ? silenceRowHeight + 6 : 0)
            + (showsChaptersTrack ? chaptersRowHeight + 6 : 0)
        let height = max(0, contentHeight - top)
        return Canvas { context, _ in
            if case .segment(let index) = selection,
                let range = EditorTimeRange.segment(.init(
                    eventTimes: sceneEvents.map(\.time), index: index, duration: duration
                )) {
                let start = CGFloat(projection.displayTime(range.start)) * pxPerSecond
                let end = CGFloat(projection.displayTime(range.end)) * pxPerSecond
                let path = Path(CGRect(x: start, y: top, width: max(0, end - start), height: height))
                context.fill(path, with: .color(BlitzUI.mint.opacity(0.08)))
                context.stroke(path, with: .color(BlitzUI.mint), lineWidth: 1.5)
            }
            for event in sceneEvents.dropFirst() {
                let time = projection.displayTime(event.time)
                guard time > 0, time < projection.duration else { continue }
                let x = CGFloat(time) * pxPerSecond
                let gap = Path(CGRect(x: x - 1, y: top, width: 3, height: height))
                context.fill(gap, with: .color(BlitzUI.projectLibraryBackground))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func hoverOverlay(_ request: RangeOverlayRequest) -> some View {
        let start = CGFloat(projection.displayTime(request.range.start)) * request.pxPerSecond
        let end = CGFloat(projection.displayTime(request.range.end)) * request.pxPerSecond
        let top: CGFloat = 0
        return Rectangle()
            .fill(.white.opacity(0.055))
            .overlay { Rectangle().strokeBorder(.white.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }
            .frame(width: max(1, end - start), height: max(0, contentHeight - top))
            .offset(x: start, y: top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func rangeOverlay(_ request: RangeOverlayRequest) -> some View {
        let range = request.range
        let isSilenceSelection = !selectedSilenceRanges.isEmpty
        let outline = isSilenceSelection ? Color.white : BlitzUI.mint
        let top: CGFloat = 0
        let height = max(0, contentHeight - top)
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(outline.opacity(isSilenceSelection ? 0.06 : 0.12))
                .overlay { Rectangle().strokeBorder(.black.opacity(0.65), lineWidth: 4) }
                .overlay { Rectangle().strokeBorder(outline, lineWidth: 2) }
                .frame(width: max(1, CGFloat(projection.displayTime(range.end) - projection.displayTime(range.start)) * request.pxPerSecond), height: height)
                .offset(x: CGFloat(projection.displayTime(range.start)) * request.pxPerSecond, y: top)
                .allowsHitTesting(false)
            ForEach(selectedSilenceRanges.count > 1 ? [] : [true, false], id: \.self) { isStart in
                Capsule()
                    .fill(outline)
                    .frame(width: 8, height: 28)
                    .frame(width: 16, height: 40)
                    .contentShape(.rect)
                    .offset(
                        x: CGFloat(projection.displayTime(isStart ? range.start : range.end)) * request.pxPerSecond - 8,
                        y: top + max(0, (height - 40) / 2)
                    )
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named(timelineContentSpace))
                            .onChanged { value in
                                let time = projection.takeTime(Double(value.location.x / request.pxPerSecond))
                                let anchor = isStart ? min(time, range.end) : range.start
                                let head = isStart ? range.end : max(time, range.start)
                                if let adjusted = EditorTimeRange.resolve(.init(
                                    anchor: anchor, head: head, duration: duration
                                )) {
                                    selection = isSilenceSelection ? .silenceRange(adjusted) : .range(adjusted)
                                }
                            },
                        isEnabled: isInteractive
                    )
                    .accessibilityLabel(isStart ? "Range start" : "Range end")
                    .accessibilityValue(rangeTime(projection.displayTime(isStart ? range.start : range.end)))
                    .help(isStart ? "Drag to adjust range start" : "Drag to adjust range end")
            }
        }
    }

    private var gutterHeading: some View {
        HStack {
            Text("TRACKS")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.28))
            Spacer()
        }
        .padding(.leading, 6)
        .frame(width: gutterWidth, height: rulerHeight)
    }

    private var gutterColumn: some View {
        VStack(spacing: 6) {
            if showsSilenceTrack {
                Button(action: onOpenSilence) {
                    Label("Sound / silence", systemImage: "waveform")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .blitzButton(.quiet)
                .controlSize(.small)
                .frame(width: gutterWidth, height: silenceRowHeight)
                .help("Open silence detection settings")
            }

            ForEach(Array(gutterRows.enumerated()), id: \.offset) { _, row in
                let isSelected = row.item.map { selection == .placed($0) }
                    ?? row.asset.map { selection == .asset($0.id) } ?? false
                HStack(spacing: 9) {
                    Button {
                        if let item = row.item { selection = .placed(item) }
                        else if let asset = row.asset { selection = .asset(asset.id) }
                    } label: {
                        HStack(spacing: 9) {
                            BlitzIconTile(symbolName: row.icon, isSelected: isSelected, size: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(isSelected ? BlitzUI.primaryText : BlitzUI.secondaryText)
                                    .lineLimit(1)
                                if let asset = row.asset, asset.isAudio {
                                    Text(mutedAssetIDs.contains(asset.id) ? "Muted" : "Included")
                                        .font(.system(size: 10))
                                        .foregroundStyle(BlitzUI.secondaryText)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled((row.asset == nil && row.item == nil) || !isInteractive)
                    .accessibilityLabel("Select \(row.title) track")
                    if let asset = row.asset, toggleableAssetIDs.contains(asset.id) {
                        trackToggle(for: asset)
                    } else {
                        Color.clear.frame(width: 32)
                    }
                }
                .padding(.horizontal, 5)
                .frame(width: gutterWidth, height: row.height)
                .background(isSelected ? BlitzUI.quietFill : .clear, in: .rect(cornerRadius: BlitzUI.controlRadius))
            }
        }
        .frame(width: gutterWidth)
    }

    private func trackToggle(for asset: EditorAsset) -> some View {
        let isOff = hiddenAssetIDs.contains(asset.id) || mutedAssetIDs.contains(asset.id)
        let symbol = asset.isVideo
            ? (isOff ? "eye.slash" : "eye")
            : (isOff ? "speaker.slash" : "speaker.wave.2")
        let verb = asset.isVideo ? (isOff ? "Show" : "Hide") : (isOff ? "Unmute" : "Mute")
        return Button {
            onToggleTrack(asset)
        } label: {
            if asset.isVideo {
                Image(systemName: symbol)
            } else {
                Label(verb, systemImage: symbol)
                    .frame(width: 64)
            }
        }
        .blitzButton(asset.isVideo ? .quiet : .secondary)
        .controlSize(.mini)
        .disabled(!isInteractive)
        .accessibilityLabel("\(verb) \(asset.title)")
        .accessibilityValue(isOff ? (asset.isVideo ? "Hidden" : "Muted") : "Included")
        .help("\(verb) \(asset.title) throughout playback and the entire export")
    }

    private var emptyHint: some View {
        Text("No editable tracks in this recording.")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
    }


    private struct RulerRequest {
        let pxPerSecond: CGFloat
        let width: CGFloat
        let viewport: EditorTimelineViewport
    }

    private func ruler(_ request: RulerRequest) -> some View {
        Canvas { context, size in
            guard request.pxPerSecond > 0 else { return }
            let interval = EditorTimelineRuler.interval(for: Double(request.pxPerSecond))
            let minor = interval / 5
            let first = max(0, Int(floor(Double(request.viewport.lowerBound / request.pxPerSecond) / minor)))
            let last = Int(ceil(min(projection.duration, Double(request.viewport.upperBound / request.pxPerSecond)) / minor))
            for index in first...max(first, last) {
                let time = Double(index) * minor
                let x = CGFloat(time) * request.pxPerSecond - request.viewport.lowerBound
                let major = index % 5 == 0
                context.fill(
                    Path(CGRect(x: x, y: size.height - (major ? 7 : 3), width: 1, height: major ? 7 : 3)),
                    with: .color(.white.opacity(major ? 0.3 : 0.13))
                )
                if major {
                    let title = EditorTimelineRuler.label(.init(time: time, interval: interval))
                    let label = Text(title)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                    context.draw(label, at: CGPoint(x: x + 5, y: 10), anchor: .leading)
                }
            }
        }
        .frame(width: request.viewport.width, height: rulerHeight)
        .offset(x: request.viewport.lowerBound)
        .frame(width: request.width, height: rulerHeight, alignment: .leading)
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { seek(toContentX: $0.location.x, pxPerSecond: request.pxPerSecond) }
                .onEnded { _ in onSeekEnded() },
            isEnabled: isInteractive
        )
        .accessibilityLabel("Time ruler")
        .help("Click or drag to scrub")
        .contextMenu { timelineContextMenu }
    }

    private func chaptersTrack(pxPerSecond: CGFloat, contentWidth: CGFloat) -> some View {
        let chapters = timelineChapters
        return ZStack(alignment: .topLeading) {
            ForEach(chapters.indices, id: \.self) { index in
                let chapter = chapters[index]
                let start = min(max(chapter.time, 0), duration)
                let rawEnd = chapter.endTime
                    ?? (index + 1 < chapters.count ? chapters[index + 1].time : duration)
                let end = min(max(rawEnd, start + 0.1), duration)
                let gap: CGFloat = index + 1 < chapters.count ? 2 : 0
                let visibleStart = projection.displayTime(start)
                let visibleEnd = projection.displayTime(end)
                if visibleEnd > visibleStart {
                    chapterClip(chapter, start: projection.takeTime(visibleStart))
                        .frame(width: max(1, CGFloat(visibleEnd - visibleStart) * pxPerSecond - gap), height: chaptersRowHeight)
                        .clipped()
                        .offset(x: CGFloat(visibleStart) * pxPerSecond)
                }
            }
        }
        .frame(width: contentWidth, height: chaptersRowHeight, alignment: .topLeading)
        .background(
            Rectangle()
                .fill(Color.white.opacity(0.025))
        )
    }

    private func chapterClip(_ chapter: RecordingProject.ChapterSnapshot, start: Double) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(BlitzUI.trackCamera.opacity(0.22))
            .overlay(alignment: .leading) {
                Text(chapter.title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)
                    .padding(.horizontal, 7)
            }
            .contentShape(.rect(cornerRadius: 5))
            .onTapGesture {
                onSeek(start)
                onSeekEnded()
            }
    }


    private func segmentsTrack(pxPerSecond: CGFloat, contentWidth: CGFloat) -> some View {
        let events = sceneEvents
        let activeIndex = activeSegmentIndex

        return ZStack(alignment: .topLeading) {
            ForEach(events.indices, id: \.self) { index in
                let start = min(max(events[index].time, 0), duration)
                let end = index + 1 < events.count
                    ? min(max(events[index + 1].time, start), duration)
                    : duration
                let gap: CGFloat = index + 1 < events.count ? 2 : 0
                let visibleStart = projection.displayTime(start)
                let visibleEnd = projection.displayTime(end)
                if visibleEnd > visibleStart {
                    segmentClip(.init(index: index, start: projection.takeTime(visibleStart), isActive: activeIndex == index))
                        .frame(width: max(1, CGFloat(visibleEnd - visibleStart) * pxPerSecond - gap), height: segmentsRowHeight)
                        .clipped()
                        .offset(x: CGFloat(visibleStart) * pxPerSecond)
                }
            }
        }
        .frame(width: contentWidth, height: segmentsRowHeight, alignment: .topLeading)
        .background(
            Rectangle()
                .fill(Color.white.opacity(0.025))
        )
    }

    private struct SegmentClipRequest {
        let index: Int
        let start: Double
        let isActive: Bool
    }

    private func segmentClip(_ request: SegmentClipRequest) -> some View {
        let index = request.index
        let savedScene = RecordingScene(snapshot: sceneEvents[index].scene)
            ?? RecordingScene(settings: RecordingSettings())
        let scene = EditorSceneTimelineSceneResolver.scene(request: .init(
            savedScene: savedScene,
            eventIndex: index,
            draftScene: draftScene,
            draftEventIndex: draftSceneEventIndex
        ))
        let isSelected = selection == .segment(index)
        return EditorSceneTimelineItem(
            scene: scene,
            canvasAspectRatio: captureLayout.aspectRatio,
            isSelected: isSelected,
            isActive: request.isActive
        )
        .contentShape(.rect(cornerRadius: BlitzUI.controlRadius))
        .pointingHandCursor()
        .onTapGesture {
            selection = .segment(index)
            onSeek(min(duration, request.start + 0.001))
            onSeekEnded()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Segment \(index + 1)")
        .accessibilityValue(isSelected ? "Selected, all tracks" : "All tracks")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            selection = .segment(index)
            onSeek(min(duration, request.start + 0.001))
            onSeekEnded()
        }
        .help("Select this segment across all tracks. Press Delete to remove it and close the gap.")
        .contextMenu {
            Button("Delete segment from all tracks", systemImage: "trash") {
                selection = .segment(index)
                onDeleteSegment()
            }
            .disabled(!isInteractive)
            Button("Select segment range", systemImage: "rectangle.dashed") {
                let end = index + 1 < sceneEvents.count ? sceneEvents[index + 1].time : duration
                if let range = EditorTimeRange.resolve(.init(
                    anchor: request.start, head: end, duration: duration
                )) {
                    selection = .range(range)
                }
            }
            .disabled(!isInteractive)
            Button("Join with previous scene", systemImage: "rectangle.compress.vertical") {
                selection = .segment(index)
                onJoinSegment()
            }
            .disabled(!isInteractive || index == 0)
            Divider()
            timelineContextMenu
        }
    }

    private var activeSegmentIndex: Int? {
        EditorSceneTimelineActiveIndexResolver.index(request: .init(
            eventTimes: sceneEvents.map(\.time),
            playbackTime: playbackTime
        ))
    }

    private var captureLayout: CaptureLayout {
        guard let rawLayout = project?.settings.layout else { return .horizontal }
        return CaptureLayout(rawValue: rawLayout) ?? .horizontal
    }

    private struct AssetTrackRequest {
        let asset: EditorAsset
        let pxPerSecond: CGFloat
        let contentWidth: CGFloat
        let viewport: EditorTimelineViewport
    }

    private func assetTrack(_ request: AssetTrackRequest) -> some View {
        let asset = request.asset
        let rowHeight = asset.isVideo ? videoRowHeight : audioRowHeight
        let sourceDuration = library.durations[asset.id] ?? duration
        let sourceOffset = asset.kind == .output ? 0
            : (project?.sourceOffset(forRole: asset.kind.rawValue) ?? 0) - (project?.timelineTrimOffsetSeconds ?? 0)
        let width = max(1, CGFloat(projection.duration) * request.pxPerSecond)
        let frames = library.filmstrips[asset.id] ?? []
        let requestedFrameCount = EditorTimelineFilmstripCells.loadingCount(for: width)
        let filmstripTaskID = EditorFilmstripTaskID(
            assetID: asset.id,
            requestedFrameCount: requestedFrameCount
        )
        let isSelected = selection == .asset(asset.id)
        let isOff = hiddenAssetIDs.contains(asset.id) || mutedAssetIDs.contains(asset.id)
        let shape = RoundedRectangle(cornerRadius: BlitzUI.controlRadius, style: .continuous)
        let viewport = EditorTimelineViewport(
            lowerBound: min(width, request.viewport.lowerBound),
            upperBound: min(width, request.viewport.upperBound)
        )
        let showsSilence = !asset.isVideo && silence.audioSourcePaths.contains(asset.url.path)
        let silenceRuns = showsSilence ? SilenceTimelineBands.overlayRuns(
            .init(
                cuts: silence.cuts, projection: projection, pixelsPerSecond: request.pxPerSecond, viewport: viewport
            ),
            selections: selectedSilenceRanges
        ) : []

        return ZStack(alignment: .leading) {
            shape.fill(asset.tint.opacity(asset.isVideo ? 0.1 : 0.12))
            EditorTimelineMediaCanvas(
                frames: frames,
                waveform: library.timelineWaveforms[asset.id],
                isVideo: asset.isVideo,
                tint: asset.tint,
                projection: projection,
                sourceDuration: sourceDuration,
                sourceOffset: sourceOffset,
                pixelsPerSecond: request.pxPerSecond,
                viewport: viewport
            )
            .equatable()
            .padding(.vertical, asset.isVideo ? 3 : 0)
            if showsSilence {
                SilenceWaveformOverlay(runs: silenceRuns, viewport: viewport)
                    .equatable()
            }
        }
        .frame(width: width, height: rowHeight)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(isSelected ? BlitzUI.mint : asset.tint.opacity(0.28), lineWidth: isSelected ? 2 : 1)
                .allowsHitTesting(false)
        }
        .contentShape(shape)
        .pointingHandCursor()
        .gesture(SpatialTapGesture().onEnded { event in
            if isInteractive, showsSilence, silence.canClassify,
                let segment = SilenceTimelineSegments.at(.init(
                    segments: selectableSilenceSegments,
                    time: projection.takeTime(Double(event.location.x / request.pxPerSecond))
                )) {
                clickSilenceRange(segment.range)
            } else if isInteractive,
                let index = EditorSceneTimelineActiveIndexResolver.index(request: .init(
                    eventTimes: sceneEvents.map(\.time),
                    playbackTime: projection.takeTime(Double(event.location.x / request.pxPerSecond))
                )) {
                selection = .segment(index)
            } else {
                selection = .asset(asset.id)
            }
        })
        .onContinuousHover { phase in
            guard showsSilence, isInteractive else { return }
            switch phase {
            case .active(let location):
                hoveredSilenceRange = SilenceTimelineSegments.at(.init(
                    segments: selectableSilenceSegments,
                    time: projection.takeTime(Double(location.x / request.pxPerSecond))
                ))?.range
            case .ended:
                hoveredSilenceRange = nil
            }
        }
        .opacity(isOff ? 0.3 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { selection = .asset(asset.id) }
        .accessibilityLabel("\(asset.title) track")
        .accessibilityValue(isOff ? (asset.isVideo ? "Hidden" : "Muted in playback and export")
            : showsSilence && !selectedSilenceRanges.isEmpty ? "Sound or silence section selected"
            : isSelected ? "Selected" : "Enabled")
        .help(showsSilence
            ? "Click to select. ⌘-click to add or remove. Shift-click to extend. Drag to select a time range."
            : "Click to select a segment across all tracks. Drag to select a range. Select the track name for source controls.")
        .contextMenu {
            Button("Select \(asset.title)", systemImage: asset.systemImage) {
                selection = .asset(asset.id)
            }
            if case .segment = selection {
                Button("Delete segment from all tracks", systemImage: "trash", action: onDeleteSegment)
                    .disabled(!isInteractive || !canDeleteSegment)
            }
            if toggleableAssetIDs.contains(asset.id) {
                Button(
                    asset.isVideo ? (isOff ? "Show \(asset.title)" : "Hide \(asset.title)")
                        : (isOff ? "Unmute \(asset.title)" : "Mute \(asset.title)"),
                    systemImage: asset.isVideo ? (isOff ? "eye" : "eye.slash")
                        : (isOff ? "speaker.wave.2" : "speaker.slash")
                ) { onToggleTrack(asset) }
                .disabled(!isInteractive)
            }
            Divider()
            timelineContextMenu
        }
        .frame(width: request.contentWidth, height: rowHeight, alignment: .leading)
        .blitzCard(cornerRadius: BlitzUI.controlRadius)
        .task(id: filmstripTaskID) {
            guard asset.isVideo, frames.count < requestedFrameCount else { return }
            if !frames.isEmpty {
                do {
                    try await Task.sleep(for: .milliseconds(180))
                } catch { return }
            }
            guard !Task.isCancelled else { return }
            await library.loadFilmstrip(request: EditorFilmstripLoadRequest(
                assetID: asset.id,
                url: asset.url,
                frameCount: requestedFrameCount
            ))
        }
    }

    private struct EditorFilmstripTaskID: Hashable {
        let assetID: String
        let requestedFrameCount: Int
    }

    @ViewBuilder
    private var timelineContextMenu: some View {
        if classificationSelection != nil {
            Button("Mark as sound", systemImage: "waveform") {
                classifySelectedRanges(.sound)
            }
            .disabled(!isInteractive || !silence.canClassify)
            Button("Mark as silence", systemImage: "waveform.slash") {
                classifySelectedRanges(.silence)
            }
            .disabled(!isInteractive || !silence.canClassify)
            Divider()
        }
        if case .range(let range) = selection {
            Button("Cut selected range", systemImage: "scissors", action: onCutRange)
                .disabled(!isInteractive || !range.canCut)
            Button("Restore selected range", systemImage: "arrow.uturn.backward", action: onRestoreRange)
                .disabled(!isInteractive || !(project?.edits.enabledCuts.contains {
                    $0.start < range.end && $0.end > range.start
                } ?? false))
            Button("Clear selection", systemImage: "xmark") { selection = nil }
            Divider()
        }
        Button("Mark range in at playhead", systemImage: "selection.pin.in.out", action: onMarkIn)
            .disabled(!isInteractive)
        Button("Mark range out at playhead", systemImage: "selection.pin.in.out", action: onMarkOut)
            .disabled(!isInteractive)
        Button("Split all tracks at playhead", systemImage: "scissors", action: onSplit)
            .disabled(!isInteractive)
        Divider()
        Button("Silence settings", systemImage: "waveform", action: onOpenSilence)
        Button("Fit recording", systemImage: "arrow.left.and.right") { zoomLevel = 1 }
        Button("Keyboard shortcuts", systemImage: "keyboard") { showsShortcuts = true }
    }

    private struct PlayheadRequest {
        let pxPerSecond: CGFloat
        let showsHandle: Bool
    }

    private func playhead(_ request: PlayheadRequest) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isPlaying)) { _ in
            let time = isPlaying ? liveTime() : playbackTime
            let x = CGFloat(projection.displayTime(time)) * request.pxPerSecond

            ZStack(alignment: .top) {
                Rectangle()
                    .fill(BlitzUI.mint)
                    .frame(width: 1.5)
                    .frame(maxHeight: .infinity)

                if request.showsHandle {
                    PlayheadHandle()
                        .fill(BlitzUI.mint)
                        .frame(width: 11, height: 14)
                        .overlay {
                            PlayheadHandle()
                                .stroke(Color.black.opacity(0.7), lineWidth: 1)
                        }

                    Color.clear
                        .frame(width: 28, height: rulerHeight)
                        .contentShape(.rect)
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named(timelineContentSpace))
                                .onChanged { seek(toContentX: $0.location.x, pxPerSecond: request.pxPerSecond) }
                                .onEnded { _ in onSeekEnded() },
                            isEnabled: isInteractive
                        )
                }
            }
            .frame(width: 28)
            .frame(maxHeight: .infinity, alignment: .top)
            .offset(x: x - 14)
            .opacity(isInteractive ? 1 : 0.4)
            .allowsHitTesting(request.showsHandle)
        }
    }


    private var sceneEvents: [RecordingProject.SceneEventSnapshot] {
        project?.sceneEvents ?? []
    }

    private var timelineChapters: [RecordingProject.ChapterSnapshot] {
        (project?.chapters ?? []).sorted { lhs, rhs in
            if lhs.time == rhs.time {
                return lhs.title < rhs.title
            }
            return lhs.time < rhs.time
        }
    }

    private var outputAsset: EditorAsset? {
        assets.first { $0.kind == .output && $0.exists && $0.isVideo }
    }

    private var showsChaptersTrack: Bool {
        !timelineChapters.isEmpty
    }

    private var showsSegmentsTrack: Bool {
        !sceneEvents.isEmpty
    }

    private var showsSilenceTrack: Bool {
        !silence.windows.isEmpty
    }

    private var trackAssets: [EditorAsset] {
        var rows = assets.filter { $0.exists && $0.isPlayable && $0.kind != .output }
        if let output = outputAsset, sceneEvents.isEmpty {
            rows.insert(output, at: 0)
        }
        return rows
    }

    private var gutterRows: [(icon: String, title: String, height: CGFloat, asset: EditorAsset?, item: EditorPlacedItem.ID?)] {
        guard duration > 0 else { return [] }
        var rows: [(icon: String, title: String, height: CGFloat, asset: EditorAsset?, item: EditorPlacedItem.ID?)] = []
        if showsChaptersTrack {
            rows.append((icon: "text.quote", title: "Chapters", height: chaptersRowHeight, asset: nil, item: nil))
        }
        if showsSegmentsTrack {
            rows.append((icon: BlitzSymbols.scenes, title: "Segments", height: segmentsRowHeight, asset: nil, item: nil))
        }
        for track in placedTracks {
            rows.append((icon: track.symbol, title: track.title, height: placedRowHeight, asset: nil,
                         item: track.items.first?.id))
        }
        for asset in trackAssets {
            rows.append((
                icon: asset.systemImage,
                title: asset.title,
                height: asset.isVideo ? videoRowHeight : audioRowHeight,
                asset: asset,
                item: nil
            ))
        }
        return rows
    }

    private var contentHeight: CGFloat {
        var height: CGFloat = 0
        if duration > 0 {
            if showsSilenceTrack {
                height += 6 + silenceRowHeight
            }
            if showsChaptersTrack {
                height += 6 + chaptersRowHeight
            }
            if showsSegmentsTrack {
                height += 6 + segmentsRowHeight
            }
            height += CGFloat(placedTracks.count) * (placedRowHeight + 6)
            for asset in trackAssets {
                height += 6 + (asset.isVideo ? videoRowHeight : audioRowHeight)
            }
            if !showsSegmentsTrack && trackAssets.isEmpty {
                height += 6 + 56
            }
        }
        return max(0, height - 6)
    }

    private func isSilenceTrack(at y: CGFloat) -> Bool {
        var top: CGFloat = 0
        if showsSilenceTrack {
            if y >= top, y < top + silenceRowHeight { return true }
            top += silenceRowHeight + 6
        }
        for row in gutterRows {
            if y >= top, y < top + row.height, let asset = row.asset {
                return !asset.isVideo && silence.audioSourcePaths.contains(asset.url.path)
            }
            top += row.height + 6
        }
        return false
    }


    private func seek(toContentX x: CGFloat, pxPerSecond: CGFloat) {
        guard duration > 0, pxPerSecond > 0 else { return }
        onSeek(projection.takeTime(min(max(0, Double(x / pxPerSecond)), projection.duration)))
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct EditorSceneTimelineItem: View {
    let scene: RecordingScene
    let canvasAspectRatio: CGFloat
    let isSelected: Bool
    let isActive: Bool

    private let shape = RoundedRectangle(cornerRadius: BlitzUI.controlRadius, style: .continuous)

    var body: some View {
        GeometryReader { proxy in
            let presentation = EditorSceneTimelineItemPresentation.make(scene: scene)
            HStack(spacing: 6) {
                EditorSceneTimelineThumbnail(scene: scene, canvasAspectRatio: canvasAspectRatio)
                    .frame(width: thumbnailWidth(for: proxy.size.width), height: 26)

                if proxy.size.width >= 86 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(presentation.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(BlitzUI.primaryText)
                            .lineLimit(1)

                        if let detail = presentation.detail {
                            Text(detail)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(BlitzUI.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
        }
        .background(isActive ? BlitzUI.trackCamera.opacity(0.12) : BlitzUI.cardFill, in: shape)
        .overlay {
            shape.strokeBorder(
                isSelected ? BlitzUI.mint : (isActive ? BlitzUI.panelStroke : BlitzUI.separator),
                lineWidth: isSelected ? 2 : 1
            )
            .allowsHitTesting(false)
        }
        .overlay(alignment: .leading) {
            if isActive {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(BlitzUI.mint)
                    .frame(width: 3)
                    .padding(.vertical, 5)
                    .padding(.leading, 2)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(EditorSceneTimelineItemPresentation.make(scene: scene).title)
    }

    private func thumbnailWidth(for itemWidth: CGFloat) -> CGFloat {
        if itemWidth >= 86 {
            return min(52, max(24, itemWidth * 0.36))
        }
        return max(6, itemWidth - 8)
    }
}

private struct EditorSceneTimelineThumbnail: View {
    let scene: RecordingScene
    let canvasAspectRatio: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let canvas = fittedCanvas(in: proxy.size)
            let geometry = SceneRenderGeometry(canvas: canvas, scene: scene, origin: .upperLeft)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color(cgColor: scene.canvasBackgroundStyle.appearance.solidCGColor))
                    .frame(width: canvas.width, height: canvas.height)
                    .offset(x: canvas.minX, y: canvas.minY)

                ForEach(geometry.activePlacements, id: \.kind) { placement in
                    sourceLayer(placement)
                }

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    .frame(width: canvas.width, height: canvas.height)
                    .offset(x: canvas.minX, y: canvas.minY)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        }
    }

    private func sourceLayer(_ placement: SceneRenderLayerPlacement) -> some View {
        let shape = RoundedRectangle(cornerRadius: placement.cornerRadius, style: .continuous)
        let isScreen = placement.kind == .screen
        let shadowEnabled = isScreen ? scene.screenShadowEnabled : scene.cameraShadowEnabled
        return BlitzSceneThumbnailLayer(kind: placement.kind)
            .clipShape(shape)
            .shadow(color: shadowEnabled ? .black.opacity(0.55) : .clear, radius: 1.5, y: 1)
            .frame(width: placement.targetRect.width, height: placement.targetRect.height)
            .offset(x: placement.targetRect.minX, y: placement.targetRect.minY)
    }

    private func fittedCanvas(in size: CGSize) -> CGRect {
        let available = CGSize(width: max(1, size.width), height: max(1, size.height))
        let ratio = max(0.01, canvasAspectRatio)
        let availableRatio = available.width / available.height
        let canvasSize: CGSize
        if availableRatio > ratio {
            canvasSize = CGSize(width: available.height * ratio, height: available.height)
        } else {
            canvasSize = CGSize(width: available.width, height: available.width / ratio)
        }
        return CGRect(
            x: (available.width - canvasSize.width) / 2,
            y: (available.height - canvasSize.height) / 2,
            width: canvasSize.width,
            height: canvasSize.height
        )
    }
}

private struct TimelineActionButton: View {
    let title: String
    let systemName: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        BlitzToolbarButton(configuration: .init(
            title: title,
            symbolName: systemName,
            showsTitle: true,
            action: action
        ))
        .disabled(isDisabled)
    }
}

enum EditorSceneTitle {
    static func title(for snapshot: RecordingProject.SceneSnapshot) -> String {
        let layerOrder = snapshot.sceneLayout.layerOrder.compactMap(SceneLayerKind.init(rawValue:))
        let sourceOpacities = Dictionary(uniqueKeysWithValues: snapshot.sourceOpacities.compactMap { key, value in
            CaptureSource(rawValue: key).map { ($0, CGFloat(value)) }
        })
        let scene = RecordingScene(
            enabledSources: Set(snapshot.enabledSources.compactMap(CaptureSource.init(rawValue:))),
            sceneLayout: SceneLayout(
                screenFrame: CGRect(
                    x: snapshot.sceneLayout.screenFrame.x,
                    y: snapshot.sceneLayout.screenFrame.y,
                    width: snapshot.sceneLayout.screenFrame.width,
                    height: snapshot.sceneLayout.screenFrame.height
                ),
                cameraFrame: CGRect(
                    x: snapshot.sceneLayout.cameraFrame.x,
                    y: snapshot.sceneLayout.cameraFrame.y,
                    width: snapshot.sceneLayout.cameraFrame.width,
                    height: snapshot.sceneLayout.cameraFrame.height
                ),
                layerOrder: layerOrder.isEmpty ? [.screen, .camera] : layerOrder
            ),
            screenCropAmount: snapshot.screenCropAmount.map {
                CGPoint(x: CGFloat($0.x), y: CGFloat($0.y))
            } ?? .zero,
            screenCropPosition: snapshot.screenCropPosition.map {
                CGPoint(x: CGFloat($0.x), y: CGFloat($0.y))
            } ?? .zero,
            screenContentMode: snapshot.screenContentMode.flatMap(CameraContentMode.init(rawValue:)) ?? .fill,
            cameraContentMode: CameraContentMode(rawValue: snapshot.cameraContentMode) ?? .fill,
            sourceOpacities: sourceOpacities
        )
        return title(for: scene)
    }

    static func title(for scene: RecordingScene) -> String {
        let canvas = CGRect(x: 0, y: 0, width: 1, height: 1)
        let geometry = SceneRenderGeometry(canvas: canvas, scene: scene, origin: .upperLeft)
        let activeKinds = geometry.activeLayerOrder.filter { scene.renderedSources.contains($0.source) }
        if let topKind = activeKinds.last,
           geometry.isFullCanvasFrame(for: topKind) {
            return title(hasScreen: topKind == .screen, hasCamera: topKind == .camera)
        }
        return title(
            hasScreen: activeKinds.contains(.screen),
            hasCamera: activeKinds.contains(.camera)
        )
    }

    private static func title(hasScreen: Bool, hasCamera: Bool) -> String {
        switch (hasScreen, hasCamera) {
        case (true, true): return "Screen + Camera"
        case (true, false): return "Screen"
        case (false, true): return "Camera"
        case (false, false): return "Scene"
        }
    }
}

private struct PlayheadHandle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius: CGFloat = 2.5
        let tipTop = rect.maxY - rect.height * 0.38
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: tipTop))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: tipTop))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}
