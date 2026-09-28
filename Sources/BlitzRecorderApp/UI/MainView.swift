import AppKit
import BlitzRecorderCore
import SwiftUI

struct MainView: View {
    struct Configuration {
        let viewModel: RecorderViewModel
        let mcpServer: BlitzRecorderMCPServer
    }

    @Bindable var vm: RecorderViewModel
    private let mcpServer: BlitzRecorderMCPServer
    @State private var retainsEditor = false

    init(configuration: Configuration) {
        vm = configuration.viewModel
        mcpServer = configuration.mcpServer
    }

    var body: some View {
        HStack(spacing: 0) {
            AppNavigationSidebar(vm: vm)
            Rectangle().fill(BlitzUI.separator).frame(width: 1)
                .padding(.top, MainWindowChrome.toolbarHeight)
            ZStack {
                backgroundLayer
                recorderContent()
                    .opacity(vm.studioMode == .record && !vm.isShowingSettings ? 1 : 0)
                    .disabled(vm.studioMode != .record || vm.isShowingSettings)
                    .allowsHitTesting(vm.studioMode == .record && !vm.isShowingSettings)
                    .accessibilityHidden(vm.studioMode != .record || vm.isShowingSettings)

                if (retainsEditor || vm.studioMode == .edit) && vm.canOpenEditor {
                    EditorView(vm: vm)
                        .id(vm.lastExportedProject?.id)
                        .opacity(vm.isEditorVisible ? 1 : 0)
                        .disabled(!vm.isEditorVisible)
                        .allowsHitTesting(vm.isEditorVisible)
                        .accessibilityHidden(!vm.isEditorVisible)
                }
                if vm.studioMode == .projects && !vm.isShowingSettings {
                    ProjectLibraryView(vm: vm)
                }
                if vm.isShowingSettings {
                    SettingsView(configuration: .init(viewModel: vm, mcpServer: mcpServer))
                }
            }
        }
        .background(BlitzUI.panelBackground)
        .ignoresSafeArea(.container, edges: .top)
        .onChange(of: vm.studioMode, initial: true) { _, mode in
            if mode == .edit { retainsEditor = true }
        }
        .overlay {
            if vm.showsFirstRunOnboarding && !vm.isShowingSettings {
                RecordingAccessCover(vm: vm)
            }
        }
        .task {
            await vm.refreshSources()
            vm.syncSettings()
            vm.refreshTargetWindow()
            vm.refreshRecentProjects()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            vm.refreshTargetWindow()
        }
    }

    private func recorderContent() -> some View {
        VStack(spacing: 0) {
            CaptureCommandBar(vm: vm)
                .blitzWindowToolbar(showsUpdate: true)
            recordContent()
        }
    }

    private func recordContent() -> some View {
        HStack(alignment: .top, spacing: 0) {
            if vm.showsRecorderSources {
                SourcesSidebar(vm: vm)
                Rectangle().fill(BlitzUI.separator).frame(width: 1)
            }

            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    RecordingOutputPicker(vm: vm)
                    Spacer(minLength: 0)
                    if vm.state == .idle {
                        HStack(spacing: 8) {
                            Text("Live preview")
                                .font(.system(size: 11))
                                .foregroundStyle(BlitzUI.secondaryText)
                            Toggle("Live preview", isOn: Binding(
                                get: { vm.isLivePreviewEnabled },
                                set: { vm.setLivePreviewEnabled($0) }
                            ))
                            .toggleStyle(.blitzSwitchOnly)
                            .controlSize(.small)
                            .help("Turn the live preview on or off")
                        }
                        .fixedSize()
                    }
                    Button { vm.selectBackgroundLayer() } label: {
                        Label("Canvas", systemImage: "square.on.circle")
                    }
                    .blitzButton(.secondary)
                    .controlSize(.small)
                    .disabled(!vm.canEditScene)
                }

                ZStack(alignment: .top) {
                    PreviewStageRepresentable(view: vm.previewStage)

                    if vm.screenNeedsPicking {
                        ScreenPickPromptOverlay(vm: vm)
                    }

                    SplitDividerOverlay(vm: vm)
                    CropToolbarOverlay(vm: vm)

                    if vm.state == .idle && !vm.isLivePreviewEnabled {
                        Color.black
                            .overlay {
                                VStack(spacing: 12) {
                                    Image(systemName: "eye.slash")
                                        .font(.system(size: 28, weight: .light))
                                        .foregroundStyle(BlitzUI.mint)
                                    Text("Live preview is off")
                                        .font(.system(size: 16, weight: .semibold))
                                    Text("Mac camera, microphone, screen, and system audio start when you record.")
                                        .font(.system(size: 12))
                                        .foregroundStyle(BlitzUI.secondaryText)
                                        .multilineTextAlignment(.center)
                                    Button("Turn on preview") {
                                        vm.setLivePreviewEnabled(true)
                                    }
                                    .blitzButton(.secondary)
                                    .padding(.top, 4)
                                }
                                .padding(24)
                            }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                BottomDock(vm: vm)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
            }
            .padding(14)
            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            .background(BlitzUI.canvasBackground)

            Rectangle().fill(BlitzUI.separator).frame(width: 1)
            SceneWorkspaceInspector(vm: vm)
        }
        .frame(maxHeight: .infinity)
    }

}

