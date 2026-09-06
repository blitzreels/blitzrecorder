import AppKit
import SwiftUI

enum BlitzSymbols {
    static let screen = "display"
    static let camera = "video"
    static let microphone = "mic"
    static let systemAudio = "speaker.wave.2"
    static let scenes = "rectangle.stack"
    static let layout = "rectangle.split.2x1"
    static let split = "rectangle.split.1x2"
    static let pictureInPicture = "pip"
    static let layers = "square.3.layers.3d"
    static let canvas = "paintpalette"
    static let source = "macwindow"
    static let videoQuality = "play.rectangle"
}

struct BlitzSymbol: View {
    struct Configuration {
        let name: String
        let size: CGFloat
    }

    let configuration: Configuration

    var body: some View {
        Group {
            if let glyph = BlitzGlyphKind(rawValue: configuration.name) {
                BlitzGlyphShape(kind: glyph)
                    .stroke(style: StrokeStyle(
                        lineWidth: max(1.1, configuration.size * 1.6 / 24),
                        lineCap: .round,
                        lineJoin: .round
                    ))
            } else {
                Image(systemName: configuration.name)
                    .font(.system(size: configuration.size * 0.78, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .symbolVariant(.none)
            }
        }
        .frame(width: configuration.size, height: configuration.size)
        .accessibilityHidden(true)
    }
}

enum BlitzGlyphKind: String, CaseIterable {
    case screen = "display"
    case camera = "video"
    case microphone = "mic"
    case systemAudio = "speaker.wave.2"
    case scenes = "rectangle.stack"
    case layout = "rectangle.split.2x1"
    case split = "rectangle.split.1x2"
    case pictureInPicture = "pip"
    case layers = "square.3.layers.3d"
    case source = "macwindow"
    case videoQuality = "play.rectangle"
}

struct BlitzGlyphShape: Shape {
    let kind: BlitzGlyphKind

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch kind {
        case .screen:
            path.addRoundedRect(in: CGRect(x: 3, y: 4, width: 18, height: 13), cornerSize: CGSize(width: 2, height: 2))
            path.move(to: CGPoint(x: 12, y: 17))
            path.addLine(to: CGPoint(x: 12, y: 21))
            path.move(to: CGPoint(x: 8, y: 21))
            path.addLine(to: CGPoint(x: 16, y: 21))
        case .source:
            path.addRoundedRect(in: CGRect(x: 3, y: 4, width: 18, height: 16), cornerSize: CGSize(width: 2, height: 2))
            path.move(to: CGPoint(x: 3, y: 8))
            path.addLine(to: CGPoint(x: 21, y: 8))
        case .videoQuality:
            path.addRoundedRect(in: CGRect(x: 3, y: 5, width: 18, height: 14), cornerSize: CGSize(width: 2, height: 2))
            path.move(to: CGPoint(x: 10, y: 9))
            path.addLine(to: CGPoint(x: 15, y: 12))
            path.addLine(to: CGPoint(x: 10, y: 15))
            path.closeSubpath()
        case .camera:
            path.addRoundedRect(in: CGRect(x: 2.5, y: 5.5, width: 13.5, height: 13), cornerSize: CGSize(width: 3, height: 3))
            path.move(to: CGPoint(x: 16, y: 10))
            path.addLine(to: CGPoint(x: 21.5, y: 7))
            path.addLine(to: CGPoint(x: 21.5, y: 17))
            path.addLine(to: CGPoint(x: 16, y: 14))
        case .microphone:
            path.addRoundedRect(in: CGRect(x: 9, y: 3, width: 6, height: 12), cornerSize: CGSize(width: 3, height: 3))
            path.move(to: CGPoint(x: 6, y: 11))
            path.addLine(to: CGPoint(x: 6, y: 12))
            path.addCurve(to: CGPoint(x: 18, y: 12), control1: CGPoint(x: 6, y: 20), control2: CGPoint(x: 18, y: 20))
            path.addLine(to: CGPoint(x: 18, y: 11))
            path.move(to: CGPoint(x: 12, y: 18))
            path.addLine(to: CGPoint(x: 12, y: 21))
            path.move(to: CGPoint(x: 9, y: 21))
            path.addLine(to: CGPoint(x: 15, y: 21))
        case .systemAudio:
            path.move(to: CGPoint(x: 3, y: 10))
            for point in [
                CGPoint(x: 6, y: 10), CGPoint(x: 11, y: 6), CGPoint(x: 11, y: 18),
                CGPoint(x: 6, y: 14), CGPoint(x: 3, y: 14)
            ] {
                path.addLine(to: point)
            }
            path.closeSubpath()
            path.move(to: CGPoint(x: 15, y: 9))
            path.addCurve(to: CGPoint(x: 15, y: 15), control1: CGPoint(x: 18, y: 10), control2: CGPoint(x: 18, y: 14))
        case .scenes:
            for origin in [CGPoint(x: 3, y: 3), CGPoint(x: 13, y: 3), CGPoint(x: 3, y: 13), CGPoint(x: 13, y: 13)] {
                path.addRoundedRect(
                    in: CGRect(origin: origin, size: CGSize(width: 8, height: 8)),
                    cornerSize: CGSize(width: 2, height: 2)
                )
            }
        case .layout:
            path.addRoundedRect(in: CGRect(x: 3, y: 4, width: 7.5, height: 16), cornerSize: CGSize(width: 2, height: 2))
            path.addRoundedRect(in: CGRect(x: 13.5, y: 4, width: 7.5, height: 16), cornerSize: CGSize(width: 2, height: 2))
        case .split:
            path.addRoundedRect(in: CGRect(x: 3, y: 4, width: 18, height: 6.5), cornerSize: CGSize(width: 2, height: 2))
            path.addRoundedRect(in: CGRect(x: 3, y: 13.5, width: 18, height: 6.5), cornerSize: CGSize(width: 2, height: 2))
        case .pictureInPicture:
            path.addRoundedRect(in: CGRect(x: 3, y: 4, width: 18, height: 16), cornerSize: CGSize(width: 2, height: 2))
            path.addRoundedRect(in: CGRect(x: 12, y: 12, width: 6, height: 5), cornerSize: CGSize(width: 1, height: 1))
        case .layers:
            path.move(to: CGPoint(x: 3, y: 7))
            path.addLine(to: CGPoint(x: 12, y: 3))
            path.addLine(to: CGPoint(x: 21, y: 7))
            path.addLine(to: CGPoint(x: 12, y: 11))
            path.closeSubpath()
            path.move(to: CGPoint(x: 3, y: 12))
            path.addLine(to: CGPoint(x: 12, y: 16))
            path.addLine(to: CGPoint(x: 21, y: 12))
            path.move(to: CGPoint(x: 3, y: 17))
            path.addLine(to: CGPoint(x: 12, y: 21))
            path.addLine(to: CGPoint(x: 21, y: 17))
        }
        return path.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
            .offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

enum BlitzUI {
    static let mint = Color(red: 0.09, green: 1.0, blue: 0.65)
    static let orange = Color(red: 1.0, green: 0.66, blue: 0.16)
    static let recordRed = Color(red: 1.0, green: 0.27, blue: 0.27)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.22)
    static let panelStroke = Color.white.opacity(0.10)
    static let canvasBackground = Color(red: 0.035, green: 0.035, blue: 0.043)
    static let panelBackground = Color(white: 0.105)
    static let projectLibraryBackground = Color(red: 0.055, green: 0.055, blue: 0.063)
    static let quietFill = Color.white.opacity(0.045)
    static let selectedFill = Color.white.opacity(0.10)
    static let controlFill = Color.white.opacity(0.055)
    static let cardFill = Color.white.opacity(0.035)
    static let primaryText = Color.white.opacity(0.92)
    static let secondaryText = Color.white.opacity(0.56)
    static let hoverFill = Color.white.opacity(0.075)
    static let controlRadius: CGFloat = 8
    static let cardRadius: CGFloat = 12
    static let separator = Color.white.opacity(0.08)
    static let sceneCardRadius: CGFloat = 10
    static let scenePreviewFill = Color(white: 0.10)
    static let scenePreviewStroke = Color.white.opacity(0.3)
    static let screenPreviewFill = Color(white: 0.58)
    static let cameraPreviewFill = mint.opacity(0.75)

    static let trackScreen = Color.cyan
    static let trackCamera = Color.teal
    static let trackMicrophone = Color(red: 0.72, green: 0.54, blue: 1.0)
    static let trackSystemAudio = Color(red: 0.36, green: 0.56, blue: 1.0)

    static func levelColor(active: Bool) -> Color {
        active ? mint : Color.white.opacity(0.3)
    }

    static func sectionLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            BlitzSymbol(configuration: .init(name: icon, size: 16))
                .foregroundStyle(.white.opacity(0.62))
                .frame(width: 16, height: 16)

            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(BlitzUI.secondaryText)
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
                BlitzSymbol(configuration: .init(name: symbolName, size: size * 0.82))
                    .foregroundStyle(isSelected ? BlitzUI.mint : .white.opacity(0.78))
            }
        }
        .frame(width: size, height: size)
    }
}

