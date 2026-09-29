import SwiftUI

enum RecorderInspectorTab: CaseIterable, Hashable {
    case screen
    case camera
    case audio
    case background

    var title: String {
        switch self {
        case .screen: return "Screen"
        case .camera: return "Camera"
        case .audio: return "Audio"
        case .background: return "Background"
        }
    }

    var symbolName: String {
        switch self {
        case .screen: return BlitzSymbols.screen
        case .camera: return BlitzSymbols.camera
        case .audio: return "waveform"
        case .background: return "photo"
        }
    }

    init(selection: RecorderInspectorSelection) {
        switch selection {
        case .canvas: self = .background
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
        .frame(minWidth: 264, idealWidth: 280, maxWidth: 280)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(BlitzUI.panelBackground)
        .foregroundStyle(BlitzUI.primaryText)
        .tint(BlitzUI.mint)
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(RecorderInspectorTab.allCases, id: \.self) { item in
                BlitzTab(configuration: .init(
                    title: item.title,
                    symbolName: item.symbolName,
                    symbolPlacement: .above,
                    isSelected: tab == item,
                    expands: true,
                    action: { select(item) }
                ))
                .disabled(!isEnabled(item))
                .help(help(for: item))
            }
        }
        .controlSize(.mini)
        .padding(6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scene settings")
    }

    @ViewBuilder
    private var pane: some View {
        switch tab {
        case .screen: screenPane
        case .camera: cameraPane
        case .audio: audioPane
        case .background: backgroundPane
        }
    }

    private var screenPane: some View {
        Group {
            notice(for: .screen)
            EditorInspectorSection(configuration: .init(title: "Framing") {
                ScreenSourceInspector(vm: vm, enabled: vm.isSourceConfigured(.screen))
            })
            sceneSection(for: .screen)
        }
    }

    private var cameraPane: some View {
        Group {
            notice(for: .camera)
            if vm.isCameraInsetLayout && !vm.isCameraCropModeEnabled {
                EditorInspectorSection(configuration: .init(title: "Corner") {
                    CameraInsetFrameControls(vm: vm)
                })
            }
            EditorInspectorSection(configuration: .init(title: "Framing") {
                CameraCropControls(vm: vm)
            })
            EditorInspectorSection(configuration: .init(title: "Effects") {
                CameraSourceInspector(vm: vm, enabled: vm.isSourceConfigured(.camera))
                if vm.isCameraInsetLayout {
                    Toggle("Shadow", isOn: Binding(
                        get: { vm.settings.cameraShadowEnabled },
                        set: { vm.setCameraShadowEnabled($0) }
                    ))
                    .toggleStyle(.blitzSwitch)
                    .disabled(!vm.canEditScene)
                    .help("Add a soft shadow under the camera")
                }
            })
            sceneSection(for: .camera)
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
                    Toggle("Slowly move the colors", isOn: Binding(
                        get: { vm.settings.canvasBackgroundAnimated },
                        set: { vm.setCanvasBackgroundAnimated($0) }
                    ))
                    .toggleStyle(.blitzSwitch)
                    .disabled(!vm.canEditScene)
                }
            })
            EditorInspectorSection(configuration: .init(title: "Spacing and guides") {
                BlitzInspectorSlider(configuration: .init(
                    title: "Padding",
                    value: Binding(
                        get: { Double(vm.settings.canvasPadding) },
                        set: { vm.setCanvasPadding(CGFloat($0)) }
                    ),
                    range: 0...0.12,
                    step: 0.005,
                    valueLabel: "\(Int((vm.settings.canvasPadding / 0.12 * 100).rounded()))%",
                    onEditingChanged: { _ in },
                    onReset: { vm.setCanvasPadding(0) }
                ))
                .disabled(!vm.canEditScene)
                Toggle("Show framing guides", isOn: Binding(
                    get: { vm.settings.showsRuleOfThirdsOverlay },
                    set: { vm.setRuleOfThirds($0) }
                ))
                .toggleStyle(.blitzSwitch)
                .disabled(!vm.canEditScene)
                .help("Show rule-of-thirds lines on the preview. They are never recorded.")
                if vm.settings.layout == .vertical {
                    Toggle("Show app safe zones", isOn: $showsSafeZones)
                        .toggleStyle(.blitzSwitch)
                        .help("Shade where TikTok, Reels and Shorts put captions and buttons. Never recorded.")
                }
            })
        }
    }

    @ViewBuilder
    private func notice(for source: CaptureSource) -> some View {
        if let notice = vm.sourceReadinessNotice(source), notice.action != .chooseScreen {
            SourceReadinessNoticeView(notice: notice, vm: vm)
        }
    }

    private func sceneSection(for source: CaptureSource) -> some View {
        let isVisible = vm.isSourceVisible(source)
        let name = source == .screen ? "screen" : "camera"
        return EditorInspectorSection(configuration: .init(title: "In \(vm.selectedSceneName)") {
            HStack(spacing: 8) {
                Button {
                    vm.setSourceVisible(source, visible: !isVisible)
                } label: {
                    Label(isVisible ? "Hide" : "Show", systemImage: isVisible ? "eye.slash.fill" : "eye.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!vm.isSourceConfigured(source))
                .help(isVisible
                    ? "Hide the \(name) in this scene. It keeps recording on its own track."
                    : "Show the \(name) in this scene")
                Button(action: vm.fitSelectedLayer) {
                    Label("Fit", systemImage: "arrow.up.left.and.arrow.down.right")
                        .frame(maxWidth: .infinity)
                }
                .help("Fit this layer to its space in the scene")
                Button(action: vm.resetSceneLayout) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .help("Put every layer of this scene back where it started")
            }
            .blitzButton(.secondary)
            .disabled(!vm.canEditScene)
            if !isVisible {
                Text("Hidden here. Still recording on its own track.")
                    .font(BlitzType.caption)
                    .foregroundStyle(BlitzUI.secondaryText)
            }
        })
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
        case .screen: return vm.isSourceConfigured(.screen)
        case .camera: return vm.isSourceConfigured(.camera)
        case .audio: return vm.isSourceConfigured(.microphone) || vm.isSourceConfigured(.systemAudio)
        case .background: return true
        }
    }

    private func help(for item: RecorderInspectorTab) -> String {
        switch item {
        case .screen: return "Screen framing in this scene"
        case .camera: return "Camera framing and effects"
        case .audio: return "Microphone and Mac audio volume"
        case .background: return "Background and spacing"
        }
    }

    private func select(_ item: RecorderInspectorTab) {
        switch item {
        case .screen: vm.selectSource(.screen)
        case .camera: vm.selectSource(.camera)
        case .audio: vm.selectSource(vm.isSourceConfigured(.microphone) ? .microphone : .systemAudio)
        case .background: vm.selectBackgroundLayer()
        }
    }
}