enum ScreenSplitDividerGeometry {
    struct Drag {
        let startHeight: Double
        let translation: CGFloat
        let canvasHeight: CGFloat
    }

    static func height(_ drag: Drag) -> Double {
        guard drag.startHeight.isFinite, drag.translation.isFinite,
              drag.canvasHeight.isFinite, drag.canvasHeight > 0 else {
            return Double(SceneLayout.defaultScreenSplitHeight)
        }
        let proposed = drag.startHeight + Double(drag.translation / drag.canvasHeight)
        let clamped = Double(SceneLayout.clampedScreenSplitHeight(CGFloat(proposed)))
        let snapDistance = min(0.018, 6 / Double(drag.canvasHeight))
        return [0.5, 2.0 / 3.0, 0.75].first { abs($0 - clamped) <= snapDistance } ?? clamped
    }
}

private struct SplitDividerOverlay: View {
    @Bindable var vm: RecorderViewModel
    @State private var dragOrigin: DragOrigin?
    @State private var isHovering = false

    private struct DragOrigin {
        let height: Double
        let canvasHeight: CGFloat
    }

    var body: some View {
        GeometryReader { proxy in
            if vm.showsScreenSplitControl, vm.canEditScene,
               !vm.isScreenCropModeEnabled, !vm.isCameraCropModeEnabled,
               !vm.previewCanvasFrame.isEmpty {
                let canvas = vm.previewCanvasFrame
                handle
                    .frame(width: max(0, canvas.width - 2), height: 28)
                    .contentShape(.rect)
                    .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                        .onChanged { value in
                            if dragOrigin == nil {
                                dragOrigin = DragOrigin(height: vm.screenSplitHeight, canvasHeight: canvas.height)
                            }
                            guard let dragOrigin else { return }
                            vm.previewScreenSplitHeight(ScreenSplitDividerGeometry.height(.init(
                                startHeight: dragOrigin.height,
                                translation: value.translation.height,
                                canvasHeight: dragOrigin.canvasHeight
                            )))
                        }
                        .onEnded { _ in
                            guard dragOrigin != nil else { return }
                            vm.commitScreenSplitPreview()
                            dragOrigin = nil
                        }
                    )
                    .position(
                        x: canvas.midX,
                        y: proxy.size.height - canvas.maxY + canvas.height * vm.screenSplitHeight
                    )
                    .onHover {
                        isHovering = $0
                        ($0 ? NSCursor.resizeUpDown : NSCursor.arrow).set()
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Screen and camera divider")
                    .accessibilityValue("\(Int((vm.screenSplitHeight * 100).rounded())) percent screen")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: vm.setScreenSplitHeight(vm.screenSplitHeight + 0.05)
                        case .decrement: vm.setScreenSplitHeight(vm.screenSplitHeight - 0.05)
                        @unknown default: break
                        }
                    }
                    .help("Drag to share space between screen and camera")
            }
        }
        .onChange(of: vm.selectedSceneID) { _, _ in cancelDrag() }
        .onDisappear { cancelDrag() }
    }

    private var handle: some View {
        ZStack {
            Rectangle()
                .fill(BlitzUI.mint.opacity(isHovering || dragOrigin != nil ? 0.8 : 0))
                .frame(height: 1)
            Capsule()
                .fill(.black.opacity(0.7))
                .frame(width: 46, height: 18)
                .overlay {
                    Capsule()
                        .fill(isHovering || dragOrigin != nil ? BlitzUI.mint : .white.opacity(0.85))
                        .frame(width: 24, height: 3)
                }
        }
    }

    private func cancelDrag() {
        dragOrigin = nil
        vm.cancelScreenSplitPreview()
        if isHovering {
            isHovering = false
            NSCursor.arrow.set()
        }
    }
}

