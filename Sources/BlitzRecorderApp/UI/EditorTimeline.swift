import AppKit
import Observation
import SwiftUI

private let timelineContentSpace = "EditorTimelineContent"

@MainActor
@Observable
private final class EditorTimelineScrollOffset {
    var value: CGFloat = 0
}

@MainActor
@Observable
final class EditorTimelineRulerHover {
    var position: CGFloat?

    struct Update {
        let location: CGPoint?
        let ruler: CGRect
        let isInteractive: Bool
    }

    func update(_ request: Update) {
        let next = request.location.flatMap { location -> CGFloat? in
            guard request.isInteractive, request.ruler.contains(location) else { return nil }
            return location.x - request.ruler.minX
        }
        if position != next { position = next }
    }
}

struct EditorTimelineHoverLine: View {
    let hover: EditorTimelineRulerHover
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let position = hover.position
        Canvas { context, size in
            guard let position, position >= 0, position <= size.width else { return }
            let x = (position * displayScale).rounded() / displayScale
            context.fill(Path(CGRect(x: x, y: 0, width: 1 / displayScale, height: size.height)),
                         with: .color(.white.opacity(0.6)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
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
    let transcript: RecordingTranscript?
    let transcriptionStatus: TranscriptionJobStatus
    let onGenerateTranscript: () -> Void
    let assets: [EditorAsset]
    let library: EditorMediaLibrary
    let draftScene: RecordingScene?
    let draftSceneEventIndex: Int?
    let duration: Double
    let playback: EditorPlaybackController
    @Binding var selection: EditorSelection?
    let onSeek: (Double) -> Void
    let onSeekEnded: () -> Void
    let onTogglePlayback: () -> Void
    let onPlaybackRateChange: (EditorPlaybackRate) -> Void
    let isInteractive: Bool
    let hiddenAssetIDs: Set<String>
    let mutedAssetIDs: Set<String>
    let toggleableAssetIDs: Set<String>
    let onToggleTrack: (EditorAsset) -> Void
    let onSplit: () -> Void
    let onDeleteSelection: () -> Void
    let deleteAction: EditorDeleteRouting.Action?
    let onDeleteSegment: () -> Void
    let canDeleteSegment: Bool
    let onJoinSegment: () -> Void
    let onRestoreRange: () -> Void
    let onTrimClip: (TimelineEdits) -> Void
    let onMarkIn: () -> Void
    let onMarkOut: () -> Void
    @Binding var zoomLevel: Double
    @Binding var showsShortcuts: Bool
    @Binding var showsSourceTracks: Bool
    let silence: SilenceEditingSession
    let onOpenSilence: () -> Void
    let onChangePlacedItem: (EditorPlacedItemEditing.Change) -> Void
    let onRemovePlacedItem: (EditorPlacedItem.ID) -> Void

    @State private var transcriptItems: [EditorTranscriptItem] = []
    @State private var transcriptLayout = EditorTranscriptLayout(.init(items: [], projection: .init(.init(duration: 0, cuts: []))))
    @State private var projection = EditorTimelineProjection(.init(duration: 0, cuts: []))
    @State private var clipLayout = EditorVideoClipLayout(.init(projection: .init(.init(duration: 0, cuts: [])), splits: []))
    @State private var scrollOffset: CGFloat = 0
    @State private var trackScrollWidth: CGFloat = 0
    @State private var rulerScrollOffset = EditorTimelineScrollOffset()
    @State private var rulerHover = EditorTimelineRulerHover()
    @State private var scrollPosition = ScrollPosition(x: 0)
    @State private var silenceSegments: [SilenceTimelineSegment] = []
    @State private var selectableSilenceSegments: [SilenceTimelineSegment] = []
    @State private var hoveredClipRange: EditorTimeRange?
    @State private var hoveredChapterTime: Double?
    @State private var selectionFocusTime: Double?
    @State private var clipTrim = EditorClipTrimSession()
    @State private var zoomFitDuration: Double = 0
    @State private var showsPlaybackVolume = false

    private let gutterWidth: CGFloat = 180
    private let rulerHeight: CGFloat = 30
    private let chaptersRowHeight: CGFloat = 32
    private let segmentsRowHeight: CGFloat = 38
    private let videoRowHeight: CGFloat = 54
    private let audioRowHeight: CGFloat = 44
    private let transcriptRowHeight: CGFloat = 30
    private let clipRowHeight: CGFloat = 64
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
            && playback.currentTime > item.timing.start + 0.05 && playback.currentTime < item.timing.end - 0.05
    }

    private var displayedEdits: TimelineEdits {
        clipTrim.edits(committed: project?.edits ?? .empty)
    }

    var body: some View {
        timelineContent
            .onDisappear { cancelTimelineDrag() }
            .onChange(of: project?.edits) { cancelTimelineDrag() }
            .onChange(of: isInteractive) { if !isInteractive { cancelTimelineDrag() } }
            .onChange(of: showsSourceTracks) {
                cancelTimelineDrag()
                if !showsSourceTracks, case .asset = selection { selection = nil }
            }
    }

    private var timelineContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle()
                .fill(BlitzUI.separator)
                .frame(height: 1)
            GeometryReader { proxy in
                timelineBody(viewportWidth: proxy.size.width)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .frame(maxHeight: .infinity, alignment: .top)
            selectionStatus
        }
        .background(BlitzUI.projectLibraryBackground)
        .onChange(of: projection) { updateTranscriptLayout() }
        .onChange(of: EditorClipSpine.Request(edits: displayedEdits, duration: duration, silenceCuts: silence.cuts), initial: true) {
            clipLayout = EditorClipSpine.layout(.init(
                edits: displayedEdits, duration: duration, silenceCuts: silence.cuts
            ))
        }
        .onChange(of: transcript, initial: true) { updateTranscriptItems() }
        .onChange(of: silence.windows) { updateTranscriptItems() }
        .onChange(of: silence.threshold) { updateTranscriptItems() }
        .onChange(of: duration) {
            zoomFitDuration = 0
            updateTranscriptItems()
        }
        .onChange(of: EditorTimelineProjection.Request(duration: duration, cuts: displayedEdits.cuts), initial: true) {
            projection = EditorTimelineProjection(.init(duration: duration, cuts: displayedEdits.cuts))
        }
        .onChange(of: clipLayout) { updateSilenceSegments() }
        .onChange(of: SilenceTimelineSegments.Request(duration: duration, cuts: silence.cuts), initial: true) {
            updateSilenceSegments()
        }
        .onChange(of: SilenceTimelineSegments.SelectableRequest(segments: silenceSegments, projection: projection), initial: true) {
            selectableSilenceSegments = SilenceTimelineSegments.selectable(
                .init(segments: silenceSegments, projection: projection))
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                editActions
                Spacer(minLength: 0)
                playbackControls
                Spacer(minLength: 0)
                listeningAndZoomControls
            }
            .blitzWorkspaceToolbar()
            VStack(spacing: 0) {
                HStack {
                    editActions
                    Spacer(minLength: 0)
                    listeningAndZoomControls
                }
                .blitzWorkspaceToolbar()
                playbackControls
                    .frame(maxWidth: .infinity)
                    .blitzWorkspaceToolbar()
            }
        }
    }

