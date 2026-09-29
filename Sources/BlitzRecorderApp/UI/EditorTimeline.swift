import AppKit
import Observation
import SwiftUI

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
    @State var headerWidth: CGFloat = 1_440
    @State var transportWidth: CGFloat = 330
    @Binding var showsShortcuts: Bool
    @Binding var showsSourceTracks: Bool
    let silence: SilenceEditingSession
    let onOpenSilence: () -> Void
    let onChangePlacedItem: (EditorPlacedItemEditing.Change) -> Void
    let onRemovePlacedItem: (EditorPlacedItem.ID) -> Void

    @State var transcriptItems: [EditorTranscriptItem] = []
    @State var transcriptLayout = EditorTranscriptLayout(.init(items: [], projection: .init(.init(duration: 0, cuts: []))))
    @State var projection = EditorTimelineProjection(.init(duration: 0, cuts: []))
    @State var clipLayout = EditorVideoClipLayout(.init(projection: .init(.init(duration: 0, cuts: [])), splits: []))
    @State var scrollOffset: CGFloat = 0
    @State var trackScrollWidth: CGFloat = 0
    @State var rulerScrollOffset = EditorTimelineScrollOffset()
    @State var rulerHover = EditorTimelineRulerHover()
    @State var scrollPosition = ScrollPosition(x: 0)
    @State var silenceSegments: [SilenceTimelineSegment] = []
    @State var selectableSilenceSegments: [SilenceTimelineSegment] = []
    @State var hoveredClipRange: EditorTimeRange?
    @State var hoveredChapterTime: Double?
    @State var selectionFocusTime: Double?
    @State var clipTrim = EditorClipTrimSession()
    @State var zoomFitDuration: Double = 0

    let gutterWidth: CGFloat = 180
    let rulerHeight: CGFloat = 30
    let chaptersRowHeight: CGFloat = 32
    let segmentsRowHeight: CGFloat = 38
    private let videoRowHeight: CGFloat = 54
    private let audioRowHeight: CGFloat = 44
    let transcriptRowHeight: CGFloat = 30
    let clipRowHeight: CGFloat = 64
    let placedRowHeight: CGFloat = 38

    var placedTracks: [EditorPlacedTrack] {
        var tracks = EditorPlacedTrack.resolve(project?.edits ?? .empty)
        if let project, let music = EditorPlacedTrack.music(.init(projectID: project.id,
            path: project.editorState.backgroundMusicPath, duration: duration)) { tracks.append(music) }
        return tracks
    }
    var selectedPlacedItem: EditorPlacedItem.ID? {
        if case .placed(let id) = selection { return id }
        return nil
    }
    var canSplitSelection: Bool {
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

    var activeSegmentIndex: Int? {
        EditorSceneTimelineActiveIndexResolver.index(request: .init(
            eventTimes: sceneEvents.map(\.time),
            playbackTime: playback.currentTime
        ))
    }

    var captureLayout: CaptureLayout {
        guard let rawLayout = project?.settings.layout else { return .horizontal }
        return CaptureLayout(rawValue: rawLayout) ?? .horizontal
    }

    var overviewAsset: EditorAsset? {
        sourceAssets.first { $0.isVideo && !hiddenAssetIDs.contains($0.id) }
    }

    var sceneEvents: [RecordingProject.SceneEventSnapshot] {
        project?.sceneEvents ?? []
    }

    var timelineChapters: [RecordingProject.ChapterSnapshot] {
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

    var showsChaptersTrack: Bool {
        !timelineChapters.isEmpty
    }

    var showsSegmentsTrack: Bool {
        EditorTimelineLaneVisibility.showsScenes(eventCount: sceneEvents.count)
    }

    var trackAssets: [EditorAsset] {
        sourceAssets.filter { showsSourceTracks || $0.isAudio }
    }

    var sourceAssets: [EditorAsset] {
        var rows = assets.filter { $0.exists && $0.isPlayable && $0.kind != .output }
        if let output = outputAsset, sceneEvents.isEmpty {
            rows.insert(output, at: 0)
        }
        return rows
    }

    typealias GutterRow = (icon: String, title: String, height: CGFloat, asset: EditorAsset?, item: EditorPlacedItem.ID?)

    var gutterRows: [GutterRow] {
        guard duration > 0 else { return [] }
        var rows: [GutterRow] = []
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
                height: rowHeight(for: asset),
                asset: asset,
                item: nil
            ))
        }
        return rows
    }

    var silenceMarkedRows: [Range<CGFloat>] {
        guard duration > 0 else { return [] }
        var rows: [Range<CGFloat>] = [0..<clipRowHeight]
        var top = clipRowHeight + 6
        for row in gutterRows {
            if row.asset != nil { rows.append(top..<(top + row.height)) }
            top += row.height + 6
        }
        return rows
    }

    func rowHeight(for asset: EditorAsset) -> CGFloat {
        asset.isVideo ? videoRowHeight : audioRowHeight
    }

    func isTrackOff(_ asset: EditorAsset) -> Bool {
        hiddenAssetIDs.contains(asset.id) || mutedAssetIDs.contains(asset.id)
    }

    var segmentsTrackTop: CGFloat {
        clipRowHeight + 6 + transcriptRowHeight + 6
            + (showsChaptersTrack ? chaptersRowHeight + 6 : 0)
    }

    var contentHeight: CGFloat {
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
                height += 6 + rowHeight(for: asset)
            }
            if !showsSegmentsTrack && sourceAssets.isEmpty {
                height += 6 + 56
            }
        }
        return max(0, height - 6)
    }
}
