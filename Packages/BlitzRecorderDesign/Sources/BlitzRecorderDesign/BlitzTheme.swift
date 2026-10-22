import Foundation
import Observation
import SwiftUI

// MARK: - User choices

public enum BlitzAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: "Automatic"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    public var symbolName: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}

/// The app's one accent. Red (record) and amber (warnings) stay fixed so they keep their meaning,
/// which is why there is no red, orange or yellow theme. Light values are deeper so they read on white.
public enum BlitzAccentTheme: String, CaseIterable, Identifiable {
    case mint
    case sky
    case indigo
    case violet
    case pink
    case graphite

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .mint: "Mint"
        case .sky: "Sky"
        case .indigo: "Indigo"
        case .violet: "Violet"
        case .pink: "Pink"
        case .graphite: "Graphite"
        }
    }

    public var accentPair: BlitzColorPair {
        switch self {
        case .mint: .init(light: BlitzPlatformColor(srgbRed: 0, green: 0.68, blue: 0.45, alpha: 1),
                          dark: BlitzPlatformColor(srgbRed: 0.09, green: 1.0, blue: 0.65, alpha: 1))
        case .sky: .init(light: BlitzPlatformColor(srgbRed: 0, green: 0.52, blue: 0.9, alpha: 1),
                         dark: BlitzPlatformColor(srgbRed: 0.3, green: 0.76, blue: 1.0, alpha: 1))
        case .indigo: .init(light: BlitzPlatformColor(srgbRed: 0.3, green: 0.36, blue: 0.94, alpha: 1),
                            dark: BlitzPlatformColor(srgbRed: 0.42, green: 0.49, blue: 1.0, alpha: 1))
        case .violet: .init(light: BlitzPlatformColor(srgbRed: 0.52, green: 0.3, blue: 0.94, alpha: 1),
                            dark: BlitzPlatformColor(srgbRed: 0.68, green: 0.47, blue: 1.0, alpha: 1))
        case .pink: .init(light: BlitzPlatformColor(srgbRed: 0.88, green: 0.18, blue: 0.52, alpha: 1),
                          dark: BlitzPlatformColor(srgbRed: 1.0, green: 0.42, blue: 0.72, alpha: 1))
        case .graphite: .init(light: BlitzPlatformColor(srgbRed: 0.22, green: 0.23, blue: 0.27, alpha: 1),
                              dark: BlitzPlatformColor(srgbRed: 0.86, green: 0.87, blue: 0.9, alpha: 1))
        }
    }

    public var highlightPair: BlitzColorPair {
        switch self {
        case .mint: .init(light: BlitzPlatformColor(srgbRed: 0.12, green: 0.8, blue: 0.56, alpha: 1),
                          dark: BlitzPlatformColor(srgbRed: 0.36, green: 1.0, blue: 0.78, alpha: 1))
        case .sky: .init(light: BlitzPlatformColor(srgbRed: 0.2, green: 0.64, blue: 0.98, alpha: 1),
                         dark: BlitzPlatformColor(srgbRed: 0.52, green: 0.85, blue: 1.0, alpha: 1))
        case .indigo: .init(light: BlitzPlatformColor(srgbRed: 0.45, green: 0.5, blue: 1.0, alpha: 1),
                            dark: BlitzPlatformColor(srgbRed: 0.58, green: 0.64, blue: 1.0, alpha: 1))
        case .violet: .init(light: BlitzPlatformColor(srgbRed: 0.64, green: 0.45, blue: 1.0, alpha: 1),
                            dark: BlitzPlatformColor(srgbRed: 0.8, green: 0.64, blue: 1.0, alpha: 1))
        case .pink: .init(light: BlitzPlatformColor(srgbRed: 0.98, green: 0.34, blue: 0.64, alpha: 1),
                          dark: BlitzPlatformColor(srgbRed: 1.0, green: 0.6, blue: 0.82, alpha: 1))
        case .graphite: .init(light: BlitzPlatformColor(srgbRed: 0.36, green: 0.37, blue: 0.42, alpha: 1),
                              dark: BlitzPlatformColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1))
        }
    }

    /// Text and glyphs placed on an accent fill.
    public var onAccentPair: BlitzColorPair {
        let light = BlitzPlatformColor(white: 1, alpha: 0.97)
        switch self {
        case .indigo, .violet: return .init(light: light, dark: BlitzPlatformColor(white: 1, alpha: 0.96))
        case .mint, .sky, .pink, .graphite: return .init(light: light, dark: BlitzPlatformColor(white: 0, alpha: 0.86))
        }
    }

}

/// The hue of the backgrounds behind everything: neutral grey, or a hint of blue or warmth.
public enum BlitzSurfaceTint: String, CaseIterable, Identifiable {
    case neutral
    case cool
    case warm

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .neutral: "Neutral"
        case .cool: "Cool"
        case .warm: "Warm"
        }
    }

    public var palette: BlitzSurfacePalette {
        switch self {
        case .neutral: .neutral
        case .cool: .cool
        case .warm: .warm
        }
    }
}