struct BlitzScenePresetCard: View {
    let preset: ScenePreset
    let layout: CaptureLayout
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                BlitzSceneLayoutThumbnail(
                    layout: layout,
                    sceneLayout: SceneLayout.presetLayout(preset, for: layout),
                    visibleSources: visibleSources
                )
                .frame(height: 46)
                .padding(.horizontal, 4)

                Text(preset.compactTitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(isSelected ? 0.96 : 0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 82)
            .contentShape(.rect)
        }
        .buttonStyle(BlitzScenePresetButtonStyle(isSelected: isSelected))
        .disabled(!isEnabled)
        .opacity(isEnabled || isSelected ? 1 : 0.5)
        .pointingHandCursor()
        .help(preset.compactTitle)
    }

    private var visibleSources: Set<CaptureSource> {
        switch preset {
        case .screenFullscreen:
            return [.screen]
        case .webcamFullscreen:
            return [.camera]
        default:
            return [.screen, .camera]
        }
    }
}

struct BlitzScenePresetButtonStyle: ButtonStyle {
    let isSelected: Bool
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                isSelected ? BlitzUI.mint.opacity(0.08) : .white.opacity(isHovering ? 0.075 : 0.045),
                in: .rect(cornerRadius: BlitzUI.sceneCardRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: BlitzUI.sceneCardRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? BlitzUI.mint.opacity(0.65) : .white.opacity(isHovering ? 0.18 : 0.1),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            }
            .contentShape(.rect(cornerRadius: BlitzUI.sceneCardRadius))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .animation(.easeOut(duration: 0.16), value: isSelected)
    }
}

