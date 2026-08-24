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

private struct CompactFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = layout(
            proposal: ProposedViewSize(width: bounds.width, height: proposal.height),
            subviews: subviews
        )
        for placement in result.placements {
            subviews[placement.index].place(
                at: CGPoint(
                    x: bounds.minX + placement.origin.x,
                    y: bounds.minY + placement.origin.y
                ),
                proposal: ProposedViewSize(placement.size)
            )
        }
    }

    private func layout(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> Result {
        let availableWidth = proposal.width ?? .infinity
        var placements: [Placement] = []
        var cursor = CGPoint.zero
        var rowHeight: CGFloat = 0
        var measuredWidth: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if cursor.x > 0, cursor.x + size.width > availableWidth {
                cursor.x = 0
                cursor.y += rowHeight + spacing
                rowHeight = 0
            }
            placements.append(Placement(index: index, origin: cursor, size: size))
            cursor.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            measuredWidth = max(measuredWidth, cursor.x - spacing)
        }

        return Result(
            size: CGSize(width: measuredWidth, height: cursor.y + rowHeight),
            placements: placements
        )
    }

    private struct Placement {
        let index: Int
        let origin: CGPoint
        let size: CGSize
    }

    private struct Result {
        let size: CGSize
        let placements: [Placement]
    }
}

enum ProjectLibrarySymbols {
    static let editRecording = "scissors"
    static let media = "film.stack"
}

enum ProjectLibraryDetailTab: CaseIterable {
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

struct StudioSectionTabs: View {
    @Bindable var vm: RecorderViewModel

    private struct TabConfiguration {
        let title: String
        let isSelected: Bool
        let isEnabled: Bool
        let action: () -> Void
    }

    var body: some View {
        HStack(spacing: 2) {
            tab(TabConfiguration(
                title: "Record",
                isSelected: vm.studioMode == .record,
                isEnabled: true,
                action: vm.showRecorder
            ))

            tab(TabConfiguration(
                title: "Projects",
                isSelected: vm.studioMode == .projects,
                isEnabled: vm.canShowProjects,
                action: vm.showProjects
            ))
        }
        .padding(3)
        .background(.white.opacity(0.035), in: .rect(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(.white.opacity(0.055), lineWidth: 1)
        }
    }

    private func tab(_ configuration: TabConfiguration) -> some View {
        Button(action: configuration.action) {
            Text(configuration.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(
                    configuration.isSelected
                        ? .white.opacity(0.94)
                        : .white.opacity(configuration.isEnabled ? 0.48 : 0.22)
                )
                .padding(.horizontal, 18)
                .frame(height: 30)
                .background(
                    configuration.isSelected
                        ? Color.white.opacity(0.095)
                        : Color.clear,
                    in: .rect(cornerRadius: 7)
                )
                .overlay(alignment: .bottom) {
                    if configuration.isSelected {
                        Capsule()
                            .fill(BlitzUI.mint)
                            .frame(width: 18, height: 2)
                            .offset(y: -2)
                    }
                }
                .contentShape(.rect(cornerRadius: 7))
        }
        .buttonStyle(ProjectLibraryPressButtonStyle())
        .disabled(!configuration.isEnabled)
        .help(
            configuration.isEnabled
                ? configuration.title
                : "Record a project to unlock Projects."
        )
        .pointingHandCursor(enabled: configuration.isEnabled)
    }
}

struct ProjectLibraryView: View {
    @Bindable var vm: RecorderViewModel
    @State private var selectedProjectIDs: Set<UUID> = []
    @State private var selectedDetailTab: ProjectLibraryDetailTab = .overview
    @State private var searchText = ""
    @State private var openingProjectID: UUID?
    @State private var projectsPendingDeletion: [RecordingProjectHistory.Entry] = []
    @State private var projectPendingRename: RecordingProjectHistory.Entry?
    @State private var projectTitleDraft = ""
    @State private var titleGenerationProjectID: UUID?
    @State private var metadataByProjectID: [UUID: ProjectLibraryMetadata] = [:]
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

    private struct SidebarDetailRequest {
        let project: RecordingProjectHistory.Entry
        let metadata: ProjectLibraryMetadata
    }

    private struct TranscriptRowRequest {
        let segment: RecordingTranscript.Segment
        let transcript: RecordingTranscript
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
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .background(BlitzUI.projectLibraryBackground)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(.white.opacity(0.08))
                        .frame(height: 1)
                }

            HStack(spacing: 0) {
                projectSidebar

                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 1)

                projectDetail
            }
        }
        .background(BlitzUI.projectLibraryBackground)
        .task {
            vm.refreshRecentProjects()
            selectFirstProjectIfNeeded()
        }
        .task(id: vm.recentProjects.map(\.id)) {
            await loadMetadata()
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
            selectFirstProjectIfNeeded()
        }
        .onChange(of: selectedProjectIDs) {
            selectedDetailTab = .overview
        }
        .onDisappear {
            projectPlayback.teardown()
        }
        .alert(deletionAlertTitle, isPresented: deletionConfirmationBinding) {
            Button("Cancel", role: .cancel) {
                projectsPendingDeletion = []
            }
            Button("Move to Trash", role: .destructive) {
                applySelectionAfterDeletion()
                vm.deleteProjects(projectsPendingDeletion)
                projectsPendingDeletion = []
            }
        } message: {
            Text(deletionAlertMessage)
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
            VStack(alignment: .leading, spacing: 3) {
                Text("Projects")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white.opacity(0.94))
                    .lineLimit(1)

                Text(projectCountLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.38))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            StudioSectionTabs(vm: vm)
                .frame(maxWidth: .infinity)

