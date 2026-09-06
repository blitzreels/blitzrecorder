import SwiftUI

private let timelineContentSpace = "EditorTimelineContent"
private let layoutSegmentFill = Color(red: 0.045, green: 0.12, blue: 0.13)

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
    let onDeleteCut: () -> Void
    let canDeleteCut: Bool

    @State private var zoomLevel: Double = 1

    private let gutterWidth: CGFloat = 136
    private let rulerHeight: CGFloat = 26
    private let chaptersRowHeight: CGFloat = 32
    private let segmentsRowHeight: CGFloat = 42
    private let videoRowHeight: CGFloat = 48
    private let audioRowHeight: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)

            HStack(spacing: 0) {
                GeometryReader { proxy in
                    timelineBody(viewportWidth: proxy.size.width)
                }
                .frame(height: contentHeight)
            }
            .padding(12)
        }
        .background(Color.black.opacity(0.22), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }


    private var header: some View {
        ZStack {
            HStack(spacing: 8) {
                TimelineActionButton(
                    title: "Split",
                    systemName: "scissors",
                    isDisabled: !isInteractive,
                    action: onSplit
                )

                TimelineActionButton(
                    title: "Delete",
                    systemName: "trash",
                    isDisabled: !canDeleteCut,
                    action: onDeleteCut
                )

                TimelineActionButton(
                    title: "Fit",
                    systemName: "arrow.left.and.right.square",
                    isDisabled: zoomLevel == 1
                ) {
                    zoomLevel = 1
                }

                Spacer(minLength: 420)

                HStack(spacing: 7) {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                    Slider(value: $zoomLevel, in: 1...12)
                        .controlSize(.mini)
                        .frame(width: 104)
                        .help("Timeline zoom")
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(Color.white.opacity(0.035), in: .rect(cornerRadius: 9))
            }

            HStack(spacing: 6) {
                TimelineTransportControls(
                    isPlaying: isPlaying,
                    isDisabled: !isInteractive,
                    onPrevious: onPrevious,
                    onTogglePlayback: onTogglePlayback,
                    onNext: onNext
                )

                TimelineControlDivider()

                Text("\(formatTime(playbackTime)) / \(formatTime(duration))")
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 102, height: 40)

                TimelineControlDivider()

                TimelinePlaybackRateSelector(
                    playbackRate: playbackRate,
                    isDisabled: !isInteractive,
                    onSelect: onPlaybackRateChange
                )
            }
            .padding(4)
            .background(Color.black.opacity(0.38), in: .rect(cornerRadius: 13))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
        .background(Color.white.opacity(0.018))
    }


    private func timelineBody(viewportWidth: CGFloat) -> some View {
        let trackViewport = max(viewportWidth - gutterWidth - 8, 40)
        let pxPerSecond = trackViewport / CGFloat(max(duration, 0.5)) * CGFloat(zoomLevel)
        let contentWidth = max(CGFloat(contentSeconds) * pxPerSecond, trackViewport)

        return HStack(alignment: .top, spacing: 8) {
            gutterColumn

            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    Canvas { context, size in
                        guard pxPerSecond > 0 else { return }
                        let candidates: [Double] = [1, 2, 5, 10, 15, 30, 60, 120, 300]
                        let interval = candidates.first { CGFloat($0) * pxPerSecond >= 64 } ?? 300
                        var time = 0.0
                        while time <= contentSeconds + 0.001 {
                            let x = CGFloat(time) * pxPerSecond
                            context.fill(
                                Path(CGRect(x: x, y: rulerHeight, width: 1, height: max(0, size.height - rulerHeight))),
                                with: .color(.white.opacity(0.045))
                            )
                            time += interval
                        }
                    }
                    .frame(width: contentWidth, height: contentHeight)
                    .allowsHitTesting(false)

                    VStack(alignment: .leading, spacing: 6) {
                        ruler(pxPerSecond: pxPerSecond, width: contentWidth)

                        if duration > 0 {
                            if showsChaptersTrack {
                                chaptersTrack(pxPerSecond: pxPerSecond, contentWidth: contentWidth)
                            }
                            if showsSegmentsTrack {
                                segmentsTrack(pxPerSecond: pxPerSecond, contentWidth: contentWidth)
                            }
                            ForEach(trackAssets) { asset in
                                assetTrack(asset, pxPerSecond: pxPerSecond, contentWidth: contentWidth)
                            }
                            if !showsSegmentsTrack && trackAssets.isEmpty {
                                emptyHint
                            }
                        }
                    }

                    if duration > 0 {
                        playhead(pxPerSecond: pxPerSecond)
                    }
                }
                .frame(width: contentWidth, alignment: .topLeading)
                .coordinateSpace(name: timelineContentSpace)
            }
        }
    }

    private var gutterColumn: some View {
        VStack(spacing: 6) {
            Color.clear
                .frame(width: gutterWidth, height: rulerHeight)

            ForEach(Array(gutterRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 5) {
                    BlitzSymbol(configuration: .init(name: row.icon, size: 16))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 16)

                    Text(row.title)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let asset = row.asset, toggleableAssetIDs.contains(asset.id) {
                        trackToggle(for: asset)
                    } else {
                        Color.clear.frame(width: 20)
                    }
                }
                .padding(.leading, 10)
                .padding(.trailing, 4)
                .frame(width: gutterWidth, height: row.height)
                .background(Color.white.opacity(0.035), in: .rect(cornerRadius: 7))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(row.asset?.tint.opacity(0.72) ?? Color.white.opacity(0.2))
                        .frame(width: 3, height: max(12, row.height - 16))
                        .padding(.leading, 2)
                }
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
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(isOff ? 0.9 : 0.5))
                .frame(width: 40, height: 40)
                .contentShape(.rect(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help("\(verb) \(asset.title) for the entire export")
    }

    private var emptyHint: some View {
        Text("No editable tracks in this recording.")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
    }


    private func ruler(pxPerSecond: CGFloat, width: CGFloat) -> some View {
        Canvas { context, size in
            guard pxPerSecond > 0 else { return }
            let candidates: [Double] = [1, 2, 5, 10, 15, 30, 60, 120, 300]
            let interval = candidates.first { CGFloat($0) * pxPerSecond >= 64 } ?? 300
            let minor = interval / 5

            var index = 0
            var t = 0.0
            while t <= duration + 0.001 {
                let x = CGFloat(t) * pxPerSecond
                if index % 5 == 0 {
                    context.fill(
                        Path(CGRect(x: x, y: size.height - 6, width: 1, height: 6)),
                        with: .color(.white.opacity(0.28))
                    )
                    let label = Text(formatTime(t))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                    context.draw(label, at: CGPoint(x: x + 4, y: size.height - 14), anchor: .leading)
                } else {
                    context.fill(
                        Path(CGRect(x: x, y: size.height - 3, width: 1, height: 3)),
                        with: .color(.white.opacity(0.14))
                    )
                }
                index += 1
                t = Double(index) * minor
            }
        }
        .frame(width: width, height: rulerHeight)
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { seek(toContentX: $0.location.x, pxPerSecond: pxPerSecond) }
                .onEnded { _ in onSeekEnded() },
            isEnabled: isInteractive
        )
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
                let width = max(34, CGFloat(end - start) * pxPerSecond - gap)
                chapterClip(chapter, start: start)
                    .frame(width: width, height: chaptersRowHeight)
                    .offset(x: CGFloat(start) * pxPerSecond)
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
            .modifier(TimelineClipHover(cornerRadius: 5))
            .onTapGesture {
                onSeek(start)
                onSeekEnded()
            }
    }


    private func segmentsTrack(pxPerSecond: CGFloat, contentWidth: CGFloat) -> some View {
        let events = sceneEvents

        return ZStack(alignment: .topLeading) {
            ForEach(events.indices, id: \.self) { index in
                let start = min(max(events[index].time, 0), duration)
                let end = index + 1 < events.count
                    ? min(max(events[index + 1].time, start), duration)
                    : duration
                let gap: CGFloat = index + 1 < events.count ? 2 : 0
                let width = max(14, CGFloat(end - start) * pxPerSecond - gap)

                segmentClip(index: index, start: start)
                    .frame(width: width, height: segmentsRowHeight)
                    .offset(x: CGFloat(start) * pxPerSecond)
            }
        }
        .frame(width: contentWidth, height: segmentsRowHeight, alignment: .topLeading)
        .background(
            Rectangle()
                .fill(Color.white.opacity(0.025))
        )
    }

    private func segmentClip(index: Int, start: Double) -> some View {
        let savedScene = RecordingScene(snapshot: sceneEvents[index].scene)
            ?? RecordingScene(settings: RecordingSettings())
        let scene = EditorSceneTimelineSceneResolver.scene(request: .init(
            savedScene: savedScene,
            eventIndex: index,
            draftScene: draftScene,
            draftEventIndex: draftSceneEventIndex
        ))
        let isSelected = selection == .segment(index)
        let isActive = activeSegmentIndex == index
        return EditorSceneTimelineItem(
            scene: scene,
            canvasAspectRatio: captureLayout.aspectRatio,
            isSelected: isSelected,
            isActive: isActive
        )
        .contentShape(.rect(cornerRadius: 6))
        .modifier(TimelineClipHover(cornerRadius: 6))
        .onTapGesture {
            selection = .segment(index)
            onSeek(min(duration, start + 0.001))
            onSeekEnded()
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

    private func assetTrack(_ asset: EditorAsset, pxPerSecond: CGFloat, contentWidth: CGFloat) -> some View {
        let rowHeight: CGFloat = asset.isVideo ? videoRowHeight : audioRowHeight
        let clipSeconds = trackDuration(for: asset)
        let width = max(14, CGFloat(clipSeconds) * pxPerSecond)
        let frames = library.filmstrips[asset.id] ?? []
        let requestedFrameCount = EditorFilmstripLayout.requestedFrameCount(width: width)
        let filmstripTaskID = EditorFilmstripTaskID(
            assetID: asset.id,
            requestedFrameCount: requestedFrameCount,
            availableFrameCount: frames.count
        )
        let isSelected = selection == .asset(asset.id)
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)

        return ZStack {
            shape.fill(asset.tint.opacity(0.18))
            if asset.isVideo {
                EditorFilmstrip(frames: frames, width: width)
            } else {
                waveform(values: library.waveforms[asset.id] ?? [], tint: asset.tint)
            }
            if isSelected {
                shape.strokeBorder(BlitzUI.mint, lineWidth: 2)
            }
        }
        .overlay(alignment: asset.isVideo ? .topLeading : .leading) {
            clipLabel(asset.title, isSelected: isSelected)
        }
        .clipShape(shape)
        .overlay {
            shape
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .contentShape(shape)
        .modifier(TimelineClipHover(cornerRadius: 5))
        .onTapGesture { selection = .asset(asset.id) }
        .opacity(hiddenAssetIDs.contains(asset.id) || mutedAssetIDs.contains(asset.id) ? 0.35 : 1)
        .frame(width: width, height: rowHeight)
        .frame(width: contentWidth, height: rowHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.022))
        )
        .animation(.easeOut(duration: 0.14), value: isSelected)
        .task(id: filmstripTaskID) {
            guard asset.isVideo, frames.count < requestedFrameCount else { return }
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
        let availableFrameCount: Int
    }

    private struct EditorFilmstrip: View {
        let frames: [CGImage]
        let width: CGFloat

        var body: some View {
            GeometryReader { proxy in
                let layout = EditorFilmstripLayout.make(request: .init(
                    width: width,
                    availableFrameCount: frames.count
                ))
                HStack(spacing: 0) {
                    ForEach(Array(layout.frameIndices.enumerated()), id: \.offset) { _, frameIndex in
                        Image(decorative: frames[frameIndex], scale: 1)
                            .resizable()
                            .scaledToFill()
                            .frame(width: layout.cellWidth, height: proxy.size.height)
                            .clipped()
                    }
                }
            }
        }
    }

    private func waveform(values: [Float], tint: Color) -> some View {
        Canvas { context, size in
            guard !values.isEmpty else {
                let line = CGRect(x: 0, y: size.height / 2 - 0.75, width: size.width, height: 1.5)
                context.fill(Path(roundedRect: line, cornerRadius: 0.75), with: .color(tint.opacity(0.4)))
                return
            }
            let slot = size.width / CGFloat(values.count)
            let barWidth = max(1, slot - 1)
            let maxHeight = size.height - 8
            for (index, value) in values.enumerated() {
                let height = max(1.5, CGFloat(value) * maxHeight)
                let x = CGFloat(index) * slot + (slot - barWidth) / 2
                let bar = CGRect(x: x, y: (size.height - height) / 2, width: barWidth, height: height)
                context.fill(Path(roundedRect: bar, cornerRadius: barWidth / 2), with: .color(tint.opacity(0.85)))
            }
        }
    }

    private func clipLabel(_ title: String, isSelected: Bool) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(isSelected ? BlitzUI.mint : .white.opacity(0.85))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.58), in: .rect(cornerRadius: 4))
            .padding(4)
    }


    private func playhead(pxPerSecond: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isPlaying)) { _ in
            let time = isPlaying ? liveTime() : playbackTime
            let x = CGFloat(min(max(time, 0), duration)) * pxPerSecond

            ZStack(alignment: .top) {
                Rectangle()
                    .fill(BlitzUI.mint)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                    .shadow(color: BlitzUI.mint.opacity(0.38), radius: 3)

                PlayheadHandle()
                    .fill(BlitzUI.mint)
                    .frame(width: 13, height: 16)
                    .overlay {
                        PlayheadHandle()
                            .stroke(Color.black.opacity(0.7), lineWidth: 1)
                    }

                Color.clear
                    .frame(width: 28)
                    .frame(maxHeight: .infinity)
                    .contentShape(.rect)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named(timelineContentSpace))
                            .onChanged { seek(toContentX: $0.location.x, pxPerSecond: pxPerSecond) }
                            .onEnded { _ in onSeekEnded() },
                        isEnabled: isInteractive
                    )
            }
            .frame(width: 28)
            .frame(maxHeight: .infinity, alignment: .top)
            .offset(x: x - 14)
            .opacity(isInteractive ? 1 : 0.4)
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

    private var trackAssets: [EditorAsset] {
        var rows = assets.filter { $0.exists && $0.isPlayable && $0.kind != .output }
        if let output = outputAsset, sceneEvents.isEmpty {
            rows.insert(output, at: 0)
        }
        return rows
    }

    private var contentSeconds: Double {
        let longestTrack = trackAssets
            .map(trackDuration)
            .max() ?? 0
        return max(duration, longestTrack)
    }

    private func trackDuration(for asset: EditorAsset) -> Double {
        EditorTimelineTrackDuration.resolve(.init(
            rawDuration: library.durations[asset.id],
            playbackDuration: duration
        ))
    }

    private var gutterRows: [(icon: String, title: String, height: CGFloat, asset: EditorAsset?)] {
        guard duration > 0 else { return [] }
        var rows: [(icon: String, title: String, height: CGFloat, asset: EditorAsset?)] = []
        if showsChaptersTrack {
            rows.append((icon: "text.quote", title: "Chapters", height: chaptersRowHeight, asset: nil))
        }
        if showsSegmentsTrack {
            rows.append((icon: BlitzSymbols.scenes, title: "Scenes", height: segmentsRowHeight, asset: nil))
        }
        for asset in trackAssets {
            rows.append((
                icon: asset.systemImage,
                title: asset.title,
                height: asset.isVideo ? videoRowHeight : audioRowHeight,
                asset: asset
            ))
        }
        return rows
    }

    private var contentHeight: CGFloat {
        var height = rulerHeight
        if duration > 0 {
            if showsChaptersTrack {
                height += 6 + chaptersRowHeight
            }
            if showsSegmentsTrack {
                height += 6 + segmentsRowHeight
            }
            for asset in trackAssets {
                height += 6 + (asset.isVideo ? videoRowHeight : audioRowHeight)
            }
            if !showsSegmentsTrack && trackAssets.isEmpty {
                height += 6 + 56
            }
        }
        return height
    }


    private func seek(toContentX x: CGFloat, pxPerSecond: CGFloat) {
        guard duration > 0, pxPerSecond > 0 else { return }
        onSeek(min(max(0, Double(x / pxPerSecond)), duration))
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

    private let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)

    var body: some View {
        GeometryReader { proxy in
            let presentation = EditorSceneTimelineItemPresentation.make(scene: scene)
            HStack(spacing: 6) {
                EditorSceneTimelineThumbnail(scene: scene, canvasAspectRatio: canvasAspectRatio)
                    .frame(width: thumbnailWidth(for: proxy.size.width), height: 34)

                if proxy.size.width >= 86 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(presentation.title)
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)

                        if let detail = presentation.detail {
                            Text(detail)
                                .font(.system(size: 7.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.52))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(4)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
        }
        .background(shape.fill(layoutSegmentFill.opacity(isActive ? 1 : 0.68)))
        .overlay {
            shape.strokeBorder(
                isSelected ? BlitzUI.mint : Color.white.opacity(isActive ? 0.16 : 0.07),
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
        .animation(.easeOut(duration: 0.14), value: isSelected)
        .animation(.easeOut(duration: 0.14), value: isActive)
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
        Button(action: action) {
            HStack(spacing: 6) {
                BlitzSymbol(configuration: .init(name: systemName, size: 16))
                Text(title)
            }
            .frame(height: 28)
        }
        .blitzGlassButton()
        .disabled(isDisabled)
        .pointingHandCursor()
    }
}

private struct TimelineTransportControls: View {
    let isPlaying: Bool
    let isDisabled: Bool
    let onPrevious: () -> Void
    let onTogglePlayback: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            TimelineTransportButton(
                systemName: "backward.end.fill",
                help: "Previous segment",
                isDisabled: isDisabled,
                action: onPrevious
            )

            TimelinePlayPauseButton(
                isPlaying: isPlaying,
                isDisabled: isDisabled,
                action: onTogglePlayback
            )

            TimelineTransportButton(
                systemName: "forward.end.fill",
                help: "Next segment",
                isDisabled: isDisabled,
                action: onNext
            )
        }
    }
}