public struct BlitzSurfacePalette {
    /// Behind the studio canvas and video.
    public let canvas: BlitzColorPair
    /// Pages and the editor.
    public let page: BlitzColorPair
    /// Window title bars: one step lighter than the page on dark, the page itself on light.
    public var toolbar: BlitzColorPair { .init(light: page.light, dark: panel.dark) }
    /// Panels, popovers and settings cards.
    public let panel: BlitzColorPair

    public static let neutral = BlitzSurfacePalette(
        canvas: .init(light: BlitzPlatformColor(srgbRed: 0.89, green: 0.89, blue: 0.9, alpha: 1),
                      dark: BlitzPlatformColor(srgbRed: 0.035, green: 0.035, blue: 0.043, alpha: 1)),
        page: .init(light: BlitzPlatformColor(srgbRed: 0.975, green: 0.975, blue: 0.98, alpha: 1),
                    dark: BlitzPlatformColor(srgbRed: 0.055, green: 0.055, blue: 0.063, alpha: 1)),
        panel: .init(light: BlitzPlatformColor(srgbRed: 0.945, green: 0.945, blue: 0.952, alpha: 1),
                     dark: BlitzPlatformColor(white: 0.105, alpha: 1))
    )

    public static let cool = BlitzSurfacePalette(
        canvas: .init(light: BlitzPlatformColor(srgbRed: 0.87, green: 0.89, blue: 0.93, alpha: 1),
                      dark: BlitzPlatformColor(srgbRed: 0.03, green: 0.04, blue: 0.06, alpha: 1)),
        page: .init(light: BlitzPlatformColor(srgbRed: 0.965, green: 0.972, blue: 0.99, alpha: 1),
                    dark: BlitzPlatformColor(srgbRed: 0.05, green: 0.06, blue: 0.085, alpha: 1)),
        panel: .init(light: BlitzPlatformColor(srgbRed: 0.93, green: 0.94, blue: 0.965, alpha: 1),
                     dark: BlitzPlatformColor(srgbRed: 0.09, green: 0.1, blue: 0.13, alpha: 1))
    )

    public static let warm = BlitzSurfacePalette(
        canvas: .init(light: BlitzPlatformColor(srgbRed: 0.91, green: 0.89, blue: 0.86, alpha: 1),
                      dark: BlitzPlatformColor(srgbRed: 0.045, green: 0.04, blue: 0.035, alpha: 1)),
        page: .init(light: BlitzPlatformColor(srgbRed: 0.985, green: 0.975, blue: 0.96, alpha: 1),
                    dark: BlitzPlatformColor(srgbRed: 0.07, green: 0.062, blue: 0.055, alpha: 1)),
        panel: .init(light: BlitzPlatformColor(srgbRed: 0.955, green: 0.942, blue: 0.92, alpha: 1),
                     dark: BlitzPlatformColor(srgbRed: 0.12, green: 0.11, blue: 0.1, alpha: 1))
    )
}

// MARK: - Neutral tokens (shared by every theme)

/// Translucent ink: white on dark, black on light. Everything that layers over a surface uses these.
public enum BlitzColors {
    private static func ink(_ amount: CGFloat) -> BlitzColorPair {
        .init(light: BlitzPlatformColor(white: 0, alpha: amount * 0.92), dark: BlitzPlatformColor(white: 1, alpha: amount))
    }

