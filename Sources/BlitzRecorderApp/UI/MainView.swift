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
            CaptureCommandBar(vm: vm)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .background(.bar)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(.white.opacity(0.08))
                        .frame(height: 1)
                }

            if vm.studioMode == .edit {
                EditorView(vm: vm)
            } else {
                recordContent(screenshotVariant: screenshotVariant)
            }
        }
    }

    private func recordContent(screenshotVariant: ScreenshotVariant) -> some View {
            HStack(alignment: .top, spacing: 0) {
                SourcesSidebar(vm: vm)

                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 1)

                VStack(spacing: 12) {
                    ZStack(alignment: .top) {
                        PreviewStageRepresentable(view: vm.previewStage)

                        if ScreenshotVariant.isScreenshotModeEnabled {
                            ScreenshotPreviewCanvas(variant: screenshotVariant)
                        }

                        if vm.screenNeedsPicking {
                            ScreenPickPromptOverlay(vm: vm)
                        }

                        CropToolbarOverlay(vm: vm)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    BottomDock(vm: vm)

                    CaptureSceneCarousel(vm: vm)
                }
                .padding(14)
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                .background(BlitzUI.canvasBackground)

                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 1)

                SceneWorkspaceInspector(vm: vm)
            }
            .frame(maxHeight: .infinity)
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
                CropFloatingToolbar(vm: vm)
                    .fixedSize()
                    .position(
                        x: frame.midX,
                        y: proxy.size.height - frame.midY
                    )
            }
        }
    }
}

private struct ScreenPickPromptOverlay: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        GeometryReader { proxy in
            if let frame = vm.screenLayerFrame, frame.width > 1, frame.height > 1 {
                ScreenPickPrompt(vm: vm)
                    .frame(
                        width: min(320, max(120, frame.width - 16)),
                        height: min(170, max(80, frame.height - 16))
                    )
                    .position(x: frame.midX, y: proxy.size.height - frame.midY)
            } else {
                ScreenPickPrompt(vm: vm)
                    .frame(
                        width: min(320, max(120, proxy.size.width - 48)),
                        height: min(170, max(80, proxy.size.height - 48))
                    )
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        }
    }
}

private struct ScreenPickPrompt: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 220 || proxy.size.height < 128

            Button {
                vm.pickScreen()
            } label: {
                VStack(spacing: compact ? 6 : 10) {
                    Image(systemName: "rectangle.on.rectangle.angled")
                        .font(.system(size: compact ? 18 : 26, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(BlitzUI.mint)

                    VStack(spacing: 3) {
                        Text(compact ? "Pick screen" : "Pick a screen to preview")
                            .font(.system(size: compact ? 11 : 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)

                        if !compact {
                            Text("Choose a display, window, or app")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(.white.opacity(0.55))
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }
                    }
                }
                .padding(.horizontal, compact ? 12 : 24)
                .padding(.vertical, compact ? 10 : 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black.opacity(0.4), in: .rect(cornerRadius: compact ? 10 : 14))
                .contentShape(.rect(cornerRadius: compact ? 10 : 14))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help("Pick a screen, window, or app to capture")
        }
    }
}

private struct CropFloatingToolbar: View {
    @Bindable var vm: RecorderViewModel

    private let accent = BlitzUI.mint
    private var isCameraCrop: Bool { vm.isCameraCropModeEnabled }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                if isCameraCrop {
                    vm.applyCameraCropMode()
                } else {
                    vm.applyScreenCropMode()
                }
            } label: {
                Label("Done cropping", systemImage: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black.opacity(0.88))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(accent, in: .rect(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()

            Button {
                if isCameraCrop {
                    vm.resetCameraCrop()
                } else {
                    vm.resetScreenCropMode()
                }
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 28, height: 28)
            }
            .blitzGlassButton()
            .controlSize(.small)
            .pointingHandCursor()

            Button {
                if isCameraCrop {
                    vm.cancelCameraCropMode()
                } else {
                    vm.cancelScreenCropMode()
                }
            } label: {
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

private typealias SceneWorkspaceTheme = BlitzUI

private struct StudioModeSwitch: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        HStack(spacing: 2) {
            tab("Record", icon: "record.circle", mode: .record)
            tab("Edit", icon: "timeline.selection", mode: .edit)
        }
        .padding(3)
        .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 9))
    }

    private func tab(_ title: String, icon: String, mode: RecorderViewModel.StudioMode) -> some View {
        let isSelected = vm.studioMode == mode
        let isEnabled = mode == .record || (vm.canOpenEditor && vm.state == .idle)
        return Button {
            if mode == .edit {
                vm.openEditor()
            } else {
                vm.closeEditor()
            }
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.62))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.white.opacity(0.14) : Color.clear, in: .rect(cornerRadius: 7))
        .contentShape(.rect(cornerRadius: 7))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .pointingHandCursor()
        .help(helpText(for: mode, isEnabled: isEnabled))
    }

    private func helpText(for mode: RecorderViewModel.StudioMode, isEnabled: Bool) -> String {
        switch mode {
        case .record:
            return "Capture studio"
        case .edit:
            return isEnabled ? "Edit and export the last take" : "Record a take first"
        }
    }
}