private struct CanvasSelectionButton: View {
    @Bindable var vm: RecorderViewModel

    @State private var isHovering = false

    private var isEnabled: Bool {
        vm.canEditScene && !vm.isScreenCropModeEnabled && !vm.isCameraCropModeEnabled
    }

    var body: some View {
        Button {
            vm.selectBackgroundLayer()
        } label: {
            HStack(spacing: 7) {
                CanvasBackgroundSwatchCache.image(vm.settings.canvasBackgroundStyle)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 18, height: 18)
                    .clipShape(.circle)
                    .overlay {
                        Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1)
                    }

                Text("Canvas")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(vm.isBackgroundLayerSelected ? 0.94 : 0.76))
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(BlitzPressButtonStyle())
        .background(buttonFill, in: .rect(cornerRadius: 10))
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .disabled(!isEnabled)
        .pointingHandCursor()
        .help("Edit canvas background and spacing")
    }

    private var buttonFill: Color {
        if vm.isBackgroundLayerSelected {
            return BlitzUI.mint.opacity(0.18)
        }
        return isHovering && isEnabled ? Color.white.opacity(0.11) : BlitzUI.controlFill
    }
}


private struct ProductIconImage: View {
    let image: NSImage?
    let fallbackSystemImage: String
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                Image(systemName: fallbackSystemImage)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.68))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

private extension Bundle {
    var blitzRecorderCameraIcon: NSImage? {
        guard let url = url(forResource: "CompanionAppIcon", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

struct CropToolbarOverlay: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        GeometryReader { proxy in
            if let frame = vm.cropToolbarFrame,
               vm.isScreenCropModeEnabled || vm.isCameraCropModeEnabled {
                CropFloatingToolbar(configuration: cropToolbarConfiguration)
                    .fixedSize()
                    .position(
                        x: frame.midX,
                        y: proxy.size.height - frame.midY
                    )
            }
        }
    }

    private var cropToolbarConfiguration: CropFloatingToolbarConfiguration {
        CropFloatingToolbarConfiguration(
            onDone: {
                if vm.isCameraCropModeEnabled {
                    vm.applyCameraCropMode()
                } else {
                    vm.applyScreenCropMode()
                }
            },
            onReset: {
                if vm.isCameraCropModeEnabled {
                    vm.resetCameraCrop()
                } else {
                    vm.resetScreenCropMode()
                }
            },
            onCancel: {
                if vm.isCameraCropModeEnabled {
                    vm.cancelCameraCropMode()
                } else {
                    vm.cancelScreenCropMode()
                }
            }
        )
    }
}

private struct ScreenPickPromptOverlay: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        GeometryReader { proxy in
            if let frame = vm.screenLayerFrame, frame.width > 1, frame.height > 1 {
                ScreenPickPrompt(vm: vm)
                    .fixedSize()
                    .position(x: frame.midX, y: proxy.size.height - frame.midY)
            } else {
                ScreenPickPrompt(vm: vm)
                    .fixedSize()
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        }
    }
}

private struct ScreenPickPrompt: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        Button {
            vm.pickScreen()
        } label: {
            Text(vm.screenPickActionTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(.black.opacity(0.68), in: .rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.24), radius: 12, y: 4)
                .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help("Choose an app window and fit it to the current scene")
    }
}

struct CropFloatingToolbarConfiguration {
    let onDone: () -> Void
    let onReset: () -> Void
    let onCancel: () -> Void
}

struct CropFloatingToolbar: View {
    let configuration: CropFloatingToolbarConfiguration

    private let accent = BlitzUI.mint

