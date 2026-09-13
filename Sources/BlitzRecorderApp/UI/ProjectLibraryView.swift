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

enum ProjectLibrarySymbols {
    static let media = "film.stack"
}

enum ProjectLibraryDetailTab: CaseIterable, Equatable {
    case overview
    case transcript
    case media

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .transcript: return "Transcript"
        case .media: return "Media"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "rectangle.on.rectangle"
        case .transcript: return "text.alignleft"
        case .media: return ProjectLibrarySymbols.media
        }
    }
}

struct ProjectLibraryNavigationState: Equatable {
    var selectedProjectIDs: Set<UUID> = []
    var selectedDetailTab: ProjectLibraryDetailTab = .overview
    var searchText = ""
    var filters = ProjectLibraryFilters()

    mutating func reconcileSelection(availableProjectIDs: [UUID]) {
        let validSelection = selectedProjectIDs.intersection(availableProjectIDs)
        let nextSelection = validSelection.isEmpty
            ? Set(availableProjectIDs.prefix(1))
            : validSelection
        guard nextSelection != selectedProjectIDs else { return }
        selectedProjectIDs = nextSelection
        selectedDetailTab = .overview
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
        selectedDetailTab = .overview
    }
}

struct ProjectLibraryView: View {
    private func speakerColor(_ index: Int) -> Color {
        let colors: [Color] = [
            BlitzUI.mint,
            .blue,
            .purple,
            .orange,
            .pink,
            .teal,
        ]
        return colors[index % colors.count]
    }

    @Bindable var vm: RecorderViewModel
    @State private var openingProjectID: UUID?
    @State private var projectsPendingDeletion: [RecordingProjectHistory.Entry] = []
    @State private var projectPendingRename: RecordingProjectHistory.Entry?
    @State private var projectTitleDraft = ""
    @State private var titleGenerationProjectID: UUID?
    @State private var metadataByProjectID: [UUID: ProjectLibraryMetadata] = [:]
    @State private var isLoadingMetadata = false
    @State private var showsFilters = false
    @State private var transcriptSearch = ProjectTranscriptSearch()
    @State private var transcriptMatches: [UUID: [ProjectTranscriptMatch]] = [:]
    @State private var isSearchingTranscripts = false
    @State private var transcriptByProjectID: [UUID: RecordingTranscript] = [:]
    @State private var projectPlayback = EditorPlaybackController()
    @State private var projectWaveformLibrary = EditorMediaLibrary()
    @State private var playbackProjectID: UUID?
    @State private var playbackProjectPath: String?
    @State private var playbackWaveformSamples: [Float] = []
    @State private var playbackLoadError: String?
    @State private var mediaAssets: [EditorAsset] = []
    @State private var mediaAssetsProjectID: UUID?
    @State private var isLoadingMediaAssets = false
    @State private var hoveredSidebarProjectID: UUID?
    @State private var hoveredBulkProjectID: UUID?
    @FocusState private var isSearchFocused: Bool

    private struct ThumbnailConfiguration {
        let metadata: ProjectLibraryMetadata
        let width: CGFloat
        let height: CGFloat
        let cornerRadius: CGFloat
        let showsDuration: Bool
    }

    private struct MetadataBlockConfiguration {
        let title: String
        let value: String
    }

    private struct TranscriptRowRequest {
        let segment: RecordingTranscript.Segment
        let transcript: RecordingTranscript
        let showsSpeaker: Bool
    }

    private struct TranscriptUnavailableRequest {
        let project: RecordingProjectHistory.Entry
        let status: TranscriptionJobStatus
    }

    private struct MediaWaveformRequest {
        let values: [Float]
        let tint: Color
    }

