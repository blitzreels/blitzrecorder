import AppKit

struct CanvasBackgroundStyle: RawRepresentable, Hashable, CaseIterable, Sendable {
    let rawValue: String

    init?(rawValue: String) {
        let base = rawValue.split(separator: "|", maxSplits: 1).first.map(String.init) ?? rawValue
        guard Self.presetRawValues.contains(base)
                || base.hasPrefix(Self.colorPrefix)
                || base.hasPrefix(Self.imagePrefix) else { return nil }
        self.rawValue = rawValue
    }

    private init(preset: String) {
        rawValue = preset
    }

    static let black = Self(preset: "black")
    static let graphite = Self(preset: "graphite")
    static let slate = Self(preset: "slate")
    static let midnight = Self(preset: "midnight")
    static let ocean = Self(preset: "ocean")
    static let aurora = Self(preset: "aurora")
    static let nebula = Self(preset: "nebula")
    static let macOSSonoma = Self(preset: "macos-sonoma")
    static let macOSSonomaHorizon = Self(preset: "macos-sonoma-horizon")
    static let macOSRadialSky = Self(preset: "macos-radial-sky")
    static let macOSIMacBlue = Self(preset: "macos-imac-blue")
    static let macOSIMacPurple = Self(preset: "macos-imac-purple")
    static let macOSVentura = Self(preset: "macos-ventura")
    static let macOSMonterey = Self(preset: "macos-monterey")
    static let macOSBigSur = Self(preset: "macos-big-sur")
    static let seasonalSpringAurora = Self(preset: "seasonal-spring-aurora")
    static let seasonalSummerCoast = Self(preset: "seasonal-summer-coast")
    static let seasonalAutumnSonoma = Self(preset: "seasonal-autumn-sonoma")
    static let seasonalWinterFrost = Self(preset: "seasonal-winter-frost")
    static let seasonalMidnightLake = Self(preset: "seasonal-midnight-lake")
    static let studioGraphiteGlass = Self(preset: "studio-graphite-glass")
    static let studioPaperWhite = Self(preset: "studio-paper-white")
    static let studioSoftSpotlight = Self(preset: "studio-soft-spotlight")
    static let monterey = Self(preset: "monterey")
    static let sunset = Self(preset: "sunset")
    static let dune = Self(preset: "dune")
    static let blush = Self(preset: "blush")
    static let silver = Self(preset: "silver")
    static let peach = Self(preset: "peach")
    static let sorbet = Self(preset: "sorbet")
    static let mint = Self(preset: "mint")
    static let sky = Self(preset: "sky")
    static let lilac = Self(preset: "lilac")
    static let citrus = Self(preset: "citrus")
    static let flamingo = Self(preset: "flamingo")
    static let electric = Self(preset: "electric")

    static let allCases: [CanvasBackgroundStyle] = [
        .black,
        .graphite,
        .slate,
        .midnight,
        .ocean,
        .aurora,
        .nebula,
        .macOSSonoma,
        .macOSSonomaHorizon,
        .macOSRadialSky,
        .macOSIMacBlue,
        .macOSIMacPurple,
        .macOSVentura,
        .macOSMonterey,
        .macOSBigSur,
        .seasonalSpringAurora,
        .seasonalSummerCoast,
        .seasonalAutumnSonoma,
        .seasonalWinterFrost,
        .seasonalMidnightLake,
        .studioGraphiteGlass,
        .studioPaperWhite,
        .studioSoftSpotlight,
        .monterey,
        .sunset,
        .dune,
        .blush,
        .silver,
        .peach,
        .sorbet,
        .mint,
        .sky,
        .lilac,
        .citrus,
        .flamingo,
        .electric
    ]

    private static let presetRawValues = Set(allCases.map(\.rawValue))
    private static let colorPrefix = "color:"
    private static let imagePrefix = "image:"
    private static let blurPrefix = "blur="

    var base: CanvasBackgroundStyle {
        let raw = rawValue.split(separator: "|", maxSplits: 1).first.map(String.init) ?? rawValue
        return CanvasBackgroundStyle(preset: raw)
    }

    var blur: CanvasBackgroundBlur {
        rawValue.split(separator: "|").dropFirst()
            .compactMap { $0.hasPrefix(Self.blurPrefix) ? CanvasBackgroundBlur(rawValue: String($0.dropFirst(Self.blurPrefix.count))) : nil }
            .first ?? .none
    }

