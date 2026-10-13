import SwiftUI

enum BlitzButtonEmphasis {
    case accent
    case emphasized
    case secondary
    case quiet
    case record
    case dock

    var isDockControl: Bool { self == .record || self == .dock }
}

enum BlitzControlMetrics {
    static let radius: CGFloat = 10
    static let dockHeight: CGFloat = 44
    static let prominentDockHeight: CGFloat = 56
    static let dockRadius: CGFloat = BlitzUI.cardRadius
    static let rowHeight: CGFloat = 38
    static let toolbarHeight: CGFloat = 38
    static let detailedRowHeight: CGFloat = 64
    static let menuPadding: CGFloat = 8
    static let sectionHeight: CGFloat = 30
    static let dividerHeight: CGFloat = 11

    static func height(_ size: ControlSize) -> CGFloat {
        switch size {
        case .mini: 24
        case .small: 28
        case .large, .extraLarge: 40
        default: 34
        }
    }

    static func fontSize(_ size: ControlSize) -> CGFloat {
        switch size {
        case .mini, .small: 11
        case .large, .extraLarge: 13
        default: 12
        }
    }

    static func horizontalPadding(_ size: ControlSize) -> CGFloat {
        switch size {
        case .mini, .small: 8
        case .large, .extraLarge: 16
        default: 10
        }
    }
}

struct BlitzButtonStyle: ButtonStyle {
    let emphasis: BlitzButtonEmphasis
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @State private var isHovering = false

    init(_ emphasis: BlitzButtonEmphasis) {
        self.emphasis = emphasis
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(emphasis.isDockControl
                ? BlitzType.control(controlSize == .extraLarge ? 16 : 13)
                : BlitzType.control(BlitzControlMetrics.fontSize(controlSize)))
            .symbolRenderingMode(.monochrome)
            .symbolVariant(.none)
            .labelStyle(BlitzControlLabelStyle())
            .padding(.horizontal, emphasis.isDockControl
                ? (controlSize == .extraLarge ? 26 : 18)
                : BlitzControlMetrics.horizontalPadding(controlSize))
            .padding(.vertical, 4)
            .frame(minHeight: emphasis.isDockControl
                ? (controlSize == .extraLarge ? BlitzControlMetrics.prominentDockHeight : BlitzControlMetrics.dockHeight)
                : BlitzControlMetrics.height(controlSize))
            .foregroundStyle(foregroundColor(configuration.role))
            .background(fill, in: .rect(cornerRadius: radius, style: .continuous))
            .overlay {
                if emphasis != .quiet {
                    BlitzEdgeHighlight(cornerRadius: radius)
                        .opacity(emphasis == .secondary || emphasis == .dock ? 1 : 0.7)
                }
            }
            .shadow(color: glow, radius: isEnabled ? 6 : 0, y: 2)
            .blitzFocusRing(cornerRadius: radius)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.97 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .opacity(isEnabled ? (configuration.isPressed ? 0.86 : 1) : 0.4)
            .contentShape(.rect(cornerRadius: radius, style: .continuous))
            .onHover { isHovering = $0 }
            .pointingHandCursor()
    }

    private var radius: CGFloat {
        emphasis.isDockControl ? BlitzControlMetrics.dockRadius : BlitzControlMetrics.radius
    }

    private func foregroundColor(_ role: ButtonRole?) -> Color {
        if role == .destructive { return BlitzUI.recordRed }
        switch emphasis {
        case .accent: return BlitzUI.onAccent
        case .emphasized: return BlitzUI.inverseText
        case .secondary: return BlitzUI.primaryText
        case .quiet: return isHovering && isEnabled ? BlitzUI.primaryText : BlitzUI.secondaryText
        case .record: return .white
        case .dock: return BlitzUI.primaryText
        }
    }

    private var fill: AnyShapeStyle {
        let hovered = isHovering && isEnabled
        switch emphasis {
        case .accent:
            return AnyShapeStyle(LinearGradient(colors: [BlitzUI.accentHighlight, BlitzUI.accent],
                                                startPoint: .top, endPoint: .bottom).opacity(hovered ? 0.92 : 1))
        case .emphasized: return AnyShapeStyle(hovered ? BlitzUI.supportingText : BlitzUI.primaryText)
        case .secondary:
            return AnyShapeStyle(LinearGradient(colors: [hovered ? BlitzUI.strongFill : BlitzUI.raisedFillTop,
                                                         hovered ? BlitzUI.hoverFill : BlitzUI.raisedFillBottom],
                                                startPoint: .top, endPoint: .bottom))
        case .quiet: return AnyShapeStyle(hovered ? BlitzUI.quietFill : .clear)
        case .record:
            return AnyShapeStyle(LinearGradient(colors: [BlitzUI.recordRedHighlight, BlitzUI.recordRed],
                                                startPoint: .top, endPoint: .bottom).opacity(hovered ? 1 : 0.94))
        case .dock: return AnyShapeStyle(hovered ? BlitzUI.strongFill : BlitzUI.selectedFill)
        }
    }

    private var glow: Color {
        switch emphasis {
        case .accent: BlitzUI.accentGlow
        case .record: BlitzUI.recordGlow
        case .emphasized, .secondary, .quiet, .dock: .clear
        }
    }
}

/// Icons sit one weight above the label so they never look hairline next to medium text.
struct BlitzControlLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.fontWeight(.semibold)
            configuration.title
        }
    }
}

struct BlitzPressButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.76 : 1) : 0.4)
            .pointingHandCursor()
    }
}

extension View {
    func blitzButton(_ emphasis: BlitzButtonEmphasis) -> some View {
        buttonStyle(BlitzButtonStyle(emphasis))
    }
}
