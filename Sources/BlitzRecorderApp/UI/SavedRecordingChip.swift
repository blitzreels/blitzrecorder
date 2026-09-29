import AppKit
import AVFoundation
import SwiftUI

struct ProjectReadyChip: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        EditRecordingButton(configuration: .init(
            title: "Edit recording",
            isLoading: false,
            help: "Open \(projectDetail) in the editor",
            action: { vm.openEditor() }
        ))
        .contextMenu {
            Button("Edit recording") { vm.openEditor() }
            Button("Show Source Files") {
                vm.revealLastSourceTracks()
            }
            Divider()
            Button("Clear") { vm.clearPostRecordingStatus() }
        }
    }

    private var projectDetail: String {
        vm.lastPostRecordingProjectOutput?.sourceDirectory.lastPathComponent
            ?? vm.lastExportedSourceTakeURL?.lastPathComponent
            ?? "Editable source project"
    }
}

struct SavedRecordingChip: View {
    @Bindable var vm: RecorderViewModel
    let url: URL
    let sourceTakeURL: URL?
    let warning: String?
    @State private var metadata = RecordingFileMetadata.empty
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            RecordingThumbnailButton(
                image: metadata.thumbnail,
                durationLabel: metadata.durationLabel,
                height: 40,
                help: "Play \(url.lastPathComponent)"
            ) {
                NSWorkspace.shared.open(url)
            }

            SavedRecordingSummaryButton(detail: savedDetail, path: url.path) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }

            if let warning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(BlitzType.glyph(11))
                    .foregroundStyle(BlitzUI.warning)
                    .help(warning)
            }

            if sourceTakeURL != nil {
                EditRecordingButton(configuration: .init(
                    title: "Edit",
                    isLoading: false,
                    help: "Open this recording in the editor",
                    action: { vm.openEditor() }
                ))
                .controlSize(.small)
                .fixedSize()
            }

            if hovering {
                DockDismissButton(help: "Clear and get ready for the next take") {
                    vm.clearPostRecordingStatus()
                }
            }
        }
        .frame(maxWidth: 440, alignment: .leading)
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .contextMenu {
            Button("Play") { NSWorkspace.shared.open(url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("Rename…") { vm.renameLastExportedFile() }
            if let sourceTakeURL {
                Button("Edit recording") { vm.openEditor() }
                Button("Show Source Files") {
                    NSWorkspace.shared.activateFileViewerSelecting([sourceTakeURL])
                }
            }
            Divider()
            Button("Clear") { vm.clearPostRecordingStatus() }
        }
        .task(id: url) {
            metadata = .empty
            metadata = await RecordingFileMetadata.load(for: url)
        }
    }

    private var savedDetail: String {
        var parts = [url.lastPathComponent]
        if metadata.thumbnail == nil, let durationLabel = metadata.durationLabel {
            parts.append(durationLabel)
        }
        if let sizeLabel = metadata.sizeLabel {
            parts.append(sizeLabel)
        }
        return parts.joined(separator: " · ")
    }
}

private struct SavedRecordingSummaryButton: View {
    let detail: String
    let path: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(BlitzType.glyph(10))
                        .foregroundStyle(BlitzUI.mint.opacity(0.9))
                    Text("Recording saved")
                        .font(BlitzType.strong)
                        .foregroundStyle(BlitzUI.primaryText)
                        .fixedSize()
                }
                Text(detail)
                    .font(BlitzType.footnote)
                    .monospacedDigit()
                    .foregroundStyle(hovering ? BlitzUI.supportingText : BlitzUI.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .frame(minWidth: 120, maxWidth: 180, alignment: .leading)
        .layoutPriority(-1)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .pointingHandCursor()
        .help("Show in Finder — \(path)")
    }
}

private struct RecordingThumbnailButton: View {
    let image: NSImage?
    let durationLabel: String?
    var height: CGFloat = 68
    let help: String
    let action: () -> Void
    @State private var hovering = false

    private var width: CGFloat {
        guard let image, image.size.height > 0 else { return height * 16 / 9 }
        let ideal = height * image.size.width / image.size.height
        return min(max(ideal, height * 0.6), height * 1.9)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(BlitzUI.controlFill)
                    Image(systemName: "film")
                        .font(BlitzType.glyph(16))
                        .foregroundStyle(BlitzUI.tertiaryText)
                }

                Rectangle()
                    .fill(.black.opacity(hovering ? 0.35 : 0))
                Image(systemName: "play.fill")
                    .font(BlitzType.glyph(16))
                    .foregroundStyle(.white)
                    .opacity(hovering ? 1 : 0)
            }
            .frame(width: width, height: height)
            .overlay(alignment: .bottomTrailing) {
                if let durationLabel {
                    Text(durationLabel)
                        .font(BlitzType.footnote)
                        .monospacedDigit()
                        .foregroundStyle(BlitzUI.primaryText)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .padding(4)
                        .opacity(hovering ? 0 : 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: BlitzUI.controlRadius, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .pointingHandCursor()
        .help(help)
    }
}

private struct DockDismissButton: View {
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(BlitzType.glyph(10))
                .foregroundStyle(hovering ? BlitzUI.primaryText : BlitzUI.tertiaryText)
                .frame(width: 22, height: 22)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .pointingHandCursor()
        .help(help)
    }
}

private struct RecordingFileMetadata {
    let sizeLabel: String?
    let durationLabel: String?
    let thumbnail: NSImage?

    static let empty = RecordingFileMetadata(sizeLabel: nil, durationLabel: nil, thumbnail: nil)

    static func load(for url: URL) async -> RecordingFileMetadata {
        async let sizeLabel = fileSizeLabel(for: url)
        async let durationLabel = durationLabel(for: url)
        async let thumbnail = thumbnail(for: url)
        return await RecordingFileMetadata(sizeLabel: sizeLabel, durationLabel: durationLabel, thumbnail: thumbnail)
    }

    private static func thumbnail(for url: URL) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        guard let (cgImage, _) = try? await generator.image(at: .zero) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private static func fileSizeLabel(for url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let byteCount = attributes[.size] as? NSNumber else {
            return nil
        }
        return ByteCountFormatter.string(fromByteCount: byteCount.int64Value, countStyle: .file)
    }

    private static func durationLabel(for url: URL) async -> String? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration),
              duration.isValid,
              duration.seconds.isFinite,
              duration.seconds > 0 else {
            return nil
        }
        return formattedDuration(seconds: duration.seconds)
    }

    private static func formattedDuration(seconds: Double) -> String {
        let totalSeconds = Int(seconds.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