struct SceneBackgroundSwatchRow: View {
    @Bindable var vm: RecorderViewModel

    private let columns = [GridItem(.adaptive(minimum: 36, maximum: 40), spacing: 8, alignment: .leading)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            swatchSection(.init(title: "Gradients", styles: CanvasBackgroundStyle.allCases.filter {
                !$0.isSystemWallpaper && !$0.isSeasonalWallpaper && !$0.isStudioWallpaper
            }))
            swatchSection(.init(title: "macOS", styles: CanvasBackgroundStyle.allCases.filter(\.isSystemWallpaper)))
            swatchSection(.init(title: "Seasons", styles: CanvasBackgroundStyle.allCases.filter(\.isSeasonalWallpaper)))
            swatchSection(.init(title: "Studio", styles: CanvasBackgroundStyle.allCases.filter(\.isStudioWallpaper)))
        }
        .disabled(!vm.canEditScene)
        .opacity(vm.canEditScene ? 1 : 0.52)
    }

    private struct SwatchSection {
        let title: String
        let styles: [CanvasBackgroundStyle]
    }

    private func swatchSection(_ section: SwatchSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.title)
                .font(BlitzType.captionEmphasis)
                .foregroundStyle(BlitzUI.secondaryText)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(section.styles, id: \.self) { style in
                    swatch(style)
                }
            }
        }
    }

    private func swatch(_ style: CanvasBackgroundStyle) -> some View {
        let isSelected = vm.settings.canvasBackgroundStyle == style
        return Button {
            vm.setCanvasBackgroundStyle(style)
        } label: {
            CanvasBackgroundSwatchCache.image(style)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(.rect(cornerRadius: BlitzUI.controlRadius))
                .padding(3)
                .background(isSelected ? BlitzUI.selectedFill : .clear, in: .rect(cornerRadius: BlitzUI.cardRadius))
                .overlay(alignment: .bottomTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(BlitzType.glyph(13))
                            .foregroundStyle(BlitzUI.mint)
                            .background(Circle().fill(.black))
                            .offset(x: 2, y: 2)
                    }
                }
                .contentShape(.rect(cornerRadius: BlitzUI.cardRadius))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .help(style.displayName)
    }
}
