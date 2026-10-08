import AppKit
import SwiftUI

enum RecordingHUDAnchor: String, CaseIterable {
    case topCenter, topLeft, topRight, bottomLeft, bottomRight, free

    var isBottom: Bool { self == .bottomLeft || self == .bottomRight }

    struct PlacementRequest {
        let size: CGSize
        let visibleFrame: CGRect
        let margin: CGFloat
    }

    func origin(_ request: PlacementRequest) -> CGPoint {
        let frame = request.visibleFrame
        let size = request.size
        let margin = request.margin
        let x: CGFloat = switch self {
        case .topCenter, .free: frame.midX - size.width / 2
        case .topLeft, .bottomLeft: frame.minX + margin
        case .topRight, .bottomRight: frame.maxX - size.width - margin
        }
        let y = isBottom ? frame.minY + margin : frame.maxY - size.height - margin
        return CGPoint(x: x.rounded(), y: y.rounded())
    }

    struct PositionRequest {
        let panelFrame: CGRect
        let visibleFrame: CGRect
    }

    struct FreeOriginRequest {
        let topLeft: CGPoint
        let size: CGSize
        let visibleFrame: CGRect
        let margin: CGFloat
    }

    static func freeOrigin(_ request: FreeOriginRequest) -> CGPoint {
        let frame = request.visibleFrame.insetBy(dx: request.margin, dy: request.margin)
        let x = min(max(request.visibleFrame.minX + request.topLeft.x * request.visibleFrame.width, frame.minX), frame.maxX - request.size.width)
        let top = request.visibleFrame.minY + request.topLeft.y * request.visibleFrame.height
        let y = min(max(top - request.size.height, frame.minY), frame.maxY - request.size.height)
        return CGPoint(x: x.rounded(), y: y.rounded())
    }

    static func normalizedTopLeft(_ request: PositionRequest) -> CGPoint {
        CGPoint(
            x: (request.panelFrame.minX - request.visibleFrame.minX) / max(1, request.visibleFrame.width),
            y: (request.panelFrame.maxY - request.visibleFrame.minY) / max(1, request.visibleFrame.height)
        )
    }
}

@MainActor
@Observable
final class RecordingHUDModel {
    var anchor: RecordingHUDAnchor {
        didSet { UserDefaults.standard.set(anchor.rawValue, forKey: Self.anchorKey) }
    }
    var freeTopLeft: CGPoint {
        didSet { UserDefaults.standard.set([freeTopLeft.x, freeTopLeft.y], forKey: Self.freeKey) }
    }
    var isHovering = false
    var isPeeking = false
    var openPopovers = 0
    var isDragging = false {
        didSet {
            if isDragging && !oldValue {
                expansionDuringDrag = isHovering || isPeeking || openPopovers > 0
            } else if !isDragging {
                expansionDuringDrag = nil
            }
        }
    }
    private var expansionDuringDrag: Bool?

    var isExpanded: Bool { expansionDuringDrag ?? (isHovering || isPeeking || openPopovers > 0) }

    private static let anchorKey = "recordingHUD.anchor"
    private static let freeKey = "recordingHUD.freeTopLeft"
    static let taughtKey = "recordingHUD.taughtHover"

    init() {
        anchor = UserDefaults.standard.string(forKey: Self.anchorKey).flatMap(RecordingHUDAnchor.init) ?? .topCenter
        let stored = UserDefaults.standard.array(forKey: Self.freeKey) as? [Double] ?? []
        freeTopLeft = stored.count == 2 ? CGPoint(x: stored[0], y: stored[1]) : CGPoint(x: 0.4, y: 1)
    }
}

@MainActor
final class RecordingHUDController {
    private let viewModel: RecorderViewModel
    private let model = RecordingHUDModel()
    private var panel: NSPanel?
    private var screen: NSScreen?
    private var contentSize = CGSize(width: 220, height: 40)
    private static let margin: CGFloat = 10

    init(viewModel: RecorderViewModel) {
        self.viewModel = viewModel
    }

    func update(for state: RecordingState) {
        switch state {
        case .starting, .recording, .paused:
            show()
        case .idle, .finishing:
            panel?.orderOut(nil)
            model.isHovering = false
            model.openPopovers = 0
        }
    }

