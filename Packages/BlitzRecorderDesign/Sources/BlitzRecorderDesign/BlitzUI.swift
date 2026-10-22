import SwiftUI

public enum BlitzSymbols {
    public static let screen = "display"
    public static let camera = "video"
    public static let microphone = "mic"
    public static let systemAudio = "speaker.wave.2"
    public static let scenes = "rectangle.stack"
    public static let layout = "rectangle.split.2x1"
    public static let split = "rectangle.split.1x2"
    public static let pictureInPicture = "pip"
    public static let source = "macwindow"
    public static let videoQuality = "play.rectangle"

    // One icon per action, on buttons, inline actions and menus alike. Scripts/check-design-system.sh rejects
    // these names written as literals anywhere else.
    public static let edit = "scissors"
    public static let export = "square.and.arrow.up"
    public static let saveToMac = "square.and.arrow.down"
    public static let share = "link"
    public static let copyLink = "doc.on.doc"
    public static let openLink = "safari"
    public static let rename = "square.and.pencil"
    public static let delete = "trash"
    public static let folder = "folder"
    public static let library = "film.stack"
    public static let recorderHidden = "eye.slash"
    public static let recorderShown = "eye"
}

public enum BlitzType {
#if os(macOS)
    public static let largeTitle = Font.system(size: 24, weight: .semibold)
    public static let title = Font.system(size: 17, weight: .semibold)
    public static let headline = Font.system(size: 15, weight: .semibold)
    public static let section = Font.system(size: 13, weight: .semibold)
    public static let callout = Font.system(size: 13)
    /// Sidebar links and list titles. One weight in every state so selection never shifts the layout.
    public static let navigation = Font.system(size: 13, weight: .medium)
    public static let body = Font.system(size: 12)
    public static let label = Font.system(size: 12, weight: .medium)
    public static let strong = Font.system(size: 12, weight: .semibold)
    public static let caption = Font.system(size: 11)
    public static let captionEmphasis = Font.system(size: 11, weight: .medium)
    public static let footnote = Font.system(size: 10, weight: .medium)
    public static let numeric = Font.system(size: 11, weight: .medium).monospacedDigit()
    public static let shortcutBadge = Font.system(size: 9, weight: .semibold).monospacedDigit()
    public static let countdown = Font.system(size: 120, weight: .bold, design: .rounded).monospacedDigit()
    /// Point sizes written for the Mac are used as is.
    static let scale: CGFloat = 1
#else
    // The same hierarchy on iPhone, on the system text styles so Dynamic Type keeps working.
    public static let largeTitle = Font.title.weight(.semibold)
    public static let title = Font.title3.weight(.semibold)
    public static let headline = Font.headline
    public static let section = Font.subheadline.weight(.semibold)
    public static let callout = Font.callout
    /// List titles. One weight in every state so selection never shifts the layout.
    public static let navigation = Font.body.weight(.medium)
    public static let body = Font.subheadline
    public static let label = Font.subheadline.weight(.medium)
    public static let strong = Font.subheadline.weight(.semibold)
    public static let caption = Font.footnote
    public static let captionEmphasis = Font.footnote.weight(.medium)
    public static let footnote = Font.caption.weight(.medium)
    public static let numeric = Font.footnote.weight(.medium).monospacedDigit()
    public static let shortcutBadge = Font.caption2.weight(.semibold).monospacedDigit()
    public static let countdown = Font.system(size: 120, weight: .bold, design: .rounded).monospacedDigit()
    /// Point sizes written for the Mac grow by the same step the text styles do on iPhone.
    static let scale: CGFloat = 1.3
#endif

    public static func glyph(_ size: CGFloat) -> Font {
        .system(size: size * scale, weight: .medium)
    }

    public static func symbol(_ size: CGFloat) -> Font {
        .system(size: size * scale, weight: .semibold)
    }

    public static func control(_ size: CGFloat) -> Font {
        .system(size: size * scale, weight: .medium)
    }

    public static func monogram(_ size: CGFloat) -> Font {
        .system(size: size * scale, weight: .semibold, design: .rounded)
    }
}

public struct BlitzSymbol: View {
    public struct Configuration {
        public let name: String
        public let size: CGFloat

        public init(name: String, size: CGFloat) {
            self.name = name
            self.size = size
        }
    }

    public let configuration: Configuration

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    public var body: some View {
        Image(systemName: configuration.name)
            .font(BlitzType.symbol(configuration.size * 0.8))
            .symbolRenderingMode(.monochrome)
            .imageScale(.medium)
            .frame(width: configuration.size * BlitzType.scale, height: configuration.size * BlitzType.scale)
            .accessibilityHidden(true)
    }
}

