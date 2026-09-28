import AppKit
import SwiftUI

enum EditorExportDestination: String, CaseIterable {
    case file
    case link

    var title: String { self == .file ? "Save to Mac" : "Share link" }

    func layouts(_ request: EditorExportLayouts.Request) -> [CaptureLayout] {
        EditorExportLayouts.resolve(.init(current: request.current, additional: self == .link ? [] : request.additional))
    }
}

struct EditorExportPopover: View {
    struct Configuration {
        let destination: Binding<EditorExportDestination>
        let additionalLayouts: Binding<Set<CaptureLayout>>
        let currentLayout: CaptureLayout
        let format: Binding<OutputVideoFormat>
        let resolution: Binding<OutputResolution>
        let framesPerSecond: Binding<Int>
        let quality: Binding<ExportVideoQuality>
        let playbackRate: Binding<ExportPlaybackRate>
        let estimatedSize: String
        let estimatedSizeCaption: String
        let encodingDetail: String
        let directory: URL
        let canExport: Bool
        let export: () -> Void
        let chooseFolder: () -> Void
    }

    let configuration: Configuration
    @State private var showsAdvanced = false

    private var layouts: [CaptureLayout] {
        configuration.destination.wrappedValue.layouts(.init(
            current: configuration.currentLayout, additional: configuration.additionalLayouts.wrappedValue))
    }

    private var formatOptions: [OutputVideoFormat] {
        configuration.quality.wrappedValue.requiresQuickTime ? [.mov] : OutputVideoFormat.allCases
    }

    private var summary: String {
        let format = layouts.count > 1 ? "\(layouts.count) videos" : EditorExportLayouts.title(configuration.currentLayout)
        return "\(format) · \(configuration.resolution.wrappedValue.displayName) · \(configuration.framesPerSecond.wrappedValue) fps"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(layouts.count > 1 ? "Export videos" : "Export video")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(BlitzUI.primaryText)
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundStyle(BlitzUI.supportingText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                BlitzSegmentedPicker(configuration: .init(
                    title: "Export destination", options: EditorExportDestination.allCases,
                    selection: configuration.destination, label: { $0.title }
                ))
                Text(configuration.destination.wrappedValue == .link
                     ? "Keep a high-quality copy of your edit in the cloud. A hosting subscription is required."
                     : "Save a video file to your Mac.")
                    .font(.system(size: 12))
                    .foregroundStyle(BlitzUI.supportingText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                if configuration.destination.wrappedValue == .link {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("High quality · 1080p max", systemImage: "checkmark.shield")
                            .font(.system(size: 13, weight: .semibold))
                        Text("\(configuration.resolution.wrappedValue.displayName) · \(configuration.framesPerSecond.wrappedValue) fps · High-quality HEVC")
                            .font(.system(size: 12))
                        Text("Smaller uploads with the source frame rate. Streaming adapts to the viewer’s connection.")
                            .font(.system(size: 12)).foregroundStyle(BlitzUI.supportingText)
                            .fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quality")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(BlitzUI.secondaryText)
                        BlitzSegmentedPicker(configuration: .init(
                            title: "Export quality", options: ExportVideoQuality.menuCases,
                            selection: configuration.quality, label: { $0.displayName }
                        ))
                        .controlSize(.mini)
                        .help(configuration.quality.wrappedValue.plainDescription)
                    }
                    EditorExportChoiceRow(configuration: .init(
                        title: "Export FPS", options: RecordingSettings.supportedFrameRates,
                        selection: configuration.framesPerSecond, label: { "\($0)" }
                    ))
                }
                EditorExportSpeedControl(selection: configuration.playbackRate)
            }

            if configuration.destination.wrappedValue == .file {
                BlitzInspectorDisclosure(configuration: .init(
                    title: "Advanced settings", detail: nil, isExpanded: $showsAdvanced,
                    content: { advancedSettings }
                ))
            }

            Rectangle().fill(BlitzUI.separator).frame(height: 1)

            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundStyle(BlitzUI.secondaryText)
                Text("Save to \(configuration.directory.lastPathComponent)")
                    .font(.system(size: 12))
                    .foregroundStyle(BlitzUI.supportingText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(configuration.directory.path)
                Spacer(minLength: 0)
                Button("Change", action: configuration.chooseFolder)
                    .blitzButton(.quiet)
                    .controlSize(.small)
                    .accessibilityLabel("Change export folder")
                    .help("Change where finished videos are saved. Source files stay in the library.")
            }

            Button(action: configuration.export) {
                Text(configuration.destination.wrappedValue == .link ? "Continue to share"
                     : layouts.count > 1 ? "Export \(layouts.count) videos" : "Export video")
                    .frame(maxWidth: .infinity)
            }
            .blitzButton(.accent)
            .controlSize(.large)
            .disabled(!configuration.canExport)
        }
        .padding(20)
        .frame(width: 380)
        .background(BlitzUI.panelBackground)
        .preferredColorScheme(.dark)
    }

    private var advancedHeight: CGFloat {
        let screen = NSApp.mainWindow?.screen ?? NSScreen.main
        return min(260, max(140, (screen?.visibleFrame.height ?? 800) - 520))
    }

    private var advancedSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 12) {
                    EditorExportChoiceRow(configuration: .init(
                        title: "File format", options: OutputVideoFormat.allCases,
                        selection: configuration.format, label: { $0.displayName },
                        isOptionEnabled: { formatOptions.contains($0) }
                    ))
                    .help(configuration.quality.wrappedValue.requiresQuickTime
                        ? "ProRes requires MOV." : configuration.format.wrappedValue.plainDescription)
                    EditorExportChoiceRow(configuration: .init(
                        title: "Resolution", options: OutputResolution.allCases,
                        selection: configuration.resolution, label: { $0.displayName }
                    ))
                }
                Rectangle().fill(BlitzUI.separator).frame(height: 1)
                if configuration.destination.wrappedValue == .file {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Also export")
                        .font(.system(size: 12, weight: .medium))
                    ForEach(CaptureLayout.allCases.filter { $0 != configuration.currentLayout }, id: \.self) { layout in
                        Toggle(EditorExportLayouts.title(layout), isOn: Binding(
                            get: { configuration.additionalLayouts.wrappedValue.contains(layout) },
                            set: { enabled in
                                if enabled { configuration.additionalLayouts.wrappedValue.insert(layout) }
                                else { configuration.additionalLayouts.wrappedValue.remove(layout) }
                            }
                        ))
                        .toggleStyle(.blitzCheckbox)
                        .controlSize(.small)
                        .help("Export an additional \(EditorExportLayouts.title(layout).lowercased()) video. Adjust its framing above the preview.")
                    }
                }
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(configuration.estimatedSizeCaption) · \(configuration.estimatedSize)")
                    Text(configuration.encodingDetail)
                }
                .font(.system(size: 11))
                .foregroundStyle(BlitzUI.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.automatic)
        .frame(height: advancedHeight)
    }
}

