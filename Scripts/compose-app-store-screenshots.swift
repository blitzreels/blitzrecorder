import AppKit
import CoreText
import Foundation

// Composes raw device captures into branded App Store marketing screenshots
// using the blitzrecorder.com landing page design system: ink background
// (#050807), emerald aurora glows, Schibsted Grotesk display headlines with
// the landing `.text-gradient` on the key phrase, Hanken Grotesk body, mint
// check items, and the real UI inside device bezels (App Store compliant —
// only the framing is marketing).
//
// ASO story order: what it is (Mac + iPhone duo) → pair with a code →
// control from the Mac → full-quality recording → automatic transfer.
// The Mac app requirement is visible (MacBook frame) and written in the copy.
//
// Usage:
//   swift Scripts/compose-app-store-screenshots.swift [rawDir] [outDir] [WxH] [device]
//
// Defaults to the iPhone 6.9" upload set (1320x2868, device=iphone).
// For the iPad 13" set:
//   swift Scripts/compose-app-store-screenshots.swift \
//     AppStore/ScreenshotAssets/iPad-13/raw AppStore/ScreenshotAssets/iPad-13 2064x2752 ipad

let args = Array(CommandLine.arguments.dropFirst())
let rawDir = URL(fileURLWithPath: args.count > 0 ? args[0] : "AppStore/ScreenshotAssets/iPhone-6.9/raw", isDirectory: true)
let outDir = URL(fileURLWithPath: args.count > 1 ? args[1] : "AppStore/ScreenshotAssets/iPhone-6.9", isDirectory: true)
let canvasSpec = (args.count > 2 ? args[2] : "1320x2868").split(separator: "x").compactMap { Int($0) }
let W = canvasSpec.count == 2 ? canvasSpec[0] : 1320
let H = canvasSpec.count == 2 ? canvasSpec[1] : 2868
let deviceKind = args.count > 3 ? args[3] : "iphone"

// The Mac studio UI shown inside the MacBook frame (same asset as the landing hero).
let macUIPath = "Web/blitzrecorder/public/generated-screens/macos-recorder-live.png"

// MARK: - Fonts (landing: Schibsted Grotesk display, Hanken Grotesk body)

let fontsDir = URL(fileURLWithPath: "AppStore/ScreenshotAssets/fonts", isDirectory: true)
for file in ["SchibstedGrotesk.ttf", "HankenGrotesk.ttf"] {
    let url = fontsDir.appendingPathComponent(file)
    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
}

/// Variable-font instance at a given wght axis value. 0x77676874 == 'wght'.
func vfont(_ family: String, weight: CGFloat, size: CGFloat) -> NSFont {
    let variationKey = NSFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
    let desc = NSFontDescriptor(fontAttributes: [
        .family: family,
        variationKey: [2003265652: weight],
    ])
    return NSFont(descriptor: desc, size: size) ?? .systemFont(ofSize: size, weight: .bold)
}
func display(_ weight: CGFloat, _ size: CGFloat) -> NSFont { vfont("Schibsted Grotesk", weight: weight, size: size) }
func body(_ weight: CGFloat, _ size: CGFloat) -> NSFont { vfont("Hanken Grotesk", weight: weight, size: size) }

// MARK: - Colours (landing globals.css)

func srgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
}
func hex(_ v: UInt32, _ a: Double = 1) -> NSColor {
    srgb(Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255, a)
}
let ink = hex(0x050807)            // --background
let mint = hex(0x5EF2AF)           // --primary
let mutedText = hex(0xB3C4BD)      // --muted-foreground
let teal = srgb(0.10, 0.55, 0.78)  // cool counter-light
let recordRed = srgb(1.0, 0.27, 0.23)
// .text-gradient stops
let gradTop = hex(0xB6FFE1), gradMid = hex(0x5EF2AF), gradBottom = hex(0x2FCF93)

// MARK: - Slide configuration

