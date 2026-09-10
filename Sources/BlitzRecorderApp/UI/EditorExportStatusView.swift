import SwiftUI

enum EditorExportStatus {
    struct Progress {
        let title: String
        let percentage: String
        let detail: String?
        let value: Double

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
        let open: (URL) -> Void
        let reveal: (URL) -> Void
        let retry: () -> Void
        let dismiss: () -> Void
    }

    let configuration: Configuration

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(tone)
                .frame(width: 24)
            detail
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            actions
        }
        .padding(12)
        .frame(maxWidth: 940)
        .background(BlitzUI.controlFill, in: .rect(cornerRadius: BlitzControlMetrics.radius))
        .overlay {
            RoundedRectangle(cornerRadius: BlitzControlMetrics.radius)
                .strokeBorder(BlitzUI.panelStroke, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var symbol: String {
        switch configuration.status {
        case .exporting: "square.and.arrow.up"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle"
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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BlitzUI.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Video exported · \(url.deletingLastPathComponent().lastPathComponent)")
                    .font(.system(size: 11))
                    .foregroundStyle(BlitzUI.secondaryText)
                    .lineLimit(1)
            }
            .help(url.path)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 4) {
                Text("Export failed")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BlitzUI.primaryText)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(BlitzUI.secondaryText)
                    .lineLimit(2)
                    .help(message)
            }
        case .exporting(let progress):
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(progress.title.isEmpty ? "Exporting video" : progress.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(BlitzUI.primaryText)
                    if let detail = progress.supplementaryDetail {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(BlitzUI.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(progress.percentage)
                        .font(.system(size: 11, weight: .medium))
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
            Button { configuration.open(url) } label: {
                Label("Open video", systemImage: "play")
                    .frame(width: 110)
            }
            .blitzButton(.secondary)
            Button { configuration.reveal(url) } label: {
                Label("Show in Finder", systemImage: "folder")
                    .frame(width: 110)
            }
            .blitzButton(.secondary)
            dismissButton
        case .failed:
            Button("Try again", action: configuration.retry)
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
