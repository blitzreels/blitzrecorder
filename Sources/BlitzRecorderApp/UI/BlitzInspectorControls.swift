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
                    .font(BlitzType.captionEmphasis)
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
                            .font(controlSize == .large ? BlitzType.body : BlitzType.caption)
                            .foregroundStyle(controlSize == .large ? BlitzUI.supportingText : BlitzUI.secondaryText)
                    }
                    Image(systemName: configuration.isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(BlitzType.glyph(controlSize == .large ? 11 : 9))
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

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(configuration.title)
                .font(BlitzType.section)
                .foregroundStyle(BlitzUI.primaryText)
            Spacer(minLength: 0)
            if let detail = configuration.detail {
                Text(detail)
                    .font(BlitzType.caption)
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
                .font(controlSize == .large ? BlitzType.section : BlitzType.captionEmphasis)
                .foregroundStyle(controlSize == .large ? BlitzUI.supportingText : BlitzUI.secondaryText)
                .frame(width: controlSize == .large ? 70 : 64, alignment: .leading)
            Slider(
                value: steppedValue,
                in: configuration.range,
                onEditingChanged: configuration.onEditingChanged
            )
            .controlSize(.small)
            .tint(BlitzUI.accent)
            .accessibilityLabel(configuration.title)
            .accessibilityValue(configuration.valueLabel)
            .accessibilityAction(named: "Reset", configuration.onReset)
            Text(configuration.valueLabel)
                .font((controlSize == .large ? BlitzType.label : BlitzType.captionEmphasis).monospacedDigit())
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

    private var steppedValue: Binding<Double> {
        Binding(
            get: { configuration.value.wrappedValue },
            set: { proposed in
                let step = configuration.step
                let snapped = step > 0 ? (proposed / step).rounded() * step : proposed
                configuration.value.wrappedValue = min(configuration.range.upperBound, max(configuration.range.lowerBound, snapped))
            }
        )
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
                        .font(BlitzType.captionEmphasis)
                        .foregroundStyle(BlitzUI.secondaryText)
                    Text(configuration.selection.displayName)
                        .font(BlitzType.label)
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
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    BlitzInspectorHeading(configuration: .init(title: "Background", detail: nil))
                    BlitzBackgroundPalette(
                        configuration: .init(
                            selection: configuration.selection,
                            onSelect: configuration.onSelect
                        ))
                }
                .padding(16)
            }
            .scrollIndicators(.never)
            .frame(width: 320, height: 560)
        }
    }
}

/// A few backgrounds one click away, plus the full chooser behind More.
struct EditorBackgroundSwatches: View {
    let configuration: BlitzBackgroundPalette.Configuration
    @State private var showsAll = false

    private static let featured: [CanvasBackgroundStyle] = [
        .macOSSonoma, .macOSRadialSky, .aurora, .ocean, .midnight, .graphite,
    ]

    private var swatches: [CanvasBackgroundStyle] {
        let featured = Self.featured
        guard !featured.contains(configuration.selection) else { return featured }
        return [configuration.selection] + featured.dropLast()
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(swatches, id: \.self) { style in
                let isSelected = style == configuration.selection
                Button { configuration.onSelect(style) } label: {
                    CanvasBackgroundSwatchCache.image(style)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .clipShape(.rect(cornerRadius: BlitzUI.controlRadius - 3))
                        .padding(3)
                        .background {
                            if isSelected { BlitzSelectedBackground(cornerRadius: BlitzUI.controlRadius) }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(style.displayName)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                .help(style.displayName)
                .pointingHandCursor()
            }
            Button("More") { showsAll.toggle() }
                .blitzButton(.quiet)
                .controlSize(.small)
                .fixedSize()
                .help("All backgrounds")
                .popover(isPresented: $showsAll, arrowEdge: .leading) {
                    ScrollView {
                        BlitzBackgroundPalette(configuration: configuration).padding(16)
                    }
                    .scrollIndicators(.never)
                    .frame(width: 320, height: 560)
                }
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
        CanvasBackgroundChooser(configuration: .init(selection: configuration.selection, onSelect: configuration.onSelect))
    }
}
