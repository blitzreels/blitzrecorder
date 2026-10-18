import AppKit
import SwiftUI

enum EditorExportDestination: String, CaseIterable {
    case file
    case link

    var title: String { self == .file ? "Save to Mac" : "Share link" }
    var systemImage: String { self == .file ? "square.and.arrow.down" : "link" }

    func layouts(_ request: EditorExportLayouts.Request) -> [CaptureLayout] {
        EditorExportLayouts.resolve(.init(current: request.current, additional: self == .link ? [] : request.additional))
    }
}

struct EditorExportSettings: View {
    struct Configuration {
        let additionalLayouts: Binding<Set<CaptureLayout>>
        let currentLayout: CaptureLayout
        let format: Binding<OutputVideoFormat>
        let resolution: Binding<OutputResolution>
        let framesPerSecond: Binding<Int>
        let quality: Binding<ExportVideoQuality>
        let playbackRate: Binding<ExportPlaybackRate>
        let estimatedSize: String
        let fileSize: EditorExportSizeSlider.Configuration
        let sizeEstimate: (ExportVideoQuality) -> String
        let encodingDetail: String
        let directory: URL
        let canExport: Bool
        let export: () -> Void
        let chooseFolder: () -> Void
    }

    /// The controls scroll in the pane. The folder and Export button stay pinned below them.
    enum Section {
        case controls
        case action
    }

    let configuration: Configuration
    let section: Section
    @State private var showsAdvanced = false

    private var layouts: [CaptureLayout] {
        EditorExportDestination.file.layouts(.init(
            current: configuration.currentLayout, additional: configuration.additionalLayouts.wrappedValue))
    }

    private var formatOptions: [OutputVideoFormat] {
        configuration.quality.wrappedValue.requiresQuickTime ? [.mov] : OutputVideoFormat.allCases
    }

    private var advancedDetail: String {
        let extra = layouts.count > 1 ? " · +\(layouts.count - 1)" : ""
        return "\(configuration.format.wrappedValue.displayName) · \(configuration.framesPerSecond.wrappedValue) fps\(extra)"
    }

    var body: some View {
        switch section {
        case .controls:
            VStack(alignment: .leading, spacing: 18) { controls }
        case .action:
            action
        }
    }

