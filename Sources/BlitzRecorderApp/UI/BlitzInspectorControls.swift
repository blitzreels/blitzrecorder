import SwiftUI

struct BlitzInspectorHeading: View {
    struct Configuration {
        let title: String
        let detail: String?
    }

    let configuration: Configuration

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(configuration.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BlitzUI.primaryText)
            Spacer(minLength: 0)
            if let detail = configuration.detail {
                Text(detail)
                    .font(.system(size: 10, weight: .medium))
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

    var body: some View {
        HStack(spacing: 12) {
            Text(configuration.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(BlitzUI.secondaryText)
                .frame(width: 64, alignment: .leading)
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
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(BlitzUI.primaryText)
                .monospacedDigit()
                .frame(width: 38, alignment: .trailing)
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
                BlitzSymbol(configuration: .init(name: "chevron.right", size: 12))
                    .foregroundStyle(BlitzUI.secondaryText)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(BlitzSelectionButtonStyle(isSelected: isPresented))
        .background(BlitzUI.quietFill, in: .rect(cornerRadius: BlitzUI.controlRadius))
        .pointingHandCursor()
        .accessibilityLabel("Canvas background")
        .accessibilityValue(configuration.selection.displayName)
        .help("Choose a canvas background for this segment")
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
