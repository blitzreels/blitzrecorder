import AppKit
import BlitzRecorderCore
import SwiftUI

struct MainView: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        let screenshotVariant = ScreenshotVariant.current

        ZStack {
            backgroundLayer

            recorderContent(screenshotVariant: screenshotVariant)
        }
        .overlay(alignment: .topTrailing) {
            screenshotOverlay
                .padding(.top, 58)
                .padding(.trailing, 22)
        }
        .overlay {
            if vm.showsFirstRunOnboarding {
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

    private func recorderContent(screenshotVariant: ScreenshotVariant) -> some View {
        VStack(spacing: 0) {
            switch vm.studioMode {
            case .edit:
                EditorView(vm: vm)
            case .projects:
                ProjectLibraryView(vm: vm)
            case .record:
                CaptureCommandBar(vm: vm)
                    .blitzWorkspaceToolbar()

                recordContent(screenshotVariant: screenshotVariant)
            }
        }
    }

    private func recordContent(screenshotVariant: ScreenshotVariant) -> some View {
        HStack(alignment: .top, spacing: 0) {
            SourcesSidebar(vm: vm)

            Rectangle()
                .fill(BlitzUI.separator)
                .frame(width: 1)

            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    RecordingOutputPicker(vm: vm)
                    Spacer(minLength: 0)
                    CanvasSelectionButton(vm: vm)
                }

                ZStack(alignment: .top) {
                    PreviewStageRepresentable(view: vm.previewStage)

                    if ScreenshotVariant.isScreenshotModeEnabled {
                        ScreenshotPreviewCanvas(variant: screenshotVariant)
                    }

                    if vm.screenNeedsPicking {
                        ScreenPickPromptOverlay(vm: vm)
                    }

                    SplitDividerOverlay(vm: vm)
                    CropToolbarOverlay(vm: vm)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                BottomDock(vm: vm)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
            }
            .padding(14)
            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            .background(BlitzUI.canvasBackground)

            Rectangle()
                .fill(BlitzUI.separator)
                .frame(width: 1)

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
        .buttonStyle(CanvasSelectionButtonStyle())
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

private struct CanvasSelectionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
            .blitzGlassButton()
            .controlSize(.small)
            .pointingHandCursor()

            Button(action: configuration.onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 28, height: 28)
            }
            .blitzGlassButton()
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
    @State private var isHovering = false
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
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(BlitzUI.secondaryText)
                    .rotationEffect(.degrees(isPresented ? 180 : 0))
            }
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(isHovering || isPresented ? BlitzUI.hoverFill : BlitzUI.controlFill, in: .rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(BlitzUI.panelStroke, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Recording quality, \(qualityPresentation.controlLabel)")
        .disabled(vm.state != .idle)
        .opacity(vm.state == .idle ? 1 : 0.5)
        .onHover { isHovering = $0 }
        .pointingHandCursor()
        .help("Choose recording resolution and Source FPS")
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
                title: "Projects",
                symbolName: "chevron.left",
                showsTitle: true,
                action: vm.showProjects
            ))
            .disabled(!vm.canShowProjects)
            .help("Open projects")

            Rectangle()
                .fill(BlitzUI.separator)
                .frame(width: 1, height: 16)

            statusRow

            Spacer(minLength: 16)

            RecordingQualityShortcut(vm: vm)

            BlitzToolbarButton(configuration: .init(
                title: "Settings",
                symbolName: "gearshape",
                showsTitle: false,
                action: { vm.onPresentSettings?(nil) }
            ))
            .help("Open Settings (Cmd+,)")
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
        case .finishing: return "Finishing…"
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
                Text("Switch scenes while recording")
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
                SceneWorkspaceThumbnail(scene: scene)
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
        .help("Switch to \(scene.name)")
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
            Label("New scene", systemImage: "plus")
                .frame(maxWidth: .infinity, minHeight: 24)
        }
        .blitzGlassButton()
        .controlSize(.small)
        .disabled(!vm.canEditScene)
        .pointingHandCursor()
        .help("Create a new scene")
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
                    sceneActions
                }
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
        .blitzGlassButton()
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
        .blitzGlassButton()
        .controlSize(.small)
        .pointingHandCursor()
        .accessibilityLabel("Cancel rename")
        .help("Cancel (Esc)")
    }

    private var sceneActions: some View {
        BlitzGlassMenu(entries: sceneActionEntries, menuWidth: 210) {
            BlitzSymbol(configuration: .init(name: "ellipsis", size: 18))
                .foregroundStyle(BlitzUI.secondaryText)
                .frame(width: 32, height: 32)
        }
        .disabled(!vm.canEditScene)
        .accessibilityLabel("Scene actions")
        .pointingHandCursor()
        .help("Rename, reset, duplicate, or organise this scene")
    }

    private var sceneActionEntries: [BlitzMenuEntry] {
        var entries: [BlitzMenuEntry] = [
            .item(BlitzMenuItem(title: "Rename scene…", systemImage: "pencil", action: beginEditing)),
            .item(BlitzMenuItem(title: "Reset layout", systemImage: "arrow.counterclockwise") {
                vm.resetSceneLayout()
            }),
            .divider,
            .item(BlitzMenuItem(title: "Duplicate scene", systemImage: "plus.square.on.square") {
                vm.duplicateSelectedScene()
            })
        ]
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
            VStack(alignment: .leading, spacing: 14) {
                SceneEditorHeader(vm: vm)
                layoutPicker
                if vm.showsScreenSplitControl {
                    splitHeightControl
                }
            }
            .padding(14)

            Rectangle()
                .fill(BlitzUI.separator)
                .frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    contextHeader
                    if vm.isBackgroundLayerSelected {
                        backgroundControls
                    } else {
                        SelectedSourceInspector(vm: vm)
                        if vm.selectedSource?.source == .camera {
                            CameraCropControls(vm: vm)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .id(vm.inspectorSelection)
        }
        .frame(minWidth: 264, idealWidth: 280, maxWidth: 280)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(BlitzUI.panelBackground)
    }

    private var layoutPicker: some View {
        BlitzGlassMenu(entries: layoutEntries, menuWidth: 246) {
            HStack(spacing: 8) {
                BlitzSymbol(configuration: .init(
                    name: vm.activeScenePreset?.symbolName ?? BlitzSymbols.layout,
                    size: 18
                ))
                .foregroundStyle(BlitzUI.secondaryText)
                Text("Layout")
                    .foregroundStyle(BlitzUI.secondaryText)
                Spacer(minLength: 4)
                Text(vm.activeScenePreset?.compactTitle ?? "Custom")
                    .foregroundStyle(BlitzUI.primaryText)
                    .lineLimit(1)
                BlitzSymbol(configuration: .init(name: "chevron.down", size: 12))
                    .foregroundStyle(BlitzUI.secondaryText)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(BlitzUI.controlFill, in: .rect(cornerRadius: BlitzUI.controlRadius))
        }
        .disabled(!vm.canEditScene)
        .accessibilityLabel("Layout, \(vm.activeScenePreset?.compactTitle ?? "Custom")")
        .help("Change the layout of this scene")
        .pointingHandCursor()
    }

    private var layoutEntries: [BlitzMenuEntry] {
        ScenePreset.allCases.filter { $0.supports(vm.settings.layout) }.map { preset in
            .item(BlitzMenuItem(
                title: preset.compactTitle,
                systemImage: preset.symbolName,
                isSelected: vm.isScenePresetActive(preset),
                action: { vm.setScenePreset(preset) }
            ))
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

                BlitzGlassMenu(entries: [
                    .item(BlitzMenuItem(
                        title: "Fit \(contextTitle.lowercased()) layer",
                        systemImage: "arrow.up.left.and.arrow.down.right",
                        action: { vm.fitSelectedLayer() }
                    ))
                ], menuWidth: 210) {
                    BlitzSymbol(configuration: .init(name: "ellipsis", size: 18))
                        .foregroundStyle(BlitzUI.secondaryText)
                        .frame(width: 32, height: 32)
                }
                .disabled(!vm.canEditScene)
                .accessibilityLabel("\(contextTitle) layer actions")
                .help("Adjust this layer in the scene")
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
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(!vm.canEditScene)

            if vm.settings.canvasBackgroundStyle.supportsBackgroundAnimation {
                Toggle(isOn: Binding(
                    get: { vm.settings.canvasBackgroundAnimated },
                    set: { vm.setCanvasBackgroundAnimated($0) }
                )) {
                    Label("Animate", systemImage: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
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

    var body: some View {
        BlitzSceneLayoutThumbnail(
            layout: scene.layout,
            sceneLayout: scene.snapshot.sceneLayout,
            visibleSources: scene.snapshot.enabledVideoSources.subtracting(scene.snapshot.hiddenVideoSources)
        )
    }
}

struct RemoteCameraPage: View {
    @Bindable var vm: RecorderViewModel

    private let accent = BlitzUI.mint

	var body: some View {
		Group {
			if vm.isRemoteCameraSelected {
				connectedLayout
			} else {
				disconnectedLayout
			}
		}
		.onAppear {
			vm.startRemoteCameraDiscovery()
		}
	}

    private var disconnectedLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                onboardingHeader
                setupStepsCard
                nearbyDevicesCard
            }
            .settingsPageContent()
        }
        .background(BlitzUI.projectLibraryBackground)
        .foregroundStyle(.white)
    }

    private var onboardingHeader: some View {
        SettingsPageHeader(.init(
            title: "Devices",
            detail: "Pair an iPhone for higher-quality video while the Mac keeps a responsive preview.",
            systemImage: "iphone.gen3",
            status: vm.remoteCameraDeviceSummaries.isEmpty ? "Searching" : "iPhone found"
        ))
        .padding(.bottom, 4)
    }

    private var setupStepsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set up your iPhone")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.52))

            VStack(alignment: .leading, spacing: 16) {
                downloadStep
                stepRow(
                    2,
                    title: "Open it",
                    detail: "Open the app. Use the same Wi-Fi as this Mac."
                )
                stepRow(
                    3,
                    title: "Connect them",
                    detail: "Your iPhone shows up below. Click it, then type the 6 numbers it shows you."
                )
                stepRow(
                    4,
                    title: "Hit record",
                    detail: "Pick your iPhone in Devices and press record."
                )
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var downloadStep: some View {
        HStack(alignment: .top, spacing: 12) {
            stepBadge(1)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Get the app")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                    Text("Put BlitzRecorder Camera on your iPhone.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                companionAppLink
            }
            Spacer(minLength: 0)
        }
    }

    private func stepRow(_ number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            stepBadge(number)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func stepBadge(_ number: Int) -> some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.16))
            Circle()
                .stroke(accent.opacity(0.45), lineWidth: 1)
            Text("\(number)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
        }
        .frame(width: 24, height: 24)
    }

    private var nearbyDevicesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("Nearby iPhones")
                    .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.52))
                Spacer(minLength: 0)
                if vm.remoteCameraDeviceSummaries.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if vm.remoteCameraDeviceSummaries.isEmpty {
                searchingRow
                directConnectionRow
            } else {
                VStack(spacing: 8) {
                    ForEach(vm.remoteCameraDeviceSummaries) { device in
                        remoteCameraDeviceRow(device)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var searchingRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi")
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.62))
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text("Looking for your iPhone…")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                Text("Open the app on your iPhone. Use the same Wi-Fi as this Mac.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: .rect(cornerRadius: 10))
    }

    private var directConnectionRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "network")
                    .font(.system(size: 14, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.62))
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect by address")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                    Text("Use the address and port shown on the iPhone when it does not appear automatically.")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                TextField("iPhone address", text: $vm.directRemoteCameraHost)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 8))

                TextField("Port", text: $vm.directRemoteCameraPort)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 10)
                    .frame(width: 76, height: 32)
                    .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 8))

                Button {
                    vm.connectDirectRemoteCamera()
                } label: {
                    Label("Connect", systemImage: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 11)
                .frame(height: 32)
                .background(accent.opacity(0.18), in: .rect(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(accent.opacity(0.38), lineWidth: 1)
                }
                .disabled(
                    vm.directRemoteCameraHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || vm.directRemoteCameraPort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: .rect(cornerRadius: 10))
    }

    private var companionAppLink: some View {
        Link(destination: BlitzRecorderProductIdentity.companionInstallURL) {
            HStack(spacing: 12) {
                ProductIconImage(
                    image: Bundle.main.blitzRecorderCameraIcon,
                    fallbackSystemImage: "iphone.gen3",
                    size: 42,
                    cornerRadius: 9
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(BlitzRecorderProductIdentity.companionDisplayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                    Text("iPhone app")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.52))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.055), in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help("Open \(BlitzRecorderProductIdentity.companionDisplayName)")
    }

    private var connectedLayout: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsPageHeader(.init(
                title: "Devices",
                detail: "Control the paired iPhone camera and monitor its recording connection.",
                systemImage: "iphone.gen3.radiowaves.left.and.right",
                status: "Connected"
            ))

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(vm.selectedRemoteCameraDeviceDescription)
                        .font(.system(size: 20, weight: .semibold))
                    Text("The iPhone records the sharp video. The Mac shows a quick preview.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            HSplitView {
                previewColumn
                settingsColumn
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 34)
        .padding(.top, 34)
        .padding(.bottom, 24)
        .background(BlitzUI.projectLibraryBackground)
        .foregroundStyle(.white)
    }

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            remotePreview

            previewLegend

            if vm.isRemoteCameraSelected {
                RemoteCameraOrientationControl(vm: vm, usesPanelBackground: true)
                    .frame(maxWidth: 420)
            }

            remoteStatusDetails
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.trailing, 20)
    }

    private var settingsColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                pairingSection
                RemoteCameraControlsPane(vm: vm)
            }
            .padding(.leading, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)
        .frame(maxHeight: .infinity)
        .scrollIndicators(.visible)
    }

    @ViewBuilder
    private var remotePreview: some View {
        GeometryReader { proxy in
            let previewSize = fittedRemotePreviewSize(in: proxy.size)

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.black)

                CameraPreviewRepresentable(view: vm.remoteCameraPreviewSurface)
                    .frame(width: previewSize.width, height: previewSize.height)
                    .clipped()

                if !vm.hasRemoteCameraPreviewImage {
                    VStack(spacing: 8) {
                        Image(systemName: vm.isRemoteCameraSelected ? "iphone.gen3.radiowaves.left.and.right" : "iphone.gen3")
                            .font(.system(size: 32, weight: .regular))
                            .foregroundStyle(.tertiary)
                        Text(previewEmptyTitle)
                            .font(.system(size: 14, weight: .medium))
                        Text(previewEmptyDetail)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: 320)
                    .frame(width: previewSize.width, height: previewSize.height)
                    .background(.black.opacity(0.82))
                }

            }
            .frame(width: previewSize.width, height: previewSize.height)
            .border(Color(nsColor: .separatorColor).opacity(0.3), width: 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var previewLegend: some View {
        Label("Source records on iPhone", systemImage: "iphone.gen3.radiowaves.left.and.right")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .allowsHitTesting(false)
    }

    private var pairingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Pairing")

            if vm.remoteCameraDeviceSummaries.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Open BlitzRecorder Camera on your iPhone", systemImage: "iphone.gen3")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(vm.remoteCameraDeviceSummaries) { device in
                        remoteCameraDeviceRow(device)
                    }
                }
            }
        }
    }

    private func remoteCameraDeviceRow(_ device: RemoteCameraDeviceSummary) -> some View {
        Button {
            vm.setCamera(device.cameraID)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(device.isSelected ? Color.white.opacity(0.16) : Color.white.opacity(0.08))
                    Image(systemName: device.isReady ? "iphone.gen3.radiowaves.left.and.right" : "iphone.gen3")
                        .font(.system(size: 14, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(device.isSelected ? .white : .white.opacity(0.72))
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                    Text(device.detail)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    if let lensCount = device.lensCount, lensCount > 0 {
                        lensDots(count: lensCount)
                            .help("\(lensCount) camera lenses available")
                    }

                    Text(device.status)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(device.isSelected ? .black.opacity(0.78) : .white.opacity(0.6))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(device.isSelected ? Color.white : Color.white.opacity(0.08), in: .capsule)
                }
            }
            .padding(8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(vm.state != .idle)
        .opacity(vm.state == .idle || device.isSelected ? 1 : 0.48)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(device.isSelected ? Color.white.opacity(0.16) : Color.white.opacity(0.04))
        )
        .pointingHandCursor()
        .help("Use \(device.name) as the iPhone camera")
    }

    private func lensDots(count: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<min(count, 4), id: \.self) { _ in
                Circle()
                    .fill(.white.opacity(0.42))
                    .frame(width: 4, height: 4)
            }
        }
        .frame(width: 24, alignment: .trailing)
    }

    private var remoteStatusDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("iPhone")
            statusRow("Device", value: vm.selectedRemoteCameraDeviceDescription)
            statusRow("Status", value: vm.selectedRemoteCameraStatus ?? (vm.isRemoteCameraSelected ? "Waiting" : "No iPhone selected"))
            statusRow("Video", value: vm.selectedRemoteCameraReviewStatus)
            statusRow("Controls", value: vm.selectedRemoteCameraCapabilities == nil ? "Waiting" : "Ready")
        }
        .frame(maxWidth: 460, alignment: .leading)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
    }

    private func statusRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 12, weight: .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private var previewEmptyTitle: String {
        vm.isRemoteCameraSelected ? "Waiting for iPhone video" : "No iPhone selected"
    }

    private var previewEmptyDetail: String {
        vm.isRemoteCameraSelected
            ? "Keep the iPhone app open. The good video records on the iPhone."
            : "Choose a nearby iPhone from Pairing."
    }

    private func fittedRemotePreviewSize(in availableSize: CGSize) -> CGSize {
        let aspectRatio = max(0.1, vm.remoteCameraPreviewAspectRatio)
        let availableWidth = max(1, availableSize.width)
        let availableHeight = max(1, availableSize.height)
        let widthFittedToHeight = availableHeight * aspectRatio

        if widthFittedToHeight <= availableWidth {
            return CGSize(width: widthFittedToHeight, height: availableHeight)
        }

        return CGSize(width: availableWidth, height: availableWidth / aspectRatio)
    }
}