    private var editActions: some View {
        HStack(spacing: 2) {
            TimelineActionButton(
                title: "Split", systemName: "scissors",
                isDisabled: !isInteractive || !canSplitSelection, action: onSplit
            )
            .help(selectedPlacedItem == nil ? "Split the clip at the playhead. All sources stay linked (⌘B)."
                  : "Split the selected item at the playhead (⌘B).")
            TimelineActionButton(
                title: deleteAction == .toggleAsset ? "Hide / mute" : "Delete", systemName: "trash",
                isDisabled: !isInteractive || deleteAction == nil, action: onDeleteSelection
            )
            .help(deleteAction.map(EditorDeleteRouting.help) ?? "Drag to select a range, then press Return or Delete.")
            BlitzGlassMenu(entries: selectionEntries + [
                .divider,
                .item(.init(title: "Silence settings", systemImage: "waveform", action: onOpenSilence)),
                .item(.init(title: "Keyboard shortcuts", systemImage: "keyboard", action: { showsShortcuts = true }))
            ], menuWidth: 280) {
                Image(systemName: "ellipsis").frame(width: 28, height: 28)
            }
            .accessibilityLabel("Timeline actions")
            .help("Selection, restoration, and keyboard shortcuts")
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var selectionStatus: some View {
        HStack(spacing: 10) {
            if let selected = selection?.rangeSelection {
                Text("\(rangeTime(projection.displayTime(selected.bounds.start))) – \(rangeTime(projection.displayTime(selected.bounds.end)))")
                    .foregroundStyle(BlitzUI.primaryText)
                Text(String(format: "%.2f s selected", selected.displayRanges.reduce(0) {
                    $0 + projection.displayTime($1.end) - projection.displayTime($1.start)
                }))
                Text("Return to delete")
                Button { selection = nil } label: { Image(systemName: "xmark") }
                    .blitzButton(.quiet)
                    .controlSize(.mini)
                    .accessibilityLabel("Clear selection")
                    .help("Clear selection (Esc)")
            } else if case .asset(let id) = selection, let asset = assets.first(where: { $0.id == id }) {
                Text("\(asset.title) selected · Delete to \(asset.isVideo ? "hide" : "mute") the entire track")
            } else if selection != nil {
                Text("Item selected · Return to delete · Esc to clear")
            } else {
                Text("Drag to select · Return to delete · ⌘Z to undo")
            }
            Spacer(minLength: 0)
            Text("\(clipLayout.clips.count) clips")
        }
        .font(.system(size: 11))
        .monospacedDigit()
        .foregroundStyle(BlitzUI.secondaryText)
        .lineLimit(1)
        .padding(.horizontal, 18)
        .frame(height: 30)
        .overlay(alignment: .top) { Rectangle().fill(BlitzUI.separator).frame(height: 1) }
    }

    @ViewBuilder
    private var selectionCommands: some View {
        ForEach(Array(selectionEntries.enumerated()), id: \.offset) { _, entry in
            switch entry {
            case .item(let item):
                Button(item.title, systemImage: item.systemImage ?? "circle", action: item.action)
                    .disabled(!item.isEnabled)
            case .divider: Divider()
            case .section(let title): Text(title)
            }
        }
    }

    private var selectionEntries: [BlitzMenuEntry] {
        var entries: [BlitzMenuEntry] = [
            .item(.init(title: "Mark range start", subtitle: "I", systemImage: "selection.pin.in.out",
                        isEnabled: isInteractive, action: onMarkIn)),
            .item(.init(title: "Mark range end", subtitle: "O", systemImage: "selection.pin.in.out",
                        isEnabled: isInteractive, action: onMarkOut))
        ]
        if let selected = selection?.rangeSelection {
            let canRestore = project?.edits.enabledCuts.contains { cut in
                selected.ranges.contains { $0.start < cut.end && $0.end > cut.start }
            } ?? false
            entries += [
                .divider,
                .item(.init(title: "Zoom to selection", systemImage: "viewfinder", action: {
                    let range = selected.bounds
                    let width = projection.displayTime(range.end) - projection.displayTime(range.start)
                    selectionFocusTime = (range.start + range.end) / 2
                    zoomLevel = EditorTimelineZoom.clamp(.init(
                        value: projection.duration / max(1, width * 2), duration: projection.duration
                    ))
                })),
                .item(.init(title: "Restore footage in selection", subtitle: "Shift Delete",
                            systemImage: "arrow.uturn.backward", isEnabled: isInteractive && canRestore,
                            action: onRestoreRange)),
                .item(.init(title: "Keep as speech", systemImage: "waveform",
                            isEnabled: isInteractive && silence.canClassify,
                            action: { classifySelectedRanges(.sound) })),
                .item(.init(title: "Mark as silence", systemImage: "waveform.slash",
                            isEnabled: isInteractive && silence.canClassify,
                            action: { classifySelectedRanges(.silence) }))
            ]
        }
        entries.append(.item(.init(title: "Clear selection", subtitle: "Esc", systemImage: "xmark",
                                  isEnabled: selection != nil, action: { selection = nil })))
        return entries
    }

    private var playbackControls: some View {
        EditorPlaybackControls(configuration: .init(
            time: projection.displayTime(playback.currentTime),
            liveTime: { [playback, projection] in projection.displayTime(playback.displayTime()) },
            duration: projection.duration,
            isPlaying: playback.isPlaying,
            isEnabled: isInteractive,
            rate: playback.playbackRate,
            onSeek: {
                onSeek(projection.takeTime($0))
                onSeekEnded()
            },
            onTogglePlayback: onTogglePlayback,
            onRateChange: onPlaybackRateChange
        ))
        .fixedSize()
    }

    private var listeningAndZoomControls: some View {
        HStack(spacing: 10) {
            Button { showsPlaybackVolume.toggle() } label: {
                Image(systemName: playback.playbackVolume == 0 ? "speaker.slash" : "speaker.wave.2")
            }
            .blitzButton(.quiet)
            .controlSize(.small)
            .accessibilityLabel("Playback volume")
            .accessibilityValue("\(Int(playback.playbackVolume * 100))%")
            .help("Preview volume. Export audio is unchanged.")
            .disabled(!isInteractive || playback.muteableSources.isEmpty)
            .popover(isPresented: $showsPlaybackVolume) {
                BlitzPlaybackVolumeControl(configuration: .init(
                    volume: Binding(get: { playback.playbackVolume }, set: { playback.setPlaybackVolume($0) }),
                    sliderWidth: 140, onToggleMute: { playback.togglePlaybackMute() }
                ))
                .padding(16)
            }
            BlitzSymbol(configuration: .init(name: "plus.magnifyingglass", size: 14))
                .foregroundStyle(BlitzUI.secondaryText)
            Slider(
                value: logarithmicZoom,
                in: log2(EditorTimelineZoom.minimum)...log2(EditorTimelineZoom.maximum(for: projection.duration))
            )
                .controlSize(.small)
                .tint(BlitzUI.mint)
                .frame(width: 100)
                .accessibilityLabel("Timeline zoom")
                .accessibilityValue(String(format: "%.2f×", zoomLevel))
                .help("Timeline zoom (⌘− / ⌘+). Fit with F.")
            TimelineActionButton(
                title: "Fit", systemName: "arrow.left.and.right", isDisabled: zoomLevel == 1
            ) { zoomLevel = 1 }
            .help("Fit the full recording in the timeline (F)")
        }
        .fixedSize(horizontal: true, vertical: false)

    }

    private var logarithmicZoom: Binding<Double> {
        Binding(
            get: { EditorTimelineZoom.sliderValue(.init(value: zoomLevel, duration: projection.duration)) },
            set: { zoomLevel = EditorTimelineZoom.scale(.init(value: $0, duration: projection.duration)) }
        )
    }

    private func rangeTime(_ time: Double) -> String {
        let value = time.isFinite ? min(projection.duration, max(0, time)) : 0
        let label = MediaTimecode.label(.init(time: value, duration: projection.duration))
        return label + String(format: ".%02d", Int((value * 100).rounded(.down)) % 100)
    }

    private func classifySelectedRanges(_ classification: SilenceClassification) {
        guard let selected = classificationSelection else { return }
        silence.classifyTogether(selected.ranges.map { .init(range: $0, classification: classification) })
        selection = .silenceRanges(selected)
    }

    private func clickTimelineRange(_ click: EditorTimelineRangeClick) {
        let current = selection?.rangeSelection ?? selectedSceneRange.map(SilenceSegmentSelection.init)
        let range: EditorTimeRange
        if click.modifiers.contains(.shift), let current {
            range = .init(start: min(current.anchor.start, click.range.start), end: max(current.anchor.end, click.range.end))
        } else {
            range = click.range
        }
        selection = SilenceSegmentSelection.clickingItems(.init(
            current: current, target: click.range, ranges: [range],
            extending: click.modifiers.contains(.shift), toggling: click.modifiers.contains(.command)
        )).map(EditorSelection.ranges)
    }

    private func clickVideoClip(_ click: EditorTimelineRangeClick) {
        selection = SilenceSegmentSelection.clickingItems(.init(
            current: selection?.rangeSelection ?? selectedSceneRange.map(SilenceSegmentSelection.init),
            target: click.range, ranges: clipLayout.clips.map(\.range),
            extending: click.modifiers.contains(.shift), toggling: click.modifiers.contains(.command)
        )).map(EditorSelection.ranges)
    }

    private var selectedSceneRange: EditorTimeRange? {
        guard case .segment(let index) = selection else { return nil }
        return EditorTimeRange.segment(.init(eventTimes: sceneEvents.map(\.time), index: index, duration: duration))
    }

    private func clickTranscriptRange(_ click: EditorTimelineRangeClick) {
        selection = SilenceSegmentSelection.clickingItems(.init(
            current: selection?.rangeSelection ?? selectedSceneRange.map(SilenceSegmentSelection.init),
            target: click.range, ranges: transcriptLayout.items.map { $0.source.range },
            extending: click.modifiers.contains(.shift), toggling: click.modifiers.contains(.command)
        )).map(EditorSelection.ranges)
        if click.modifiers.intersection([.shift, .command]).isEmpty {
            onSeek(click.range.start)
            onSeekEnded()
        }
    }

    private var classificationSelection: SilenceSegmentSelection? {
        selection?.rangeSelection
    }

    private var selectionTint: Color {
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

    private func timelineBody(viewportWidth: CGFloat) -> some View {
        let trackViewport = max(trackScrollWidth > 0 ? trackScrollWidth - 16 : viewportWidth - gutterWidth - 24, 40)
        let layoutDuration = clipTrim.lockedDisplayDuration
            ?? EditorTimelineZoom.fitDuration(
                anchor: zoomFitDuration, zoom: zoomLevel, current: projection.duration)
        let pxPerSecond = trackViewport / CGFloat(max(layoutDuration, 0.5)) * CGFloat(EditorTimelineZoom.clamp(.init(value: zoomLevel, duration: layoutDuration)))
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
                    content: ruler(.init(pxPerSecond: pxPerSecond, width: contentWidth, viewport: viewport))
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
                                    EditorVideoClipStrip(configuration: .init(
                                        layout: clipLayout, viewport: viewport, pixelsPerSecond: pxPerSecond,
                                        width: contentWidth, height: clipRowHeight,
                                        edits: project?.edits ?? .empty, duration: duration,
                                        selectedRanges: selection?.rangeSelection?.ranges ?? [],
                                        hoveredRange: hoveredClipRange,
                                        trimOrigin: clipTrim.origin,
                                        onSelect: clickVideoClip,
                                        onHover: { hoveredClipRange = $0 },
                                        onBeginTrim: { origin in
                                            clipTrim.beginTrim(.init(origin: origin, displayDuration: projection.duration))
                                        },
                                        onTrim: previewClipTrim,
                                        onEndTrim: commitClipTrim,
                                        onCancelTrim: cancelTimelineDrag))
                                        .background {
                                            if let asset = overviewAsset {
                                                clipFilmstrip(.init(asset: asset, pxPerSecond: pxPerSecond,
                                                    contentWidth: contentWidth, viewport: viewport))
                                            }
                                        }
                                        .clipShape(.rect(cornerRadius: 4))
                                        .disabled(!isInteractive)
                                        .contextMenu { selectionCommands; Divider(); timelineContextMenu }
                                    transcriptTrack(.init(pixelsPerSecond: pxPerSecond, contentWidth: contentWidth, viewport: viewport))
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
                                    if !showsSegmentsTrack && sourceAssets.isEmpty {
                                        emptyHint
                                    }
                                }
                            }
                            .contentShape(.rect)
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 5, coordinateSpace: .named(timelineContentSpace))
                                    .onChanged { value in
                                        guard !clipTrim.isActive, !isPlacedTrack(at: value.startLocation.y),
                                            let range = EditorTimeRange.resolve(.init(
                                                anchor: projection.takeTime(Double(value.startLocation.x / pxPerSecond)),
                                                head: projection.takeTime(Double(value.location.x / pxPerSecond)), duration: duration
                                            ))
                                        else { return }
                                        selection = .range(range)
                                    },
                                isEnabled: isInteractive
                            )

