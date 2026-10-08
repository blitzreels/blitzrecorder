import AppKit
import SwiftUI

struct HostedVideoLinkField: View {
    let url: URL
    let prominence: BlitzButtonEmphasis

    static func displayText(_ url: URL) -> String {
        (url.host() ?? "") + url.path()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(Self.displayText(url))
                .font(BlitzType.body)
                .foregroundStyle(BlitzUI.supportingText)
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(url.absoluteString)
            BlitzCopyButton(configuration: .watchLink(.init(url: url, title: "Copy", emphasis: prominence, width: .fit)))
                .controlSize(.small)
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(BlitzUI.quietFill, in: .rect(cornerRadius: BlitzControlMetrics.radius))
    }
}

struct HostedVideoLinkActions: View {
    let url: URL

    var body: some View {
        HStack(spacing: 8) {
            BlitzCopyButton(configuration: .watchLink(.init(url: url, title: "Copy link", emphasis: .secondary, width: .fit)))
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Label("Open video", systemImage: "arrow.up.right")
            }.blitzButton(.quiet)
                .accessibilityLabel("Open shared video")
                .help("Open the shared video in your browser")
        }
    }
}

extension BlitzCopyButton.Configuration {
    struct WatchLinkRequest {
        let url: URL
        let title: String
        let emphasis: BlitzButtonEmphasis
        let width: BlitzCopyButton.Width
    }

    static func watchLink(_ request: WatchLinkRequest) -> Self {
        .init(
            text: request.url.absoluteString,
            title: request.title,
            accessibilityLabel: "Copy link",
            help: "Copy the watch link",
            emphasis: request.emphasis,
            width: request.width
        )
    }
}
