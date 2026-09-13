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

struct BlitzSelectionButtonStyle: ButtonStyle {
    let isSelected: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? BlitzUI.primaryText : BlitzUI.secondaryText)
            .background(
                isSelected ? BlitzUI.selectedFill : (isEnabled && isHovering ? BlitzUI.quietFill : Color.clear),
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
        }
        .blitzButton(.quiet)
        .accessibilityLabel(configuration.title)
    }
}

private struct BlitzWorkspaceToolbarModifier: ViewModifier {
    @Environment(\.controlSize) private var controlSize

    func body(content: Content) -> some View {
        content
            .frame(height: controlSize == .large || controlSize == .extraLarge ? 56 : 36)
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

enum BlitzTabSymbolPlacement {
    case leading
    case above
}

struct BlitzTab: View {
    struct Configuration {
        let title: String
        let symbolName: String?
        var symbolPlacement: BlitzTabSymbolPlacement = .leading
        let isSelected: Bool
        let expands: Bool
        let action: () -> Void
    }

    let configuration: Configuration
    @Environment(\.controlSize) private var controlSize

    var body: some View {
        Button(action: configuration.action) {
            let layout = configuration.symbolPlacement == .above
                ? AnyLayout(VStackLayout(spacing: 5)) : AnyLayout(HStackLayout(spacing: 6))
            layout {
                if let symbolName = configuration.symbolName {
                    BlitzSymbol(configuration: .init(name: symbolName, size: 16))
                        .foregroundStyle(configuration.isSelected ? BlitzUI.mint : BlitzUI.secondaryText)
                }
                Text(configuration.title)
                    .font(.system(size: configuration.symbolPlacement == .above ? 10 : controlSize == .large ? 12 : 11, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, controlSize == .mini || controlSize == .large ? 6 : 10)
            .frame(maxWidth: configuration.expands ? .infinity : nil)
            .frame(height: configuration.symbolPlacement == .above ? 48 : controlSize == .large ? 40 : 32)
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
        var symbolName: (Value) -> String? = { _ in nil }
        var isOptionEnabled: (Value) -> Bool = { _ in true }
    }

    let configuration: Configuration

    var body: some View {
        HStack(spacing: 2) {
            ForEach(configuration.options, id: \.self) { value in
                BlitzTab(configuration: .init(
                    title: configuration.label(value),
                    symbolName: configuration.symbolName(value),
                    isSelected: configuration.selection.wrappedValue == value,
                    expands: true,
                    action: { configuration.selection.wrappedValue = value }
                ))
                .disabled(!configuration.isOptionEnabled(value))
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

}
