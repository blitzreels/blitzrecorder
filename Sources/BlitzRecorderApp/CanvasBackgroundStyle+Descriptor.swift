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

        if let color = solidColor {
            return CanvasBackgroundDescriptor(baseStops: [(color, 0)], blobs: [], glow: false, grain: 0, representative: color)
        }
        if customImageURL != nil {
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.12, 0.12, 0.13), 0)], blobs: [], glow: false, grain: 0,
                representative: srgb(0.12, 0.12, 0.13))
        }
        switch base {
        case .black:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.016, 0.016, 0.022), 0)],
                blobs: [],
                glow: true, grain: 0,
                representative: srgb(0.016, 0.016, 0.022))
        case .graphite:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.13, 0.135, 0.15), 0), (srgb(0.035, 0.037, 0.045), 1)],
                blobs: [
                    blob(0.80, 0.12, 0.85, srgb(0.42, 0.44, 0.5), 0.42),
                    blob(0.15, 0.95, 0.70, srgb(0.18, 0.19, 0.23), 0.35)
                ],
                glow: true, grain: 0.03,
                representative: srgb(0.13, 0.14, 0.16))
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
                baseStops: [(srgb(0.04, 0.04, 0.12), 0), (srgb(0.01, 0.012, 0.04), 1)],
                blobs: [
                    blob(0.18, 0.22, 0.85, srgb(0.3, 0.22, 0.85), 0.60),
                    blob(0.85, 0.78, 0.85, srgb(0.08, 0.32, 0.85), 0.55),
                    blob(0.62, 0.05, 0.45, srgb(0.55, 0.35, 0.95), 0.35)
                ],
                glow: true, grain: 0.03,
                representative: srgb(0.1, 0.1, 0.3))
        case .ocean:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.01, 0.08, 0.16), 0), (srgb(0.005, 0.025, 0.07), 1)],
                blobs: [
                    blob(0.80, 0.20, 0.85, srgb(0.05, 0.62, 0.85), 0.60),
                    blob(0.18, 0.75, 0.85, srgb(0.04, 0.22, 0.62), 0.55),
                    blob(0.48, 0.98, 0.55, srgb(0.1, 0.85, 0.8), 0.38)
                ],
                glow: true, grain: 0.03,
                representative: srgb(0.04, 0.24, 0.38))
        case .aurora:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.015, 0.04, 0.08), 0), (srgb(0.01, 0.05, 0.06), 1)],
                blobs: [
                    blob(0.25, 0.75, 0.80, srgb(0.1, 0.85, 0.55), 0.55),
                    blob(0.75, 0.25, 0.80, srgb(0.45, 0.25, 0.85), 0.55),
                    blob(0.55, 0.55, 0.45, srgb(0.05, 0.7, 0.75), 0.35)
                ],
                glow: true, grain: 0.03,
                representative: srgb(0.1, 0.32, 0.36))
        case .nebula:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.07, 0.02, 0.12), 0), (srgb(0.025, 0.01, 0.06), 1)],
                blobs: [
                    blob(0.25, 0.28, 0.80, srgb(0.85, 0.2, 0.62), 0.55),
                    blob(0.80, 0.72, 0.85, srgb(0.45, 0.22, 0.9), 0.55),
                    blob(0.62, 0.10, 0.45, srgb(1.0, 0.45, 0.7), 0.32)
                ],
                glow: true, grain: 0.03,
                representative: srgb(0.3, 0.1, 0.34))
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
                baseStops: [(srgb(0.1, 0.03, 0.02), 0), (srgb(0.04, 0.01, 0.01), 1)],
                blobs: [
                    blob(0.30, 0.35, 0.85, srgb(0.95, 0.35, 0.12), 0.55),
                    blob(0.80, 0.80, 0.80, srgb(0.7, 0.1, 0.15), 0.50),
                    blob(0.70, 0.10, 0.45, srgb(1.0, 0.6, 0.25), 0.30)
                ],
                glow: true, grain: 0.03,
                representative: srgb(0.38, 0.13, 0.07))
        case .seasonalWinterFrost:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.86, 0.9, 0.95), 0), (srgb(0.7, 0.77, 0.88), 1)],
                blobs: [
                    blob(0.25, 0.20, 0.80, srgb(1.0, 1.0, 1.0), 0.75),
                    blob(0.85, 0.85, 0.80, srgb(0.55, 0.65, 0.85), 0.45),
                    blob(0.75, 0.20, 0.50, srgb(0.8, 0.85, 1.0), 0.40)
                ],
                glow: false, grain: 0.02,
                representative: srgb(0.8, 0.85, 0.92))
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
                baseStops: [(srgb(0.96, 0.96, 0.95), 0), (srgb(0.86, 0.87, 0.88), 1)],
                blobs: [
                    blob(0.30, 0.20, 0.85, srgb(1.0, 1.0, 1.0), 0.80),
                    blob(0.85, 0.90, 0.75, srgb(0.78, 0.8, 0.84), 0.40)
                ],
                glow: false, grain: 0.015,
                representative: srgb(0.92, 0.92, 0.92))
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
                baseStops: [(srgb(0.1, 0.03, 0.07), 0), (srgb(0.04, 0.01, 0.04), 1)],
                blobs: [
                    blob(0.22, 0.28, 0.85, srgb(0.85, 0.18, 0.38), 0.55),
                    blob(0.78, 0.80, 0.85, srgb(1.0, 0.48, 0.18), 0.55),
                    blob(0.75, 0.15, 0.50, srgb(0.6, 0.2, 0.65), 0.35)
                ],
                glow: true, grain: 0.03,
                representative: srgb(0.38, 0.14, 0.18))
        case .dune:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.1, 0.06, 0.03), 0), (srgb(0.04, 0.025, 0.01), 1)],
                blobs: [
                    blob(0.35, 0.25, 0.85, srgb(0.95, 0.62, 0.25), 0.55),
                    blob(0.80, 0.85, 0.85, srgb(0.65, 0.3, 0.12), 0.50),
                    blob(0.10, 0.80, 0.50, srgb(0.85, 0.45, 0.3), 0.30)
                ],
                glow: true, grain: 0.03,
                representative: srgb(0.36, 0.22, 0.1))
        case .blush:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.08, 0.03, 0.08), 0), (srgb(0.03, 0.01, 0.04), 1)],
                blobs: [
                    blob(0.30, 0.30, 0.85, srgb(1.0, 0.42, 0.68), 0.55),
                    blob(0.80, 0.75, 0.85, srgb(0.60, 0.30, 0.85), 0.50),
                    blob(0.70, 0.08, 0.40, srgb(1.0, 0.72, 0.70), 0.30)
                ],
                glow: true, grain: 0.03,
                representative: srgb(0.38, 0.16, 0.32))
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
        case .peach:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(1.00, 0.86, 0.78), 0), (srgb(0.98, 0.70, 0.66), 1)],
                blobs: [
                    blob(0.20, 0.20, 0.80, srgb(1.00, 0.93, 0.80), 0.80),
                    blob(0.85, 0.80, 0.80, srgb(0.98, 0.58, 0.62), 0.55),
                    blob(0.75, 0.15, 0.50, srgb(1.00, 0.78, 0.55), 0.50)
                ],
                glow: false, grain: 0.015,
                representative: srgb(0.99, 0.78, 0.72))
        case .sorbet:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(1.00, 0.82, 0.88), 0), (srgb(0.80, 0.86, 1.00), 1)],
                blobs: [
                    blob(0.18, 0.20, 0.75, srgb(1.00, 0.70, 0.80), 0.60),
                    blob(0.85, 0.85, 0.80, srgb(0.60, 0.75, 1.00), 0.55),
                    blob(0.70, 0.15, 0.50, srgb(1.00, 0.95, 0.70), 0.55)
                ],
                glow: false, grain: 0.015,
                representative: srgb(0.90, 0.84, 0.94))
        case .mint:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.82, 0.97, 0.90), 0), (srgb(0.62, 0.90, 0.86), 1)],
                blobs: [
                    blob(0.20, 0.25, 0.80, srgb(0.95, 1.00, 0.92), 0.75),
                    blob(0.85, 0.80, 0.80, srgb(0.40, 0.85, 0.80), 0.50),
                    blob(0.70, 0.10, 0.50, srgb(0.75, 0.98, 0.70), 0.45)
                ],
                glow: false, grain: 0.015,
                representative: srgb(0.72, 0.93, 0.88))
        case .sky:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.80, 0.90, 1.00), 0), (srgb(0.55, 0.72, 0.98), 1)],
                blobs: [
                    blob(0.25, 0.20, 0.80, srgb(0.95, 0.98, 1.00), 0.75),
                    blob(0.85, 0.85, 0.80, srgb(0.40, 0.58, 0.98), 0.50),
                    blob(0.70, 0.15, 0.50, srgb(0.70, 0.90, 1.00), 0.45)
                ],
                glow: false, grain: 0.015,
                representative: srgb(0.68, 0.80, 0.98))
        case .lilac:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.92, 0.86, 1.00), 0), (srgb(0.76, 0.68, 0.98), 1)],
                blobs: [
                    blob(0.20, 0.20, 0.80, srgb(1.00, 0.96, 1.00), 0.75),
                    blob(0.85, 0.80, 0.80, srgb(0.62, 0.50, 0.98), 0.50),
                    blob(0.70, 0.15, 0.50, srgb(0.98, 0.75, 0.95), 0.45)
                ],
                glow: false, grain: 0.015,
                representative: srgb(0.84, 0.77, 0.98))
        case .citrus:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(1.00, 0.62, 0.10), 0), (srgb(0.98, 0.35, 0.15), 1)],
                blobs: [
                    blob(0.25, 0.25, 0.80, srgb(1.00, 0.90, 0.30), 0.60),
                    blob(0.85, 0.85, 0.80, srgb(1.00, 0.20, 0.35), 0.45),
                    blob(0.75, 0.15, 0.45, srgb(1.00, 0.75, 0.20), 0.40)
                ],
                glow: false, grain: 0.02,
                representative: srgb(0.99, 0.50, 0.14))
        case .flamingo:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(1.00, 0.45, 0.60), 0), (srgb(0.85, 0.25, 0.55), 1)],
                blobs: [
                    blob(0.25, 0.20, 0.80, srgb(1.00, 0.75, 0.65), 0.60),
                    blob(0.85, 0.85, 0.80, srgb(0.65, 0.25, 0.85), 0.50),
                    blob(0.70, 0.10, 0.45, srgb(1.00, 0.55, 0.75), 0.40)
                ],
                glow: false, grain: 0.02,
                representative: srgb(0.92, 0.36, 0.58))
        case .electric:
            return CanvasBackgroundDescriptor(
                baseStops: [(srgb(0.15, 0.25, 0.95), 0), (srgb(0.45, 0.10, 0.85), 1)],
                blobs: [
                    blob(0.20, 0.20, 0.80, srgb(0.20, 0.75, 1.00), 0.60),
                    blob(0.85, 0.85, 0.80, srgb(0.85, 0.25, 0.95), 0.55),
                    blob(0.75, 0.20, 0.50, srgb(0.45, 0.55, 1.00), 0.40)
                ],
                glow: false, grain: 0.02,
                representative: srgb(0.30, 0.18, 0.90))
        default:
            return CanvasBackgroundStyle.black.descriptor
        }
    }
}