    var body: some View {
        HStack(spacing: 8) {
            Button(action: configuration.onDone) {
                Label("Done cropping", systemImage: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black.opacity(0.88))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(accent, in: .rect(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()

            Button(action: configuration.onReset) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 28, height: 28)
            }
            .blitzButton(.secondary)
            .controlSize(.small)
            .pointingHandCursor()

            Button(action: configuration.onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 28, height: 28)
            }
            .blitzButton(.secondary)
            .controlSize(.small)
            .pointingHandCursor()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .foregroundStyle(.white)
        .background(.black.opacity(0.70), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct RecordingQualityShortcut: View {
    @Bindable var vm: RecorderViewModel
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 9) {
                BlitzSymbol(configuration: .init(name: BlitzSymbols.videoQuality, size: 18))
                    .foregroundStyle(BlitzUI.secondaryText)
                Text(vm.settings.outputResolution.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BlitzUI.primaryText)
                Rectangle()
                    .fill(BlitzUI.panelStroke)
                    .frame(width: 1, height: 12)
                Text("\(vm.settings.framesPerSecond) FPS")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(BlitzUI.secondaryText)
                BlitzMenuChevron()
            }
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 36)
        }
        .buttonStyle(BlitzMenuTriggerStyle(isPresented: isPresented))
        .accessibilityLabel("Recording quality, \(qualityPresentation.controlLabel)")
        .disabled(vm.state != .idle)
        .help("Choose recording resolution and Source FPS")
        .onChange(of: vm.state) {
            if vm.state != .idle { isPresented = false }
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            qualityPopover
        }
    }

    private var qualityPopover: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recording quality")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BlitzUI.primaryText)
                Text(resolutionDimensions)
                    .font(.system(size: 11))
                    .foregroundStyle(BlitzUI.secondaryText)
                    .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Resolution")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(BlitzUI.secondaryText)
                BlitzSegmentedPicker(configuration: .init(
                    title: "Recording resolution",
                    options: OutputResolution.allCases,
                    selection: Binding(get: { vm.settings.outputResolution }, set: { vm.setResolution($0) }),
                    label: { $0.displayName }
                ))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Source FPS")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(BlitzUI.secondaryText)
                BlitzSegmentedPicker(configuration: .init(
                    title: "Source FPS",
                    options: RecordingSettings.supportedFrameRates,
                    selection: Binding(get: { vm.settings.framesPerSecond }, set: { vm.setFrameRate($0) }),
                    label: { "\($0) FPS" }
                ))
                Text(frameRateDescription)
                    .font(.system(size: 10))
                    .foregroundStyle(BlitzUI.secondaryText)
            }
        }
        .disabled(vm.state != .idle)
        .padding(16)
        .frame(width: 288)
        .preferredColorScheme(.dark)
    }

    private var qualityPresentation: RecordingQualityPresentation {
        RecordingQualityPresentation(settings: vm.settings)
    }

    private var resolutionDimensions: String {
        let dimensions = vm.settings.outputResolution.dimensions(for: vm.settings.layout)
        return "\(dimensions.width) × \(dimensions.height)"
    }

    private var frameRateDescription: String {
        switch vm.settings.framesPerSecond {
        case 24: return "Cinematic motion"
        case 60: return "Extra smooth motion"
        default: return "Standard motion"
        }
    }
}

private struct CaptureCommandBar: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        HStack(spacing: 16) {
            BlitzToolbarButton(configuration: .init(
                title: vm.showsRecorderSources ? "Hide sources and scenes" : "Show sources and scenes",
                symbolName: "sidebar.left",
                showsTitle: false,
                action: { vm.showsRecorderSources.toggle() }
            ))
            .accessibilityValue(vm.showsRecorderSources ? "Visible" : "Hidden")
            Text("Recorder")
                .font(.system(size: 15, weight: .semibold))
            Rectangle().fill(BlitzUI.separator).frame(width: 1, height: 16)

            statusRow

            Spacer(minLength: 16)

