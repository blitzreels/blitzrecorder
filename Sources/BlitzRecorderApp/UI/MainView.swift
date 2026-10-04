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
        .environment(\.workspaceRecorder, vm)
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
        .task(id: vm.state) {
            vm.refreshScreenSuggestion()
            while vm.state == .recording && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                vm.refreshScreenSuggestion()
            }
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
            SourcesSidebar(vm: vm)
            Rectangle().fill(BlitzUI.separator).frame(width: 1)

            VStack(spacing: 12) {
                ZStack(alignment: .top) {
                    PreviewStageRepresentable(view: vm.previewStage)
                        .accessibilityElement()
                        .accessibilityLabel("Scene preview, \(vm.selectedSceneName)")
                        .accessibilityHint("Use the actions to choose which layer to edit.")
                        .accessibilityAction(named: "Edit screen") { vm.selectSource(.screen) }
                        .accessibilityAction(named: "Edit camera") { vm.selectSource(.camera) }
                        .accessibilityAction(named: "Edit background") { vm.selectBackgroundLayer() }

                    if vm.screenNeedsPicking {
                        ScreenPickPromptOverlay(vm: vm)
                    }

                    SplitDividerOverlay(vm: vm)
                    SideSplitDividerOverlay(vm: vm)
                    CropToolbarOverlay(vm: vm)
                    ShortFormSafeZoneOverlay(vm: vm)

                    if let remaining = vm.countdownRemaining {
                        RecordingCountdownOverlay(configuration: .init(
                            remaining: remaining,
                            onCancel: vm.cancelCountdown
                        ))
                    }

                    if vm.state == .idle && !vm.isLivePreviewEnabled {
                        Color.black
                            .overlay {
                                VStack(spacing: 12) {
                                    Image(systemName: "eye.slash")
                                        .font(BlitzType.glyph(28))
                                        .foregroundStyle(BlitzUI.mint)
                                    Text("Live preview is off")
                                        .font(BlitzType.title)
                                    Text("Mac camera, microphone, screen, and system audio start when you record.")
                                        .font(BlitzType.body)
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
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            .background(BlitzUI.canvasBackground)

            Rectangle().fill(BlitzUI.separator).frame(width: 1)
            RecorderLayerInspector(vm: vm)
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

enum SideSplitDividerGeometry {
    struct Drag {
        let startWidth: Double
        let translation: CGFloat
        let canvasWidth: CGFloat
        let cameraIsLeft: Bool
        let layout: CaptureLayout
    }

    static func width(_ drag: Drag) -> Double {
        guard drag.startWidth.isFinite, drag.translation.isFinite,
              drag.canvasWidth.isFinite, drag.canvasWidth > 0 else {
            return Double(SceneLayout.defaultSideBySideCameraWidth(for: drag.layout))
        }
        let delta = Double(drag.translation / drag.canvasWidth) * (drag.cameraIsLeft ? 1 : -1)
        let clamped = Double(SceneLayout.clampedSideBySideCameraWidth(CGFloat(drag.startWidth + delta)))
        let snapDistance = min(0.018, 6 / Double(drag.canvasWidth))
        let portrait = Double(SceneLayout.portraitCameraWidth(for: drag.layout))
        return [portrait, 0.5].first { abs($0 - clamped) <= snapDistance } ?? clamped
    }
}

private struct SideSplitDividerOverlay: View {
    @Bindable var vm: RecorderViewModel
    @State private var dragOrigin: DragOrigin?
    @State private var isHovering = false

    private struct DragOrigin {
        let width: Double
        let canvasWidth: CGFloat
    }

    var body: some View {
        GeometryReader { proxy in
            if vm.showsSideSplitControl, vm.canEditScene,
               !vm.isScreenCropModeEnabled, !vm.isCameraCropModeEnabled,
               !vm.previewCanvasFrame.isEmpty {
                let canvas = vm.previewCanvasFrame
                let dividerX = vm.sideSplitCameraIsLeft ? vm.sideSplitCameraWidth : 1 - vm.sideSplitCameraWidth
                handle
                    .frame(width: 28, height: max(0, canvas.height - 2))
                    .contentShape(.rect)
                    .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                        .onChanged { value in
                            if dragOrigin == nil {
                                dragOrigin = DragOrigin(width: vm.sideSplitCameraWidth, canvasWidth: canvas.width)
                            }
                            guard let dragOrigin else { return }
                            vm.previewSideSplitCameraWidth(SideSplitDividerGeometry.width(.init(
                                startWidth: dragOrigin.width,
                                translation: value.translation.width,
                                canvasWidth: dragOrigin.canvasWidth,
                                cameraIsLeft: vm.sideSplitCameraIsLeft,
                                layout: vm.settings.layout
                            )))
                        }
                        .onEnded { _ in
                            guard dragOrigin != nil else { return }
                            vm.commitSideSplitPreview()
                            dragOrigin = nil
                        }
                    )
                    .onHover {
                        isHovering = $0
                        ($0 ? NSCursor.resizeLeftRight : NSCursor.arrow).set()
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Camera and screen divider")
                    .accessibilityValue("\(Int((vm.sideSplitCameraWidth * 100).rounded())) percent camera")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: vm.setSideSplitCameraWidth(vm.sideSplitCameraWidth + 0.05)
                        case .decrement: vm.setSideSplitCameraWidth(vm.sideSplitCameraWidth - 0.05)
                        @unknown default: break
                        }
                    }
                    .help("Drag to share space between camera and screen")
                    .position(
                        x: canvas.minX + canvas.width * dividerX,
                        y: proxy.size.height - canvas.midY
                    )
            }
        }
        .onChange(of: vm.selectedSceneID) { _, _ in cancelDrag() }
        .onDisappear { cancelDrag() }
    }

    private var handle: some View {
        ZStack {
            Rectangle()
                .fill(BlitzUI.mint.opacity(isHovering || dragOrigin != nil ? 0.8 : 0))
                .frame(width: 1)
            Capsule()
                .fill(.black.opacity(0.7))
                .frame(width: 18, height: 46)
                .overlay {
                    Capsule()
                        .fill(isHovering || dragOrigin != nil ? BlitzUI.mint : BlitzUI.supportingText)
                        .frame(width: 3, height: 24)
                }
        }
    }

    private func cancelDrag() {
        dragOrigin = nil
        vm.cancelSideSplitPreview()
        if isHovering {
            isHovering = false
            NSCursor.arrow.set()
        }
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
                    .position(
                        x: canvas.midX,
                        y: proxy.size.height - canvas.maxY + canvas.height * vm.screenSplitHeight
                    )
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
                        .fill(isHovering || dragOrigin != nil ? BlitzUI.mint : BlitzUI.supportingText)
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
            Label(vm.screenPickActionTitle, systemImage: "macwindow")
        }
        .blitzButton(.emphasized)
        .controlSize(.large)
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
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

    var body: some View {
        HStack(spacing: 8) {
            Button(action: configuration.onCancel) {
                Image(systemName: "xmark")
            }
            .blitzButton(.secondary)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Cancel")
            .help("Cancel (Esc)")

            Button(action: configuration.onReset) {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .blitzButton(.secondary)
            .help("Show the whole source again")

            Button(action: configuration.onDone) {
                Label("Done", systemImage: "checkmark")
            }
            .blitzButton(.accent)
            .keyboardShortcut(.defaultAction)
            .help("Keep this framing (Return)")
        }
        .pointingHandCursor()
        .padding(8)
        .background(.regularMaterial, in: .rect(cornerRadius: BlitzUI.cardRadius))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
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
                    .font(BlitzType.strong)
                    .foregroundStyle(BlitzUI.primaryText)
                Rectangle()
                    .fill(BlitzUI.panelStroke)
                    .frame(width: 1, height: 12)
                Text("\(vm.settings.framesPerSecond) FPS")
                    .font(BlitzType.captionEmphasis)
                    .foregroundStyle(BlitzUI.secondaryText)
                BlitzMenuChevron()
            }
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: BlitzControlMetrics.toolbarHeight)
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
                    .font(BlitzType.headline)
                    .foregroundStyle(BlitzUI.primaryText)
                Text(resolutionDimensions)
                    .font(BlitzType.caption)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Resolution")
                    .font(BlitzType.captionEmphasis)
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
                    .font(BlitzType.captionEmphasis)
                    .foregroundStyle(BlitzUI.secondaryText)
                BlitzSegmentedPicker(configuration: .init(
                    title: "Source FPS",
                    options: RecordingSettings.supportedFrameRates,
                    selection: Binding(get: { vm.settings.framesPerSecond }, set: { vm.setFrameRate($0) }),
                    label: { "\($0) FPS" }
                ))
                Text(frameRateDescription)
                    .font(BlitzType.footnote)
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
        HStack(spacing: 12) {
            FolderRecordTargetMenu(vm: vm)
                .frame(maxWidth: 220, alignment: .leading)
                .padding(.leading, 40)
            Spacer(minLength: 16)
            RecordingQualityShortcut(vm: vm)
        }
        .overlay {
            RecordingOutputPicker(vm: vm)
        }
    }
}

private extension MainView {
    var backgroundLayer: some View {
        BlitzUI.canvasBackground
            .ignoresSafeArea()
    }
}