    func withBlur(_ blur: CanvasBackgroundBlur) -> CanvasBackgroundStyle {
        guard blur != .none else { return base }
        return CanvasBackgroundStyle(preset: "\(base.rawValue)|\(Self.blurPrefix)\(blur.rawValue)")
    }

    static func solid(_ color: NSColor) -> CanvasBackgroundStyle {
        let rgb = color.usingColorSpace(.sRGB) ?? .black
        let hex = String(format: "%02X%02X%02X",
                         Int((rgb.redComponent * 255).rounded()),
                         Int((rgb.greenComponent * 255).rounded()),
                         Int((rgb.blueComponent * 255).rounded()))
        return CanvasBackgroundStyle(preset: colorPrefix + hex)
    }

    static func image(fileName: String) -> CanvasBackgroundStyle {
        CanvasBackgroundStyle(preset: imagePrefix + fileName)
    }

    var solidColor: NSColor? {
        let raw = base.rawValue
        guard raw.hasPrefix(Self.colorPrefix), let value = UInt32(raw.dropFirst(Self.colorPrefix.count), radix: 16) else {
            return nil
        }
        return NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    var customImageURL: URL? {
        let raw = base.rawValue
        guard raw.hasPrefix(Self.imagePrefix) else { return nil }
        let name = String(raw.dropFirst(Self.imagePrefix.count))
        guard !name.isEmpty, !name.contains("/") else { return nil }
        return CanvasBackgroundLibrary.directory.appendingPathComponent(name)
    }

    var isCustom: Bool { solidColor != nil || customImageURL != nil }

    var displayName: String {
        if solidColor != nil { return "Custom color" }
        if customImageURL != nil { return "Your image" }
        switch base {
        case .black: return "Black"
        case .graphite: return "Titanium"
        case .slate: return "Slate"
        case .midnight: return "Midnight"
        case .ocean: return "Lagoon"
        case .aurora: return "Aurora"
        case .nebula: return "Nebula"
        case .macOSSonoma: return "macOS Sonoma"
        case .macOSSonomaHorizon: return "Sonoma Horizon"
        case .macOSRadialSky: return "Radial Sky"
        case .macOSIMacBlue: return "iMac Blue"
        case .macOSIMacPurple: return "iMac Purple"
        case .macOSVentura: return "macOS Ventura"
        case .macOSMonterey: return "macOS Monterey"
        case .macOSBigSur: return "macOS Big Sur"
        case .seasonalSpringAurora: return "Spring Aurora"
        case .seasonalSummerCoast: return "Summer Coast"
        case .seasonalAutumnSonoma: return "Copper"
        case .seasonalWinterFrost: return "Frost"
        case .seasonalMidnightLake: return "Midnight Lake"
        case .studioGraphiteGlass: return "Graphite Glass"
        case .studioPaperWhite: return "Paper"
        case .studioSoftSpotlight: return "Soft Spotlight"
        case .monterey: return "Monterey"
        case .sunset: return "Ember"
        case .dune: return "Dune"
        case .blush: return "Blush"
        case .silver: return "Liquid Silver"
        case .peach: return "Peach"
        case .sorbet: return "Sorbet"
        case .mint: return "Mint"
        case .sky: return "Sky"
        case .lilac: return "Lilac"
        case .citrus: return "Citrus"
        case .flamingo: return "Flamingo"
        case .electric: return "Electric"
        default: return "Background"
        }
    }
}

enum CanvasBackgroundBlur: String, CaseIterable, Sendable {
    case none, light, strong

    var title: String {
        switch self {
        case .none: "None"
        case .light: "Light"
        case .strong: "Strong"
        }
    }

    var radiusFraction: CGFloat {
        switch self {
        case .none: 0
        case .light: 0.012
        case .strong: 0.035
        }
    }
}

enum CanvasBackgroundLibrary {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BlitzRecorder", isDirectory: true)
            .appendingPathComponent("Backgrounds", isDirectory: true)
    }

    static func importImage(from source: URL) throws -> CanvasBackgroundStyle {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
        let name = "\(UUID().uuidString).\(ext)"
        try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(name))
        return .image(fileName: name)
    }

    static func recentImages(limit: Int) -> [CanvasBackgroundStyle] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        )) ?? []
        return urls
            .sorted { modificationDate($0) > modificationDate($1) }
            .prefix(limit)
            .map { .image(fileName: $0.lastPathComponent) }
    }

    private static func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