struct BlitzSceneLayoutThumbnail: View {
    let layout: CaptureLayout
    let sceneLayout: SceneLayout
    let visibleSources: Set<CaptureSource>

    var body: some View {
        GeometryReader { proxy in
            let canvas = fittedCanvas(in: proxy.size)
            let items = sceneLayout.resolvedItems(
                enabledSources: visibleSources,
                fillsCanvasWhenOnlyVideoSource: true
            )

            let inset: CGFloat = 2
            let contentSize = CGSize(width: max(0, canvas.width - inset * 2), height: max(0, canvas.height - inset * 2))
            let radius: CGFloat = 5

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(BlitzUI.scenePreviewFill)

                ForEach(items, id: \.kind) { item in
                    let frame = item.normalizedFrame.standardized.intersection(
                        CGRect(x: 0, y: 0, width: 1, height: 1)
                    )
                    if !frame.isNull, !frame.isEmpty {
                        BlitzSceneThumbnailLayer(kind: item.kind)
                            .padding(0.75)
                            .frame(
                                width: frame.width * contentSize.width,
                                height: frame.height * contentSize.height
                            )
                            .offset(
                                x: inset + frame.minX * contentSize.width,
                                y: inset + (1 - frame.maxY) * contentSize.height
                            )
                    }
                }
            }
            .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
            .clipShape(.rect(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(BlitzUI.scenePreviewStroke, lineWidth: 1)
            }
            .offset(x: canvas.minX, y: canvas.minY)
        }
        .accessibilityHidden(true)
    }