private extension MainView {
    var backgroundLayer: some View {
        BlitzUI.canvasBackground
            .ignoresSafeArea()
    }

    @ViewBuilder
    private var screenshotOverlay: some View {
        switch ScreenshotVariant.current {
        case .plan:
            ScreenshotCard(width: 320) {
                VStack(alignment: .leading, spacing: 12) {
                    screenshotEyebrow("ACCESS")
                    Text("Free 1080p tier")
                        .font(.system(size: 16, weight: .bold))
                    Text("No account, card, watermark, or subscription.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.62))
                    Text("$39 unlocks iPhone camera, 4K, and 60 fps.")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.54))

                    Label("AGPL source code", systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.16), in: .rect(cornerRadius: 8))

                    HStack(spacing: 8) {
                        screenshotSmallButton("Privacy", icon: "hand.raised")
                        screenshotSmallButton("Support", icon: "questionmark.circle")
                    }

                    Divider().background(.white.opacity(0.12))

                    HStack(spacing: 12) {
                        Text("Terms")
                        Text("Privacy")
                        Text("Support")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.66))
                }
            }
        case .iphoneControls:
            ScreenshotCard(width: 330) {
                VStack(alignment: .leading, spacing: 12) {
                    screenshotEyebrow("IPHONE CAMERA")
                    HStack(spacing: 9) {
                        Image(systemName: "iphone.gen3")
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Connected to iPhone")
                                .font(.system(size: 15, weight: .bold))
                            Text("Monitor preview, local recording, transfer back to Mac")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.56))
                        }
                    }

                    HStack(spacing: 7) {
                        screenshotPill("Wide")
                        screenshotPill("1.4x")
                        screenshotPill("4K")
                        screenshotPill("30 fps")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        screenshotControlRow("Lens", value: "Wide", icon: "camera.aperture")
                        screenshotControlRow("Focus", value: "Continuous", icon: "scope")
                        screenshotControlRow("Exposure", value: "Auto", icon: "sun.max")
                        screenshotControlRow("Transfer", value: "Ready", icon: "arrow.up.doc")
                    }
                }
            }
        case .none:
            EmptyView()
        }
    }

    private func screenshotEyebrow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.55))
    }

    private func screenshotSmallButton(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.10), in: .rect(cornerRadius: 8))
    }

    private func screenshotPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.10), in: .capsule)
    }

    private func screenshotControlRow(_ title: String, value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 16)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.08), in: .rect(cornerRadius: 8))
    }
}

