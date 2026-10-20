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
    static let source = "macwindow"
    static let videoQuality = "play.rectangle"

    // One icon per action, on buttons, inline actions and menus alike. Scripts/check-design-system.sh rejects
    // these names written as literals anywhere else.
    static let edit = "scissors"
    static let export = "square.and.arrow.up"
    static let saveToMac = "square.and.arrow.down"
    static let share = "link"
    static let copyLink = "doc.on.doc"
    static let openLink = "safari"
    static let rename = "square.and.pencil"
    static let delete = "trash"
    static let folder = "folder"
    static let library = "film.stack"
    static let recorderHidden = "eye.slash"
    static let recorderShown = "eye"
}

enum BlitzType {
    static let largeTitle = Font.system(size: 24, weight: .semibold)
    static let title = Font.system(size: 17, weight: .semibold)
    static let headline = Font.system(size: 15, weight: .semibold)
    static let section = Font.system(size: 13, weight: .semibold)
    static let callout = Font.system(size: 13)
    /// Sidebar links and list titles. One weight in every state so selection never shifts the layout.
    static let navigation = Font.system(size: 13, weight: .medium)
    static let body = Font.system(size: 12)
    static let label = Font.system(size: 12, weight: .medium)
    static let strong = Font.system(size: 12, weight: .semibold)
    static let caption = Font.system(size: 11)
    static let captionEmphasis = Font.system(size: 11, weight: .medium)
    static let footnote = Font.system(size: 10, weight: .medium)
    static let numeric = Font.system(size: 11, weight: .medium).monospacedDigit()
    static let shortcutBadge = Font.system(size: 9, weight: .semibold).monospacedDigit()
    static let countdown = Font.system(size: 120, weight: .bold, design: .rounded).monospacedDigit()

    static func glyph(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium)
    }

    static func symbol(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold)
    }

    static func control(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium)
    }

    static func monogram(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
}

struct BlitzSymbol: View {
    struct Configuration {
        let name: String
        let size: CGFloat
    }

    let configuration: Configuration

    var body: some View {
        Image(systemName: configuration.name)
            .font(BlitzType.symbol(configuration.size * 0.8))
            .symbolRenderingMode(.monochrome)
            .imageScale(.medium)
            .frame(width: configuration.size, height: configuration.size)
            .accessibilityHidden(true)
    }
}

enum BlitzUI {
    static var accent: Color { BlitzThemeStore.shared.accent.accentPair.color }
    static var accentHighlight: Color { BlitzThemeStore.shared.accent.highlightPair.color }
    static var accentGlow: Color { BlitzThemeStore.shared.accent.accentPair.alpha(.init(light: 0.18, dark: 0.28)).color }
    static var onAccent: Color { BlitzThemeStore.shared.accent.onAccentPair.color }
    static let recordRed = BlitzColors.recordRed.color
    static let recordRedHighlight = Color(red: 1.0, green: 0.38, blue: 0.35)
    static let recordGlow = BlitzColors.recordRed.alpha(.init(light: 0.2, dark: 0.3)).color
    static let warning = BlitzColors.warning.color

    static var canvasBackground: Color { BlitzThemeStore.shared.tint.palette.canvas.color }
    static var projectLibraryBackground: Color { BlitzThemeStore.shared.tint.palette.page.color }
    static var panelBackground: Color { BlitzThemeStore.shared.tint.palette.panel.color }
    static var toolbarBackground: Color { BlitzThemeStore.shared.tint.palette.toolbar.color }
    static let toolbarDivider = BlitzColors.toolbarDivider.color
    static let overlayFill = BlitzColors.overlayFill.color

    static let primaryText = BlitzColors.primaryText.color
    static let supportingText = BlitzColors.supportingText.color
    static let secondaryText = BlitzColors.secondaryText.color
    static let tertiaryText = BlitzColors.tertiaryText.color
    static let inverseText = BlitzColors.inverseText.color
    static let quietFill = BlitzColors.quietFill.color
    static let cardFill = BlitzColors.cardFill.color
    static let controlFill = BlitzColors.controlFill.color
    static let hoverFill = BlitzColors.hoverFill.color
    static let selectedFill = BlitzColors.selectedFill.color
    static let strongFill = BlitzColors.strongFill.color
    static let separator = BlitzColors.separator.color
    static let panelStroke = BlitzColors.panelStroke.color
    static let strongStroke = BlitzColors.strongStroke.color
    static let raisedFillTop = BlitzColors.raisedFillTop.color
    static let raisedFillBottom = BlitzColors.raisedFillBottom.color
    static let edgeHighlight = BlitzColors.edgeHighlight.color
    static let glassTint = BlitzColors.glassTint.color
    static let insetWell = BlitzColors.insetWell.color
    static let elevationShadow = BlitzColors.elevationShadow.color
    static let deepShadow = BlitzColors.deepShadow.color

