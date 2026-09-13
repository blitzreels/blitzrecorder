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
    static let controlRadius = BlitzControlMetrics.radius
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

struct BlitzScenePreview {
    let screen: CGImage?
    let camera: CGImage?
    let background: CanvasBackgroundStyle
}

struct BlitzScenePresetCard: View {
    let preset: ScenePreset
    let layout: CaptureLayout
    let isSelected: Bool
    let isEnabled: Bool
    let availableSources: Set<CaptureSource>
    var preview: BlitzScenePreview? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                BlitzSceneLayoutThumbnail(
                    layout: layout,
                    sceneLayout: SceneLayout.presetLayout(preset, for: layout),
                    visibleSources: visibleSources,
                    preview: preview
                )
                .frame(height: preview == nil ? 46 : 58)
                .padding(.horizontal, 4)

                Text(preset.compactTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(isSelected ? 0.96 : 0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: preview == nil ? 82 : 94)
            .contentShape(.rect)
        }
        .buttonStyle(BlitzScenePresetButtonStyle(isSelected: isSelected))
        .disabled(!isEnabled)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .opacity(isEnabled || isSelected ? 1 : 0.5)
        .pointingHandCursor()
        .help(preset.compactTitle)
    }

    private var visibleSources: Set<CaptureSource> {
        preset.requiredVideoSources.intersection(availableSources)
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
    var preview: BlitzScenePreview? = nil

    var body: some View {
        GeometryReader { proxy in
            let canvas = fittedCanvas(in: proxy.size)
            let items = sceneLayout.resolvedItems(
                enabledSources: visibleSources,
                fillsCanvasWhenOnlyVideoSource: false
            )

            let inset: CGFloat = 2
            let contentSize = CGSize(width: max(0, canvas.width - inset * 2), height: max(0, canvas.height - inset * 2))
            let radius: CGFloat = 5

            ZStack(alignment: .topLeading) {
                if let preview {
                    CanvasBackgroundSwatchCache.image(preview.background)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: canvas.width, height: canvas.height)
                        .clipped()
                } else {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(BlitzUI.scenePreviewFill)
                }

                ForEach(items, id: \.kind) { item in
                    let frame = item.normalizedFrame.standardized.intersection(
                        CGRect(x: 0, y: 0, width: 1, height: 1)
                    )
                    if !frame.isNull, !frame.isEmpty {
                        BlitzSceneThumbnailLayer(
                            kind: item.kind,
                            image: item.kind == .screen ? preview?.screen : preview?.camera
                        )
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
    var image: CGImage? = nil

    var body: some View {
        GeometryReader { proxy in
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            } else {
                BlitzUI.screenPreviewFill
                    .overlay {
                        if kind == .camera {
                            BlitzUI.cameraPreviewFill
                        }
                    }
            }
        }
        .clipShape(.rect(cornerRadius: 2))
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