    public static let primaryText = BlitzColorPair(light: BlitzPlatformColor(white: 0, alpha: 0.86), dark: BlitzPlatformColor(white: 1, alpha: 0.92))
    public static let supportingText = BlitzColorPair(light: BlitzPlatformColor(white: 0, alpha: 0.68), dark: BlitzPlatformColor(white: 1, alpha: 0.72))
    public static let secondaryText = BlitzColorPair(light: BlitzPlatformColor(white: 0, alpha: 0.52), dark: BlitzPlatformColor(white: 1, alpha: 0.56))
    public static let tertiaryText = BlitzColorPair(light: BlitzPlatformColor(white: 0, alpha: 0.36), dark: BlitzPlatformColor(white: 1, alpha: 0.38))
    public static let quietFill = ink(0.045)
    public static let cardFill = ink(0.035)
    public static let controlFill = ink(0.055)
    public static let hoverFill = ink(0.075)
    public static let selectedFill = ink(0.1)
    public static let strongFill = ink(0.16)
    public static let separator = ink(0.08)
    public static let panelStroke = ink(0.1)
    public static let strongStroke = ink(0.22)
    /// Raised surfaces are lit glass on dark and white paper on light.
    public static let raisedFillTop = BlitzColorPair(light: BlitzPlatformColor(white: 1, alpha: 1), dark: BlitzPlatformColor(white: 1, alpha: 0.1))
    public static let raisedFillBottom = BlitzColorPair(light: BlitzPlatformColor(white: 0.985, alpha: 1), dark: BlitzPlatformColor(white: 1, alpha: 0.055))
    public static let edgeHighlight = BlitzColorPair(light: BlitzPlatformColor(white: 0, alpha: 0.07), dark: BlitzPlatformColor(white: 1, alpha: 0.13))
    public static let glassTint = BlitzColorPair(light: BlitzPlatformColor(white: 0.99, alpha: 0.55), dark: BlitzPlatformColor(white: 0.11, alpha: 0.55))
    public static let insetWell = BlitzColorPair(light: BlitzPlatformColor(white: 0, alpha: 0.05), dark: BlitzPlatformColor(white: 0, alpha: 0.24))
    public static let elevationShadow = BlitzColorPair(light: BlitzPlatformColor(white: 0, alpha: 0.06), dark: BlitzPlatformColor(white: 0, alpha: 0.22))
    public static let deepShadow = BlitzColorPair(light: BlitzPlatformColor(white: 0, alpha: 0.1), dark: BlitzPlatformColor(white: 0, alpha: 0.32))
    /// Glyphs on a `primaryText` fill (the white play button in dark mode, a dark one in light mode).
    public static let inverseText = BlitzColorPair(light: BlitzPlatformColor(white: 1, alpha: 0.96), dark: BlitzPlatformColor(white: 0, alpha: 0.88))
    public static let warning = BlitzColorPair(light: BlitzPlatformColor(srgbRed: 0.8, green: 0.48, blue: 0, alpha: 1),
                                        dark: BlitzPlatformColor(srgbRed: 1.0, green: 0.72, blue: 0.22, alpha: 1))
    /// Hairline under title bars; light mode needs it because the bar and the page share one color.
    public static let toolbarDivider = BlitzColorPair(light: BlitzPlatformColor(white: 0, alpha: 0.07), dark: BlitzPlatformColor(white: 0, alpha: 0))
    public static let recordRed = BlitzColorPair(light: BlitzPlatformColor(srgbRed: 0.96, green: 0.23, blue: 0.23, alpha: 1),
                                          dark: BlitzPlatformColor(srgbRed: 1.0, green: 0.27, blue: 0.27, alpha: 1))
    public static let overlayFill = BlitzColorPair(light: BlitzPlatformColor(white: 0.99, alpha: 0.94), dark: BlitzPlatformColor(white: 0.07, alpha: 0.94))
    public static let scenePreviewFill = BlitzColorPair(light: BlitzPlatformColor(white: 0.84, alpha: 1), dark: BlitzPlatformColor(white: 0.1, alpha: 1))
    public static let scenePreviewStroke = ink(0.3)
    public static let screenPreviewFill = BlitzColorPair(light: BlitzPlatformColor(white: 0.66, alpha: 1), dark: BlitzPlatformColor(white: 0.3, alpha: 1))
    public static let cameraPreviewFill = BlitzColorPair(light: BlitzPlatformColor(white: 0.46, alpha: 1), dark: BlitzPlatformColor(white: 0.62, alpha: 1))
}

// MARK: - Store

extension Notification.Name {
    public static let blitzAccentChanged = Notification.Name("BlitzRecorder.accentChanged")
    public static let blitzAppearanceChanged = Notification.Name("BlitzRecorder.appearanceChanged")
}

/// SwiftUI views that read `BlitzUI` re-render on change through Observation;
/// AppKit drawing listens for `.blitzAccentChanged` and `viewDidChangeEffectiveAppearance`.
@Observable
public final class BlitzThemeStore {
    public static let shared = BlitzThemeStore()
    private enum Key {
        static let accent = "appearance.accentTheme"
        static let mode = "appearance.mode"
        static let tint = "appearance.surfaceTint"
    }

    private let defaults: UserDefaults

    public var accent: BlitzAccentTheme {
        didSet {
            guard accent != oldValue else { return }
            defaults.set(accent.rawValue, forKey: Key.accent)
            NotificationCenter.default.post(name: .blitzAccentChanged, object: nil)
        }
    }

    public var mode: BlitzAppearanceMode {
        didSet {
            guard mode != oldValue else { return }
            defaults.set(mode.rawValue, forKey: Key.mode)
            NotificationCenter.default.post(name: .blitzAppearanceChanged, object: nil)
        }
    }

    public var tint: BlitzSurfaceTint {
        didSet {
            guard tint != oldValue else { return }
            defaults.set(tint.rawValue, forKey: Key.tint)
            NotificationCenter.default.post(name: .blitzAccentChanged, object: nil)
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        accent = defaults.string(forKey: Key.accent).flatMap(BlitzAccentTheme.init(rawValue:)) ?? .mint
        mode = defaults.string(forKey: Key.mode).flatMap(BlitzAppearanceMode.init(rawValue:)) ?? .dark
        tint = defaults.string(forKey: Key.tint).flatMap(BlitzSurfaceTint.init(rawValue:)) ?? .neutral
    }
}