    var body: some View {
        VStack(spacing: 0) {
            commandBar
                .blitzWorkspaceToolbar()
                .controlSize(.large)
            trashStatusBar

            HStack(spacing: 0) {
                projectSidebar

                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 1)

                projectDetail
            }
        }
        .background(BlitzUI.projectLibraryBackground)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .task {
            vm.refreshRecentProjects()
            selectFirstProjectIfNeeded()
        }
        .task(id: vm.recentProjects.map(\.id)) {
            await loadMetadata()
        }
        .task(id: transcriptSearchTaskID) {
            await searchTranscripts()
        }
        .task(id: transcriptTaskID) {
            loadSelectedTranscript()
        }
        .task(id: playbackTaskID) {
            await loadSelectedPlayback()
        }
        .task(id: mediaTaskID) {
            await loadSelectedMediaAssets()
        }
        .onChange(of: filteredProjects.map(\.id)) {
            if !vm.projectTrash.isWorking { selectFirstProjectIfNeeded() }
        }
        .onChange(of: vm.projectLibraryNavigation.selectedProjectIDs) {
            vm.projectLibraryNavigation.selectedDetailTab = vm.projectLibraryNavigation.searchText.isEmpty ? .overview : .transcript
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
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(BlitzUI.primaryText)
            Text(projectCountLabel)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(BlitzUI.secondaryText)

            Spacer(minLength: 16)

            AppUpdateToolbarButton()

            BlitzToolbarButton(configuration: .init(
                title: "Settings",
                symbolName: "gearshape",
                showsTitle: true,
                action: { vm.onPresentSettings?(nil) }
            ))
            .help("Open Settings (Cmd+,)")

            Button(action: vm.showRecorder) {
                HStack(spacing: 10) {
                    Label("New recording", systemImage: "record.circle")
                    Text("⌘N")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.black.opacity(0.5))
                        .accessibilityHidden(true)
                }
            }
            .blitzButton(.accent)
            .controlSize(.large)
            .disabled(vm.projectTrash.isWorking)
            .keyboardShortcut("n", modifiers: .command)
            .help("Set up a new recording (⌘N)")
            .accessibilityLabel("New recording")
            .pointingHandCursor(enabled: !vm.projectTrash.isWorking)
        }
    }

    private var projectSidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                TextField("Search titles and spoken words", text: $vm.projectLibraryNavigation.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($isSearchFocused)

                if !vm.projectLibraryNavigation.searchText.isEmpty {
                    Button {
                        vm.projectLibraryNavigation.searchText = ""
                        isSearchFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(BlitzUI.secondaryText)
                            .frame(width: 22, height: 26)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .accessibilityLabel("Clear project search")
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(.white.opacity(0.055), in: .rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSearchFocused ? BlitzUI.mint.opacity(0.65) : .white.opacity(0.07), lineWidth: 1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            HStack(spacing: 8) {
                Button {
                    showsFilters.toggle()
                } label: {
                    Label(
                        vm.projectLibraryNavigation.filters.activeCount == 0
                            ? "Filters" : "Filters (\(vm.projectLibraryNavigation.filters.activeCount))",
                        systemImage: "line.3.horizontal.decrease"
                    )
                    .labelStyle(.titleAndIcon)
                }
                .blitzButton(.secondary)
                .fixedSize()
                .popover(isPresented: $showsFilters) {
                    ProjectLibraryFiltersView(filters: $vm.projectLibraryNavigation.filters)
                }
                BlitzDropdown(configuration: .init(
                    title: "Sort projects", selection: $vm.projectLibraryNavigation.filters.sort,
                    options: ProjectLibraryFilters.Sort.allCases.map { .init(value: $0, title: $0.rawValue, detail: nil) },
                    menuWidth: 220
                ))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            if vm.projectLibraryNavigation.filters.activeCount > 0 || isLoadingMetadata {
                HStack {
                    Text(isSearchingTranscripts ? "Searching transcripts…" : isLoadingMetadata ? "Loading project details…" : "\(filteredProjects.count) matching projects")
                        .font(.system(size: 10))
                        .foregroundStyle(BlitzUI.secondaryText)
                    Spacer()
                    if vm.projectLibraryNavigation.filters.activeCount > 0 {
                        Button("Clear filters") {
                            vm.projectLibraryNavigation.filters = .init(sort: vm.projectLibraryNavigation.filters.sort)
                        }
                        .blitzButton(.quiet)
                        .controlSize(.mini)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            Divider()

            List(selection: $vm.projectLibraryNavigation.selectedProjectIDs) {
                ForEach(filteredProjects, id: \.id) { project in
                    sidebarRow(project)
                        .tag(project.id)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(BlitzUI.projectLibraryBackground)
            .onDeleteCommand {
                queueDeletion(projects(for: vm.projectLibraryNavigation.selectedProjectIDs))
            }
            .contextMenu(forSelectionType: UUID.self) { selection in
                projectContextMenu(selection)
            } primaryAction: { selection in
                let projects = projects(for: selection)
                if !vm.projectTrash.isWorking, projects.count == 1, let project = projects.first {
                    vm.openProject(project)
                }
            }
        }
        .frame(width: 370)
        .background(BlitzUI.projectLibraryBackground)
    }

    private func sidebarRow(_ project: RecordingProjectHistory.Entry) -> some View {
        let metadata = metadataByProjectID[project.id] ?? .empty
        let isHovering = hoveredSidebarProjectID == project.id
        return HStack(spacing: 10) {
            projectThumbnail(ThumbnailConfiguration(
                metadata: metadata,
                width: 104,
                height: 66,
                cornerRadius: 6,
                showsDuration: true
            ))

            VStack(alignment: .leading, spacing: 3) {
                Text(displayTitle(project))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
                    .frame(height: 30, alignment: .topLeading)

                if let match = transcriptMatches[project.id]?.first {
                    Text("\(SilenceTime.label(match.time)) · \(match.text)")
                        .font(.system(size: 11))
                        .foregroundStyle(BlitzUI.mint)
                        .lineLimit(2)
                }

                Text(metadata.videoQuality?.label ?? (metadataByProjectID[project.id] == nil ? "Loading quality…" : "Quality unavailable"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(BlitzUI.secondaryText)
                    .lineLimit(1)
                    .help(metadata.videoQuality?.detail ?? "No readable video metadata")

                Text(project.recordedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            isHovering ? Color.white.opacity(0.07) : .clear,
            in: .rect(cornerRadius: 8)
        )
        .contentShape(.rect)
        .onHover { hovering in
            if hovering {
                hoveredSidebarProjectID = project.id
            } else if hoveredSidebarProjectID == project.id {
                hoveredSidebarProjectID = nil
            }
        }
        .pointingHandCursor()
    }

    @ViewBuilder
    private func projectContextMenu(
        _ selection: Set<UUID>
    ) -> some View {
        let projects = projects(for: selection)

        Group {
            if projects.count == 1, let project = projects.first {
                Button("Edit recording") {
                    vm.openProject(project)
                }

                Button {
                    beginRename(project)
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
            }

            if !projects.isEmpty {
                Button {
                    vm.revealProjects(projects)
                } label: {
                    Label(
                        projects.count == 1 ? "Show in Finder" : "Show Selected in Finder",
                        systemImage: "folder"
                    )
                }

                Divider()

                Button(role: .destructive) {
                    queueDeletion(projects)
                } label: {
                    Label(
                        projects.count == 1
                            ? "Move to Trash"
                            : "Move \(projects.count) Projects to Trash",
                        systemImage: "trash"
                    )
                }
            }
        }
        .disabled(vm.projectTrash.isWorking)
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
                    .font(.system(size: 12, weight: .medium))
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
    private var projectDetail: some View {
        if vm.projectLibraryNavigation.selectedProjectIDs.count > 1 {
            bulkSelectionDetail
        } else if let project = selectedProject {
            VStack(spacing: 0) {
                detailHeader(project)
                    .padding(.horizontal, 34)
                    .padding(.top, 24)
                    .padding(.bottom, 16)

                projectDetailTabBar

                Divider()

                GeometryReader { proxy in
                    let overviewLayout = ProjectLibraryOverviewSizing.layout(.init(
                        viewportSize: proxy.size
                    ))
                    ScrollView {
                        selectedProjectDetail(
                            project,
                            overviewLayout: overviewLayout
                        )
                        .frame(
                            maxWidth: vm.projectLibraryNavigation.selectedDetailTab == .transcript
                                ? 720
                                : overviewLayout.contentWidth,
                            alignment: .leading
                        )
                        .frame(
                            maxWidth: .infinity,
                            alignment: vm.projectLibraryNavigation.selectedDetailTab == .transcript
                                ? .topLeading : .top
                        )
                        .padding(.horizontal, 34)
                        .padding(.vertical, 24)
                    }
                }

                if vm.projectLibraryNavigation.selectedDetailTab == .transcript,
                   playbackProjectID == project.id,
                   projectPlayback.isReady {
                    ProjectLibraryPlaybackControls(configuration: .init(
                        controller: projectPlayback,
                        waveformSamples: playbackWaveformSamples
                    ))
                    .padding(.horizontal, 34)
                    .padding(.vertical, 12)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(BlitzUI.separator)
                            .frame(height: 1)
                    }
                }
            }
            .background(BlitzUI.projectLibraryBackground)
        } else {
            detailEmptyState
        }
    }

    private var projectDetailTabBar: some View {
        HStack(spacing: 2) {
            ForEach(ProjectLibraryDetailTab.allCases, id: \.self) { tab in
                BlitzTab(configuration: .init(
                    title: tab.title,
                    symbolName: tab.systemImage,
                    isSelected: vm.projectLibraryNavigation.selectedDetailTab == tab,
                    expands: false,
                    action: { vm.projectLibraryNavigation.selectedDetailTab = tab }
                ))
            }
        }
        .blitzTabGroup()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 34)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func selectedProjectDetail(
        _ project: RecordingProjectHistory.Entry,
        overviewLayout: ProjectLibraryOverviewLayout
    ) -> some View {
        switch vm.projectLibraryNavigation.selectedDetailTab {
        case .overview:
            VStack(alignment: .leading, spacing: 18) {
                detailPreview(project, overviewLayout: overviewLayout)
                detailMetadata(project)
            }
        case .transcript:
            inlineTranscript(project)
        case .media:
            projectMedia(project)
        }
    }

    private var bulkSelectionDetail: some View {
        let projects = projects(for: vm.projectLibraryNavigation.selectedProjectIDs)
        let summary = ProjectLibrarySelectionSummary(
            projects.map { metadataByProjectID[$0.id] ?? .empty }
        )
        return VStack(spacing: 18) {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(projects.count) projects selected")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white.opacity(0.94))

                    Text("Choose a project below to view its details.")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.44))
                }

                Spacer(minLength: 16)

                HStack(spacing: 8) {
                    bulkMetric(.init(
                        title: "Duration",
                        value: summary.durationLabel,
                        systemImage: "clock"
                    ))
                    bulkMetric(.init(
                        title: "Size",
                        value: summary.sizeLabel,
                        systemImage: "externaldrive"
                    ))
                }
            }

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 280), spacing: 14)],
                    spacing: 14
                ) {
                    ForEach(projects, id: \.id) { project in
                        bulkProjectCard(project)
                    }
                }
                .padding(1)
            }
            .frame(maxHeight: 520)

            HStack(spacing: 10) {
                ProjectLibraryActionButton(configuration: .init(
                    title: "Show in Finder",
                    systemImage: "folder",
                    tone: .secondary,
                    isLoading: false,
                    action: { vm.revealProjects(projects) }
                ))

                Button(role: .destructive) {
                    queueDeletion(projects)
                } label: {
                    Label("Move \(projects.count) projects to Trash", systemImage: "trash")
                }
                .blitzButton(.secondary)
                .disabled(vm.projectTrash.isWorking)
                .pointingHandCursor()
            }
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 30)
        .frame(maxWidth: 1_040)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BlitzUI.projectLibraryBackground)
    }

    private struct BulkMetricConfiguration {
        let title: String
        let value: String
        let systemImage: String
    }

    private func bulkMetric(
        _ configuration: BulkMetricConfiguration
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: configuration.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BlitzUI.mint)

            VStack(alignment: .leading, spacing: 2) {
                Text(configuration.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.40))
                Text(configuration.value)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.84))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 14)
        .frame(minWidth: 138, minHeight: 52, alignment: .leading)
        .background(.white.opacity(0.04), in: .rect(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        }
    }

    private func bulkProjectCard(
        _ project: RecordingProjectHistory.Entry
    ) -> some View {
        let metadata = metadataByProjectID[project.id] ?? .empty
        let isHovering = hoveredBulkProjectID == project.id
        return Button {
            vm.projectLibraryNavigation.selectedProjectIDs = [project.id]
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                GeometryReader { proxy in
                    ZStack(alignment: .topTrailing) {
                        projectThumbnail(.init(
                            metadata: metadata,
                            width: proxy.size.width,
                            height: proxy.size.height,
                            cornerRadius: 10,
                            showsDuration: true
                        ))

                        Label("View project", systemImage: "arrow.up.right")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(.white.opacity(0.94))
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(.black.opacity(0.72), in: .capsule)
                            .padding(10)
                            .opacity(isHovering ? 1 : 0)
                    }
                }
                .frame(height: 146)

                VStack(alignment: .leading, spacing: 8) {
                    Text(displayTitle(project))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(isHovering ? 0.96 : 0.88))
                        .lineLimit(1)

                    HStack(spacing: 7) {
                        Label(
                            metadata.durationLabel ?? "—",
                            systemImage: "clock"
                        )
                        Text("·")
                        Text(metadata.sizeLabel ?? "Size unavailable")
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(1)

                    Text(project.recordedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.36))
                        .lineLimit(1)
                }
                .padding(13)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                .white.opacity(isHovering ? 0.075 : 0.035),
                in: .rect(cornerRadius: 13)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(
                        isHovering
                            ? Color.white.opacity(0.18)
                            : BlitzUI.separator,
                        lineWidth: 1
                    )
            }
            .contentShape(.rect(cornerRadius: 13))
        }
        .buttonStyle(BlitzPressButtonStyle())
        .onHover { hovering in
            if hovering {
                hoveredBulkProjectID = project.id
            } else if hoveredBulkProjectID == project.id {
                hoveredBulkProjectID = nil
            }
        }
        .pointingHandCursor()
        .help("View \(displayTitle(project))")
        .contextMenu { projectContextMenu(vm.projectLibraryNavigation.selectedProjectIDs) }
    }

    private func detailPreview(
        _ project: RecordingProjectHistory.Entry,
        overviewLayout: ProjectLibraryOverviewLayout
    ) -> some View {
        let metadata = metadataByProjectID[project.id] ?? .empty
        return HStack(spacing: 0) {
            Spacer(minLength: 0)
            ProjectLibraryPlayerSurface(configuration: .init(
                controller: projectPlayback,
                isCurrentProject: playbackProjectID == project.id,
                fallbackThumbnail: metadata.thumbnail,
                waveformSamples: playbackWaveformSamples,
                loadError: playbackLoadError ?? projectPlayback.loadError,
                maximumSize: overviewLayout.playerMaximumSize
            ))
            Spacer(minLength: 0)
        }
    }

    private func detailHeader(
        _ project: RecordingProjectHistory.Entry
    ) -> some View {
        let status = vm.transcriptionController.status(for: project)
        let recordedAt = project.recordedAt
        return HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(displayTitle(project))
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(recordedAt.formatted(date: .abbreviated, time: .shortened))
                        .help("Recorded \(recordedAt.formatted(date: .long, time: .shortened))")
                    Text("·")
                    Text(transcriptStatusLabel(status))
                        .foregroundStyle(transcriptStatusColor(status))
                }
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(BlitzUI.secondaryText)
            }

            Spacer(minLength: 0)

            detailActions(project)
                .fixedSize()
        }
        .contextMenu { projectContextMenu([project.id]) }
    }

    private func detailActions(
        _ project: RecordingProjectHistory.Entry
    ) -> some View {
        let isOpening = openingProjectID == project.id
        return HStack(spacing: 12) {
            Button(role: .destructive) { queueDeletion([project]) } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 36, height: 40)
            }
            .buttonStyle(BlitzSelectionButtonStyle(isSelected: false))
            .pointingHandCursor()
            .accessibilityLabel("Move to Trash")
            .help("Move this recording to Trash")

            EditRecordingButton(configuration: .init(
                title: "Edit recording",
                isLoading: isOpening,
                help: "Open this recording in the editor",
                action: {
                    openingProjectID = project.id
                    Task {
                        await Task.yield()
                        vm.openProject(project)
                        openingProjectID = nil
                    }
                }
            ))
            .controlSize(.large)
        }
        .disabled(vm.projectTrash.isWorking)
    }

    @ViewBuilder
    private func inlineTranscript(
        _ project: RecordingProjectHistory.Entry
    ) -> some View {
        let status = vm.transcriptionController.status(for: project)
        VStack(alignment: .leading, spacing: 24) {
            if let transcript = selectedTranscript {
                HStack(spacing: 8) {
                    Text(transcriptSummaryLabel(transcript))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(BlitzUI.secondaryText)

                    Spacer(minLength: 12)

                    Button {
                        guard titleGenerationProjectID == nil else { return }
                        titleGenerationProjectID = project.id
                        Task {
                            await vm.generateProjectTitle(
                                ProjectTranscriptTitleRequest(
                                    project: project,
                                    transcript: transcript.formattedText
                                )
                            )
                            titleGenerationProjectID = nil
                        }
                    } label: {
                        if titleGenerationProjectID == project.id {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Generate title", systemImage: "sparkles")
                        }
                    }
                    .buttonStyle(BlitzButtonStyle(.secondary))
                    .disabled(titleGenerationProjectID != nil)
                    .help("Generate a title from the transcript using the local AI model")

                    TranscriptCopyButton(.init(
                        markdown: transcript.markdownText(title: displayTitle(project)),
                        appearance: .compact
                    ))
                }

                let matches = transcriptMatches[project.id] ?? []
                let matchIDs = Set(matches.map(\.id))
                if !matches.isEmpty {
                    Text("\(matches.count) matching moments · Click a timestamp to play")
                        .font(.system(size: 12))
                        .foregroundStyle(BlitzUI.mint)
                }
                if transcript.segments.isEmpty {
                    Text(transcript.text).textSelection(.enabled)
                }
                let segments = matches.isEmpty ? transcript.segments : transcript.segments.filter { matchIDs.contains($0.id) }
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                        inlineTranscriptRow(TranscriptRowRequest(
                            segment: segment,
                            transcript: transcript,
                            showsSpeaker: transcript.speakerCount > 1
                                && (index == 0 || segments[index - 1].speakerID != segment.speakerID)
                        ))
                    }
                }
            } else {
                transcriptUnavailableState(TranscriptUnavailableRequest(
                    project: project,
                    status: status
                ))
            }
        }
    }

    private func inlineTranscriptRow(
        _ request: TranscriptRowRequest
    ) -> some View {
        let speakerIndex = request.transcript.speakers.firstIndex {
            $0.id == request.segment.speakerID
        } ?? 0
        return HStack(alignment: .top, spacing: 18) {
            TranscriptTimestampButton(
                timestamp: durationLabel(request.segment.startTime),
                isEnabled: playbackProjectID == selectedProject?.id && projectPlayback.isReady,
                isActive: projectPlayback.isPlaying
                    && projectPlayback.currentTime >= request.segment.startTime
                    && projectPlayback.currentTime < request.segment.endTime,
                action: {
                    projectPlayback.play(from: request.segment.startTime)
                }
            )

            VStack(alignment: .leading, spacing: 6) {
                if request.showsSpeaker {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(speakerColor(speakerIndex).opacity(0.75))
                            .frame(width: 5, height: 5)
                        Text(request.transcript.speakerName(for: request.segment.speakerID))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(BlitzUI.secondaryText)
                    }
                    .padding(.top, 4)
                }

                Text(request.segment.text)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(BlitzUI.primaryText)
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, request.showsSpeaker ? 0 : 3)
            }
        }
        .padding(.top, request.showsSpeaker ? 18 : 6)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func transcriptUnavailableState(
        _ request: TranscriptUnavailableRequest
    ) -> some View {
        if request.status == .waitingForModel {
            transcriptionModelState(request.project)
        } else {
            transcriptJobState(request)
        }
    }

    private func transcriptJobState(
        _ request: TranscriptUnavailableRequest
    ) -> some View {
        HStack(spacing: 12) {
            if request.status.isRunning {
                ProgressView()
                    .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(transcriptStatusLabel(request.status))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                Text(transcriptUnavailableDetail(request.status))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.white.opacity(0.38))
            }

            Spacer(minLength: 0)

            if !request.status.isRunning {
                Button(transcriptActionTitle(request.status)) {
                    performTranscriptAction(request.project)
                }
                .buttonStyle(BlitzButtonStyle(.secondary))
                .pointingHandCursor()
            }
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func transcriptionModelState(
        _ project: RecordingProjectHistory.Entry
    ) -> some View {
        switch vm.transcriptionController.modelState {
        case .notDownloaded:
            transcriptionModelCard(.init(
                title: "Local speech model required",
                detail: "Download it once to generate timed transcripts and detect speakers on this Mac.",
                systemImage: "arrow.down.circle",
                errorMessage: nil,
                progress: nil,
                progressLabel: nil,
                actionTitle: "Download and Generate",
                action: { requestTranscript(project) }
            ))
        case .downloading(let progress, let phase):
            transcriptionModelCard(.init(
                title: "Downloading speech model",
                detail: "Keep BlitzRecorder open. Transcription starts when the model is ready.",
                systemImage: "arrow.down.circle.fill",
                errorMessage: nil,
                progress: progress,
                progressLabel: "\(phase) · \(Int((progress * 100).rounded()))%",
                actionTitle: nil,
                action: nil
            ))
        case .failed(let message):
            transcriptionModelCard(.init(
                title: "Model download failed",
                detail: "The model is stored locally and can be downloaded again.",
                systemImage: "exclamationmark.triangle.fill",
                errorMessage: message,
                progress: nil,
                progressLabel: nil,
                actionTitle: "Retry Download",
                action: { requestTranscript(project) }
            ))
        case .ready:
            transcriptJobState(TranscriptUnavailableRequest(
                project: project,
                status: .queued
            ))
        }
    }

    private struct TranscriptionModelCardConfiguration {
        let title: String
        let detail: String
        let systemImage: String
        let errorMessage: String?
        let progress: Double?
        let progressLabel: String?
        let actionTitle: String?
        let action: (() -> Void)?
    }

    private func transcriptionModelCard(
        _ configuration: TranscriptionModelCardConfiguration
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: configuration.systemImage)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(
                    configuration.errorMessage == nil
                        ? BlitzUI.mint
                        : BlitzUI.warning
                )
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 7) {
                Text(configuration.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.80))

                Text(configuration.detail)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.white.opacity(0.42))
                    .fixedSize(horizontal: false, vertical: true)

                if let progress = configuration.progress {
                    ProgressView(value: progress)
                        .tint(BlitzUI.mint)
                        .frame(maxWidth: 360)
                }

                if let progressLabel = configuration.progressLabel {
                    Text(progressLabel)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.46))
                }

                if let errorMessage = configuration.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(BlitzUI.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            if let actionTitle = configuration.actionTitle,
               let action = configuration.action {
                Button(actionTitle, action: action)
                    .buttonStyle(BlitzButtonStyle(.secondary))
                    .pointingHandCursor()
            }
        }
        .padding(.vertical, 12)
    }

    private func detailMetadata(
        _ project: RecordingProjectHistory.Entry
    ) -> some View {
        let metadata = metadataByProjectID[project.id] ?? .empty
        return VStack(alignment: .leading, spacing: 16) {
            Rectangle()
                .fill(BlitzUI.separator)
                .frame(height: 1)

            HStack(alignment: .top, spacing: 24) {
                metadataBlock(MetadataBlockConfiguration(
                    title: "Duration",
                    value: metadata.durationLabel ?? "—"
                ))
                metadataBlock(MetadataBlockConfiguration(
                    title: "Video quality",
                    value: metadata.videoQuality?.label ?? "—"
                ))
                .help(metadata.videoQuality?.detail ?? "No readable video metadata")
                metadataBlock(MetadataBlockConfiguration(
                    title: "Sources",
                    value: metadata.sourceSummary
                ))
                metadataBlock(MetadataBlockConfiguration(
                    title: "Project size",
                    value: metadata.sizeLabel ?? "—"
                ))
            }
        }
    }

    private func metadataBlock(
        _ configuration: MetadataBlockConfiguration
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(configuration.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.36))
            Text(configuration.value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func projectMedia(
        _ project: RecordingProjectHistory.Entry
    ) -> some View {
        let captureAssets = mediaAssets.filter { $0.kind != .output }
        let outputAssets = mediaAssets.filter { $0.kind == .output }
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 16) {
                Text(mediaCaptureSummary(captureAssets))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(BlitzUI.secondaryText)

                Spacer(minLength: 12)

                Button {
                    vm.revealProject(project)
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                .buttonStyle(BlitzButtonStyle(.secondary))
                .pointingHandCursor()
            }

            if isLoadingMediaAssets, mediaAssetsProjectID != project.id {
                ProgressView("Loading media…")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(BlitzUI.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if captureAssets.isEmpty {
                Text("No original capture files are available for this recording.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(BlitzUI.secondaryText)
                    .padding(.vertical, 24)
            } else {
                mediaAssetList(.init(title: "Original captures", assets: captureAssets))
            }

            if !outputAssets.isEmpty {
                mediaAssetList(.init(title: "Exports", assets: outputAssets))
            }
        }
    }

    private struct MediaAssetListConfiguration {
        let title: String
        let assets: [EditorAsset]
    }

    private func mediaAssetList(_ configuration: MediaAssetListConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(configuration.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BlitzUI.primaryText)
                .padding(.bottom, 4)

            ForEach(configuration.assets) { asset in
                mediaAssetRow(asset)

                if asset.id != configuration.assets.last?.id {
                    Rectangle()
                        .fill(BlitzUI.separator)
                        .frame(height: 1)
                }
            }
        }
    }

    private func mediaAssetRow(_ asset: EditorAsset) -> some View {
        let details = projectWaveformLibrary.technicalMetadata[asset.id]
        let duration = projectWaveformLibrary.durations[asset.id]
            .map(ProjectLibraryMetadata.durationLabel) ?? "—"
        let fileSize = projectWaveformLibrary.fileSizes[asset.id] ?? "—"
        let format = details?.format ?? asset.url.pathExtension.uppercased()
        return HStack(spacing: 16) {
            mediaAssetVisual(asset)
                .frame(width: 144, height: 81)
                .background(BlitzUI.quietFill, in: .rect(cornerRadius: BlitzUI.controlRadius))
                .clipShape(.rect(cornerRadius: BlitzUI.controlRadius))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(mediaAssetTitle(asset))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(BlitzUI.primaryText)

                    if !asset.exists {
                        Text("Missing file")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(BlitzUI.warning)
                    }

                    Spacer(minLength: 8)

                    Text(duration)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(BlitzUI.secondaryText)
                }

                if let details {
                    Text(details.quality)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(BlitzUI.secondaryText)
                        .lineLimit(2)
                }

                Text("\(format) · \(fileSize) · \(asset.url.lastPathComponent)")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(BlitzUI.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(asset.url.lastPathComponent)
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([asset.url])
            } label: {
                BlitzSymbol(configuration: .init(name: "folder", size: 16))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(BlitzSelectionButtonStyle(isSelected: false))
            .disabled(!asset.exists)
            .pointingHandCursor(enabled: asset.exists)
            .accessibilityLabel("Show \(mediaAssetTitle(asset)) in Finder")
            .help("Show \(asset.url.lastPathComponent) in Finder")
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func mediaAssetVisual(_ asset: EditorAsset) -> some View {
        if asset.isVideo, let frame = projectWaveformLibrary.filmstrips[asset.id]?.first {
            Image(decorative: frame, scale: 1)
                .resizable()
                .scaledToFit()
        } else if asset.isAudio, asset.exists {
            mediaWaveform(MediaWaveformRequest(
                values: projectWaveformLibrary.waveforms[asset.id] ?? [],
                tint: BlitzUI.secondaryText
            ))
            .padding(.horizontal, 12)
            .padding(.vertical, 22)
        } else {
            BlitzSymbol(configuration: .init(name: asset.systemImage, size: 24))
                .foregroundStyle(BlitzUI.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func mediaWaveform(
        _ request: MediaWaveformRequest
    ) -> some View {
        Canvas { context, size in
            guard !request.values.isEmpty else {
                let line = CGRect(
                    x: 0,
                    y: size.height / 2 - 0.75,
                    width: size.width,
                    height: 1.5
                )
                context.fill(
                    Path(roundedRect: line, cornerRadius: 0.75),
                    with: .color(request.tint.opacity(0.38))
                )
                return
            }
            let slot = size.width / CGFloat(request.values.count)
            let barWidth = max(1, slot - 1)
            let maximumHeight = size.height - 8
            for (index, value) in request.values.enumerated() {
                let height = max(1.5, CGFloat(value) * maximumHeight)
                let bar = CGRect(
                    x: CGFloat(index) * slot + (slot - barWidth) / 2,
                    y: (size.height - height) / 2,
                    width: barWidth,
                    height: height
                )
                context.fill(
                    Path(roundedRect: bar, cornerRadius: barWidth / 2),
                    with: .color(request.tint.opacity(0.84))
                )
            }
        }
    }

    private func mediaCaptureSummary(
        _ assets: [EditorAsset]
    ) -> String {
        let screenCount = assets.filter { $0.kind == .screen && $0.exists }.count
        let cameraCount = assets.filter { $0.kind == .camera && $0.exists }.count
        let audioCount = assets.filter {
            ($0.kind == .microphone || $0.kind == .systemAudio) && $0.exists
        }.count
        return ProjectMediaInventorySummary(
            screenCaptureCount: screenCount,
            cameraCaptureCount: cameraCount,
            audioTrackCount: audioCount
        ).label
    }

    private func mediaAssetTitle(
        _ asset: EditorAsset
    ) -> String {
        let baseTitle: String
        switch asset.kind {
        case .output: baseTitle = "Finished export"
        case .screen: baseTitle = "Screen capture"
        case .camera: baseTitle = "Camera capture"
        case .microphone: baseTitle = "Microphone"
        case .systemAudio: baseTitle = "System audio"
        case .other: baseTitle = asset.title
        }
        let matchingAssets = mediaAssets.filter { $0.kind == asset.kind }
        guard matchingAssets.count > 1,
              let index = matchingAssets.firstIndex(where: { $0.id == asset.id }) else {
            return baseTitle
        }
        return "\(baseTitle) \(index + 1)"
    }

    private var detailEmptyState: some View {
        VStack(spacing: 8) {
            Text(vm.recentProjects.isEmpty ? "No projects yet" : (filteredProjects.isEmpty ? "No projects found" : "Select a project"))
                .font(.system(size: 18, weight: .semibold))
            Text(
                vm.recentProjects.isEmpty
                    ? (vm.projectTrash.canRestore ? "Restore a project above or start a new recording." : "Start a new recording to create your first project.")
                    : (filteredProjects.isEmpty ? "Try a different search or clear the filters." : "Choose a recording from the library.")
            )
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(.secondary)
            if filteredProjects.isEmpty, vm.projectLibraryNavigation.filters.activeCount > 0 {
                Button("Clear filters") {
                    vm.projectLibraryNavigation.filters = .init(sort: vm.projectLibraryNavigation.filters.sort)
                }
                .blitzButton(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BlitzUI.projectLibraryBackground)
    }

    private func projectThumbnail(
        _ configuration: ThumbnailConfiguration
    ) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black.opacity(0.3)
            if let thumbnail = configuration.metadata.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(width: configuration.width, height: configuration.height)
            } else {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.075),
                            Color.white.opacity(0.025)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Image(systemName: configuration.metadata.sourceRoles.isDisjoint(with: ["screen", "camera"])
                        && !configuration.metadata.sourceRoles.isDisjoint(with: ["microphone", "systemAudio"])
                        ? "waveform" : "film")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(BlitzUI.secondaryText)
                }
            }

            if configuration.showsDuration,
               let duration = configuration.metadata.durationSeconds {
                BlitzTimecode(configuration: .init(time: duration, duration: duration))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.94))
                    .padding(.horizontal, 4)
                    .frame(height: 18)
                    .background(.black.opacity(0.8), in: .rect(cornerRadius: 4))
                    .padding(4)
            }
        }
        .frame(width: configuration.width, height: configuration.height)
        .clipShape(.rect(cornerRadius: configuration.cornerRadius))
        .overlay {
            RoundedRectangle(
                cornerRadius: configuration.cornerRadius,
                style: .continuous
            )
            .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }

    private func performTranscriptAction(
        _ project: RecordingProjectHistory.Entry
    ) {
        switch vm.transcriptionController.status(for: project) {
        case .ready:
            loadSelectedTranscript()
        case .notGenerated, .failed:
            vm.transcriptionController.retry(.project(
                URL(fileURLWithPath: project.projectPath)
            ))
        case .waitingForModel:
            requestTranscript(project)
        case .queued, .preparingAudio, .transcribing, .diarizing, .saving:
            break
        }
    }

    private func requestTranscript(
        _ project: RecordingProjectHistory.Entry
    ) {
        vm.transcriptionController.retry(.project(
            URL(fileURLWithPath: project.projectPath)
        ))
    }

    private func transcriptActionTitle(
        _ status: TranscriptionJobStatus
    ) -> String {
        switch status {
        case .ready:
            return "Reload Transcript"
        case .failed:
            return "Retry Transcript"
        case .notGenerated:
            return "Generate Transcript"
        case .waitingForModel:
            return "Download Model"
        case .queued, .preparingAudio, .transcribing, .diarizing, .saving:
            return "Transcribing"
        }
    }

    private func transcriptSummaryLabel(
        _ transcript: RecordingTranscript
    ) -> String {
        if transcript.speakerCount == 1,
           let speaker = transcript.speakers.first {
            return "\(durationLabel(transcript.speakingDuration(for: speaker.id))) · "
                + "\(transcript.segmentCount) segments"
        }
        return "\(transcript.speakerCount) speakers · "
            + "\(transcript.segmentCount) segments"
    }

    private func transcriptStatusLabel(
        _ status: TranscriptionJobStatus
    ) -> String {
        switch status {
        case .ready:
            return "Transcript ready"
        case .failed:
            return "Transcript failed"
        case .waitingForModel:
            return "Speech model required"
        case .notGenerated:
            return "No transcript"
        case .queued, .preparingAudio, .transcribing, .diarizing, .saving:
            return "Transcribing"
        }
    }

    private func transcriptStatusColor(
        _ status: TranscriptionJobStatus
    ) -> Color {
        switch status {
        case .ready:
            return BlitzUI.mint.opacity(0.84)
        case .failed:
            return BlitzUI.warning
        case .notGenerated, .waitingForModel,
             .queued, .preparingAudio, .transcribing, .diarizing, .saving:
            return .white.opacity(0.42)
        }
    }

    private func transcriptUnavailableDetail(
        _ status: TranscriptionJobStatus
    ) -> String {
        switch status {
        case .ready:
            return "The saved transcript could not be loaded."
        case .failed:
            return "Retry local transcription for this recording."
        case .waitingForModel:
            return "Download the local speech model to find speakers and segments."
        case .notGenerated:
            return "Generate timed text and speaker diarization locally."
        case .queued:
            return "Waiting for local transcription to start."
        case .preparingAudio:
            return "Preparing the project audio."
        case .transcribing:
            return "Converting speech into timed text."
        case .diarizing:
            return "Finding and separating speakers."
        case .saving:
            return "Saving the inline transcript."
        }
    }

    private func durationLabel(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func displayTitle(
        _ project: RecordingProjectHistory.Entry
    ) -> String {
        project.displayTitle
    }

    private func selectFirstProjectIfNeeded() {
        vm.projectLibraryNavigation.reconcileSelection(availableProjectIDs: filteredProjects.map(\.id))
    }

    private func loadMetadata() async {
        isLoadingMetadata = true
        defer { isLoadingMetadata = false }
        metadataByProjectID = metadataByProjectID.filter { id, _ in
            vm.recentProjects.contains { $0.id == id }
        }

        let projects = vm.recentProjects.filter {
            metadataByProjectID[$0.id] == nil
        }
        for startIndex in stride(from: 0, to: projects.count, by: 6) {
            guard !Task.isCancelled else { return }
            let endIndex = min(startIndex + 6, projects.count)
            let batch = Array(projects[startIndex..<endIndex])
            await withTaskGroup(
                of: (UUID, ProjectLibraryMetadata).self
            ) { group in
                for project in batch {
                    group.addTask {
                        (
                            project.id,
                            await ProjectLibraryMetadataLoader.load(project)
                        )
                    }
                }
                for await (id, metadata) in group {
                    guard !Task.isCancelled else { return }
                    metadataByProjectID[id] = metadata
                }
            }
        }
    }

    private func loadSelectedTranscript() {
        guard vm.projectLibraryNavigation.selectedDetailTab == .transcript,
              let project = selectedProject,
              case .ready = vm.transcriptionController.status(for: project) else {
            return
        }

        do {
            let recordingProject = try TakeFileStore().loadRecordingProject(
                at: URL(fileURLWithPath: project.projectPath)
            )
            let artifactStore = TranscriptArtifactStore()
            let locations = artifactStore.locations(for: recordingProject)
            transcriptByProjectID[project.id] = try artifactStore.load(
                from: locations.jsonURL
            )
        } catch {
            transcriptByProjectID.removeValue(forKey: project.id)
        }
    }

    private func loadSelectedPlayback() async {
        guard let project = selectedProject else {
            return
        }
        guard ProjectLibraryPlaybackReloadPolicy.shouldReload(.init(
            selectedProjectPath: project.projectPath,
            loadedProjectPath: playbackProjectPath,
            hasActivePlayback: projectPlayback.isReady
        )) else { return }

        playbackProjectID = nil
        playbackProjectPath = nil
        playbackWaveformSamples = []
        projectPlayback.teardown()
        playbackLoadError = nil

        do {
            let recordingProject = try TakeFileStore().loadRecordingProject(
                at: URL(fileURLWithPath: project.projectPath)
            )
            guard !Task.isCancelled else { return }
            await projectPlayback.load(
                project: recordingProject,
                baseSettings: vm.settings
            )
            guard !Task.isCancelled,
                  selectedProject?.id == project.id,
                  projectPlayback.isReady else {
                return
            }
            playbackProjectID = project.id
            playbackProjectPath = project.projectPath

            if let transcript = projectTranscript(recordingProject) {
                playbackWaveformSamples = ProjectSpeechWaveform.samples(.init(
                    segments: transcript.segments,
                    duration: projectPlayback.duration,
                    bucketCount: 240
                ))
                return
            }

            guard let waveformAsset = preferredWaveformAsset(recordingProject) else {
                return
            }
            await projectWaveformLibrary.loadAssets([waveformAsset])
            guard !Task.isCancelled,
                  selectedProject?.id == project.id else {
                return
            }
            playbackWaveformSamples = projectWaveformLibrary.waveforms[waveformAsset.id] ?? []
        } catch {
            guard !Task.isCancelled else { return }
            playbackLoadError = error.localizedDescription
        }
    }

    private func loadSelectedMediaAssets() async {
        guard vm.projectLibraryNavigation.selectedDetailTab == .media,
              let projectEntry = selectedProject else {
            mediaAssets = []
            mediaAssetsProjectID = nil
            isLoadingMediaAssets = false
            return
        }

        let projectID = projectEntry.id
        isLoadingMediaAssets = true
        do {
            let recordingProject = try TakeFileStore().loadRecordingProject(
                at: URL(fileURLWithPath: projectEntry.projectPath)
            )
            var loadedAssets = EditorAsset.assets(
                project: recordingProject,
                finalVideoURL: nil
            ).filter(\.isPlayable)
            var knownPaths = Set(loadedAssets.map { $0.url.standardizedFileURL.path })
            for export in recordingProject.exports.reversed() {
                let url = URL(fileURLWithPath: export.path)
                let path = url.standardizedFileURL.path
                guard !knownPaths.contains(path) else { continue }
                loadedAssets.append(EditorAsset.output(url: url))
                knownPaths.insert(path)
            }
            guard !Task.isCancelled,
                  vm.projectLibraryNavigation.selectedDetailTab == .media,
                  selectedProject?.id == projectID else {
                return
            }
            mediaAssets = loadedAssets
            mediaAssetsProjectID = projectID
            await projectWaveformLibrary.loadAssets(loadedAssets)
            guard !Task.isCancelled,
                  vm.projectLibraryNavigation.selectedDetailTab == .media,
                  selectedProject?.id == projectID else {
                return
            }
            isLoadingMediaAssets = false
        } catch {
            guard selectedProject?.id == projectID else { return }
            mediaAssets = []
            mediaAssetsProjectID = projectID
            isLoadingMediaAssets = false
        }
    }

    private func projectTranscript(
        _ project: RecordingProject
    ) -> RecordingTranscript? {
        let artifactStore = TranscriptArtifactStore()
        let locations = artifactStore.locations(for: project)
        return try? artifactStore.load(from: locations.jsonURL)
    }

    private func preferredWaveformAsset(
        _ project: RecordingProject
    ) -> EditorAsset? {
        let assets = EditorAsset.assets(project: project, finalVideoURL: nil)
        return assets.first { $0.kind == .microphone && $0.isAudio }
            ?? assets.first { $0.kind == .systemAudio && $0.isAudio }
    }

    private var transcriptSearchTaskID: String {
        vm.projectLibraryNavigation.searchText + vm.recentProjects.map {
            "\($0.id)-\($0.updatedAt)-\(vm.transcriptionController.status(for: $0).label)"
        }.joined()
    }

    private func searchTranscripts() async {
        let query = vm.projectLibraryNavigation.searchText
        transcriptMatches = [:]
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            isSearchingTranscripts = false
            return
        }
        isSearchingTranscripts = true
        do {
            try await Task.sleep(for: .milliseconds(180))
            let matches = try await transcriptSearch.search(.init(query: query, projects: vm.recentProjects))
            try Task.checkCancellation()
            transcriptMatches = matches
            isSearchingTranscripts = false
            if let id = vm.projectLibraryNavigation.selectedProjectIDs.first, matches[id] != nil {
                vm.projectLibraryNavigation.selectedDetailTab = .transcript
            }
        } catch {
            if !Task.isCancelled { isSearchingTranscripts = false }
        }
    }

    private var filteredProjects: [RecordingProjectHistory.Entry] {
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

    private var selectedProject: RecordingProjectHistory.Entry? {
        guard vm.projectLibraryNavigation.selectedProjectIDs.count == 1,
              let selectedProjectID = vm.projectLibraryNavigation.selectedProjectIDs.first else {
            return nil
        }
        return filteredProjects.first { $0.id == selectedProjectID }
    }

    private var selectedTranscript: RecordingTranscript? {
        guard let selectedProject else { return nil }
        return transcriptByProjectID[selectedProject.id]
    }

    private var transcriptTaskID: String {
        guard let project = selectedProject else { return "none" }
        let status = vm.transcriptionController.status(for: project)
        return "\(vm.projectLibraryNavigation.selectedDetailTab.title)-\(project.id.uuidString)-\(status.label)"
    }

    private var playbackTaskID: String {
        selectedProject?.projectPath ?? "none"
    }

    private var mediaTaskID: String {
        guard vm.projectLibraryNavigation.selectedDetailTab == .media,
              let selectedProject else {
            return "inactive"
        }
        return selectedProject.projectPath
    }

    private var projectCountLabel: String {
        "\(vm.recentProjects.count) project\(vm.recentProjects.count == 1 ? "" : "s")"
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

    private func projects(
        for selection: Set<UUID>
    ) -> [RecordingProjectHistory.Entry] {
        filteredProjects.filter { selection.contains($0.id) }
    }

    private func queueDeletion(
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

    private func beginRename(
        _ project: RecordingProjectHistory.Entry
    ) {
        projectTitleDraft = project.title
        projectPendingRename = project
    }

}


private struct TranscriptTimestampButton: View {
    let timestamp: String
    let isEnabled: Bool
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(timestamp)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(isActive ? BlitzUI.mint : BlitzUI.secondaryText)
                .frame(width: 52, height: 24, alignment: .leading)
        }
        .buttonStyle(BlitzSelectionButtonStyle(isSelected: false))
        .disabled(!isEnabled)
        .pointingHandCursor(enabled: isEnabled)
        .help("Play from \(timestamp)")
        .accessibilityLabel("Play transcript from \(timestamp)")
    }
}
