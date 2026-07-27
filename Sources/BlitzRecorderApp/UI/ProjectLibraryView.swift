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

    private struct FileLocationRequest {
        let systemImage: String
        let title: String
        let detail: String
        let path: String
    }

    var body: some View {
        VStack(spacing: 0) {
            commandBar
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .background(.bar)
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
    }

    private func sidebarRow(_ project: RecordingProjectHistory.Entry) -> some View {
        let metadata = metadataByProjectID[project.id] ?? .empty
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
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
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

                ScrollView {
                    selectedProjectDetail(project)
                        .frame(maxWidth: 720, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .top)
                        .padding(.horizontal, 34)
                        .padding(.vertical, 28)
                }
            }
            .background(BlitzUI.canvasBackground)
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
        _ project: RecordingProjectHistory.Entry
    ) -> some View {
        switch selectedDetailTab {
        case .overview:
            VStack(alignment: .leading, spacing: 24) {
                detailPreview(project)
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
        return VStack(spacing: 18) {
            Image(systemName: "rectangle.stack.badge.checkmark")
                .font(.system(size: 32, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(BlitzUI.mint)
                .frame(width: 64, height: 64)
                .background(BlitzUI.mint.opacity(0.10), in: .circle)

            VStack(spacing: 6) {
                Text("\(projects.count) projects selected")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white.opacity(0.94))

                Text("Command-click to add or remove projects. Shift-click selects a range.")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.46))
            }

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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BlitzUI.canvasBackground)
    }

    private func detailPreview(
        _ project: RecordingProjectHistory.Entry
    ) -> some View {
        let metadata = metadataByProjectID[project.id] ?? .empty
        return HStack(spacing: 0) {
            Spacer(minLength: 0)
            ProjectLibraryPlayerSurface(
                controller: projectPlayback,
                isCurrentProject: playbackProjectID == project.id,
                fallbackThumbnail: metadata.thumbnail,
                waveformSamples: playbackWaveformSamples,
                loadError: playbackLoadError ?? projectPlayback.loadError
            )
            Spacer(minLength: 0)
        }
    }

    private func detailHeader(
        _ project: RecordingProjectHistory.Entry
    ) -> some View {
        let status = vm.transcriptionController.status(for: project)
        return HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(displayTitle(project))
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(project.updatedAt.formatted(date: .long, time: .shortened))
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

    private func transcriptUnavailableState(
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

    private func projectMedia(
        _ project: RecordingProjectHistory.Entry
    ) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recording media")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))

                Text("Original captures, edit data, and finished exports for this recording.")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.44))
            }

            fileLocation(FileLocationRequest(
                systemImage: "tray.full",
                title: "Original captures",
                detail: "Screen, camera, microphone, and system audio recorded for this take.",
                path: project.takeDirectoryPath
            ))
            fileLocation(FileLocationRequest(
                systemImage: "doc.text",
                title: "Edit project",
                detail: "Scene layout, timing, and editing settings used by BlitzRecorder.",
                path: project.projectPath
            ))

            if let finalVideoPath = project.finalVideoPath {
                fileLocation(FileLocationRequest(
                    systemImage: "film",
                    title: "Exported video",
                    detail: "Finished video ready to play, share, or publish.",
                    path: finalVideoPath
                ))
            }

            ProjectLibraryActionButton(configuration: .init(
                title: "Open media folder",
                systemImage: "folder",
                tone: .secondary,
                isLoading: false,
                action: { vm.revealProject(project) }
            ))
        }
    }

    private func fileLocation(
        _ request: FileLocationRequest
    ) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: request.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(BlitzUI.mint)
                .frame(width: 40, height: 40)
                .background(BlitzUI.mint.opacity(0.09), in: .rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(request.title)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.86))

                    Spacer(minLength: 0)

                    Text(URL(fileURLWithPath: request.path).lastPathComponent)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.44))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Text(request.detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.50))
                    .fixedSize(horizontal: false, vertical: true)

                Text(request.path)
                    .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.28))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.035), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.065), lineWidth: 1)
        }
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
        .background(BlitzUI.canvasBackground)
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
            vm.transcriptionController.downloadModels()
        case .queued, .preparingAudio, .transcribing, .diarizing, .saving:
            break
        }
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
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let prefix = String(project.title.prefix(19))
        if formatter.date(from: prefix) != nil {
            return "Recording at \(project.updatedAt.formatted(date: .omitted, time: .shortened))"
        }
        return project.title
    }

    private func sidebarDetail(_ request: SidebarDetailRequest) -> String {
        var parts = [
            request.project.updatedAt.formatted(date: .abbreviated, time: .omitted)
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
