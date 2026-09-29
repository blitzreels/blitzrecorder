import SwiftUI

enum EditorExportStatus {
    struct Progress {
        let title: String
        let percentage: String
        let detail: String?
        let value: Double?

        var supplementaryDetail: String? {
            guard let detail else { return nil }
            let ignored = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
            let normalizedTitle = title.trimmingCharacters(in: ignored)
            let normalizedDetail = detail.trimmingCharacters(in: ignored)
            guard !normalizedDetail.isEmpty,
                  normalizedDetail.localizedCaseInsensitiveCompare(normalizedTitle) != .orderedSame else {
                return nil
            }
            return detail
        }
    }

    case exporting(Progress)
    case succeeded(URL)
    case failed(String)
}

struct EditorExportStatusView: View {
    struct Configuration {
        let status: EditorExportStatus
        let savedCount: Int
        let open: (URL) -> Void
        let reveal: (URL) -> Void
        let share: (URL) -> Void
        let sendToBlitzReels: (URL) -> Void
        let retry: () -> Void
        let dismiss: () -> Void
    }

    let configuration: Configuration

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(BlitzType.glyph(18))
                .foregroundStyle(tone)
                .frame(width: 24)
            detail
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            HStack(spacing: 8) { actions }
                .fixedSize(horizontal: true, vertical: false)
        }
        .editorNoticeSurface()
    }

    private var symbol: String {
        switch configuration.status {
        case .exporting: "square.and.arrow.down"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var tone: Color {
        switch configuration.status {
        case .exporting: BlitzUI.secondaryText
        case .succeeded: BlitzUI.mint
        case .failed: BlitzUI.warning
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch configuration.status {
        case .succeeded(let url):
            VStack(alignment: .leading, spacing: 4) {
                Text(url.lastPathComponent)
                    .font(BlitzType.strong)
                    .foregroundStyle(BlitzUI.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(configuration.savedCount > 1 ? "\(configuration.savedCount) videos saved" : "Saved") to \(url.deletingLastPathComponent().lastPathComponent)")
                    .font(BlitzType.caption)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .lineLimit(1)
            }
            .help(url.path)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 4) {
                Text("Export failed")
                    .font(BlitzType.strong)
                    .foregroundStyle(BlitzUI.primaryText)
                Text(message)
                    .font(BlitzType.caption)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .lineLimit(2)
                    .help(message)
            }
        case .exporting(let progress):
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(progress.title.isEmpty ? "Exporting video" : progress.title)
                        .font(BlitzType.label)
                        .foregroundStyle(BlitzUI.primaryText)
                    if let detail = progress.supplementaryDetail {
                        Text(detail)
                            .font(BlitzType.caption)
                            .foregroundStyle(BlitzUI.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(progress.percentage)
                        .font(BlitzType.captionEmphasis)
                        .monospacedDigit()
                        .foregroundStyle(BlitzUI.secondaryText)
                }
                ProgressView(value: progress.value)
                    .progressViewStyle(.linear)
                    .tint(BlitzUI.mint)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch configuration.status {
        case .succeeded(let url):
            Button { configuration.share(url) } label: {
                Label("Get link", systemImage: "link")
            }
            .blitzButton(.secondary)
            .help("Upload this export to BlitzRecorder hosting and get a watch link")
            if url.pathExtension.lowercased() == "mp4" {
                Button { configuration.sendToBlitzReels(url) } label: {
                    Label("Add captions", systemImage: "captions.bubble")
                }
                .blitzButton(.secondary)
                .accessibilityLabel("Add captions in BlitzReels")
                .help("Send this MP4 to BlitzReels for captions and optional B-roll")
            }
            Rectangle().fill(BlitzUI.separator).frame(width: 1, height: 20)
                .accessibilityHidden(true)
            Button { configuration.open(url) } label: {
                Label("Play", systemImage: "play.fill")
                    .labelStyle(.iconOnly)
            }
            .blitzButton(.quiet)
            .help("Play the exported video")
            Button { configuration.reveal(url) } label: {
                Label("Show in Finder", systemImage: "folder")
                    .labelStyle(.iconOnly)
            }
            .blitzButton(.quiet)
            .help(configuration.savedCount > 1 ? "Show all exported videos in Finder" : "Show in Finder")
            ShareLink(item: url) {
                Label("Send file", systemImage: "square.and.arrow.up")
                    .labelStyle(.iconOnly)
            }
            .blitzButton(.quiet)
            .help("Send the file with AirDrop, Mail, Messages and more")
            dismissButton
        case .failed:
            Button(action: configuration.retry) { Label("Try again", systemImage: "arrow.clockwise") }
                .blitzButton(.secondary)
            dismissButton
        case .exporting:
            EmptyView()
        }
    }

    private var dismissButton: some View {
        Button(action: configuration.dismiss) {
            Image(systemName: "xmark")
                .frame(width: 14, height: 14)
        }
        .blitzButton(.quiet)
        .accessibilityLabel("Dismiss export status")
        .help("Dismiss export status")
    }
}

extension View {
    func editorNoticeSurface() -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: 720)
            .background(.regularMaterial, in: .rect(cornerRadius: BlitzUI.cardRadius))
            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
            .environment(\.colorScheme, .dark)
    }
}
