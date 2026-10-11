import SwiftUI

enum RecorderInspectorTab: CaseIterable, Hashable {
    case layout
    case screen
    case camera
    case audio
    case background

    var title: String {
        switch self {
        case .layout: return "Layout"
        case .screen: return "Screen"
        case .camera: return "Camera"
        case .audio: return "Audio"
        case .background: return "Canvas"
        }
    }

    var symbolName: String {
        switch self {
        case .layout: return "rectangle.split.2x1"
        case .screen: return BlitzSymbols.screen
        case .camera: return BlitzSymbols.camera
        case .audio: return "waveform"
        case .background: return "photo"
        }
    }

    init(selection: RecorderInspectorSelection) {
        switch selection {
        case .canvas: self = .background
        case .layout: self = .layout
        case .source(.screen): self = .screen
        case .source(.camera): self = .camera
        case .source(.microphone), .source(.systemAudio): self = .audio
        }
    }
}

struct RecorderLayerInspector: View {
    @Bindable var vm: RecorderViewModel
    @AppStorage(ShortFormSafeZone.preferenceKey) private var showsSafeZones = false

    private var tab: RecorderInspectorTab {
        RecorderInspectorTab(selection: vm.inspectorSelection)
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Rectangle().fill(BlitzUI.separator).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: EditorInspectorMetrics.sectionSpacing) {
                    pane
                }
                .padding(.horizontal, 16)
                .padding(.vertical, EditorInspectorMetrics.verticalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(BlitzUI.panelBackground)
        .foregroundStyle(BlitzUI.primaryText)
        .tint(BlitzUI.mint)
    }

    private var tabBar: some View {
        BlitzToolTabBar(configuration: .init(
            title: "Scene settings",
            options: RecorderInspectorTab.allCases,
            selection: tab,
            label: { $0.title },
            symbolName: { $0.symbolName },
            help: { help(for: $0) },
            isOptionEnabled: { isEnabled($0) },
            select: { select($0) }
        ))
    }

    @ViewBuilder
    private var pane: some View {
        switch tab {
        case .layout: layoutPane
        case .screen: screenPane
        case .camera: cameraPane
        case .audio: audioPane
        case .background: backgroundPane
        }
    }

    private var screenPane: some View {
        Group {
            notice(for: .screen)
            EditorInspectorSection(configuration: .init(
                title: vm.supportsScreenWindowScaling ? "App window" : "Screen framing"
            ) {
                ScreenSourceInspector(vm: vm, enabled: vm.isSourceConfigured(.screen))
            })
            hiddenNotice(for: .screen)
        }
    }

    private var cameraPane: some View {
        Group {
            notice(for: .camera)
            EditorInspectorSection(configuration: .init(title: "Framing") {
                CameraCropControls(vm: vm)
            })
            EditorInspectorSection(configuration: .init(title: "Effects") {
                CameraSourceInspector(vm: vm, enabled: vm.isSourceConfigured(.camera))
                if vm.cameraFloats {
                    presetRow(.init(
                        title: "Corners",
                        options: CameraCornerPreset.allCases,
                        selection: Binding(
                            get: { CameraCornerPreset.nearest(vm.settings.cameraCornerRadius) },
                            set: { vm.setCameraCornerRadius($0.value) }
                        ),
                        label: \.title
                    ))
                    .disabled(!vm.canEditScene)
                    Toggle("Shadow", isOn: Binding(
                        get: { vm.settings.cameraShadowEnabled },
                        set: { vm.setCameraShadowEnabled($0) }
                    ))
                    .toggleStyle(.blitzSwitch)
                    .disabled(!vm.canEditScene)
                    .help("Add a soft shadow under the camera")
                } else if vm.settings.visibleSources.isSuperset(of: [.screen, .camera]) {
                    layoutCaption("Corners match the screen. Change them in Canvas, next to Padding.")
                }
            })
            hiddenNotice(for: .camera)
        }
    }