    private func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        guard !panel.isVisible else { return }
        screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        place(animated: false)
        panel.orderFrontRegardless()
        teachHoverOnce()
    }

    private func teachHoverOnce() {
        guard !UserDefaults.standard.bool(forKey: RecordingHUDModel.taughtKey) else { return }
        UserDefaults.standard.set(true, forKey: RecordingHUDModel.taughtKey)
        model.isPeeking = true
        Task { @MainActor [model] in
            try? await Task.sleep(for: .seconds(3))
            model.isPeeking = false
        }
    }

    private func makePanel() -> NSPanel {
        let root = RecordingHUDView(vm: viewModel, model: model, actions: .init(
            resize: { [weak self] size in self?.resize(size) },
            dragChanged: { [weak self] in self?.dragChanged() },
            dragEnded: { [weak self] in self?.dragEnded() }
        ))
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: false
        )
        panel.contentView = host
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = true
        panel.title = "Recording controls"
        panel.setAccessibilityLabel("Recording controls")
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.sharingType = .none
        panel.appearance = NSAppearance(named: .darkAqua)
        return panel
    }

    private func resize(_ size: CGSize) {
        guard size.width > 0, size.height > 0, size != contentSize else { return }
        contentSize = size
        guard !model.isDragging else { return }
        place(animated: false)
    }

    private func place(animated: Bool) {
        guard let panel, let visible = (screen ?? panel.screen ?? NSScreen.main)?.visibleFrame else { return }
        let origin = model.anchor == .free
            ? RecordingHUDAnchor.freeOrigin(.init(topLeft: model.freeTopLeft, size: contentSize, visibleFrame: visible, margin: 0))
            : model.anchor.origin(.init(size: contentSize, visibleFrame: visible, margin: Self.margin))
        let frame = NSRect(origin: origin, size: contentSize)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func dragChanged() {
        guard !model.isDragging else { return }
        model.isDragging = true
    }

    private func dragEnded() {
        guard let panel else {
            model.isDragging = false
            return
        }
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        screen = NSScreen.screens.first { $0.frame.contains(center) } ?? screen
        if let visible = screen?.visibleFrame {
            model.freeTopLeft = RecordingHUDAnchor.normalizedTopLeft(.init(
                panelFrame: panel.frame, visibleFrame: visible
            ))
            model.anchor = .free
        }
        model.isDragging = false
        place(animated: false)
    }
}

struct RecordingHUDActions {
    let resize: (CGSize) -> Void
    let dragChanged: () -> Void
    let dragEnded: () -> Void
}

struct RecordingHUDView: View {
    @Bindable var vm: RecorderViewModel
    @Bindable var model: RecordingHUDModel
    let actions: RecordingHUDActions
    @State private var isDragHovering = false
    @State private var isIdle = false
    @State private var collapseTask: Task<Void, Never>?
    @State private var idleTask: Task<Void, Never>?

    private var hasPrompt: Bool {
        vm.unavailableScreenSourceNotice != nil || vm.autoSwitchNotice != nil
            || (vm.suggestedScreenSource != nil && vm.state == .recording)
    }

    private var isWide: Bool { model.isExpanded || hasPrompt }

    var body: some View {
        VStack(spacing: 0) {
            if model.anchor.isBottom {
                if model.isExpanded { details; divider }
                prompt
                bar
            } else {
                bar
                prompt
                if model.isExpanded { divider; details }
            }
        }
        .frame(width: isWide ? 340 : nil)
        .fixedSize()
        .background(RecordingHUDSurface())
        .opacity(isIdle && !isWide ? 0.5 : 1)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { actions.resize($0) }
        .onHover(perform: hover)
        .onChange(of: model.isDragging) { _, dragging in
            if dragging {
                collapseTask?.cancel()
                idleTask?.cancel()
                isIdle = false
            }
        }
        .onAppear(perform: scheduleIdle)
        .environment(\.colorScheme, .dark)
        .animation(.spring(duration: 0.28, bounce: 0.12), value: model.isExpanded)
        .animation(.easeOut(duration: 0.18), value: hasPrompt)
        .animation(.easeOut(duration: 0.4), value: isIdle)
    }

