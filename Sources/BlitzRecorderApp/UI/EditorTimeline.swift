import SwiftUI

private let timelineContentSpace = "EditorTimelineContent"

@MainActor
struct EditorTimelineView: View {
    let project: RecordingProject?
    let assets: [EditorAsset]
    let library: EditorMediaLibrary
    let duration: Double
    let playbackTime: Double
    let liveTime: () -> Double
    let isPlaying: Bool
    @Binding var selection: EditorSelection?
    let onSeek: (Double) -> Void
    let onSeekEnded: () -> Void
    let isInteractive: Bool
    let hiddenAssetIDs: Set<String>
    let mutedAssetIDs: Set<String>
    let toggleableAssetIDs: Set<String>
    let onToggleTrack: (EditorAsset) -> Void

    @State private var zoomLevel: Double = 1

    private let gutterWidth: CGFloat = 112
    private let rulerHeight: CGFloat = 20
    private let chaptersRowHeight: CGFloat = 30
    private let segmentsRowHeight: CGFloat = 46

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            GeometryReader { proxy in
                timelineBody(viewportWidth: proxy.size.width)
            }
            .frame(height: contentHeight)
        }
        .padding(12)
        .background(BlitzUI.quietFill, in: .rect(cornerRadius: 10))
    }


    private var header: some View {
        HStack(spacing: 10) {
            BlitzUI.sectionLabel("Timeline", icon: "timeline.selection")

            Text("\(formatTime(playbackTime)) / \(formatTime(duration))")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.58))

            Spacer(minLength: 0)

            TimelineZoomButton(systemName: "arrow.left.and.right.square", help: "Fit timeline", isDisabled: zoomLevel == 1) {
                zoomLevel = 1
            }

            HStack(spacing: 6) {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                Slider(value: $zoomLevel, in: 1...12)
                    .controlSize(.mini)
                    .frame(width: 110)
                    .help("Timeline zoom")
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }


    private func timelineBody(viewportWidth: CGFloat) -> some View {
        let trackViewport = max(viewportWidth - gutterWidth - 8, 40)
        let pxPerSecond = trackViewport / CGFloat(max(duration, 0.5)) * CGFloat(zoomLevel)
        let contentWidth = max(CGFloat(contentSeconds) * pxPerSecond, trackViewport)

        return HStack(alignment: .top, spacing: 8) {
            gutterColumn

            ScrollView(.horizontal) {
                ZStack(alignment: .topLeading) {
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
                    Image(systemName: row.icon)
                        .font(.system(size: 10, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
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
                .padding(.leading, 2)
                .frame(width: gutterWidth, height: row.height)
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
                .frame(width: 20, height: 18)
                .contentShape(.rect(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help("\(verb) \(asset.title)")
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
                        .font(.system(size: 8.5, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                    context.draw(label, at: CGPoint(x: x + 3.5, y: size.height - 11), anchor: .leading)
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
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
    }

    private func chapterClip(_ chapter: RecordingProject.ChapterSnapshot, start: Double) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(BlitzUI.trackCamera.opacity(0.22))
            .overlay(alignment: .leading) {
                Text(chapter.title)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)
                    .padding(.horizontal, 7)
            }
            .contentShape(.rect(cornerRadius: 7))
            .modifier(TimelineClipHover(cornerRadius: 7))
            .onTapGesture {
                onSeek(start)
                onSeekEnded()
            }
    }


    private func segmentsTrack(pxPerSecond: CGFloat, contentWidth: CGFloat) -> some View {
        let events = sceneEvents
        let frames = outputAsset.flatMap { library.filmstrips[$0.id] } ?? []

        return ZStack(alignment: .topLeading) {
            ForEach(events.indices, id: \.self) { index in
                let start = min(max(events[index].time, 0), duration)
                let end = index + 1 < events.count
                    ? min(max(events[index + 1].time, start), duration)
                    : duration
                let gap: CGFloat = index + 1 < events.count ? 2 : 0
                let width = max(14, CGFloat(end - start) * pxPerSecond - gap)

                segmentClip(index: index, start: start, end: end, frames: frames)
                    .frame(width: width, height: segmentsRowHeight)
                    .offset(x: CGFloat(start) * pxPerSecond)
            }
        }
        .frame(width: contentWidth, height: segmentsRowHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
    }

    private func segmentClip(index: Int, start: Double, end: Double, frames: [CGImage]) -> some View {
        let isSelected = selection == .segment(index)
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)

        return ZStack {
            shape.fill(BlitzUI.trackScreen.opacity(0.20))
            if !frames.isEmpty, duration > 0 {
                filmstrip(frames: frameSlice(frames, start: start, end: end))
            }
            if isSelected {
                shape.fill(Color.white.opacity(0.14))
            }
        }
        .overlay(alignment: .topLeading) {
            clipLabel(mixTitle(for: index), isSelected: isSelected)
        }
        .clipShape(shape)
        .contentShape(shape)
        .modifier(TimelineClipHover(cornerRadius: 7))
        .onTapGesture { selection = .segment(index) }
    }

    private func frameSlice(_ frames: [CGImage], start: Double, end: Double) -> [CGImage] {
        guard duration > 0, !frames.isEmpty else { return [] }
        let count = Double(frames.count)
        let lo = min(frames.count - 1, max(0, Int(floor(start / duration * count))))
        let hi = min(frames.count, max(lo + 1, Int(ceil(end / duration * count))))
        return Array(frames[lo..<hi])
    }

    private func mixTitle(for index: Int) -> String {
        guard sceneEvents.indices.contains(index) else { return "Scene" }
        return EditorSceneTitle.title(for: sceneEvents[index].scene)
    }


    private func assetTrack(_ asset: EditorAsset, pxPerSecond: CGFloat, contentWidth: CGFloat) -> some View {
        let rowHeight: CGFloat = asset.isVideo ? 40 : 32
        let clipSeconds = library.durations[asset.id] ?? duration
        let width = max(14, CGFloat(clipSeconds) * pxPerSecond)
        let isSelected = selection == .asset(asset.id)
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)

        return ZStack {
            shape.fill(asset.tint.opacity(0.18))
            if asset.isVideo {
                filmstrip(frames: library.filmstrips[asset.id] ?? [])
            } else {
                waveform(values: library.waveforms[asset.id] ?? [], tint: asset.tint)
            }
            if isSelected {
                shape.fill(Color.white.opacity(0.14))
            }
        }
        .overlay(alignment: asset.isVideo ? .topLeading : .leading) {
            clipLabel(asset.title, isSelected: isSelected)
        }
        .clipShape(shape)
        .contentShape(shape)
        .modifier(TimelineClipHover(cornerRadius: 7))
        .onTapGesture { selection = .asset(asset.id) }
        .opacity(hiddenAssetIDs.contains(asset.id) || mutedAssetIDs.contains(asset.id) ? 0.35 : 1)
        .frame(width: width, height: rowHeight)
        .frame(width: contentWidth, height: rowHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
    }

    private func filmstrip(frames: [CGImage]) -> some View {
        GeometryReader { proxy in
            let cellWidth = proxy.size.width / CGFloat(max(frames.count, 1))
            HStack(spacing: 0) {
                ForEach(frames.indices, id: \.self) { index in
                    Image(decorative: frames[index], scale: 1)
                        .resizable()
                        .scaledToFill()
                        .frame(width: cellWidth, height: proxy.size.height)
                        .clipped()
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
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(isSelected ? BlitzUI.mint : .white.opacity(0.85))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.45), in: Capsule())
            .padding(4)
    }


    private func playhead(pxPerSecond: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isPlaying)) { _ in
            let time = isPlaying ? liveTime() : playbackTime
            let x = CGFloat(min(max(time, 0), duration)) * pxPerSecond

            ZStack(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.92))
                    .frame(width: 1.5)
                    .frame(maxHeight: .infinity)

                PlayheadHandle()
                    .fill(BlitzUI.mint)
                    .frame(width: 11, height: 14)

                Color.clear
                    .frame(width: 18)
                    .frame(maxHeight: .infinity)
                    .contentShape(.rect)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named(timelineContentSpace))
                            .onChanged { seek(toContentX: $0.location.x, pxPerSecond: pxPerSecond) }
                            .onEnded { _ in onSeekEnded() },
                        isEnabled: isInteractive
                    )
            }
            .frame(width: 18)
            .frame(maxHeight: .infinity, alignment: .top)
            .offset(x: x - 9)
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
            .compactMap { library.durations[$0.id] }
            .max() ?? 0
        return max(duration, longestTrack)
    }

    private var gutterRows: [(icon: String, title: String, height: CGFloat, asset: EditorAsset?)] {
        guard duration > 0 else { return [] }
        var rows: [(icon: String, title: String, height: CGFloat, asset: EditorAsset?)] = []
        if showsChaptersTrack {
            rows.append((icon: "text.quote", title: "Chapters", height: chaptersRowHeight, asset: nil))
        }
        if showsSegmentsTrack {
            rows.append((icon: "film", title: "Scenes", height: segmentsRowHeight, asset: nil))
        }
        for asset in trackAssets {
            rows.append((
                icon: asset.systemImage,
                title: asset.title,
                height: asset.isVideo ? 40 : 32,
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
                height += 6 + (asset.isVideo ? 40 : 32)
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

private struct TimelineZoomButton: View {
    let systemName: String
    let help: String
    let isDisabled: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        let button = Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(isDisabled ? 0.22 : (isHovering ? 0.9 : 0.55)))
                .frame(width: 22, height: 20)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovering = $0 && !isDisabled }
        .help(help)

        if isDisabled {
            button
        } else {
            button.pointingHandCursor()
        }
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
                if isHovering {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
            .onHover { isHovering = $0 }
            .pointingHandCursor()
    }
}
