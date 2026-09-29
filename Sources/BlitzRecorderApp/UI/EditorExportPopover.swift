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
        EditorExportDestination.file.layouts(.init(
            current: configuration.currentLayout, additional: configuration.additionalLayouts.wrappedValue))
    }

    private var formatOptions: [OutputVideoFormat] {
        configuration.quality.wrappedValue.requiresQuickTime ? [.mov] : OutputVideoFormat.allCases
    }

    private var summary: String {
        let formats = layouts.count > 1 ? "\(layouts.count) videos" : EditorExportLayouts.title(configuration.currentLayout)
        return [formats, configuration.resolution.wrappedValue.displayName,
                "\(configuration.framesPerSecond.wrappedValue) fps", configuration.estimatedSize]
            .joined(separator: " · ")
    }

    private var advancedDetail: String {
        let extra = layouts.count > 1 ? " · +\(layouts.count - 1)" : ""
        return "\(configuration.format.wrappedValue.displayName) · \(configuration.framesPerSecond.wrappedValue) fps\(extra)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(layouts.count > 1 ? "Export \(layouts.count) videos" : "Export video")
                    .font(BlitzType.title)
                    .foregroundStyle(BlitzUI.primaryText)
                Text(summary)
                    .font(BlitzType.body.monospacedDigit())
                    .foregroundStyle(BlitzUI.supportingText)
                    .lineLimit(1)
                    .help("\(configuration.estimatedSizeCaption) · \(configuration.encodingDetail)")
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Quality")
                        .font(BlitzType.label)
                        .foregroundStyle(BlitzUI.secondaryText)
                    Spacer(minLength: 8)
                    Text(configuration.quality.wrappedValue.plainDescription)
                        .font(BlitzType.caption)
                        .foregroundStyle(BlitzUI.secondaryText)
                        .lineLimit(1)
                }
                BlitzSegmentedPicker(configuration: .init(
                    title: "Export quality", options: ExportVideoQuality.menuCases,
                    selection: configuration.quality, label: { $0.displayName }
                ))
                .controlSize(.mini)
            }

            VStack(spacing: 10) {
                EditorExportChoiceRow(configuration: .init(
                    title: "Resolution", options: OutputResolution.allCases,
                    selection: configuration.resolution, label: { $0.displayName }
                ))
                EditorExportSpeedControl(selection: configuration.playbackRate)
            }

            BlitzInspectorDisclosure(configuration: .init(
                title: "More options", detail: showsAdvanced ? nil : advancedDetail, isExpanded: $showsAdvanced,
                content: { advancedSettings }
            ))

            VStack(spacing: 12) {
                Rectangle().fill(BlitzUI.separator).frame(height: 1)
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .foregroundStyle(BlitzUI.secondaryText)
                    Text(configuration.directory.lastPathComponent)
                        .font(BlitzType.body)
                        .foregroundStyle(BlitzUI.supportingText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(configuration.directory.path)
                    Spacer(minLength: 0)
                    Button("Change…", action: configuration.chooseFolder)
                        .blitzButton(.quiet)
                        .controlSize(.small)
                        .accessibilityLabel("Change export folder")
                        .help("Change where finished videos are saved. Source files stay in the library.")
                }
                Button(action: configuration.export) {
                    Text(layouts.count > 1 ? "Export \(layouts.count) videos" : "Export video")
                        .frame(maxWidth: .infinity)
                }
                .blitzButton(.accent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!configuration.canExport)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(BlitzUI.panelBackground)
        .preferredColorScheme(.dark)
    }

    private var advancedSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            EditorExportChoiceRow(configuration: .init(
                title: "Frame rate", options: RecordingSettings.supportedFrameRates,
                selection: configuration.framesPerSecond, label: { "\($0)" }
            ))
            EditorExportChoiceRow(configuration: .init(
                title: "File format", options: OutputVideoFormat.allCases,
                selection: configuration.format, label: { $0.displayName },
                isOptionEnabled: { formatOptions.contains($0) }
            ))
            .help(configuration.quality.wrappedValue.requiresQuickTime
                ? "ProRes requires MOV." : configuration.format.wrappedValue.plainDescription)
            HStack(spacing: 16) {
                Text("Also export")
                    .font(BlitzType.label)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .frame(width: 88, alignment: .leading)
                HStack(spacing: 14) {
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
                Spacer(minLength: 0)
            }
            .frame(minHeight: BlitzControlMetrics.height(.regular))
            Text("\(configuration.estimatedSizeCaption) \(configuration.estimatedSize) · \(configuration.encodingDetail)")
                .font(BlitzType.caption)
                .foregroundStyle(BlitzUI.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct EditorExportChoiceRow<Value: Hashable>: View {
    let configuration: BlitzSegmentedPicker<Value>.Configuration

    var body: some View {
        HStack(spacing: 16) {
            Text(configuration.title)
                .font(BlitzType.label)
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
                .font(BlitzType.label)
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
                    .font(BlitzType.label.monospacedDigit())
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
        additionalLayouts: .constant([]), currentLayout: .vertical,
        format: .constant(.mp4), resolution: .constant(.p1080), framesPerSecond: .constant(24),
        quality: .constant(.high), playbackRate: .constant(.init(clamping: 1.3)),
        estimatedSize: "≈ 160 MB", estimatedSizeCaption: "Estimated size", encodingDetail: "HEVC · 12.0 Mbps",
        directory: URL(fileURLWithPath: "/tmp/Recordings"), canExport: true,
        export: {}, chooseFolder: {}
    ))
}
