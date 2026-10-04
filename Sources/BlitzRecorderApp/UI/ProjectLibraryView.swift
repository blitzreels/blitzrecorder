import AppKit
import SwiftUI

struct ProjectLibraryRenameRequest {
    let project: RecordingProjectHistory.Entry
    let title: String
}

struct ProjectTranscriptTitleRequest {
    let project: RecordingProjectHistory.Entry
    let transcript: String
}

struct ProjectTranscriptSpeakerRenameRequest {
    let project: RecordingProjectHistory.Entry
    let rename: TranscriptSpeakerRenameRequest
}

enum ProjectLibrarySymbols {
    static let media = "film.stack"
}

struct ProjectLibraryNavigationState: Equatable {
    enum Section: String, CaseIterable {
        case recordings = "Recordings"
        case shared = "Shared"
    }
    var section: Section = .recordings
    var selectedProjectIDs: Set<UUID> = []
    var searchText = ""
    var filters = ProjectLibraryFilters()

    mutating func reconcileSelection(availableProjectIDs: [UUID]) {
        let validSelection = selectedProjectIDs.intersection(availableProjectIDs)
        let nextSelection = validSelection.isEmpty
            ? Set(availableProjectIDs.prefix(1))
            : validSelection
        guard nextSelection != selectedProjectIDs else { return }
        selectedProjectIDs = nextSelection
    }

    struct Removal {
        let previousOrder: [UUID]
        let removedIDs: Set<UUID>
        let availableIDs: [UUID]
    }

    mutating func reconcileAfterRemoval(_ request: Removal) {
        let remaining = selectedProjectIDs.subtracting(request.removedIDs).intersection(request.availableIDs)
        if !remaining.isEmpty {
            selectedProjectIDs = remaining
            return
        }
        let anchor = request.previousOrder.firstIndex { selectedProjectIDs.contains($0) } ?? 0
        let available = Set(request.availableIDs)
        let next = request.previousOrder.dropFirst(anchor).first { available.contains($0) }
            ?? request.previousOrder.prefix(anchor).last { available.contains($0) }
            ?? request.availableIDs.first
        selectedProjectIDs = next.map { [$0] } ?? []
    }
}