    private func fittedCanvas(in slot: CGSize) -> CGRect {
        guard slot.width > 0, slot.height > 0 else { return .zero }
        let aspect = layout.aspectRatio
        var width = slot.width
        var height = width / aspect
        if height > slot.height {
            height = slot.height
            width = height * aspect
        }
        return CGRect(
            x: (slot.width - width) / 2,
            y: (slot.height - height) / 2,
            width: width,
            height: height
        )
    }
}

struct BlitzSceneThumbnailLayer: View {
    let kind: SceneLayerKind

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(kind == .screen ? BlitzUI.screenPreviewFill : BlitzUI.cameraPreviewFill)
            .accessibilityHidden(true)
    }
}

extension ScenePreset {
    var compactTitle: String {
        switch self {
        case .screenTop50:
            return "Split"
        case .cameraInset:
            return "Picture in picture"
        case .webcamLeft:
            return "Side by side"
        case .screenFullscreen:
            return "Screen only"
        case .webcamFullscreen:
            return "Camera only"
        default:
            return detail
        }
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

struct BlitzStatusDot: View {
    var tone: BlitzStatusTone
    var diameter: CGFloat = 7

    var body: some View {
        Circle()
            .fill(tone.color)
            .frame(width: diameter, height: diameter)

    }
}

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
        content
            .background(isSelected ? BlitzUI.selectedFill : BlitzUI.quietFill, in: .rect(cornerRadius: cornerRadius))
    }
}

extension View {
    func blitzSelectedSurface(isSelected: Bool, cornerRadius: CGFloat = 10) -> some View {
        modifier(BlitzSelectedSurface(isSelected: isSelected, cornerRadius: cornerRadius))
    }
}


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

enum BlitzMenuEntry {
    case item(BlitzMenuItem)
    case divider
    case section(String)
}

struct BlitzGlassMenu<Label: View>: View {
    let entries: [BlitzMenuEntry]
    var menuWidth: CGFloat = 240
    @ViewBuilder var label: () -> Label

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            label()
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            BlitzGlassMenuList(entries: entries, width: menuWidth, maxHeight: adaptivePopoverMaxHeight) {
                isPresented = false
            }
            .preferredColorScheme(.dark)
        }
    }

    private var adaptivePopoverMaxHeight: CGFloat {
        let visibleHeight = NSScreen.main?.visibleFrame.height ?? 720
        return min(520, max(260, visibleHeight - 120))
    }
}

struct BlitzSourcePickerItem {
    let title: String
    let subtitle: String?
    let systemImage: String
    let icon: NSImage?
    let thumbnail: NSImage?
    let isSelected: Bool
    let action: () -> Void
}

struct BlitzSourcePickerSection {
    let title: String
    let items: [BlitzSourcePickerItem]
}

struct BlitzSourcePickerModel {
    enum Layout {
        case list
        case thumbnails
    }

    let title: String
    let subtitle: String
    let systemImage: String
    let icon: NSImage?
    let sections: [BlitzSourcePickerSection]
    let actions: [BlitzSourcePickerItem]
    let layout: Layout
    let enabled: Bool
    var hiddenSections: [BlitzSourcePickerSection] = []
}

