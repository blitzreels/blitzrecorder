import Foundation

enum CanvasBackgroundStyle: String, CaseIterable {
    case black = "black"
    case graphite = "graphite"
    case slate = "slate"
    case midnight = "midnight"
    case ocean = "ocean"
    case aurora = "aurora"
    case nebula = "nebula"
    case macOSSonoma = "macos-sonoma"
    case macOSSonomaHorizon = "macos-sonoma-horizon"
    case macOSRadialSky = "macos-radial-sky"
    case macOSIMacBlue = "macos-imac-blue"
    case macOSIMacPurple = "macos-imac-purple"
    case macOSVentura = "macos-ventura"
    case macOSMonterey = "macos-monterey"
    case macOSBigSur = "macos-big-sur"
    case seasonalSpringAurora = "seasonal-spring-aurora"
    case seasonalSummerCoast = "seasonal-summer-coast"
    case seasonalAutumnSonoma = "seasonal-autumn-sonoma"
    case seasonalWinterFrost = "seasonal-winter-frost"
    case seasonalMidnightLake = "seasonal-midnight-lake"
    case studioGraphiteGlass = "studio-graphite-glass"
    case studioPaperWhite = "studio-paper-white"
    case studioSoftSpotlight = "studio-soft-spotlight"
    case monterey = "monterey"
    case sunset = "sunset"
    case dune = "dune"
    case blush = "blush"
    case silver = "silver"

    var displayName: String {
        switch self {
        case .black:
            return "Black"
        case .graphite:
            return "Titanium"
        case .slate:
            return "Slate"
        case .midnight:
            return "Midnight"
        case .ocean:
            return "Lagoon"
        case .aurora:
            return "Aurora"
        case .nebula:
            return "Nebula"
        case .macOSSonoma:
            return "macOS Sonoma"
        case .macOSSonomaHorizon:
            return "Sonoma Horizon"
        case .macOSRadialSky:
            return "Radial Sky"
        case .macOSIMacBlue:
            return "iMac Blue"
        case .macOSIMacPurple:
            return "iMac Purple"
        case .macOSVentura:
            return "macOS Ventura"
        case .macOSMonterey:
            return "macOS Monterey"
        case .macOSBigSur:
            return "macOS Big Sur"
        case .seasonalSpringAurora:
            return "Spring Aurora"
        case .seasonalSummerCoast:
            return "Summer Coast"
        case .seasonalAutumnSonoma:
            return "Autumn Sonoma"
        case .seasonalWinterFrost:
            return "Winter Frost"
        case .seasonalMidnightLake:
            return "Midnight Lake"
        case .studioGraphiteGlass:
            return "Graphite Glass"
        case .studioPaperWhite:
            return "Paper White"
        case .studioSoftSpotlight:
            return "Soft Spotlight"
        case .monterey:
            return "Monterey"
        case .sunset:
            return "Ember"
        case .dune:
            return "Dune"
        case .blush:
            return "Blush"
        case .silver:
            return "Liquid Silver"
        }
    }
}