            HStack {
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

    private var projectSidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                TextField("Search projects", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(.white.opacity(0.055), in: .rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.07), lineWidth: 1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            List(selection: $selectedProjectIDs) {
                Section {
                    ForEach(filteredProjects, id: \.id) { project in
                        sidebarRow(project)
                            .tag(project.id)
                    }
                } header: {
                    Text("Project Library")
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(BlitzUI.projectLibraryBackground)
            .contextMenu(forSelectionType: UUID.self) { selection in
                projectContextMenu(selection)
            } primaryAction: { selection in
                let projects = projects(for: selection)
                if projects.count == 1, let project = projects.first {
                    vm.openProject(project)
                }
            }
        }
        .frame(width: 310)
        .background(BlitzUI.projectLibraryBackground)
    }

    private func sidebarRow(_ project: RecordingProjectHistory.Entry) -> some View {
        let metadata = metadataByProjectID[project.id] ?? .empty
        let isHovering = hoveredSidebarProjectID == project.id
        return HStack(spacing: 10) {
            projectThumbnail(ThumbnailConfiguration(
                metadata: metadata,
                width: 72,
                height: 42,
                cornerRadius: 6,
                showsDuration: false
            ))

            VStack(alignment: .leading, spacing: 3) {
                Text(displayTitle(project))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)

                Text(sidebarDetail(SidebarDetailRequest(
                    project: project,
                    metadata: metadata
                )))
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
        .onContinuousHover { phase in
            switch phase {
            case .active:
                hoveredSidebarProjectID = project.id
                NSCursor.pointingHand.set()
            case .ended:
                if hoveredSidebarProjectID == project.id {
                    hoveredSidebarProjectID = nil
                    NSCursor.arrow.set()
                }
            }
        }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    @ViewBuilder
    private func projectContextMenu(
        _ selection: Set<UUID>
    ) -> some View {
        let projects = projects(for: selection)

        if projects.count == 1, let project = projects.first {
            Button {
                vm.openProject(project)
            } label: {
                Label("Open in Editor", systemImage: ProjectLibrarySymbols.editRecording)
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

    @ViewBuilder
    private var projectDetail: some View {
        if selectedProjectIDs.count > 1 {
            bulkSelectionDetail
        } else if let project = selectedProject {
            VStack(spacing: 0) {
                detailHeader(project)
                    .padding(.horizontal, 34)
                    .padding(.top, 24)
                    .padding(.bottom, 18)

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
                            maxWidth: selectedDetailTab == .transcript
                                ? 720
                                : overviewLayout.contentWidth,
                            alignment: .leading
                        )
                        .frame(maxWidth: .infinity, alignment: .top)
                        .padding(.horizontal, 34)
                        .padding(.vertical, 28)
                    }
                }
            }
            .background(BlitzUI.projectLibraryBackground)
        } else {
            detailEmptyState
        }
    }

    private var projectDetailTabBar: some View {
        HStack(spacing: 4) {
            ForEach(ProjectLibraryDetailTab.allCases, id: \.self) { tab in
                Button {
                    selectedDetailTab = tab
                } label: {
                    Label(tab.title, systemImage: tab.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(
                            selectedDetailTab == tab
                                ? .white.opacity(0.94)
                                : .white.opacity(0.48)
                        )
                        .padding(.horizontal, 14)
                        .frame(minHeight: 40)
                        .contentShape(.rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .background(
                    selectedDetailTab == tab
                        ? BlitzUI.selectedFill
                        : Color.clear,
                    in: .rect(cornerRadius: 8)
                )
                .pointingHandCursor()
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private func selectedProjectDetail(
        _ project: RecordingProjectHistory.Entry,
        overviewLayout: ProjectLibraryOverviewLayout
    ) -> some View {
        switch selectedDetailTab {
        case .overview:
            VStack(alignment: .leading, spacing: 24) {
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
        let projects = projects(for: selectedProjectIDs)
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
                    Label("Move to Trash", systemImage: "trash")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.red.opacity(0.88))
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .background(.red.opacity(0.08), in: .rect(cornerRadius: 11))
                        .overlay {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(.red.opacity(0.15), lineWidth: 1)
                        }
                }
                .buttonStyle(ProjectLibraryPressButtonStyle())
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
            selectedProjectIDs = [project.id]
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
                            .offset(y: isHovering ? 0 : -4)
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
                    .stroke(
                        isHovering
                            ? BlitzUI.mint.opacity(0.38)
                            : .white.opacity(0.065),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: .black.opacity(isHovering ? 0.30 : 0.12),
                radius: isHovering ? 14 : 5,
                y: isHovering ? 7 : 2
            )
            .scaleEffect(isHovering ? 1.012 : 1)
            .contentShape(.rect(cornerRadius: 13))
        }
        .buttonStyle(ProjectLibraryPressButtonStyle())
        .onContinuousHover { phase in
            switch phase {
            case .active:
                hoveredBulkProjectID = project.id
                NSCursor.pointingHand.set()
            case .ended:
                if hoveredBulkProjectID == project.id {
                    hoveredBulkProjectID = nil
                }
                NSCursor.arrow.set()
            }
        }
        .animation(.easeOut(duration: 0.16), value: isHovering)
        .help("View \(displayTitle(project))")
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
            VStack(alignment: .leading, spacing: 8) {
                Text(displayTitle(project))
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text("Recorded \(recordedAt.formatted(date: .long, time: .shortened))")
                    if abs(project.updatedAt.timeIntervalSince(recordedAt)) > 1 {
                        Text("·")
                        Text("Edited \(project.updatedAt.formatted(date: .omitted, time: .shortened))")
                    }
                    Text("·")
                    Text(transcriptStatusLabel(status))
                        .foregroundStyle(transcriptStatusColor(status))
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.48))
            }

            Spacer(minLength: 0)

            detailActions(project)
        }
    }

    private func detailActions(
        _ project: RecordingProjectHistory.Entry
    ) -> some View {
        let isOpening = openingProjectID == project.id
        return HStack(spacing: 8) {
            ProjectLibraryActionButton(configuration: .init(
                title: "Edit recording",
                systemImage: ProjectLibrarySymbols.editRecording,
                tone: .primary,
                isLoading: isOpening,
                action: {
                    openingProjectID = project.id
                    Task {
                        await Task.yield()
                        vm.openProject(project)
                        openingProjectID = nil
                    }
                }
            ))

            ProjectLibraryIconActionButton(configuration: .init(
                title: "View recording media",
                systemImage: ProjectLibrarySymbols.media,
                tone: .secondary,
                action: { selectedDetailTab = .media }
            ))

            ProjectLibraryIconActionButton(configuration: .init(
                title: "Move project to Trash",
                systemImage: "trash",
                tone: .destructive,
                action: { queueDeletion([project]) }
            ))
        }
    }

    @ViewBuilder
    private func inlineTranscript(
        _ project: RecordingProjectHistory.Entry
    ) -> some View {
        let status = vm.transcriptionController.status(for: project)
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Transcript")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))

                Spacer(minLength: 0)

                if let transcript = selectedTranscript {
                    TranscriptCopyButton(.init(
                        markdown: transcript.markdownText(title: displayTitle(project)),
                        appearance: .compact
                    ))

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
                    .buttonStyle(.borderless)
                    .foregroundStyle(BlitzUI.mint)
                    .disabled(titleGenerationProjectID != nil)
                    .help("Generate a title from the transcript using the local AI model")

                    Text(transcriptSummaryLabel(transcript))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.36))
                }
            }

            if let transcript = selectedTranscript {
                if transcript.speakerCount > 1 {
                    speakerLegend(transcript)
                }

                LazyVStack(spacing: 0) {
                    ForEach(transcript.segments) { segment in
                        inlineTranscriptRow(TranscriptRowRequest(
                            segment: segment,
                            transcript: transcript
                        ))

                        if segment.id != transcript.segments.last?.id {
                            Divider()
                                .padding(
                                    .leading,
                                    transcript.speakerCount == 1 ? 66 : 60
                                )
                        }
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

    private func speakerLegend(
        _ transcript: RecordingTranscript
    ) -> some View {
        CompactFlowLayout(spacing: 8) {
            ForEach(Array(transcript.speakers.enumerated()), id: \.element.id) { index, speaker in
                HStack(spacing: 6) {
                    Circle()
                        .fill(TranscriptDetailView.speakerColor(index))
                        .frame(width: 8, height: 8)
                    Text(speaker.displayName)
                        .font(.system(size: 10, weight: .semibold))
                    Text(durationLabel(transcript.speakingDuration(for: speaker.id)))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.34))
                }
                .foregroundStyle(.white.opacity(0.68))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(.white.opacity(0.045), in: .capsule)
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inlineTranscriptRow(
        _ request: TranscriptRowRequest
    ) -> some View {
        let speakerIndex = request.transcript.speakers.firstIndex {
            $0.id == request.segment.speakerID
        } ?? 0
        return HStack(alignment: .top, spacing: 14) {
            TranscriptTimestampButton(
                timestamp: durationLabel(request.segment.startTime),
                isEnabled: playbackProjectID == selectedProject?.id
                    && projectPlayback.isReady,
                action: {
                    projectPlayback.play(from: request.segment.startTime)
                }
            )

            if request.transcript.speakerCount == 1 {
                Text(request.segment.text)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.84))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .padding(.top, 8)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(TranscriptDetailView.speakerColor(speakerIndex))
                            .frame(width: 8, height: 8)
                        Text(request.transcript.speakerName(for: request.segment.speakerID))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.70))
                    }

                    Text(request.segment.text)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, request.transcript.speakerCount == 1 ? 9 : 13)
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
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(.white.opacity(0.055), in: .rect(cornerRadius: 9))
                .pointingHandCursor()
            }
        }
        .padding(14)
        .background(.white.opacity(0.025), in: .rect(cornerRadius: 10))
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
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .background(.white.opacity(0.07), in: .rect(cornerRadius: 9))
                    .pointingHandCursor()
            }
        }
        .padding(16)
        .background(.white.opacity(0.035), in: .rect(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        }
    }

    private func detailMetadata(
        _ project: RecordingProjectHistory.Entry
    ) -> some View {
        let metadata = metadataByProjectID[project.id] ?? .empty
        return VStack(alignment: .leading, spacing: 16) {
            Text("Project details")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))

            HStack(alignment: .top, spacing: 44) {
                metadataBlock(MetadataBlockConfiguration(
                    title: "Duration",
                    value: metadata.durationLabel ?? "—"
                ))
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
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recording media")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))

                Text(mediaCaptureSummary(captureAssets))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.44))
            }

