import AVFoundation
import BlitzRecorderDesign
import SwiftUI
import UIKit

struct RecordingLibraryRow: View {
    let recording: CameraPendingRecording

    var body: some View {
        HStack(spacing: 12) {
            RecordingThumbnailView(url: recording.url)
                .frame(width: 96, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(recording.createdAtLabel)
                    .font(BlitzType.navigation)
                    .foregroundStyle(BlitzUI.primaryText)
                    .lineLimit(1)
                Text([recording.fileName, recording.byteCountLabel].joined(separator: " · "))
                    .font(BlitzType.caption)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 66)
    }
}

private struct RecordingThumbnailView: View {
    let url: URL
    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(BlitzUI.controlFill)
                BlitzSymbol(configuration: .init(name: didFail ? "video.slash" : "video", size: 18))
                    .foregroundStyle(BlitzUI.tertiaryText)
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fill)
        .clipped()
        .accessibilityHidden(true)
        .task(id: url) {
            image = nil
            didFail = false
            image = await RecordingThumbnailGenerator.thumbnail(for: url)
            didFail = image == nil
        }
    }
}

private enum RecordingThumbnailGenerator {
    static func thumbnail(for url: URL) async -> UIImage? {
        await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 320, height: 320)

            guard let result = try? await generator.image(at: .zero) else {
                return nil
            }
            return UIImage(cgImage: result.image)
        }.value
    }
}