struct Glow { let x: CGFloat; let y: CGFloat; let r: CGFloat; let color: NSColor } // fractions of W/H
struct MacLayer {
    let width: CGFloat       // fraction of W
    let topFrac: CGFloat     // top edge, fraction of H from top
    var shiftX: CGFloat = 0  // px at 1320 scale
}
struct Slide {
    let out: String                          // output file name (no extension)
    let phoneRaw: String                     // raw capture name in rawDir
    let eyebrow: String
    var eyebrowDot: NSColor? = nil           // ● REC indicator
    let headline: String                     // \n for manual breaks
    let gradientPhrase: String               // substring drawn with .text-gradient
    var sub: String? = nil
    var checks: [String] = []
    let glows: [Glow]
    var mac: MacLayer? = nil                 // MacBook behind the phone
    var phoneWidth: CGFloat = 0.70           // fraction of W
    var phoneRotation: CGFloat = 0           // degrees
    var phoneBottom: CGFloat = 130           // bottom margin; negative bleeds off-canvas
    var phoneTopFrac: CGFloat? = nil         // overrides phoneBottom when set
    var phoneShiftX: CGFloat = 0
}

// Brand voice: landing page copy, 5th-grade simple, full sentences, no em dashes.
let slides: [Slide] = [
    Slide(
        out: "01-hero-mac-iphone", phoneRaw: "02-connected",
        eyebrow: "MAC + IPHONE",
        headline: "iPhone camera\nfor your Mac.",
        gradientPhrase: "for your Mac.",
        sub: "Studio quality video, run from the free Mac app.",
        glows: [
            Glow(x: 0.50, y: 1.02, r: 0.95, color: mint.withAlphaComponent(0.20)),
            Glow(x: 0.92, y: 0.66, r: 0.55, color: teal.withAlphaComponent(0.10)),
        ],
        mac: MacLayer(width: 0.97, topFrac: 0.345),
        phoneWidth: 0.38, phoneRotation: 5, phoneTopFrac: 0.50, phoneShiftX: 330
    ),
    Slide(
        out: "02-pairing", phoneRaw: "01-pairing-screen",
        eyebrow: "EASY SETUP",
        headline: "Pair once with\na 6-digit code.",
        gradientPhrase: "a 6-digit code.",
        sub: "Open the Mac app and type the code.",
        glows: [
            Glow(x: 0.06, y: 0.62, r: 0.70, color: mint.withAlphaComponent(0.16)),
            Glow(x: 0.90, y: 0.10, r: 0.60, color: teal.withAlphaComponent(0.10)),
        ],
        phoneWidth: 0.66, phoneBottom: 120
    ),
    Slide(
        out: "03-mac-control", phoneRaw: "02-connected",
        eyebrow: "REMOTE CONTROL",
        headline: "Camera controls\non your Mac.",
        gradientPhrase: "on your Mac.",
        checks: ["Zoom, focus, and exposure", "Pick any lens", "The phone stays on its tripod"],
        glows: [
            Glow(x: 0.04, y: 0.20, r: 0.62, color: teal.withAlphaComponent(0.10)),
            Glow(x: 0.85, y: 0.92, r: 0.80, color: mint.withAlphaComponent(0.18)),
        ],
        mac: MacLayer(width: 1.08, topFrac: 0.42),
        phoneWidth: 0.32, phoneRotation: -4, phoneTopFrac: 0.56, phoneShiftX: -370
    ),
    Slide(
        out: "04-recording", phoneRaw: "03-recording",
        eyebrow: "RECORDING",
        eyebrowDot: recordRed,
        headline: "Video recording,\nnot a stream.",
        gradientPhrase: "not a stream.",
        sub: "The full file saves on your iPhone.",
        glows: [
            Glow(x: 0.94, y: 0.96, r: 0.72, color: mint.withAlphaComponent(0.18)),
            Glow(x: 0.04, y: 0.16, r: 0.60, color: recordRed.withAlphaComponent(0.07)),
        ],
        phoneWidth: 0.78, phoneBottom: -190
    ),
    Slide(
        out: "05-transfer", phoneRaw: "04-transfer",
        eyebrow: "AUTO TRANSFER",
        headline: "Your take lands\non your Mac.",
        gradientPhrase: "on your Mac.",
        sub: "Sends itself over Wi-Fi. No cable.",
        glows: [
            Glow(x: 0.88, y: 0.16, r: 0.78, color: mint.withAlphaComponent(0.22)),
            Glow(x: 0.06, y: 0.92, r: 0.55, color: teal.withAlphaComponent(0.08)),
        ],
        mac: MacLayer(width: 0.60, topFrac: 0.45, shiftX: -210),
        phoneWidth: 0.50, phoneRotation: -3, phoneTopFrac: 0.385, phoneShiftX: 250
    ),
]