            if isLoadingMediaAssets, mediaAssetsProjectID != project.id {
                ProgressView("Inspecting recorded media…")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.54))
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else if captureAssets.isEmpty {
                Text("No original capture files are available for this recording.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Original captures")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))

                    ForEach(captureAssets) { asset in
                        mediaAssetCard(asset)
                    }
                }
            }

            if !outputAssets.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Finished exports")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))

                    ForEach(outputAssets) { asset in
                        mediaAssetCard(asset)
                    }
                }
            }

            Button("Show all files in Finder") {
                vm.revealProject(project)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.72))
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(.white.opacity(0.055), in: .rect(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
            .pointingHandCursor()
        }
    }

    private func mediaAssetCard(
        _ asset: EditorAsset
    ) -> some View {
        let details = projectWaveformLibrary.technicalMetadata[asset.id]
        let duration = asset.exists
            ? projectWaveformLibrary.durations[asset.id]
                .map(ProjectLibraryMetadata.durationLabel) ?? "Reading duration…"
            : "Unavailable"
        let fileSize = asset.exists
            ? projectWaveformLibrary.fileSizes[asset.id] ?? "Reading size…"
            : "Unavailable"
        let format = asset.exists
            ? details?.format ?? "Reading format…"
            : asset.url.pathExtension.uppercased()
        let quality = asset.exists
            ? details?.quality ?? "Reading quality…"
            : "Capture file unavailable"
        return HStack(spacing: 16) {
            mediaAssetVisual(asset)
                .frame(width: 248, height: 124)
                .background(.black.opacity(0.28), in: .rect(cornerRadius: 9))
                .clipShape(.rect(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(.white.opacity(0.09), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(mediaAssetTitle(asset))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.90))

                    if !asset.exists {
                        Text("Missing")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.red.opacity(0.88))
                    }

                    Spacer(minLength: 0)

                    Text(duration)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.58))
                }

                Text(format)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(BlitzUI.mint.opacity(0.86))

                Text(quality)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Text(fileSize)
                    Text("·")
                    Text(asset.url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 8)

                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([asset.url])
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.68))
                    .pointingHandCursor()
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.36))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.032), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.065), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func mediaAssetVisual(
        _ asset: EditorAsset
    ) -> some View {
        if asset.isVideo {
            let frames = projectWaveformLibrary.filmstrips[asset.id] ?? []
            if frames.isEmpty {
                Text(asset.exists ? "Generating thumbnails…" : "Capture unavailable")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.34))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { proxy in
                    let visibleFrames = Array(frames.prefix(5))
                    HStack(spacing: 1) {
                        ForEach(Array(visibleFrames.enumerated()), id: \.offset) { _, frame in
                            Image(decorative: frame, scale: 1)
                                .resizable()
                                .scaledToFill()
                                .frame(
                                    width: proxy.size.width / CGFloat(visibleFrames.count),
                                    height: proxy.size.height
                                )
                                .clipped()
                        }
                    }
                }
            }
        } else if asset.isAudio {
            mediaWaveform(MediaWaveformRequest(
                values: projectWaveformLibrary.waveforms[asset.id] ?? [],
                tint: asset.tint
            ))
            .padding(.horizontal, 10)
            .padding(.vertical, 14)
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
            Text(filteredProjects.isEmpty ? "No projects found" : "Select a project")
                .font(.system(size: 18, weight: .semibold))
            Text(
                filteredProjects.isEmpty
                    ? "Try a different search."
                    : "Choose a recording from the library."
            )
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BlitzUI.projectLibraryBackground)
    }

    private func projectThumbnail(
        _ configuration: ThumbnailConfiguration
    ) -> some View {
        ZStack(alignment: .bottomTrailing) {
            if let thumbnail = configuration.metadata.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
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

                    Text("No thumbnail")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.30))
                }
            }

            if configuration.showsDuration,
               let durationLabel = configuration.metadata.durationLabel {
                Text(durationLabel)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.94))
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .background(.black.opacity(0.68), in: .capsule)
                    .padding(9)
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

    private func sidebarDetail(_ request: SidebarDetailRequest) -> String {
        var parts = [
            request.project.recordedAt.formatted(date: .abbreviated, time: .omitted)
        ]
        if let durationLabel = request.metadata.durationLabel {
            parts.append(durationLabel)
        }
        return parts.joined(separator: " · ")
    }

    private func selectFirstProjectIfNeeded() {
        guard !filteredProjects.isEmpty else {
            selectedProjectIDs = []
            return
        }
        let validSelection = selectedProjectIDs.intersection(
            Set(filteredProjects.map(\.id))
        )
        if validSelection.isEmpty, let firstProjectID = filteredProjects.first?.id {
            selectedProjectIDs = [firstProjectID]
        } else if validSelection != selectedProjectIDs {
            selectedProjectIDs = validSelection
        }
    }

    private func loadMetadata() async {
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
        guard selectedDetailTab == .transcript,
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
        guard selectedDetailTab == .media,
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
                  selectedDetailTab == .media,
                  selectedProject?.id == projectID else {
                return
            }
            mediaAssets = loadedAssets
            mediaAssetsProjectID = projectID
            await projectWaveformLibrary.loadAssets(loadedAssets)
            guard !Task.isCancelled,
                  selectedDetailTab == .media,
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

    private var filteredProjects: [RecordingProjectHistory.Entry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return vm.recentProjects }
        return vm.recentProjects.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.takeDirectoryPath.localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedProject: RecordingProjectHistory.Entry? {
        guard selectedProjectIDs.count == 1,
              let selectedProjectID = selectedProjectIDs.first else {
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
        return "\(selectedDetailTab.title)-\(project.id.uuidString)-\(status.label)"
    }

    private var playbackTaskID: String {
        selectedProject?.projectPath ?? "none"
    }

    private var mediaTaskID: String {
        guard selectedDetailTab == .media,
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

    private var deletionAlertMessage: String {
        if projectsPendingDeletion.count == 1,
           let project = projectsPendingDeletion.first {
            return "\"\(displayTitle(project))\" and its editable source files will move to Trash. "
                + "Exported videos stay in the output folder."
        }
        return "The selected projects and their editable source files will move to Trash. "
            + "Exported videos stay in the output folder."
    }

    private func projects(
        for selection: Set<UUID>
    ) -> [RecordingProjectHistory.Entry] {
        filteredProjects.filter { selection.contains($0.id) }
    }

    private func queueDeletion(
        _ projects: [RecordingProjectHistory.Entry]
    ) {
        projectsPendingDeletion = projects
    }

    private func applySelectionAfterDeletion() {
        let deletedIDs = Set(projectsPendingDeletion.map(\.id))
        let remaining = filteredProjects.filter { !deletedIDs.contains($0.id) }
        selectedProjectIDs = remaining.first.map { [$0.id] } ?? []
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

private struct ProjectLibraryPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct TranscriptTimestampButton: View {
    let timestamp: String
    let isEnabled: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "play.fill")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(BlitzUI.mint)
                    .opacity(isHovering && isEnabled ? 1 : 0)

                Text(timestamp)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(
                        isHovering && isEnabled
                            ? BlitzUI.mint
                            : .white.opacity(0.38)
                    )
            }
            .frame(width: 52, height: 40, alignment: .leading)
            .background(
                isHovering && isEnabled
                    ? BlitzUI.mint.opacity(0.08)
                    : .clear,
                in: .rect(cornerRadius: 8)
            )
            .contentShape(.rect)
        }
        .buttonStyle(ProjectLibraryPressButtonStyle())
        .disabled(!isEnabled)
        .onHover { isHovering = $0 }
        .pointingHandCursor()
        .help("Play from \(timestamp)")
        .accessibilityLabel("Play transcript from \(timestamp)")
    }
}
