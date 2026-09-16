import AppKit
import SwiftUI

enum PreviewUnavailableLayout {
    static let regularInset: CGFloat = 16
    static let compactInset: CGFloat = 8
    static let compactWidth: CGFloat = 72
    static let compactHeight: CGFloat = 64

    static func isCompact(_ size: CGSize) -> Bool {
        size.width < compactWidth || size.height < compactHeight
    }

    static func maximumLabelWidth(for containerWidth: CGFloat) -> CGFloat {
        let inset = containerWidth < compactWidth ? compactInset : regularInset
        return max(0, containerWidth - inset * 2)
    }
}

enum PreviewUnavailablePresentation: Equatable {
    case empty
    case loading
    case unavailable

    static func from(message: String) -> Self {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        let text = trimmed.lowercased()
        if text.contains("starting")
            || text.contains("restarting")
            || text.contains("waiting")
            || text.contains("preparing") {
            return .loading
        }
        return .unavailable
    }
}

enum PreviewUnavailableKind {
    case screen
    case camera

    var symbolName: String {
        switch self {
        case .screen: BlitzSymbols.screen
        case .camera: BlitzSymbols.camera
        }
    }
}

/// Empty-state chrome for a preview slot. Hidden unless there is a real message —
/// never a default plate over live video.
final class PreviewUnavailableOverlay: NSView {
    let kind: PreviewUnavailableKind
    private let fillLayer = CALayer()
    private let stack = NSStackView()
    private let iconView = NSImageView()
    private let spinner = NSProgressIndicator()
    private let label = NSTextField(wrappingLabelWithString: "")
    private var labelMaxWidthConstraint: NSLayoutConstraint?
    private(set) var message = ""

    var messageFrameForTesting: CGRect { label.frame }
    var fillFrameForTesting: CGRect { bounds }
    var isShowingMessageForTesting: Bool { !isHidden }

    private var renderedMessage = ""
    private var renderedCompact = false

    init(kind: PreviewUnavailableKind) {
        self.kind = kind
        super.init(frame: .zero)
        wantsLayer = true
        isHidden = true
        layer?.isOpaque = false
        layer?.backgroundColor = .clear

        fillLayer.backgroundColor = NSColor.black.withAlphaComponent(0.42).cgColor
        fillLayer.actions = [
            "bounds": NSNull(),
            "position": NSNull(),
            "frame": NSNull()
        ]
        layer?.addSublayer(fillLayer)

        let symbol = NSImage(systemSymbolName: kind.symbolName, accessibilityDescription: nil)
        iconView.image = symbol?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        )
        iconView.contentTintColor = NSColor.white.withAlphaComponent(0.58)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setContentHuggingPriority(.required, for: .vertical)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.isHidden = true

        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = NSColor.white.withAlphaComponent(0.86)
        label.alignment = .center
        label.maximumNumberOfLines = 3
        label.lineBreakMode = .byWordWrapping
        label.drawsBackground = false
        label.isBezeled = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(spinner)
        stack.addArrangedSubview(label)
        addSubview(stack)

        let labelMaxWidthConstraint = label.widthAnchor.constraint(
            lessThanOrEqualTo: widthAnchor,
            constant: -PreviewUnavailableLayout.regularInset * 2
        )
        self.labelMaxWidthConstraint = labelMaxWidthConstraint
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: PreviewUnavailableLayout.regularInset),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -PreviewUnavailableLayout.regularInset),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            labelMaxWidthConstraint
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(message: String) {
        self.message = message
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        isHidden = trimmed.isEmpty
        guard !trimmed.isEmpty else {
            spinner.stopAnimation(nil)
            renderedMessage = ""
            return
        }
        refresh()
    }

    override func layout() {
        super.layout()
        fillLayer.frame = bounds
        let compact = PreviewUnavailableLayout.isCompact(bounds.size)
        let inset = compact ? PreviewUnavailableLayout.compactInset : PreviewUnavailableLayout.regularInset
        labelMaxWidthConstraint?.constant = -inset * 2
        guard !isHidden else { return }
        let needsRefresh = message != renderedMessage || compact != renderedCompact
        guard needsRefresh else { return }
        refresh()
    }

    private func refresh() {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let compact = PreviewUnavailableLayout.isCompact(bounds.size)
        renderedMessage = message
        renderedCompact = compact
        let presentation = PreviewUnavailablePresentation.from(message: trimmed)
        let loading = presentation == .loading
        spinner.isHidden = !loading
        if loading {
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }
        iconView.isHidden = loading || compact
        label.stringValue = trimmed
        label.font = .systemFont(ofSize: compact ? 11 : 12, weight: .semibold)
        stack.spacing = compact ? 6 : 10
    }
}

struct PreviewSourceUnavailableView: View {
    enum Kind {
        case screen
        case camera
    }

    let kind: Kind
    let message: String
    var isCompact: Bool = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
            VStack(spacing: isCompact ? 6 : 10) {
                accessory
                if !message.isEmpty {
                    Text(message)
                        .font(.system(size: isCompact ? 11 : 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.86))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
            }
            .padding(isCompact ? 8 : 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var accessory: some View {
        switch PreviewUnavailablePresentation.from(message: message) {
        case .loading:
            ProgressView()
                .controlSize(isCompact ? .mini : .small)
                .tint(.white.opacity(0.86))
        case .empty:
            EmptyView()
        case .unavailable:
            if !isCompact {
                BlitzSymbol(configuration: .init(
                    name: kind == .screen ? BlitzSymbols.screen : BlitzSymbols.camera,
                    size: 22
                ))
                .foregroundStyle(Color.white.opacity(0.58))
            }
        }
    }
}

#Preview("Screen unavailable") {
    PreviewSourceUnavailableView(kind: .screen, message: "Screen preview unavailable")
        .frame(width: 420, height: 240)
        .clipShape(.rect(cornerRadius: 10))
}

#Preview("Camera unavailable") {
    PreviewSourceUnavailableView(kind: .camera, message: "Camera unavailable")
        .frame(width: 160, height: 284)
        .clipShape(.rect(cornerRadius: 10))
}