    private func hover(_ hovering: Bool) {
        guard !model.isDragging else { return }
        collapseTask?.cancel()
        idleTask?.cancel()
        isIdle = false
        if hovering {
            model.isHovering = true
            return
        }
        collapseTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            model.isHovering = false
            scheduleIdle()
        }
    }

    private func scheduleIdle() {
        idleTask?.cancel()
        idleTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, !model.isHovering else { return }
            isIdle = true
        }
    }

    private var divider: some View {
        Rectangle().fill(BlitzUI.hoverFill).frame(height: 1).padding(.horizontal, 12)
    }

    private var bar: some View {
        HStack(spacing: 4) {
            HStack(spacing: 10) {
                VStack(spacing: 3) {
                    ForEach(0..<3) { _ in
                        HStack(spacing: 3) {
                            Circle().frame(width: 3, height: 3)
                            Circle().frame(width: 3, height: 3)
                        }
                    }
                }
                .frame(width: 12, height: 18)
                .foregroundStyle(isDragHovering ? BlitzUI.primaryText : BlitzUI.secondaryText)
                .accessibilityHidden(true)
                status
                if vm.settings.enabledSources.contains(.microphone) {
                    RecordingHUDMeter(levels: vm.micLevels, isActive: vm.state == .recording)
                        .help(vm.selectedMicrophoneDisplayName)
                }
                if isWide { Spacer(minLength: 8) }
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
            .background(isDragHovering || model.isDragging ? BlitzUI.hoverFill : BlitzUI.quietFill, in: .capsule)
            .contentShape(.capsule)
            .gesture(WindowDragGesture()
                .onChanged { _ in actions.dragChanged() }
                .onEnded { _ in actions.dragEnded() })
            .allowsWindowActivationEvents(true)
            .blitzCursor(model.isDragging ? .closedHand : .openHand)
            .onHover { isDragHovering = $0 }
            .help("Drag to move recording controls")
            controls
            if !isWide {
                Image(systemName: model.anchor.isBottom ? "chevron.up" : "chevron.down")
                    .font(BlitzType.symbol(9))
                    .foregroundStyle(BlitzUI.tertiaryText)
                    .padding(.trailing, 6)
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 5)
        .frame(height: 40)
        .help(model.isExpanded ? "Drag to move" : "Hover to change scene, screen and mic. Drag to move.")
    }

    private var status: some View {
        HStack(spacing: 7) {
            switch vm.state {
            case .starting:
                ProgressView().controlSize(.mini)
                Text("Starting").foregroundStyle(BlitzUI.supportingText)
            case .paused:
                Image(systemName: "pause.fill")
                    .font(BlitzType.symbol(9))
                    .foregroundStyle(BlitzUI.warning)
                Text(vm.formattedElapsed).foregroundStyle(BlitzUI.supportingText)
            default:
                RecordingHUDDot()
                Text(vm.formattedElapsed).foregroundStyle(BlitzUI.primaryText)
            }
        }
        .font(BlitzType.section.monospacedDigit())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(vm.state == .paused ? "Paused at \(vm.formattedElapsed)" : "Recording \(vm.formattedElapsed)")
    }

    private var controls: some View {
        HStack(spacing: 2) {
            RecordingHUDIconButton(configuration: .init(
                symbol: vm.state == .paused ? "play.fill" : "pause.fill",
                fill: .clear,
                help: vm.state == .paused ? "Resume" : "Pause",
                isEnabled: vm.state == .recording || vm.state == .paused,
                action: vm.togglePause
            ))
            RecordingHUDIconButton(configuration: .init(
                symbol: "stop.fill", fill: BlitzUI.recordRed,
                help: "Stop recording",
                isEnabled: vm.state == .recording || vm.state == .paused,
                action: vm.primaryAction
            ))
        }
    }

    @ViewBuilder
    private var prompt: some View {
        if let missing = vm.unavailableScreenSourceNotice {
            promptRow {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(BlitzUI.recordRed)
                VStack(alignment: .leading, spacing: 4) {
                    Text(missing.title).foregroundStyle(BlitzUI.recordRed)
                    Text(missing.detail).foregroundStyle(BlitzUI.secondaryText)
                        .font(BlitzType.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    BlitzSourcePicker(model: ScreenCaptureSourcePickerModel(vm: vm, enabled: vm.canAdjustScreenCapture).model)
                }
            }
        }
        if let notice = vm.autoSwitchNotice {
            promptRow {
                RecordingSourceAppIcon(binding: notice)
                    .frame(width: 24, height: 24)
                Text("Switching to \(notice.applicationName ?? notice.displayName)…")
                    .foregroundStyle(BlitzUI.primaryText).lineLimit(1)
                Spacer(minLength: 0)
            }
        } else if let suggestion = vm.suggestedScreenSource, vm.state == .recording {
            promptRow {
                VStack(alignment: .leading, spacing: 8) {
                    Text("You changed windows. Record this one?")
                        .foregroundStyle(BlitzUI.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        RecordingSourceAppIcon(binding: suggestion)
                            .frame(width: 24, height: 24)
                        Text(suggestion.displayName)
                            .foregroundStyle(BlitzUI.secondaryText)
                            .lineLimit(2)
                            .help(suggestion.displayName)
                    }
                    HStack {
                        Button("Not now", action: vm.dismissScreenSuggestion)
                            .blitzButton(.quiet)
                            .controlSize(.small)
                        Spacer(minLength: 8)
                        Button("Use this window", action: vm.acceptScreenSuggestion)
                            .blitzButton(.accent)
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private func promptRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) { content() }
            .font(BlitzType.label)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.isPeeking {
                Text("Hover the bar anytime to change scene, screen and mic.")
                    .font(BlitzType.caption)
                    .foregroundStyle(BlitzUI.secondaryText)
            }
            if vm.currentScenes.count > 1 { scenes }
            VStack(spacing: 2) {
                if vm.settings.enabledSources.contains(.screen) {
                    RecordingHUDPickerRow(configuration: .init(
                        symbol: vm.settings.screenSourceBinding?.kind == .display ? "display" : "macwindow",
                        title: "Screen",
                        model: ScreenCaptureSourcePickerModel(vm: vm, enabled: vm.canAdjustScreenCapture).model,
                        openPopovers: $model.openPopovers
                    ))
                    followRow
                }
                if vm.settings.enabledSources.contains(.microphone) {
                    RecordingHUDPickerRow(configuration: .init(
                        symbol: "mic.fill", title: "Microphone",
                        model: MicrophoneSourcePickerModel(vm: vm, enabled: true).model,
                        openPopovers: $model.openPopovers
                    ))
                }
            }
        }
        .padding(12)
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: model.anchor.isBottom ? .bottom : .top)))
    }

    private var scenes: some View {
        let frames = vm.liveSceneThumbnails
        let preview = frames.screen != nil || frames.camera != nil
            ? BlitzScenePreview(screen: frames.screen, camera: frames.camera, background: vm.settings.canvasBackgroundStyle)
            : nil
        return HStack(spacing: 6) {
            ForEach(vm.currentScenes.prefix(4)) { scene in
                let isSelected = vm.selectedSceneID == scene.id
                Button {
                    vm.selectScene(scene.id)
                } label: {
                    VStack(spacing: 5) {
                        BlitzSceneLayoutThumbnail(
                            layout: scene.layout,
                            sceneLayout: isSelected ? vm.settings.sceneLayout : scene.snapshot.sceneLayout,
                            visibleSources: vm.settings.enabledSources.intersection([.screen, .camera])
                                .subtracting(scene.snapshot.hiddenVideoSources),
                            preview: preview
                        )
                        .frame(height: 36)
                        Text(scene.name)
                            .font(BlitzType.footnote)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(isSelected ? BlitzUI.primaryText : BlitzUI.secondaryText)
                            .lineLimit(1)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity)
                    .background(isSelected ? BlitzUI.strongFill : BlitzUI.quietFill,
                                in: .rect(cornerRadius: BlitzUI.controlRadius))
                    .contentShape(.rect)
                }
                .buttonStyle(BlitzPressButtonStyle())
                .disabled(!vm.canSwitchScene && !isSelected)
                .help(scene.name)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private var followRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.swap")
                .font(BlitzType.symbol(12))
                .foregroundStyle(BlitzUI.secondaryText)
                .frame(width: 20)
            Text("Follow active window")
                .font(BlitzType.label)
                .foregroundStyle(BlitzUI.primaryText)
            Spacer(minLength: 8)
            Toggle("Follow active window", isOn: $vm.followsActiveWindow)
                .toggleStyle(.blitzSwitchOnly)
                .controlSize(.mini)
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
        .disabled(vm.settings.screenSourceBinding?.kind == .display)
        .help(vm.settings.screenSourceBinding?.kind == .display
            ? "You're recording a whole display, so every window is already in the video"
            : "On: switch and fit the active window automatically. Off: ask before switching.")
    }
}

private struct RecordingHUDSurface: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(BlitzUI.overlayFill)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(BlitzUI.separator, lineWidth: 1)
            }
    }
}