    private var audioPane: some View {
        Group {
            audioSection(.init(
                title: "Microphone",
                source: .microphone,
                levels: vm.micLevels,
                gain: Binding(get: { vm.settings.microphoneGain }, set: { vm.setMicrophoneGain($0) })
            ))
            audioSection(.init(
                title: "Mac audio",
                source: .systemAudio,
                levels: vm.sysLevels,
                gain: Binding(get: { vm.settings.systemAudioGain }, set: { vm.setSystemAudioGain($0) })
            ))
        }
    }

    private var backgroundPane: some View {
        Group {
            EditorInspectorSection(configuration: .init(title: "Background") {
                SceneBackgroundSwatchRow(vm: vm)
                if vm.settings.canvasBackgroundStyle.supportsBackgroundAnimation {
                    Toggle("Gentle motion", isOn: Binding(
                        get: { vm.settings.canvasBackgroundAnimated },
                        set: { vm.setCanvasBackgroundAnimated($0) }
                    ))
                    .toggleStyle(.blitzSwitch)
                    .disabled(!vm.canEditScene)
                    .help("Slowly drift the gradient colors while you record")
                }
            })
            EditorInspectorSection(configuration: .init(title: "Frame") {
                presetRow(.init(
                    title: "Padding",
                    options: CanvasPaddingPreset.allCases,
                    selection: Binding(
                        get: { CanvasPaddingPreset.nearest(vm.settings.canvasPadding) },
                        set: { vm.setCanvasPadding($0.value) }
                    ),
                    label: \.title
                ))
                presetRow(.init(
                    title: "Corners",
                    options: ScreenCornerPreset.allCases,
                    selection: Binding(
                        get: { ScreenCornerPreset.nearest(vm.settings.screenCornerRadius) },
                        set: { vm.setScreenCornerRadius($0.value) }
                    ),
                    label: \.title
                ))
                Toggle("Shadow", isOn: Binding(
                    get: { vm.settings.screenShadowEnabled },
                    set: { vm.setScreenShadowEnabled($0) }
                ))
                .toggleStyle(.blitzSwitch)
                .help("Lift the screen off the background. Shows when there is padding.")
            })
            .disabled(!vm.canEditScene)
            EditorInspectorSection(configuration: .init(title: "Guides") {
                Toggle("Rule of thirds", isOn: Binding(
                    get: { vm.settings.showsRuleOfThirdsOverlay },
                    set: { vm.setRuleOfThirds($0) }
                ))
                .toggleStyle(.blitzSwitch)
                .disabled(!vm.canEditScene)
                .help("Show rule-of-thirds lines on the preview. They are never recorded.")
                if vm.settings.layout == .vertical {
                    Toggle("App safe zones", isOn: $showsSafeZones)
                        .toggleStyle(.blitzSwitch)
                        .help("Shade where TikTok, Reels and Shorts put captions and buttons. Never recorded.")
                }
            })
        }
    }

    private struct PresetRow<Value: Hashable> {
        let title: String
        let options: [Value]
        let selection: Binding<Value>
        let label: (Value) -> String
    }

    private func presetRow<Value: Hashable>(_ row: PresetRow<Value>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.title)
                .font(BlitzType.label)
                .foregroundStyle(BlitzUI.supportingText)
            BlitzSegmentedPicker(configuration: .init(
                title: row.title, options: row.options, selection: row.selection, label: row.label
            ))
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func notice(for source: CaptureSource) -> some View {
        if let notice = vm.sourceReadinessNotice(source), notice.action != .chooseScreen {
            SourceReadinessNoticeView(notice: notice, vm: vm)
        }
    }

