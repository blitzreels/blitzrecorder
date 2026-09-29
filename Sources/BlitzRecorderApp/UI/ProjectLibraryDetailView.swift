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
        let status = vm.transcriptionController.status(for: project)
        let recordedAt = project.recordedAt
        let metadata = metadataByProjectID[project.id] ?? .empty
        return HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(displayTitle(project))
                    .font(BlitzType.largeTitle)
                    .foregroundStyle(BlitzUI.primaryText)
                    .lineLimit(2)
                    .onTapGesture(count: 2) { beginRename(project) }
                    .help("Double-click to rename")

                HStack(spacing: 8) {
                    Text(recordedAt.formatted(date: .abbreviated, time: .shortened))
                        .help("Recorded \(recordedAt.formatted(date: .long, time: .shortened))")
                    if let duration = metadata.durationLabel {
                        Text("·")
                        Text(duration).monospacedDigit()
                    }
                    Text("·")
                    if status.isRunning {
                        ProgressView().controlSize(.mini)
                            .accessibilityLabel(status.label)
                    }
                    Text(transcriptStatusLabel(status))
                        .foregroundStyle(transcriptStatusColor(status))
                }
                .font(BlitzType.body)
                .foregroundStyle(BlitzUI.secondaryText)
                if let url = sharing.sharedURL(forProject: project.projectPath) {
                    HostedVideoLinkActions(url: url).controlSize(.small)
                }
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
        return HStack(spacing: 8) {
            BlitzGlassMenu(entries: projectMenuEntries(project), menuWidth: 220) {
                Image(systemName: "ellipsis")
                    .font(BlitzType.glyph(14))
                    .foregroundStyle(BlitzUI.primaryText)
                    .frame(width: 36, height: BlitzControlMetrics.height(.large))
            }
            .accessibilityLabel("More actions")
            .help("Rename, show in Finder, or move to Trash")

            EditRecordingButton(configuration: .init(
                title: "Edit recording",
                isLoading: isOpening,
                help: vm.state == .idle ? "Open this recording in the editor" : "Finish recording before editing a project",
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
            .disabled(vm.state != .idle)
        }
        .disabled(vm.projectTrash.isWorking)
    }

    private func projectMenuEntries(_ project: RecordingProjectHistory.Entry) -> [BlitzMenuEntry] {
        var entries: [BlitzMenuEntry] = [
            .item(.init(title: "Rename", systemImage: "pencil", action: { beginRename(project) })),
            .item(.init(title: "Show in Finder", systemImage: "folder.fill", action: { vm.revealProject(project) }))
        ]
        if let url = sharing.sharedURL(forProject: project.projectPath) {
            entries.append(.item(.init(title: "Copy watch link", systemImage: "doc.on.doc.fill", action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
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
