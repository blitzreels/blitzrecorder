import AppKit
import Foundation

// Composes raw device captures into branded App Store marketing screenshots:
// brand mesh-gradient background + eyebrow + headline + the real UI inside an
// iPhone bezel. Keeps the real app UI (App Store compliant) — only the framing
// is marketing.
//
// Usage:
//   swift Scripts/compose-app-store-screenshots.swift [rawDir] [outDir]
//
// Defaults to the iPhone 6.9" upload set. Reads every *.png under rawDir and
// writes a same-named composite into outDir. Headlines are keyed by file name
// (without extension); unknown names fall back to no headline.

let args = CommandLine.arguments.dropFirst()
let rawDir = URL(fileURLWithPath: args.first ?? "AppStore/ScreenshotAssets/iPhone-6.9/raw", isDirectory: true)
let outDir = URL(fileURLWithPath: args.dropFirst().first ?? "AppStore/ScreenshotAssets/iPhone-6.9", isDirectory: true)

// Brand voice: outcome, simple, full-sentence, no em dashes. Eyebrow ties brand.
let eyebrow = "BLITZRECORDER CAMERA"
let headlines: [String: String] = [
    "01-pairing-screen": "Turn your iPhone into a studio camera for your Mac.",
    "02-connected": "Pair once and your Mac runs the shot.",
    "03-recording": "Record in studio quality, completely wireless.",
    "04-transfer": "Your finished take lands on the Mac by itself."
]

// MARK: - Colours (brand: mint accent over deep ink)

func srgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
}
let mint = srgb(0.09, 1.0, 0.65)               // BlitzUI.mint
let inkTop = srgb(0.055, 0.102, 0.090)         // deep teal-ink
let inkBottom = srgb(0.027, 0.043, 0.039)      // near black
let white = NSColor.white

// MARK: - Helpers

func loadImage(_ url: URL) -> NSImage? { NSImage(contentsOf: url) }

func radialGlow(center: CGPoint, radius: CGFloat, color: NSColor) {
    guard let g = NSGradient(colors: [color, color.withAlphaComponent(0)]) else { return }
    g.draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
}

