import AppKit
import SwiftUI

enum TranscriptCopyButtonAppearance {
    case compact
    case regular
}

enum TranscriptCopyFeedback: Equatable {
    case idle
    case copying
    case copied
    case failed

    var title: String {
        switch self {
        case .idle: return "Copy Markdown"
        case .copying: return "Copying…"
        case .copied: return "Copied"
        case .failed: return "Copy failed"
        }
    }

    var systemImage: String {
        switch self {
        case .idle: return "doc.on.doc"
        case .copying: return "arrow.trianglehead.2.clockwise.rotate.90"
        case .copied: return "checkmark"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    var help: String {
        switch self {
        case .idle: return "Copy the full transcript with headings, speakers, and timestamps"
        case .copying: return "Copying the transcript to the clipboard"
        case .copied: return "Transcript copied to the clipboard"
        case .failed: return "The clipboard did not accept the transcript. Click to retry."
        }
    }
}

@MainActor
enum TranscriptClipboardWriter {
    static func copy(markdown: String) async -> Bool {
        for attempt in 0..<3 {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            let didWrite = pasteboard.setString(markdown, forType: .string)
            if didWrite && pasteboard.string(forType: .string) == markdown {
                return true
            }
            if attempt < 2 {
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        return false
    }
}

struct TranscriptCopyButtonRequest {
    let markdown: String
    let appearance: TranscriptCopyButtonAppearance
}

struct TranscriptCopyButton: View {
    let request: TranscriptCopyButtonRequest
    @State private var feedback = TranscriptCopyFeedback.idle
    @State private var feedbackGeneration = 0

    init(_ request: TranscriptCopyButtonRequest) {
        self.request = request
    }

    var body: some View {
        Button(action: copy) {
            HStack(spacing: 6) {
                BlitzSymbol(configuration: .init(name: feedback.systemImage, size: 16))
                Text(feedback == .idle ? "Copy" : feedback.title)
            }
            .foregroundStyle(foregroundColor)
        }
        .buttonStyle(BlitzControlButtonStyle(isProminent: false))
        .disabled(feedback == .copying)
        .pointingHandCursor(enabled: feedback != .copying)
        .help(feedback.help)
        .accessibilityLabel(feedback == .idle ? "Copy transcript" : feedback.title)
    }

    private var foregroundColor: Color {
        switch feedback {
        case .copied: return BlitzUI.mint
        case .failed: return .red
        case .idle, .copying:
            switch request.appearance {
            case .compact: return .white.opacity(0.82)
            case .regular: return .primary
            }
        }
    }

    private func copy() {
        guard feedback != .copying else { return }
        feedbackGeneration += 1
        let generation = feedbackGeneration
        feedback = .copying

        Task { @MainActor in
            let didCopy = await TranscriptClipboardWriter.copy(markdown: request.markdown)
            guard generation == feedbackGeneration else { return }
            feedback = didCopy ? .copied : .failed
            let delay = didCopy ? Duration.seconds(2) : Duration.seconds(3)
            try? await Task.sleep(for: delay)
            guard generation == feedbackGeneration else { return }
            feedback = .idle
        }
    }
}
