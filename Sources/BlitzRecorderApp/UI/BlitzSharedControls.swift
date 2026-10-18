import AppKit
import SwiftUI

@MainActor
enum BlitzClipboard {
    static func copy(_ text: String) async -> Bool {
        for attempt in 0..<3 {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            if pasteboard.setString(text, forType: .string), pasteboard.string(forType: .string) == text {
                return true
            }
            if attempt < 2 {
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        return false
    }

    static func copyInBackground(_ text: String) {
        Task { _ = await copy(text) }
    }
}

enum BlitzCopyFeedback: Equatable {
    case idle
    case copying
    case copied
    case failed

    static let copiedTitle = "Copied"
    static let failedTitle = "Copy failed"

    var symbolName: String {
        switch self {
        case .idle, .copying: "doc.on.doc"
        case .copied: "checkmark"
        case .failed: "exclamationmark.triangle.fill"
        }
    }
}

struct BlitzCopyButton: View {
    enum Width: Equatable {
        case fit
        case fill
        case fixed(CGFloat)
    }

    struct Configuration {
        let text: String
        let title: String
        let accessibilityLabel: String
        let help: String
        let emphasis: BlitzButtonEmphasis
        let width: Width
    }

    let configuration: Configuration
    @State private var feedback = BlitzCopyFeedback.idle
    @State private var generation = 0

    var body: some View {
        Button(action: copy) {
            Label {
                ZStack {
                    Text(configuration.title).hidden()
                    Text(BlitzCopyFeedback.copiedTitle).hidden()
                    Text(title)
                }
            } icon: {
                Image(systemName: feedback.symbolName)
                    .foregroundStyle(feedback == .failed ? AnyShapeStyle(BlitzUI.warning) : AnyShapeStyle(.foreground))
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: fixedWidth, alignment: .center)
            .frame(maxWidth: configuration.width == .fill ? .infinity : nil)
        }
        .blitzButton(configuration.emphasis)
        .disabled(feedback == .copying)
        .accessibilityLabel(feedback == .idle || feedback == .copying ? configuration.accessibilityLabel : title)
        .help(feedback == .failed ? "The clipboard did not accept it. Click to retry." : configuration.help)
        .onChange(of: configuration.text) {
            generation += 1
            feedback = .idle
        }
    }

    private var title: String {
        switch feedback {
        case .idle, .copying: configuration.title
        case .copied: BlitzCopyFeedback.copiedTitle
        case .failed: BlitzCopyFeedback.failedTitle
        }
    }

    private var fixedWidth: CGFloat? {
        if case .fixed(let width) = configuration.width { return width }
        return nil
    }

    private func copy() {
        guard feedback != .copying else { return }
        generation += 1
        let current = generation
        let text = configuration.text
        feedback = .copying
        Task { @MainActor in
            let didCopy = await BlitzClipboard.copy(text)
            guard current == generation else { return }
            feedback = didCopy ? .copied : .failed
            try? await Task.sleep(for: didCopy ? .seconds(2) : .seconds(3))
            guard current == generation else { return }
            feedback = .idle
        }
    }
}

/// Secondary actions shown as labeled quiet buttons, never hidden behind a ⋯ menu.
/// Pair it with `.contextMenu { BlitzContextMenuItems(entries:) }` so right-click offers the same actions.
struct BlitzInlineActions: View {
    let entries: [BlitzMenuEntry]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 2) { buttons }
            VStack(alignment: .leading, spacing: 2) { buttons }
        }
        .blitzButton(.quiet)
    }

    @ViewBuilder private var buttons: some View {
        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
            if case .item(let item) = entry {
                Button(role: item.isDestructive ? .destructive : nil, action: item.action) {
                    if let systemImage = item.systemImage {
                        Label(item.title, systemImage: systemImage)
                    } else {
                        Text(item.title)
                    }
                }
                .disabled(!item.isEnabled)
                .help(item.subtitle ?? item.title)
            }
        }
    }
}

struct BlitzContextMenuItems: View {
    let entries: [BlitzMenuEntry]

    var body: some View {
        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
            switch entry {
            case .item(let item):
                Button(role: item.isDestructive ? .destructive : nil, action: item.action) {
                    if let systemImage = item.systemImage {
                        Label(item.title, systemImage: systemImage)
                    } else {
                        Text(item.title)
                    }
                }
                .disabled(!item.isEnabled)
            case .divider:
                Divider()
            case .section(let title):
                Section(title) {}
            }
        }
    }
}