    @ViewBuilder private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            EditorExportQualityPicker(configuration: .init(
                selection: configuration.quality, size: configuration.sizeEstimate
            ))
            Text(configuration.fileSize.isCustom && configuration.fileSize.isAvailable
                 ? "Custom size, encoded like \(configuration.quality.wrappedValue.displayName). Pick a quality to undo."
                 : configuration.quality.wrappedValue.plainDescription)
                .font(BlitzType.caption)
                .foregroundStyle(BlitzUI.secondaryText)
                .lineLimit(1)
        }

        VStack(spacing: 10) {
            EditorExportSizeSlider(configuration: configuration.fileSize)
            EditorExportChoiceRow(configuration: .init(
                title: "Resolution", options: OutputResolution.allCases,
                selection: configuration.resolution, label: { $0.displayName }
            ))
        }

        BlitzInspectorDisclosure(configuration: .init(
            title: "More options", detail: showsAdvanced ? nil : advancedDetail, isExpanded: $showsAdvanced,
            content: { advancedSettings }
        ))

    }

    private var action: some View {
        VStack(spacing: 12) {
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
                    .help("Change where finished videos are saved")
            }
            EditorOutputPrimaryButton(configuration: .init(
                title: "\(layouts.count > 1 ? "Export \(layouts.count) videos" : "Export video") · \(configuration.estimatedSize)",
                systemImage: "square.and.arrow.down",
                isEnabled: configuration.canExport,
                help: configuration.encodingDetail,
                action: configuration.export
            ))
        }
    }

    private var advancedSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            EditorExportSpeedControl(selection: configuration.playbackRate)
            EditorExportChoiceRow(configuration: .init(
                title: "Frame rate", options: RecordingSettings.supportedFrameRates,
                selection: configuration.framesPerSecond, label: { "\($0)" }
            ))
            EditorExportChoiceRow(configuration: .init(
                title: "File format", options: formatOptions,
                selection: Binding(
                    get: { formatOptions.contains(configuration.format.wrappedValue) ? configuration.format.wrappedValue : .mov },
                    set: { configuration.format.wrappedValue = $0 }
                ),
                label: { $0.displayName }
            ))
            .help(configuration.quality.wrappedValue.requiresQuickTime
                ? "This quality always saves as MOV." : configuration.format.wrappedValue.plainDescription)
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
            Text("\(configuration.estimatedSize) · \(configuration.encodingDetail)")
                .font(BlitzType.caption)
                .foregroundStyle(BlitzUI.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct EditorExportSizeSlider: View {
    struct Configuration {
        let bytes: Int64
        let range: ClosedRange<Int64>
        /// True once the person dragged the slider, so the size no longer follows the quality tier.
        let isCustom: Bool
        let isAvailable: Bool
        let perVideo: Bool
        let warning: String?
        let select: (Int64?) -> Void
    }

    let configuration: Configuration
    @State private var pendingBytes: Int64?

    private var shownBytes: Int64 { pendingBytes ?? configuration.bytes }

    private var position: Binding<Double> {
        Binding(get: { Self.position(of: shownBytes, in: configuration.range) }, set: {
            pendingBytes = Self.bytes(at: $0, in: configuration.range)
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 16) {
                Text("File size")
                    .font(BlitzType.label)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .frame(width: 88, alignment: .leading)
                if configuration.isAvailable {
                    HStack(spacing: 10) {
                        Slider(value: position, in: 0...1, onEditingChanged: { editing in
                            guard !editing, let pendingBytes else { return }
                            configuration.select(pendingBytes)
                            self.pendingBytes = nil
                        })
                        .controlSize(.small)
                        .tint(BlitzUI.accent)
                        .accessibilityLabel("File size")
                        .accessibilityValue(Self.text(shownBytes))
                        Text(Self.text(shownBytes))
                            .font(BlitzType.label.monospacedDigit())
                            .foregroundStyle(BlitzUI.primaryText)
                            .frame(width: 64, alignment: .trailing)
                            .accessibilityHidden(true)
                    }
                } else {
                    Text("About \(Self.text(shownBytes)) · set by the quality")
                        .font(BlitzType.label.monospacedDigit())
                        .foregroundStyle(BlitzUI.supportingText)
                    Spacer(minLength: 0)
                }
            }
            .frame(minHeight: BlitzControlMetrics.height(.regular))
            .help(configuration.isAvailable
                  ? "Drag to pick the exact size. The quality adjusts to fit."
                  : "This quality keeps every detail, so its size depends on resolution and length.")
            if configuration.isCustom, configuration.isAvailable {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(configuration.warning
                         ?? "Stays \(Self.text(configuration.bytes))\(configuration.perVideo ? " per video" : "") even if you cut more.")
                        .font(BlitzType.caption)
                        .foregroundStyle(configuration.warning == nil ? BlitzUI.secondaryText : BlitzUI.warning)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Reset") { configuration.select(nil) }
                        .blitzButton(.quiet)
                        .controlSize(.small)
                        .help("Go back to the size of the selected quality")
                }
            }
        }
    }

    private static func position(of bytes: Int64, in range: ClosedRange<Int64>) -> Double {
        let low = log(Double(range.lowerBound)), high = log(Double(range.upperBound))
        return min(1, max(0, (log(Double(max(1, bytes))) - low) / (high - low)))
    }

    private static func bytes(at position: Double, in range: ClosedRange<Int64>) -> Int64 {
        let low = log(Double(range.lowerBound)), high = log(Double(range.upperBound))
        let raw = exp(low + (high - low) * position)
        let step = raw < 10_000_000 ? 100_000.0 : 1_000_000.0
        return Int64(max(Double(range.lowerBound), (raw / step).rounded() * step))
    }

    private static func text(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct EditorExportQualityPicker: View {
    struct Configuration {
        let selection: Binding<ExportVideoQuality>
        let size: (ExportVideoQuality) -> String
    }

    let configuration: Configuration

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ExportVideoQuality.menuCases, id: \.self) { quality in
                let isSelected = configuration.selection.wrappedValue == quality
                Button { configuration.selection.wrappedValue = quality } label: {
                    VStack(spacing: 2) {
                        Text(quality.displayName)
                            .font(BlitzType.captionEmphasis)
                            .foregroundStyle(isSelected ? BlitzUI.primaryText : BlitzUI.supportingText)
                        Text(configuration.size(quality).replacingOccurrences(of: "≈ ", with: ""))
                            .font(BlitzType.caption.monospacedDigit())
                            .foregroundStyle(BlitzUI.secondaryText)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                }
                .buttonStyle(BlitzSelectionButtonStyle(isSelected: isSelected))
                .accessibilityLabel("\(quality.displayName), about \(configuration.size(quality))")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                .help(quality.plainDescription)
                .pointingHandCursor()
            }
        }
        .blitzTabGroup()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Export quality")
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
                .tint(BlitzUI.accent)
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

#Preview("Export settings") {
    EditorExportSettings(configuration: .init(
        additionalLayouts: .constant([]), currentLayout: .vertical,
        format: .constant(.mp4), resolution: .constant(.p1080), framesPerSecond: .constant(24),
        quality: .constant(.high), playbackRate: .constant(.init(clamping: 1.3)),
        estimatedSize: "≈ 52 MB",
        fileSize: .init(bytes: 52_000_000, range: 5_000_000...276_000_000, isCustom: true, isAvailable: true,
                        perVideo: false, warning: nil, select: { _ in }),
        sizeEstimate: { ["compact": "≈ 35 MB", "web": "≈ 70 MB", "high": "≈ 138 MB", "proRes": "≈ 1,6 GB"][$0.rawValue] ?? "" },
        encodingDetail: "HEVC · 10.0 Mbps",
        directory: URL(fileURLWithPath: "/tmp/Recordings"), canExport: true,
        export: {}, chooseFolder: {}
    ), section: .controls)
}
