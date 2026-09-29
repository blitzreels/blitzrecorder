import AppKit
import CoreImage
import ImageIO
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