private struct CaptureCommandBar: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(vm.selectedSceneName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white.opacity(0.94))
                    .lineLimit(1)
                statusRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            StudioModeSwitch(vm: vm)

            HStack(spacing: 12) {
            Spacer(minLength: 0)

            Button {
                vm.onPresentSettings?(.account)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(BlitzUI.mint)
                    Text("Free")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .blitzGlassButton()
            .pointingHandCursor()
            .help("Open account")

            RecordingOutputPicker(vm: vm)

            Button {
                vm.onPresentSettings?(nil)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 32, height: 32)
            }
            .blitzGlassButton()
            .controlSize(.small)
            .pointingHandCursor()
            .help("Open Settings (Cmd+,)")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var isBlocked: Bool {
        vm.state == .idle && !vm.recordingReadiness.isReady
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
        switch vm.state {
        case .recording: return BlitzUI.recordRed
        case .paused, .starting, .finishing: return BlitzUI.warning
        case .idle: return vm.recordingReadiness.isReady ? BlitzUI.mint : BlitzUI.warning
        }
    }

    private var statusText: String {
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

private struct CaptureSceneCarousel: View {
    @Bindable var vm: RecorderViewModel
    @State private var showsAllRatios = false

    private var displayedScenes: [RecordingSceneDefinition] {
        showsAllRatios ? vm.allScenes : vm.currentScenes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                workspaceHeader("Scenes", icon: "rectangle.stack")
                Spacer(minLength: 0)
                ratioFilter
            }

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(displayedScenes) { scene in
                        sceneButton(scene)
                    }
                    newSceneButton
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.hidden)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .background(.bar)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    private func sceneButton(_ scene: RecordingSceneDefinition) -> some View {
        let isOffRatio = scene.layout != vm.settings.layout
        let isSelected = !isOffRatio && vm.selectedSceneID == scene.id
        let isInteractive = vm.canSwitchScene && !(isOffRatio && vm.state != .idle)
        return Button {
            vm.selectSceneAcrossLayouts(scene.id)
        } label: {
            VStack(spacing: 6) {
                SceneWorkspaceThumbnail(scene: scene)
                    .frame(width: 64, height: 60)
                    .overlay(alignment: .topLeading) {
                        if showsAllRatios {
                            Text(scene.layout.shortLabel)
                                .font(.system(size: 8.5, weight: .heavy))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.black.opacity(0.55)))
                                .offset(x: 3, y: 3)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(SceneWorkspaceTheme.mint)
                                .background(Circle().fill(.black.opacity(0.55)))
                                .offset(x: 4, y: -4)
                        }
                    }

                Text(scene.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(isSelected ? 0.94 : 0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(width: 92)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .blitzSelectedSurface(isSelected: isSelected, cornerRadius: 10)
        .disabled(!isInteractive)
        .opacity(isInteractive || isSelected ? 1 : 0.5)
        .pointingHandCursor()
        .help(isOffRatio ? "Switch to \(scene.name) (\(scene.layout.shortLabel))" : "Switch to \(scene.name)")
        .contextMenu {
            Button("Duplicate Scene") {
                vm.selectScene(scene.id)
                vm.duplicateSelectedScene()
            }
            .disabled(!vm.canEditScene || isOffRatio)

            Divider()

            Button("Delete \(scene.name)", role: .destructive) {
                vm.deleteScene(scene.id)
            }
            .disabled(!vm.canEditScene || isOffRatio || vm.currentScenes.count <= 1)
        }
    }

    private var ratioFilter: some View {
        HStack(spacing: 2) {
            ForEach(CaptureLayout.allCases, id: \.self) { layout in
                filterSegment(
                    label: layout.shortLabel,
                    icon: layout.symbolName,
                    isSelected: !showsAllRatios && vm.settings.layout == layout
                ) {
                    showsAllRatios = false
                    if vm.settings.layout != layout {
                        vm.setLayout(layout)
                    }
                }
                .disabled(vm.state != .idle && vm.settings.layout != layout)
            }

            filterSegment(
                label: "All",
                icon: "square.grid.2x2",
                isSelected: showsAllRatios
            ) { showsAllRatios = true }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(BlitzUI.quietFill)
        )
        .help("Filter scenes by aspect ratio")
    }

    private func filterSegment(
        label: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(isSelected ? 0.95 : 0.6))
            .padding(.horizontal, 9)
            .frame(height: 22)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? BlitzUI.selectedFill : Color.clear)
        )
        .pointingHandCursor()
    }

    private var newSceneButton: some View {
        Button {
            vm.createScene()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                        )
                        .foregroundStyle(.white.opacity(0.22))
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(width: 64, height: 56)

                Text("New Scene")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(width: 92)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(BlitzUI.quietFill, in: .rect(cornerRadius: 10))
        .disabled(!vm.canEditScene)
        .opacity(vm.canEditScene ? 1 : 0.5)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BlitzUI.sectionLabel("Editing", icon: "slider.horizontal.3")

            HStack(spacing: 8) {
                if isEditing {
                    nameField
                    commitButton
                    cancelButton
                } else {
                    nameLabel
                    renameButton
                    Spacer(minLength: 0)
                    deleteButton
                }
            }

            if vm.isSourceVisible(.camera) {
                cameraSummary
            }
        }
        .padding(.bottom, 2)
        .onChange(of: vm.selectedSceneID) { _, _ in
            if isEditing { exitEditing(commit: false) }
        }
        .onChange(of: vm.canEditScene) { _, canEdit in
            if !canEdit && isEditing { exitEditing(commit: false) }
        }
    }

    private var nameLabel: some View {
        Text(vm.selectedSceneName)
            .font(.system(size: 15, weight: .bold))
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
            .font(.system(size: 15, weight: .bold))
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
        .help("Cancel (Esc)")
    }

    private var cameraSummary: some View {
        HStack(spacing: 6) {
            Image(systemName: vm.isRemoteCameraSelected ? "iphone.gen3" : "video.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 14)
            Text(vm.selectedCameraDisplayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .help("Camera source: \(vm.selectedCameraDisplayName). Switch cameras in Devices on the left.")
    }

    private var renameButton: some View {
        Button {
            beginEditing()
        } label: {
            Image(systemName: "pencil")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
        }
        .blitzGlassButton()
        .controlSize(.small)
        .disabled(!vm.canEditScene)
        .pointingHandCursor()
        .help("Rename this scene")
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            showsDeleteConfirmation = true
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(canDelete ? BlitzUI.recordRed : .white.opacity(0.4))
                .frame(width: 24, height: 24)
        }
        .blitzGlassButton()
        .controlSize(.small)
        .disabled(!canDelete)
        .pointingHandCursor()
        .help(vm.currentScenes.count > 1 ? "Delete this scene" : "A workspace needs at least one scene")
        .confirmationDialog(
            "Delete \(vm.selectedSceneName)?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Scene", role: .destructive) {
                if let id = vm.selectedSceneID {
                    vm.deleteScene(id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the scene and its layout from this workspace.")
        }
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
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    scenePanel
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
        .padding(14)
        .frame(minWidth: 254, idealWidth: 294, maxWidth: 294)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial)
    }

    private var scenePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            SceneEditorHeader(vm: vm)

            VStack(alignment: .leading, spacing: 6) {
                workspaceHeader("Layout", icon: "square.split.2x1")
                Text("Sets how ‘\(vm.selectedSceneName)’ arranges its layers.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(ScenePreset.allCases.filter { $0.supports(vm.settings.layout) }, id: \.self) { preset in
                    ScenePresetTile(
                        title: shortPresetTitle(preset),
                        icon: preset.symbolName,
                        isSelected: vm.isScenePresetActive(preset),
                        isEnabled: vm.canEditScene
                    ) {
                        vm.setScenePreset(preset)
                    }
                    .help(presetHelp(preset))
                }
            }

            workspaceHeader("Layers", icon: "square.3.layers.3d")
            ForEach(SceneLayoutProjection.frontToBackOrder(for: vm.settings.sceneLayout), id: \.self) { layer in
                SceneLayerControlRow(vm: vm, layer: layer)
            }
            SceneBackgroundLayerRow(vm: vm)

            selectedLayerControls

            if vm.showsScreenSplitControl {
                splitHeightControl
            }
        }
    }

    @ViewBuilder
    private var selectedLayerControls: some View {
        if vm.isBackgroundLayerSelected {
            backgroundControls
        } else {
            HStack(spacing: 8) {
                workspaceAction(vm.selectedLayer == .screen ? "Fill slot" : "Fill", icon: "arrow.up.left.and.arrow.down.right") {
                    vm.fitSelectedLayer()
                }
                .disabled(!vm.canEditScene)
                workspaceAction("Reset", icon: "arrow.counterclockwise") {
                    vm.resetSceneLayout()
                }
                .disabled(!vm.canEditScene)
            }

            if vm.selectedLayer == .screen {
                screenSourceControl
                if vm.canShowScreenWindowFitControls {
                    screenWindowZoomControl
                    workspaceAction("Free crop", icon: "crop") {
                        vm.beginScreenCropMode()
                    }
                    .disabled(!vm.canEditScene || !vm.isSourceConfigured(.screen))
                }
            } else {
                CameraCropControls(vm: vm)
            }
        }
    }

    private var backgroundControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            SceneBackgroundSwatchRow(vm: vm)

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
        }
    }

    private var screenSourceControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Screen source")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.58))
                Spacer(minLength: 0)
                Button {
                    Task { await vm.refreshSources() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .blitzGlassButton()
                .controlSize(.small)
                .disabled(!vm.canEditScene)
                .pointingHandCursor()
                .help("Refresh available apps and windows")
            }

            BlitzGlassMenu(entries: screenSourceMenuEntries, menuWidth: 340) {
                HStack(spacing: 8) {
                    selectedScreenSourceIconView
                    Text(vm.selectedScreenSourceDisplayName)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.44))
                }
                .foregroundStyle(.white.opacity(0.82))
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .padding(.horizontal, 10)
            }
            .controlSize(.small)
            .disabled(!vm.canEditScene)
            .pointingHandCursor()
            .help("Choose the app, window, or display to record")

            screenCaptureModeButtons

            if vm.screenCaptureAreaSelection == .activeWindow {
                if !vm.hasAccessibilityAccessForWindowControls {
                    screenPermissionHint(
                        text: "Allow Accessibility so BlitzRecorder can resize the selected window.",
                        actionTitle: "Allow"
                    ) {
                        vm.requestAccessibilityForWindowControls()
                    }
                }

                if !vm.isPersistentScreenCaptureAccessActive && !vm.settings.usesPickedScreenContent {
                    screenPermissionHint(
                        text: "Allow Screen Recording to preview the selected source.",
                        actionTitle: "Settings"
                    ) {
                        vm.openScreenRecordingSettings()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var screenCaptureModeButtons: some View {
        HStack(spacing: 4) {
            let sourceKind = vm.settings.screenSourceBinding?.kind
            screenCaptureAreaButton(
                sourceKind == .display ? "Full" : "Display",
                icon: "display",
                isSelected: sourceKind == .display && vm.screenCaptureAreaSelection == .fullDisplay
            ) {
                vm.setFullDisplayScreenCapture()
            }

            if sourceKind == .application || vm.canUseAppOnlyCapture {
                screenCaptureAreaButton(
                    "App only",
                    icon: "macwindow.on.rectangle",
                    isSelected: sourceKind == .application
                ) {
                    vm.setAppOnlyCapture(true)
                }
            }

            screenCaptureAreaButton(
                sourceKind == .window ? "Window only" : "Window",
                icon: "app.window",
                isSelected: sourceKind == .window || (sourceKind != .application && vm.screenCaptureAreaSelection == .activeWindow)
            ) {
                vm.setWindowOnlyCapture()
            }
        }
    }

    private var screenWindowZoomControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Window zoom")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.58))
                Spacer(minLength: 0)
                Text("\(Int((vm.targetWindowZoom * 100).rounded()))%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
            }

            HStack(spacing: 6) {
                windowSizeStepButton(icon: "minus", isDisabled: vm.targetWindowZoom <= WindowZoomGeometry.minimumZoom) {
                    vm.zoomTargetWindowFit(by: -0.05)
                }
                .help("Zoom out by using a larger source window")

                Slider(
                    value: Binding(
                        get: { Double(vm.targetWindowZoom) },
                        set: { vm.setTargetWindowZoom(CGFloat($0)) }
                    ),
                    in: WindowZoomGeometry.minimumZoom...WindowZoomGeometry.maximumZoom,
                    step: 0.05
                )
                .controlSize(.small)
                .tint(BlitzUI.mint)
                .disabled(!vm.canEditScene)
                .help("Change the selected app's visual zoom in the canvas")

                windowSizeStepButton(icon: "plus", isDisabled: vm.targetWindowZoom >= WindowZoomGeometry.maximumZoom) {
                    vm.zoomTargetWindowFit(by: 0.05)
                }
                .help("Zoom in by using a narrower source window")

                windowSizeStepButton(icon: "arrow.counterclockwise", isDisabled: abs(vm.targetWindowZoom - 1) < 0.001) {
                    vm.resetTargetWindowZoom()
                }
                .help("Reset window zoom")
            }

            HStack {
                Text("50%")
                Spacer(minLength: 0)
                Text("100%")
                Spacer(minLength: 0)
                Text("150%")
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.4))

            workspaceAction("Resize window", icon: "rectangle.arrowtriangle.2.inward") {
                vm.fitCurrentScreenWindowToSlot()
            }
            .disabled(!vm.canEditScene)
            .help("Apply the current window zoom to the selected app or window")

            appContentZoomControl
        }
    }

    private var appContentZoomControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("App text zoom")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))

            HStack(spacing: 6) {
                appZoomButton("Smaller", icon: "minus") {
                    vm.zoomScreenSourceContentOut()
                }
                .help("Send Cmd - to the selected app")

                appZoomButton("100%", icon: "arrow.counterclockwise") {
                    vm.resetScreenSourceContentZoom()
                }
                .help("Send Cmd 0 to the selected app")

                appZoomButton("Larger", icon: "plus") {
                    vm.zoomScreenSourceContentIn()
                }
                .help("Send Cmd = to the selected app")
            }
        }
    }

    private func appZoomButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                Text(title)
                    .font(.system(size: 10.5, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 26)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.84))
        .background(Color.white.opacity(0.055), in: .rect(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
        .disabled(!vm.canEditScene)
        .pointingHandCursor()
    }

    private func windowSizeStepButton(icon: String, isDisabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 24, height: 22)
        }
        .buttonStyle(.plain)
        .background(Color.white.opacity(0.055), in: .rect(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
        .disabled(!vm.canEditScene || isDisabled)
        .pointingHandCursor()
    }

    private var screenSourceIcon: String {
        if vm.settings.usesPickedScreenContent {
            return "rectangle.dashed"
        }
        switch vm.settings.screenSourceBinding?.kind {
        case .application:
            return "macwindow.on.rectangle"
        case .window:
            return "app.window"
        case .display, nil:
            return "display"
        }
    }

    @ViewBuilder
    private var selectedScreenSourceIconView: some View {
        if let icon = selectedScreenSourceOption?.icon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
                .clipShape(.rect(cornerRadius: 4))
        } else {
            Image(systemName: screenSourceIcon)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 16, height: 16)
        }
    }

    private var selectedScreenSourceOption: ScreenSourceOption? {
        guard !vm.settings.usesPickedScreenContent,
              let binding = vm.settings.screenSourceBinding else {
            return nil
        }
        return vm.availableScreenSources.first { $0.binding == binding }
    }

    private var screenSourceMenuEntries: [BlitzMenuEntry] {
        var entries: [BlitzMenuEntry] = []
        appendScreenSourceSection(.application, title: "Apps", to: &entries)
        appendScreenSourceSection(.window, title: "Windows", to: &entries)
        appendScreenSourceSection(.display, title: "Displays", to: &entries)
        if !entries.isEmpty {
            entries.append(.divider)
        }
        entries.append(.item(BlitzMenuItem(
            title: "System Picker...",
            subtitle: "Choose with macOS",
            systemImage: "rectangle.dashed"
        ) {
            vm.pickScreen()
        }))
        return entries
    }

    private func appendScreenSourceSection(
        _ kind: ScreenSourceBinding.Kind,
        title: String,
        to entries: inout [BlitzMenuEntry]
    ) {
        let options = vm.availableScreenSources.filter { $0.binding.kind == kind }
        guard !options.isEmpty else { return }

        entries.append(.section(title))
        entries += options.map { option in
            .item(BlitzMenuItem(
                title: option.title,
                subtitle: option.subtitle,
                systemImage: option.systemImage,
                icon: option.icon,
                isSelected: !vm.settings.usesPickedScreenContent && vm.settings.screenSourceBinding == option.binding
            ) {
                vm.setScreenSource(option.binding)
            })
        }
    }

    private func screenCaptureAreaButton(
        _ title: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.86)
                .frame(maxWidth: .infinity, minHeight: 30)
                .foregroundStyle(.white.opacity(isSelected ? 0.94 : 0.62))
        }
        .buttonStyle(.plain)
        .disabled(!vm.canEditScene)
        .background(.white.opacity(isSelected ? 0.16 : 0.045), in: .rect(cornerRadius: 8))
        .pointingHandCursor()
    }

    private func screenPermissionHint(
        text: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(BlitzUI.warning)
                .frame(width: 16, height: 16)

            Text(text)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: action) {
                Text(actionTitle)
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .frame(height: 22)
            }
            .blitzGlassButton()
            .controlSize(.small)
            .pointingHandCursor()
        }
        .padding(8)
        .background(BlitzUI.warning.opacity(0.10), in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(BlitzUI.warning.opacity(0.30), lineWidth: 1)
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

            HStack {
                Text("Camera")
                Spacer(minLength: 0)
                Text("Screen")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.46))
        }
    }

    private func workspaceAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.84)
                .frame(maxWidth: .infinity, minHeight: 30)
        }
        .blitzGlassButton()
        .controlSize(.small)
        .pointingHandCursor()
    }

    private func shortPresetTitle(_ preset: ScenePreset) -> String {
        switch preset {
        case .screenTop50:
            return "Split"
        case .cameraInset:
            return "Inset"
        case .webcamLeft:
            return "Left Cam"
        case .screenFullscreen:
            return "Screen"
        case .webcamFullscreen:
            return "Camera"
        default:
            return preset.detail
        }
    }

    private func presetHelp(_ preset: ScenePreset) -> String {
        switch preset {
        case .screenTop50:
            return "Split: screen on top, camera filling the band below."
        case .cameraInset:
            return "Inset: full screen with the camera in a corner bubble."
        case .webcamLeft:
            return "Left Cam: camera on the left, screen on the right."
        case .screenFullscreen:
            return "Screen: screen fills the frame, camera hidden."
        case .webcamFullscreen:
            return "Camera: camera fills the frame, screen hidden."
        default:
            return preset.detail
        }
    }
}

