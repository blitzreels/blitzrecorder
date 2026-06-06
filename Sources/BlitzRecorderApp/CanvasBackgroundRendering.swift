import AppKit
import CoreImage
import ImageIO
import QuartzCore
import SwiftUI

/// A single soft radial color blob, the building block of the mesh-style canvas
/// backgrounds. Coordinates are normalized in a **top-left** origin space; the
/// radius is normalized to the canvas's long edge so blobs scale on any aspect.
struct CanvasBackgroundBlob {
    var center: CGPoint
    var radius: CGFloat
    var color: NSColor
    var alpha: CGFloat
}

/// Declarative recipe for a canvas background: a vertical base gradient with a
/// handful of overlapping radial blobs (the "mesh gradient" technique used by
/// Screen Studio / macOS wallpapers) plus a faint grain to kill 8-bit banding.
struct CanvasBackgroundDescriptor {
    /// Top → bottom base gradient stops `(color, location 0...1)`.
    var baseStops: [(color: NSColor, location: CGFloat)]
    var blobs: [CanvasBackgroundBlob]
    /// `true` → blobs blend additively (`.plusLighter`) for a luminous glow on
    /// dark bases. `false` → normal blending, used by light styles (Silver).
    var glow: Bool
    /// Drawn alpha of the tiled grain (0 = none). Subtle dither, ~0.04–0.06.
    var grain: CGFloat
    /// A representative flat color (export fallback / solid instruction bg).
    var representative: NSColor
}

struct CanvasAppearance {
    let style: CanvasBackgroundStyle

    var descriptor: CanvasBackgroundDescriptor { style.descriptor }

    var solidCGColor: CGColor { descriptor.representative.cgColor }

    /// Seconds for one full loop of the animated drift. Slow on purpose — the
    /// motion should read as ambient, not busy.
    static let animationLoopDuration: Double = 8.0

    /// Where a blob sits at a given loop `phase` (0...1). Each blob orbits a small
    /// ellipse an integer number of times per loop, so the motion is seamless
    /// (phase 0 == phase 1) and every blob drifts on its own axis/phase.
    static func animatedCenter(_ base: CGPoint, index: Int, phase: Double) -> CGPoint {
        let cycles: Double = (index % 2 == 0) ? 1 : 2
        let direction: Double = (index % 2 == 0) ? 1 : -1
        let amplitudeX = 0.05
        let amplitudeY = 0.055
        let angle = 2 * Double.pi * cycles * phase * direction + Double(index) * 1.7
        return CGPoint(
            x: base.x + CGFloat(amplitudeX * cos(angle)),
            y: base.y + CGFloat(amplitudeY * sin(angle))
        )
    }

    /// Render `count` evenly-spaced frames of one animation loop. Used to prebake
    /// the export (Merger) `contents` keyframe animation.
    func animationFrames(pixelWidth: Int, pixelHeight: Int, count: Int) -> [CGImage] {
        guard count > 0 else { return [] }
        return (0..<count).compactMap { index in
            renderCGImage(pixelWidth: pixelWidth, pixelHeight: pixelHeight, animationPhase: Double(index) / Double(count))
        }
    }

