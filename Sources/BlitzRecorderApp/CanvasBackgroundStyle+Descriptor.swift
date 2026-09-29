import AppKit

extension CanvasBackgroundStyle {
    /// Hand-tuned mesh recipes. Coordinates are top-left origin; radii are
    /// normalized to the long edge. Dark styles glow additively; Silver blends
    /// normally over a light base.
    var descriptor: CanvasBackgroundDescriptor {
        func srgb(_ r: Double, _ g: Double, _ b: Double) -> NSColor {
            NSColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1)
        }
        func blob(_ x: Double, _ y: Double, _ radius: Double, _ color: NSColor, _ alpha: Double) -> CanvasBackgroundBlob {
            CanvasBackgroundBlob(center: CGPoint(x: x, y: y), radius: CGFloat(radius), color: color, alpha: CGFloat(alpha))
        }

        switch self {
        case .black:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.016, 0.016, 0.022), 0)],
                blobs: [],
                glow: true, grain: 0,
                representative: srgb(0.016, 0.016, 0.022))
        case .graphite:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.11, 0.12, 0.14), 0), (srgb(0.04, 0.045, 0.055), 1)],
                blobs: [
                    blob(0.78, 0.16, 0.75, srgb(0.34, 0.37, 0.43), 0.38),
                    blob(0.20, 0.86, 0.65, srgb(0.20, 0.22, 0.27), 0.32)
                ],
                glow: true, grain: 0.05,
                representative: srgb(0.12, 0.13, 0.16))
        case .slate:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.09, 0.11, 0.15), 0), (srgb(0.035, 0.045, 0.075), 1)],
                blobs: [
                    blob(0.26, 0.24, 0.78, srgb(0.20, 0.31, 0.47), 0.42),
                    blob(0.82, 0.80, 0.72, srgb(0.14, 0.20, 0.33), 0.38)
                ],
                glow: true, grain: 0.05,
                representative: srgb(0.10, 0.13, 0.19))
        case .midnight:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.05, 0.06, 0.14), 0), (srgb(0.015, 0.02, 0.06), 1)],
                blobs: [
                    blob(0.22, 0.28, 0.82, srgb(0.22, 0.18, 0.58), 0.5),
                    blob(0.82, 0.72, 0.78, srgb(0.10, 0.30, 0.66), 0.46),
                    blob(0.64, 0.10, 0.5, srgb(0.36, 0.22, 0.64), 0.3)
                ],
                glow: true, grain: 0.055,
                representative: srgb(0.07, 0.08, 0.18))
        case .ocean:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.02, 0.10, 0.18), 0), (srgb(0.01, 0.035, 0.085), 1)],
                blobs: [
                    blob(0.76, 0.24, 0.82, srgb(0.10, 0.56, 0.70), 0.5),
                    blob(0.20, 0.72, 0.80, srgb(0.05, 0.26, 0.52), 0.46),
                    blob(0.50, 0.92, 0.5, srgb(0.16, 0.72, 0.72), 0.3)
                ],
                glow: true, grain: 0.05,
                representative: srgb(0.04, 0.18, 0.30))
        case .aurora:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.02, 0.05, 0.10), 0), (srgb(0.02, 0.06, 0.08), 1)],
                blobs: [
                    blob(0.30, 0.70, 0.72, srgb(0.15, 0.76, 0.56), 0.5),
                    blob(0.70, 0.30, 0.76, srgb(0.36, 0.22, 0.62), 0.5),
                    blob(0.54, 0.54, 0.5, srgb(0.10, 0.62, 0.62), 0.34),
                    blob(0.86, 0.82, 0.45, srgb(0.50, 0.20, 0.56), 0.3)
                ],
                glow: true, grain: 0.05,
                representative: srgb(0.10, 0.30, 0.35))
        case .nebula:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.07, 0.03, 0.12), 0), (srgb(0.03, 0.02, 0.07), 1)],
                blobs: [
                    blob(0.28, 0.30, 0.80, srgb(0.66, 0.18, 0.56), 0.5),
                    blob(0.78, 0.68, 0.80, srgb(0.40, 0.20, 0.72), 0.5),
                    blob(0.60, 0.14, 0.5, srgb(0.82, 0.36, 0.62), 0.3),
                    blob(0.15, 0.86, 0.6, srgb(0.16, 0.12, 0.46), 0.36)
                ],
                glow: true, grain: 0.055,
                representative: srgb(0.22, 0.10, 0.28))
        case .macOSSonoma:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.16, 0.08, 0.18), 0), (srgb(0.46, 0.12, 0.18), 1)],
                blobs: [
                    blob(0.24, 0.22, 0.78, srgb(0.62, 0.16, 0.58), 0.48),
                    blob(0.82, 0.72, 0.78, srgb(0.96, 0.36, 0.16), 0.44),
                    blob(0.50, 0.46, 0.56, srgb(0.22, 0.38, 0.82), 0.26)
                ],
                glow: true, grain: 0.05,
                representative: srgb(0.42, 0.13, 0.24))
        case .macOSSonomaHorizon:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.58, 0.22, 0.12), 0), (srgb(0.10, 0.10, 0.20), 1)],
                blobs: [
                    blob(0.24, 0.18, 0.80, srgb(0.95, 0.62, 0.24), 0.42),
                    blob(0.74, 0.84, 0.72, srgb(0.20, 0.24, 0.54), 0.38),
                    blob(0.62, 0.34, 0.56, srgb(0.92, 0.28, 0.18), 0.28)
                ],
                glow: true, grain: 0.045,
                representative: srgb(0.48, 0.22, 0.16))
        case .macOSRadialSky:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.08, 0.22, 0.52), 0), (srgb(0.02, 0.05, 0.22), 1)],
                blobs: [
                    blob(0.44, 0.34, 0.86, srgb(0.22, 0.66, 0.94), 0.52),
                    blob(0.74, 0.72, 0.74, srgb(0.10, 0.24, 0.70), 0.42),
                    blob(0.24, 0.76, 0.56, srgb(0.54, 0.86, 0.98), 0.28)
                ],
                glow: true, grain: 0.045,
                representative: srgb(0.12, 0.28, 0.58))
        case .macOSIMacBlue:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.04, 0.16, 0.34), 0), (srgb(0.03, 0.05, 0.12), 1)],
                blobs: [
                    blob(0.28, 0.24, 0.82, srgb(0.14, 0.56, 0.92), 0.48),
                    blob(0.78, 0.72, 0.78, srgb(0.08, 0.28, 0.64), 0.4),
                    blob(0.48, 0.88, 0.52, srgb(0.42, 0.84, 0.96), 0.24)
                ],
                glow: true, grain: 0.045,
                representative: srgb(0.08, 0.24, 0.48))
        case .macOSIMacPurple:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.18, 0.10, 0.34), 0), (srgb(0.05, 0.03, 0.16), 1)],
                blobs: [
                    blob(0.26, 0.24, 0.82, srgb(0.46, 0.26, 0.88), 0.48),
                    blob(0.78, 0.72, 0.78, srgb(0.72, 0.36, 0.82), 0.38),
                    blob(0.50, 0.86, 0.52, srgb(0.22, 0.18, 0.58), 0.34)
                ],
                glow: true, grain: 0.05,
                representative: srgb(0.22, 0.13, 0.42))
        case .macOSVentura:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.08, 0.12, 0.30), 0), (srgb(0.28, 0.08, 0.26), 1)],
                blobs: [
                    blob(0.20, 0.20, 0.82, srgb(0.16, 0.34, 0.90), 0.48),
                    blob(0.82, 0.72, 0.82, srgb(0.86, 0.18, 0.58), 0.42),
                    blob(0.60, 0.42, 0.56, srgb(0.28, 0.66, 0.92), 0.3)
                ],
                glow: true, grain: 0.05,
                representative: srgb(0.19, 0.16, 0.42))
        case .macOSMonterey:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.06, 0.08, 0.20), 0), (srgb(0.13, 0.04, 0.12), 1)],
                blobs: [
                    blob(0.20, 0.24, 0.84, srgb(0.18, 0.38, 0.82), 0.5),
                    blob(0.80, 0.78, 0.80, srgb(0.84, 0.32, 0.58), 0.46),
                    blob(0.55, 0.43, 0.50, srgb(0.28, 0.58, 0.88), 0.3)
                ],
                glow: true, grain: 0.05,
                representative: srgb(0.20, 0.16, 0.34))
        case .macOSBigSur:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.08, 0.18, 0.32), 0), (srgb(0.16, 0.10, 0.26), 1)],
                blobs: [
                    blob(0.22, 0.24, 0.82, srgb(0.12, 0.52, 0.78), 0.44),
                    blob(0.78, 0.72, 0.80, srgb(0.58, 0.20, 0.76), 0.4),
                    blob(0.48, 0.88, 0.56, srgb(0.92, 0.30, 0.36), 0.26)
                ],
                glow: true, grain: 0.05,
                representative: srgb(0.17, 0.22, 0.42))
        case .seasonalSpringAurora:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.035, 0.09, 0.11), 0), (srgb(0.05, 0.08, 0.12), 1)],
                blobs: [
                    blob(0.24, 0.26, 0.78, srgb(0.24, 0.78, 0.58), 0.48),
                    blob(0.72, 0.32, 0.82, srgb(0.64, 0.38, 0.92), 0.44),
                    blob(0.54, 0.74, 0.60, srgb(0.98, 0.66, 0.82), 0.28),
                    blob(0.88, 0.84, 0.48, srgb(0.18, 0.54, 0.72), 0.30)
                ],
                glow: true, grain: 0.045,
                representative: srgb(0.12, 0.30, 0.28))
        case .seasonalSummerCoast:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.02, 0.13, 0.22), 0), (srgb(0.04, 0.05, 0.13), 1)],
                blobs: [
                    blob(0.22, 0.18, 0.84, srgb(0.12, 0.62, 0.82), 0.50),
                    blob(0.78, 0.76, 0.78, srgb(0.04, 0.28, 0.66), 0.44),
                    blob(0.56, 0.56, 0.54, srgb(0.76, 0.82, 0.58), 0.22),
                    blob(0.86, 0.28, 0.50, srgb(0.20, 0.76, 0.72), 0.26)
                ],
                glow: true, grain: 0.045,
                representative: srgb(0.05, 0.26, 0.40))
        case .seasonalAutumnSonoma:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.16, 0.06, 0.08), 0), (srgb(0.08, 0.035, 0.06), 1)],
                blobs: [
                    blob(0.26, 0.24, 0.82, srgb(0.92, 0.38, 0.14), 0.48),
                    blob(0.76, 0.70, 0.78, srgb(0.72, 0.16, 0.34), 0.44),
                    blob(0.55, 0.42, 0.56, srgb(0.96, 0.66, 0.28), 0.28),
                    blob(0.18, 0.86, 0.48, srgb(0.34, 0.18, 0.44), 0.32)
                ],
                glow: true, grain: 0.05,
                representative: srgb(0.38, 0.13, 0.12))
        case .seasonalWinterFrost:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.58, 0.68, 0.78), 0), (srgb(0.20, 0.28, 0.40), 1)],
                blobs: [
                    blob(0.30, 0.20, 0.74, srgb(0.96, 1.0, 1.0), 0.54),
                    blob(0.78, 0.80, 0.74, srgb(0.34, 0.50, 0.76), 0.44),
                    blob(0.54, 0.52, 0.60, srgb(0.70, 0.86, 0.94), 0.36)
                ],
                glow: false, grain: 0.035,
                representative: srgb(0.52, 0.64, 0.76))
        case .seasonalMidnightLake:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.018, 0.04, 0.08), 0), (srgb(0.008, 0.016, 0.04), 1)],
                blobs: [
                    blob(0.24, 0.28, 0.84, srgb(0.10, 0.34, 0.74), 0.48),
                    blob(0.80, 0.76, 0.78, srgb(0.12, 0.62, 0.58), 0.36),
                    blob(0.54, 0.90, 0.46, srgb(0.34, 0.22, 0.66), 0.28),
                    blob(0.70, 0.18, 0.44, srgb(0.06, 0.18, 0.40), 0.42)
                ],
                glow: true, grain: 0.055,
                representative: srgb(0.05, 0.11, 0.20))
        case .studioGraphiteGlass:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.16, 0.17, 0.18), 0), (srgb(0.045, 0.05, 0.06), 1)],
                blobs: [
                    blob(0.22, 0.18, 0.78, srgb(0.44, 0.48, 0.54), 0.32),
                    blob(0.82, 0.76, 0.76, srgb(0.12, 0.14, 0.18), 0.44),
                    blob(0.62, 0.38, 0.54, srgb(0.26, 0.32, 0.38), 0.26)
                ],
                glow: true, grain: 0.045,
                representative: srgb(0.12, 0.13, 0.15))
        case .studioPaperWhite:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.92, 0.93, 0.91), 0), (srgb(0.72, 0.76, 0.78), 1)],
                blobs: [
                    blob(0.26, 0.22, 0.72, srgb(1.0, 1.0, 0.96), 0.58),
                    blob(0.82, 0.78, 0.74, srgb(0.58, 0.66, 0.74), 0.36),
                    blob(0.55, 0.52, 0.56, srgb(0.82, 0.88, 0.90), 0.34)
                ],
                glow: false, grain: 0.025,
                representative: srgb(0.84, 0.86, 0.86))
        case .studioSoftSpotlight:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.13, 0.13, 0.15), 0), (srgb(0.025, 0.026, 0.032), 1)],
                blobs: [
                    blob(0.50, 0.34, 0.82, srgb(0.62, 0.66, 0.72), 0.32),
                    blob(0.22, 0.82, 0.62, srgb(0.08, 0.10, 0.14), 0.42),
                    blob(0.82, 0.78, 0.66, srgb(0.18, 0.22, 0.28), 0.30)
                ],
                glow: true, grain: 0.045,
                representative: srgb(0.10, 0.10, 0.12))
        case .monterey:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.05, 0.07, 0.16), 0), (srgb(0.10, 0.04, 0.10), 1)],
                blobs: [
                    blob(0.22, 0.24, 0.85, srgb(0.18, 0.36, 0.80), 0.5),
                    blob(0.80, 0.78, 0.80, srgb(0.80, 0.32, 0.56), 0.46),
                    blob(0.56, 0.42, 0.5, srgb(0.26, 0.56, 0.86), 0.3)
                ],
                glow: true, grain: 0.05,
                representative: srgb(0.20, 0.16, 0.34))
        case .sunset:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.10, 0.03, 0.10), 0), (srgb(0.05, 0.02, 0.06), 1)],
                blobs: [
                    blob(0.74, 0.70, 0.82, srgb(0.96, 0.46, 0.18), 0.5),
                    blob(0.26, 0.34, 0.80, srgb(0.70, 0.15, 0.26), 0.5),
                    blob(0.60, 0.88, 0.5, srgb(0.98, 0.72, 0.32), 0.34),
                    blob(0.14, 0.80, 0.5, srgb(0.50, 0.10, 0.30), 0.3)
                ],
                glow: true, grain: 0.05,
                representative: srgb(0.35, 0.12, 0.15))
        case .dune:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.12, 0.07, 0.05), 0), (srgb(0.055, 0.04, 0.04), 1)],
                blobs: [
                    blob(0.30, 0.30, 0.85, srgb(0.86, 0.56, 0.26), 0.5),
                    blob(0.78, 0.74, 0.80, srgb(0.70, 0.32, 0.18), 0.46),
                    blob(0.60, 0.14, 0.5, srgb(0.92, 0.72, 0.42), 0.3)
                ],
                glow: true, grain: 0.05,
                representative: srgb(0.30, 0.18, 0.10))
        case .blush:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.16, 0.10, 0.13), 0), (srgb(0.08, 0.055, 0.08), 1)],
                blobs: [
                    blob(0.28, 0.30, 0.80, srgb(0.86, 0.46, 0.56), 0.46),
                    blob(0.78, 0.70, 0.80, srgb(0.92, 0.60, 0.50), 0.42),
                    blob(0.58, 0.16, 0.5, srgb(0.56, 0.40, 0.72), 0.3)
                ],
                glow: true, grain: 0.05,
                representative: srgb(0.28, 0.16, 0.20))
        case .silver:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.84, 0.87, 0.92), 0), (srgb(0.55, 0.60, 0.68), 1)],
                blobs: [
                    blob(0.30, 0.20, 0.72, srgb(0.99, 1.0, 1.0), 0.6),
                    blob(0.80, 0.82, 0.72, srgb(0.50, 0.57, 0.68), 0.5),
                    blob(0.55, 0.52, 0.6, srgb(0.72, 0.80, 0.90), 0.4)
                ],
                glow: false, grain: 0.04,
                representative: srgb(0.78, 0.82, 0.88))
        }
    }
}