// MARK: - Drawing helpers

func loadImage(_ url: URL) -> NSImage? { NSImage(contentsOf: url) }

func radialGlow(_ ctx: CGContext, center: CGPoint, radius: CGFloat, color: NSColor) {
    guard let g = NSGradient(colors: [color, color.withAlphaComponent(0)]) else { return }
    g.draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
}

func roundedRectPath(_ rect: CGRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

/// Renders an attributed string offscreen and uses it as an alpha mask to fill
/// the landing `.text-gradient` (176deg, #b6ffe1 → #5ef2af → #2fcf93).
func drawGradientText(_ ctx: CGContext, _ text: NSAttributedString, in rect: CGRect) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    text.draw(in: rect)
    NSGraphicsContext.restoreGraphicsState()
    guard let mask = rep.cgImage else { return }

    ctx.saveGState()
    ctx.clip(to: CGRect(x: 0, y: 0, width: W, height: H), mask: mask)
    let colors = [gradTop.cgColor, gradMid.cgColor, gradBottom.cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.52, 1])!
    // 176deg ≈ vertical with a slight lean; CG origin is bottom-left.
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.midX - rect.height * 0.035, y: rect.maxY),
        end: CGPoint(x: rect.midX + rect.height * 0.035, y: rect.minY),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    ctx.restoreGState()
}

func checkCircle(_ ctx: CGContext, at center: CGPoint, radius: CGFloat) {
    mint.withAlphaComponent(0.15).setFill()
    NSBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()
    let check = NSBezierPath()
    check.move(to: CGPoint(x: center.x - radius * 0.42, y: center.y + radius * 0.02))
    check.line(to: CGPoint(x: center.x - radius * 0.10, y: center.y - radius * 0.32))
    check.line(to: CGPoint(x: center.x + radius * 0.46, y: center.y + radius * 0.30))
    check.lineWidth = radius * 0.22
    check.lineCapStyle = .round
    check.lineJoinStyle = .round
    mint.setStroke()
    check.stroke()
}

