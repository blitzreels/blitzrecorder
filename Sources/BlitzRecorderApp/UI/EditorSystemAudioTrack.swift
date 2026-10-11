import SwiftUI

struct EditorAudioChunk: Identifiable {
    let region: EditorAudioVolumeRegion
    let start: Double
    let end: Double
    var id: String { "\(region.start)-\(region.end)" }

    struct Request {
        let ranges: [EditorTimeRange]
        let sourceOffset: Double
        let duration: Double
        let projection: EditorTimelineProjection
    }

    static func resolve(_ request: Request) -> [Self] {
        request.ranges.compactMap { range in
            let start = max(0, range.start + request.sourceOffset)
            let end = min(request.duration, range.end + request.sourceOffset)
            let outputStart = request.projection.displayTime(start)
            let outputEnd = request.projection.displayTime(end)
            guard end > start, ((outputEnd - outputStart) * 600).rounded() >= 1 else { return nil }
            return .init(region: .init(source: .systemAudio, start: start, end: end, volume: 1),
                start: outputStart, end: outputEnd)
        }
    }
}

struct EditorSystemAudioChunk: View {
    struct Configuration {
        let chunk: EditorAudioChunk
        let waveform: EditorAudioWaveform?
        let sourceDuration: Double
        let sourceOffset: Double
        let projection: EditorTimelineProjection
        let pixelsPerSecond: CGFloat
        let viewport: EditorTimelineViewport
        let height: CGFloat
        let playback: EditorPlaybackController
        let onCommit: (EditorAudioVolumeRegion) -> Bool
    }
    let configuration: Configuration
    @State private var showsVolume = false

    private var chunk: EditorAudioChunk { configuration.chunk }
    private var volume: Double { configuration.playback.audioLevels.regionVolume(chunk.region) }
    private var start: CGFloat { max(configuration.viewport.lowerBound, CGFloat(chunk.start) * configuration.pixelsPerSecond) }
    private var end: CGFloat { min(configuration.viewport.upperBound, CGFloat(chunk.end) * configuration.pixelsPerSecond) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5).fill(BlitzUI.trackSystemAudio.opacity(0.18))
            EditorTimelineMediaCanvas(frames: [], waveform: configuration.waveform, isVideo: false,
                tint: BlitzUI.trackSystemAudio, projection: configuration.projection,
                sourceDuration: configuration.sourceDuration, sourceOffset: configuration.sourceOffset,
                pixelsPerSecond: configuration.pixelsPerSecond, viewport: .init(lowerBound: start, upperBound: end))
                .offset(x: -start)
            if end - start >= 65 {
                Text("\(Int((volume * 100).rounded()))%")
                    .font(BlitzType.footnote.monospacedDigit())
                    .padding(4)
                    .background(BlitzUI.panelBackground.opacity(0.85), in: .rect(cornerRadius: 4))
                    .padding(3)
            }
        }
        .frame(width: max(1, end - start), height: configuration.height)
        .clipShape(.rect(cornerRadius: 5))
        .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(showsVolume ? BlitzUI.mint : BlitzUI.trackSystemAudio, lineWidth: 1) }
        .contentShape(.rect)
        .pointingHandCursor()
        .onTapGesture { showsVolume = true }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Mac audio chunk, \(SilenceTime.label(chunk.end - chunk.start))")
        .accessibilityValue("\(Int((volume * 100).rounded())) percent")
        .accessibilityAction { showsVolume = true }
        .help("Mac audio · \(EditorPlaybackPosition.display(chunk.start))–\(EditorPlaybackPosition.display(chunk.end)). Click to adjust this chunk’s volume.")
        .popover(isPresented: $showsVolume, arrowEdge: .top) {
            EditorAudioChunkVolume(configuration: configuration)
                .padding(16).frame(width: 280)
        }
        .offset(x: start)
    }
}

private struct EditorAudioChunkVolume: View {
    let configuration: EditorSystemAudioChunk.Configuration
    @State private var original: EditorAudioLevels?

