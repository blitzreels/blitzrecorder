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
                    .foregroundStyle(feedback == .failed ? BlitzUI.warning : .primary)
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

struct BlitzOverflowMenu: View {
    enum Placement {
        case inline
        case dock
    }

    struct Configuration {
        let entries: [BlitzMenuEntry]
        let menuWidth: CGFloat
        let placement: Placement
        let isBusy: Bool
        let accessibilityLabel: String
        let help: String
    }

    let configuration: Configuration
    @State private var isPresented = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    var body: some View {
        trigger
            .accessibilityLabel(configuration.accessibilityLabel)
            .help(configuration.help)
            .onChange(of: isEnabled) {
                if !isEnabled { isPresented = false }
            }
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                BlitzMenuList(
                    entries: configuration.entries,
                    width: configuration.menuWidth,
                    maxHeight: BlitzMenuList.adaptiveMaxHeight
                ) {
                    isPresented = false
                }
                .preferredColorScheme(.dark)
            }
    }

    @ViewBuilder
    private var trigger: some View {
        switch configuration.placement {
        case .dock:
            Button { isPresented.toggle() } label: {
                glyph.foregroundStyle(BlitzUI.primaryText)
            }
            .blitzButton(.dock)
            .fixedSize()
        case .inline:
            let side = BlitzControlMetrics.height(controlSize)
            Button { isPresented.toggle() } label: {
                glyph
                    .foregroundStyle(BlitzUI.supportingText)
                    .frame(width: side, height: side)
                    .contentShape(.rect)
            }
            .buttonStyle(BlitzMenuTriggerStyle(isPresented: isPresented))
        }
    }

    @ViewBuilder
    private var glyph: some View {
        if configuration.isBusy {
            ProgressView().controlSize(.small)
        } else {
            Image(systemName: "ellipsis").font(BlitzType.glyph(13))
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