private struct TimelineTransportButton: View {
    let systemName: String
    let help: String
    let isDisabled: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(.white.opacity(isDisabled ? 0.24 : (isHovering ? 0.94 : 0.62)))
                .frame(width: 40, height: 40)
                .background(
                    Color.white.opacity(isHovering && !isDisabled ? 0.08 : 0),
                    in: .rect(cornerRadius: 9)
                )
                .contentShape(.rect(cornerRadius: 9))
        }
        .buttonStyle(TimelinePressButtonStyle())
        .disabled(isDisabled)
        .onHover { isHovering = $0 && !isDisabled }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .pointingHandCursor()
        .help(help)
    }
}

private struct TimelinePlayPauseButton: View {
    let isPlaying: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: "play.fill")
                    .offset(x: 1)
                    .opacity(isPlaying ? 0 : 1)
                    .scaleEffect(isPlaying ? 0.25 : 1)
                    .blur(radius: isPlaying ? 4 : 0)

                Image(systemName: "pause.fill")
                    .opacity(isPlaying ? 1 : 0)
                    .scaleEffect(isPlaying ? 1 : 0.25)
                    .blur(radius: isPlaying ? 0 : 4)
            }
            .font(.system(size: 12.5, weight: .bold))
            .foregroundStyle(.white.opacity(isDisabled ? 0.3 : 0.94))
            .frame(width: 42, height: 40)
            .background(BlitzUI.selectedFill, in: .rect(cornerRadius: 9))
            .contentShape(.rect(cornerRadius: 9))
        }
        .buttonStyle(TimelinePressButtonStyle())
        .disabled(isDisabled)
        .animation(.easeOut(duration: 0.16), value: isPlaying)
        .pointingHandCursor()
        .help(isPlaying ? "Pause (Space)" : "Play (Space or L)")
    }
}