struct RecordingHUDMeter: View {
    let levels: TrackLevels
    let isActive: Bool

    var body: some View {
        let recent = Array(levels.levels.suffix(5))
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(recent.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(isActive ? BlitzUI.mint : BlitzUI.tertiaryText)
                    .frame(width: 3, height: max(3, CGFloat(min(1, level)) * 16))
            }
        }
        .frame(width: 23, height: 16)
        .animation(.linear(duration: 0.08), value: recent)
        .accessibilityLabel("Microphone level")
    }
}

struct RecordingHUDIconButton: View {
    struct Configuration {
        let symbol: String
        let fill: Color
        let help: String
        let isEnabled: Bool
        let action: () -> Void
    }

    let configuration: Configuration
    @State private var isHovering = false

    var body: some View {
        Button(action: configuration.action) {
            Image(systemName: configuration.symbol)
                .font(BlitzType.symbol(11))
                .foregroundStyle(BlitzUI.primaryText)
                .frame(width: 30, height: 30)
                .background(configuration.fill, in: .circle)
                .background(isHovering ? BlitzUI.selectedFill : .clear, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(BlitzPressButtonStyle())
        .pointingHandCursor(enabled: configuration.isEnabled)
        .disabled(!configuration.isEnabled)
        .onHover { isHovering = $0 }
        .help(configuration.help)
        .accessibilityLabel(configuration.help)
    }
}

private struct RecordingHUDPickerRow: View {
    struct Configuration {
        let symbol: String
        let title: String
        let model: BlitzSourcePickerModel
        let openPopovers: Binding<Int>
    }

    let configuration: Configuration
    @State private var isPresented = false
    @State private var isHovering = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 10) {
                if let icon = configuration.model.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: configuration.symbol)
                        .font(BlitzType.symbol(12))
                        .foregroundStyle(BlitzUI.secondaryText)
                        .frame(width: 20)
                }
                Text(configuration.title)
                    .font(BlitzType.label)
                    .foregroundStyle(BlitzUI.primaryText)
                Spacer(minLength: 8)
                Text(configuration.model.title)
                    .font(BlitzType.body)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 150, alignment: .trailing)
                Image(systemName: "chevron.right")
                    .font(BlitzType.symbol(9))
                    .foregroundStyle(BlitzUI.tertiaryText)
            }
            .padding(.horizontal, 8)
            .frame(height: 34)
            .background(isHovering || isPresented ? BlitzUI.hoverFill : .clear,
                        in: .rect(cornerRadius: BlitzUI.controlRadius))
            .contentShape(.rect)
        }
        .buttonStyle(BlitzPressButtonStyle())
        .pointingHandCursor(enabled: configuration.model.enabled)
        .disabled(!configuration.model.enabled)
        .onHover { isHovering = $0 }
        .help(configuration.model.title)
        .accessibilityLabel(configuration.title)
        .accessibilityValue(configuration.model.title)
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            BlitzSourcePickerPopover(model: configuration.model) { isPresented = false }
                .preferredColorScheme(.dark)
        }
        .onChange(of: isPresented) { _, presented in
            configuration.openPopovers.wrappedValue = max(0, configuration.openPopovers.wrappedValue + (presented ? 1 : -1))
        }
    }
}

struct RecordingHUDDot: View {
    @State private var dimmed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        BlitzStatusDot(tone: .recording, diameter: 8)
            .opacity(dimmed ? 0.35 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dimmed = true }
            }
            .accessibilityHidden(true)
    }
}

private struct RecordingSourceAppIcon: View {
    let binding: ScreenSourceBinding

    var body: some View {
        Group {
            if let icon = ScreenSourceCatalog.appIcon(for: binding) {
                Image(nsImage: icon).resizable().scaledToFit()
            } else {
                Image(systemName: binding.kind == .display ? "display" : "macwindow")
                    .foregroundStyle(BlitzUI.secondaryText)
            }
        }
        .accessibilityHidden(true)
    }
}