struct BlitzSourcePicker: View {
    let model: BlitzSourcePickerModel

    @State private var isPresented = false
    @State private var isHovering = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 10) {
                sourceIcon

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(model.enabled ? 0.94 : 0.38))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(model.subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(model.enabled ? 0.5 : 0.28))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 4)

                Text("Change")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(model.enabled ? 0.68 : 0.28))

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(model.enabled ? 0.42 : 0.2))
            }
            .padding(.horizontal, 10)
            .frame(height: 54)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.white.opacity(isHovering ? 0.085 : 0.05),
                in: .rect(cornerRadius: 9)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(.white.opacity(isHovering ? 0.16 : 0.1), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .contentShape(.rect(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .disabled(!model.enabled)
        .onHover { isHovering = $0 }
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            BlitzSourcePickerPopover(model: model) {
                isPresented = false
            }
            .preferredColorScheme(.dark)
        }
        .pointingHandCursor()
    }

    @ViewBuilder
    private var sourceIcon: some View {
        if let icon = model.icon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .padding(5)
                .clipShape(.rect(cornerRadius: 8))
        } else {
            BlitzSymbol(configuration: .init(name: model.systemImage, size: 22))
                .foregroundStyle(model.enabled ? BlitzUI.mint : .white.opacity(0.28))
                .frame(width: 34, height: 34)
        }
    }
}

private struct BlitzSourcePickerPopover: View {
    let model: BlitzSourcePickerModel
    let dismiss: () -> Void

    @State private var showsHiddenSections = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Choose source")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))
            }
            .padding(.horizontal, 14)
            .padding(.top, 13)
            .padding(.bottom, 10)

            Divider()
                .overlay(BlitzUI.separator)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(visibleSections.enumerated()), id: \.offset) { _, section in
                        if !section.items.isEmpty {
                            sourceSection(section)
                        }
                    }

                    if !model.hiddenSections.isEmpty {
                        hiddenSectionsButton
                    }
                }
                .padding(10)
            }
            .scrollIndicators(.visible)
            .frame(maxHeight: 420)

            if !model.actions.isEmpty {
                Divider()
                    .overlay(BlitzUI.separator)

                VStack(spacing: 4) {
                    ForEach(Array(model.actions.enumerated()), id: \.offset) { _, item in
                        BlitzSourcePickerActionRow(item: item, dismiss: dismiss)
                    }
                }
                .padding(8)
            }
        }
        .frame(width: model.layout == .thumbnails ? 520 : 330)
    }

    private var visibleSections: [BlitzSourcePickerSection] {
        model.sections + (showsHiddenSections ? model.hiddenSections : [])
    }

    private var hiddenSectionsButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                showsHiddenSections.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: showsHiddenSections ? "eye.slash" : "eye")
                Text(showsHiddenSections ? "Hide private apps" : "Show all apps")
                Spacer(minLength: 0)
                Image(systemName: showsHiddenSections ? "chevron.up" : "chevron.down")
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.62))
            .padding(.horizontal, 9)
            .frame(minHeight: 36)
            .background(Color.white.opacity(0.035), in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private func sourceSection(_ section: BlitzSourcePickerSection) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(section.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.horizontal, 4)

            if model.layout == .thumbnails {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                        BlitzSourcePickerThumbnailCard(item: item, dismiss: dismiss)
                    }
                }
            } else {
                VStack(spacing: 3) {
                    ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                        BlitzSourcePickerRow(item: item, dismiss: dismiss)
                    }
                }
            }
        }
    }
}

