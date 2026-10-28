import SwiftUI

enum RecorderInspectorTab: CaseIterable, Hashable {
    case layout
    case screen
    case camera
    case secondCamera
    case background

    var title: String {
        switch self {
        case .layout: return "Layout"
        case .screen: return "Screen"
        case .camera: return "Camera"
        case .secondCamera: return "Camera 2"
        case .background: return "Background"
        }
    }

    var symbolName: String {
        switch self {
        case .layout: return "rectangle.split.2x1"
        case .screen: return BlitzSymbols.screen
        case .camera, .secondCamera: return BlitzSymbols.camera
        case .background: return "square.stack.3d.down.forward"
        }
    }

    init(selection: RecorderInspectorSelection) {
        switch selection {
        case .canvas: self = .background
        case .layout: self = .layout
        case .source(.screen): self = .screen
        case .source(.camera): self = .camera
        case .secondCamera: self = .secondCamera
        case .source(.microphone), .source(.systemAudio): self = .layout
        }
    }
}

struct RecorderLayerInspector: View {
    @Bindable var vm: RecorderViewModel

    private var tab: RecorderInspectorTab {
        RecorderInspectorTab(selection: vm.inspectorSelection)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EditorInspectorMetrics.sectionSpacing) {
                layerList
                pane
            }
            .padding(.horizontal, 14)
            .padding(.vertical, EditorInspectorMetrics.verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(BlitzMaterialBackground(kind: .sidebar))
        .foregroundStyle(BlitzUI.primaryText)
        .tint(BlitzUI.accent)
    }

    /// The scene's layers, top to bottom, with Background last. Selecting one here, on the canvas or in the
    /// inputs list is the same selection.
    private var layerList: some View {
        VStack(alignment: .leading, spacing: 2) {
            BlitzUI.sectionLabel("Layers in \(vm.selectedSceneName)")
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            ForEach(RecorderInspectorTab.allCases, id: \.self) { item in
                if isEnabled(item) {
                    LayerListRow(configuration: .init(
                        title: title(for: item),
                        symbol: item.symbolName,
                        isSelected: tab == item,
                        visibility: visibility(item),
                        help: help(for: item),
                        select: { select(item) }
                    ))
                }
            }
        }
    }

    private func visibility(_ item: RecorderInspectorTab) -> LayerListRow.Visibility? {
        let source: CaptureSource
        switch item {
        case .screen: source = .screen
        case .camera: source = .camera
        case .layout, .secondCamera, .background: return nil
        }
        let isVisible = vm.isSourceVisible(source)
        return .init(
            isVisible: isVisible,
            isEnabled: vm.canEditScene,
            toggle: { vm.setSourceVisible(source, visible: !isVisible) }
        )
    }

    @ViewBuilder
    private var pane: some View {
        switch tab {
        case .layout: layoutPane
        case .screen: screenPane
        case .camera: cameraPane
        case .secondCamera: secondCameraPane
        case .background: backgroundPane
        }
    }