struct EditorExportChoiceRow<Value: Hashable>: View {
    let configuration: BlitzSegmentedPicker<Value>.Configuration

    var body: some View {
        HStack(spacing: 16) {
            Text(configuration.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(BlitzUI.secondaryText)
                .frame(width: 88, alignment: .leading)
            BlitzSegmentedPicker(configuration: configuration)
        }
    }
}

struct EditorExportSpeedControl: View {
    @Binding var selection: ExportPlaybackRate
    @State private var pendingValue: Double?

    private var value: Binding<Double> {
        Binding(get: { pendingValue ?? selection.value }, set: { value in
            if pendingValue != nil { pendingValue = value }
            else { selection = ExportPlaybackRate(clamping: value) }
        })
    }

    var body: some View {
        HStack(spacing: 16) {
            Text("Speed")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(BlitzUI.secondaryText)
                .frame(width: 88, alignment: .leading)
            HStack(spacing: 10) {
                Slider(value: value,
                       in: ExportPlaybackRate.normal.value...Double(TimelineTimeMap.maximumPlaybackRateTenths) / 10,
                       step: 0.1, onEditingChanged: { editing in
                    if editing { pendingValue = selection.value }
                    else { commit() }
                })
                .controlSize(.small)
                .tint(BlitzUI.mint)
                .accessibilityLabel("Export speed")
                .accessibilityValue(ExportPlaybackRate(clamping: value.wrappedValue).displayName)
                Text(ExportPlaybackRate(clamping: value.wrappedValue).displayName)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(BlitzUI.primaryText)
                    .frame(width: 40, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: BlitzControlMetrics.height(.regular))
        .help("Export speed from 1× to 2×. Voice pitch stays natural.")
        .onDisappear { commit() }
    }

    private func commit() {
        guard let pendingValue else { return }
        selection = ExportPlaybackRate(clamping: pendingValue)
        self.pendingValue = nil
    }
}

#Preview("Export popover") {
    EditorExportPopover(configuration: .init(
        destination: .constant(.file),
        additionalLayouts: .constant([]), currentLayout: .vertical,
        format: .constant(.mp4), resolution: .constant(.p1080), framesPerSecond: .constant(24),
        quality: .constant(.high), playbackRate: .constant(.init(clamping: 1.3)),
        estimatedSize: "≈ 160 MB", estimatedSizeCaption: "Estimated size", encodingDetail: "HEVC · 12.0 Mbps",
        directory: URL(fileURLWithPath: "/tmp/Recordings"), canExport: true,
        export: {}, chooseFolder: {}
    ))
}
