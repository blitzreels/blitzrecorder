import AppKit
import SwiftUI

struct EditorWindowRequest {
    let project: RecordingProjectHistory.Entry?
    let presentsExport: Bool
}

@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    struct Configuration {
        let coordinator: RecorderCoordinator
        let showRecorder: () -> Void
        let showSettings: (SettingsPane?) -> Void
        let historyChanged: () -> Void
        let closed: () -> Void
    }

    let viewModel: RecorderViewModel
    private let configuration: Configuration

    init(_ configuration: Configuration) {
        self.configuration = configuration
        viewModel = RecorderViewModel(coordinator: configuration.coordinator, previewStage: PreviewStageView())
        viewModel.showsFirstRunOnboarding = false
        viewModel.onShowRecorder = configuration.showRecorder
        viewModel.onPresentSettings = configuration.showSettings

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "BlitzRecorder Editor"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.moveToActiveSpace]
        MainWindowChrome.configure(window)
        window.center()
        super.init(window: window)
        window.delegate = self

        viewModel.onProjectOpened = { [weak self] in self?.updateTitle() }
        viewModel.onEditorHistoryChanged = { [weak self] in
            self?.updateTitle()
            configuration.historyChanged()
        }
        viewModel.onFillEditorWindow = { [weak window] in
            guard let window, let frame = window.screen?.visibleFrame else { return }
            window.setFrame(frame, display: true, animate: true)
        }
        let host = NSHostingView(rootView: EditorWindowView(vm: viewModel))
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        window.contentView = host
        window.contentMinSize = MainWindowController.minimumWindowContentSize
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(_ request: EditorWindowRequest) {
        viewModel.settings = configuration.coordinator.settings
        if let project = request.project {
            viewModel.openProject(project)
        }
        if request.presentsExport, viewModel.isEditorVisible {
            viewModel.exports.isEditorExportPresented = true
        }
        updateTitle()
        showWindow(nil)
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        configuration.historyChanged()
    }

    func windowWillClose(_ notification: Notification) {
        viewModel.studioMode = .projects
        window?.contentView = nil
        configuration.closed()
    }

    private func updateTitle() {
        window?.title = viewModel.isEditorVisible
            ? "BlitzRecorder Editor — \(viewModel.lastExportedProject?.displayTitle ?? "Video")"
            : "BlitzRecorder Editor — Library"
    }
}

private struct EditorWindowView: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        Group {
            if vm.isEditorVisible {
                EditorView(vm: vm).id(vm.lastExportedProject?.id)
            } else {
                ProjectLibraryView(vm: vm)
            }
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 4) {
                if vm.isEditorVisible {
                    Button(action: vm.showProjects) { Label("Library", systemImage: "chevron.left") }
                        .blitzButton(.quiet)
                }
                Button(action: vm.showRecorder) {
                    Image(systemName: "record.circle")
                }
                .blitzButton(.quiet)
                .accessibilityLabel("Show Recorder")
                .help("Bring the recorder window to the front")
            }
            .frame(height: MainWindowChrome.toolbarHeight)
            .padding(.leading, MainWindowChrome.trafficLightsWidth)
        }
        .overlay(alignment: .bottomTrailing) {
            ExportResultToast(vm: vm).padding(16)
        }
        .environment(\.windowToolbarLeadingInset, MainWindowChrome.trafficLightsWidth + (vm.isEditorVisible ? 144 : 52))
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