            RecordingQualityShortcut(vm: vm)

        }
    }

    private var isBlocked: Bool {
        vm.studioMode == .record && vm.state == .idle && !vm.recordingReadiness.isReady
    }

    @ViewBuilder private var statusRow: some View {
        if isBlocked {
            Button { vm.openReadinessDetails() } label: { statusContent(showChevron: true) }
                .buttonStyle(.plain)
                .help(vm.recordingReadiness.detail)
                .pointingHandCursor()
        } else {
            statusContent(showChevron: false)
        }
    }

    private func statusContent(showChevron: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusDotColor)
                .frame(width: 7, height: 7)
            Text(statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.60))
                .lineLimit(1)
                .monospacedDigit()
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .contentShape(.rect)
    }

    private var statusDotColor: Color {
        if vm.studioMode == .edit && vm.state == .idle {
            return BlitzUI.mint
        }
        switch vm.state {
        case .recording: return BlitzUI.recordRed
        case .paused, .starting, .finishing: return BlitzUI.warning
        case .idle: return vm.recordingReadiness.isReady ? BlitzUI.mint : BlitzUI.warning
        }
    }

    private var statusText: String {
        if vm.studioMode == .edit && vm.state == .idle {
            return "Edit and export last take"
        }
        switch vm.state {
        case .recording: return "Recording  \(vm.formattedElapsed)"
        case .paused: return "Paused  \(vm.formattedElapsed)"
        case .starting: return "Starting…"
        case .finishing: return vm.sessionProgressTitle
        case .idle:
            let readiness = vm.recordingReadiness
            return readiness.isReady ? "Ready to record" : readiness.blockers.shortSummary
        }
    }
}

