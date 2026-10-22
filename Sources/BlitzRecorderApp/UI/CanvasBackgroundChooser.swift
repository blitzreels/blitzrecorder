import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CanvasBackgroundChooser: View {
    struct Configuration {
        let selection: CanvasBackgroundStyle
        let onSelect: (CanvasBackgroundStyle) -> Void
    }

    let configuration: Configuration
    @State private var recentImages: [CanvasBackgroundStyle] = []
    @State private var showsColorPicker = false
    @State private var importError: String?

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    private static let darkGradients: [CanvasBackgroundStyle] = [
        .black, .graphite, .midnight, .ocean, .aurora, .nebula,
        .blush, .sunset, .seasonalAutumnSonoma, .dune, .seasonalWinterFrost, .studioPaperWhite
    ]
    private static let brightGradients: [CanvasBackgroundStyle] = [
        .peach, .sorbet, .mint, .sky, .lilac, .citrus, .flamingo, .electric
    ]

    private var selectedBase: CanvasBackgroundStyle { configuration.selection.base }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            customSection
            if !CanvasBackgroundStyle.pickerWallpapers.isEmpty {
                section(.init(title: "Wallpapers", styles: CanvasBackgroundStyle.pickerWallpapers))
            }
            section(.init(title: "Bright", styles: Self.brightGradients))
            section(.init(title: "Dark", styles: Self.darkGradients + legacySelection))
        }
        .onAppear { recentImages = CanvasBackgroundLibrary.recentImages(limit: 6) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Canvas background")
    }

    private var legacySelection: [CanvasBackgroundStyle] {
        let offered = CanvasBackgroundStyle.pickerWallpapers + Self.darkGradients + Self.brightGradients
        guard !selectedBase.isCustom, !offered.contains(selectedBase) else { return [] }
        return [selectedBase]
    }

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            header(title: "Custom", detail: selectedBase.isCustom ? selectedBase.displayName : nil)
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 8) {
                CanvasBackgroundActionTile(configuration: .init(
                    title: "Image", systemImage: "photo.badge.plus", fill: nil,
                    isSelected: false, help: "Use your own picture as the background", action: chooseImage
                ))
                CanvasBackgroundActionTile(configuration: .init(
                    title: "Color", systemImage: "eyedropper",
                    fill: selectedBase.solidColor.map { Color(nsColor: $0) },
                    isSelected: selectedBase.solidColor != nil,
                    help: "Pick any solid color", action: { showsColorPicker = true }
                ))
                .popover(isPresented: $showsColorPicker, arrowEdge: .leading) {
                    CanvasColorPicker(configuration: .init(
                        initial: selectedBase.solidColor ?? CanvasColorPicker.presets[6],
                        onChange: { configuration.onSelect(.solid($0)) }
                    ))
                }
                ForEach(recentImages, id: \.self) { style in
                    swatch(style)
                }
            }
            if configuration.selection.isImageBased {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Blur")
                        .font(BlitzType.label)
                        .foregroundStyle(BlitzUI.supportingText)
                    BlitzSegmentedPicker(configuration: .init(
                        title: "Blur",
                        options: CanvasBackgroundBlur.allCases,
                        selection: Binding(
                            get: { configuration.selection.blur },
                            set: { configuration.onSelect(configuration.selection.withBlur($0)) }
                        ),
                        label: \.title
                    ))
                    .controlSize(.small)
                }
                .padding(.top, 4)
            }
            if let importError {
                Text(importError)
                    .font(BlitzType.caption)
                    .foregroundStyle(BlitzUI.warning)
            }
        }
    }

    private struct Section {
        let title: String
        let styles: [CanvasBackgroundStyle]
    }

    private func section(_ section: Section) -> some View {
        let selected = section.styles.first { $0 == selectedBase }
        return VStack(alignment: .leading, spacing: 8) {
            header(title: section.title, detail: selected?.displayName)
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 8) {
                ForEach(section.styles, id: \.self) { style in
                    swatch(style)
                }
            }
        }
    }

    private func header(title: String, detail: String?) -> some View {
        HStack(spacing: 6) {
            BlitzUI.sectionLabel(title)
            Spacer(minLength: 4)
            if let detail {
                Text(detail)
                    .font(BlitzType.caption)
                    .foregroundStyle(BlitzUI.secondaryText)
            }
        }
    }

    private func swatch(_ style: CanvasBackgroundStyle) -> some View {
        CanvasBackgroundSwatch(configuration: .init(
            style: style,
            isSelected: style == selectedBase,
            action: { configuration.onSelect(style.isImageBased ? style.withBlur(configuration.selection.blur) : style) }
        ))
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Use as background"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let style = try CanvasBackgroundLibrary.importImage(from: url)
            importError = nil
            recentImages = CanvasBackgroundLibrary.recentImages(limit: 6)
            configuration.onSelect(style)
        } catch {
            importError = "Couldn't use that image. Try a PNG, JPEG or HEIC file."
        }
    }
}

