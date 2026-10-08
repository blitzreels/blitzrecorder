import SwiftUI

enum BlitzButtonEmphasis {
    case accent
    case emphasized
    case secondary
    case quiet
    case record
    case dock
    case prominent

    var isDockControl: Bool { self == .record || self == .dock || self == .prominent }
}

enum BlitzControlMetrics {
    static let radius: CGFloat = 8
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
            .padding(.horizontal, emphasis.isDockControl
                ? (controlSize == .extraLarge ? 24 : 18)
                : BlitzControlMetrics.horizontalPadding(controlSize))
            .padding(.vertical, 4)
            .frame(minHeight: emphasis.isDockControl
                ? (controlSize == .extraLarge ? BlitzControlMetrics.prominentDockHeight : BlitzControlMetrics.dockHeight)
                : BlitzControlMetrics.height(controlSize))
            .foregroundStyle(foregroundColor(configuration.role))
            .background(fill, in: .rect(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(emphasis == .secondary ? BlitzUI.panelStroke : .clear, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .blitzFocusRing(cornerRadius: radius)
            .opacity(isEnabled ? (configuration.isPressed ? 0.76 : 1) : 0.4)
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
        case .accent, .emphasized: return .black.opacity(0.88)
        case .secondary: return BlitzUI.primaryText
        case .quiet: return isHovering && isEnabled ? BlitzUI.primaryText : BlitzUI.secondaryText
        case .record: return .white
        case .dock: return BlitzUI.primaryText
        case .prominent: return .black.opacity(0.88)
        }
    }

    private var fill: Color {
        let hovered = isHovering && isEnabled
        switch emphasis {
        case .accent: return hovered ? BlitzUI.mint.opacity(0.9) : BlitzUI.mint
        case .emphasized: return hovered ? .white : BlitzUI.primaryText
        case .secondary: return hovered ? BlitzUI.hoverFill : BlitzUI.controlFill
        case .quiet: return hovered ? BlitzUI.quietFill : .clear
        case .record: return BlitzUI.recordRed.opacity(hovered ? 1 : 0.9)
        case .dock: return hovered ? BlitzUI.strongFill : BlitzUI.selectedFill
        case .prominent: return hovered ? BlitzUI.mint.opacity(0.9) : BlitzUI.mint
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
