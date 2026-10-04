import AppKit
import SwiftUI

enum RecordingHUDAnchor: String, CaseIterable {
    case topCenter, topLeft, topRight, bottomLeft, bottomRight

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
        case .topCenter: frame.midX - size.width / 2
        case .topLeft, .bottomLeft: frame.minX + margin
        case .topRight, .bottomRight: frame.maxX - size.width - margin
        }
        let y = isBottom ? frame.minY + margin : frame.maxY - size.height - margin
        return CGPoint(x: x.rounded(), y: y.rounded())
    }

    struct NearestRequest {
        let center: CGPoint
        let visibleFrame: CGRect
    }

    static func nearest(_ request: NearestRequest) -> RecordingHUDAnchor {
        let frame = request.visibleFrame
        let points: [(RecordingHUDAnchor, CGPoint)] = [
            (.topCenter, CGPoint(x: frame.midX, y: frame.maxY)),
            (.topLeft, CGPoint(x: frame.minX, y: frame.maxY)),
            (.topRight, CGPoint(x: frame.maxX, y: frame.maxY)),
            (.bottomLeft, CGPoint(x: frame.minX, y: frame.minY)),
            (.bottomRight, CGPoint(x: frame.maxX, y: frame.minY))
        ]
        return points.min { lhs, rhs in
            hypot(lhs.1.x - request.center.x, lhs.1.y - request.center.y)
                < hypot(rhs.1.x - request.center.x, rhs.1.y - request.center.y)
        }?.0 ?? .topCenter
    }
}

@MainActor
@Observable
final class RecordingHUDModel {
    var anchor: RecordingHUDAnchor {
        didSet { UserDefaults.standard.set(anchor.rawValue, forKey: Self.anchorKey) }
    }
    var isHovering = false
    var openPopovers = 0
    var isDragging = false

    var isExpanded: Bool { (isHovering || openPopovers > 0) && !isDragging }

    private static let anchorKey = "recordingHUD.anchor"

    init() {
        anchor = UserDefaults.standard.string(forKey: Self.anchorKey).flatMap(RecordingHUDAnchor.init) ?? .topCenter
    }
}

@MainActor
final class RecordingHUDController {
    private let viewModel: RecorderViewModel
    private let model = RecordingHUDModel()
    private var panel: NSPanel?
    private var screen: NSScreen?
    private var contentSize = CGSize(width: 220, height: 40)
    private var dragOffset: CGPoint?
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
        panel.isMovable = false
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
        let origin = model.anchor.origin(.init(size: contentSize, visibleFrame: visible, margin: Self.margin))
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
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        if dragOffset == nil {
            dragOffset = CGPoint(x: mouse.x - panel.frame.minX, y: mouse.y - panel.frame.minY)
            model.isDragging = true
        }
        guard let offset = dragOffset else { return }
        panel.setFrameOrigin(NSPoint(x: mouse.x - offset.x, y: mouse.y - offset.y))
    }

    private func dragEnded() {
        dragOffset = nil
        model.isDragging = false
        guard let panel else { return }
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        screen = NSScreen.screens.first { $0.frame.contains(center) } ?? screen
        guard let visible = screen?.visibleFrame else { return }
        model.anchor = RecordingHUDAnchor.nearest(.init(center: center, visibleFrame: visible))
        place(animated: true)
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
    @State private var isIdle = false
    @State private var collapseTask: Task<Void, Never>?
    @State private var idleTask: Task<Void, Never>?

    private var hasPrompt: Bool {
        vm.autoSwitchNotice != nil || (vm.suggestedScreenSource != nil && vm.state == .recording)
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
        .onAppear(perform: scheduleIdle)
        .environment(\.colorScheme, .dark)
        .animation(.spring(duration: 0.28, bounce: 0.12), value: model.isExpanded)
        .animation(.easeOut(duration: 0.18), value: hasPrompt)
        .animation(.easeOut(duration: 0.4), value: isIdle)
    }

    private func hover(_ hovering: Bool) {
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
        HStack(spacing: 10) {
            status
            if vm.settings.enabledSources.contains(.microphone) {
                RecordingHUDMeter(levels: vm.micLevels, isActive: vm.state == .recording)
                    .help(vm.selectedMicrophoneDisplayName)
            }
            if isWide { Spacer(minLength: 8) }
            controls
        }
        .padding(.leading, 14)
        .padding(.trailing, 5)
        .frame(height: 40)
        .contentShape(.rect)
        .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { _ in actions.dragChanged() }
            .onEnded { _ in actions.dragEnded() })
        .help("Drag to move")
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
        if let notice = vm.autoSwitchNotice {
            promptRow {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(BlitzUI.mint)
                Text(notice).foregroundStyle(BlitzUI.primaryText).lineLimit(1)
                Spacer(minLength: 0)
            }
        } else if let suggestion = vm.suggestedScreenSource, vm.state == .recording {
            promptRow {
                Text("Record \(suggestion.applicationName ?? suggestion.displayName)?")
                    .foregroundStyle(BlitzUI.primaryText)
                    .lineLimit(1)
                    .help(suggestion.displayName)
                Spacer(minLength: 8)
                Button("Keep", action: vm.dismissScreenSuggestion)
                    .blitzButton(.quiet)
                    .controlSize(.small)
                Button("Switch", action: vm.acceptScreenSuggestion)
                    .blitzButton(.accent)
                    .controlSize(.small)
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
            : "Record whichever window you bring to the front")
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

private struct RecordingHUDMeter: View {
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

private struct RecordingHUDIconButton: View {
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
                Image(systemName: configuration.symbol)
                    .font(BlitzType.symbol(12))
                    .foregroundStyle(BlitzUI.secondaryText)
                    .frame(width: 20)
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

private struct RecordingHUDDot: View {
    @State private var dimmed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(BlitzUI.recordRed)
            .frame(width: 8, height: 8)
            .opacity(dimmed ? 0.35 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dimmed = true }
            }
            .accessibilityHidden(true)
    }
}
