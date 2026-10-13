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
            .background {
                if isSelected {
                    BlitzSelectedBackground(cornerRadius: BlitzUI.controlRadius)
                } else {
                    RoundedRectangle(cornerRadius: BlitzUI.controlRadius, style: .continuous)
                        .fill(isEnabled && isHovering ? BlitzUI.quietFill : Color.clear)
                }
            }
            .contentShape(.rect(cornerRadius: BlitzUI.controlRadius))
            .blitzFocusRing(cornerRadius: BlitzUI.controlRadius)
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
                        .font(BlitzType.label)
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
                        .symbolVariant(configuration.isSelected ? .fill : .none)
                        .foregroundStyle(configuration.isSelected ? BlitzUI.accent : BlitzUI.secondaryText)
                }
                Text(configuration.title)
                    .font(configuration.symbolPlacement == .above ? BlitzType.footnote : controlSize == .large ? BlitzType.control(13) : BlitzType.captionEmphasis)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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
        var help: (Value) -> String? = { _ in nil }
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
                .help(configuration.help(value) ?? "")
            }
        }
        .blitzTabGroup()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(configuration.title)
    }
}

struct BlitzToolTabBar<Value: Hashable>: View {
    struct Configuration {
        let title: String
        let options: [Value]
        let selection: Value
        let label: (Value) -> String
        let symbolName: (Value) -> String
        let help: (Value) -> String
        let isOptionEnabled: (Value) -> Bool
        let select: (Value) -> Void
    }

    let configuration: Configuration

    /// A labeled tool rail on the inspector's outer edge (as in Descript, Riverside, VEED):
    /// every tool keeps its name, and the rail scales to any number of tools without crowding.
    static var railWidth: CGFloat { 64 }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 2) {
                ForEach(configuration.options, id: \.self) { option in
                    let isSelected = configuration.selection == option
                    Button { configuration.select(option) } label: {
                        VStack(spacing: 4) {
                            BlitzSymbol(configuration: .init(name: configuration.symbolName(option), size: 18))
                                .symbolVariant(isSelected ? .fill : .none)
                                .foregroundStyle(isSelected ? BlitzUI.accent : BlitzUI.secondaryText)
                            Text(configuration.label(option))
                                .font(BlitzType.footnote)
                                .foregroundStyle(isSelected ? BlitzUI.primaryText : BlitzUI.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(width: Self.railWidth - 12, height: 50)
                        .contentShape(.rect)
                    }
                    .buttonStyle(BlitzSelectionButtonStyle(isSelected: isSelected))
                    .disabled(!configuration.isOptionEnabled(option))
                    .help(configuration.help(option) == configuration.label(option)
                          ? configuration.label(option)
                          : "\(configuration.label(option)): \(configuration.help(option))")
                    .accessibilityLabel(configuration.label(option))
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
            .padding(.vertical, 10)
            .frame(width: Self.railWidth)
        }
        .scrollIndicators(.never)
        .frame(width: Self.railWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(BlitzUI.insetWell)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(configuration.title)
    }
}

private struct BlitzTabGroupModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(3)
            .background(BlitzUI.insetWell, in: .rect(cornerRadius: BlitzUI.controlRadius + 3, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: BlitzUI.controlRadius + 3, style: .continuous)
                    .strokeBorder(BlitzUI.separator, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

private struct BlitzFocusRing: View {
    let cornerRadius: CGFloat
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius + 3, style: .continuous)
            .strokeBorder(isFocused ? BlitzUI.accent : .clear, lineWidth: 2)
            .padding(-3)
            .allowsHitTesting(false)
    }
}

extension View {
    func blitzFocusRing(cornerRadius: CGFloat) -> some View {
        overlay { BlitzFocusRing(cornerRadius: cornerRadius) }
    }

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