private enum ScreenshotVariant: Equatable {
    case none
    case plan
    case iphoneControls

    static var current: ScreenshotVariant {
        let environment = ProcessInfo.processInfo.environment
        guard isScreenshotModeEnabled else {
            return .none
        }

        switch environment["BLITZRECORDER_SCREENSHOT_VARIANT"] {
        case "plan": return .plan
        case "iphone-controls": return .iphoneControls
        default: return .none
        }
    }

    static var isScreenshotModeEnabled: Bool {
        ProcessInfo.processInfo.environment["BLITZRECORDER_SCREENSHOT_MODE"] == "1"
    }
}

private struct ScreenshotPreviewCanvas: View {
    let variant: ScreenshotVariant

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(red: 0.03, green: 0.04, blue: 0.05)

                screenshotWorkspace(width: proxy.size.width, height: proxy.size.height)
            }
            .clipShape(.rect(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            )
        }
        .padding(.horizontal, 4)
    }

    private func screenshotWorkspace(width: CGFloat, height: CGFloat) -> some View {
        let stageHeight = min(height * 0.78, 560)
        let stageWidth = min(stageHeight * 9 / 16, width * 0.34)

        return HStack(alignment: .center, spacing: 28) {
            VStack(alignment: .leading, spacing: 14) {
                screenshotTimeline
                screenshotAudioMeters
            }
            .frame(width: min(width * 0.28, 260), alignment: .leading)

            screenshotShortsFrame
                .frame(width: stageWidth, height: stageHeight)

            VStack(alignment: .leading, spacing: 14) {
                screenshotStatusCard
                screenshotRenderCard
            }
            .frame(width: min(width * 0.24, 230), alignment: .leading)
        }
        .padding(.horizontal, 28)
    }

    private var screenshotShortsFrame: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26)
                .fill(Color(red: 0.065, green: 0.075, blue: 0.09))

            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.12, green: 0.16, blue: 0.18))
                    .overlay(alignment: .topLeading) {
                        HStack(spacing: 6) {
                            Circle().fill(Color(red: 1.0, green: 0.36, blue: 0.34))
                            Circle().fill(Color(red: 1.0, green: 0.77, blue: 0.28))
                            Circle().fill(Color(red: 0.25, green: 0.86, blue: 0.48))
                        }
                        .frame(width: 54, height: 8)
                        .padding(12)
                    }
                    .overlay {
                        VStack(alignment: .leading, spacing: 10) {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.white.opacity(0.72))
                                .frame(width: 112, height: 12)
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color(red: 0.14, green: 0.88, blue: 0.68).opacity(0.72))
                                .frame(width: 154, height: 12)
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.white.opacity(0.24))
                                .frame(width: 132, height: 12)
                        }
                    }
                    .padding(18)

                ZStack(alignment: .bottomTrailing) {
                    Color(red: 0.075, green: 0.085, blue: 0.105)
                    .clipShape(.rect(cornerRadius: 16))

                    ScreenshotRuleOfThirdsShape()
                        .stroke(.white.opacity(0.14), lineWidth: 1)

                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(red: 0.08, green: 0.09, blue: 0.12))
                        .frame(width: 96, height: 132)
                        .overlay {
                            VStack(spacing: 8) {
                                Circle()
                                    .fill(Color(red: 0.18, green: 0.9, blue: 0.76).opacity(0.72))
                                    .frame(width: 34, height: 34)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white.opacity(0.68))
                                    .frame(width: 48, height: 7)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white.opacity(0.34))
                                    .frame(width: 60, height: 7)
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                        )
                        .padding(16)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }

            VStack {
                Spacer()
                HStack {
                    Label(variant == .iphoneControls ? "iPhone camera linked" : "Ready to export", systemImage: variant == .iphoneControls ? "iphone.gen3" : "square.and.arrow.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.black.opacity(0.36), in: .capsule)
                    Spacer()
                }
                .padding(16)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        )
    }

    private var screenshotTimeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Scene")
                .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.48))
            screenshotTrack(label: "Screen", color: Color(red: 0.20, green: 0.74, blue: 0.96), width: 164)
            screenshotTrack(label: "Camera", color: Color(red: 0.18, green: 0.9, blue: 0.72), width: 116)
            screenshotTrack(label: "Cursor", color: Color(red: 0.95, green: 0.72, blue: 0.25), width: 136)
        }
        .padding(14)
        .background(Color.white.opacity(0.07), in: .rect(cornerRadius: 14))
    }

    private func screenshotTrack(label: String, color: Color, width: CGFloat) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(0.62))
                .frame(width: width * 0.36, height: 7)
        }
    }

    private var screenshotAudioMeters: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Audio")
                .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.48))
            screenshotMeter("Mic", fill: 0.68)
            screenshotMeter("System", fill: 0.46)
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 14))
    }

    private func screenshotMeter(_ label: String, fill: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule()
                        .fill(Color(red: 0.18, green: 0.9, blue: 0.72).opacity(0.76))
                        .frame(width: proxy.size.width * fill)
                }
            }
            .frame(height: 7)
        }
    }

    private var screenshotStatusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Vertical Shorts layout", systemImage: "rectangle.portrait")
                .font(.system(size: 11, weight: .bold))
            Text("Screen, face camera, cursor, and safe-zone overlays are arranged for export.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(Color.white.opacity(0.07), in: .rect(cornerRadius: 14))
    }

    private var screenshotRenderCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Export")
                    .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.48))
                Spacer()
                Text("1080x1920")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.56))
            }
            ProgressView(value: 0.72)
                .progressViewStyle(.linear)
                .tint(Color(red: 0.18, green: 0.9, blue: 0.72))
            Text(exportStatusText)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.66))
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 14))
    }

    private var exportStatusText: String {
        switch variant {
        case .plan:
            return "Unlimited exports included"
        case .iphoneControls:
            return "Transfer ready from iPhone"
        case .none:
            return "Export preview ready"
        }
    }
}

private struct ScreenshotRuleOfThirdsShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            let firstX = rect.minX + rect.width / 3
            let secondX = rect.minX + rect.width * 2 / 3
            let firstY = rect.minY + rect.height / 3
            let secondY = rect.minY + rect.height * 2 / 3

            path.move(to: CGPoint(x: firstX, y: rect.minY))
            path.addLine(to: CGPoint(x: firstX, y: rect.maxY))
            path.move(to: CGPoint(x: secondX, y: rect.minY))
            path.addLine(to: CGPoint(x: secondX, y: rect.maxY))
            path.move(to: CGPoint(x: rect.minX, y: firstY))
            path.addLine(to: CGPoint(x: rect.maxX, y: firstY))
            path.move(to: CGPoint(x: rect.minX, y: secondY))
            path.addLine(to: CGPoint(x: rect.maxX, y: secondY))
        }
    }
}

private struct ScreenshotCard<Content: View>: View {
    let width: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(width: width, alignment: .leading)
            .foregroundStyle(.white)
            .background(.regularMaterial, in: .rect(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.white.opacity(0.16), lineWidth: 1)
            )
    }
}