/// MacBook frame, matching the landing hero: aluminum rim, black bezel with a
/// camera notch, the studio UI inside, and a bottom deck with a thumb groove.
func drawMacBook(_ ctx: CGContext, ui: NSImage, width: CGFloat, topY: CGFloat, shiftX: CGFloat, scale: CGFloat) {
    let rim: CGFloat = 3 * scale
    let bezelPad: CGFloat = 11 * scale
    let uiAspect = ui.size.width / ui.size.height
    let uiW = width - (rim + bezelPad) * 2
    let uiH = uiW / uiAspect
    let bodyW = width
    let bodyH = uiH + (rim + bezelPad) * 2
    let x = (CGFloat(W) - bodyW) / 2 + shiftX
    let yTop = CGFloat(H) - topY            // CG bottom-left origin
    let yBottom = yTop - bodyH
    let bodyRect = CGRect(x: x, y: yBottom, width: bodyW, height: bodyH)

    // Soft shadow.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.60)
    shadow.shadowBlurRadius = 90
    shadow.shadowOffset = NSSize(width: 0, height: -34)
    shadow.set()
    hex(0x26262A).setFill()
    roundedRectPath(bodyRect, radius: 20 * scale).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Aluminum rim (brighter top, like the landing's gradient).
    if let rimGrad = NSGradient(colors: [hex(0x5B5B60), hex(0x26262A)]) {
        NSGraphicsContext.saveGraphicsState()
        roundedRectPath(bodyRect, radius: 20 * scale).addClip()
        rimGrad.draw(in: bodyRect, angle: -90)
        NSGraphicsContext.restoreGraphicsState()
    }

    // Black bezel.
    let bezelRect = bodyRect.insetBy(dx: rim, dy: rim)
    hex(0x08080A).setFill()
    roundedRectPath(bezelRect, radius: 18 * scale).fill()

    // The studio UI.
    let uiRect = CGRect(x: x + rim + bezelPad, y: yBottom + rim + bezelPad, width: uiW, height: uiH)
    NSGraphicsContext.saveGraphicsState()
    roundedRectPath(uiRect, radius: 10 * scale).addClip()
    ui.draw(in: uiRect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    let uiRing = roundedRectPath(uiRect, radius: 10 * scale)
    uiRing.lineWidth = 1.5
    NSColor.white.withAlphaComponent(0.05).setStroke()
    uiRing.stroke()

    // Camera notch (top center, on top of the UI).
    let notchW = bodyW * 0.16
    let notchH = 17 * scale
    let notchRect = CGRect(x: x + (bodyW - notchW) / 2, y: yTop - rim - notchH, width: notchW, height: notchH)
    let notch = NSBezierPath()
    notch.move(to: CGPoint(x: notchRect.minX, y: notchRect.maxY))
    notch.line(to: CGPoint(x: notchRect.maxX, y: notchRect.maxY))
    notch.line(to: CGPoint(x: notchRect.maxX, y: notchRect.minY + 7 * scale))
    notch.appendArc(withCenter: CGPoint(x: notchRect.maxX - 7 * scale, y: notchRect.minY + 7 * scale), radius: 7 * scale, startAngle: 0, endAngle: -90, clockwise: true)
    notch.line(to: CGPoint(x: notchRect.minX + 7 * scale, y: notchRect.minY))
    notch.appendArc(withCenter: CGPoint(x: notchRect.minX + 7 * scale, y: notchRect.minY + 7 * scale), radius: 7 * scale, startAngle: -90, endAngle: -180, clockwise: true)
    notch.close()
    hex(0x08080A).setFill()
    notch.fill()
    NSColor.white.withAlphaComponent(0.30).setFill()
    let camR = 2.2 * scale
    NSBezierPath(ovalIn: CGRect(x: notchRect.midX - camR, y: notchRect.midY - camR, width: camR * 2, height: camR * 2)).fill()

    // Bottom deck.
    let deckW = bodyW * 1.04
    let deckH = 15 * scale
    let deckRect = CGRect(x: x - bodyW * 0.02, y: yBottom - deckH, width: deckW, height: deckH)
    if let deckGrad = NSGradient(colors: [hex(0x6A6A70), hex(0x34343A), hex(0x161618)]) {
        NSGraphicsContext.saveGraphicsState()
        let deckPath = NSBezierPath()
        deckPath.appendRoundedRect(deckRect, xRadius: 7 * scale, yRadius: 7 * scale)
        deckPath.addClip()
        deckGrad.draw(in: deckRect, angle: -90)
        NSGraphicsContext.restoreGraphicsState()
    }
    let grooveW = deckW * 0.13
    let groove = CGRect(x: deckRect.midX - grooveW / 2, y: deckRect.maxY - 7 * scale, width: grooveW, height: 7 * scale)
    hex(0x1B1B1E).setFill()
    roundedRectPath(groove, radius: 4 * scale).fill()
}

// MARK: - Compose

func compose(phoneRaw: NSImage, macUI: NSImage?, slide: Slide) -> NSBitmapImageRep {
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

    // ---- Background: ink + per-slide aurora glows (landing SiteBackground) ----
    ink.setFill()
    ctx.fill(canvas)
    for glow in slide.glows {
        radialGlow(ctx, center: CGPoint(x: CGFloat(W) * glow.x, y: CGFloat(H) * glow.y),
                   radius: CGFloat(W) * glow.r, color: glow.color)
    }

    // ---- Type (top zone, AppKit rect coords measured from top) ----
    let padX: CGFloat = 116
    let textWidth = CGFloat(W) - padX * 2
    func yFromTop(_ top: CGFloat, _ height: CGFloat) -> CGFloat { CGFloat(H) - top - height }
    var cursorTop: CGFloat = 196
    // Type scale follows the smaller proportion so the squarer iPad canvas
    // doesn't blow the text zone past the device.
    let scale = min(CGFloat(W) / 1320, CGFloat(H) / 2868)

    // Eyebrow: gradient dash + tracked caps (landing Eyebrow component).
    let dashY = yFromTop(cursorTop + 21 * scale, 3)
    if let dash = NSGradient(colors: [mint.withAlphaComponent(0), mint.withAlphaComponent(0.7)]) {
        dash.draw(in: CGRect(x: padX, y: dashY, width: 56 * scale, height: 3), angle: 0)
    }
    var eyebrowX = padX + 76 * scale
    if let dot = slide.eyebrowDot {
        dot.setFill()
        let r = 12 * scale
        NSBezierPath(ovalIn: CGRect(x: eyebrowX, y: dashY - r + 2, width: r * 2, height: r * 2)).fill()
        eyebrowX += r * 2 + 18 * scale
    }
    let eyeAttrs: [NSAttributedString.Key: Any] = [
        .font: body(620, 31 * scale), .foregroundColor: mint, .kern: 6.5 * scale,
    ]
    NSAttributedString(string: slide.eyebrow, attributes: eyeAttrs)
        .draw(at: CGPoint(x: eyebrowX, y: yFromTop(cursorTop, 44 * scale)))
    cursorTop += 104 * scale

    // Headline: Schibsted bold, white, gradient on the key phrase.
    let hStyle = NSMutableParagraphStyle()
    hStyle.lineHeightMultiple = 0.99
    hStyle.lineBreakMode = .byWordWrapping
    let hFont = display(700, 116 * scale)
    let lineCount = slide.headline.components(separatedBy: "\n").count
    let hHeight = CGFloat(lineCount) * 132 * scale + 24 * scale
    let hRect = CGRect(x: padX, y: yFromTop(cursorTop, hHeight), width: textWidth, height: hHeight)

    let whitePass = NSMutableAttributedString(
        string: slide.headline,
        attributes: [.font: hFont, .foregroundColor: NSColor.white, .paragraphStyle: hStyle, .kern: -1.5]
    )
    let gradPass = NSMutableAttributedString(
        string: slide.headline,
        attributes: [.font: hFont, .foregroundColor: NSColor.clear, .paragraphStyle: hStyle, .kern: -1.5]
    )
    if let range = slide.headline.range(of: slide.gradientPhrase) {
        let nsRange = NSRange(range, in: slide.headline)
        whitePass.addAttribute(.foregroundColor, value: NSColor.clear, range: nsRange)
        gradPass.addAttribute(.foregroundColor, value: NSColor.white, range: nsRange)
    }
    whitePass.draw(in: hRect)
    drawGradientText(ctx, gradPass, in: hRect)
    cursorTop += CGFloat(lineCount) * 132 * scale + 38 * scale

    // Sub: Hanken, muted (landing Paragraph).
    if let sub = slide.sub {
        let sStyle = NSMutableParagraphStyle()
        sStyle.lineHeightMultiple = 1.16
        sStyle.lineBreakMode = .byWordWrapping
        let sAttrs: [NSAttributedString.Key: Any] = [
            .font: body(420, 47 * scale), .foregroundColor: mutedText, .paragraphStyle: sStyle,
        ]
        let bound = NSAttributedString(string: sub, attributes: sAttrs)
            .boundingRect(with: NSSize(width: textWidth * 0.94, height: 400), options: [.usesLineFragmentOrigin])
        NSAttributedString(string: sub, attributes: sAttrs)
            .draw(in: CGRect(x: padX, y: yFromTop(cursorTop, bound.height + 8), width: textWidth * 0.94, height: bound.height + 8))
        cursorTop += bound.height + 26 * scale
    }

    // Check items (landing CheckItem): mint circle + check + white text.
    if !slide.checks.isEmpty {
        cursorTop += 8 * scale
        for item in slide.checks {
            let rowH: CGFloat = 84 * scale
            let circleR: CGFloat = 27 * scale
            let rowCenterY = yFromTop(cursorTop, rowH) + rowH / 2
            checkCircle(ctx, at: CGPoint(x: padX + circleR, y: rowCenterY), radius: circleR)
            let cAttrs: [NSAttributedString.Key: Any] = [
                .font: body(480, 47 * scale), .foregroundColor: hex(0xF4FAF7),
            ]
            let text = NSAttributedString(string: item, attributes: cAttrs)
            text.draw(at: CGPoint(x: padX + circleR * 2 + 26 * scale, y: rowCenterY - text.size().height / 2))
            cursorTop += rowH
        }
    }

    // ---- MacBook layer (behind the phone) ----
    if let mac = slide.mac, let macUI {
        drawMacBook(ctx, ui: macUI, width: CGFloat(W) * mac.width,
                    topY: CGFloat(H) * mac.topFrac, shiftX: mac.shiftX * scale, scale: scale)
    }

    // ---- iPhone bezel with the real capture ----
    let rawAspect = phoneRaw.size.width / phoneRaw.size.height
    let screenW = CGFloat(W) * slide.phoneWidth
    let screenH = screenW / rawAspect
    let t: CGFloat = max(10, 22 * scale * (slide.phoneWidth / 0.70))
    let screenRadius = deviceKind == "ipad" ? screenW * 0.045 : screenW * 0.095
    let outerW = screenW + t * 2
    let outerH = screenH + t * 2
    let originX = (CGFloat(W) - outerW) / 2 + slide.phoneShiftX * scale
    let originY: CGFloat
    if let topFrac = slide.phoneTopFrac {
        originY = CGFloat(H) - CGFloat(H) * topFrac - outerH
    } else {
        originY = slide.phoneBottom
    }

    ctx.saveGState()
    let rotation = slide.phoneRotation * .pi / 180
    if rotation != 0 {
        let cx = originX + outerW / 2, cy = originY + outerH / 2
        ctx.translateBy(x: cx, y: cy)
        ctx.rotate(by: rotation)
        ctx.translateBy(x: -cx, y: -cy)
    }

    let outerRect = CGRect(x: originX, y: originY, width: outerW, height: outerH)
    let screenRect = CGRect(x: originX + t, y: originY + t, width: screenW, height: screenH)

    // Soft drop shadow under the device.
    NSGraphicsContext.saveGraphicsState()
    let devShadow = NSShadow()
    devShadow.shadowColor = NSColor.black.withAlphaComponent(0.62)
    devShadow.shadowBlurRadius = 80
    devShadow.shadowOffset = NSSize(width: 0, height: -30)
    devShadow.set()
    let bezel = roundedRectPath(outerRect, radius: screenRadius + t)
    srgb(0.039, 0.039, 0.047).setFill() // near-black bezel
    bezel.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Clip + draw the real UI into the screen.
    NSGraphicsContext.saveGraphicsState()
    roundedRectPath(screenRect, radius: screenRadius).addClip()
    phoneRaw.draw(in: screenRect, from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    // ring-gradient: brighter on top, fading down (landing .ring-gradient).
    let inner = roundedRectPath(screenRect, radius: screenRadius)
    inner.lineWidth = 2
    NSColor.white.withAlphaComponent(0.06).setStroke()
    inner.stroke()
    ctx.saveGState()
    ctx.setLineWidth(2.5)
    if let ring = NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0.05)]) {
        ctx.addPath(CGPath(roundedRect: outerRect.insetBy(dx: -1, dy: -1), cornerWidth: screenRadius + t, cornerHeight: screenRadius + t, transform: nil))
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        ring.draw(in: outerRect.insetBy(dx: -3, dy: -3), angle: -90)
    }
    ctx.restoreGState()

    ctx.restoreGState() // rotation

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - Run

let fm = FileManager.default
try fm.createDirectory(at: outDir, withIntermediateDirectories: true)

let macUI = loadImage(URL(fileURLWithPath: macUIPath))
if macUI == nil {
    FileHandle.standardError.write(Data("warning: \(macUIPath) not found; Mac layers skipped\n".utf8))
}

var rendered = 0
for var slide in slides {
    let rawURL = rawDir.appendingPathComponent("\(slide.phoneRaw).png")
    guard let raw = loadImage(rawURL) else { continue } // iPad set only has the pairing capture
    if deviceKind == "ipad" {
        // The 4:3 iPad capture is much taller once framed; pull it in, keep it
        // upright, and skip the Mac layer so the text zone stays clear.
        slide.phoneWidth = 0.62
        slide.phoneBottom = -100
        slide.phoneTopFrac = nil
        slide.phoneRotation = 0
        slide.phoneShiftX = 0
        slide.mac = nil
    }
    let rep = compose(phoneRaw: raw, macUI: macUI, slide: slide)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("error: PNG encode failed for \(slide.out)\n".utf8))
        exit(1)
    }
    let out = outDir.appendingPathComponent("\(slide.out).png")
    try png.write(to: out)
    rendered += 1
    print("✓ composed \(out.lastPathComponent) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
}
if rendered == 0 {
    FileHandle.standardError.write(Data("error: no slides rendered from \(rawDir.path)\n".utf8))
    exit(1)
}