private struct ScenePresetTile: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                BlitzIconTile(symbolName: icon, isSelected: isSelected, size: 30)

                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isSelected ? .white.opacity(0.92) : .white.opacity(0.64))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .blitzSelectedSurface(isSelected: isSelected)
        .disabled(!isEnabled)
        .opacity(isEnabled || isSelected ? 1 : 0.52)
        .pointingHandCursor()
    }
}

private struct SceneLayerControlRow: View {
    @Bindable var vm: RecorderViewModel
    let layer: SceneLayerKind

    private var isSelected: Bool { !vm.isBackgroundLayerSelected && vm.selectedLayer == layer }
    private var isVisible: Bool { vm.isSourceVisible(layer.source) }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                vm.selectLayer(layer)
            } label: {
                HStack(spacing: 9) {
                    BlitzIconTile(symbolName: layer.source.symbolName, isSelected: isSelected)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(layer.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(isSelected ? 0.92 : 0.72))
                            .lineLimit(1)
                        Text(isVisible ? "Visible" : "Hidden")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.44))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()

            Button {
                vm.setSourceVisible(layer.source, visible: !isVisible)
            } label: {
                Image(systemName: isVisible ? "eye.fill" : "eye.slash")
                    .font(.system(size: 11, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(isVisible ? 0.72 : 0.38))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .background(Color.white.opacity(0.045), in: .rect(cornerRadius: 7))
            .disabled(!vm.canEditScene)
            .pointingHandCursor()
            .help(isVisible ? "Hide \(layer.rawValue)" : "Show \(layer.rawValue)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .blitzSelectedSurface(isSelected: isSelected)
    }
}

private struct SceneBackgroundLayerRow: View {
    @Bindable var vm: RecorderViewModel

    private var isSelected: Bool { vm.isBackgroundLayerSelected }

    var body: some View {
        Button {
            vm.selectBackgroundLayer()
        } label: {
            HStack(spacing: 9) {
                BlitzIconTile(symbolName: "paintpalette", isSelected: isSelected)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Background")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(isSelected ? 0.92 : 0.72))
                        .lineLimit(1)
                    Text(vm.settings.canvasBackgroundStyle.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.44))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                CanvasBackgroundSwatchCache.image(vm.settings.canvasBackgroundStyle)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 18, height: 18)
                    .clipShape(.circle)
                    .overlay {
                        Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1)
                    }
                    .padding(.trailing, 5)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .blitzSelectedSurface(isSelected: isSelected)
        .pointingHandCursor()
        .help("Edit the scene background")
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
                .textCase(.uppercase)

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

    private var aspect: CGFloat { scene.layout.aspectRatio }

    private func fittedCanvas(in slot: CGSize) -> CGRect {
        guard slot.width > 0, slot.height > 0 else { return .zero }
        var width = slot.width
        var height = slot.width / aspect
        if height > slot.height {
            height = slot.height
            width = slot.height * aspect
        }
        let originX = (slot.width - width) / 2
        let originY = (slot.height - height) / 2
        return CGRect(x: originX, y: originY, width: width, height: height)
    }

    var body: some View {
        GeometryReader { proxy in
            let canvas = fittedCanvas(in: proxy.size)
            let cornerRadius: CGFloat = 6
            let visible = scene.snapshot.enabledVideoSources.subtracting(scene.snapshot.hiddenVideoSources)
            let items = scene.snapshot.sceneLayout.resolvedItems(
                enabledSources: visible,
                fillsCanvasWhenOnlyVideoSource: true
            )

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(BlitzUI.canvasBackground)
                    .frame(width: canvas.width, height: canvas.height)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(.white.opacity(0.16), lineWidth: 1)
                    }

                ForEach(items, id: \.kind) { item in
                    let frame = item.normalizedFrame.standardized
                    let rectWidth = max(3, frame.width * canvas.width)
                    let rectHeight = max(3, frame.height * canvas.height)
                    SceneWorkspaceLayerRect(
                        kind: item.kind,
                        width: rectWidth,
                        height: rectHeight
                    )
                    .offset(
                        x: frame.minX * canvas.width,
                        y: (1 - frame.maxY) * canvas.height
                    )
                }
            }
            .frame(width: canvas.width, height: canvas.height)
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .offset(x: canvas.minX, y: canvas.minY)
        }
    }
}