                            if duration > 0 {
                                EditorTimelineSilenceOverlay(configuration: .init(
                                    segments: selectableSilenceSegments, projection: projection,
                                    pixelsPerSecond: pxPerSecond, viewport: viewport, rows: silenceMarkedRows))
                                    .equatable()
                                    .frame(width: viewport.width, height: contentHeight)
                                    .offset(x: viewport.lowerBound)
                                linkedSegmentOverlay(pxPerSecond)
                                if let range = hoveredClipRange, clipTrim.origin == nil,
                                    selection?.rangeSelection?.ranges.contains(range) != true {
                                    hoverOverlay(.init(range: range, pxPerSecond: pxPerSecond))
                                }
                                if let selected = selection?.rangeSelection {
                                    if selected.ranges.count == 1 {
                                        rangeOverlay(.init(range: selected.bounds, pxPerSecond: pxPerSecond))
                                    } else {
                                        EditorTimelineSelectionCanvas(configuration: .init(
                                            ranges: selected.displayRanges, projection: projection, viewport: viewport,
                                            pixelsPerSecond: pxPerSecond, height: contentHeight, tint: selectionTint))
                                            .frame(width: viewport.width, height: contentHeight)
                                            .offset(x: viewport.lowerBound)
                                            .allowsHitTesting(false)
                                    }
                                }
                            }
                        }
                        .frame(width: contentWidth, alignment: .topLeading)
                        .background { EditorTimelineKeyboardFocus().allowsHitTesting(false) }
                        .coordinateSpace(name: timelineContentSpace)
                        .padding(.horizontal, 8)
                    }
                    .scrollPosition($scrollPosition)
                    .onChange(of: zoomLevel) { _, _ in
                        zoomFitDuration = projection.duration
                        scrollPosition.scrollTo(x: EditorTimelineScroll.centered(
                            on: projection.displayTime(selectionFocusTime ?? playback.currentTime),
                            pixelsPerSecond: pxPerSecond,
                            contentWidth: contentWidth,
                            viewportWidth: trackViewport
                        ))
                    }
                    .onChange(of: selectionFocusTime) { _, _ in
                        guard selectionFocusTime != nil else { return }
                        scrollPosition.scrollTo(x: EditorTimelineScroll.centered(
                            on: projection.displayTime(selectionFocusTime ?? playback.currentTime),
                            pixelsPerSecond: pxPerSecond,
                            contentWidth: contentWidth,
                            viewportWidth: trackViewport
                        ))
                    }
                    .onChange(of: projection.duration) { old, new in
                        zoomFitDuration = EditorTimelineZoom.anchoredFitDuration(
                            currentAnchor: zoomFitDuration, oldDuration: old, zoom: zoomLevel)
                        let fit = EditorTimelineZoom.fitDuration(
                            anchor: zoomFitDuration, zoom: zoomLevel, current: new)
                        let pps = trackViewport / CGFloat(max(fit, 0.5))
                            * CGFloat(EditorTimelineZoom.clamp(.init(value: zoomLevel, duration: fit)))
                        let width = max(CGFloat(new) * pps, trackViewport)
                        let clamped = EditorTimelineScroll.clamped(
                            offset: rulerScrollOffset.value, contentWidth: width, viewportWidth: trackViewport)
                        if abs(clamped - rulerScrollOffset.value) > 0.5 {
                            scrollPosition.scrollTo(x: clamped)
                        }
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
        .overlayPreferenceValue(EditorTimelineControlKey.self) { controls in
            GeometryReader { geometry in
                if duration > 0 {
                    ZStack(alignment: .topLeading) {
                        EditorTimelineHoverLine(hover: rulerHover)
                            .frame(width: trackViewport + 16)
                            .clipped()
                            .padding(.leading, gutterWidth + 8)
                            .zIndex(0)
                        EditorTimelinePlayhead(configuration: .init(
                            projection: projection, scrollOffset: rulerScrollOffset, pixelsPerSecond: pxPerSecond,
                            playbackTime: playback.currentTime, liveTime: { playback.displayTime() },
                            isPlaying: playback.isPlaying,
                            isInteractive: isInteractive, rulerHeight: rulerHeight, viewportWidth: trackViewport + 16,
                            onSeek: onSeek, onSeekEnded: onSeekEnded))
                            .frame(width: trackViewport + 16)
                            .clipped()
                            .padding(.leading, gutterWidth + 8)
                            .zIndex(1)
                        EditorTimelineControlLayer(configuration: .init(
                            controls: controls, geometry: geometry,
                            viewport: CGRect(x: gutterWidth + 8, y: rulerHeight + 6,
                                width: trackViewport + 16, height: max(0, geometry.size.height - rulerHeight - 6))))
                            .disabled(!isInteractive)
                            .zIndex(2)
                    }
                }
            }
        }
        .onContinuousHover { phase in
            let location: CGPoint?
            switch phase {
            case .active(let point): location = point
            case .ended: location = nil
            }
            rulerHover.update(.init(
                location: location,
                ruler: CGRect(x: gutterWidth + 8, y: 0, width: trackViewport + 16, height: rulerHeight),
                isInteractive: isInteractive && duration > 0))
        }
        .onChange(of: isInteractive) { _, enabled in
            if !enabled { rulerHover.position = nil }
        }
        .onDisappear { rulerHover.position = nil }
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
        let top = clipRowHeight + 6 + transcriptRowHeight + 6
            + (showsChaptersTrack ? chaptersRowHeight + 6 : 0)
            + (showsSegmentsTrack ? segmentsRowHeight + 6 : 0)
        return y >= top && y < top + CGFloat(placedTracks.count) * (placedRowHeight + 6)
    }

    private func linkedSegmentOverlay(_ pxPerSecond: CGFloat) -> some View {
        let top = clipRowHeight + 6 + transcriptRowHeight + 6
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
        EditorTimelineRangeHighlight(configuration: .init(
            range: request.range, projection: projection, pixelsPerSecond: request.pxPerSecond,
            height: contentHeight, tint: selectionTint))
            .onDisappear { cancelTimelineDrag() }
    }

    private func cancelTimelineDrag() {
        _ = clipTrim.finish()
    }

    private func previewClipTrim(_ translationWidth: CGFloat) {
        if let trimmed = clipTrim.applyTrim(translationWidth: translationWidth) {
            selection = .range(trimmed)
        }
    }

    private func commitClipTrim() {
        var session = clipTrim
        let edits = session.finish()
        clipTrim = session
        if let edits { onTrimClip(edits) }
    }

    private var gutterHeading: some View {
        HStack(spacing: 8) {
            Text("Tracks")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(BlitzUI.supportingText)
            Spacer(minLength: 0)
            Button {
                cancelTimelineDrag()
                if case .asset = selection { selection = nil }
                showsSourceTracks.toggle()
            } label: {
                Label("Video", systemImage: showsSourceTracks ? "chevron.down" : "chevron.right")
            }
            .blitzButton(.quiet)
            .controlSize(.mini)
            .accessibilityLabel(showsSourceTracks ? "Collapse video tracks" : "Expand video tracks")
            .accessibilityValue("\(sourceAssets.filter { !$0.isAudio }.count) tracks")
            .help("Show Screen and Camera tracks. Audio waveforms stay visible.")
        }
        .padding(.leading, 10)
        .padding(.trailing, 2)
        .frame(width: gutterWidth, height: rulerHeight)
    }

    private var gutterColumn: some View {
        VStack(spacing: 6) {
            if duration > 0 {
                EditorTimelineTrackHeader(configuration: .init(
                    title: "Video", symbol: "film.stack", tint: BlitzUI.mint, status: nil,
                    height: clipRowHeight, isSelected: false, isInteractive: isInteractive, onSelect: nil,
                    accessory: { Color.clear.frame(width: 30) }
                ))
                .help("Video clips stay linked across Screen, Camera, and audio. ⌘B splits the whole clip at the playhead.")
            }
            ForEach(Array(gutterRows.enumerated()), id: \.offset) { _, row in
                let isSelected = row.item.map { selection == .placed($0) }
                    ?? row.asset.map { selection == .asset($0.id) } ?? false
                let isOff = row.asset.map { hiddenAssetIDs.contains($0.id) || mutedAssetIDs.contains($0.id) } ?? false
                let onSelect: (() -> Void)? = row.item != nil || row.asset != nil ? {
                    if let item = row.item { selection = .placed(item) }
                    else if let asset = row.asset { selection = .asset(asset.id) }
                } : nil
                EditorTimelineTrackHeader(configuration: .init(
                    title: row.title, symbol: row.icon,
                    tint: row.asset?.tint ?? BlitzUI.supportingText,
                    status: row.title == "Transcript" && transcriptionStatus.isRunning ? transcriptionStatus.label
                        : row.asset.map { library.loadingIDs.contains($0.id) } == true
                        ? (row.asset?.isAudio == true ? "Loading waveform" : "Loading previews")
                        : isOff ? (row.asset?.isVideo == true ? "Hidden" : "Muted") : nil,
                    height: row.height, isSelected: isSelected, isInteractive: isInteractive,
                    onSelect: onSelect,
                    accessory: {
                        if row.title == "Transcript", transcriptionStatus.isRunning {
                            ProgressView().controlSize(.mini)
                                .frame(width: 30)
                                .help(transcriptionStatus.label)
                                .accessibilityLabel(transcriptionStatus.label)
                        } else if row.title == "Transcript", transcript != nil, transcript?.words == nil {
                            Button("Words", action: onGenerateTranscript)
                                .blitzButton(.secondary)
                                .controlSize(.mini)
                                .disabled(transcriptionStatus.isRunning)
                                .accessibilityLabel("Generate word timings")
                                .help(transcriptionStatus.isRunning ? transcriptionStatus.label
                                    : "Generate precise word timings for this older transcript.")
                        } else if let asset = row.asset, toggleableAssetIDs.contains(asset.id) {
                            if library.loadingIDs.contains(asset.id) || library.filmstripLoadingCounts[asset.id] != nil {
                                ProgressView().controlSize(.mini)
                                    .help(asset.isAudio ? "Preparing waveform" : "Preparing thumbnails")
                            }
                            EditorTimelineTrackToggle(configuration: .init(
                                title: asset.title, isVideo: asset.isVideo, isOff: isOff,
                                isInteractive: isInteractive, onToggle: { onToggleTrack(asset) }))
                        } else {
                            Color.clear.frame(width: 30)
                        }
                    }
                ))
            }
        }
        .frame(width: gutterWidth)
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
        .blitzCursor(.arrow)
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
            .fill(BlitzUI.trackCamera.opacity(hoveredChapterTime == chapter.time ? 0.4 : 0.22))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(hoveredChapterTime == chapter.time ? BlitzUI.trackCamera : .clear, lineWidth: 2)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .leading) {
                Text(chapter.title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)
                    .padding(.horizontal, 7)
            }
            .contentShape(.rect(cornerRadius: 5))
            .pointingHandCursor()
            .onHover { hoveredChapterTime = $0 && isInteractive ? chapter.time : nil }
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
            let modifiers = NSEvent.modifierFlags
            if !modifiers.intersection([.shift, .command]).isEmpty,
                let range = EditorTimeRange.segment(.init(eventTimes: sceneEvents.map(\.time), index: index, duration: duration)) {
                clickTimelineRange(.init(range: range, modifiers: modifiers))
            } else {
                selection = .segment(index)
                onSeek(min(duration, request.start + 0.001))
                onSeekEnded()
            }
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
            playbackTime: playback.currentTime
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

    private var overviewAsset: EditorAsset? {
        sourceAssets.first { $0.isVideo && !hiddenAssetIDs.contains($0.id) }
    }

    private func clipFilmstrip(_ request: AssetTrackRequest) -> some View {
        let asset = request.asset
        let frames = library.filmstrips[asset.id] ?? []
        let frameCount = EditorTimelineFilmstripCells.loadingCount(for: request.contentWidth)
        return EditorTimelineMediaCanvas(
            frames: frames, waveform: nil, isVideo: true, tint: asset.tint,
            projection: projection, sourceDuration: library.durations[asset.id] ?? duration,
            sourceOffset: asset.kind == .output ? 0
                : (project?.sourceOffset(forRole: asset.kind.rawValue) ?? 0) - (project?.timelineTrimOffsetSeconds ?? 0),
            pixelsPerSecond: request.pxPerSecond, viewport: request.viewport
        )
        .equatable()
        .frame(width: request.contentWidth, height: clipRowHeight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: EditorFilmstripTaskID(assetID: asset.id, requestedFrameCount: frameCount)) {
            guard frames.count < frameCount else { return }
            if !frames.isEmpty {
                do { try await Task.sleep(for: .milliseconds(180)) }
                catch { return }
            }
            guard !Task.isCancelled else { return }
            await library.loadFilmstrip(request: .init(assetID: asset.id, url: asset.url, frameCount: frameCount))
        }
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
        }
        .frame(width: width, height: rowHeight)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(isSelected ? BlitzUI.mint : asset.tint.opacity(0.28), lineWidth: isSelected ? 2 : 1)
                .allowsHitTesting(false)
        }
        .contentShape(shape)
        .pointingHandCursor()
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                guard isInteractive, request.pxPerSecond > 0 else { return }
                let range = clipLayout.clip(at: Double(location.x / request.pxPerSecond))?.range
                if hoveredClipRange != range { hoveredClipRange = range }
            case .ended:
                hoveredClipRange = nil
            }
        }
        .onDisappear { hoveredClipRange = nil }
        .gesture(SpatialTapGesture().onEnded { event in
            if let clip = clipLayout.clip(at: Double(event.location.x / request.pxPerSecond)) {
                clickVideoClip(.init(range: clip.range, modifiers: NSEvent.modifierFlags))
            }
        })
        .opacity(isOff ? 0.3 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            if let clip = clipLayout.clip(at: projection.displayTime(playback.currentTime)) ?? clipLayout.clips.last {
                clickVideoClip(.init(range: clip.range, modifiers: []))
            }
        }
        .accessibilityLabel("\(asset.title) track")
        .accessibilityValue(isOff ? (asset.isVideo ? "Hidden" : "Muted in playback and export")
            : isSelected ? "Selected" : "Enabled, \(max(0, clipLayout.clips.count - 1)) clip boundaries")
        .help("Click to select a linked clip. Drag to select a range. Return or Delete removes selected time from all tracks. Select the track name to hide or mute the entire track.")
        .contextMenu {
            Button("Select \(asset.title) track", systemImage: asset.systemImage) {
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
        Button("Silence settings", systemImage: "waveform", action: onOpenSilence)
        Button("Keyboard shortcuts", systemImage: "keyboard") { showsShortcuts = true }
    }

    private func updateTranscriptItems() {
        transcriptItems = transcript.map {
            EditorTranscriptTimeline.items(.init(
                transcript: $0, windows: silence.windows, threshold: silence.threshold, duration: duration
            ))
        } ?? []
        updateTranscriptLayout()
        silence.setTranscript(transcript)
    }

    private func updateSilenceSegments() {
        let resolved = SilenceTimelineSegments.resolve(.init(duration: duration, cuts: silence.cuts))
        silenceSegments = SilenceTimelineSegments.capped(.init(
            segments: resolved, end: clipLayout.clips.last?.range.end ?? duration
        ))
    }

    private func updateTranscriptLayout() {
        transcriptLayout = EditorTranscriptLayout(.init(items: transcriptItems, projection: projection))
    }

    private var transcriptionFailureDetail: String {
        if case .failed(let message) = transcriptionStatus { return message }
        return "Generate a local transcript to select and cut spoken words."
    }

    private struct TranscriptTrackRequest {
        let pixelsPerSecond: CGFloat
        let contentWidth: CGFloat
        let viewport: EditorTimelineViewport
    }

    @ViewBuilder
    private func transcriptTrack(_ request: TranscriptTrackRequest) -> some View {
        if transcriptItems.isEmpty {
            HStack(spacing: 8) {
                Text(transcriptionStatus.label)
                    .font(.system(size: 11))
                    .foregroundStyle(BlitzUI.secondaryText)
                Button("Generate transcript", action: onGenerateTranscript)
                    .blitzButton(.secondary)
                    .controlSize(.mini)
                    .disabled(transcriptionStatus.isRunning)
            }
            .frame(width: request.contentWidth, height: transcriptRowHeight, alignment: .leading)
            .help(transcriptionFailureDetail)
        } else {
            EditorTranscriptStrip(configuration: .init(
                layout: transcriptLayout, viewport: request.viewport,
                pixelsPerSecond: request.pixelsPerSecond, width: request.contentWidth, height: transcriptRowHeight,
                selections: selection?.rangeSelection?.ranges ?? [], onSelect: clickTranscriptRange
            ))
            .disabled(!isInteractive)
            .contextMenu {
                Button("Remove all silence without dialogue") { silence.removeNonDialogue() }
                    .disabled(!silence.canRemoveNonDialogue)
                Divider()
                Button(transcript?.words?.isEmpty == false ? "Regenerate transcript" : "Generate word timings",
                       action: onGenerateTranscript)
                    .disabled(transcriptionStatus.isRunning)
            }
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
        EditorTimelineLaneVisibility.showsScenes(eventCount: sceneEvents.count)
    }

    private var trackAssets: [EditorAsset] {
        sourceAssets.filter { showsSourceTracks || $0.isAudio }
    }

    private var sourceAssets: [EditorAsset] {
        var rows = assets.filter { $0.exists && $0.isPlayable && $0.kind != .output }
        if let output = outputAsset, sceneEvents.isEmpty {
            rows.insert(output, at: 0)
        }
        return rows
    }

    private var gutterRows: [(icon: String, title: String, height: CGFloat, asset: EditorAsset?, item: EditorPlacedItem.ID?)] {
        guard duration > 0 else { return [] }
        var rows: [(icon: String, title: String, height: CGFloat, asset: EditorAsset?, item: EditorPlacedItem.ID?)] = []
        rows.append((icon: "text.quote", title: "Transcript", height: transcriptRowHeight, asset: nil, item: nil))
        if showsChaptersTrack {
            rows.append((icon: "text.quote", title: "Chapters", height: chaptersRowHeight, asset: nil, item: nil))
        }
        if showsSegmentsTrack {
            rows.append((icon: BlitzSymbols.scenes, title: "Scenes", height: segmentsRowHeight, asset: nil, item: nil))
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

    private var silenceMarkedRows: [Range<CGFloat>] {
        guard duration > 0 else { return [] }
        var rows: [Range<CGFloat>] = [0..<clipRowHeight]
        var top = clipRowHeight + 6
        for row in gutterRows {
            if row.asset != nil { rows.append(top..<(top + row.height)) }
            top += row.height + 6
        }
        return rows
    }

    private var contentHeight: CGFloat {
        var height: CGFloat = 0
        if duration > 0 {
            height += clipRowHeight + 6
            height += transcriptRowHeight + 6
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
            if !showsSegmentsTrack && sourceAssets.isEmpty {
                height += 6 + 56
            }
        }
        return max(0, height - 6)
    }

    private func seek(toContentX x: CGFloat, pxPerSecond: CGFloat) {
        guard duration > 0, pxPerSecond > 0 else { return }
        onSeek(projection.takeTime(min(max(0, Double(x / pxPerSecond)), projection.duration)))
    }

}

private struct EditorSceneTimelineItem: View {
    let scene: RecordingScene
    let canvasAspectRatio: CGFloat
    let isSelected: Bool
    let isActive: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

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
        .background(isHovering ? BlitzUI.hoverFill : isActive ? BlitzUI.trackCamera.opacity(0.12) : BlitzUI.cardFill, in: shape)
        .overlay {
            shape.strokeBorder(
                isSelected || isHovering ? BlitzUI.mint : (isActive ? BlitzUI.panelStroke : BlitzUI.separator),
                lineWidth: isSelected || isHovering ? 2 : 1
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
        .onHover { isHovering = $0 && isEnabled }
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

private struct EditorTimelinePlayhead: View {
    struct Configuration {
        let projection: EditorTimelineProjection
        let scrollOffset: EditorTimelineScrollOffset
        let pixelsPerSecond: CGFloat
        let playbackTime: Double
        let liveTime: () -> Double
        let isPlaying: Bool
        let isInteractive: Bool
        let rulerHeight: CGFloat
        let viewportWidth: CGFloat
        let onSeek: (Double) -> Void
        let onSeekEnded: () -> Void
    }

    let configuration: Configuration
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !configuration.isPlaying)) { _ in
            let time = configuration.isPlaying ? configuration.liveTime() : configuration.playbackTime
            let displayTime = configuration.projection.displayTime(time)
            let rawX = 8 + CGFloat(displayTime) * configuration.pixelsPerSecond - configuration.scrollOffset.value
            let x = (rawX * displayScale).rounded() / displayScale
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    guard x >= 0, x <= size.width else { return }
                    let marker = EditorTimelinePlayheadShape().path(in: CGRect(x: x - 6, y: 0, width: 12, height: size.height))
                    context.stroke(marker, with: .color(.black.opacity(0.7)), lineWidth: 2)
                    context.fill(marker, with: .color(BlitzUI.mint))
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                Color.clear
                    .frame(width: max(0, min(configuration.viewportWidth, x + 14) - max(0, x - 14)),
                        height: configuration.rulerHeight)
                    .contentShape(.rect)
                    .offset(x: max(0, x - 14))
                    .allowsHitTesting(configuration.isInteractive && x >= 0 && x <= configuration.viewportWidth)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("EditorTimelinePlayhead"))
                            .onChanged { value in
                                guard configuration.pixelsPerSecond > 0 else { return }
                                let displayTime = Double((value.location.x + configuration.scrollOffset.value - 8)
                                    / configuration.pixelsPerSecond)
                                configuration.onSeek(configuration.projection.takeTime(
                                    min(configuration.projection.duration, max(0, displayTime))))
                            }
                            .onEnded { _ in configuration.onSeekEnded() },
                        isEnabled: configuration.isInteractive
                    )
                    .accessibilityLabel("Playhead")
                    .accessibilityValue(MediaTimecode.label(.init(time: displayTime, duration: configuration.projection.duration)))
                    .help("Drag to scrub the full timeline")
            }
            .coordinateSpace(name: "EditorTimelinePlayhead")
            .opacity(configuration.isInteractive ? 1 : 0.4)
        }
    }
}

private struct EditorTimelinePlayheadShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius: CGFloat = 2.5
        let shoulder = rect.minY + 8
        let stemTop = rect.minY + 13
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: shoulder))
        path.addLine(to: CGPoint(x: rect.midX + 1, y: stemTop))
        path.addLine(to: CGPoint(x: rect.midX + 1, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX - 1, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX - 1, y: stemTop))
        path.addLine(to: CGPoint(x: rect.minX, y: shoulder))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}
