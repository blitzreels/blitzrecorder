import SwiftUI

@MainActor @Observable
final class EditorCursorTrackCache {
    enum State: Equatable {
        case loading
        case missing
        case loaded
    }

    static let shared = EditorCursorTrackCache()

    private(set) var state: State = .missing
    private(set) var track: RecordingCursorTrack?
    private(set) var hasClicks = false
    @ObservationIgnored private var fingerprint: MediaFileFingerprint?
    @ObservationIgnored private var directory: String?
    @ObservationIgnored private var task: Task<Void, Never>?

    func prepare(directory: String) {
        let url = URL(fileURLWithPath: directory).appendingPathComponent("cursor-track.json")
        let current = MediaFileFingerprint(url: url)
        guard directory != self.directory || current != fingerprint else { return }
        task?.cancel()
        self.directory = directory
        fingerprint = current
        track = nil
        hasClicks = false
        guard current != nil else {
            state = .missing
            return
        }
        state = .loading
        task = Task { [weak self] in
            let (decoded, clicks) = await Task.detached(priority: .userInitiated) {
                let track = (try? Data(contentsOf: url))
                    .flatMap { try? JSONDecoder().decode(RecordingCursorTrack.self, from: $0) }
                return (track, track?.samples.contains(where: \.clicked) == true)
            }.value
            guard !Task.isCancelled, let self, self.directory == directory else { return }
            self.track = decoded
            self.hasClicks = clicks
            self.state = decoded == nil ? .missing : .loaded
        }
    }
}

struct TimelineEditingPanel: View {
    struct Configuration {
        let vm: RecorderViewModel
        let playback: EditorPlaybackController
        let preview: BlitzScenePreview
        let selectedKeyframeID: Binding<UUID?>
    }

    @Bindable var vm: RecorderViewModel
    let playback: EditorPlaybackController
    let scenePreview: BlitzScenePreview
    let selectedKeyframeID: Binding<UUID?>
    @State private var magnification = 1.7
    @State private var cursorScale = 1.5
    private let cursorTracks = EditorCursorTrackCache.shared
    @State private var message: String?
    @State private var messageIsError = false

    init(configuration: Configuration) {
        vm = configuration.vm
        playback = configuration.playback
        scenePreview = configuration.preview
        selectedKeyframeID = configuration.selectedKeyframeID
    }

    private var edits: TimelineEdits { vm.lastExportedProject?.edits ?? .empty }
    private var cursorTrack: RecordingCursorTrack? { cursorTracks.track }
    private var hasCursorClicks: Bool { cursorTracks.hasClicks }

