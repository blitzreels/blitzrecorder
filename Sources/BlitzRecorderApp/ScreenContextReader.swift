import AppKit
import ApplicationServices
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers
import Vision

struct ScreenMoment: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    /// Seconds on the take timeline.
    let time: Double
    let app: String
    let window: String?
    let text: String
    /// Web addresses and ticket IDs read on screen, such as LIN-482.
    var links: [String] = []

    var heading: String {
        [app, window].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
    }
}

/// What the person recording is looking at: the frontmost app and window, and the text in that window. The text
/// is read on the Mac and only kept with the take's notes.
enum ScreenContextReader {
    struct Frontmost: Sendable {
        let app: String
        let processID: pid_t
        let window: String?
    }

    static let maximumTextCharacters = 600

    /// Apps whose windows hold passwords, keys or system secrets: never read, titled or saved with a take.
    static let privateApps: Set<String> = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop", "com.dashlane.dashlanephonefinal",
        "com.lastpass.LastPass", "in.sinew.Enpass-Desktop", "org.keepassxc.keepassxc", "com.apple.Passwords",
        "com.apple.keychainaccess", "com.apple.systempreferences", "com.apple.SecurityAgent",
        "com.apple.LocalAuthentication.UIAgent",
    ]

    /// The frontmost app other than BlitzRecorder and the private apps, with the title of its focused window when
    /// Accessibility allows it.
    @MainActor
    static func frontmost() -> Frontmost? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = app.bundleIdentifier,
              bundleIdentifier != Bundle.main.bundleIdentifier,
              !privateApps.contains(bundleIdentifier) else { return nil }
        return Frontmost(app: app.localizedName ?? "App", processID: app.processIdentifier,
                         window: focusedWindowTitle(app.processIdentifier))
    }

    private static func focusedWindowTitle(_ processID: pid_t) -> String? {
        let element = AXUIElementCreateApplication(processID)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success
        else { return nil }
        let text = (title as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    struct TextRequest: Sendable {
        let processID: pid_t
        let languages: [String]
    }

    struct WindowGlance: @unchecked Sendable {
        let text: String
        let image: CGImage?
    }

    /// The frontmost window of the app and its text, top to bottom; empty when the window can't be read.
    static func windowGlance(_ request: TextRequest) async -> WindowGlance {
        guard let image = await frontWindowImage(request.processID) else { return WindowGlance(text: "", image: nil) }
        return WindowGlance(text: recognizedText(.init(image: image, languages: request.languages)), image: image)
    }

    private static let ticketPattern = try? NSRegularExpression(pattern: "\\b[A-Z][A-Z0-9]{1,9}-\\d{1,6}\\b")

    /// Web addresses and ticket IDs in text read from the screen.
    static func links(in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let urls = (detector?.matches(in: text, range: range) ?? []).compactMap { $0.url?.absoluteString }
            .filter { !$0.hasPrefix("mailto:") }
        let tickets = (ticketPattern?.matches(in: text, range: range) ?? []).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
        var seen = Set<String>()
        return (urls + tickets).filter { seen.insert($0).inserted }
    }

    /// Names and terms that recur on screen: words with capitals inside, acronyms and ticket IDs, which speech
    /// recognition tends to mishear.
    static func terms(in texts: [String]) -> [String] {
        var counts: [String: Int] = [:]
        for text in texts {
            let words = Set(text.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" }).map(String.init))
            for word in words where word.count >= 2 && word.count <= 24 {
                let capitals = word.filter(\.isUppercase).count
                let isAcronym = capitals == word.filter(\.isLetter).count && capitals >= 2
                let hasInnerCapital = word.dropFirst().contains(where: \.isUppercase) && word.contains(where: \.isLowercase)
                guard isAcronym || hasInnerCapital || word.contains("-") && capitals > 0 else { continue }
                counts[word, default: 0] += 1
            }
        }
        return counts.filter { $0.value >= 2 }.sorted { $0.value > $1.value || $0.value == $1.value && $0.key < $1.key }
            .prefix(30).map(\.key)
    }

    struct Thumbnail {
        let image: CGImage
        let url: URL
    }

    /// Writes a JPEG at most 960 points wide.
    static func saveThumbnail(_ thumbnail: Thumbnail) -> Bool {
        let scale = min(1, 960 / CGFloat(thumbnail.image.width))
        let width = max(1, Int(CGFloat(thumbnail.image.width) * scale))
        let height = max(1, Int(CGFloat(thumbnail.image.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
        context.interpolationQuality = .high
        context.draw(thumbnail.image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return false }
        try? FileManager.default.createDirectory(at: thumbnail.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(thumbnail.url as CFURL, UTType.jpeg.identifier as CFString,
                                                                1, nil) else { return false }
        CGImageDestinationAddImage(destination, scaled, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    private static func frontWindowImage(_ processID: pid_t) async -> CGImage? {
        let listed = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        guard let windowNumber = listed.first(where: {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == processID && ($0[kCGWindowLayer as String] as? Int) == 0
        })?[kCGWindowNumber as String] as? CGWindowID,
              let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
              let window = content.windows.first(where: { $0.windowID == windowNumber }),
              window.frame.width >= 80, window.frame.height >= 80 else { return nil }
        let configuration = SCStreamConfiguration()
        let scale = min(1, 1_600 / window.frame.width)
        configuration.width = max(2, Int(window.frame.width * 2 * scale))
        configuration.height = max(2, Int(window.frame.height * 2 * scale))
        configuration.showsCursor = false
        return try? await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration
        )
    }

    private struct Recognition {
        let image: CGImage
        let languages: [String]
    }

    private static func recognizedText(_ recognition: Recognition) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if !recognition.languages.isEmpty { request.recognitionLanguages = recognition.languages }
        guard (try? VNImageRequestHandler(cgImage: recognition.image).perform([request])) != nil else { return "" }
        let lines = (request.results ?? [])
            .sorted {
                abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.01
                    ? $0.boundingBox.midY > $1.boundingBox.midY : $0.boundingBox.minX < $1.boundingBox.minX
            }
            .compactMap { $0.topCandidates(1).first }
            .filter { $0.confidence >= 0.4 && $0.string.trimmingCharacters(in: .whitespaces).count >= 2 }
            .map(\.string)
        var text = ""
        for line in lines {
            guard text.count + line.count + 3 <= maximumTextCharacters else { break }
            text += text.isEmpty ? line : " · " + line
        }
        return text
    }

    struct Comparison {
        let previous: ScreenMoment
        let app: String
        let window: String?
        let text: String
    }

    /// True when the screen still shows mostly the same words in the same window.
    static func isSame(_ comparison: Comparison) -> Bool {
        guard comparison.previous.app == comparison.app, comparison.previous.window == comparison.window else {
            return false
        }
        let before = Set(comparison.previous.text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }))
        let after = Set(comparison.text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }))
        guard !before.isEmpty || !after.isEmpty else { return true }
        return Double(before.intersection(after).count) / Double(before.union(after).count) >= 0.6
    }
}