    /// Render the background to a CGImage in a top-left origin space. Pure and
    /// thread-safe (Core Graphics only), so it feeds the live preview, the
    /// recording compositor, the export merger, and the SwiftUI swatches alike.
    /// `animationPhase` nil = static (authored blob positions); non-nil applies
    /// the drift for that loop phase.
    func renderCGImage(pixelWidth: Int, pixelHeight: Int, animationPhase: Double? = nil) -> CGImage? {
        let w = max(1, pixelWidth)
        let h = max(1, pixelHeight)

        if let wallpaper = style.systemWallpaperImage(pixelWidth: w, pixelHeight: h) {
            return wallpaper
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Flip into a top-left origin space so blob coordinates read naturally
        // and match SwiftUI / CALayer geometry.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)

        let size = CGSize(width: w, height: h)
        let longEdge = max(size.width, size.height)
        let descriptor = self.descriptor

        // Base gradient (vertical).
        if descriptor.baseStops.count <= 1 {
            ctx.setFillColor((descriptor.baseStops.first?.color ?? .black).cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
        } else {
            let colors = descriptor.baseStops.map { $0.color.cgColor } as CFArray
            let locations = descriptor.baseStops.map { $0.location }
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
                ctx.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: size.width / 2, y: 0),
                    end: CGPoint(x: size.width / 2, y: size.height),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }
        }

        // Soft radial blobs.
        if !descriptor.blobs.isEmpty {
            ctx.saveGState()
            ctx.setBlendMode(descriptor.glow ? .plusLighter : .normal)
            for (index, blob) in descriptor.blobs.enumerated() {
                let peak = blob.color.withAlphaComponent(blob.alpha).cgColor
                let mid = blob.color.withAlphaComponent(blob.alpha * 0.4).cgColor
                let clear = blob.color.withAlphaComponent(0).cgColor
                guard let gradient = CGGradient(
                    colorsSpace: colorSpace,
                    colors: [peak, mid, clear] as CFArray,
                    locations: [0, 0.5, 1]
                ) else { continue }
                let normalizedCenter = animationPhase.map {
                    Self.animatedCenter(blob.center, index: index, phase: $0)
                } ?? blob.center
                let center = CGPoint(x: normalizedCenter.x * size.width, y: normalizedCenter.y * size.height)
                ctx.drawRadialGradient(
                    gradient,
                    startCenter: center,
                    startRadius: 0,
                    endCenter: center,
                    endRadius: blob.radius * longEdge,
                    options: []
                )
            }
            ctx.restoreGState()
        }

        // Faint grain to break banding on smooth dark gradients.
        if descriptor.grain > 0, let tile = Self.grainTile {
            ctx.saveGState()
            ctx.setBlendMode(.plusLighter)
            ctx.setAlpha(descriptor.grain)
            let tileSize: CGFloat = 128
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    ctx.draw(tile, in: CGRect(x: x, y: y, width: tileSize, height: tileSize))
                    x += tileSize
                }
                y += tileSize
            }
            ctx.restoreGState()
        }

        return ctx.makeImage()
    }

    /// CIImage for the recording compositor. Upright and positioned at `rect`.
    func ciImage(in rect: CGRect) -> CIImage {
        let width = max(1, Int(rect.width.rounded(.up)))
        let height = max(1, Int(rect.height.rounded(.up)))
        guard rect.width > 0, rect.height > 0,
              let cgImage = renderCGImage(pixelWidth: width, pixelHeight: height) else {
            return CIImage(color: CIColor(cgColor: solidCGColor)).cropped(to: rect)
        }
        return CIImage(cgImage: cgImage)
            .transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
            .cropped(to: rect)
    }

    /// A CALayer whose contents are the rendered background, for the live
    /// preview and the export (Core Animation) layer tree. `scale` is the pixel
    /// density: pass the backing scale for the on-screen preview, and `1` for
    /// the export merger whose frame is already in output pixels.
    func backgroundLayer(frame: CGRect, scale: CGFloat) -> CALayer {
        let layer = CALayer()
        layer.frame = frame
        layer.contentsGravity = .resize
        layer.masksToBounds = true
        layer.backgroundColor = solidCGColor
        let pixelWidth = max(1, Int((frame.width * scale).rounded(.up)))
        let pixelHeight = max(1, Int((frame.height * scale).rounded(.up)))
        layer.contents = renderCGImage(pixelWidth: pixelWidth, pixelHeight: pixelHeight)
        return layer
    }

    /// 128×128 white-noise tile, generated once and shared read-only across the
    /// preview (main) and compositor (render queue) threads.
    private static let grainTile: CGImage? = {
        let n = 128
        var bytes = [UInt8](repeating: 0, count: n * n * 4)
        for i in 0..<(n * n) {
            let v = UInt8.random(in: 0...255)
            bytes[i * 4 + 0] = v
            bytes[i * 4 + 1] = v
            bytes[i * 4 + 2] = v
            bytes[i * 4 + 3] = 255
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        return bytes.withUnsafeMutableBytes { ptr -> CGImage? in
            guard let ctx = CGContext(
                data: ptr.baseAddress,
                width: n,
                height: n,
                bitsPerComponent: 8,
                bytesPerRow: n * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            return ctx.makeImage()
        }
    }()
}

extension CanvasBackgroundStyle {
    var appearance: CanvasAppearance { CanvasAppearance(style: self) }

    var supportsBackgroundAnimation: Bool { !isSystemWallpaper && self != .black }

    var isSystemWallpaper: Bool { !systemWallpaperCandidates.isEmpty }

    var isSeasonalWallpaper: Bool {
        switch self {
        case .seasonalSpringAurora,
             .seasonalSummerCoast,
             .seasonalAutumnSonoma,
             .seasonalWinterFrost,
             .seasonalMidnightLake:
            return true
        default:
            return false
        }
    }

    var isStudioWallpaper: Bool {
        switch self {
        case .studioGraphiteGlass,
             .studioPaperWhite,
             .studioSoftSpotlight:
            return true
        default:
            return false
        }
    }

    fileprivate var systemWallpaperCandidates: [String] {
        switch self {
        case .macOSSonoma:
            return [
                "/System/Library/Desktop Pictures/Sonoma.heic",
                "/System/Library/Desktop Pictures/.thumbnails/Sonoma.heic"
            ]
        case .macOSSonomaHorizon:
            return [
                "/System/Library/Desktop Pictures/.wallpapers/Sonoma Horizon/Sonoma Horizon.heic",
                "/System/Library/Desktop Pictures/.wallpapers/Sonoma Horizon/Sonoma Horizon Thumbnail@2x.png"
            ]
        case .macOSRadialSky:
            return [
                "/System/Library/Desktop Pictures/Radial Sky Blue.heic"
            ]
        case .macOSIMacBlue:
            return [
                "/System/Library/Desktop Pictures/iMac Blue.heic"
            ]
        case .macOSIMacPurple:
            return [
                "/System/Library/Desktop Pictures/iMac Purple.heic"
            ]
        case .macOSVentura:
            return [
                "/System/Library/Desktop Pictures/Ventura Graphic.heic"
            ]
        case .macOSMonterey:
            return [
                "/System/Library/Desktop Pictures/Monterey Graphic.heic"
            ]
        case .macOSBigSur:
            return [
                "/System/Library/Desktop Pictures/Big Sur.heic"
            ]
        default:
            return []
        }
    }

    fileprivate func systemWallpaperImage(pixelWidth: Int, pixelHeight: Int) -> CGImage? {
        guard let source = SystemWallpaperImageCache.sourceImage(
            for: systemWallpaperCandidates,
            minimumLongEdge: min(pixelWidth, pixelHeight)
        ) else {
            return nil
        }
        return SystemWallpaperImageCache.aspectFill(
            source,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            representative: descriptor.representative.cgColor
        )
    }

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

enum SystemWallpaperImageCache {
    private static let lock = NSLock()
    private static var sourceCache: [String: CGImage] = [:]
    private static var renderCache: [RenderKey: CGImage] = [:]

    static func sourceImage(for candidates: [String], minimumLongEdge: Int) -> CGImage? {
        for path in candidates {
            if let cached = cachedSource(for: path),
               max(cached.width, cached.height) >= minimumLongEdge {
                return cached
            }
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let url = URL(fileURLWithPath: path)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                continue
            }
            guard max(image.width, image.height) >= minimumLongEdge else {
                continue
            }
            lock.lock()
            sourceCache[path] = image
            lock.unlock()
            return image
        }
        return nil
    }

    static func aspectFill(
        _ image: CGImage,
        pixelWidth: Int,
        pixelHeight: Int,
        representative: CGColor
    ) -> CGImage? {
        let width = max(1, pixelWidth)
        let height = max(1, pixelHeight)
        let key = RenderKey(sourceID: ObjectIdentifier(image), width: width, height: height)
        lock.lock()
        if let cached = renderCache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let target = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.setFillColor(representative)
        ctx.fill(target)

        let sourceSize = CGSize(width: image.width, height: image.height)
        let scale = max(target.width / sourceSize.width, target.height / sourceSize.height)
        let drawSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let drawRect = CGRect(
            x: (target.width - drawSize.width) / 2,
            y: (target.height - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        ctx.interpolationQuality = .high
        ctx.draw(image, in: drawRect)

        guard let rendered = ctx.makeImage() else { return nil }
        lock.lock()
        renderCache[key] = rendered
        if renderCache.count > 80 {
            renderCache.removeAll(keepingCapacity: true)
            renderCache[key] = rendered
        }
        lock.unlock()
        return rendered
    }

    private static func cachedSource(for path: String) -> CGImage? {
        lock.lock()
        let image = sourceCache[path]
        lock.unlock()
        return image
    }

    private struct RenderKey: Hashable {
        var sourceID: ObjectIdentifier
        var width: Int
        var height: Int
    }
}

/// Main-thread cache of rendered background images for SwiftUI swatches and
/// scene thumbnails. Square renders; consumers clip to circle / rounded rect.
@MainActor
enum CanvasBackgroundSwatchCache {
    private static var cache: [CanvasBackgroundStyle: Image] = [:]

    static func image(_ style: CanvasBackgroundStyle, size: Int = 320) -> Image {
        if let cached = cache[style] { return cached }
        let image: Image
        if let cgImage = style.appearance.renderCGImage(pixelWidth: size, pixelHeight: size) {
            image = Image(decorative: cgImage, scale: 1, orientation: .up)
        } else {
            image = Image(systemName: "square.fill")
        }
        cache[style] = image
        return image
    }
}