    var body: some View {
        EditorInspectorPane(configuration: .init(
            title: "Motion",
            detail: "Zoom into your clicks and smooth the cursor.",
            showsFooter: message != nil || (hasCursorClicks && edits.zoom.isActive),
            content: {
                VStack(alignment: .leading, spacing: EditorInspectorMetrics.sectionSpacing) {
                    if let id = selectedKeyframeID.wrappedValue,
                       let keyframe = edits.zoom.keyframes.first(where: { $0.id == id }) {
                        EditorZoomPointInspector(configuration: .init(
                            vm: vm, playback: playback, point: keyframe, selection: selectedKeyframeID
                        ))
                        Rectangle().fill(BlitzUI.separator).frame(height: 1)
                    }
                    zoomContent
                }
            },
            footer: {
                if let message {
                    Text(message).font(BlitzType.caption).foregroundStyle(
                        messageIsError ? BlitzUI.recordRed : BlitzUI.secondaryText
                    )
                    .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.updatesFrequently)
                }
                if hasCursorClicks && edits.zoom.isActive {
                    Button(action: generateZoom) {
                        Label("Update cursor zoom", systemImage: "arrow.triangle.2.circlepath").frame(maxWidth: .infinity)
                    }
                    .blitzButton(.accent)
                    .help("Rebuild zoom points from the clicks in this take")
                }
            }
        ))
        .onAppear {
            magnification = edits.zoom.isEmpty ? 1.7 : edits.zoom.intensity
            cursorScale = edits.cursorStyle.scale
        }
        .onAppear {
            if let project = vm.lastExportedProject { cursorTracks.prepare(directory: project.takeDirectoryPath) }
        }
        .onChange(of: edits.cursorStyle.scale) { _, value in cursorScale = value }
        .onChange(of: edits.zoom.intensity) { _, value in magnification = value }
    }

    private var zoomContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            cursorContent
            Divider()
            if cursorTracks.state == .loading {
                loadingPlaceholder
            } else if !hasCursorClicks {
                emptyState(.init(
                    symbol: "cursorarrow.motionlines",
                    title: cursorTrack == nil ? "No cursor track on this take" : "No clicks recorded",
                    detail: cursorTrack == nil
                        ? "Record a new take with screen sources saved to use automatic cursor zoom."
                        : "Click while recording to mark the moments for automatic screen zooms."
                ))
            }
            if hasCursorClicks || !edits.zoom.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: Binding(
                        get: { edits.zoom.isActive },
                        set: { setCursorZoomEnabled($0) }
                    )) {
                        illustratedLabel(.init(
                            title: "Cursor zoom",
                            detail: edits.zoom.isActive
                                ? "Zoom into clicks, then ease back."
                                : "Keep the screen steady.",
                            effect: .zoom(amount: magnification, enabled: edits.zoom.isActive)
                        ))
                    }
                    .toggleStyle(.blitzSwitch)
                    .help("Turn cursor zoom on or off for preview and export. Your zoom points are kept when off.")

                    BlitzInspectorSlider(configuration: .init(
                        title: "Amount",
                        value: $magnification,
                        range: 1.3...2.5,
                        step: 0.1,
                        valueLabel: String(format: "%.1f×", magnification),
                        onEditingChanged: { _ in },
                        onReset: { magnification = 1.7 }
                    ))
                    .accessibilityLabel("Cursor zoom amount")
                    .disabled(!edits.zoom.isActive)
                    .opacity(edits.zoom.isActive ? 1 : 0.45)
                }
            }
            Toggle(isOn: Binding(
                get: { edits.cameraFollowsZoom },
                set: { value in
                    var updated = edits
                    updated.cameraFollowsZoom = value
                    apply(.init(edits: updated, actionName: "Change Camera Motion"))
                })) {
                    illustratedLabel(.init(
                        title: "Camera follows zoom", detail: "Shrink the camera during close-ups.",
                        effect: .cameraFollow(edits.cameraFollowsZoom && edits.zoom.isActive)
                    ))
                }
                .toggleStyle(.blitzSwitch)
                .help("The picture-in-picture camera shrinks during screen zooms, then returns to its original size.")
        }
    }

    private var cursorContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cursor").font(BlitzType.section)
            if cursorTrack?.supportsPresentation == true {
                Toggle(isOn: Binding(
                    get: { edits.cursorStyle.smoothed },
                    set: { value in
                        var updated = edits
                        updated.cursorStyle.smoothed = value
                        apply(.init(edits: updated, actionName: "Change Cursor Smoothing"))
                    })) {
                        illustratedLabel(.init(
                            title: "Smooth movement", detail: "Soften the cursor’s path.",
                            effect: .smoothing(edits.cursorStyle.smoothed)
                        ))
                    }
                .toggleStyle(.blitzSwitch)
                Toggle(isOn: Binding(
                    get: { edits.cursorStyle.emphasizesClicks },
                    set: { value in
                        var updated = edits
                        updated.cursorStyle.emphasizesClicks = value
                        apply(.init(edits: updated, actionName: "Change Cursor Clicks"))
                    })) {
                        illustratedLabel(.init(
                            title: "Emphasize clicks", detail: "Highlight each click with a ring.",
                            effect: .clicks(edits.cursorStyle.emphasizesClicks)
                        ))
                    }
                .toggleStyle(.blitzSwitch)
                illustratedLabel(.init(
                    title: "Cursor size", detail: "Keep the pointer easy to follow.",
                    effect: .cursorSize(cursorScale)
                ))
                BlitzInspectorSlider(configuration: .init(
                    title: "Size",
                    value: $cursorScale,
                    range: 0.75...3,
                    step: 0.25,
                    valueLabel: String(format: "%.1f×", cursorScale),
                    onEditingChanged: { editing in
                        guard !editing else { return }
                        var updated = edits
                        updated.cursorStyle.scale = cursorScale
                        apply(.init(edits: updated, actionName: "Resize Cursor"))
                    },
                    onReset: {
                        cursorScale = 1.5
                        var updated = edits
                        updated.cursorStyle.scale = cursorScale
                        apply(.init(edits: updated, actionName: "Resize Cursor"))
                    }
                ))
                .accessibilityLabel("Cursor size")

            } else {
                Text("This take has its original cursor. Record a new display capture with source files saved to adjust its look.")
                    .foregroundStyle(BlitzUI.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.font(BlitzType.body)
    }

    private struct MotionLabel {
        let title: String
        let detail: String
        let effect: EditorMotionEffect
    }

    private func illustratedLabel(_ request: MotionLabel) -> some View {
        BlitzIllustratedLabel(configuration: .init(
            title: request.title,
            detail: request.detail,
            preview: { isAnimating in
                EditorMotionPreview(configuration: .init(
                    effect: request.effect, source: scenePreview, isAnimating: isAnimating
                ))
            }
        ))
    }

    private struct EmptyStateRequest {
        let symbol: String
        let title: String
        let detail: String
    }
    private func emptyState(_ request: EmptyStateRequest) -> some View {
        VStack(spacing: 10) {
            Image(systemName: request.symbol).font(BlitzType.glyph(26)).foregroundStyle(
                BlitzUI.secondaryText)
            Text(request.title).font(BlitzType.section)
            Text(request.detail).font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                .multilineTextAlignment(.center).frame(maxWidth: 340)
        }.frame(maxWidth: .infinity).padding(.vertical, 26)
            .background(BlitzUI.cardFill, in: .rect(cornerRadius: BlitzUI.cardRadius))
    }

    @discardableResult
    private func apply(_ request: EditorTimelineEditsChange) -> Bool {
        let map = TimelineTimeMap(
            takeDuration: TimelineTimeMap.time(playback.duration), cuts: request.edits.enabledCuts)
        guard map.outputDuration.seconds >= 0.1 else {
            message = "Keep at least a moment of the recording."
            messageIsError = true
            return false
        }
        playback.pauseForEditing()
        guard vm.applyTimelineEdits(request) else {
            message = vm.detailMessage
            messageIsError = true
            return false
        }
        message = nil
        messageIsError = false
        return true
    }

    private func setCursorZoomEnabled(_ enabled: Bool) {
        if enabled && edits.zoom.isEmpty {
            generateZoom()
            return
        }
        var updated = edits
        updated.zoom.isEnabled = enabled
        apply(.init(edits: updated, actionName: enabled ? "Enable Cursor Zoom" : "Disable Cursor Zoom"))
    }

    private var loadingPlaceholder: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: BlitzUI.controlRadius).fill(BlitzUI.controlFill).frame(width: 64, height: 40)
            VStack(alignment: .leading, spacing: 7) {
                RoundedRectangle(cornerRadius: 3).fill(BlitzUI.controlFill).frame(width: 110, height: 11)
                RoundedRectangle(cornerRadius: 3).fill(BlitzUI.quietFill).frame(width: 170, height: 9)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reading cursor clicks")
    }

    private func generateZoom() {
        guard let project = vm.lastExportedProject, let cursorTrack else { return }
        var updated = edits
        updated.zoom = CursorZoomPlanning.plan(
            .init(
                samples: cursorTrack.samples, duration: playback.duration,
                trimOffset: project.timelineTrimOffsetSeconds, cuts: edits.enabledCuts, magnification: magnification))
        guard apply(.init(edits: updated, actionName: "Follow Cursor")) else { return }
        message =
            updated.zoom.isEmpty
            ? "No usable clicks remain after your cuts." : "Cursor zoom saved. Preview before exporting."
    }

}
