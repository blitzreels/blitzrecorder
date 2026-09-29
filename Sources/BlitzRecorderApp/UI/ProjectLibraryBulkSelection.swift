import SwiftUI

extension ProjectLibraryView {
    var bulkSelectionDetail: some View {
        let projects = projects(for: vm.projectLibraryNavigation.selectedProjectIDs)
        let summary = ProjectLibrarySelectionSummary(
            projects.map { metadataByProjectID[$0.id] ?? .empty }
        )
        return VStack(spacing: 18) {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(projects.count) projects selected")
                        .font(BlitzType.largeTitle)
                        .foregroundStyle(BlitzUI.primaryText)

                    Text("Choose a project below to view its details.")
                        .font(BlitzType.captionEmphasis)
                        .foregroundStyle(BlitzUI.tertiaryText)
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
                .font(BlitzType.glyph(13))
                .foregroundStyle(BlitzUI.mint)

            VStack(alignment: .leading, spacing: 2) {
                Text(configuration.title)
                    .font(BlitzType.footnote)
                    .foregroundStyle(BlitzUI.tertiaryText)
                Text(configuration.value)
                    .font(BlitzType.section)
                    .foregroundStyle(BlitzUI.supportingText)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 14)
        .frame(minWidth: 138, minHeight: 52, alignment: .leading)
        .background(BlitzUI.cardFill, in: .rect(cornerRadius: BlitzUI.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: BlitzUI.cardRadius, style: .continuous)
                .stroke(BlitzUI.separator, lineWidth: 1)
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
                            cornerRadius: BlitzUI.cardRadius,
                            showsDuration: true
                        ))

                        Label("View project", systemImage: "arrow.up.right")
                            .font(BlitzType.footnote)
                            .foregroundStyle(BlitzUI.primaryText)
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
                        .font(BlitzType.headline)
                        .foregroundStyle(isHovering ? BlitzUI.primaryText : BlitzUI.supportingText)
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
                    .font(BlitzType.footnote)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .lineLimit(1)

                    Text(project.recordedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(BlitzType.footnote)
                        .foregroundStyle(BlitzUI.tertiaryText)
                        .lineLimit(1)
                }
                .padding(13)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isHovering ? BlitzUI.hoverFill : BlitzUI.cardFill,
                in: .rect(cornerRadius: BlitzUI.cardRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: BlitzUI.cardRadius, style: .continuous)
                    .strokeBorder(
                        isHovering
                            ? BlitzUI.strongStroke
                            : BlitzUI.separator,
                        lineWidth: 1
                    )
            }
            .contentShape(.rect(cornerRadius: BlitzUI.cardRadius))
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

    private func projectThumbnail(
        _ configuration: ProjectLibraryThumbnail.Configuration
    ) -> ProjectLibraryThumbnail {
        ProjectLibraryThumbnail(configuration: configuration)
    }
}