struct CaptureScenePicker: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Scenes")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BlitzUI.primaryText)
                Text(vm.state == .recording || vm.state == .paused
                     ? "Select a scene to go live" : "Select a scene to edit its layout")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(BlitzUI.secondaryText)
            }
            .padding(.horizontal, 2)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(vm.currentScenes) { scene in
                    sceneButton(scene)
                }
            }

            newSceneButton
        }
        .frame(maxWidth: .infinity)
    }

    private func sceneButton(_ scene: RecordingSceneDefinition) -> some View {
        let isSelected = vm.selectedSceneID == scene.id
        return Button {
            vm.selectScene(scene.id)
        } label: {
            VStack(spacing: 6) {
                SceneWorkspaceThumbnail(scene: scene, enabledSources: vm.settings.enabledSources)
                    .frame(width: 68, height: 44)

                Text(scene.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(isSelected ? 0.94 : 0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BlitzUI.mint)
                        .padding(7)
                        .allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(BlitzScenePresetButtonStyle(isSelected: isSelected))
        .disabled(!vm.canSwitchScene)
        .opacity(vm.canSwitchScene || isSelected ? 1 : 0.5)
        .pointingHandCursor()
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .help(vm.state == .idle ? "Edit \(scene.name)" : "Switch to \(scene.name)")
        .contextMenu {
            Button("Duplicate Scene") {
                vm.selectScene(scene.id)
                vm.duplicateSelectedScene()
            }
            .disabled(!vm.canEditScene)

            Divider()

            Button("Delete \(scene.name)", role: .destructive) {
                vm.deleteScene(scene.id)
            }
            .disabled(!vm.canEditScene || vm.currentScenes.count <= 1)
        }
    }

    private var newSceneButton: some View {
        Button {
            vm.createScene()
        } label: {
            Label("Add scene", systemImage: "plus")
                .frame(maxWidth: .infinity, minHeight: 24)
        }
        .blitzButton(.secondary)
        .controlSize(.small)
        .disabled(!vm.canEditScene)
        .pointingHandCursor()
        .help("Create a scene from this layout, then customize it in the preview")
    }
}

private struct SceneEditorHeader: View {
    @Bindable var vm: RecorderViewModel

    @State private var isEditing = false
    @State private var draft = ""
    @State private var showsDeleteConfirmation = false
    @FocusState private var isNameFocused: Bool

    private var canDelete: Bool {
        vm.canEditScene && vm.currentScenes.count > 1
    }

    private var selectedSceneIndex: Int? {
        guard let id = vm.selectedSceneID else { return nil }
        return vm.currentScenes.firstIndex(where: { $0.id == id })
    }

    private var canMoveEarlier: Bool {
        vm.canEditScene && (selectedSceneIndex ?? 0) > 0
    }

    private var canMoveLater: Bool {
        guard vm.canEditScene, let selectedSceneIndex else { return false }
        return selectedSceneIndex < vm.currentScenes.count - 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if isEditing {
                    nameField
                    commitButton
                    cancelButton
                } else {
                    nameLabel
                    Spacer(minLength: 0)
                    Button("Rename", action: beginEditing)
                        .blitzButton(.quiet)
                        .controlSize(.mini)
                        .disabled(!vm.canEditScene)
                        .accessibilityLabel("Rename scene")
                        .help("Rename this scene")
                }
            }
            Text(vm.state == .recording || vm.state == .paused
                 ? "Live scene · Changes apply now" : "Editing scene · Saved automatically")
                .font(.system(size: 10))
                .foregroundStyle(BlitzUI.secondaryText)
            HStack(spacing: 8) {
                Button { vm.duplicateSelectedScene() } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                .blitzButton(.quiet)
                .controlSize(.mini)
                .disabled(!vm.canEditScene)
                .help("Make a copy of this scene to customize")
                Spacer(minLength: 0)
                if canMoveEarlier || canMoveLater || canDelete { sceneActions }
            }
        }
        .padding(.bottom, 2)
        .onChange(of: vm.selectedSceneID) { _, _ in
            if isEditing { exitEditing(commit: false) }
        }
        .onChange(of: vm.canEditScene) { _, canEdit in
            if !canEdit && isEditing { exitEditing(commit: false) }
        }
        .confirmationDialog(
            "Delete \(vm.selectedSceneName)?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete scene", role: .destructive) {
                if let id = vm.selectedSceneID {
                    vm.deleteScene(id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the scene and its layout from this workspace.")
        }
    }

    private var nameLabel: some View {
        Text(vm.selectedSceneName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white.opacity(0.94))
            .lineLimit(1)
            .truncationMode(.tail)
            .contentShape(.rect)
            .onTapGesture(count: 2) {
                if vm.canEditScene { beginEditing() }
            }
            .help(vm.canEditScene ? "Double-click to rename this scene" : vm.selectedSceneName)
    }

    private var nameField: some View {
        TextField("Scene name", text: $draft)
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .focused($isNameFocused)
            .frame(maxWidth: .infinity)
            .onSubmit { exitEditing(commit: true) }
            .onExitCommand { exitEditing(commit: false) }
            .onChange(of: isNameFocused) { _, focused in
                guard !focused, isEditing else { return }
                DispatchQueue.main.async {
                    if isEditing { exitEditing(commit: false) }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(BlitzUI.quietFill, in: .rect(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(BlitzUI.mint.opacity(0.46), lineWidth: 1)
            }
    }

    private var commitButton: some View {
        Button {
            exitEditing(commit: true)
        } label: {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(BlitzUI.mint)
                .frame(width: 24, height: 24)
        }
        .blitzButton(.secondary)
        .controlSize(.small)
        .pointingHandCursor()
        .accessibilityLabel("Save scene name")
        .help("Save name (Return)")
    }

    private var cancelButton: some View {
        Button {
            exitEditing(commit: false)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 24, height: 24)
        }
        .blitzButton(.secondary)
        .controlSize(.small)
        .pointingHandCursor()
        .accessibilityLabel("Cancel rename")
        .help("Cancel (Esc)")
    }

    private var sceneActions: some View {
        BlitzGlassMenu(entries: sceneActionEntries, menuWidth: 210) {
            HStack(spacing: 6) {
                Text("Organize")
                BlitzMenuChevron()
            }
            .font(.system(size: 11))
            .foregroundStyle(BlitzUI.secondaryText)
            .padding(.horizontal, 8)
            .frame(height: BlitzControlMetrics.height(.mini))
        }
        .disabled(!vm.canEditScene)
        .accessibilityLabel("Organize scene")
        .pointingHandCursor()
        .help("Move or delete this scene")
    }

    private var sceneActionEntries: [BlitzMenuEntry] {
        var entries: [BlitzMenuEntry] = []
        if canMoveEarlier {
            entries.append(.item(BlitzMenuItem(title: "Move earlier", systemImage: "arrow.left") {
                guard let id = vm.selectedSceneID else { return }
                vm.moveScene(id, direction: .up)
            }))
        }
        if canMoveLater {
            entries.append(.item(BlitzMenuItem(title: "Move later", systemImage: "arrow.right") {
                guard let id = vm.selectedSceneID else { return }
                vm.moveScene(id, direction: .down)
            }))
        }
        if canDelete {
            entries.append(.divider)
            entries.append(.item(BlitzMenuItem(
                title: "Delete scene…",
                systemImage: "trash",
                isDestructive: true
            ) {
                showsDeleteConfirmation = true
            }))
        }
        return entries
    }

    private func beginEditing() {
        guard vm.canEditScene else { return }
        draft = vm.selectedSceneName
        isEditing = true
        DispatchQueue.main.async { isNameFocused = true }
    }

    private func exitEditing(commit: Bool) {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if commit, !trimmed.isEmpty, trimmed != vm.selectedSceneName, let id = vm.selectedSceneID {
            vm.renameScene(id, to: trimmed)
        }
        isEditing = false
        isNameFocused = false
    }
}

private struct SceneWorkspaceInspector: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        VStack(spacing: 0) {
            SceneEditorHeader(vm: vm)
                .padding(14)
            Rectangle().fill(BlitzUI.separator).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    layoutPicker
                    if vm.showsScreenSplitControl { splitHeightControl }
                    Rectangle().fill(BlitzUI.separator).frame(height: 1)
                    contextHeader
                    if vm.isBackgroundLayerSelected {
                        backgroundControls
                    } else {
                        SelectedSourceInspector(vm: vm)
                        if vm.selectedSource?.source == .camera { CameraCropControls(vm: vm) }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
        }
        .frame(minWidth: 264, idealWidth: 280, maxWidth: 280)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(BlitzUI.panelBackground)
    }

    private var layoutPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Layout")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                Button("Reset", action: vm.resetSceneLayout)
                    .blitzButton(.quiet)
                    .controlSize(.mini)
                    .disabled(!vm.canEditScene)
                    .accessibilityLabel("Reset scene layout")
                    .help("Reset the layout of this scene")
                if vm.activeScenePreset == nil {
                    Text("Custom")
                        .font(.system(size: 10))
                        .foregroundStyle(BlitzUI.secondaryText)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(ScenePreset.allCases.filter { $0.supports(vm.settings.layout) }, id: \.self) { preset in
                    BlitzScenePresetCard(
                        preset: preset,
                        layout: vm.settings.layout,
                        isSelected: vm.isScenePresetActive(preset),
                        isEnabled: vm.canEditScene,
                        availableSources: [.screen, .camera]
                    ) {
                        vm.setScenePreset(preset)
                    }
                    .help("Apply \(preset.compactTitle) to this scene")
                }
            }
            Text("Drag the sources in the preview to customize.")
                .font(.system(size: 10))
                .foregroundStyle(BlitzUI.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var contextHeader: some View {
        HStack(spacing: 8) {
            Text(contextTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BlitzUI.primaryText)
            Spacer(minLength: 0)
            if let layer = vm.inspectorSelection.sceneLayer {
                Button {
                    vm.setSourceVisible(layer.source, visible: !vm.isSourceVisible(layer.source))
                } label: {
                    BlitzSymbol(configuration: .init(
                        name: vm.isSourceVisible(layer.source) ? "eye" : "eye.slash",
                        size: 18
                    ))
                    .foregroundStyle(BlitzUI.secondaryText)
                    .frame(width: 32, height: 32)
                }
                .buttonStyle(BlitzSelectionButtonStyle(isSelected: false))
                .disabled(!vm.canEditScene)
                .accessibilityLabel("\(vm.isSourceVisible(layer.source) ? "Hide" : "Show") \(contextTitle) in this scene")
                .help("Show or hide this layer in the scene. Its source keeps recording.")
                .pointingHandCursor()

                Button("Fit", action: vm.fitSelectedLayer)
                    .blitzButton(.quiet)
                    .controlSize(.mini)
                    .disabled(!vm.canEditScene)
                    .accessibilityLabel("Fit \(contextTitle.lowercased()) layer")
                    .help("Fit this layer to its space in the scene")
            }
        }
    }

    private var contextTitle: String {
        if vm.isBackgroundLayerSelected {
            return "Canvas"
        }
        switch vm.selectedSource?.source ?? .screen {
        case .screen: return "Screen"
        case .camera: return "Camera"
        case .microphone: return "Microphone"
        case .systemAudio: return "System audio"
        }
    }

    private var backgroundControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("Padding")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.58))
                    Spacer(minLength: 0)
                    Text("\(Int((vm.settings.canvasPadding * 100).rounded()))%")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.7))
                }
                Slider(
                    value: Binding(
                        get: { Double(vm.settings.canvasPadding) },
                        set: { vm.setCanvasPadding(CGFloat($0)) }
                    ),
                    in: 0...0.12,
                    step: 0.005
                )
                .controlSize(.small)
                .tint(BlitzUI.mint)
                .disabled(!vm.canEditScene)
            }

            Toggle(isOn: Binding(
                get: { vm.settings.showsRuleOfThirdsOverlay },
                set: { vm.setRuleOfThirds($0) }
            )) {
                Label("Rule of thirds", systemImage: "grid")
                    .font(.system(size: 12, weight: .semibold))
            }
            .toggleStyle(.blitzSwitch)
            .disabled(!vm.canEditScene)

            if vm.settings.canvasBackgroundStyle.supportsBackgroundAnimation {
                Toggle(isOn: Binding(
                    get: { vm.settings.canvasBackgroundAnimated },
                    set: { vm.setCanvasBackgroundAnimated($0) }
                )) {
                    Label("Animate", systemImage: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                }
                .toggleStyle(.blitzSwitch)
                .tint(BlitzUI.mint)
                .disabled(!vm.canEditScene)
                .help("Slowly drift the background colors")
            }


            SceneBackgroundSwatchRow(vm: vm)
        }
    }

    private var splitHeightControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Split height")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.58))
                Spacer(minLength: 0)
                Text("\(Int((vm.screenSplitHeight * 100).rounded()))%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
            }

            Slider(
                value: Binding(
                    get: { vm.screenSplitHeight },
                    set: { vm.setScreenSplitHeight($0) }
                ),
                in: Double(SceneLayout.minimumScreenSplitHeight)...Double(SceneLayout.maximumScreenSplitHeight),
                step: 0.01
            )
            .controlSize(.small)
            .tint(BlitzUI.mint)
            .disabled(!vm.canEditScene)
            .accessibilityLabel("Split height")
            .help("Adjust the space shared by the screen and camera in this scene")

            HStack {
                Text("More camera")
                Spacer(minLength: 0)
                Text("More screen")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.46))
        }
    }

}

