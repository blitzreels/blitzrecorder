import AppKit
import ApplicationServices
import AVFoundation
import Darwin
import Foundation
import Speech

@MainActor
enum AppSupportActions {
    static func showAboutPanel() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        let credits = NSMutableAttributedString(string: """
        A screen, camera, and audio recorder for creators.

        Website: \(AppLinks.landingPage.absoluteString)
        GitHub: https://github.com/blitzreels/blitzrecorder-public
        License: AGPLv3.

        Includes Sparkle for direct-download app updates.
        """)
        credits.addAttribute(
            .font,
            value: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            range: NSRange(location: 0, length: credits.length)
        )

        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "BlitzRecorder",
            .applicationVersion: version,
            .version: "Version \(version) (\(build))",
            .credits: credits
        ])
    }

    static func openHelp() {
        NSWorkspace.shared.open(AppLinks.support)
    }

    static func openReleaseNotes() {
        NSWorkspace.shared.open(AppUpdateController.releaseNotesURL)
    }

    static func openPrivacyPolicy() {
        NSWorkspace.shared.open(AppLinks.privacy)
    }

    static func reportIssue(diagnostics: String) {
        var components = URLComponents(string: "https://github.com/blitzreels/blitzrecorder-public/issues/new")
        components?.queryItems = [
            URLQueryItem(name: "template", value: "bug_report.yml"),
            URLQueryItem(name: "title", value: "[Bug]: "),
            URLQueryItem(name: "body", value: """


Diagnostics:
```
\(diagnostics)
```
""")
        ]
        open(components?.url ?? URL(string: "https://github.com/blitzreels/blitzrecorder-public/issues/new/choose")!)
    }

    static func sendFeedback(diagnostics: String) {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "support@blitzreels.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "BlitzRecorder feedback"),
            URLQueryItem(name: "body", value: """
Tell us what happened or what you would like to see:


Diagnostics:
\(diagnostics)
""")
        ]
        open(components.url ?? AppLinks.support)
    }

    static func copyDiagnostics(_ diagnostics: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(diagnostics, forType: .string)

        let alert = NSAlert()
        alert.messageText = "Diagnostics copied"
        alert.informativeText = "Paste them into a GitHub issue or support email when you want help. No diagnostics are sent automatically."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

@MainActor
enum AppDiagnostics {
    static func report(coordinator: RecorderCoordinator, accessController: AccessController) -> String {
        let settings = coordinator.settings
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let bundleID = bundle.bundleIdentifier ?? "unknown"
        let enabledSources = settings.enabledSources
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.rawValue)
            .joined(separator: ", ")
        let visibleSources = settings.visibleSources
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.rawValue)
            .joined(separator: ", ")

        return """
        BlitzRecorder Diagnostics
        Generated: \(Self.isoDate())

        App
        - Version: \(version) (\(build))
        - Bundle ID: \(bundleID)
        - Distribution: \(Self.distribution)
        - Sparkle configured: \(Self.sparkleConfigured ? "yes" : "no")

        System
        - macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        - Architecture: \(Self.architecture)\(Self.isTranslated ? " via Rosetta" : "")
        - Processor count: \(ProcessInfo.processInfo.processorCount)
        - Memory: \(Self.physicalMemory)

        Permissions
        - Screen Recording: \(Self.yesNo(CGPreflightScreenCaptureAccess()))
        - Accessibility: \(Self.yesNo(AXIsProcessTrusted()))
        - Camera: \(Self.authorizationStatus(AVCaptureDevice.authorizationStatus(for: .video)))
        - Microphone: \(Self.authorizationStatus(AVCaptureDevice.authorizationStatus(for: .audio)))
        - Speech Recognition: \(Self.speechStatus(SFSpeechRecognizer.authorizationStatus()))

        Recording
        - State: \(coordinator.state)
        - Layout: \(settings.layout.rawValue)
        - Resolution: \(settings.outputResolution.displayName)
        - Frame rate: \(settings.framesPerSecond)
        - Format: \(settings.outputVideoFormat.displayName)
        - Enabled sources: \(enabledSources.isEmpty ? "none" : enabledSources)
        - Visible sources: \(visibleSources.isEmpty ? "none" : visibleSources)
        - Saves source files: \(Self.yesNo(settings.savesSourceFiles))
        - Output folder writable: \(Self.yesNo(FileManager.default.isWritableFile(atPath: settings.outputDirectory.path)))

        Access
        - Model: free 1080p tier + Early Lifetime License
        - Can render export: \(Self.yesNo(accessController.canRenderExport))

        Privacy
        - Crash reporting SDK: none
        - Analytics SDK: none
        - Diagnostics sent automatically: no
        """
    }

    private static var distribution: String {
        #if DIRECT_DISTRIBUTION
        return "Direct DMG"
        #else
        return "App Store or local Xcode build"
        #endif
    }

    private static var sparkleConfigured: Bool {
        guard let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else {
            return false
        }
        return !feedURL.isEmpty && !publicKey.isEmpty
    }

    private static var architecture: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        var machine = systemInfo.machine
        let capacity = MemoryLayout.size(ofValue: machine)
        return withUnsafePointer(to: &machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) {
                String(cString: $0)
            }
        }
    }

    private static var isTranslated: Bool {
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0)
        return result == 0 && translated == 1
    }

    private static var physicalMemory: String {
        let bytes = ProcessInfo.processInfo.physicalMemory
        let gib = Double(bytes) / 1_073_741_824
        return String(format: "%.1f GB", gib)
    }

    private static func isoDate() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? "yes" : "no"
    }

    private static func authorizationStatus(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "authorized"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .notDetermined:
            return "not determined"
        @unknown default:
            return "unknown"
        }
    }

    private static func speechStatus(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "authorized"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .notDetermined:
            return "not determined"
        @unknown default:
            return "unknown"
        }
    }
}
