import BlitzRecorderCore
import SwiftUI

struct CaptureCommandBar: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        BlitzAdaptiveRow(.init(minimumContentWidth: 180)) {
            FolderRecordTargetChip(vm: vm)
                .frame(maxWidth: 240, alignment: .leading)
            RecordingOutputPicker(vm: vm)
            CanvasGuidesMenu(vm: vm)
            RecorderVisibilityMenu(vm: vm)
            RecordingQualityShortcut(vm: vm)
        }
    }
}

/// Preview-only guides live with the preview controls, not in the canvas settings: they are never recorded.
private struct CanvasGuidesMenu: View {
    @Bindable var vm: RecorderViewModel
    @AppStorage(ShortFormSafeZone.preferenceKey) private var showsSafeZones = false

    private var showsSafeZoneOption: Bool { vm.settings.layout == .vertical }
    private var anyGuideOn: Bool {
        vm.settings.showsRuleOfThirdsOverlay || (showsSafeZoneOption && showsSafeZones)
    }

    var body: some View {
        BlitzGlassMenu(entries: entries, menuWidth: 240) {
            HStack(spacing: 7) {
                BlitzSymbol(configuration: .init(name: "squareshape.split.3x3", size: 16))
                    .foregroundStyle(anyGuideOn ? BlitzUI.accent : BlitzUI.secondaryText)
                Text("Guides")
                    .font(BlitzType.label)
                    .foregroundStyle(BlitzUI.primaryText)
            }
            .padding(.horizontal, 10)
            .frame(height: BlitzControlMetrics.toolbarHeight)
        }
        .disabled(!vm.canEditScene)
        .help("Preview guides. They are never recorded.")
    }

    private var entries: [BlitzMenuEntry] {
        var entries: [BlitzMenuEntry] = [
            .item(.init(title: "Rule of thirds", subtitle: "Lines to help you frame the shot",
                        systemImage: "squareshape.split.3x3", isSelected: vm.settings.showsRuleOfThirdsOverlay,
                        action: { vm.setRuleOfThirds(!vm.settings.showsRuleOfThirdsOverlay) }))
        ]
        if showsSafeZoneOption {
            entries.append(.item(.init(title: "App safe zones", subtitle: "Where TikTok, Reels and Shorts put buttons",
                                       systemImage: "iphone", isSelected: showsSafeZones,
                                       action: { showsSafeZones.toggle() })))
        }
        return entries
    }
}

private struct RecordingQualityShortcut: View {
    @Bindable var vm: RecorderViewModel
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 9) {
                BlitzSymbol(configuration: .init(name: BlitzSymbols.videoQuality, size: 18))
                    .foregroundStyle(BlitzUI.secondaryText)
                Text(vm.settings.outputResolution.displayName)
                    .font(BlitzType.strong)
                    .foregroundStyle(BlitzUI.primaryText)
                Rectangle()
                    .fill(BlitzUI.panelStroke)
                    .frame(width: 1, height: 12)
                Text("\(vm.settings.framesPerSecond) FPS")
                    .font(BlitzType.captionEmphasis)
                    .foregroundStyle(BlitzUI.secondaryText)
                BlitzMenuChevron()
            }
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: BlitzControlMetrics.toolbarHeight)
        }
        .buttonStyle(BlitzMenuTriggerStyle(isPresented: isPresented))
        .accessibilityLabel("Recording quality, \(qualityPresentation.controlLabel)")
        .disabled(vm.state != .idle)
        .help("Choose recording resolution and Source FPS")
        .onChange(of: vm.state) {
            if vm.state != .idle { isPresented = false }
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            qualityPopover
        }
    }

    private var qualityPopover: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recording quality")
                    .font(BlitzType.headline)
                    .foregroundStyle(BlitzUI.primaryText)
                Text(resolutionDimensions)
                    .font(BlitzType.caption)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 8) {
                BlitzUI.sectionLabel("Resolution")
                BlitzSegmentedPicker(configuration: .init(
                    title: "Recording resolution",
                    options: OutputResolution.allCases,
                    selection: Binding(get: { vm.settings.outputResolution }, set: { vm.setResolution($0) }),
                    label: { $0.displayName }
                ))
            }

            VStack(alignment: .leading, spacing: 8) {
                BlitzUI.sectionLabel("Source FPS")
                BlitzSegmentedPicker(configuration: .init(
                    title: "Source FPS",
                    options: RecordingSettings.supportedFrameRates,
                    selection: Binding(get: { vm.settings.framesPerSecond }, set: { vm.setFrameRate($0) }),
                    label: { "\($0) FPS" }
                ))
                Text(frameRateDescription)
                    .font(BlitzType.footnote)
                    .foregroundStyle(BlitzUI.secondaryText)
            }
        }
        .disabled(vm.state != .idle)
        .padding(16)
        .frame(width: 288)
    }

    private var qualityPresentation: RecordingQualityPresentation {
        RecordingQualityPresentation(settings: vm.settings)
    }

    private var resolutionDimensions: String {
        let dimensions = vm.settings.outputResolution.dimensions(for: vm.settings.layout)
        return "\(dimensions.width) × \(dimensions.height)"
    }

    private var frameRateDescription: String {
        switch vm.settings.framesPerSecond {
        case 24: return "Cinematic motion"
        case 60: return "Extra smooth motion"
        default: return "Standard motion"
        }
    }
}