private struct SceneBackgroundSwatchRow: View {
    @Bindable var vm: RecorderViewModel

    private let columns = [GridItem(.adaptive(minimum: 38, maximum: 38), spacing: 8, alignment: .leading)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            swatchSection("Mesh", styles: meshStyles)
            swatchSection("macOS", styles: macOSStyles)
            swatchSection("Seasonal", styles: seasonalStyles)
            swatchSection("Studio", styles: studioStyles)
        }
        .padding(.vertical, 1)
        .disabled(!vm.canEditScene)
        .opacity(vm.canEditScene ? 1 : 0.52)
    }

    private var meshStyles: [CanvasBackgroundStyle] {
        CanvasBackgroundStyle.allCases.filter {
            !$0.isSystemWallpaper && !$0.isSeasonalWallpaper && !$0.isStudioWallpaper
        }
    }

    private var macOSStyles: [CanvasBackgroundStyle] {
        CanvasBackgroundStyle.allCases.filter(\.isSystemWallpaper)
    }

    private var seasonalStyles: [CanvasBackgroundStyle] {
        CanvasBackgroundStyle.allCases.filter(\.isSeasonalWallpaper)
    }

    private var studioStyles: [CanvasBackgroundStyle] {
        CanvasBackgroundStyle.allCases.filter(\.isStudioWallpaper)
    }

    private func swatchSection(_ title: String, styles: [CanvasBackgroundStyle]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.46))

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(styles, id: \.self) { style in
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
                .frame(width: 38, height: 38)
                .clipShape(.rect(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isSelected ? BlitzUI.mint : .white.opacity(0.14),
                            lineWidth: isSelected ? 2 : 1
                        )
                }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help(style.displayName)
    }
}

private struct SceneWorkspaceThumbnail: View {
    let scene: RecordingSceneDefinition
    let enabledSources: Set<CaptureSource>

    var body: some View {
        BlitzSceneLayoutThumbnail(
            layout: scene.layout,
            sceneLayout: scene.snapshot.sceneLayout,
            visibleSources: scene.snapshot.enabledVideoSources.intersection(enabledSources).subtracting(scene.snapshot.hiddenVideoSources)
        )
    }
}

private extension MainView {
    var backgroundLayer: some View {
        BlitzUI.canvasBackground
            .ignoresSafeArea()
    }
}
