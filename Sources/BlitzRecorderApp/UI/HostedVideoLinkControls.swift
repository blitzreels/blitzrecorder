import AppKit
import SwiftUI

struct HostedVideoLinkField: View {
    let url: URL
    let prominence: BlitzButtonEmphasis
    @State private var copied = false

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
            Button {
                copied = copyLink(url)
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc.fill")
                    .frame(minWidth: 64)
            }
            .blitzButton(prominence)
            .controlSize(.small)
            .accessibilityLabel(copied ? "Link copied" : "Copy link")
            .help("Copy the watch link")
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(BlitzUI.quietFill, in: .rect(cornerRadius: BlitzControlMetrics.radius))
        .resetsCopiedState($copied, for: url)
    }
}

struct HostedVideoCopyLinkButton: View {
    let url: URL
    @State private var copied = false

    var body: some View {
        Button {
            copied = copyLink(url)
        } label: {
            Label(copied ? "Link copied" : "Copy link", systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc.fill")
                .frame(maxWidth: .infinity)
        }
        .blitzButton(.accent)
        .controlSize(.large)
        .help("Copy the watch link")
        .resetsCopiedState($copied, for: url)
    }
}

struct HostedVideoLinkActions: View {
    let url: URL
    @State private var copied = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                copied = copyLink(url)
            } label: {
                Label(copied ? "Copied" : "Copy link", systemImage: copied ? "checkmark" : "link")
            }.blitzButton(.secondary)
                .accessibilityLabel(copied ? "Link copied" : "Copy link")
                .help("Copy the watch link")
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Label("Open video", systemImage: "arrow.up.right")
            }.blitzButton(.quiet)
                .accessibilityLabel("Open shared video")
                .help("Open the shared video in your browser")
        }
        .resetsCopiedState($copied, for: url)
    }
}

struct HostedVideoCopyButton: View {
    let url: URL
    @State private var copied = false

    var body: some View {
        Button {
            copied = copyLink(url)
        } label: {
            Label(copied ? "Copied" : "Copy link", systemImage: copied ? "checkmark" : "doc.on.doc")
                .frame(width: 84)
        }
        .blitzButton(.secondary)
        .accessibilityLabel(copied ? "Link copied" : "Copy link")
        .help("Copy the watch link")
        .resetsCopiedState($copied, for: url)
    }
}

private func copyLink(_ url: URL) -> Bool {
    NSPasteboard.general.clearContents()
    return NSPasteboard.general.setString(url.absoluteString, forType: .string)
}

private extension View {
    func resetsCopiedState(_ copied: Binding<Bool>, for url: URL) -> some View {
        onChange(of: url) { copied.wrappedValue = false }
            .task(id: copied.wrappedValue) {
                guard copied.wrappedValue else { return }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                copied.wrappedValue = false
            }
    }
}
