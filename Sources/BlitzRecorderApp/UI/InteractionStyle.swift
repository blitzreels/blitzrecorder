import AppKit
import SwiftUI

private struct BlitzGlassSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let radius = min(cornerRadius, 10)
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

private struct BlitzCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 12
    var selected: Bool = false

    func body(content: Content) -> some View {
        content
            .background(selected ? BlitzUI.selectedFill : BlitzUI.cardFill, in: .rect(cornerRadius: cornerRadius))
    }
}

struct BlitzControlButtonStyle: ButtonStyle {
    let isProminent: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .symbolRenderingMode(.monochrome)
            .symbolVariant(.none)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minHeight: minimumHeight)
            .foregroundStyle(
                isProminent
                    ? Color.black.opacity(0.88)
                    : (configuration.role == .destructive ? BlitzUI.recordRed : BlitzUI.primaryText)
            )
            .background(
                isProminent ? BlitzUI.mint : (isHovering ? BlitzUI.hoverFill : BlitzUI.controlFill),
                in: .rect(cornerRadius: BlitzUI.controlRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: BlitzUI.controlRadius)
                    .strokeBorder(isProminent ? Color.clear : BlitzUI.panelStroke, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.38)
            .contentShape(.rect(cornerRadius: BlitzUI.controlRadius))
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var minimumHeight: CGFloat {
        switch controlSize {
        case .mini: return 24
        case .small: return 28
        case .large, .extraLarge: return 36
        default: return 32
        }
    }
}

struct BlitzSelectionButtonStyle: ButtonStyle {
    let isSelected: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? BlitzUI.primaryText : BlitzUI.secondaryText)
            .background(
                isSelected ? BlitzUI.selectedFill : (isHovering ? BlitzUI.quietFill : Color.clear),
                in: .rect(cornerRadius: BlitzUI.controlRadius)
            )
            .contentShape(.rect(cornerRadius: BlitzUI.controlRadius))
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.38)
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

struct BlitzToolbarButton: View {
    struct Configuration {
        let title: String
        let symbolName: String
        let showsTitle: Bool
        let action: () -> Void
    }

    let configuration: Configuration

    var body: some View {
        Button(action: configuration.action) {
            HStack(spacing: 7) {
                BlitzSymbol(configuration: .init(name: configuration.symbolName, size: 16))
                if configuration.showsTitle {
                    Text(configuration.title)
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 34)
        }
        .buttonStyle(BlitzSelectionButtonStyle(isSelected: false))
        .accessibilityLabel(configuration.title)
        .pointingHandCursor()
    }
}

private struct BlitzWorkspaceToolbarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(height: 36)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(BlitzUI.projectLibraryBackground)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(BlitzUI.separator)
                    .frame(height: 1)
                    .allowsHitTesting(false)
            }
    }
}

struct BlitzTab: View {
    struct Configuration {
        let title: String
        let symbolName: String?
        let isSelected: Bool
        let expands: Bool
        let action: () -> Void
    }

    let configuration: Configuration

    var body: some View {
        Button(action: configuration.action) {
            HStack(spacing: 6) {
                if let symbolName = configuration.symbolName {
                    BlitzSymbol(configuration: .init(name: symbolName, size: 16))
                        .foregroundStyle(configuration.isSelected ? BlitzUI.mint : BlitzUI.secondaryText)
                }
                Text(configuration.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: configuration.expands ? .infinity : nil)
            .frame(height: 32)
        }
        .buttonStyle(BlitzSelectionButtonStyle(isSelected: configuration.isSelected))
        .accessibilityAddTraits(configuration.isSelected ? [.isSelected] : [])
        .pointingHandCursor()
    }
}

struct BlitzSegmentedPicker<Value: Hashable>: View {
    struct Configuration {
        let title: String
        let options: [Value]
        let selection: Binding<Value>
        let label: (Value) -> String
    }

    let configuration: Configuration

    var body: some View {
        HStack(spacing: 2) {
            ForEach(configuration.options, id: \.self) { value in
                BlitzTab(configuration: .init(
                    title: configuration.label(value),
                    symbolName: nil,
                    isSelected: configuration.selection.wrappedValue == value,
                    expands: true,
                    action: { configuration.selection.wrappedValue = value }
                ))
            }
        }
        .blitzTabGroup()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(configuration.title)
    }
}

private struct BlitzTabGroupModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(3)
            .background(BlitzUI.quietFill, in: .rect(cornerRadius: 10))
    }
}

private struct PointingHandCursorModifier: ViewModifier {
    let isEnabled: Bool
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                guard isEnabled else { return }
                guard hovering != isHovering else { return }
                isHovering = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onChange(of: isEnabled) {
                if !isEnabled, isHovering {
                    NSCursor.pop()
                    isHovering = false
                }
            }
            .onDisappear {
                if isHovering {
                    NSCursor.pop()
                    isHovering = false
                }
            }
    }
}

extension View {
    func blitzWorkspaceToolbar() -> some View {
        modifier(BlitzWorkspaceToolbarModifier())
    }

    func blitzTabGroup() -> some View {
        modifier(BlitzTabGroupModifier())
    }

    func blitzGlassSurface(cornerRadius: CGFloat) -> some View {
        modifier(BlitzGlassSurfaceModifier(cornerRadius: cornerRadius))
    }

    func blitzCard(cornerRadius: CGFloat = 12, selected: Bool = false) -> some View {
        modifier(BlitzCardModifier(cornerRadius: cornerRadius, selected: selected))
    }

    @ViewBuilder
    func blitzGlassButton() -> some View {
        self.buttonStyle(BlitzControlButtonStyle(isProminent: false))
    }

    @ViewBuilder
    func blitzProminentGlassButton() -> some View {
        self.buttonStyle(BlitzControlButtonStyle(isProminent: true))
    }

    func pointingHandCursor(enabled: Bool = true) -> some View {
        modifier(PointingHandCursorModifier(isEnabled: enabled))
    }
}
