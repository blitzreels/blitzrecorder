import SwiftUI

struct BlitzVisualChoice<Preview: View>: View {
    struct Configuration {
        let title: String
        let help: String
        let isSelected: Bool
        let action: () -> Void
        let preview: () -> Preview
    }

    let configuration: Configuration

    var body: some View {
        Button(action: configuration.action) {
            VStack(spacing: 8) {
                configuration.preview()
                    .frame(height: 52)
                    .clipShape(.rect(cornerRadius: 5))
                    .accessibilityHidden(true)
                Text(configuration.title)
                    .font(.system(size: 11, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(8)
        }
        .buttonStyle(BlitzSelectionButtonStyle(isSelected: configuration.isSelected))
        .accessibilityLabel(configuration.title)
        .accessibilityAddTraits(configuration.isSelected ? .isSelected : [])
        .help(configuration.help)
        .pointingHandCursor()
    }
}

struct BlitzInspectorDisclosure<Content: View>: View {
    struct Configuration {
        let title: String
        let detail: String?
        let isExpanded: Binding<Bool>
        let content: () -> Content
    }

    let configuration: Configuration
    @Environment(\.controlSize) private var controlSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                configuration.isExpanded.wrappedValue.toggle()
            } label: {
                HStack(spacing: 8) {
                    Text(configuration.title)
                        .foregroundStyle(controlSize == .large ? BlitzUI.primaryText : BlitzUI.secondaryText)
                    Spacer(minLength: 0)
                    if let detail = configuration.detail {
                        Text(detail)
                            .font(.system(size: controlSize == .large ? 12 : 10))
                            .foregroundStyle(controlSize == .large ? BlitzUI.supportingText : BlitzUI.secondaryText)
                    }
                    Image(systemName: configuration.isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.system(size: controlSize == .large ? 11 : 9, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .blitzButton(.quiet)
            .accessibilityLabel(configuration.title)
            .accessibilityValue(configuration.isExpanded.wrappedValue ? "Expanded" : "Collapsed")
            if configuration.isExpanded.wrappedValue {
                configuration.content()
            }
        }
    }
}

struct BlitzInspectorHeading: View {
    struct Configuration {
        let title: String
        let detail: String?
    }

    let configuration: Configuration
    @Environment(\.controlSize) private var controlSize

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(configuration.title)
                .font(.system(size: controlSize == .large ? 14 : 12, weight: .semibold))
                .foregroundStyle(BlitzUI.primaryText)
            Spacer(minLength: 0)
            if let detail = configuration.detail {
                Text(detail)
                    .font(.system(size: controlSize == .large ? 12 : 10, weight: .medium))
                    .foregroundStyle(BlitzUI.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

struct BlitzInspectorSlider: View {
    struct Configuration {
        let title: String
        let value: Binding<Double>
        let range: ClosedRange<Double>
        let step: Double
        let valueLabel: String
        let onEditingChanged: (Bool) -> Void
        let onReset: () -> Void
    }

    let configuration: Configuration
    @Environment(\.controlSize) private var controlSize

    var body: some View {
        HStack(spacing: 12) {
            Text(configuration.title)
                .font(.system(size: controlSize == .large ? 13 : 11, weight: .medium))
                .foregroundStyle(controlSize == .large ? BlitzUI.supportingText : BlitzUI.secondaryText)
                .frame(width: controlSize == .large ? 70 : 64, alignment: .leading)
            Slider(
                value: configuration.value,
                in: configuration.range,
                step: configuration.step,
                onEditingChanged: configuration.onEditingChanged
            )
            .controlSize(.small)
            .tint(BlitzUI.mint)
            .accessibilityLabel(configuration.title)
            .accessibilityValue(configuration.valueLabel)
            .accessibilityAction(named: "Reset", configuration.onReset)
            Text(configuration.valueLabel)
                .font(.system(size: controlSize == .large ? 12 : 10, weight: .medium, design: .monospaced))
                .foregroundStyle(BlitzUI.primaryText)
                .monospacedDigit()
                .frame(width: controlSize == .large ? 48 : 38, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 28)
        .contextMenu {
            Button("Reset \(configuration.title.lowercased())", action: configuration.onReset)
        }
    }
}

struct BlitzBackgroundPicker: View {
    let configuration: BlitzBackgroundPalette.Configuration
    @State private var isPresented = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 12) {
                CanvasBackgroundSwatchCache.image(configuration.selection)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 64, height: 40)
                    .clipped()
                    .clipShape(.rect(cornerRadius: BlitzUI.controlRadius - 2))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Background")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(BlitzUI.secondaryText)
                    Text(configuration.selection.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(BlitzUI.primaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                BlitzMenuChevron()
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(BlitzMenuTriggerStyle(isPresented: isPresented))
        .accessibilityLabel("Canvas background")
        .accessibilityValue(configuration.selection.displayName)
        .help("Choose a canvas background for this segment")
        .onChange(of: isEnabled) {
            if !isEnabled { isPresented = false }
        }
        .popover(isPresented: $isPresented, arrowEdge: .leading) {
            VStack(alignment: .leading, spacing: 14) {
                BlitzInspectorHeading(configuration: .init(title: "Background", detail: nil))
                BlitzBackgroundPalette(
                    configuration: .init(
                        selection: configuration.selection,
                        onSelect: {
                            configuration.onSelect($0)
                            isPresented = false
                        }
                    ))
            }
            .padding(16)
            .frame(width: 320)
        }
    }
}

struct BlitzBackgroundPalette: View {
    struct Configuration {
        let selection: CanvasBackgroundStyle
        let onSelect: (CanvasBackgroundStyle) -> Void
    }

    let configuration: Configuration

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 40, maximum: 64), spacing: 8)], spacing: 8) {
            ForEach(CanvasBackgroundStyle.allCases, id: \.self) { style in
                let isSelected = configuration.selection == style
                Button {
                    configuration.onSelect(style)
                } label: {
                    CanvasBackgroundSwatchCache.image(style)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 32)
                        .clipped()
                        .clipShape(.rect(cornerRadius: BlitzUI.controlRadius - 3))
                        .padding(3)
                        .frame(maxWidth: .infinity)
                        .contentShape(.rect)
                }
                .buttonStyle(BlitzSelectionButtonStyle(isSelected: isSelected))
                .overlay {
                    RoundedRectangle(cornerRadius: BlitzUI.controlRadius)
                        .strokeBorder(isSelected ? BlitzUI.mint : BlitzUI.panelStroke, lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .accessibilityLabel(style.displayName)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                .help(style.displayName)
                .pointingHandCursor()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Canvas background")
    }
}
