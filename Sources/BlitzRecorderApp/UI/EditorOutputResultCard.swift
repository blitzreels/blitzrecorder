import AppKit
import SwiftUI

/// What the editor just finished making, shown on the canvas until dismissed so the result and its place on
/// disk or on the web are never missed.
enum EditorOutputResult: Hashable {
    case exported(files: [URL])
    case exportFailed(String)
    case shared(link: URL, file: URL?)
    case shareFailed(String)
}

struct EditorOutputResultCard: View {
    struct Configuration {
        let result: EditorOutputResult
        let canShare: Bool
        let share: (URL) -> Void
        let sendToBlitzReels: (URL) -> Void
        let showSharing: () -> Void
        let dismiss: () -> Void
    }

    let configuration: Configuration
    @State private var metadata = RecordingFileMetadata.empty
    @State private var copyFeedback = BlitzCopyFeedback.idle

    private var file: URL? {
        switch configuration.result {
        case .exported(let files): files.first
        case .shared(_, let file): file
        case .exportFailed, .shareFailed: nil
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if let file {
                RecordingThumbnailButton(image: metadata.thumbnail, durationLabel: metadata.durationLabel, height: 72,
                                         help: "Play \(file.lastPathComponent)\nDrag to drop the video into another app") {
                    NSWorkspace.shared.open(file)
                }
                .onDrag { NSItemProvider(contentsOf: file) ?? NSItemProvider() }
                .accessibilityLabel("Play exported video")
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(BlitzType.symbol(20))
                    .foregroundStyle(BlitzUI.warning)
                    .frame(width: 40)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(BlitzType.headline)
                    .foregroundStyle(BlitzUI.primaryText)
                ForEach(details, id: \.self) { line in
                    Text(line)
                        .font(BlitzType.caption)
                        .foregroundStyle(BlitzUI.secondaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                actions
                    .padding(.top, 4)
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: configuration.dismiss) { Image(systemName: "xmark") }
                .blitzButton(.quiet)
                .accessibilityLabel("Dismiss")
                .help("Dismiss")
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .fixedSize(horizontal: false, vertical: true)
        .editorNoticeSurface()
        .accessibilityElement(children: .contain)
        .task(id: file) {
            metadata = .empty
            guard let file else { return }
            metadata = await RecordingFileMetadata.load(for: file)
        }
    }

    private var title: String {
        switch configuration.result {
        case .exported(let files): files.count > 1 ? "Exported \(files.count) videos" : "Video exported"
        case .exportFailed: "Export failed"
        case .shared: copyFeedback == .failed ? "Link ready" : "Link ready and copied"
        case .shareFailed: "Upload stopped"
        }
    }

    private var details: [String] {
        switch configuration.result {
        case .exported(let files):
            guard let file = files.first else { return [] }
            let name = files.count > 1 ? files.map(\.lastPathComponent).joined(separator: ", ") : file.lastPathComponent
            return [[name, metadata.sizeLabel].compactMap { $0 }.joined(separator: " · "),
                    "In " + Self.folderLabel(file.deletingLastPathComponent())]
        case .exportFailed(let message), .shareFailed(let message):
            return [message]
        case .shared(let link, _):
            return [Self.linkLabel(link), "Anyone with the link can watch"]
        }
    }

    @ViewBuilder private var actions: some View {
        switch configuration.result {
        case .exported(let files):
            HStack(spacing: 6) {
                Button("Show in Finder", systemImage: BlitzSymbols.folder) {
                    NSWorkspace.shared.activateFileViewerSelecting(files)
                }
                .blitzButton(.secondary)
                if let file = files.first {
                    BlitzInlineActions(entries: exportedEntries(file))
                }
            }
        case .shared(let link, _):
            HStack(spacing: 6) {
                Button("Copy link", systemImage: BlitzSymbols.copyLink) { copy(link) }
                    .blitzButton(.secondary)
                BlitzInlineActions(entries: [
                    .item(.init(title: "Open link", systemImage: BlitzSymbols.openLink) { NSWorkspace.shared.open(link) }),
                    .item(.init(title: "Manage sharing", systemImage: BlitzSymbols.share, action: configuration.showSharing))
                ])
            }
        case .shareFailed:
            Button("View upload", systemImage: BlitzSymbols.share, action: configuration.showSharing)
                .blitzButton(.secondary)
        case .exportFailed:
            EmptyView()
        }
    }

    private func exportedEntries(_ file: URL) -> [BlitzMenuEntry] {
        var entries: [BlitzMenuEntry] = []
        if configuration.canShare {
            entries.append(.item(.init(title: "Share link", systemImage: BlitzSymbols.share) { configuration.share(file) }))
        }
        entries.append(.item(.init(title: "Send to BlitzReels", systemImage: "paperplane") { configuration.sendToBlitzReels(file) }))
        return entries
    }

    private func copy(_ link: URL) {
        copyFeedback = .copying
        Task { copyFeedback = await BlitzClipboard.copy(link.absoluteString) ? .copied : .failed }
    }

    private static func folderLabel(_ folder: URL) -> String {
        let path = folder.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    private static func linkLabel(_ link: URL) -> String {
        (link.host() ?? "") + link.path()
    }
}
