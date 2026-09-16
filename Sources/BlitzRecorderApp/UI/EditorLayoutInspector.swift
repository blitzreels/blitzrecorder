import SwiftUI

struct EditorLayoutInspector: View {
    @Bindable var vm: RecorderViewModel
    let playback: EditorPlaybackController
    let sceneEvents: [RecordingSceneEvent]
    let captureLayout: CaptureLayout?
    let canvasAspectRatio: CGFloat
    let recordedVideoSources: Set<CaptureSource>
    let scenePresetPreview: BlitzScenePreview
    let cameraAssetID: String?
    @Binding var showsSourceFraming: Bool
    @Binding var framingSource: SceneLayerKind
    @Binding var screenZoomDraft: Double?
    @Binding var cameraZoomDraft: Double?
    @Binding var cameraCropDraft: EditorCameraCropDraft?
    @Binding var canvasSceneDraft: RecordingScene?
    @Binding var canvasCommitTask: Task<Void, Never>?
    @Binding var preservesCanvasPreviewOnNextProjectRefresh: Bool
    @Binding var selection: EditorSelection?
    @Binding var editErrorMessage: String?
    @Binding var aspectRatioLockedKinds: Set<SceneLayerKind>

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            sceneControlsSection
            inspectorDivider
            VStack(alignment: .leading, spacing: 12) {
                BlitzInspectorHeading(configuration: .init(title: "Canvas", detail: nil))
                canvasControlsSection
                VStack(spacing: 2) {
                    canvasPaddingSection
                    screenAppearanceSection
                }
            }
            inspectorDivider
            sourceFramingSection
        }
    }

    private var currentEventIndex: Int {
        EditorTimelineIndex.eventIndex(at: playback.currentTime, in: sceneEvents)
    }

    private var currentEventScene: RecordingScene? {
        sceneEvents.indices.contains(currentEventIndex) ? sceneEvents[currentEventIndex].scene : nil
    }

    private var displayedCanvasScene: RecordingScene? {
        canvasSceneDraft ?? currentEventScene
    }

    private var inspectorDivider: some View {
        Rectangle()
            .fill(BlitzUI.separator)
            .frame(height: 1)
    }

    @ViewBuilder
    private var sceneControlsSection: some View {
        if let scene = currentEventScene, captureLayout != nil {
            VStack(alignment: .leading, spacing: 12) {
                BlitzInspectorHeading(
                    configuration: .init(
                        title: "Composition",
                        detail: sceneEvents.count > 1 ? "Segment \(currentEventIndex + 1)" : "Full video"
                    ))
                LazyVGrid(columns: scenePresetColumns, spacing: 8) {
                    ForEach(
                        ScenePreset.allCases.filter { $0.supports(captureLayout ?? .horizontal) },
                        id: \.self
                    ) { preset in
                        let layout = editorLayout(for: preset)
                        BlitzScenePresetCard(
                            preset: preset,
                            layout: captureLayout ?? .horizontal,
                            isSelected: EditorScenePresetSelection.isSelected(
                                .init(preset: preset, scene: scene, layout: layout)),
                            isEnabled: preset.requiredVideoSources.isSubset(of: recordedVideoSources),
                            availableSources: recordedVideoSources,
                            preview: scenePresetPreview
                        ) {
                            applyScenePreset(preset)
                        }
                        .help(
                            "\(preset.compactTitle). Applies to this segment. Drag sources in the preview to reposition them."
                        )
                    }
                }
            }
        }
    }

    private var scenePresetColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
    }

    private var sourceFramingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                showsSourceFraming.toggle()
            } label: {
                HStack {
                    Text("Source framing")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 0)
                    BlitzSymbol(
                        configuration: .init(
                            name: showsSourceFraming ? "chevron.up" : "chevron.down", size: 12
                        )
                    )
                    .foregroundStyle(BlitzUI.secondaryText)
                }
                .foregroundStyle(BlitzUI.primaryText)
                .frame(maxWidth: .infinity, minHeight: 28)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .accessibilityValue(showsSourceFraming ? "Expanded" : "Collapsed")

            if showsSourceFraming {
                BlitzSegmentedPicker(
                    configuration: .init(
                        title: "Source to frame",
                        options: [SceneLayerKind.screen, .camera],
                        selection: $framingSource,
                        label: { $0 == .screen ? "Screen" : "Camera" }
                    ))
                if framingSource == .screen {
                    screenZoomSection
                    screenFrameSection
                    frameAspectSection(.screen)
                } else if currentEventScene?.enabledSources.contains(.camera) == true {
                    cameraControlsSection
                } else {
                    Text("Choose a composition with Camera to adjust its framing.")
                        .font(.system(size: 11))
                        .foregroundStyle(BlitzUI.secondaryText)
                }
            }
        }
    }

    @ViewBuilder
    private var screenFrameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            BlitzUI.sectionLabel("Screen frame", icon: "macwindow")

            if sceneEvents.count > 1 {
                Text("Applies to segment \(currentEventIndex + 1)")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
            }

            SourceFramingPicker(selection: segmentSceneBinding(\.screenContentMode, fallback: .fill))
        }
    }

    @ViewBuilder
    private var screenZoomSection: some View {
        if currentEventScene?.enabledSources.contains(.screen) == true {
            BlitzInspectorSlider(
                configuration: .init(
                    title: "Crop",
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
        }
    }

    @ViewBuilder
    private var cameraControlsSection: some View {
        if let scene = currentEventScene, scene.enabledSources.contains(.camera) {
            VStack(alignment: .leading, spacing: 14) {
                if cameraCropDraft == nil,
                   SceneLayout.isCameraInsetFrame(scene.sceneLayout.cameraFrame) {
                    CameraInsetFrameControlPanel(configuration: editorCameraInsetConfiguration)
                }

                CameraImageControls(configuration: editorCameraImageConfiguration)
            }
        }
    }

    @ViewBuilder
    private var canvasControlsSection: some View {
        if let scene = displayedCanvasScene {
            BlitzBackgroundPicker(
                configuration: .init(
                    selection: scene.canvasBackgroundStyle,
                    onSelect: setCanvasBackground
                ))
        }
    }

    @ViewBuilder
    private var canvasPaddingSection: some View {
        if currentEventScene != nil {
            BlitzInspectorSlider(
                configuration: .init(
                    title: "Padding",
                    value: Binding(get: { Double(canvasPaddingValue) }, set: { previewCanvasPadding(CGFloat($0)) }),
                    range: 0...0.12,
                    step: 0.005,
                    valueLabel: "\(Int((canvasPaddingValue * 100).rounded()))%",
                    onEditingChanged: { if !$0 { commitCanvasSceneDraft() } },
                    onReset: {
                        previewCanvasPadding(0)
                        commitCanvasSceneDraft()
                    }
                ))
        }
    }

    @ViewBuilder
    private var screenAppearanceSection: some View {
        if let scene = displayedCanvasScene, scene.renderedSources.contains(.screen) {
            BlitzInspectorSlider(
                configuration: .init(
                    title: "Corners",
                    value: Binding(
                        get: { Double(screenCornerRadiusValue) }, set: { previewScreenCornerRadius(CGFloat($0)) }),
                    range: 0...0.12,
                    step: 0.005,
                    valueLabel: "\(Int((screenCornerRadiusValue * 100).rounded()))%",
                    onEditingChanged: { if !$0 { commitCanvasSceneDraft() } },
                    onReset: {
                        previewScreenCornerRadius(0)
                        commitCanvasSceneDraft()
                    }
                )
            )
            .help("Round the screen recording")
            Toggle("Shadow", isOn: screenShadowBinding)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(BlitzUI.secondaryText)
                .toggleStyle(.blitzSwitch)
                .tint(BlitzUI.mint)
                .frame(minHeight: 28)
                .help("Add a soft shadow under the screen recording")
        }
    }

    @ViewBuilder
    private func frameAspectSection(_ kind: SceneLayerKind) -> some View {
        if let scene = currentEventScene {
            let sceneRequest = EditorFrameRatioSceneRequest(kind: kind, scene: scene)
            let currentRatio = EditorFrameRatio.displayAspectRatio(sceneRequest, canvasAspectRatio: canvasAspectRatio)
            let sourceRatio = playback.sourceAspectRatios[kind] ?? 1
            let selectedPreset = EditorFrameRatio.selectedPreset(
                sceneRequest,
                canvasAspectRatio: canvasAspectRatio,
                sourceRatio: sourceRatio
            )

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    BlitzUI.sectionLabel("Frame", icon: "aspectratio")
                    Spacer(minLength: 0)
                    Text(EditorFrameRatioLabel.text(for: currentRatio))
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(BlitzUI.mint)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(BlitzUI.mint.opacity(0.10), in: .capsule)
                }

                LazyVGrid(columns: EditorFrameRatio.columns, spacing: 6) {
                    ForEach(EditorFrameRatio.availablePresets(sourceRatio: sourceRatio)) { preset in
                        let isSelected = preset == selectedPreset
                        EditorFrameRatioButton(
                            title: preset.title,
                            isSelected: isSelected
                        ) {
                            applyFrameRatio(.init(kind: kind, preset: preset))
                        }
                    }
                }

                Toggle("Lock aspect ratio", isOn: aspectRatioLockBinding(for: kind))
                    .font(.system(size: 10.5, weight: .semibold))
                    .toggleStyle(.blitzSwitch)
                    .tint(BlitzUI.mint)

                Text("Lock for proportional corners. Unlock or drag a side handle to reshape.")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.44))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(BlitzUI.quietFill, in: .rect(cornerRadius: 10))
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
        playback.pauseForEditing()
        guard
            vm.applyProjectSceneEdit(
                eventIndex: index,
                { scene in
                    scene.sceneLayout = layout
                    scene.enabledSources.formUnion([.screen, .camera])
                    scene.sourceOpacities[.screen] = 1
                    scene.sourceOpacities[.camera] = 1
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

    private func beginEditorCameraCrop() {
        guard let draft = EditorCameraCropSession.begin(eventIndex: currentEventIndex, sceneEvents: sceneEvents) else {
            return
        }
        playback.pauseForEditing()
        cameraZoomDraft = nil
        cameraCropDraft = draft
        if let cameraAssetID {
            selection = .asset(cameraAssetID)
        }
    }

    private func resetEditorCameraCrop() {
        if let cameraCropDraft {
            self.cameraCropDraft = EditorCameraCropSession.resetting(cameraCropDraft)
            return
        }
        previewCameraZoom(0)
        commitCameraZoom()
    }

    private var editorCameraInsetConfiguration: CameraInsetFrameControlsConfiguration {
        let layout = captureLayout ?? .horizontal
        let frame = currentEventScene?.sceneLayout.cameraFrame ?? .zero
        return CameraInsetFrameControlsConfiguration(
            alignment: Binding(
                get: { SceneLayout.cameraInsetAlignment(for: frame) },
                set: { applyEditorCameraInsetChange(.alignment($0)) }
            ),
            shape: Binding(
                get: { SceneLayout.cameraInsetShape(for: frame, in: layout) },
                set: { applyEditorCameraInsetChange(.shape($0)) }
            ),
            size: Binding(
                get: { Double(SceneLayout.cameraInsetSize(for: frame, in: layout)) },
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
        var shape = SceneLayout.cameraInsetShape(for: frame, in: layout)
        var size = SceneLayout.cameraInsetSize(for: frame, in: layout)

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
        }) else {
            editErrorMessage = vm.detailMessage
            return
        }
    }

    private var editorCameraImageConfiguration: CameraImageControlsConfiguration {
        let scene = cameraCropDraft?.scene ?? currentEventScene
        let position = scene?.cameraCropPosition ?? .zero
        let amount = scene?.cameraCropAmount ?? .zero
        let isCentered = max(amount.x, amount.y) < 0.001
            && abs(position.x) < 0.001
            && abs(position.y) < 0.001
        let showsShadow = scene.map { SceneLayout.isCameraInsetFrame($0.sceneLayout.cameraFrame) } ?? false
        return CameraImageControlsConfiguration(
            contentMode: segmentSceneBinding(\.cameraContentMode, fallback: .fill),
            cropZoom: cameraZoomBinding,
            shadowEnabled: segmentSceneBinding(\.cameraShadowEnabled, fallback: false),
            isCropModeEnabled: cameraCropDraft != nil,
            showsShadow: showsShadow,
            isResetDisabled: isCentered,
            onCropZoomEditingChanged: { isEditing in
                if !isEditing {
                    commitCameraZoom()
                }
            },
            onBeginCrop: beginEditorCameraCrop,
            onResetCrop: resetEditorCameraCrop
        )
    }

    private func applyFrameRatio(_ request: EditorFrameRatioChange) {
        guard let currentEventScene else { return }
        let sourceRatio = playback.sourceAspectRatios[request.kind] ?? 1
        let scene = EditorFrameRatio.applied(
            request,
            scene: currentEventScene,
            sourceRatio: sourceRatio,
            canvasAspectRatio: canvasAspectRatio
        )
        playback.pauseForEditing()
        guard vm.applyProjectSceneEdit(eventIndex: currentEventIndex, { editedScene in
            editedScene.sceneLayout = scene.sceneLayout
            editedScene.cameraContentMode = scene.cameraContentMode
        }) else {
            editErrorMessage = vm.detailMessage
            return
        }
    }

    private func aspectRatioLockBinding(for kind: SceneLayerKind) -> Binding<Bool> {
        Binding(
            get: { aspectRatioLockedKinds.contains(kind) },
            set: { isLocked in
                if isLocked {
                    aspectRatioLockedKinds.insert(kind)
                } else {
                    aspectRatioLockedKinds.remove(kind)
                }
            }
        )
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

    private func setCanvasBackground(_ style: CanvasBackgroundStyle) {
        previewCanvasScene { scene in
            scene.canvasBackgroundStyle = style
        }
        scheduleCanvasSceneCommit()
        selection = .segment(currentEventIndex)
    }

    private var canvasPaddingValue: CGFloat {
        displayedCanvasScene?.canvasPadding ?? 0
    }

    private func previewCanvasPadding(_ padding: CGFloat) {
        let clamped = EditorCanvasAppearance.clampedPadding(padding)
        previewCanvasScene { scene in
            scene.canvasPadding = clamped
        }
    }

    private var screenCornerRadiusValue: CGFloat {
        displayedCanvasScene?.screenCornerRadius ?? 0
    }

    private func previewScreenCornerRadius(_ radius: CGFloat) {
        let clamped = EditorCanvasAppearance.clampedCornerRadius(radius)
        previewCanvasScene { scene in
            scene.screenCornerRadius = clamped
        }
    }

    private var screenShadowBinding: Binding<Bool> {
        Binding(
            get: { displayedCanvasScene?.screenShadowEnabled ?? false },
            set: { enabled in
                previewCanvasScene { scene in
                    scene.screenShadowEnabled = enabled
                }
                scheduleCanvasSceneCommit()
            }
        )
    }

    private func previewCanvasScene(_ mutate: (inout RecordingScene) -> Void) {
        guard var scene = displayedCanvasScene else { return }
        if canvasSceneDraft == nil {
            playback.pauseForEditing()
        }
        mutate(&scene)
        canvasSceneDraft = scene
        playback.setPreviewSceneOverride(scene, at: playback.currentTime)
    }

    private func scheduleCanvasSceneCommit() {
        canvasCommitTask?.cancel()
        canvasCommitTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(20))
            guard !Task.isCancelled else { return }
            commitCanvasSceneDraft()
        }
    }

    private func commitCanvasSceneDraft() {
        canvasCommitTask?.cancel()
        canvasCommitTask = nil
        guard let draft = canvasSceneDraft else { return }
        let index = currentEventIndex
        preservesCanvasPreviewOnNextProjectRefresh = true
        let succeeded = vm.applyProjectSceneEdit(eventIndex: index) {
            EditorCanvasAppearance.copy(draft, into: &$0)
        }
        if !succeeded {
            preservesCanvasPreviewOnNextProjectRefresh = false
            canvasSceneDraft = nil
            playback.setPreviewSceneOverride(nil, at: playback.currentTime)
            editErrorMessage = vm.detailMessage
        }
    }
}
