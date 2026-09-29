import SwiftUI

extension EditorTimelineView {
    var gutterHeading: some View {
        HStack(spacing: 0) {
            Button {
                cancelTimelineDrag()
                if case .asset = selection { selection = nil }
                showsSourceTracks.toggle()
            } label: {
                Label("Source tracks", systemImage: showsSourceTracks ? "rectangle.stack.fill" : "rectangle.stack")
            }
            .blitzButton(.quiet)
            .controlSize(.mini)
            .accessibilityLabel(showsSourceTracks ? "Collapse video tracks" : "Expand video tracks")
            .accessibilityValue("\(sourceAssets.filter { !$0.isAudio }.count) tracks")
            .help(showsSourceTracks ? "Hide the Screen and Camera tracks. Audio waveforms stay visible."
                : "Show the Screen and Camera tracks. Audio waveforms stay visible.")
            Spacer(minLength: 0)
        }
        .padding(.leading, 4)
        .padding(.trailing, 2)
        .frame(width: gutterWidth, height: rulerHeight)
    }

    var gutterColumn: some View {
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
                let isOff = row.asset.map(isTrackOff) ?? false
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

    var emptyHint: some View {
        Text("No editable tracks in this recording.")
            .font(BlitzType.label)
            .foregroundStyle(BlitzUI.secondaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
    }

    struct RulerRequest {
        let pxPerSecond: CGFloat
        let width: CGFloat
        let viewport: EditorTimelineViewport
    }

    func ruler(_ request: RulerRequest) -> some View {
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
                    with: .color(major ? BlitzUI.tertiaryText : BlitzUI.selectedFill)
                )
                if major {
                    let title = EditorTimelineRuler.label(.init(time: time, interval: interval))
                    let label = Text(title)
                        .font(BlitzType.footnote.monospaced())
                        .foregroundStyle(BlitzUI.secondaryText)
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
}