private struct SceneWorkspaceLayerRect: View {
    let kind: SceneLayerKind
    let width: CGFloat
    let height: CGFloat

    private var corner: CGFloat { kind == .camera ? 5 : 4 }

    private var fill: Color { Color.white.opacity(0.14) }

    private var glyph: String {
        kind == .camera ? "video.fill" : "macwindow"
    }

    private var glyphTint: Color { Color.white.opacity(0.85) }

    var body: some View {
        let minSide = min(width, height)
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(fill)
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(.white.opacity(0.28), lineWidth: 1)
            }
            .overlay {
                if minSide > 14 {
                    Image(systemName: glyph)
                        .font(.system(size: min(11, minSide * 0.42), weight: .semibold))
                        .foregroundStyle(glyphTint)
                }
            }
            .frame(width: width, height: height)
    }
}

private func workspaceHeader(_ title: String, icon: String) -> some View {
    BlitzUI.sectionLabel(title, icon: icon)
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
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 28)
            .padding(.vertical, 28)
        }
        .foregroundStyle(.white)
    }

    private var onboardingHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Film with your iPhone")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
            Text("Your iPhone has a better camera than a webcam. It records the video while your Mac shows it live.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var setupStepsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SET UP IN 4 STEPS")
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.7)
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
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .blitzGlassSurface(cornerRadius: 16)
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
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(accent)
        }
        .frame(width: 24, height: 24)
    }

    private var nearbyDevicesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("NEARBY IPHONES")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.7)
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
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .blitzGlassSurface(cornerRadius: 16)
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
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
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
        Text(title.uppercased())
            .font(.system(size: 11, weight: .medium))
            .tracking(0.8)
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
            .font(.system(size: 10, weight: .heavy))
            .tracking(0.8)
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
            Text("SCENE")
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.8)
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
            Text("AUDIO")
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.8)
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
                Text("EXPORT")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.8)
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