public enum BlitzUI {
    public static var accent: Color { BlitzThemeStore.shared.accent.accentPair.color }
    public static var accentHighlight: Color { BlitzThemeStore.shared.accent.highlightPair.color }
    public static var accentGlow: Color { BlitzThemeStore.shared.accent.accentPair.alpha(.init(light: 0.18, dark: 0.28)).color }
    public static var onAccent: Color { BlitzThemeStore.shared.accent.onAccentPair.color }
    public static let recordRed = BlitzColors.recordRed.color
    public static let recordRedHighlight = Color(red: 1.0, green: 0.38, blue: 0.35)
    public static let recordGlow = BlitzColors.recordRed.alpha(.init(light: 0.2, dark: 0.3)).color
    public static let warning = BlitzColors.warning.color

    public static var canvasBackground: Color { BlitzThemeStore.shared.tint.palette.canvas.color }
    public static var projectLibraryBackground: Color { BlitzThemeStore.shared.tint.palette.page.color }
    public static var panelBackground: Color { BlitzThemeStore.shared.tint.palette.panel.color }
    public static var toolbarBackground: Color { BlitzThemeStore.shared.tint.palette.toolbar.color }
    public static let toolbarDivider = BlitzColors.toolbarDivider.color
    public static let overlayFill = BlitzColors.overlayFill.color

    public static let primaryText = BlitzColors.primaryText.color
    public static let supportingText = BlitzColors.supportingText.color
    public static let secondaryText = BlitzColors.secondaryText.color
    public static let tertiaryText = BlitzColors.tertiaryText.color
    public static let inverseText = BlitzColors.inverseText.color
    public static let quietFill = BlitzColors.quietFill.color
    public static let cardFill = BlitzColors.cardFill.color
    public static let controlFill = BlitzColors.controlFill.color
    public static let hoverFill = BlitzColors.hoverFill.color
    public static let selectedFill = BlitzColors.selectedFill.color
    public static let strongFill = BlitzColors.strongFill.color
    public static let separator = BlitzColors.separator.color
    public static let panelStroke = BlitzColors.panelStroke.color
    public static let strongStroke = BlitzColors.strongStroke.color
    public static let raisedFillTop = BlitzColors.raisedFillTop.color
    public static let raisedFillBottom = BlitzColors.raisedFillBottom.color
    public static let edgeHighlight = BlitzColors.edgeHighlight.color
    public static let glassTint = BlitzColors.glassTint.color
    public static let insetWell = BlitzColors.insetWell.color
    public static let elevationShadow = BlitzColors.elevationShadow.color
    public static let deepShadow = BlitzColors.deepShadow.color

    public static let controlRadius = BlitzControlMetrics.radius
    public static let cardRadius: CGFloat = 12
    public static let surfaceRadius: CGFloat = 16
    public static let sceneCardRadius: CGFloat = 12
    public static let scenePreviewFill = BlitzColors.scenePreviewFill.color
    public static let scenePreviewStroke = BlitzColors.scenePreviewStroke.color
    public static let screenPreviewFill = BlitzColors.screenPreviewFill.color
    public static let cameraPreviewFill = BlitzColors.cameraPreviewFill.color
    public static let screenPreviewGlyph = Color.white.opacity(0.5)
    /// Text and glyphs drawn on top of footage, thumbnails or dark scrims: fixed, never follow light mode.
    public static let onMediaText = Color.white
    public static let onMediaSecondaryText = Color.white.opacity(0.75)
    public static let onMediaStroke = Color.white.opacity(0.3)
    public static let cameraPreviewGlyph = Color.black.opacity(0.55)

    public static let trackScreen = Color.cyan
    public static let trackCamera = Color.teal
    public static let trackMicrophone = Color(red: 0.72, green: 0.54, blue: 1.0)
    public static let trackSystemAudio = Color(red: 0.36, green: 0.56, blue: 1.0)

    public static func levelColor(active: Bool) -> Color {
        active ? accent : tertiaryText
    }

    public static func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(BlitzType.captionEmphasis)
            .foregroundStyle(BlitzUI.secondaryText)
            .lineLimit(1)
    }
}

public enum BlitzStatusTone: Equatable {
    case recording
    case live
    case ready
    case warning
    case muted

    public var color: Color {
        switch self {
        case .recording: return BlitzUI.recordRed
        case .live, .ready: return BlitzUI.accent
        case .warning: return BlitzUI.warning
        case .muted: return BlitzUI.tertiaryText
        }
    }
}

public struct BlitzStatusDot: View {
    public var tone: BlitzStatusTone
    public var diameter: CGFloat = 7

    public init(tone: BlitzStatusTone, diameter: CGFloat = 7) {
        self.tone = tone
        self.diameter = diameter
    }

    public var body: some View {
        Circle()
            .fill(tone.color)
            .frame(width: diameter, height: diameter)

    }
}