    static let controlRadius = BlitzControlMetrics.radius
    static let cardRadius: CGFloat = 12
    static let surfaceRadius: CGFloat = 16
    static let sceneCardRadius: CGFloat = 12
    static let scenePreviewFill = BlitzColors.scenePreviewFill.color
    static let scenePreviewStroke = BlitzColors.scenePreviewStroke.color
    static let screenPreviewFill = BlitzColors.screenPreviewFill.color
    static let cameraPreviewFill = BlitzColors.cameraPreviewFill.color
    static let screenPreviewGlyph = Color.white.opacity(0.5)
    /// Text and glyphs drawn on top of footage, thumbnails or dark scrims: fixed, never follow light mode.
    static let onMediaText = Color.white
    static let onMediaSecondaryText = Color.white.opacity(0.75)
    static let onMediaStroke = Color.white.opacity(0.3)
    static let cameraPreviewGlyph = Color.black.opacity(0.55)

    static let trackScreen = Color.cyan
    static let trackCamera = Color.teal
    static let trackMicrophone = Color(red: 0.72, green: 0.54, blue: 1.0)
    static let trackSystemAudio = Color(red: 0.36, green: 0.56, blue: 1.0)

    static func levelColor(active: Bool) -> Color {
        active ? accent : tertiaryText
    }

    static func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(BlitzType.captionEmphasis)
            .foregroundStyle(BlitzUI.secondaryText)
            .lineLimit(1)
    }
}

struct BlitzIconTile: View {
    let symbolName: String
    let isSelected: Bool
    var icon: NSImage? = nil
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: BlitzUI.controlRadius, style: .continuous)
                .fill(isSelected ? BlitzUI.accent.opacity(0.16) : BlitzUI.controlFill)
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size * 0.68, height: size * 0.68)
                    .clipShape(.rect(cornerRadius: 4))
            } else {
                BlitzSymbol(configuration: .init(name: symbolName, size: size * 0.82))
                    .foregroundStyle(isSelected ? BlitzUI.accent : BlitzUI.supportingText)
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
                    .font(BlitzType.captionEmphasis)
                    .foregroundStyle(isSelected ? BlitzUI.primaryText : BlitzUI.supportingText)
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
                isSelected ? BlitzUI.selectedFill : (isHovering ? BlitzUI.hoverFill : BlitzUI.quietFill),
                in: .rect(cornerRadius: BlitzUI.sceneCardRadius)
            )
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
                (kind == .camera ? BlitzUI.cameraPreviewFill : BlitzUI.screenPreviewFill)
                    .overlay {
                        let glyphSize = min(proxy.size.width, proxy.size.height) * 0.5
                        if glyphSize >= 6 {
                            Image(systemName: kind == .camera ? "person.fill" : BlitzSymbols.source)
                                .font(BlitzType.symbol(min(glyphSize, 14)))
                                .foregroundStyle(kind == .camera ? BlitzUI.cameraPreviewGlyph : BlitzUI.screenPreviewGlyph)
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
            return "Camera left"
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
    case recording
    case live
    case ready
    case warning
    case muted

    var color: Color {
        switch self {
        case .recording: return BlitzUI.recordRed
        case .live, .ready: return BlitzUI.accent
        case .warning: return BlitzUI.warning
        case .muted: return BlitzUI.tertiaryText
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
            context.fill(
                Path(roundedRect: CGRect(x: 0, y: size.height / 2 - 1, width: size.width, height: 2), cornerRadius: 1),
                with: .color(BlitzUI.separator)
            )
            guard !values.isEmpty else { return }

            let recentMax = max(0.08, (values.suffix(16).max() ?? 0) * 0.86)
            let barCount = values.count
            let spacing: CGFloat = 1
            let barWidth = max(1.5, (size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount))
            let centerY = size.height / 2
            let color = BlitzUI.levelColor(active: active)

            for (i, raw) in values.enumerated() {
                guard raw > 0.003 else { continue }
                let normalized = max(0.08, min(1, raw / recentMax))
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

