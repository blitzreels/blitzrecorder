import AppKit
import SwiftUI

struct HostedVideoShareHistory: View {
    struct Configuration {
        let links: [HostedVideoShareController.ProjectLink]
        /// Shown at the top of the panel already, so not listed again.
        let featuredLink: URL?
        let exports: [RecordingProject.ExportRecord]
        let linksNote: String?
        let canShareFile: Bool
        let shareFile: (URL) -> Void
        let reuseSettings: (RecordingProject.ExportRecord) -> Void
    }

    @Bindable var controller: HostedVideoShareController
    let configuration: Configuration
    @State private var stopping: HostedLibraryVideo?

    private static let rowHeight: CGFloat = 44

    private var listedLinks: [HostedVideoShareController.ProjectLink] {
        configuration.links.filter { $0.url != configuration.featuredLink }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !listedLinks.isEmpty {
                section(title: listedLinks.count == 1 ? "Link" : "Links", note: configuration.linksNote) {
                    ForEach(listedLinks) { linkRow($0) }
                }
            }
            if !configuration.exports.isEmpty {
                section(title: "Saved to this Mac", note: nil) {
                    ForEach(configuration.exports) { exportRow($0) }
                }
            }
        }
        .confirmationDialog("Stop sharing this link?", isPresented: Binding(
            get: { stopping != nil }, set: { if !$0 { stopping = nil } }), presenting: stopping) { video in
            Button("Stop sharing", role: .destructive) { Task { await controller.stopSharing(video) } }
        } message: { video in
            Text(video.isOwnStorage
                 ? "The link stops working and the video is deleted from your Cloudflare. Your recording stays on this Mac."
                 : "The link stops working for everyone. Your recording stays on this Mac.")
        }
    }

    private func section<Rows: View>(title: String, note: String?, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(BlitzType.strong).foregroundStyle(BlitzUI.secondaryText)
            VStack(spacing: 2) { rows() }
            if let note {
                Text(note)
                    .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func linkRow(_ link: HostedVideoShareController.ProjectLink) -> some View {
        let entries = linkEntries(link)
        return row(.init(
            title: HostedVideoLinkField.displayText(link.url),
            detail: ([link.video.statusLabel] + [link.sharedAt.map(Self.dateLabel)].compactMap { $0 })
                .joined(separator: " · "),
            help: link.url.absoluteString,
            isAvailable: true
        )) {
            if controller.changingVideos.contains(link.video.id) {
                ProgressView().controlSize(.small)
            } else {
                BlitzCopyButton(configuration: .watchLink(.init(url: link.url, title: "Copy", emphasis: .quiet, width: .fit)))
                Button { NSWorkspace.shared.open(link.url) } label: { Label("Open", systemImage: BlitzSymbols.openLink) }
                    .blitzButton(.quiet)
                    .help("Open the watch page in your browser")
            }
        }
        .contextMenu { BlitzContextMenuItems(entries: entries) }
    }

    private func linkEntries(_ link: HostedVideoShareController.ProjectLink) -> [BlitzMenuEntry] {
        let listed = link.video.listed != false
        return [
            .item(.init(title: "Copy link", systemImage: BlitzSymbols.copyLink, action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link.url.absoluteString, forType: .string)
            })),
            .item(.init(title: "Open", systemImage: BlitzSymbols.openLink, action: { NSWorkspace.shared.open(link.url) })),
            .divider,
            .item(.init(title: listed ? "Hide link" : "Show link", systemImage: listed ? "eye.slash" : "eye",
                action: { Task { await controller.setListed(.init(video: link.video, listed: !listed)) } })),
            .item(.init(title: "Stop sharing…", systemImage: "xmark.circle", isDestructive: true,
                action: { stopping = link.video })),
        ]
    }

    private func exportRow(_ record: RecordingProject.ExportRecord) -> some View {
        let url = URL(fileURLWithPath: record.path)
        let exists = FileManager.default.fileExists(atPath: record.path)
        let link = configuration.links.first { $0.matches(record) }
        let file = ExportFile(record: record, url: url, exists: exists, link: link)
        let detail = exists ? Self.exportDetail(record) : "Moved or deleted · \(Self.dateLabel(record.createdAt))"
        return row(.init(
            title: Self.exportTitle(record),
            detail: link.map { "\($0.video.statusLabel) · \(detail)" } ?? detail,
            help: link.map { "\(record.path)\n\($0.url.absoluteString)" } ?? record.path,
            isAvailable: exists
        )) {
            BlitzInlineActions(entries: exportEntries(file).filter(\.isInline).map(\.entry))
        }
        .contextMenu { BlitzContextMenuItems(entries: exportEntries(file).map(\.entry)) }
    }

    private struct ExportFile {
        let record: RecordingProject.ExportRecord
        let url: URL
        let exists: Bool
        let link: HostedVideoShareController.ProjectLink?
    }

    private struct ExportEntry {
        let entry: BlitzMenuEntry
        let isInline: Bool
    }

    private func exportEntries(_ file: ExportFile) -> [ExportEntry] {
        let share = BlitzMenuEntry.item(.init(
            title: file.link == nil ? "Share" : "Share again",
            subtitle: file.link == nil ? "Create a link from this file without exporting again"
                : "This file already has a link. Sharing again creates a second one.",
            systemImage: BlitzSymbols.share, isEnabled: file.exists && configuration.canShareFile,
            action: { configuration.shareFile(file.url) }))
        let show = BlitzMenuEntry.item(.init(title: "Show", subtitle: "Show in Finder", systemImage: BlitzSymbols.folder,
            isEnabled: file.exists, action: { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }))
        var entries: [ExportEntry] = [
            .init(entry: .item(.init(title: "Export again with these settings", systemImage: "arrow.clockwise",
                action: { configuration.reuseSettings(file.record) })), isInline: false),
            .init(entry: .divider, isInline: false),
        ]
        if let link = file.link {
            entries.append(.init(entry: .item(.init(title: "Copy link", systemImage: BlitzSymbols.copyLink, action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link.url.absoluteString, forType: .string)
            })), isInline: false))
            entries.append(.init(entry: .item(.init(title: "Open link", systemImage: BlitzSymbols.openLink,
                action: { NSWorkspace.shared.open(link.url) })), isInline: false))
        }
        entries.append(.init(entry: share, isInline: true))
        entries.append(.init(entry: show, isInline: true))
        if let link = file.link {
            entries.append(.init(entry: .divider, isInline: false))
            entries.append(.init(entry: .item(.init(title: "Stop sharing…", systemImage: "xmark.circle",
                isDestructive: true, action: { stopping = link.video })), isInline: false))
        }
        return entries
    }

    private struct Row {
        let title: String
        let detail: String
        let help: String
        let isAvailable: Bool
    }

    private func row<Actions: View>(_ content: Row, @ViewBuilder actions: () -> Actions) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(content.title)
                    .font(BlitzType.label)
                    .foregroundStyle(content.isAvailable ? BlitzUI.primaryText : BlitzUI.secondaryText)
                    .lineLimit(1).truncationMode(.middle)
                Text(content.detail)
                    .font(BlitzType.caption.monospacedDigit())
                    .foregroundStyle(BlitzUI.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(content.help)
            HStack(spacing: 2) { actions() }
                .controlSize(.small)
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .frame(height: Self.rowHeight)
        .background(BlitzUI.quietFill, in: .rect(cornerRadius: BlitzControlMetrics.radius))
    }

    private static func exportTitle(_ record: RecordingProject.ExportRecord) -> String {
        guard let quality = ExportVideoQuality(rawValue: record.quality) else {
            return URL(fileURLWithPath: record.path).lastPathComponent
        }
        return [quality.displayName, record.resolution, "\(record.framesPerSecond) fps"].joined(separator: " · ")
    }

    private static func exportDetail(_ record: RecordingProject.ExportRecord) -> String {
        let size = record.fileSizeBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        return [record.layout.flatMap(CaptureLayout.init(rawValue:)).map(EditorExportLayouts.title),
                size, record.format.uppercased(), dateLabel(record.createdAt)]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private static func dateLabel(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }
}
