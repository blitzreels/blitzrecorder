import BlitzRecorderCore
import SwiftUI

/// The studio top bar. The centre capsule says what file you are about to make and whether you are ready
/// (format, quality, readiness), like Xcode's activity view or Logic's display. Preview tools are quiet icons
/// on the right, and each panel toggle sits on the side of the panel it shows.
struct CaptureCommandBar: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        StudioToolbarLayout(spacing: 12) {
            HStack(spacing: 8) {
                StudioPanelToggle(panel: .inputs)
                FolderRecordTargetChip(vm: vm)
                    .frame(maxWidth: 220, alignment: .leading)
            }
            StudioOutputCapsule(vm: vm)
            HStack(spacing: 2) {
                PreviewOptionsButton(vm: vm)
                RecorderVisibilityMenu(vm: vm)
                StudioPanelToggle(panel: .inspector)
                    .padding(.leading, 6)
            }
        }
    }
}

/// Leading, centre and trailing groups at their natural widths. The centre group sits in the middle when there
/// is room and slides aside rather than overlap, the way an NSToolbar centres its items.
private struct StudioToolbarLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let ideal = sizes.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(0, subviews.count - 1))
        return CGSize(width: proposal.width ?? ideal, height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(sizes[0]))
        subviews[2].place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing, proposal: ProposedViewSize(sizes[2]))
        let lowest = bounds.minX + sizes[0].width + spacing
        let highest = bounds.maxX - sizes[2].width - spacing - sizes[1].width
        let centered = bounds.midX - sizes[1].width / 2
        let x = highest < lowest ? lowest : min(max(centered, lowest), highest)
        subviews[1].place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(sizes[1]))
    }
}

// MARK: - Toolbar buttons

struct StudioToolbarIcon: View {
    let name: String
    let color: Color

    var body: some View {
        Image(systemName: name)
            .font(BlitzType.symbol(14))
            .foregroundStyle(color)
            .frame(width: 32, height: 28)
    }
}

private struct StudioPanelToggle: View {
    enum Panel {
        case inputs
        case inspector
    }

    let panel: Panel
    @AppStorage(StudioPanels.sourcesHiddenKey) private var sourcesHidden = false
    @AppStorage(StudioPanels.inspectorHiddenKey) private var inspectorHidden = false

    private var isHidden: Binding<Bool> { panel == .inputs ? $sourcesHidden : $inspectorHidden }
    private var name: String { panel == .inputs ? "inputs" : "inspector" }
    private var shortcut: KeyEquivalent { panel == .inputs ? "1" : "2" }

    var body: some View {
        Button {
            isHidden.wrappedValue.toggle()
        } label: {
            StudioToolbarIcon(
                name: panel == .inputs ? "sidebar.left" : "sidebar.right",
                color: isHidden.wrappedValue ? BlitzUI.tertiaryText : BlitzUI.secondaryText
            )
        }
        .buttonStyle(BlitzMenuTriggerStyle(isPresented: false, variant: .borderless))
        .keyboardShortcut(shortcut, modifiers: [.control, .command])
        .help("\(isHidden.wrappedValue ? "Show" : "Hide") \(name) (⌃⌘\(String(shortcut.character)))")
        .accessibilityLabel("\(isHidden.wrappedValue ? "Show" : "Hide") \(name)")
    }
}

/// What the preview shows: guides (never recorded) and whether live previews run while idle.
private struct PreviewOptionsButton: View {
    @Bindable var vm: RecorderViewModel
    @AppStorage(ShortFormSafeZone.preferenceKey) private var showsSafeZones = false
    @State private var isPresented = false

    private var showsSafeZoneOption: Bool { vm.settings.layout == .vertical }
    private var anyGuideOn: Bool {
        vm.settings.showsRuleOfThirdsOverlay || (showsSafeZoneOption && showsSafeZones)
    }