    private var volume: Double { configuration.playback.audioLevels.regionVolume(configuration.chunk.region) }
    private func region(_ volume: Double) -> EditorAudioVolumeRegion {
        let source = configuration.chunk.region
        return .init(source: source.source, start: source.start, end: source.end, volume: volume)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mac audio chunk").font(BlitzType.section)
            Text("\(EditorPlaybackPosition.display(configuration.chunk.start))–\(EditorPlaybackPosition.display(configuration.chunk.end))")
                .font(BlitzType.caption.monospacedDigit()).foregroundStyle(BlitzUI.secondaryText)
            HStack {
                Text("Volume")
                Spacer()
                Text("\(Int((volume * 100).rounded()))%").monospacedDigit()
            }.font(BlitzType.label)
            Slider(value: Binding(get: { volume }, set: { value in
                let before = configuration.playback.audioLevels
                configuration.playback.setAudioRegionVolume(region(value))
                if original == nil, !configuration.onCommit(region(value)) {
                    configuration.playback.restoreAudioLevels(before)
                }
            }), in: 0...1, onEditingChanged: { editing in
                if editing { original = configuration.playback.audioLevels }
                else { commit() }
            })
            .accessibilityLabel("Mac audio chunk volume")
            Text("Only this chunk. Saved for playback and export.")
                .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
        }
        .onDisappear { commit() }
    }

    private func commit() {
        guard let original else { return }
        if original != configuration.playback.audioLevels, !configuration.onCommit(region(volume)) {
            configuration.playback.restoreAudioLevels(original)
        }
        self.original = nil
    }
}

extension EditorTimelineView {
    func systemAudioTrack(_ request: AssetTrackRequest) -> some View {
        let sourceOffset = (project?.sourceOffset(forRole: request.asset.kind.rawValue) ?? 0)
            - (project?.timelineTrimOffsetSeconds ?? 0)
        let state = library.audioActivity[request.asset.id]
        let chunks = EditorAudioChunk.resolve(.init(ranges: state?.ranges ?? [],
            sourceOffset: sourceOffset, duration: duration, projection: projection))
        return ZStack(alignment: .leading) {
            Color.clear
            ForEach(chunks.filter { CGFloat($0.end) * request.pxPerSecond > request.viewport.lowerBound
                && CGFloat($0.start) * request.pxPerSecond < request.viewport.upperBound }) { chunk in
                EditorSystemAudioChunk(configuration: .init(chunk: chunk,
                    waveform: library.timelineWaveforms[request.asset.id],
                    sourceDuration: library.durations[request.asset.id] ?? duration,
                    sourceOffset: sourceOffset, projection: projection, pixelsPerSecond: request.pxPerSecond,
                    viewport: request.viewport, height: rowHeight(for: request.asset), playback: playback,
                    onCommit: onChangeAudioRegion))
            }
            if chunks.isEmpty {
                EditorSystemAudioStatus(state: state, retry: {
                    Task { await library.retryAudioActivity(request.asset) }
                })
                .padding(.leading, 8).offset(x: request.viewport.lowerBound)
            }
        }
        .frame(width: request.contentWidth, height: rowHeight(for: request.asset))
        .opacity(isTrackOff(request.asset) ? 0.3 : 1)
        .disabled(!isInteractive)
    }
}

struct EditorSystemAudioStatus: View {
    let state: EditorAudioActivity.State?
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            switch state {
            case .failed(let message):
                Label("Mac audio analysis failed", systemImage: "exclamationmark.triangle")
                    .help(message)
                Button("Retry", action: retry).blitzButton(.secondary).controlSize(.mini)
                    .accessibilityLabel("Retry Mac audio analysis")
            case .ready(let ranges):
                Text(ranges.isEmpty ? "No Mac audio detected" : "No Mac audio in kept footage")
            case .loading, nil:
                ProgressView().controlSize(.mini)
                Text("Finding Mac audio…")
            }
        }
        .font(BlitzType.footnote).foregroundStyle(BlitzUI.secondaryText)
        .fixedSize()
    }
}

extension RecorderViewModel {
    func changeEditorAudioRegion(_ region: EditorAudioVolumeRegion) -> Bool {
        guard var state = editorProject?.editorState else { return false }
        var levels = state.audioLevels ?? .unity
        levels.setRegion(region)
        state.audioLevels = levels == .unity ? nil : levels
        return applyProjectEditorState(.init(editorState: state, actionName: "Change Audio Chunk Volume"))
    }
}