private struct TimelinePlaybackRateSelector: View {
    let playbackRate: EditorPlaybackRate
    let isDisabled: Bool
    let onSelect: (EditorPlaybackRate) -> Void

    var body: some View {
        HStack(spacing: 1) {
            ForEach(EditorPlaybackRate.allCases, id: \.rawValue) { rate in
                Button {
                    onSelect(rate)
                } label: {
                    Text(rate.displayName)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(
                            playbackRate == rate
                                ? BlitzUI.primaryText
                                : Color.white.opacity(isDisabled ? 0.24 : 0.56)
                        )
                        .frame(width: 38, height: 32)
                        .contentShape(.rect(cornerRadius: 9))
                }
                .buttonStyle(BlitzSelectionButtonStyle(isSelected: playbackRate == rate))
                .accessibilityAddTraits(playbackRate == rate ? [.isSelected] : [])
                .disabled(isDisabled)
                .pointingHandCursor()
                .help("Play at \(rate.displayName)")
            }
        }
        .blitzTabGroup()
        .animation(.easeOut(duration: 0.14), value: playbackRate)
        .help("Playback speed (L)")
    }
}

private struct TimelineControlDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 2)
    }
}

private struct TimelinePressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
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

private struct TimelineClipHover: ViewModifier {
    let cornerRadius: CGFloat

    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(isHovering ? 0.32 : 0), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .pointingHandCursor()
    }
}