    private var iconColor: Color {
        if !vm.isLivePreviewEnabled { return BlitzUI.warning }
        return anyGuideOn ? BlitzUI.accent : BlitzUI.secondaryText
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            StudioToolbarIcon(name: "squareshape.split.3x3", color: iconColor)
        }
        .buttonStyle(BlitzMenuTriggerStyle(isPresented: isPresented, variant: .borderless))
        .help(vm.isLivePreviewEnabled ? "Preview guides and live preview" : "Live preview is paused")
        .accessibilityLabel("Preview options")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            BlitzMenuList(entries: entries, width: 280, maxHeight: BlitzMenuList.adaptiveMaxHeight) {
                isPresented = false
            }
        }
    }

    private var entries: [BlitzMenuEntry] {
        var entries: [BlitzMenuEntry] = [
            .section("Guides · never recorded"),
            .item(.init(title: "Rule of thirds", subtitle: "Lines to help you frame the shot",
                        systemImage: "squareshape.split.3x3", isSelected: vm.settings.showsRuleOfThirdsOverlay,
                        action: { vm.setRuleOfThirds(!vm.settings.showsRuleOfThirdsOverlay) }))
        ]
        if showsSafeZoneOption {
            entries.append(.item(.init(title: "App safe zones", subtitle: "Where TikTok, Reels and Shorts put buttons",
                                       systemImage: "iphone", isSelected: showsSafeZones,
                                       action: { showsSafeZones.toggle() })))
        }
        entries += [
            .section("Preview"),
            .item(.init(title: "Live preview",
                        subtitle: "Turn off to pause camera, mic and screen previews (⌥⌘L). Recording still works.",
                        systemImage: "livephoto", isSelected: vm.isLivePreviewEnabled,
                        isEnabled: vm.state == .idle,
                        action: { vm.setLivePreviewEnabled(!vm.isLivePreviewEnabled) }))
        ]
        return entries
    }
}

// MARK: - Output capsule

/// Format · quality · readiness, in one capsule. Each part opens its own popover.
private struct StudioOutputCapsule: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        HStack(spacing: 0) {
            FormatSegment(vm: vm)
            CapsuleSeparator()
            QualitySegment(vm: vm)
            CapsuleSeparator()
            ReadinessSegment(vm: vm)
        }
        .padding(2)
        .background {
            RoundedRectangle(cornerRadius: BlitzUI.cardRadius, style: .continuous)
                .fill(BlitzUI.quietFill)
                .overlay { BlitzEdgeHighlight(cornerRadius: BlitzUI.cardRadius) }
        }
        .fixedSize()
    }
}

private struct CapsuleSeparator: View {
    var body: some View {
        Rectangle()
            .fill(BlitzUI.separator)
            .frame(width: 1, height: 14)
            .accessibilityHidden(true)
    }
}

/// One part of the output capsule: a borderless trigger, its radius concentric with the capsule's.
private struct CapsuleSegment<Label: View>: View {
    let isPresented: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .padding(.horizontal, 10)
                .frame(height: 28)
        }
        .buttonStyle(BlitzMenuTriggerStyle(isPresented: isPresented, variant: .borderless))
    }
}

private struct FormatSegment: View {
    @Bindable var vm: RecorderViewModel
    @State private var isPresented = false

    private var layout: CaptureLayout { vm.settings.layout }
    private var isLocked: Bool { vm.state != .idle }

    var body: some View {
        CapsuleSegment(isPresented: isPresented, action: { isPresented.toggle() }) {
            HStack(spacing: 7) {
                Image(systemName: layout.symbolName)
                    .font(BlitzType.symbol(12))
                    .foregroundStyle(BlitzUI.accent)
                Text(layout.formatName)
                    .font(BlitzType.strong)
                    .foregroundStyle(BlitzUI.primaryText)
                Text(layout.ratioTitle)
                    .font(BlitzType.label)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .monospacedDigit()
            }
            .lineLimit(1)
            .opacity(isLocked ? 0.6 : 1)
        }
        .disabled(isLocked)
        .help(isLocked ? "Format is set for this recording" : "Choose the video format")
        .accessibilityLabel("Format, \(layout.formatTitle)")
        .onChange(of: isLocked) { if isLocked { isPresented = false } }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            FormatPicker(selection: layout) { choice in
                vm.setLayout(choice)
                isPresented = false
            }
        }
    }
}