struct ProjectLibraryView: View {
    @Bindable var vm: RecorderViewModel
    @Bindable var sharing = HostedVideoShareController.shared
    let folderStore = ProjectFolderStore.shared
    @State var collapsedFolderIDs: Set<String> = []
    @State var dropTargetID: String?
    @State var folderPrompt: ProjectFolderPrompt?
    @State var folderNameDraft = ""
    @State var openingProjectID: UUID?
    @State var showsProjectMenu = false
    @State private var projectsPendingDeletion: [RecordingProjectHistory.Entry] = []
    @State private var projectPendingRename: RecordingProjectHistory.Entry?
    @State private var projectTitleDraft = ""
    @State var titleGenerationProjectID: UUID?
    let metadataStore = ProjectLibraryMetadataStore.shared
    var metadataByProjectID: [UUID: ProjectLibraryMetadata] { metadataStore.metadata }
    @State var showsFilters = false
    @State var transcriptSearch = ProjectTranscriptSearch()
    @State var transcriptMatches: [UUID: [ProjectTranscriptMatch]] = [:]
    @State var isSearchingTranscripts = false
    @State var transcriptByProjectID: [UUID: RecordingTranscript] = [:]
    @State var transcriptUnavailableIDs: Set<UUID> = []
    @State var projectPlayback = EditorPlaybackController()
    @State var projectWaveformLibrary = EditorMediaLibrary()
    @State var playbackProjectID: UUID?
    @State var playbackProjectPath: String?
    @State var playbackWaveformSamples: [Float] = []
    @State var playbackLoadError: String?
    @State var mediaAssets: [EditorAsset] = []
    @State var mediaAssetsProjectID: UUID?
    @State var isLoadingMediaAssets = false
    @State var hoveredBulkProjectID: UUID?
    @Namespace var libraryFocus
    @FocusState var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            commandBar
                .blitzWindowToolbar(showsUpdate: false)
            ZStack {
                VStack(spacing: 0) {
                    trashStatusBar
                    folderStatusBar
                    HStack(spacing: 0) {
                        projectSidebar
                        Rectangle().fill(BlitzUI.hoverFill).frame(width: 1)
                        projectDetail
                    }
                }
                .opacity(workPolicy.loadsLocalProjects ? 1 : 0)
                .disabled(!workPolicy.loadsLocalProjects)
                .allowsHitTesting(workPolicy.loadsLocalProjects)
                .accessibilityHidden(!workPolicy.loadsLocalProjects)

                if vm.projectLibraryNavigation.section == .shared {
                    HostedVideoLibraryView(controller: sharing, showRecordings: {
                        vm.projectLibraryNavigation.section = .recordings
                    }, thumbnail: { video in
                        guard let path = sharing.projectPath(for: video),
                              let project = vm.recentProjects.first(where: { $0.projectPath == path }) else { return nil }
                        return metadataByProjectID[project.id]?.thumbnail
                    })
                }
            }
        }
        .background(BlitzUI.projectLibraryBackground)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .task {
            vm.refreshProjectsInBackground()
            selectFirstProjectIfNeeded()
            await sharing.refresh()
        }
        .task(id: metadataTaskID) {
            await loadMetadata()
        }
        .task(id: transcriptSearchTaskID) {
            await searchTranscripts()
        }
        .task(id: transcriptTaskID) {
            await loadSelectedTranscript()
        }
        .task(id: playbackTaskID) {
            await loadSelectedPlayback()
        }
        .task(id: waveformTaskID) {
            await loadSelectedWaveform()
        }
        .task(id: mediaTaskID) {
            await loadSelectedMediaAssets()
        }
        .onChange(of: filteredProjects.map(\.id)) {
            if !vm.projectTrash.isWorking { selectFirstProjectIfNeeded() }
        }
        .onChange(of: vm.projectLibraryNavigation.section) {
            if vm.projectLibraryNavigation.section == .shared {
                isSearchFocused = false
                showsProjectMenu = false
                showsFilters = false
                projectPlayback.teardown()
            }
        }
        .onDisappear {
            projectPlayback.teardown()
        }
        .alert(deletionAlertTitle, isPresented: deletionConfirmationBinding, presenting: projectsPendingDeletion) { projects in
            Button("Cancel", role: .cancel) {
                projectsPendingDeletion = []
            }
            Button("Move to Trash", role: .destructive) {
                projectsPendingDeletion = []
                projectPlayback.pauseForEditing()
                Task { await vm.deleteProjects(projects) }
            }
        } message: { projects in
            Text(deletionAlertMessage(projects))
        }
        .alert(
            "Rename recording",
            isPresented: renameConfirmationBinding,
            presenting: projectPendingRename
        ) { project in
            TextField("Video title", text: $projectTitleDraft)
            Button("Cancel", role: .cancel) {
                projectPendingRename = nil
            }
            Button("Rename") {
                vm.renameProject(ProjectLibraryRenameRequest(
                    project: project,
                    title: projectTitleDraft
                ))
                projectPendingRename = nil
            }
            .disabled(
                projectTitleDraft
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
            )
        } message: { _ in
            Text("This title is used in Projects and as the default export filename.")
        }
        .alert(folderPrompt?.title ?? "", isPresented: folderPromptBinding, presenting: folderPrompt) { prompt in
            TextField("Folder name", text: $folderNameDraft)
            Button("Cancel", role: .cancel) { folderPrompt = nil }
            Button(prompt.actionTitle) { commitFolderPrompt(prompt) }
                .disabled(!ProjectFolderPath.isValidName(folderNameDraft))
        } message: { _ in
            Text("Recordings in this folder are named Folder - Title, so files and exports stay grouped.")
        }
        .alert("Project action failed", isPresented: projectErrorBinding) {
            Button("OK") {
                vm.projectLibraryError = nil
            }
        } message: {
            Text(vm.projectLibraryError ?? "Unknown error.")
        }
    }

    private var commandBar: some View {
        HStack(spacing: 12) {
            Text("Projects")
                .font(BlitzType.section)
                .foregroundStyle(BlitzUI.primaryText)
            BlitzSegmentedPicker(configuration: .init(
                title: "Project library", options: ProjectLibraryNavigationState.Section.allCases,
                selection: $vm.projectLibraryNavigation.section, label: { $0.rawValue }
            ))
            .fixedSize()

            Spacer(minLength: 16)

            AppUpdateToolbarButton()

            Button("Import video…", systemImage: "square.and.arrow.down", action: vm.chooseVideoToImport)
                .blitzButton(.secondary)
                .disabled(vm.videoImportProgress != nil || vm.projectTrash.isWorking)
                .keyboardShortcut("i", modifiers: .command)
                .help("Create an editable project from an MP4, MOV, or M4V video (⌘I)")

            Button(action: vm.showRecorder) {
                HStack(spacing: 8) {
                    if vm.state == .idle {
                        Image(systemName: "plus")
                    } else {
                        Image(systemName: "record.circle.fill").foregroundStyle(BlitzUI.recordRed)
                    }
                    Text(vm.state == .idle ? "New recording" : "Return to recording")
                    Text("⌘N")
                        .font(BlitzType.caption)
                        .foregroundStyle(BlitzUI.secondaryText)
                        .accessibilityHidden(true)
                }
            }
            .blitzButton(.secondary)
            .disabled(vm.projectTrash.isWorking)
            .keyboardShortcut("n", modifiers: .command)
            .help("Set up a new recording (⌘N)")
            .accessibilityLabel(vm.state == .idle ? "New recording" : "Return to recording")
            .pointingHandCursor(enabled: !vm.projectTrash.isWorking)
        }
    }

    @ViewBuilder
    private var trashStatusBar: some View {
        if vm.projectTrash.status != nil || vm.projectTrash.canRestore {
            HStack(spacing: 12) {
                if vm.projectTrash.isWorking {
                    ProgressView().controlSize(.small)
                } else {
                    BlitzSymbol(configuration: .init(name: "trash", size: 16))
                }
                Text(vm.projectTrash.status ?? "Projects in Trash")
                    .font(BlitzType.label)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .accessibilityAddTraits(.updatesFrequently)
                Spacer(minLength: 8)
                if vm.projectTrash.restorableCount > 0 {
                    Button(vm.projectTrash.restorableCount == 1 ? "Restore project" : "Restore \(vm.projectTrash.restorableCount) projects") {
                        Task { await vm.restoreTrashedProjects() }
                    }
                    .blitzButton(.secondary)
                    .disabled(!vm.projectTrash.canRestore)
                }
                if !vm.projectTrash.isWorking && !vm.projectTrash.canRestore {
                    BlitzToolbarButton(configuration: .init(
                        title: "Dismiss", symbolName: "xmark", showsTitle: false,
                        action: vm.projectTrash.dismissStatus
                    ))
                }
            }
            .blitzWorkspaceToolbar()
        }
    }

    @ViewBuilder
    private var folderStatusBar: some View {
        if let status = vm.folderExportStatus {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text(status)
                    .font(BlitzType.label)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 8)
            }
            .blitzWorkspaceToolbar()
        } else if let undo = vm.folderMoveUndo {
            HStack(spacing: 12) {
                BlitzSymbol(configuration: .init(name: "folder", size: 16))
                Text(undo.message)
                    .font(BlitzType.label)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button("Undo") { vm.undoFolderMove() }
                    .blitzButton(.secondary)
                BlitzToolbarButton(configuration: .init(
                    title: "Dismiss", symbolName: "xmark", showsTitle: false,
                    action: { vm.folderMoveUndo = nil }
                ))
            }
            .blitzWorkspaceToolbar()
        }
    }

    func displayTitle(
        _ project: RecordingProjectHistory.Entry
    ) -> String {
        project.displayTitle
    }

    private func selectFirstProjectIfNeeded() {
        vm.projectLibraryNavigation.reconcileSelection(availableProjectIDs: filteredProjects.map(\.id))
    }

    var filteredProjects: [RecordingProjectHistory.Entry] {
        let titleMatches = Set(vm.filteredLibraryProjects.map(\.id))
        return vm.projectLibraryNavigation.filters.apply(.init(
            projects: vm.recentProjects.filter { entry in
                titleMatches.contains(entry.id) || transcriptMatches[entry.id] != nil
            }, metadata: metadataByProjectID,
            transcriptReadyIDs: Set(vm.recentProjects.compactMap { project in
                if case .ready = vm.transcriptionController.status(for: project) { return project.id }
                return nil
            }),
            now: Date(), calendar: .current
        ))
    }

    var selectedProject: RecordingProjectHistory.Entry? {
        guard vm.projectLibraryNavigation.selectedProjectIDs.count == 1,
              let selectedProjectID = vm.projectLibraryNavigation.selectedProjectIDs.first else {
            return nil
        }
        return vm.recentProjects.first { $0.id == selectedProjectID }
    }

    var selectedTranscript: RecordingTranscript? {
        guard let selectedProject else { return nil }
        return transcriptByProjectID[selectedProject.id]
    }

    private var deletionConfirmationBinding: Binding<Bool> {
        Binding(
            get: { !projectsPendingDeletion.isEmpty },
            set: { isPresented in
                if !isPresented {
                    projectsPendingDeletion = []
                }
            }
        )
    }

    private var deletionAlertTitle: String {
        projectsPendingDeletion.count == 1
            ? "Move project to Trash?"
            : "Move \(projectsPendingDeletion.count) projects to Trash?"
    }

    private func deletionAlertMessage(_ projects: [RecordingProjectHistory.Entry]) -> String {
        let names = projects.prefix(3).map { "“\(displayTitle($0))”" }.joined(separator: "\n")
        let remaining = projects.count > 3 ? "\n…and \(projects.count - 3) more" : ""
        return names + remaining + "\n\nSources and saved edits move to Trash. "
            + "Exported videos in the output folder stay in place. You can restore these projects afterward."
    }

    func projects(
        for selection: Set<UUID>
    ) -> [RecordingProjectHistory.Entry] {
        let candidates = selection.count == 1 ? vm.recentProjects : filteredProjects
        return candidates.filter { selection.contains($0.id) }
    }

    func queueDeletion(
        _ projects: [RecordingProjectHistory.Entry]
    ) {
        guard !vm.projectTrash.isWorking, !projects.isEmpty else { return }
        projectsPendingDeletion = projects
    }

    private var projectErrorBinding: Binding<Bool> {
        Binding(
            get: { vm.projectLibraryError != nil },
            set: { isPresented in
                if !isPresented {
                    vm.projectLibraryError = nil
                }
            }
        )
    }

    private var folderPromptBinding: Binding<Bool> {
        Binding(
            get: { folderPrompt != nil },
            set: { isPresented in
                if !isPresented { folderPrompt = nil }
            }
        )
    }

    private var renameConfirmationBinding: Binding<Bool> {
        Binding(
            get: { projectPendingRename != nil },
            set: { isPresented in
                if !isPresented {
                    projectPendingRename = nil
                }
            }
        )
    }

    func beginRename(
        _ project: RecordingProjectHistory.Entry
    ) {
        projectTitleDraft = project.title
        projectPendingRename = project
    }

}