    @ViewBuilder
    private func hiddenNotice(for source: CaptureSource) -> some View {
        if vm.isSourceConfigured(source), !vm.isSourceVisible(source) {
            Text("Not shown in \(vm.selectedSceneName). It still records on its own track.")
                .font(BlitzType.caption)
                .foregroundStyle(BlitzUI.supportingText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var layoutPane: some View {
        Group {
            EditorInspectorSection(configuration: .init(title: vm.selectedSceneName) {
                layoutControls
            })
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Button(action: vm.resetSceneLayout) {
                    Label("Reset layout", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .blitzButton(.quiet)
                .help("Put the screen and camera back where this layout starts")
                layoutCaption("Puts the screen and camera back where this layout starts.")
            }
        }
        .disabled(!vm.canEditScene)
    }

    @ViewBuilder
    private var layoutControls: some View {
        switch vm.selectedScenePreset {
        case .webcamLeft?, .cameraRight?:
            sideBySideControls
        case .screenTop50?:
            stackedControls
        case .cameraInset?:
            CameraInsetFrameControls(vm: vm)
        case .screenFullscreen?:
            layoutCaption(vm.isSourceConfigured(.camera)
                ? "Only your screen shows. Your camera still records on its own track."
                : "Only your screen shows.")
        case .webcamFullscreen?:
            layoutCaption(vm.isSourceConfigured(.screen)
                ? "Only your camera shows. Your screen still records on its own track."
                : "Only your camera shows.")
        default:
            layoutCaption("Pick a layout in the scenes bar under the preview.")
        }
    }

    @ViewBuilder
    private var sideBySideControls: some View {
        if vm.showsSideSplitControl {
            VStack(alignment: .leading, spacing: 6) {
                BlitzUI.sectionLabel("Camera side")
                BlitzSegmentedPicker(configuration: .init(
                    title: "Camera side",
                    options: [SceneCameraSide.left, .right],
                    selection: Binding(
                        get: { vm.sideSplitCameraSide },
                        set: { vm.setSideSplitCameraSide($0) }
                    ),
                    label: { $0 == .left ? "Left" : "Right" }
                ))
            }
            BlitzInspectorSlider(configuration: .init(
                title: "Width",
                value: Binding(
                    get: { vm.sideSplitCameraWidth },
                    set: { vm.previewSideSplitCameraWidth($0) }
                ),
                range: Double(SceneLayout.minimumSideBySideCameraWidth)...Double(SceneLayout.maximumSideBySideCameraWidth),
                step: 0.005,
                valueLabel: "\(Int((vm.sideSplitCameraWidth * 100).rounded()))%",
                onEditingChanged: { if !$0 { vm.commitSideSplitPreview() } },
                onReset: {
                    vm.setSideSplitCameraWidth(Double(SceneLayout.defaultSideBySideCameraWidth(for: vm.settings.layout)))
                }
            ))
            .help("How wide the camera is. Reset goes back to a 9:16 camera.")
            layoutCaption("Camera width. You can also drag the divider on the preview.")
        } else {
            unavailableLayoutCaption
        }
    }

    @ViewBuilder
    private var stackedControls: some View {
        if vm.showsScreenSplitControl {
            BlitzInspectorSlider(configuration: .init(
                title: "Screen",
                value: Binding(
                    get: { vm.screenSplitHeight },
                    set: { vm.previewScreenSplitHeight($0) }
                ),
                range: Double(SceneLayout.minimumScreenSplitHeight)...Double(SceneLayout.maximumScreenSplitHeight),
                step: 0.005,
                valueLabel: "\(Int((vm.screenSplitHeight * 100).rounded()))%",
                onEditingChanged: { if !$0 { vm.commitScreenSplitPreview() } },
                onReset: { vm.setScreenSplitHeight(Double(SceneLayout.defaultScreenSplitHeight)) }
            ))
            .help("How much of the height the screen takes")
            layoutCaption("Screen height. You can also drag the divider on the preview.")
        } else {
            unavailableLayoutCaption
        }
    }

    private var unavailableLayoutCaption: some View {
        layoutCaption(vm.isSourceConfigured(.screen) && vm.isSourceConfigured(.camera)
            ? "You moved things by hand. Reset the layout to get these controls back."
            : "Turn on Screen and Camera in Sources to use this layout.")
    }

    private func layoutCaption(_ text: String) -> some View {
        Text(text)
            .font(BlitzType.caption)
            .foregroundStyle(BlitzUI.supportingText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private struct AudioSectionRequest {
        let title: String
        let source: CaptureSource
        let levels: TrackLevels
        let gain: Binding<Double>
    }

    private func audioSection(_ request: AudioSectionRequest) -> some View {
        EditorInspectorSection(configuration: .init(title: request.title) {
            if vm.isSourceConfigured(request.source) {
                AudioSourceInspector(
                    source: request.source,
                    levels: request.levels,
                    gain: request.gain,
                    vm: vm
                )
            } else {
                Text("Off. Turn it on in Sources to record it.")
                    .font(BlitzType.body)
                    .foregroundStyle(BlitzUI.secondaryText)
            }
        })
    }

    private func isEnabled(_ item: RecorderInspectorTab) -> Bool {
        switch item {
        case .layout: return true
        case .screen: return vm.isSourceConfigured(.screen)
        case .camera: return vm.isSourceConfigured(.camera)
        case .audio: return vm.isSourceConfigured(.microphone) || vm.isSourceConfigured(.systemAudio)
        case .background: return true
        }
    }

    private func help(for item: RecorderInspectorTab) -> String {
        switch item {
        case .layout: return "Where the screen and camera sit in this scene"
        case .screen: return "Screen framing in this scene"
        case .camera: return "Camera framing and effects"
        case .audio: return "Microphone and Mac audio volume"
        case .background: return "Background, padding and guides"
        }
    }

    private func select(_ item: RecorderInspectorTab) {
        switch item {
        case .layout: vm.selectLayoutInspector()
        case .screen: vm.selectSource(.screen)
        case .camera: vm.selectSource(.camera)
        case .audio: vm.selectSource(vm.isSourceConfigured(.microphone) ? .microphone : .systemAudio)
        case .background: vm.selectBackgroundLayer()
        }
    }
}

private enum CanvasPaddingPreset: CaseIterable {
    case none, small, medium, large

    var value: CGFloat {
        switch self {
        case .none: 0
        case .small: 0.03
        case .medium: 0.06
        case .large: 0.10
        }
    }

    var title: String {
        switch self {
        case .none: "None"
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    static func nearest(_ value: CGFloat) -> Self {
        allCases.min { abs($0.value - value) < abs($1.value - value) } ?? .none
    }
}

private enum CameraCornerPreset: CaseIterable {
    case sharp, soft, round

    var value: CGFloat {
        switch self {
        case .sharp: 0
        case .soft: SceneLayoutProjection.defaultCameraCornerRadius
        case .round: 0.18
        }
    }

    var title: String {
        switch self {
        case .sharp: "Sharp"
        case .soft: "Soft"
        case .round: "Round"
        }
    }

    static func nearest(_ value: CGFloat) -> Self {
        allCases.min { abs($0.value - value) < abs($1.value - value) } ?? .soft
    }
}

private enum ScreenCornerPreset: CaseIterable {
    case sharp, soft, round

    var value: CGFloat {
        switch self {
        case .sharp: 0
        case .soft: 0.025
        case .round: 0.06
        }
    }

    var title: String {
        switch self {
        case .sharp: "Sharp"
        case .soft: "Soft"
        case .round: "Round"
        }
    }

    static func nearest(_ value: CGFloat) -> Self {
        allCases.min { abs($0.value - value) < abs($1.value - value) } ?? .sharp
    }
}

struct SceneBackgroundSwatchRow: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        CanvasBackgroundChooser(configuration: .init(
            selection: vm.settings.canvasBackgroundStyle,
            onSelect: { vm.setCanvasBackgroundStyle($0) }
        ))
        .disabled(!vm.canEditScene)
        .opacity(vm.canEditScene ? 1 : 0.52)
    }
}
