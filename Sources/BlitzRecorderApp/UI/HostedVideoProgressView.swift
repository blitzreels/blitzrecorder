import SwiftUI

struct HostedVideoProgressPresentation {
    let stage: Int
    let title: String
    let detail: String
    let fraction: Double?

    static func exporting(_ progress: EditorExportStatus.Progress) -> Self {
        .init(stage: 0, title: "Saving cloud copy", detail: progress.supplementaryDetail ?? "Rendering a browser-ready H.264 copy, up to 1080p.",
              fraction: progress.value)
    }

    static func transfer(_ progress: HostingClient.Progress) -> Self {
        switch progress {
        case .optimizing(let fraction):
            .init(stage: 0, title: "Preparing sharing copy", detail: "Converting this file to H.264, up to 1080p. Your original stays unchanged.", fraction: fraction)
        case .preparing:
            .init(stage: 1, title: "Connecting to cloud", detail: "Your local copy is saved. Preparing a secure upload.", fraction: nil)
        case .uploading(let bytes):
            .init(stage: 1, title: "Uploading video", detail: bytes.detail, fraction: bytes.fraction)
        case .processing(let fraction):
            .init(stage: 2, title: "Preparing playback", detail: "Upload complete. Creating streaming quality options.", fraction: fraction)
        }
    }
}

struct HostedVideoProgressView: View {
    let presentation: HostedVideoProgressPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(presentation.title).font(BlitzType.section)
                Spacer(minLength: 8)
                if let fraction = presentation.fraction {
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .font(BlitzType.label.monospacedDigit())
                }
            }
            ProgressView(value: presentation.fraction)
                .progressViewStyle(.linear)
                .tint(BlitzUI.mint)
                .accessibilityLabel(presentation.title)
            Text(presentation.detail)
                .font(BlitzType.body).foregroundStyle(BlitzUI.supportingText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                ForEach(Array(["Save", "Upload", "Prepare playback"].enumerated()), id: \.offset) { item in
                    HStack(spacing: 5) {
                        Image(systemName: item.offset < presentation.stage ? "checkmark.circle.fill" : "\(item.offset + 1).circle")
                        Text(item.element)
                    }
                    .font(item.offset == presentation.stage ? BlitzType.captionEmphasis : BlitzType.caption)
                    .foregroundStyle(item.offset <= presentation.stage ? BlitzUI.primaryText : BlitzUI.secondaryText)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(presentation.stage + 1) of 3")
        }
    }
}
