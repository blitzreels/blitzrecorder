import SwiftUI

struct EditorExportPopover<MusicControls: View>: View {
    struct Configuration {
        let layouts: Binding<Set<CaptureLayout>>
        let currentLayout: CaptureLayout
        let preset: Binding<ExportPerformancePreset>
        let format: Binding<OutputVideoFormat>
        let resolution: Binding<OutputResolution>
        let framesPerSecond: Binding<Int>
        let quality: Binding<ExportVideoQuality>
        let playbackRate: Binding<ExportPlaybackRate>
        let summary: String
        let estimatedSize: String
        let estimatedSizeCaption: String
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

    private var formatOptions: [OutputVideoFormat] {
        configuration.quality.wrappedValue.requiresQuickTime ? [.mov] : OutputVideoFormat.allCases
    }

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

            VStack(alignment: .leading, spacing: 8) {
                Text("Output formats").font(.system(size: 12, weight: .semibold))
                ForEach(CaptureLayout.allCases, id: \.self) { layout in
                    Toggle(layout == .square ? "Square · 1:1" : layout == .vertical ? "Vertical · 9:16" : "Landscape · 16:9",
                        isOn: Binding(get: {
                            configuration.layouts.wrappedValue.isEmpty ? layout == configuration.currentLayout
                                : configuration.layouts.wrappedValue.contains(layout)
                        }, set: { enabled in
                            var layouts = configuration.layouts.wrappedValue
                            if layouts.isEmpty { layouts = [configuration.currentLayout] }
                            if enabled { layouts.insert(layout) } else if layouts.count > 1 { layouts.remove(layout) }
                            configuration.layouts.wrappedValue = layouts
                        }))
                        .toggleStyle(.blitzCheckbox)
                }
                Text("Choose a format above the preview to adjust its framing. Exports run one at a time.")
                    .font(.system(size: 11)).foregroundStyle(BlitzUI.secondaryText)
            }.padding(.bottom, 16)
            VStack(spacing: 12) {
                BlitzFormDropdown(configuration: .init(
                    title: "Preset", selection: configuration.preset,
                    options: ExportPerformancePreset.allCases.map {
                        .init(value: $0, title: $0.displayName, detail: $0.plainDescription)
                    }, menuWidth: 330
                ))
                BlitzFormDropdown(configuration: .init(
                    title: "Format", selection: configuration.format,
                    options: formatOptions.map {
                        .init(value: $0, title: $0.displayName, detail: $0.plainDescription)
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
                    options: ExportVideoQuality.menuCases.map {
                        .init(value: $0, title: $0.displayName, detail: $0.plainDescription)
                    }, menuWidth: 330
                ))
                BlitzFormDropdown(configuration: .init(
                    title: "Speed", selection: configuration.playbackRate,
                    options: ExportPlaybackRate.all.map {
                        .init(value: $0, title: $0.displayName, detail: nil)
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
                    Text(configuration.estimatedSizeCaption)
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
                    BlitzReelsBrand().frame(width: 96, height: 15)
                    Text("Add captions and B-roll")
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

#Preview("Export popover") {
    EditorExportPopover(configuration: .init(
        layouts: .constant([.horizontal]),
        currentLayout: .horizontal,
        preset: .constant(.fast),
        format: .constant(.mp4),
        resolution: .constant(.p1080),
        framesPerSecond: .constant(30),
        quality: .constant(.web),
        playbackRate: .constant(.normal),
        summary: "1920 × 1080 · 30 fps",
        estimatedSize: "≈ 32 MB",
        estimatedSizeCaption: "Estimated size",
        encodingDetail: "H.264 · 1.6 Mbps",
        directory: URL(fileURLWithPath: "/tmp/BlitzRecorder"),
        musicSummary: nil,
        musicControls: { EmptyView() },
        canExport: true,
        export: {},
        showFolder: {},
        showBlitzReels: {}
    ))
}