func roundedRectPath(_ rect: CGRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func compose(raw: NSImage, headline: String?) -> NSBitmapImageRep {
    // Canvas == an accepted iPhone 6.9" size; matches the raw capture.
    let W = 1320, H = 2868
    let canvas = CGRect(x: 0, y: 0, width: CGFloat(W), height: CGFloat(H))

    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: W, height: H) // 1 pixel per point → exact pixels

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.interpolationQuality = .high

    // ---- Background: vertical ink gradient + mint glows (mesh-ish) ----
    NSGradient(colors: [inkTop, inkBottom])?.draw(in: canvas, angle: -90)
    radialGlow(center: CGPoint(x: CGFloat(W) * 0.86, y: CGFloat(H) * 0.88),
               radius: CGFloat(W) * 0.78, color: mint.withAlphaComponent(0.20))
    radialGlow(center: CGPoint(x: CGFloat(W) * 0.08, y: CGFloat(H) * 0.20),
               radius: CGFloat(W) * 0.70, color: srgb(0.10, 0.55, 0.78).withAlphaComponent(0.16))
    // Edge vignette for focus on the device.
    if let v = NSGradient(colors: [NSColor.black.withAlphaComponent(0), NSColor.black.withAlphaComponent(0.34)]) {
        v.draw(fromCenter: CGPoint(x: CGFloat(W) / 2, y: CGFloat(H) * 0.46), radius: CGFloat(W) * 0.30,
               toCenter: CGPoint(x: CGFloat(W) / 2, y: CGFloat(H) * 0.46), radius: CGFloat(W) * 0.95, options: [])
    }

    // ---- Type (top zone). AppKit draws upright + top-aligned within a rect. ----
    let padX: CGFloat = 120
    func yFromTop(_ top: CGFloat, _ height: CGFloat) -> CGFloat { CGFloat(H) - top - height }

    let eyeStyle = NSMutableParagraphStyle(); eyeStyle.alignment = .left
    let eyeAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 30, weight: .semibold),
        .foregroundColor: mint, .kern: 4.0, .paragraphStyle: eyeStyle
    ]
    NSAttributedString(string: eyebrow, attributes: eyeAttrs)
        .draw(in: CGRect(x: padX, y: yFromTop(212, 46), width: CGFloat(W) - padX * 2, height: 46))

    if let headline {
        let hStyle = NSMutableParagraphStyle()
        hStyle.alignment = .left; hStyle.lineHeightMultiple = 1.04; hStyle.lineBreakMode = .byWordWrapping
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 18; shadow.shadowOffset = NSSize(width: 0, height: -3)
        let hAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 108, weight: .bold),
            .foregroundColor: white, .paragraphStyle: hStyle, .shadow: shadow
        ]
        NSAttributedString(string: headline, attributes: hAttrs)
            .draw(in: CGRect(x: padX, y: yFromTop(288, 560), width: CGFloat(W) - padX * 2, height: 560))
    }

    // ---- Device bezel with the real screenshot ----
    let rawAspect = raw.size.width / raw.size.height
    let screenW = CGFloat(W) * 0.70
    let screenH = screenW / rawAspect
    let t: CGFloat = 22                       // bezel thickness
    let screenRadius = screenW * 0.095
    let outerW = screenW + t * 2
    let outerH = screenH + t * 2
    let originX = (CGFloat(W) - outerW) / 2
    // Bottom-anchored: fixed bottom margin keeps the device a hero and the
    // headline gets whatever space is left above it.
    let bottomMargin: CGFloat = 132
    let originY = bottomMargin

    let outerRect = CGRect(x: originX, y: originY, width: outerW, height: outerH)
    let screenRect = CGRect(x: originX + t, y: originY + t, width: screenW, height: screenH)

    // Soft drop shadow under the device.
    NSGraphicsContext.saveGraphicsState()
    let devShadow = NSShadow()
    devShadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
    devShadow.shadowBlurRadius = 70; devShadow.shadowOffset = NSSize(width: 0, height: -26)
    devShadow.set()
    let bezel = roundedRectPath(outerRect, radius: screenRadius + t)
    srgb(0.039, 0.039, 0.047).setFill()       // near-black bezel
    bezel.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Clip + draw the real UI into the screen.
    NSGraphicsContext.saveGraphicsState()
    roundedRectPath(screenRect, radius: screenRadius).addClip()
    raw.draw(in: screenRect, from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    // Screen inner hairline + bezel outer hairline for crispness.
    let inner = roundedRectPath(screenRect, radius: screenRadius)
    inner.lineWidth = 2; white.withAlphaComponent(0.06).setStroke(); inner.stroke()
    let outer = roundedRectPath(outerRect, radius: screenRadius + t)
    outer.lineWidth = 2; white.withAlphaComponent(0.12).setStroke(); outer.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - Run

let fm = FileManager.default
try fm.createDirectory(at: outDir, withIntermediateDirectories: true)

let rawFiles = (try? fm.contentsOfDirectory(at: rawDir, includingPropertiesForKeys: nil))?
    .filter { $0.pathExtension.lowercased() == "png" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []

if rawFiles.isEmpty {
    FileHandle.standardError.write(Data("error: no raw PNGs in \(rawDir.path)\n".utf8))
    exit(1)
}

for file in rawFiles {
    let name = file.deletingPathExtension().lastPathComponent
    guard let raw = loadImage(file) else {
        FileHandle.standardError.write(Data("error: could not read \(file.path)\n".utf8))
        exit(1)
    }
    let rep = compose(raw: raw, headline: headlines[name])
    guard let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("error: PNG encode failed for \(name)\n".utf8))
        exit(1)
    }
    let out = outDir.appendingPathComponent(file.lastPathComponent)
    try png.write(to: out)
    print("✓ composed \(out.lastPathComponent) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
}
