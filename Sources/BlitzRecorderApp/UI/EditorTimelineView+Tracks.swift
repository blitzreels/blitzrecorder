import AppKit
import SwiftUI

extension EditorTimelineView {
    struct PlacedTrackRequest {
        let track: EditorPlacedTrack
        let pixelsPerSecond: CGFloat
        let contentWidth: CGFloat
        let viewport: EditorTimelineViewport
    }

    func placedTrack(_ request: PlacedTrackRequest) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 5).fill(BlitzUI.cardFill)
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

    func chaptersTrack(pxPerSecond: CGFloat, contentWidth: CGFloat) -> some View {
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
                .fill(BlitzUI.cardFill)
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
                    .font(BlitzType.footnote)
                    .foregroundStyle(BlitzUI.primaryText)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
            }
            .contentShape(.rect(cornerRadius: 5))
            .pointingHandCursor()
            .onHover { hoveredChapterTime = $0 && isInteractive ? chapter.time : nil }
            .onTapGesture { seekAndSettle(to: start) }
    }

    func segmentsTrack(pxPerSecond: CGFloat, contentWidth: CGFloat) -> some View {
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
                .fill(BlitzUI.cardFill)
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
                let range = segmentRange(at: index) {
                clickTimelineRange(.init(range: range, modifiers: modifiers))
            } else {
                selectSegment(request)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Segment \(index + 1)")
        .accessibilityValue(isSelected ? "Selected, all tracks" : "All tracks")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { selectSegment(request) }
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

    private func selectSegment(_ request: SegmentClipRequest) {
        selection = .segment(request.index)
        seekAndSettle(to: min(duration, request.start + 0.001))
    }

    struct AssetTrackRequest {
        let asset: EditorAsset
        let pxPerSecond: CGFloat
        let contentWidth: CGFloat
        let viewport: EditorTimelineViewport
    }

    func clipFilmstrip(_ request: AssetTrackRequest) -> some View {
        let asset = request.asset
        let frames = library.filmstrips[asset.id] ?? []
        let frameCount = EditorTimelineFilmstripCells.loadingCount(for: request.contentWidth)
        return EditorTimelineMediaCanvas(
            frames: frames, waveform: nil, isVideo: true, tint: asset.tint,
            projection: projection, sourceDuration: library.durations[asset.id] ?? duration,
            sourceOffset: sourceOffset(for: asset),
            pixelsPerSecond: request.pxPerSecond, viewport: request.viewport
        )
        .equatable()
        .frame(width: request.contentWidth, height: clipRowHeight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: EditorFilmstripTaskID(assetID: asset.id, requestedFrameCount: frameCount)) {
            await loadFilmstrip(.init(asset: asset, loadedFrameCount: frames.count, requestedFrameCount: frameCount))
        }
    }

    private func sourceOffset(for asset: EditorAsset) -> Double {
        asset.kind == .output ? 0
            : (project?.sourceOffset(forRole: asset.kind.rawValue) ?? 0) - (project?.timelineTrimOffsetSeconds ?? 0)
    }

    private struct FilmstripLoad {
        let asset: EditorAsset
        let loadedFrameCount: Int
        let requestedFrameCount: Int
    }

    private func loadFilmstrip(_ load: FilmstripLoad) async {
        guard load.loadedFrameCount < load.requestedFrameCount else { return }
        if load.loadedFrameCount > 0 {
            do { try await Task.sleep(for: .milliseconds(180)) }
            catch { return }
        }
        guard !Task.isCancelled else { return }
        await library.loadFilmstrip(request: EditorFilmstripLoadRequest(
            assetID: load.asset.id,
            url: load.asset.url,
            frameCount: load.requestedFrameCount
        ))
    }

    func assetTrack(_ request: AssetTrackRequest) -> some View {
        let asset = request.asset
        let rowHeight = self.rowHeight(for: asset)
        let sourceDuration = library.durations[asset.id] ?? duration
        let sourceOffset = self.sourceOffset(for: asset)
        let width = max(1, CGFloat(projection.duration) * request.pxPerSecond)
        let frames = library.filmstrips[asset.id] ?? []
        let requestedFrameCount = EditorTimelineFilmstripCells.loadingCount(for: width)
        let filmstripTaskID = EditorFilmstripTaskID(
            assetID: asset.id,
            requestedFrameCount: requestedFrameCount
        )
        let isSelected = selection == .asset(asset.id)
        let isOff = isTrackOff(asset)
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
            guard asset.isVideo else { return }
            await loadFilmstrip(.init(asset: asset, loadedFrameCount: frames.count, requestedFrameCount: requestedFrameCount))
        }
    }

    private struct EditorFilmstripTaskID: Hashable {
        let assetID: String
        let requestedFrameCount: Int
    }

    @ViewBuilder
    var timelineContextMenu: some View {
        Button("Silence settings", systemImage: "waveform", action: onOpenSilence)
        Button("Keyboard shortcuts", systemImage: "keyboard") { showsShortcuts = true }
    }

    private var transcriptionFailureDetail: String {
        if case .failed(let message) = transcriptionStatus { return message }
        return "Generate a local transcript to select and cut spoken words."
    }

    struct TranscriptTrackRequest {
        let pixelsPerSecond: CGFloat
        let contentWidth: CGFloat
        let viewport: EditorTimelineViewport
    }

    @ViewBuilder
    func transcriptTrack(_ request: TranscriptTrackRequest) -> some View {
        if transcriptItems.isEmpty {
            HStack(spacing: 8) {
                Text(transcriptionStatus.label)
                    .font(BlitzType.caption)
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
}
