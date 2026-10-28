import SwiftUI

struct EditorLayoutInspector: View {
    @Bindable var vm: RecorderViewModel
    let playback: EditorPlaybackController
    let sceneEvents: [RecordingSceneEvent]
    let captureLayout: CaptureLayout?
    let canvasAspectRatio: CGFloat
    let recordedVideoSources: Set<CaptureSource>
    let scenePresetPreview: BlitzScenePreview
    /// The file each canvas layer shows in the current scene.
    let layerAssetIDs: [SceneLayerKind: String]
    /// The layer picked on the canvas, so its section reads as the one being edited.
    let selectedSource: SceneLayerKind?
    @Binding var screenZoomDraft: Double?
    @Binding var cameraZoomDraft: Double?
    @Binding var sourceCropDraft: EditorSourceCropDraft?
    @Binding var canvasSceneDraft: RecordingScene?
    @Binding var canvasCommitTask: Task<Void, Never>?
    @Binding var preservesCanvasPreviewOnNextProjectRefresh: Bool
    @Binding var selection: EditorSelection?
    @Binding var editErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: EditorInspectorMetrics.sectionSpacing + 8) {
            sceneControlsSection
            if renders(.screen) {
                sourceSection(.screen) { screenControls }
            }
            if renders(.camera) {
                sourceSection(.camera) { cameraControlsSection }
            }
            if showsSecondCamera {
                sourceSection(.secondCamera) { secondCameraControls }
            }
            cameraTilesSection
            backgroundSection
        }
    }

    var showsSecondCamera: Bool {
        renders(.camera) && currentEventScene?.sceneLayout.secondCameraFrame != nil
    }

    private func sectionTitle(_ kind: SceneLayerKind) -> String {
        switch kind {
        case .screen: "Screen"
        case .camera: showsSecondCamera ? "Camera 1" : "Camera"
        case .secondCamera: "Camera 2"
        }
    }

    @ViewBuilder
    private var secondCameraControls: some View {
        if sourceCropDraft?.kind == .secondCamera {
            Text("Drag the frame on the video, then click Done.")
                .font(BlitzType.caption)
                .foregroundStyle(BlitzUI.secondaryText)
        } else if sourceCropDraft == nil {
            Button { beginEditorSourceCrop(.secondCamera) } label: {
                Label("Crop", systemImage: "crop").lineLimit(1).frame(maxWidth: .infinity)
            }
            .blitzButton(.secondary)
            .help("Choose the part of Camera 2 that fills its frame. Done applies it; Cancel keeps the current framing.")
        }
    }

    /// Spacing and shape of the two camera tiles, from presets so both tiles always stay even.
    @ViewBuilder
    private var cameraTilesSection: some View {
        if showsSecondCamera, sourceCropDraft == nil, let scene = currentEventScene {
            let context = EditorSceneTiles.Context(scene: scene, layout: captureLayout ?? .horizontal,
                                                   sourceAspectRatios: playback.sourceAspectRatios(for: scene))
            VStack(alignment: .leading, spacing: 12) {
                Text("Tiles")
                    .font(BlitzType.section)
                    .foregroundStyle(BlitzUI.primaryText)
                    .frame(minHeight: 24)
                SceneTileControls(configuration: .init(
                    tiles: EditorSceneTiles.current(context),
                    layout: context.layout,
                    cameraAspectRatio: EditorSceneTiles.cameraAspectRatio(context),
                    includesScreen: EditorSceneTiles.includesScreen(scene),
                    apply: { tiles in
                        playback.pauseForEditing()
                        if !vm.applyProjectSceneEdit(eventIndex: currentEventIndex,
                                                     EditorSceneTiles.edit(.init(tiles: tiles, context: context))) {
                            editErrorMessage = vm.detailMessage
                        }
                    }
                ))
            }
        }
    }

    private func renders(_ source: CaptureSource) -> Bool {
        currentEventScene?.renderedSources.contains(source) == true
    }

    private func sourceSection<Content: View>(
        _ kind: SceneLayerKind,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(sectionTitle(kind))
                    .font(BlitzType.section)
                    .foregroundStyle(BlitzUI.primaryText)
                Spacer(minLength: 0)
                if isFramingChanged(kind) {
                    Button("Reset") { resetFraming(kind) }
                        .blitzButton(.quiet)
                        .controlSize(.small)
                        .help("Back to the layout's own framing")
                }
            }
            .frame(minHeight: 24)
            content()
        }
        .padding(selectedSource == kind ? 10 : 0)
        .background {
            if selectedSource == kind { BlitzSelectedBackground(cornerRadius: BlitzUI.cardRadius) }
        }
        .padding(selectedSource == kind ? -10 : 0)
        .animation(.easeOut(duration: 0.12), value: selectedSource)
    }

    var currentEventIndex: Int {
        EditorTimelineIndex.eventIndex(at: playback.currentTime, in: sceneEvents)
    }

    private var currentEventScene: RecordingScene? {
        sceneEvents.indices.contains(currentEventIndex) ? sceneEvents[currentEventIndex].scene : nil
    }

    var displayedCanvasScene: RecordingScene? {
        canvasSceneDraft ?? currentEventScene
    }

    @ViewBuilder
    private var sceneControlsSection: some View {
        if let scene = currentEventScene, captureLayout != nil {
            VStack(alignment: .leading, spacing: 12) {
                BlitzInspectorHeading(
                    configuration: .init(
                        title: "Composition",
                        detail: sceneEvents.count > 1 ? "Part \(currentEventIndex + 1) of \(sceneEvents.count)" : "Whole video"
                    ))
                LazyVGrid(columns: scenePresetColumns, spacing: 8) {
                    ForEach(
                        (ScenePreset.allCases + (playback.hasSecondCamera ? ScenePreset.twoCameraPresets : [])).filter {
                            $0.supports(captureLayout ?? .horizontal)
                                && $0.requiredVideoSources.isSubset(of: recordedVideoSources)
                        },
                        id: \.self
                    ) { preset in
                        let layout = editorLayout(for: preset)
                        BlitzScenePresetCard(
                            preset: preset,
                            layout: captureLayout ?? .horizontal,
                            isSelected: EditorScenePresetSelection.isSelected(
                                .init(preset: preset, scene: scene, layout: layout)),
                            isEnabled: true,
                            availableSources: recordedVideoSources,
                            preview: scenePresetPreview
                        ) {
                            applyScenePreset(preset)
                        }
                        .help(
                            "\(preset.compactTitle). Drag the screen or camera on the video to move them."
                        )
                    }
                }
            }
        }
    }

    private var scenePresetColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
    }

    @ViewBuilder
    private var screenControls: some View {
        if sceneEvents.count > 1 {
            Text("Changes apply to part \(currentEventIndex + 1)")
                .font(BlitzType.caption)
                .foregroundStyle(BlitzUI.secondaryText)
        }
        if sourceCropDraft?.kind != .screen {
            SourceFramingPicker(selection: segmentSceneBinding(\.screenContentMode, fallback: .fill))
            BlitzInspectorSlider(
            configuration: .init(
                title: "Zoom",
                value: screenZoomBinding,
                range: 0...0.75,
                step: 0.001,
                valueLabel: EditorSourceZoom.label(screenZoomValue),
                onEditingChanged: { if !$0 { commitScreenZoom() } },
                onReset: {
                    previewScreenZoom(0)
                    commitScreenZoom()
                }
            ))
            .help("Zoom into the screen recording")
        }
        if sourceCropDraft?.kind == .screen {
            Text("Drag the frame on the video, then click Done.")
                .font(BlitzType.caption)
                .foregroundStyle(BlitzUI.secondaryText)
        } else if sourceCropDraft == nil {
            Button { beginEditorSourceCrop(.screen) } label: {
                Label("Crop", systemImage: "crop").lineLimit(1).frame(maxWidth: .infinity)
            }
            .blitzButton(.secondary)
            .help("Choose the part of your screen that fills its frame. Done applies it; Cancel keeps the current framing.")
        }
    }

    @ViewBuilder
    private var cameraControlsSection: some View {
        if let scene = currentEventScene, scene.enabledSources.contains(.camera) {
            VStack(alignment: .leading, spacing: 14) {
                if sourceCropDraft?.kind != .camera,
                   SceneLayout.isCameraInsetFrame(scene.sceneLayout.cameraFrame) {
                    CameraInsetFrameControlPanel(configuration: editorCameraInsetConfiguration)
                }

                CameraImageControls(configuration: editorCameraImageConfiguration)

                if showsEditorCameraShadow && sourceCropDraft?.kind != .camera {
                    Toggle("Shadow", isOn: segmentSceneBinding(\.cameraShadowEnabled, fallback: false))
                        .toggleStyle(.blitzSwitch)
                        .help("Add a soft shadow under the camera")
                }
            }
        }
    }

    private func editorLayout(for preset: ScenePreset) -> SceneLayout {
        SceneLayout.presetLayout(
            preset,
            for: captureLayout ?? .horizontal,
            screenAspectRatio: playback.sourceAspectRatios[.screen] ?? SceneLayout.defaultScreenAspectRatio,
            cameraAspectRatio: playback.sourceAspectRatios[.camera] ?? SceneLayout.cameraAspectRatio
        )
    }

    private func applyScenePreset(_ preset: ScenePreset) {
        let index = currentEventIndex
        if let correction = EditorScenePresetSourceCorrection.correction(for: preset) {
            playback.pauseForEditing()
            guard vm.applyProjectSceneCorrection(.init(eventIndex: index, correction: correction)) else {
                editErrorMessage = vm.detailMessage
                return
            }
            selection = .segment(index)
            return
        }
        let layout = editorLayout(for: preset)
        let angles = vm.lastExportedProject?.cameraAngles ?? []
        let canvas = captureLayout ?? .horizontal
        playback.pauseForEditing()
        guard
            vm.applyProjectSceneEdit(
                eventIndex: index,
                { scene in
                    scene.sceneLayout = layout
                    scene.cameraContentMode = .fill
                    let video = preset.requiredVideoSources
                    scene.enabledSources.subtract([.screen, .camera])
                    scene.enabledSources.formUnion(video)
                    for source in video { scene.sourceOpacities[source] = 1 }
                    if layout.secondCameraFrame != nil {
                        if let speakers = MulticamShot.speakers(in: angles) {
                            scene.cameraFeeds = CameraFeeds(camera: speakers.left, secondCamera: speakers.right)
                            let shot = MulticamShot.sideBySide(left: speakers.left, right: speakers.right)
                            MulticamShot.frameSpeakers(in: &scene, .init(
                                angles: angles, canvas: canvas, framing: .standard(for: shot)))
                        } else {
                            scene.cameraFeeds = .main
                        }
                    }
                })
        else {
            editErrorMessage = vm.detailMessage
            return
        }
        selection = .segment(index)
    }

    private var screenZoomValue: Double {
        EditorSourceZoom.value(draft: screenZoomDraft, amount: currentEventScene?.screenCropAmount ?? .zero)
    }

    private var screenZoomBinding: Binding<Double> {
        Binding(
            get: { screenZoomValue },
            set: { previewScreenZoom($0) }
        )
    }

    private func previewScreenZoom(_ zoom: Double) {
        guard var scene = currentEventScene else { return }
        let clamped = EditorSourceZoom.clamped(zoom)
        if screenZoomDraft == nil {
            playback.pauseForEditing()
        }
        screenZoomDraft = clamped
        scene.screenCropAmount = EditorSourceZoom.amount(clamped)
        playback.setPreviewSceneOverride(scene, at: playback.currentTime)
    }

    private func commitScreenZoom() {
        guard let zoom = screenZoomDraft else { return }
        let index = currentEventIndex
        let succeeded = vm.applyProjectSceneEdit(eventIndex: index) { scene in
            scene.screenCropAmount = EditorSourceZoom.amount(zoom)
        }
        screenZoomDraft = nil
        if !succeeded {
            playback.setPreviewSceneOverride(nil, at: playback.currentTime)
            editErrorMessage = vm.detailMessage
        }
    }

    private var cameraZoomValue: Double {
        EditorSourceZoom.value(draft: cameraZoomDraft, amount: currentEventScene?.cameraCropAmount ?? .zero)
    }

    private var cameraZoomBinding: Binding<Double> {
        Binding(
            get: { cameraZoomValue },
            set: { previewCameraZoom($0) }
        )
    }

    private func previewCameraZoom(_ zoom: Double) {
        guard var scene = currentEventScene else { return }
        let clamped = EditorSourceZoom.clamped(zoom)
        if cameraZoomDraft == nil {
            playback.pauseForEditing()
        }
        cameraZoomDraft = clamped
        scene.cameraContentMode = .fill
        scene.cameraCropAmount = EditorSourceZoom.amount(clamped)
        if clamped < 0.001 {
            scene.cameraCropPosition = .zero
        }
        playback.setPreviewSceneOverride(scene, at: playback.currentTime)
    }

    private func commitCameraZoom() {
        guard let zoom = cameraZoomDraft else { return }
        let index = currentEventIndex
        let succeeded = vm.applyProjectSceneEdit(eventIndex: index) { scene in
            scene.cameraContentMode = .fill
            scene.cameraCropAmount = EditorSourceZoom.amount(zoom)
            if zoom < 0.001 {
                scene.cameraCropPosition = .zero
            }
        }
        cameraZoomDraft = nil
        if !succeeded {
            playback.setPreviewSceneOverride(nil, at: playback.currentTime)
            editErrorMessage = vm.detailMessage
        }
    }

    private func beginEditorSourceCrop(_ kind: SceneLayerKind) {
        guard let draft = EditorSourceCropSession.begin(.init(
            kind: kind, eventIndex: currentEventIndex, sceneEvents: sceneEvents
        )) else { return }
        playback.pauseForEditing()
        screenZoomDraft = nil
        cameraZoomDraft = nil
        sourceCropDraft = draft
        if kind.isCamera, let assetID = layerAssetIDs[kind] {
            selection = .asset(assetID)
        }
    }

    private func resetEditorSourceCrop() {
        if let sourceCropDraft {
            self.sourceCropDraft = EditorSourceCropSession.resetting(sourceCropDraft)
            return
        }
        previewCameraZoom(0)
        commitCameraZoom()
    }

    private var editorCameraInsetConfiguration: CameraInsetFrameControlsConfiguration {
        let layout = captureLayout ?? .horizontal
        let sceneLayout = currentEventScene?.sceneLayout ?? SceneLayout(cameraFrame: .zero)
        let frame = sceneLayout.cameraFrame
        return CameraInsetFrameControlsConfiguration(
            alignment: Binding(
                get: { SceneLayout.cameraInsetAlignment(for: frame) },
                set: { applyEditorCameraInsetChange(.alignment($0)) }
            ),
            shape: Binding(
                get: { sceneLayout.cameraInsetShape(in: layout) },
                set: { applyEditorCameraInsetChange(.shape($0)) }
            ),
            size: Binding(
                get: { Double(sceneLayout.cameraInsetSize(in: layout)) },
                set: { applyEditorCameraInsetChange(.size(CGFloat($0))) }
            ),
            sizeRange: Double(SceneLayout.minimumCameraInsetSize)...Double(
                SceneLayout.maximumCameraInsetSize(for: layout)
            )
        )
    }

    private func applyEditorCameraInsetChange(_ change: EditorCameraInsetControlChange) {
        guard let scene = currentEventScene, let layout = captureLayout else { return }
        let frame = scene.sceneLayout.cameraFrame
        var alignment = SceneLayout.cameraInsetAlignment(for: frame)
        var shape = scene.sceneLayout.cameraInsetShape(in: layout)
        var size = scene.sceneLayout.cameraInsetSize(in: layout)

        switch change {
        case .alignment(let value):
            alignment = value
        case .shape(let value):
            shape = value
        case .size(let value):
            size = value
        }

        let sourceAspectRatio = playback.sourceAspectRatios[.camera] ?? SceneLayout.cameraAspectRatio
        let nextFrame = SceneLayout.cameraInsetFrame(
            for: layout,
            alignment: alignment,
            shape: shape,
            size: size,
            sourceAspectRatio: sourceAspectRatio
        )
        playback.pauseForEditing()
        guard vm.applyProjectSceneEdit(eventIndex: currentEventIndex, { editedScene in
            editedScene.sceneLayout.cameraFrame = nextFrame
            editedScene.sceneLayout.cameraMask = shape.cameraMask
        }) else {
            editErrorMessage = vm.detailMessage
            return
        }
    }

    private var showsEditorCameraShadow: Bool {
        let scene = sourceCropDraft?.scene ?? currentEventScene
        return scene.map { SceneLayout.isCameraInsetFrame($0.sceneLayout.cameraFrame) } ?? false
    }

    private var editorCameraImageConfiguration: CameraImageControlsConfiguration {
        let scene = sourceCropDraft?.scene ?? currentEventScene
        let position = scene?.cameraCropPosition ?? .zero
        let amount = scene?.cameraCropAmount ?? .zero
        let isCentered = max(amount.x, amount.y) < 0.001
            && abs(position.x) < 0.001
            && abs(position.y) < 0.001
        return CameraImageControlsConfiguration(
            contentMode: segmentSceneBinding(\.cameraContentMode, fallback: .fill),
            cropZoom: cameraZoomBinding,
            isCropModeEnabled: sourceCropDraft?.kind == .camera,
            showsContentMode: !showsEditorCameraShadow,
            isResetDisabled: isCentered,
            showsResetButton: false,
            onCropZoomEditingChanged: { isEditing in
                if !isEditing {
                    commitCameraZoom()
                }
            },
            onBeginCrop: { beginEditorSourceCrop(.camera) },
            onResetCrop: resetEditorSourceCrop
        )
    }

    private func isFramingChanged(_ kind: SceneLayerKind) -> Bool {
        guard let scene = currentEventScene else { return false }
        let amount = scene.sourceCropAmount(for: kind)
        let position = scene.sourceCropPosition(for: kind)
        let mode = kind == .screen ? scene.screenContentMode : scene.cameraContentMode
        return max(amount.x, amount.y) > 0.001 || abs(position.x) > 0.001 || abs(position.y) > 0.001 || mode != .fill
    }

    private func resetFraming(_ kind: SceneLayerKind) {
        playback.pauseForEditing()
        screenZoomDraft = nil
        cameraZoomDraft = nil
        sourceCropDraft = nil
        guard vm.applyProjectSceneEdit(eventIndex: currentEventIndex, { scene in
            if kind == .screen {
                scene.screenCropAmount = .zero
                scene.screenCropPosition = .zero
                scene.screenContentMode = .fill
            } else if kind == .secondCamera {
                scene.secondCameraCropAmount = .zero
                scene.secondCameraCropPosition = .zero
            } else {
                scene.cameraCropAmount = .zero
                scene.cameraCropPosition = .zero
                scene.cameraContentMode = .fill
            }
        }) else {
            editErrorMessage = vm.detailMessage
            return
        }
    }

    private func segmentSceneBinding<Value>(
        _ keyPath: WritableKeyPath<RecordingScene, Value>,
        fallback: Value
    ) -> Binding<Value> {
        let index = currentEventIndex
        let value = currentEventScene?[keyPath: keyPath] ?? fallback
        return Binding(
            get: { value },
            set: { newValue in
                vm.applyProjectSceneEdit(eventIndex: index) { $0[keyPath: keyPath] = newValue }
            }
        )
    }
}
