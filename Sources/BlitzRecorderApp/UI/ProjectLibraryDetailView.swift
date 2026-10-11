import AppKit
import SwiftUI

extension ProjectLibraryView {
    private struct MetadataBlockConfiguration {
        let title: String
        let value: String
    }

    @ViewBuilder
    var projectDetail: some View {
        if vm.projectLibraryNavigation.selectedProjectIDs.count > 1 {
            bulkSelectionDetail
        } else if let project = selectedProject {
            VStack(spacing: 0) {
                detailHeader(project)
                    .padding(.horizontal, 32)
                    .padding(.top, 22)
                    .padding(.bottom, 18)
                Rectangle().fill(BlitzUI.separator).frame(height: 1)
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
            .background(BlitzUI.projectLibraryBackground)
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
        .contextMenu { projectContextMenu([project.id]) }
    }

    private func detailHeading(_ project: RecordingProjectHistory.Entry) -> some View {
        let status = vm.transcriptionController.status(for: project)
        let recordedAt = project.recordedAt
        let metadata = metadataByProjectID[project.id] ?? .empty
        let presentation = ProjectTitlePresentation(.init(title: displayTitle(project), known: vm.folderIndex.known))
        return VStack(alignment: .leading, spacing: 8) {
            if let context = presentation.context {
                Text(context)
                    .font(BlitzType.captionEmphasis)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .lineLimit(1)
            }
            Text(presentation.title)
                .font(BlitzType.largeTitle)
                .foregroundStyle(BlitzUI.primaryText)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .onTapGesture(count: 2) { beginRename(project) }
                .help("\(presentation.title)\nDouble-click to rename")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Text(recordedAt.formatted(date: .abbreviated, time: .shortened))
                    if let duration = metadata.durationLabel {
                        Text("·")
                        Text(duration).monospacedDigit()
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 4) {
                    Text(recordedAt.formatted(date: .abbreviated, time: .shortened))
                    if let duration = metadata.durationLabel { Text(duration).monospacedDigit() }
                }
            }
            .font(BlitzType.body)
            .foregroundStyle(BlitzUI.secondaryText)
            .help("Recorded \(recordedAt.formatted(date: .long, time: .shortened))")

            HStack(spacing: 6) {
                if status.isRunning {
                    ProgressView().controlSize(.mini)
                        .accessibilityHidden(true)
                        .fixedSize()
                }
                Text(transcriptStatusLabel(status))
                    .lineLimit(1)
                    .foregroundStyle(transcriptStatusColor(status))
            }
            .font(BlitzType.body)
            .accessibilityElement(children: .combine)
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
            BlitzOverflowMenu(configuration: .init(
                entries: projectMenuEntries(project),
                menuWidth: 220,
                placement: .dock,
                isBusy: false,
                accessibilityLabel: "More actions",
                help: "Rename, show in Finder, or move to Trash"
            ))
        }
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

    private func projectMenuEntries(_ project: RecordingProjectHistory.Entry) -> [BlitzMenuEntry] {
        var entries: [BlitzMenuEntry] = [
            .item(.init(title: "Rename", systemImage: "pencil", action: { beginRename(project) })),
            .item(.init(title: "Show in Finder", systemImage: "folder.fill", action: { vm.revealProject(project) }))
        ]
        if let url = sharing.sharedURL(forProject: project.projectPath) {
            entries.append(.item(.init(title: "Copy watch link", systemImage: "doc.on.doc.fill", action: {
                BlitzClipboard.copyInBackground(url.absoluteString)
            })))
        }
        entries += [
            .divider,
            .item(.init(title: "Move to Trash", systemImage: "trash.fill", isDestructive: true,
                        action: { queueDeletion([project]) }))
        ]
        return entries
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
                .font(BlitzType.caption)
                .foregroundStyle(BlitzUI.secondaryText)
            Text(configuration.value)
                .font(BlitzType.strong)
                .foregroundStyle(BlitzUI.primaryText)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailEmptyState: some View {
        VStack(spacing: 8) {
            Text(vm.recentProjects.isEmpty ? "No projects yet" : (filteredProjects.isEmpty ? "No projects found" : "Select a project"))
                .font(BlitzType.title)
            Text(
                vm.recentProjects.isEmpty
                    ? (vm.projectTrash.canRestore ? "Restore a project above or start a new recording." : "Start a new recording to create your first project.")
                    : (filteredProjects.isEmpty ? "Try a different search or clear the filters." : "Choose a recording from the library.")
            )
            .font(BlitzType.body)
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
}
