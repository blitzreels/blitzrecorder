import AppKit
import SwiftUI

enum BlitzUI {
    static let mint = Color(red: 0.09, green: 1.0, blue: 0.65)
    static let orange = Color(red: 1.0, green: 0.66, blue: 0.16)
    /// The single red in the UI — reserved for the record button only.
    static let recordRed = Color(red: 1.0, green: 0.27, blue: 0.27)
    /// Amber for No-access / Waiting / needs-recovery states only. Never a selected accent.
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.22)
    static let panelStroke = Color.white.opacity(0.10)
    /// The near-black canvas surround behind the (intentionally dark) NSView preview stage.
    /// A single named token so the literal isn't duplicated across the center column.
    static let canvasBackground = Color(red: 0.035, green: 0.035, blue: 0.043)
    static let quietFill = Color.white.opacity(0.045)
    /// Selected-surface fill. Brighter than the neutral fills so selection reads on
    /// its own, now that surfaces no longer draw a mint outline.
    static let selectedFill = Color.white.opacity(0.16)
    static let controlFill = Color.white.opacity(0.055)
    /// Canonical device-card / inspector-card surface fill (flat, over the .regularMaterial rail).
    static let cardFill = Color.white.opacity(0.055)
    static let separator = Color.white.opacity(0.08)

    /// Level-meter bar color. Active feeds use mint; idle feeds fall back to dim white.
    static func levelColor(active: Bool) -> Color {
        active ? mint : Color.white.opacity(0.3)
    }

    static func sectionLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.62))
                .frame(width: 16, height: 16)

            Text(title.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(1)
        }
    }
}

struct BlitzIconTile: View {
    let symbolName: String
    let isSelected: Bool
    var icon: NSImage? = nil
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? BlitzUI.mint.opacity(0.16) : BlitzUI.controlFill)
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size * 0.68, height: size * 0.68)
                    .clipShape(.rect(cornerRadius: 4))
            } else {
                Image(systemName: symbolName)
                    .font(.system(size: max(10, size * 0.43), weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? BlitzUI.mint : .white.opacity(0.58))
            }
        }
        .frame(width: size, height: size)
    }
}

enum BlitzStatusTone: Equatable {
    case live
    case ready
    case warning
    case muted

    var color: Color {
        switch self {
        case .live, .ready: return BlitzUI.mint
        case .warning: return BlitzUI.warning
        case .muted: return Color.white.opacity(0.3)
        }
    }
}

/// Connected-by-presence status indicator. A small colored dot with an optional
/// soft glow ring when live. Replaces ad-hoc green/amber dots + textual status.
struct BlitzStatusDot: View {
    var tone: BlitzStatusTone
    var diameter: CGFloat = 7

    var body: some View {
        Circle()
            .fill(tone.color)
            .frame(width: diameter, height: diameter)
            .overlay {
                if tone == .live {
                    Circle()
                        .stroke(tone.color.opacity(0.35), lineWidth: diameter * 0.6)
                        .blur(radius: 1.2)
                }
            }
    }
}

/// Reusable horizontal audio level meter, shared by the Devices mic card and the audio inspector.
struct BlitzLevelMeter: View {
    let levels: TrackLevels
    let active: Bool

    var body: some View {
        Canvas { context, size in
            let values = levels.levels
            guard !values.isEmpty else { return }

            let recentMax = max(0.08, (values.suffix(16).max() ?? 0) * 0.86)
            let barCount = values.count
            let spacing: CGFloat = 1
            let barWidth = max(1.5, (size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount))
            let centerY = size.height / 2
            let color = BlitzUI.levelColor(active: active)

            for (i, raw) in values.enumerated() {
                let normalized = raw > 0.003 ? max(0.04, min(1, raw / recentMax)) : 0.02
                let h = max(1.5, CGFloat(normalized) * size.height)
                let x = CGFloat(i) * (barWidth + spacing)
                let rect = CGRect(x: x, y: centerY - h / 2, width: barWidth, height: h)
                let alpha = 0.25 + 0.7 * CGFloat(normalized)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .color(color.opacity(alpha))
                )
            }
        }
    }
}

