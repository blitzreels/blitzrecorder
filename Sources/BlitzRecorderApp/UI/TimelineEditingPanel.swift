import SwiftUI

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
    @AppStorage(BlitzPreviewPreferences.animatePreviewsKey) private var animatePreviews = true
    @State private var magnification = 1.7
    @State private var cursorScale = 1.5
    @State private var cursorTrack: RecordingCursorTrack?
    @State private var message: String?
    @State private var messageIsError = false

    init(configuration: Configuration) {
        vm = configuration.vm
        playback = configuration.playback
        scenePreview = configuration.preview
        selectedKeyframeID = configuration.selectedKeyframeID
    }

    private var edits: TimelineEdits { vm.lastExportedProject?.edits ?? .empty }
    private var hasCursorClicks: Bool { cursorTrack?.samples.contains(where: \.clicked) == true }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let id = selectedKeyframeID.wrappedValue,
                       let keyframe = edits.zoom.keyframes.first(where: { $0.id == id }) {
                        EditorZoomPointInspector(configuration: .init(
                            vm: vm, playback: playback, point: keyframe, selection: selectedKeyframeID
                        ))
                        Divider()
                    }
                    zoomContent
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            Divider().overlay(.white.opacity(0.05))
            VStack(alignment: .leading, spacing: 8) {
                if let message {
                    Text(message).font(.system(size: 11)).foregroundStyle(
                        messageIsError ? BlitzUI.recordRed : BlitzUI.secondaryText
                    )
                    .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.updatesFrequently)
                }
                if hasCursorClicks && edits.zoom.isActive {
                    Button("Update cursor zoom", action: generateZoom)
                        .blitzButton(.accent)
                }
                Toggle("Animate previews", isOn: $animatePreviews)
                    .toggleStyle(.blitzCheckbox)
                    .controlSize(.small)
                    .help("Animate the setting thumbnails on hover. This does not change your video or exports.")
            }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BlitzUI.projectLibraryBackground)
        .foregroundStyle(BlitzUI.primaryText)
        .buttonStyle(BlitzButtonStyle(.secondary))
        .tint(BlitzUI.mint)
        .onAppear {
            magnification = edits.zoom.isEmpty ? 1.7 : edits.zoom.intensity
            cursorScale = edits.cursorStyle.scale
        }
        .task(id: vm.lastExportedProject?.projectPath) {
            cursorTrack = nil
            if let project = vm.lastExportedProject {
                let url = URL(fileURLWithPath: project.takeDirectoryPath).appendingPathComponent("cursor-track.json")
                if let data = try? Data(contentsOf: url) {
                    cursorTrack = try? JSONDecoder().decode(RecordingCursorTrack.self, from: data)
                }
            }
        }
        .onChange(of: edits.cursorStyle.scale) { _, value in cursorScale = value }
        .onChange(of: edits.zoom.intensity) { _, value in magnification = value }
    }

    private var zoomContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            cursorContent
            Divider()
            if !hasCursorClicks {
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

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Zoom amount")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(BlitzUI.secondaryText)
                            Spacer()
                            Text("\(magnification, specifier: "%.1f")×")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                        }
                        Slider(value: $magnification, in: 1.3...2.5, step: 0.1)
                            .accessibilityLabel("Cursor zoom amount")
                        HStack {
                            Text("Subtle")
                            Spacer()
                            Text("Close-up")
                        }.font(.system(size: 11)).foregroundStyle(BlitzUI.secondaryText)
                    }
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
            Text("Cursor").font(.headline)
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
                HStack(spacing: 12) {
                    illustratedLabel(.init(
                        title: "Cursor size", detail: "Keep the pointer easy to follow.",
                        effect: .cursorSize(cursorScale)
                    ))
                    Text("\(cursorScale, specifier: "%.1f")×")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .fixedSize()
                }
                Slider(value: $cursorScale, in: 0.75...3, step: 0.25, onEditingChanged: { editing in
                    guard !editing else { return }
                    var updated = edits
                    updated.cursorStyle.scale = cursorScale
                    apply(.init(edits: updated, actionName: "Resize Cursor"))
                }).accessibilityLabel("Cursor size")

            } else {
                Text("This take has its original cursor. Record a new display capture with source files saved to adjust its look.")
                    .foregroundStyle(BlitzUI.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.font(.system(size: 12))
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
            Image(systemName: request.symbol).font(.system(size: 26, weight: .light)).foregroundStyle(
                BlitzUI.secondaryText)
            Text(request.title).font(.system(size: 13, weight: .semibold))
            Text(request.detail).font(.system(size: 11)).foregroundStyle(BlitzUI.secondaryText)
                .multilineTextAlignment(.center).frame(maxWidth: 340)
        }.frame(maxWidth: .infinity).padding(.vertical, 26)
            .background(BlitzUI.cardFill, in: .rect(cornerRadius: 12))
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
