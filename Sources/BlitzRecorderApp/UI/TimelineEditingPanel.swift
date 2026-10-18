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
            detail: "Zoom in on what matters and keep the cursor easy to follow.",
            showsFooter: false,
            content: {
                VStack(alignment: .leading, spacing: EditorInspectorMetrics.sectionSpacing) {
                    if let id = selectedKeyframeID.wrappedValue,
                       let keyframe = edits.zoom.keyframes.first(where: { $0.id == id }) {
                        EditorInspectorSection(configuration: .init(title: "Zoom point", content: {
                            EditorZoomPointInspector(configuration: .init(
                                vm: vm, playback: playback, point: keyframe, selection: selectedKeyframeID
                            ))
                        }))
                    }
                    EditorInspectorSection(configuration: .init(title: "Zoom", content: { zoomContent }))
                    EditorInspectorSection(configuration: .init(title: "Cursor", content: { cursorContent }))
                    if let message {
                        Text(message).font(BlitzType.caption)
                            .foregroundStyle(messageIsError ? BlitzUI.warning : BlitzUI.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                }
            },
            footer: { EmptyView() }
        ))
        .onAppear {
            magnification = edits.zoom.isEmpty ? ScreenZoomStrength.medium.rawValue : edits.zoom.intensity
            cursorScale = edits.cursorStyle.scale
        }
        .onAppear {
            if let project = vm.lastExportedProject { cursorTracks.prepare(directory: project.takeDirectoryPath) }
        }
        .onChange(of: edits.cursorStyle.scale) { _, value in cursorScale = value }
        .onChange(of: edits.zoom.intensity) { _, value in magnification = value }
    }

    private var zoomCount: Int {
        var count = 0
        var wasZoomed = false
        for keyframe in edits.zoom.keyframes {
            let zoomed = keyframe.amount > 0.001
            if zoomed && !wasZoomed { count += 1 }
            wasZoomed = zoomed
        }
        return count
    }

    private var zoomDetail: String {
        if edits.zoom.isEmpty { return "Zoom in where you clicked." }
        if !edits.zoom.isActive { return "Off. Your zooms are kept." }
        return zoomCount == 1 ? "1 zoom. Eases back after it." : "\(zoomCount) zooms. Eases back after each one."
    }

    private var manualZoom: CursorZoomPlanning.ManualZoomRequest {
        .init(track: edits.zoom, time: playback.currentTime, duration: playback.duration, magnification: magnification,
              cursorSamples: cursorTrack?.samples ?? [], trimOffset: vm.lastExportedProject?.timelineTrimOffsetSeconds ?? 0)
    }

    private var zoomContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if cursorTracks.state == .loading && edits.zoom.isEmpty {
                loadingPlaceholder
            } else if hasCursorClicks || !edits.zoom.isEmpty {
                Toggle(isOn: Binding(
                    get: { edits.zoom.isActive },
                    set: { setCursorZoomEnabled($0) }
                )) {
                    illustratedLabel(.init(
                        title: "Screen zoom",
                        detail: zoomDetail,
                        effect: .zoom(amount: magnification, enabled: edits.zoom.isActive)
                    ))
                }
                .toggleStyle(.blitzSwitch)
                .help("Turn screen zoom on or off for preview and export.")
            } else {
                Text(cursorTrack == nil
                     ? "This take has no click data. Add zooms by hand at the playhead."
                     : "No clicks in this take. Add zooms by hand at the playhead.")
                    .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if edits.zoom.isActive {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Strength").font(BlitzType.label).foregroundStyle(BlitzUI.supportingText)
                    BlitzSegmentedPicker(configuration: .init(
                        title: "Zoom strength",
                        options: ScreenZoomStrength.allCases,
                        selection: Binding(get: { ScreenZoomStrength.nearest(magnification) }, set: { setStrength($0) }),
                        label: \.title,
                        help: { String(format: "%.1f×", $0.rawValue) }
                    ))
                    .controlSize(.small)
                }
            }
            let canAdd = CursorZoomPlanning.canAddZoom(manualZoom)
            HStack(spacing: 8) {
                Button(action: addZoom) { Label("Add zoom at playhead", systemImage: "plus.magnifyingglass") }
                    .blitzButton(.secondary).controlSize(.small)
                    .disabled(!canAdd || !playback.hideableKinds.contains(.screen))
                    .help(canAdd ? "Zoom in for 3 seconds from the playhead" : "There's already a zoom here")
                if hasCursorClicks && !edits.zoom.isEmpty {
                    Button(action: generateZoom) { Label("Rebuild from clicks", systemImage: "arrow.triangle.2.circlepath") }
                        .blitzButton(.quiet).controlSize(.small)
                        .help("Replace every zoom with new ones from your clicks")
                }
            }
            if edits.zoom.isActive && playback.hideableKinds.contains(.camera) {
                Toggle(isOn: Binding(
                    get: { edits.cameraFollowsZoom },
                    set: { value in
                        var updated = edits
                        updated.cameraFollowsZoom = value
                        apply(.init(edits: updated, actionName: "Change Camera Motion"))
                    })) {
                        illustratedLabel(.init(
                            title: "Camera follows zoom", detail: "Shrink the camera during close-ups.",
                            effect: .cameraFollow(edits.cameraFollowsZoom)
                        ))
                    }
                    .toggleStyle(.blitzSwitch)
                    .help("The picture-in-picture camera shrinks during screen zooms, then returns to its original size.")
            }
        }
    }

    @ViewBuilder
    private var cursorContent: some View {
        if cursorTrack?.supportsPresentation == true {
            VStack(alignment: .leading, spacing: 12) {
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
            }
        } else {
            Text("Cursor effects need a full-screen recording made in BlitzRecorder. This take keeps its original cursor.")
                .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func addZoom() {
        let request = manualZoom
        guard CursorZoomPlanning.canAddZoom(request) else { return }
        var updated = edits
        updated.zoom = CursorZoomPlanning.addingZoom(request)
        if apply(.init(edits: updated, actionName: "Add Zoom")) {
            playback.seek(to: min(playback.duration, request.time + 0.5))
        }
    }

    private func setStrength(_ strength: ScreenZoomStrength) {
        magnification = strength.rawValue
        guard !edits.zoom.isEmpty else { return }
        var updated = edits
        updated.zoom = CursorZoomPlanning.changingStrength(.init(track: edits.zoom, magnification: strength.rawValue))
        apply(.init(edits: updated, actionName: "Change Zoom Strength"))
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
        message = updated.zoom.isEmpty ? "No usable clicks remain after your cuts." : nil
    }

}
