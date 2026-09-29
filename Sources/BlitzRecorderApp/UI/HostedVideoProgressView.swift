import SwiftUI

struct HostedVideoProgressPresentation {
    let stage: Int
    let title: String
    let detail: String
    let fraction: Double?

    static func exporting(_ progress: EditorExportStatus.Progress) -> Self {
        .init(stage: 0, title: "Saving cloud copy", detail: progress.supplementaryDetail ?? "Rendering your edit in high quality, up to 1080p.",
              fraction: progress.value)
    }

    static func transfer(_ progress: HostingClient.Progress) -> Self {
        switch progress {
        case .optimizing(let fraction):
            .init(stage: 0, title: "Preparing sharing copy", detail: "Creating a browser-ready MP4, up to 1080p. Your original stays unchanged.", fraction: fraction)
        case .preparing:
            .init(stage: 1, title: "Connecting to cloud", detail: "Your local copy is saved. Preparing a secure upload.", fraction: nil)
        case .uploading(let bytes):
            .init(stage: 1, title: "Uploading video", detail: bytes.detail, fraction: bytes.fraction)
        case .processing:
            .init(stage: 2, title: "Checking video", detail: "Upload complete. Your link appears once playback is verified.", fraction: nil)
        }
    }
}

struct HostedVideoProgressView: View {
    let presentation: HostedVideoProgressPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(presentation.title).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                if let fraction = presentation.fraction {
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                }
            }
            ProgressView(value: presentation.fraction)
                .progressViewStyle(.linear)
                .tint(BlitzUI.mint)
                .accessibilityLabel(presentation.title)
            Text(presentation.detail)
                .font(.system(size: 12)).foregroundStyle(BlitzUI.supportingText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                ForEach(Array(["Save", "Upload", "Check video"].enumerated()), id: \.offset) { item in
                    HStack(spacing: 5) {
                        Image(systemName: item.offset < presentation.stage ? "checkmark.circle.fill" : "\(item.offset + 1).circle")
                        Text(item.element)
                    }
                    .font(.system(size: 11, weight: item.offset == presentation.stage ? .semibold : .regular))
                    .foregroundStyle(item.offset <= presentation.stage ? BlitzUI.primaryText : BlitzUI.secondaryText)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(presentation.stage + 1) of 3")
        }
    }
}