struct CanvasBackgroundSwatch: View {
    struct Configuration {
        let style: CanvasBackgroundStyle
        let isSelected: Bool
        let action: () -> Void
    }

    let configuration: Configuration
    @State private var isHovering = false

    var body: some View {
        Button(action: configuration.action) {
            CanvasBackgroundTileFrame(configuration: .init(isSelected: configuration.isSelected, isHovering: isHovering)) {
                CanvasBackgroundSwatchCache.image(configuration.style)
                    .resizable()
                    .scaledToFill()
            }
        }
        .buttonStyle(BlitzPressButtonStyle())
        .onHover { isHovering = $0 }
        .accessibilityLabel(configuration.style.displayName)
        .accessibilityAddTraits(configuration.isSelected ? [.isSelected] : [])
        .help(configuration.style.displayName)
    }
}

private struct CanvasBackgroundActionTile: View {
    struct Configuration {
        let title: String
        let systemImage: String
        let fill: Color?
        let isSelected: Bool
        let help: String
        let action: () -> Void
    }

    let configuration: Configuration
    @State private var isHovering = false

    var body: some View {
        Button(action: configuration.action) {
            CanvasBackgroundTileFrame(configuration: .init(isSelected: configuration.isSelected, isHovering: isHovering)) {
                ZStack {
                    if let fill = configuration.fill {
                        fill
                    } else {
                        BlitzUI.controlFill
                    }
                    VStack(spacing: 3) {
                        Image(systemName: configuration.systemImage)
                            .font(BlitzType.symbol(14))
                        Text(configuration.title)
                            .font(BlitzType.footnote)
                    }
                    .foregroundStyle(configuration.fill == nil ? BlitzUI.primaryText : BlitzUI.onMediaText)
                    .shadow(color: .black.opacity(configuration.fill == nil ? 0 : 0.5), radius: 2)
                }
            }
        }
        .buttonStyle(BlitzPressButtonStyle())
        .onHover { isHovering = $0 }
        .accessibilityLabel(configuration.title)
        .help(configuration.help)
    }
}

private struct CanvasBackgroundTileFrame<Content: View>: View {
    struct Configuration {
        let isSelected: Bool
        let isHovering: Bool
    }

    let configuration: Configuration
    @ViewBuilder let content: () -> Content

    private static var radius: CGFloat { 9 }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { content() }
            .clipShape(.rect(cornerRadius: Self.radius - 3, style: .continuous))
            .padding(3)
            .overlay {
                RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                    .strokeBorder(ringColor, lineWidth: 2)
            }
            .contentShape(.rect(cornerRadius: Self.radius, style: .continuous))
    }

    private var ringColor: Color {
        if configuration.isSelected { return BlitzUI.primaryText }
        return configuration.isHovering ? BlitzUI.tertiaryText : .clear
    }
}
