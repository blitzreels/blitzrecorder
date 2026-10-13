import AppKit
import SwiftUI

extension ProjectLibraryView {
    @ViewBuilder
    var projectDetail: some View {
        if vm.projectLibraryNavigation.selectedProjectIDs.count > 1 {
            bulkSelectionDetail
        } else if let project = selectedProject {
            VStack(spacing: 0) {
                detailHeader(project)
                    .padding(.horizontal, 32)
                    .padding(.top, 22)
                    .padding(.bottom, 6)
                GeometryReader { proxy in
                    if proxy.size.width >= Self.splitDetailWidth {
                        let transcriptWidth = min(440, max(340, proxy.size.width * 0.38))
                        HStack(alignment: .top, spacing: 0) {
                            ScrollView {
                                overviewColumn(project, layout: ProjectLibraryOverviewSizing.layout(.init(
                                    viewportSize: CGSize(width: proxy.size.width - transcriptWidth - 1, height: proxy.size.height)
                                )))
                                .padding(.horizontal, 32)
                                .padding(.vertical, 24)
                            }
                            .scrollIndicators(.hidden)
                            Rectangle().fill(BlitzUI.separator).frame(width: 1)
                            VStack(alignment: .leading, spacing: 0) {
                                transcriptHeader(project)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 16)
                                Rectangle().fill(BlitzUI.separator).frame(height: 1)
                                ScrollView {
                                    transcriptBody(project)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 12)
                                }
                            }
                            .frame(width: transcriptWidth)
                        }
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 28) {
                                overviewColumn(project, layout: ProjectLibraryOverviewSizing.layout(.init(
                                    viewportSize: proxy.size
                                )))
                                VStack(alignment: .leading, spacing: 14) {
                                    transcriptHeader(project)
                                    transcriptBody(project)
                                }
                            }
                            .padding(.horizontal, 32)
                            .padding(.vertical, 24)
                        }
                    }
                }
            }
            .background(alignment: .top) {
                BlitzAmbientGlow(image: metadataByProjectID[project.id]?.thumbnail)
                    .frame(maxWidth: .infinity)
                    .frame(height: 480)
                    .clipped()
                    .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
            }
            .background(BlitzUI.projectLibraryBackground)
            .clipped()
        } else {
            detailEmptyState
        }
    }

    private static let splitDetailWidth: CGFloat = 900

    private func overviewColumn(
        _ project: RecordingProjectHistory.Entry,
        layout: ProjectLibraryOverviewLayout
    ) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            detailPreview(project, overviewLayout: layout)
            detailMetadata(project)
            projectMedia(project)
        }
        .frame(maxWidth: layout.contentWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .top)
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
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 24) {
                detailHeading(project)
                    .frame(minWidth: 340, maxWidth: .infinity, alignment: .leading)
                detailActions(project)
                    .fixedSize()
            }
            VStack(alignment: .leading, spacing: 18) {
                detailHeading(project)
                detailActions(project)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .blitzContextMenu(projectMenu(project.id))
    }

    private func detailHeading(_ project: RecordingProjectHistory.Entry) -> some View {
        let status = vm.transcriptionController.status(for: project)
        let recordedAt = project.recordedAt
        let metadata = metadataByProjectID[project.id] ?? .empty
        let presentation = ProjectTitlePresentation(.init(title: displayTitle(project), known: vm.folderIndex.known))
        let facts = [recordedAt.formatted(date: .abbreviated, time: .shortened), metadata.durationLabel, presentation.context]
            .compactMap { $0 }
        return VStack(alignment: .leading, spacing: 8) {
            Text(presentation.title)
                .font(BlitzType.largeTitle)
                .foregroundStyle(BlitzUI.primaryText)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .onTapGesture(count: 2) { beginRename(project) }
                .help("\(presentation.title)\nDouble-click to rename")

            HStack(spacing: 6) {
                Text(facts.joined(separator: " · "))
                    .foregroundStyle(BlitzUI.secondaryText)
                    .monospacedDigit()
                    .lineLimit(2)
                    .help("Recorded \(recordedAt.formatted(date: .long, time: .shortened))")
                Text("·").foregroundStyle(BlitzUI.tertiaryText)
                if status.isRunning {
                    ProgressView().controlSize(.mini).accessibilityHidden(true)
                }
                Text(transcriptStatusLabel(status))
                    .foregroundStyle(transcriptStatusColor(status) == BlitzUI.warning ? BlitzUI.warning : BlitzUI.secondaryText)
                    .lineLimit(1)
                    .fixedSize()
            }
            .font(BlitzType.body)
            if let url = sharing.sharedURL(forProject: project.projectPath) {
                HostedVideoLinkActions(url: url).controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailActions(_ project: RecordingProjectHistory.Entry) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                editRecordingAction(project)
                detailUtilities(project)
            }
            .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 8) {
                editRecordingAction(project)
                detailUtilities(project)
            }
        }
        .disabled(vm.projectTrash.isWorking)
    }

    private func detailUtilities(_ project: RecordingProjectHistory.Entry) -> some View {
        HStack(spacing: 8) {
            ProjectAIPromptButton(context: .init(
                projectId: project.id,
                title: displayTitle(project),
                recordedAt: project.recordedAt,
                previewDurationSeconds: metadataByProjectID[project.id]?.durationSeconds,
                previewQuality: metadataByProjectID[project.id]?.videoQuality?.label,
                sources: metadataByProjectID[project.id]?.sourceRoles.sorted() ?? []
            ))
            BlitzInlineActions(entries: projectActions(project))
        }
    }

    private func projectActions(_ project: RecordingProjectHistory.Entry) -> [BlitzMenuEntry] {
        var entries: [BlitzMenuEntry] = [
            .item(.init(title: "Rename", subtitle: "Rename this recording (or double-click the title)",
                        systemImage: "square.and.pencil", action: { beginRename(project) }))
        ]
        if let url = sharing.sharedURL(forProject: project.projectPath) {
            entries.append(.item(.init(title: "Copy link", subtitle: "Copy the watch link", systemImage: "link",
                                       action: { BlitzClipboard.copyInBackground(url.absoluteString) })))
        }
        entries.append(.item(.init(title: "Delete", subtitle: "Move to Trash (⌫)", systemImage: "trash",
                                   isDestructive: true, action: { queueDeletion([project]) })))
        return entries
    }

    private func editRecordingAction(_ project: RecordingProjectHistory.Entry) -> some View {
        EditRecordingButton(configuration: .init(
            title: "Edit recording",
            isLoading: openingProjectID == project.id,
            help: "Open this recording in the editor",
            placement: .page,
            action: {
                openingProjectID = project.id
                Task {
                    await Task.yield()
                    vm.openProject(project)
                    openingProjectID = nil
                }
            }
        ))
        .disabled(!vm.canOpenProjectEditor)
    }

    private func detailMetadata(
        _ project: RecordingProjectHistory.Entry
    ) -> some View {
        let metadata = metadataByProjectID[project.id] ?? .empty
        let facts = [metadata.videoQuality?.label, metadata.sourceSummary, metadata.sizeLabel].compactMap { $0 }
        return Text(facts.joined(separator: " · "))
            .font(BlitzType.body)
            .foregroundStyle(BlitzUI.secondaryText)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
            .help(metadata.videoQuality?.detail ?? "No readable video metadata")
    }

    private var detailEmptyState: some View {
        let hasFilters = filteredProjects.isEmpty && vm.projectLibraryNavigation.filters.activeCount > 0
        let configuration: BlitzEmptyState.Configuration
        if vm.recentProjects.isEmpty {
            configuration = .init(
                symbol: "record.circle", title: "No recordings yet",
                detail: vm.projectTrash.canRestore
                    ? "Restore a recording above or start a new one."
                    : "Your first recording will show up here.",
                action: .init(title: "New Recording", run: vm.startNewRecording))
        } else if filteredProjects.isEmpty {
            configuration = .init(
                symbol: "magnifyingglass", title: "No recordings found",
                detail: "Try a different search or clear the filters.",
                action: hasFilters ? .init(title: "Clear filters", run: {
                    vm.projectLibraryNavigation.filters = .init(sort: vm.projectLibraryNavigation.filters.sort)
                }) : nil)
        } else {
            configuration = .init(symbol: "film.stack", title: "Select a recording",
                                  detail: "Choose one from the list to play it.", action: nil)
        }
        return BlitzEmptyState(configuration: configuration)
            .background(BlitzUI.projectLibraryBackground)
    }

}
