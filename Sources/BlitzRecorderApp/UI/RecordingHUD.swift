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

struct RecordingHUDPickerRow: View {
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
