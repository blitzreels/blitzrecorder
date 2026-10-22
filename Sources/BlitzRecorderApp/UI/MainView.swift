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
    @AppStorage("appSidebarHidden") private var isSidebarHidden = false
    @State private var studioExitDestination: AppSidebarDestination = .recordings
    @AppStorage("recorder.sourcesWidth") private var savedSourcesWidth = 232.0
    @State private var sourcesWidthDraft: Double?
    private static let sourcesWidthRange = 200.0...380.0

    init(configuration: Configuration) {
        vm = configuration.viewModel
        mcpServer = configuration.mcpServer
    }

    var body: some View {
        HStack(spacing: 0) {
            if !isSidebarHidden && !isInStudio {
                AppSidebar(vm: vm, mcpServer: mcpServer)
                    .shadow(color: BlitzUI.elevationShadow, radius: 8, x: 2)
                    .zIndex(1)
            }
            ZStack {
                backgroundLayer
                recorderContent()
                    .opacity(vm.studioMode == .record && !vm.isShowingSettings ? 1 : 0)
                    .disabled(vm.studioMode != .record || vm.isShowingSettings)
                    .allowsHitTesting(vm.studioMode == .record && !vm.isShowingSettings)
                    .accessibilityHidden(vm.studioMode != .record || vm.isShowingSettings)

                if (retainsEditor || vm.studioMode == .edit) && vm.canOpenEditor && !vm.hasSeparateEditorWindow {
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
        .overlay(alignment: .topLeading) {
            Group {
                if isInStudio {
                    StudioExitButton(configuration: .init(destination: studioExitDestination) {
                        vm.showSidebarDestination(studioExitDestination)
                    })
                } else {
                    AppSidebarToggle(isSidebarHidden: $isSidebarHidden)
                }
            }
            .frame(height: MainWindowChrome.toolbarHeight)
            .padding(.leading, MainWindowChrome.trafficLightsWidth)
        }
        .overlay(alignment: .bottomTrailing) {
            ExportResultToast(vm: vm)
                .padding(.trailing, 16)
                .padding(.bottom, 44)
        }
        .background { AppSidebarShortcuts(vm: vm) }
        .environment(\.windowToolbarLeadingInset, toolbarLeadingInset)
        .workspaceWindowSurface(vm: vm)
        .onChange(of: vm.studioMode, initial: true) { _, mode in
            if mode == .edit { retainsEditor = true }
        }
        .onChange(of: vm.sidebarDestination) { previous, destination in
            guard destination == .record, previous != .settings else { return }
            studioExitDestination = previous == .editor ? .editor : .recordings
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
            while !Task.isCancelled {
                vm.refreshScreenSourceAvailability()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .task(id: vm.state) {
            while !Task.isCancelled {
                vm.refreshScreenSuggestion()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)) { _ in
            vm.refreshScreenSuggestion()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            vm.refreshTargetWindow()
        }
    }

    private var isInStudio: Bool {
        vm.studioMode == .record && !vm.isShowingSettings
    }

    private var toolbarLeadingInset: CGFloat {
        if isInStudio { return MainWindowChrome.trafficLightsWidth + MainWindowChrome.studioExitWidth }
        if isSidebarHidden { return MainWindowChrome.trafficLightsWidth + MainWindowChrome.sidebarToggleWidth }
        return 16
    }

    private func recorderContent() -> some View {
        VStack(spacing: 0) {
            CaptureCommandBar(vm: vm)
                .blitzWindowToolbar()
            recordContent()
        }
        .confirmationDialog(
            "\(vm.session.pendingMicrophoneFallback?.preferredName ?? "Your preferred mic") is not connected",
            isPresented: Binding(
                get: { vm.session.pendingMicrophoneFallback != nil },
                set: { if !$0 { vm.session.pendingMicrophoneFallback = nil } }
            ),
            presenting: vm.session.pendingMicrophoneFallback
        ) { missing in
            if let fallback = missing.fallbackName {
                Button("Record with \(fallback)") { vm.recordWithFallbackMicrophone() }
            }
            Button("Cancel", role: .cancel) {}
        } message: { missing in
            Text(missing.fallbackName == nil
                ? "Connect it, then press Record."
                : "Connect it and press Record again, or record this take with another mic. Your preferred mic stays saved.")
        }
    }

    private func recordContent() -> some View {
        HStack(alignment: .top, spacing: 0) {
            SourcesSidebar(vm: vm)
                .frame(width: sourcesWidthDraft ?? savedSourcesWidth)
                .zIndex(1)
            BlitzPaneDivider(configuration: .init(
                axis: .horizontal,
                paneSide: .leading,
                label: "Sources width",
                value: Binding(get: { sourcesWidthDraft ?? savedSourcesWidth }, set: { sourcesWidthDraft = $0 }),
                bounds: Self.sourcesWidthRange,
                defaultValue: 232,
                onCommit: {
                    savedSourcesWidth = sourcesWidthDraft ?? savedSourcesWidth
                    sourcesWidthDraft = nil
                }
            ))

            RecorderInspectorSplitView {
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

                        if let remaining = vm.session.countdownRemaining {
                            RecordingCountdownOverlay(configuration: .init(
                                remaining: remaining,
                                onCancel: vm.cancelCountdown
                            ))
                        }

                        if vm.state == .idle && !vm.isLivePreviewEnabled {
                            livePreviewOffPlaceholder
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
            } inspector: {
                RecorderLayerInspector(vm: vm)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var livePreviewOffPlaceholder: some View {
        BlitzUI.canvasBackground
            .overlay {
                VStack(spacing: 12) {
                    Image(systemName: "eye.slash")
                        .font(BlitzType.glyph(28))
                        .foregroundStyle(BlitzUI.accent)
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

    private var backgroundLayer: some View {
        BlitzUI.canvasBackground
            .ignoresSafeArea()
    }
}

@MainActor
extension View {
    func workspaceWindowSurface(vm: RecorderViewModel) -> some View {
        self
            .environment(\.workspaceRecorder, vm)
            .background(BlitzUI.panelBackground)
            .ignoresSafeArea(.container, edges: .top)
            .sheet(item: Binding(
                get: { vm.libraryActions.folderPrompt },
                set: { vm.libraryActions.folderPrompt = $0 }
            )) { prompt in
                ProjectFolderNameEditor(
                    prompt: prompt,
                    name: Binding(
                        get: { vm.libraryActions.folderNameDraft },
                        set: { vm.libraryActions.folderNameDraft = $0 }
                    ),
                    affectedCount: vm.folderPromptAffectedCount(prompt),
                    onSave: { vm.commitFolderPrompt(prompt) }, onCancel: { vm.libraryActions.folderPrompt = nil }
                )
            }
    }
}