struct BlitzSelectedSurface: ViewModifier {
    let isSelected: Bool
    var cornerRadius: CGFloat = 10

    func body(content: Content) -> some View {
        // Flat fill, no outline. Selected = brighter fill; the mint comes from the
        // icon/label inside the row (keeps "mint = selected" without a border).
        content
            .background(isSelected ? BlitzUI.selectedFill : BlitzUI.quietFill, in: .rect(cornerRadius: cornerRadius))
    }
}

extension View {
    func blitzSelectedSurface(isSelected: Bool, cornerRadius: CGFloat = 10) -> some View {
        modifier(BlitzSelectedSurface(isSelected: isSelected, cornerRadius: cornerRadius))
    }
}

// MARK: - Glass dropdown menu

/// A single selectable row in a `BlitzGlassMenu`.
struct BlitzMenuItem {
    var title: String
    var subtitle: String?
    var systemImage: String
    var icon: NSImage?
    var isSelected: Bool
    var isDestructive: Bool
    var action: () -> Void

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        icon: NSImage? = nil,
        isSelected: Bool = false,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.icon = icon
        self.isSelected = isSelected
        self.isDestructive = isDestructive
        self.action = action
    }
}

/// One entry in a `BlitzGlassMenu` — a tappable item, a divider, or a section caption.
enum BlitzMenuEntry {
    case item(BlitzMenuItem)
    case divider
    case section(String)
}

/// A dropdown that matches the Liquid Glass kit instead of the system `Menu`.
/// The trigger is a standard bordered (glass) button; the list is presented in a
/// `.popover` (so it escapes the Devices `ScrollView` clip) with kit-styled rows.
/// Built on a plain button + popover rather than `Menu` on purpose: `Menu`'s gesture
/// recognizers fight the `.draggable` device cards, which made the old menus flicker shut.
struct BlitzGlassMenu<Label: View>: View {
    let entries: [BlitzMenuEntry]
    var menuWidth: CGFloat = 240
    @ViewBuilder var label: () -> Label

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            label()
        }
        .buttonStyle(.bordered)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            BlitzGlassMenuList(entries: entries, width: menuWidth) {
                isPresented = false
            }
            .preferredColorScheme(.dark)
        }
    }
}

private struct BlitzGlassMenuList: View {
    let entries: [BlitzMenuEntry]
    let width: CGFloat
    let dismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    switch entry {
                    case .item(let item):
                        BlitzGlassMenuRow(item: item, dismiss: dismiss)
                    case .divider:
                        Divider()
                            .overlay(BlitzUI.separator)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                    case .section(let title):
                        Text(title.uppercased())
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(0.6)
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                            .padding(.bottom, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(6)
        }
        .scrollIndicators(.visible)
        .frame(width: width)
        .frame(maxHeight: 620)
        .background(.regularMaterial)
    }
}

private struct BlitzGlassMenuRow: View {
    let item: BlitzMenuItem
    let dismiss: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button {
            item.action()
            dismiss()
        } label: {
            HStack(spacing: 9) {
                if let icon = item.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                        .clipShape(.rect(cornerRadius: 4))
                } else {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(iconColor)
                        .frame(width: 18, height: 18)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(textColor)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let subtitle = item.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: 8)

                if item.isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(BlitzUI.mint)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovering ? Color.white.opacity(0.09) : .clear, in: .rect(cornerRadius: 7))
            .contentShape(.rect(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .pointingHandCursor()
    }

    private var textColor: Color {
        item.isDestructive ? BlitzUI.warning : .white.opacity(0.9)
    }

    private var iconColor: Color {
        item.isDestructive ? BlitzUI.warning : .white.opacity(0.6)
    }
}