    private var screenPane: some View {
        Group {
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
            EditorInspectorSection(configuration: .init(title: "Framing") {
                CameraCropControls(vm: vm, layer: .camera)
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
                    layoutCaption("Corners match the screen. Change them in Layout, under Style.")
                }
            })
            hiddenNotice(for: .camera)
        }
    }

    private var showsSecondCamera: Bool {
        vm.isSourceConfigured(.camera) && vm.settings.sceneLayout.secondCameraFrame != nil
            && vm.isSourceVisible(.camera)
    }

    private func title(for item: RecorderInspectorTab) -> String {
        switch item {
        case .layout: "Layout"
        case .camera: showsSecondCamera ? "Camera 1" : item.title
        default: item.title
        }
    }

    private var secondCameraPane: some View {
        EditorInspectorSection(configuration: .init(title: "Framing") {
            if let name = vm.secondCameraDeviceName {
                layoutCaption(name)
            }
            CameraCropControls(vm: vm, layer: .secondCamera)
            layoutCaption("Its own crop and zoom. Shape and spacing of both cameras are in Layout.")
        })
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
            EditorInspectorSection(configuration: .init(title: "Spacing") {
                presetRow(.init(
                    title: "Padding",
                    options: CanvasPaddingPreset.allCases,
                    selection: Binding(
                        get: { CanvasPaddingPreset.nearest(vm.settings.canvasPadding) },
                        set: { vm.setCanvasPadding($0.value) }
                    ),
                    label: \.title
                ))
            })
            .disabled(!vm.canEditScene)
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
            EditorInspectorSection(configuration: .init(title: "Style") {
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
                .help("Lift the screen off the background. Shows when the canvas has padding.")
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
        case .twoCameras?, .twoCamerasScreen?:
            if vm.settings.sceneLayout.secondCameraFrame != nil {
                SceneTileControls(configuration: .init(
                    tiles: vm.sceneTiles,
                    layout: vm.settings.layout,
                    cameraAspectRatio: vm.sceneTilesCameraAspectRatio,
                    includesScreen: vm.selectedScenePreset == .twoCamerasScreen,
                    apply: vm.setSceneTiles
                ))
            } else {
                unavailableLayoutCaption
            }
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

    private func isEnabled(_ item: RecorderInspectorTab) -> Bool {
        switch item {
        case .layout: return true
        case .screen: return vm.isSourceConfigured(.screen)
        case .camera: return vm.isSourceConfigured(.camera)
        case .secondCamera: return showsSecondCamera
        case .background: return true
        }
    }

    private func help(for item: RecorderInspectorTab) -> String {
        switch item {
        case .layout: return "Where the screen and camera sit in this scene, corners and shadow"
        case .screen: return "Screen framing in this scene"
        case .camera: return "Camera framing and effects"
        case .secondCamera: return "Camera 2 framing, separate from Camera 1"
        case .background: return "Background, padding and guides"
        }
    }

    private func select(_ item: RecorderInspectorTab) {
        switch item {
        case .layout: vm.selectLayoutInspector()
        case .screen: vm.selectSource(.screen)
        case .camera: vm.selectSource(.camera)
        case .secondCamera: vm.selectLayer(.secondCamera)
        case .background: vm.selectBackgroundLayer()
        }
    }
}

private struct LayerListRow: View {
    struct Visibility {
        let isVisible: Bool
        let isEnabled: Bool
        let toggle: () -> Void
    }

    struct Configuration {
        let title: String
        let symbol: String
        let isSelected: Bool
        /// Background and Layout are always there, so they have no eye.
        let visibility: Visibility?
        let help: String
        let select: () -> Void
    }

    let configuration: Configuration
    @State private var isHovering = false

    private var isHidden: Bool { configuration.visibility?.isVisible == false }

    var body: some View {
        HStack(spacing: 4) {
            Button(action: configuration.select) {
                HStack(spacing: 10) {
                    Image(systemName: configuration.symbol)
                        .font(BlitzType.symbol(13))
                        .symbolVariant(configuration.isSelected ? .fill : .none)
                        .foregroundStyle(configuration.isSelected ? BlitzUI.accent : BlitzUI.secondaryText)
                        .frame(width: 20)
                    Text(configuration.title)
                        .font(BlitzType.navigation)
                        .foregroundStyle(isHidden ? BlitzUI.tertiaryText
                            : configuration.isSelected ? BlitzUI.primaryText : BlitzUI.supportingText)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(height: 30)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(configuration.title)
            .accessibilityAddTraits(configuration.isSelected ? .isSelected : [])
            .help(configuration.help)

            if let visibility = configuration.visibility {
                Button(action: visibility.toggle) {
                    Image(systemName: visibility.isVisible ? "eye" : "eye.slash")
                        .font(BlitzType.symbol(11))
                        .foregroundStyle(visibility.isVisible ? BlitzUI.secondaryText : BlitzUI.tertiaryText)
                        .frame(width: 24, height: 24)
                        .contentShape(.rect)
                }
                .buttonStyle(BlitzPressButtonStyle())
                .disabled(!visibility.isEnabled)
                .opacity(visibility.isVisible && !isHovering && !configuration.isSelected ? 0.55 : 1)
                .help(visibility.isVisible
                      ? "Hide \(configuration.title.lowercased()) in this scene. It still records on its own track."
                      : "Show \(configuration.title.lowercased()) in this scene")
                .accessibilityLabel(visibility.isVisible ? "Hide \(configuration.title)" : "Show \(configuration.title)")
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .background {
            if configuration.isSelected {
                BlitzSelectedBackground(cornerRadius: BlitzUI.controlRadius)
            } else {
                RoundedRectangle(cornerRadius: BlitzUI.controlRadius, style: .continuous)
                    .fill(isHovering ? BlitzUI.quietFill : .clear)
            }
        }
        .onHover { isHovering = $0 }
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