/// Three formats as pictures of their frame, with where each one is used.
private struct FormatPicker: View {
    let selection: CaptureLayout
    let choose: (CaptureLayout) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Format")
                .font(BlitzType.headline)
                .foregroundStyle(BlitzUI.primaryText)
            HStack(alignment: .top, spacing: 6) {
                ForEach(CaptureLayout.allCases, id: \.self) { layout in
                    tile(layout)
                }
            }
        }
        .padding(14)
    }

    private func tile(_ layout: CaptureLayout) -> some View {
        let isSelected = layout == selection
        let shape = RoundedRectangle(cornerRadius: BlitzUI.controlRadius / 2, style: .continuous)
        return Button { choose(layout) } label: {
            VStack(spacing: 8) {
                shape
                    .fill(isSelected ? BlitzUI.accent.opacity(0.22) : BlitzUI.quietFill)
                    .overlay { shape.strokeBorder(isSelected ? BlitzUI.accent : BlitzUI.strongStroke, lineWidth: 1.5) }
                    .aspectRatio(layout.aspectRatio, contentMode: .fit)
                    .frame(width: 64, height: 56)
                VStack(spacing: 2) {
                    Text(layout.formatName)
                        .font(BlitzType.strong)
                        .foregroundStyle(BlitzUI.primaryText)
                    Text(layout.ratioTitle)
                        .font(BlitzType.caption)
                        .foregroundStyle(BlitzUI.secondaryText)
                        .monospacedDigit()
                    Text(layout.formatUse)
                        .font(BlitzType.caption)
                        .foregroundStyle(BlitzUI.tertiaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .frame(width: 108)
            .contentShape(.rect)
        }
        .buttonStyle(BlitzSelectionButtonStyle(isSelected: isSelected))
        .accessibilityLabel(layout.formatTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct QualitySegment: View {
    @Bindable var vm: RecorderViewModel
    @State private var isPresented = false

    private var isLocked: Bool { vm.state != .idle }

    var body: some View {
        CapsuleSegment(isPresented: isPresented, action: { isPresented.toggle() }) {
            HStack(spacing: 5) {
                Text(vm.settings.outputResolution.displayName)
                    .font(BlitzType.strong)
                    .foregroundStyle(BlitzUI.primaryText)
                Text("\(vm.settings.framesPerSecond) fps")
                    .font(BlitzType.label)
                    .foregroundStyle(BlitzUI.secondaryText)
            }
            .monospacedDigit()
            .lineLimit(1)
            .opacity(isLocked ? 0.6 : 1)
        }
        .disabled(isLocked)
        .help(isLocked ? "Quality is set for this recording" : "Choose resolution and frame rate")
        .accessibilityLabel("Recording quality, \(RecordingQualityPresentation(settings: vm.settings).controlLabel)")
        .onChange(of: isLocked) { if isLocked { isPresented = false } }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            qualityPopover
        }
    }

    private var qualityPopover: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Quality")
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
                BlitzUI.sectionLabel("Frame rate")
                BlitzSegmentedPicker(configuration: .init(
                    title: "Frame rate",
                    options: RecordingSettings.supportedFrameRates,
                    selection: Binding(get: { vm.settings.framesPerSecond }, set: { vm.setFrameRate($0) }),
                    label: { "\($0) fps" }
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

    private var resolutionDimensions: String {
        let dimensions = vm.settings.outputResolution.dimensions(for: vm.settings.layout)
        return "\(dimensions.width) × \(dimensions.height) pixels"
    }

    private var frameRateDescription: String {
        switch vm.settings.framesPerSecond {
        case 24: return "Cinematic motion"
        case 60: return "Extra smooth motion, for fast screens and games"
        default: return "Standard motion"
        }
    }
}

// MARK: - Readiness

/// Ready, what to fix, or the running take. Opens a checklist of every input.
private struct ReadinessSegment: View {
    @Bindable var vm: RecorderViewModel
    @State private var isPresented = false

    var body: some View {
        let status = StudioReadiness(vm: vm)
        CapsuleSegment(isPresented: isPresented, action: { isPresented.toggle() }) {
            HStack(spacing: 7) {
                status.indicator
                Text(status.title)
                    .font(status.isTimer ? BlitzType.strong.monospacedDigit() : BlitzType.strong)
                    .foregroundStyle(status.titleColor)
                if let detail = status.detail {
                    Text(detail)
                        .font(BlitzType.label)
                        .foregroundStyle(BlitzUI.secondaryText)
                }
            }
            .lineLimit(1)
        }
        .help("Check every input before you record")
        .accessibilityLabel("Status, \(status.title)")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ReadinessChecklist(vm: vm)
        }
    }
}

@MainActor
private struct StudioReadiness {
    enum Kind {
        case recording, paused, starting, waiting, ready, problems
    }

    let kind: Kind
    let title: String
    let detail: String?

    init(vm: RecorderViewModel) {
        let problems = vm.studioReadinessProblems
        switch vm.state {
        case .recording:
            (kind, title, detail) = (.recording, vm.formattedElapsed, "Recording")
        case .paused:
            (kind, title, detail) = (.paused, vm.formattedElapsed, "Paused")
        case .starting:
            let countdown = vm.session.countdownRemaining.map { "Starting in \($0)" }
            (kind, title, detail) = (.starting, countdown ?? "Starting…", nil)
        case .finishing:
            (kind, title, detail) = (.starting, "Saving…", nil)
        case .idle:
            if let countdown = vm.session.countdownRemaining {
                (kind, title, detail) = (.starting, "Starting in \(countdown)", nil)
            } else if !problems.blocking.isEmpty {
                let count = problems.blocking.count
                (kind, title, detail) = (.problems, count == 1 ? "1 to fix" : "\(count) to fix", nil)
            } else if !problems.waiting.isEmpty {
                (kind, title, detail) = (.waiting, "Getting ready", nil)
            } else {
                (kind, title, detail) = (.ready, "Ready", nil)
            }
        }
    }

    var isTimer: Bool { kind == .recording || kind == .paused }

    var titleColor: Color {
        kind == .problems ? BlitzUI.warning : BlitzUI.primaryText
    }

    @ViewBuilder
    var indicator: some View {
        switch kind {
        case .recording: BlitzStatusDot(tone: .recording, diameter: 8)
        case .paused: Image(systemName: "pause.fill").font(BlitzType.glyph(9)).foregroundStyle(BlitzUI.secondaryText)
        case .starting, .waiting: ProgressView().controlSize(.mini)
        case .ready: BlitzStatusDot(tone: .ready, diameter: 8)
        case .problems: BlitzStatusDot(tone: .warning, diameter: 8)
        }
    }
}

extension RecorderViewModel {
    /// Readiness notices for every input that is on, without duplicates, split into problems you fix and
    /// devices that are still starting.
    var studioReadinessProblems: (blocking: [SourceReadinessNotice], waiting: [SourceReadinessNotice]) {
        var seen = Set<String>()
        let notices = [CaptureSource.screen, .camera, .microphone, .systemAudio]
            .compactMap { sourceReadinessNotice($0) }
            .filter { seen.insert($0.title).inserted }
        return (notices.filter { !$0.isWaiting }, notices.filter(\.isWaiting))
    }
}

/// Every input with what it records and whether it is ready, and the fix when it is not.
private struct ReadinessChecklist: View {
    @Bindable var vm: RecorderViewModel

    private struct Row: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let value: String
        let notice: SourceReadinessNotice?
        let isOff: Bool
        let isMissing: Bool
    }

    private struct SourceRow {
        let id: String
        let source: CaptureSource
        let title: String
        let value: String
    }

    private var rows: [Row] {
        var rows: [Row] = []
        let screenName = vm.hasActiveScreenPickerSelection ? vm.selectedScreenSourceDisplayName : "Nothing picked"
        rows.append(row(.init(id: "screen", source: .screen, title: "Screen", value: screenName)))
        rows.append(row(.init(id: "camera", source: .camera, title: vm.mainCameraTitle, value: vm.selectedCameraDisplayName)))
        rows += vm.cameraAngles.map { angle in
            Row(id: "angle-\(angle.deviceID)", symbol: BlitzSymbols.camera, title: angle.name, value: angle.deviceName,
                notice: nil, isOff: false, isMissing: !angle.isConnected)
        }
        rows.append(row(.init(id: "microphone", source: .microphone, title: vm.mainMicrophoneTitle,
                              value: vm.selectedMicrophoneDisplayName)))
        rows += vm.microphoneTracks.map { track in
            Row(id: "mic-\(track.deviceID)", symbol: BlitzSymbols.microphone, title: track.name, value: track.deviceName,
                notice: nil, isOff: false, isMissing: !track.isConnected)
        }
        rows.append(row(.init(id: "system-audio", source: .systemAudio, title: "Mac audio", value: "Sound from your apps")))
        return rows
    }

    private func row(_ request: SourceRow) -> Row {
        let isOff = !vm.isSourceConfigured(request.source)
        return Row(
            id: request.id,
            symbol: request.source.symbolName,
            title: request.title,
            value: isOff ? (request.source.isAudioSource ? "Muted" : "Not recorded") : request.value,
            notice: isOff ? nil : vm.sourceReadinessNotice(request.source),
            isOff: isOff,
            isMissing: false
        )
    }

    private var heading: String {
        switch vm.state {
        case .recording, .paused: return "Recording"
        case .starting, .finishing: return "Getting ready"
        case .idle:
            let count = vm.studioReadinessProblems.blocking.count
            return count == 0 ? "Ready to record" : count == 1 ? "1 thing to fix" : "\(count) things to fix"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(heading)
                .font(BlitzType.headline)
                .foregroundStyle(BlitzUI.primaryText)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(rows) { row in
                    rowView(row)
                }
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private func rowView(_ row: Row) -> some View {
        HStack(spacing: 10) {
            Image(systemName: row.symbol)
                .font(BlitzType.symbol(13))
                .foregroundStyle(row.isOff ? BlitzUI.tertiaryText : BlitzUI.secondaryText)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(BlitzType.label)
                    .foregroundStyle(row.isOff ? BlitzUI.secondaryText : BlitzUI.primaryText)
                Text(row.notice?.title ?? (row.isMissing ? "\(row.value) · unplugged" : row.value))
                    .font(BlitzType.caption)
                    .foregroundStyle(row.notice.map { $0.isWaiting ? BlitzUI.secondaryText : BlitzUI.warning }
                        ?? (row.isMissing ? BlitzUI.warning : BlitzUI.secondaryText))
                    .truncationMode(.middle)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            trailing(row)
        }
        .frame(minHeight: 38)
        .help(row.notice?.detail ?? "")
    }

    @ViewBuilder
    private func trailing(_ row: Row) -> some View {
        if let notice = row.notice {
            if let action = notice.action {
                Button(action.shortTitle) { vm.resolveSourceReadiness(action) }
                    .blitzButton(.secondary)
                    .controlSize(.small)
                    .disabled(vm.isRequestingPermissions)
                    .help(action.title)
            } else if notice.isWaiting {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(BlitzType.glyph(11))
                    .foregroundStyle(notice.color)
            }
        } else if row.isMissing {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(BlitzType.glyph(11))
                .foregroundStyle(BlitzUI.warning)
        } else if !row.isOff {
            Image(systemName: "checkmark.circle.fill")
                .font(BlitzType.glyph(13))
                .foregroundStyle(BlitzUI.accent)
                .accessibilityLabel("Ready")
        }
    }
}

#if DEBUG
#Preview("Format picker") {
    FormatPicker(selection: .horizontal) { _ in }
        .background(BlitzUI.panelBackground)
}
#endif
