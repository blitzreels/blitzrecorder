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

struct TranscriptClipboardVerificationRequest {
    let didWrite: Bool
    let expected: String
    let actual: String?
}

enum TranscriptClipboardVerification {
    static func succeeded(_ request: TranscriptClipboardVerificationRequest) -> Bool {
        request.didWrite && request.actual == request.expected
    }
}

struct TranscriptClipboardWriteRequest {
    let markdown: String
}

@MainActor
enum TranscriptClipboardWriter {
    static func copy(_ request: TranscriptClipboardWriteRequest) async -> Bool {
        for attempt in 0..<3 {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            let didWrite = pasteboard.setString(request.markdown, forType: .string)
            if TranscriptClipboardVerification.succeeded(.init(
                didWrite: didWrite,
                expected: request.markdown,
                actual: pasteboard.string(forType: .string)
            )) {
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
    @State private var isHovering = false

    init(_ request: TranscriptCopyButtonRequest) {
        self.request = request
    }

    var body: some View {
        Button(action: copy) {
            HStack(spacing: 7) {
                Image(systemName: feedback.systemImage)
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 14, height: 14)
                    .contentTransition(.symbolEffect(.replace))

                Text(feedback.title)
                    .font(.system(size: 11, weight: .semibold))
                    .contentTransition(.opacity)
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .background(backgroundColor, in: .rect(cornerRadius: 10))
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(TranscriptCopyPressButtonStyle())
        .disabled(feedback == .copying)
        .onHover { isHovering = $0 }
        .pointingHandCursor(enabled: feedback != .copying)
        .help(feedback.help)
        .accessibilityLabel(feedback.title)
        .animation(.easeOut(duration: 0.16), value: feedback)
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

    private var backgroundColor: Color {
        switch feedback {
        case .copied: return BlitzUI.mint.opacity(isHovering ? 0.18 : 0.12)
        case .failed: return .red.opacity(isHovering ? 0.16 : 0.10)
        case .idle, .copying:
            switch request.appearance {
            case .compact: return .white.opacity(isHovering ? 0.10 : 0.065)
            case .regular: return .primary.opacity(isHovering ? 0.10 : 0.065)
            }
        }
    }

    private func copy() {
        guard feedback != .copying else { return }
        feedbackGeneration += 1
        let generation = feedbackGeneration
        feedback = .copying

        Task { @MainActor in
            let didCopy = await TranscriptClipboardWriter.copy(.init(markdown: request.markdown))
            guard generation == feedbackGeneration else { return }
            feedback = didCopy ? .copied : .failed
            let delay = didCopy ? Duration.seconds(2) : Duration.seconds(3)
            try? await Task.sleep(for: delay)
            guard generation == feedbackGeneration else { return }
            feedback = .idle
        }
    }
}

private struct TranscriptCopyPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
