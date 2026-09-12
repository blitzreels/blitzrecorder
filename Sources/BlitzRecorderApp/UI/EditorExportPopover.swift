import SwiftUI

struct EditorExportPopover<MusicControls: View>: View {
    struct Configuration {
        let preset: Binding<ExportPerformancePreset>
        let format: Binding<OutputVideoFormat>
        let resolution: Binding<OutputResolution>
        let framesPerSecond: Binding<Int>
        let quality: Binding<ExportVideoQuality>
        let summary: String
        let estimatedSize: String
        let encodingDetail: String
        let directory: URL
        let musicSummary: String?
        let musicControls: () -> MusicControls
        let canExport: Bool
        let export: () -> Void
        let showFolder: () -> Void
        let showBlitzReels: () -> Void
    }

    let configuration: Configuration
    @State private var showsMusic = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Export video")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(BlitzUI.primaryText)
                Text("Save your finished video to this Mac.")
                    .font(.system(size: 12))
                    .foregroundStyle(BlitzUI.secondaryText)
            }
            .padding(.bottom, 20)

            VStack(spacing: 12) {
                BlitzFormDropdown(configuration: .init(
                    title: "Preset", selection: configuration.preset,
                    options: ExportPerformancePreset.allCases.map {
                        .init(value: $0, title: $0.displayName, detail: $0.plainDescription)
                    }, menuWidth: 330
                ))
                BlitzFormDropdown(configuration: .init(
                    title: "Format", selection: configuration.format,
                    options: OutputVideoFormat.allCases.map {
                        .init(value: $0, title: $0.displayName, detail: nil)
                    }
                ))
                BlitzFormDropdown(configuration: .init(
                    title: "Resolution", selection: configuration.resolution,
                    options: OutputResolution.allCases.map {
                        .init(value: $0, title: $0.displayName, detail: nil)
                    }
                ))
                BlitzFormDropdown(configuration: .init(
                    title: "Export FPS", selection: configuration.framesPerSecond,
                    options: RecordingSettings.supportedFrameRates.map {
                        .init(value: $0, title: "\($0) fps", detail: nil)
                    }
                ))
                BlitzFormDropdown(configuration: .init(
                    title: "Quality", selection: configuration.quality,
                    options: ExportVideoQuality.allCases.map {
                        .init(value: $0, title: $0.displayName, detail: $0.plainDescription)
                    }
                ))
            }

            Divider().overlay(BlitzUI.separator).padding(.vertical, 18)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(configuration.summary)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(BlitzUI.primaryText)
                    Text(configuration.encodingDetail)
                        .font(.system(size: 11))
                        .foregroundStyle(BlitzUI.secondaryText)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 5) {
                    Text(configuration.estimatedSize)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(BlitzUI.primaryText)
                    Text("Estimated size")
                        .font(.system(size: 11))
                        .foregroundStyle(BlitzUI.secondaryText)
                }
                .fixedSize()
            }

            BlitzInspectorDisclosure(configuration: .init(
                title: "Background music",
                detail: configuration.musicSummary ?? "None",
                isExpanded: $showsMusic,
                content: configuration.musicControls
            ))
            .padding(.top, 12)

            Button(action: configuration.showFolder) {
                HStack(spacing: 7) {
                    Image(systemName: "folder")
                    Text("Save to")
                    Text(configuration.directory.lastPathComponent)
                        .foregroundStyle(BlitzUI.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                }
                .frame(maxWidth: .infinity)
            }
            .blitzButton(.quiet)
            .help(configuration.directory.path)
            .accessibilityLabel("Save location: \(configuration.directory.path). Show in Finder")
            .padding(.top, 12)
            .padding(.bottom, 14)

            Button(action: configuration.export) {
                Label("Export video", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .blitzButton(.accent)
            .controlSize(.large)
            .disabled(!configuration.canExport)

            Button(action: configuration.showBlitzReels) {
                HStack(spacing: 6) {
                    Text("Send to BlitzReels")
                    Image(systemName: "arrow.up.right")
                }
                .frame(maxWidth: .infinity)
            }
            .blitzButton(.quiet)
            .controlSize(.small)
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 420)
        .background(BlitzUI.panelBackground)
        .preferredColorScheme(.dark)
    }
}