private struct BlitzSourcePickerThumbnailCard: View {
    let item: BlitzSourcePickerItem
    let dismiss: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button {
            item.action()
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                preview

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.94))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.46))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
            }
            .background(rowFill, in: .rect(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(item.isSelected ? BlitzUI.mint.opacity(0.55) : .white.opacity(0.08), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .contentShape(.rect(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .pointingHandCursor()
    }

    private var preview: some View {
        ZStack {
            Color.black.opacity(0.44)

            if let thumbnail = item.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [.white.opacity(0.07), .white.opacity(0.025)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                BlitzSymbol(configuration: .init(name: item.systemImage, size: 30))
                    .foregroundStyle(.white.opacity(0.32))
            }

            VStack {
                HStack {
                    if let icon = item.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 22, height: 22)
                            .padding(4)
                            .background(.black.opacity(0.66), in: .rect(cornerRadius: 7))
                    }

                    Spacer(minLength: 0)

                    Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(item.isSelected ? BlitzUI.mint : .white.opacity(0.72))
                        .shadow(color: .black.opacity(0.7), radius: 3)
                }
                Spacer(minLength: 0)
            }
            .padding(7)
        }
        .frame(height: 108)
        .clipShape(.rect(topLeadingRadius: 9, topTrailingRadius: 9))
    }

    private var rowFill: Color {
        if item.isSelected {
            return BlitzUI.mint.opacity(0.12)
        }
        return isHovering ? Color.white.opacity(0.09) : Color.white.opacity(0.035)
    }
}

private struct BlitzSourcePickerRow: View {
    let item: BlitzSourcePickerItem
    let dismiss: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button {
            item.action()
            dismiss()
        } label: {
            HStack(spacing: 10) {
                pickerIcon

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.46))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BlitzUI.mint)
                    .opacity(item.isSelected ? 1 : 0)
            }
            .padding(.horizontal, 9)
            .frame(minHeight: 46)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowFill, in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .pointingHandCursor()
    }

    private var rowFill: Color {
        if item.isSelected {
            return BlitzUI.mint.opacity(0.1)
        }
        return isHovering ? Color.white.opacity(0.08) : Color.white.opacity(0.025)
    }

    @ViewBuilder
    private var pickerIcon: some View {
        if let icon = item.icon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
                .clipShape(.rect(cornerRadius: 5))
                .frame(width: 30, height: 30)
        } else {
            BlitzSymbol(configuration: .init(name: item.systemImage, size: 18))
                .foregroundStyle(item.isSelected ? BlitzUI.mint : .white.opacity(0.62))
                .frame(width: 30, height: 30)
        }
    }
}

private struct BlitzSourcePickerActionRow: View {
    let item: BlitzSourcePickerItem
    let dismiss: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button {
            item.action()
            dismiss()
        } label: {
            HStack(spacing: 10) {
                BlitzSymbol(configuration: .init(name: item.systemImage, size: 18))
                    .foregroundStyle(BlitzUI.mint)
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))

                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.46))
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 9)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovering ? Color.white.opacity(0.08) : .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .pointingHandCursor()
    }
}

private struct BlitzGlassMenuList: View {
    let entries: [BlitzMenuEntry]
    let width: CGFloat
    let maxHeight: CGFloat
    let dismiss: () -> Void

    private var adaptiveWidth: CGFloat {
        let visibleWidth = NSScreen.main?.visibleFrame.width ?? width
        return min(width, max(220, visibleWidth - 32))
    }

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
                        Text(title)
                            .font(.system(size: 11, weight: .semibold))
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
        .frame(width: adaptiveWidth)
        .frame(maxHeight: maxHeight)
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
                    BlitzSymbol(configuration: .init(name: item.systemImage, size: 16))
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
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .background(item.isSelected ? BlitzUI.selectedFill : (isHovering ? BlitzUI.hoverFill : .clear), in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .pointingHandCursor()
    }

    private var textColor: Color {
        item.isDestructive ? BlitzUI.recordRed : BlitzUI.primaryText
    }

    private var iconColor: Color {
        item.isDestructive ? BlitzUI.recordRed : BlitzUI.secondaryText
    }
}
