import AVFoundation
import ApplicationServices
import AppKit
import BlitzRecorderCore
import CoreGraphics
import Foundation

struct RecordingReadiness: Equatable {
    let isReady: Bool
    let title: String
    let detail: String
    let blockers: [PermissionBlocker]
    let statusLine: String

    func blocking(with blocker: PermissionBlocker, statusSuffix: String) -> RecordingReadiness {
        let statusLine = "\(self.statusLine) | \(statusSuffix)"
        return RecordingReadiness(
            isReady: false,
            title: title,
            detail: "Start disabled: \(statusLine)",
            blockers: blockers + [blocker],
            statusLine: statusLine
        )
    }

    func replacingScreenSourceBlockers(with blocker: PermissionBlocker) -> RecordingReadiness {
        let blockers = self.blockers.filter {
            $0.source != .screen && $0.source != .systemAudio
        } + [blocker]
        let statusLine = "\(self.statusLine) | Screen source: not selected"
        return RecordingReadiness(
            isReady: false,
            title: title,
            detail: "Start disabled: \(statusLine)",
            blockers: blockers,
            statusLine: statusLine
        )
    }
}

enum LocalCameraRuntimeState: Equatable {
    struct ReadinessRequest {
        let readiness: RecordingReadiness
        let settings: RecordingSettings
        let isRemoteCameraSelected: Bool
    }

    case unchecked
    case starting
    case ready
    case unavailable(String)

    func applying(_ request: ReadinessRequest) -> RecordingReadiness {
        guard request.settings.enabledSources.contains(.camera),
              !request.isRemoteCameraSelected else {
            return request.readiness
        }

        let blocker: PermissionBlocker
        switch self {
        case .unchecked, .ready:
            return request.readiness
        case .starting:
            blocker = PermissionBlocker(
                source: .camera,
                permission: "Camera availability",
                status: "starting",
                recovery: "Wait for the camera preview before recording."
            )
        case .unavailable(let reason):
            blocker = PermissionBlocker(
                source: .camera,
                permission: "Camera availability",
                status: reason,
                recovery: "Choose another camera or close the app currently using it."
            )
        }

        return request.readiness.blocking(
            with: blocker,
            statusSuffix: "Camera: \(blocker.status)"
        )
    }
}

struct PermissionBlocker: Equatable {
    let source: CaptureSource
    let permission: String
    let status: String
    let recovery: String

    var sentence: String {
        if permission == "Screen & System Audio Recording" {
            switch source {
            case .screen:
                return "Screen source selected; full-capture access is inactive. \(recovery)"
            case .systemAudio:
                return "System Audio needs Screen Recording access. \(recovery)"
            case .camera, .microphone:
                break
            }
        }
        return "\(source.rawValue) blocked by \(permission): \(status). \(recovery)"
    }
}

extension Array where Element == PermissionBlocker {
    var shortSummary: String {
        if contains(where: { $0.permission == "Sources" }) {
            return "Pick a source to record"
        }
        if contains(where: { $0.permission == "Screen source" }) {
            return "Pick a screen or app to record"
        }
        if let cameraBlocker = first(where: { $0.permission == "Camera availability" }) {
            return cameraBlocker.status == "starting" ? "Camera is starting" : "Camera unavailable"
        }
        if contains(where: { $0.source == .screen }),
           !contains(where: { $0.source == .systemAudio }) {
            return "Pick again or enable Screen Recording"
        }
        if contains(where: { $0.source == .systemAudio }),
           !contains(where: { $0.source == .screen }) {
            return "Mac audio needs Screen Recording"
        }
        var parts: [String] = []
        if contains(where: { $0.source == .screen || $0.source == .systemAudio }) {
            parts.append("Screen Recording")
        }
        if contains(where: { $0.permission == "Camera" }) { parts.append("Camera") }
        if contains(where: { $0.source == .microphone }) { parts.append("Microphone") }
        if parts.isEmpty {
            if contains(where: { $0.permission == "Remote iPhone" }) {
                return "Waiting for the iPhone camera to connect"
            }
            return "Permission needed to record"
        }
        return parts.count == 1 ? "\(parts[0]) permission needed" : "Permissions needed to record"
    }
}

struct PermissionRequestResult: Equatable {
    enum Status: Equatable {
        case granted
        case needsSettings
    }

    let status: Status
    let message: String

    var isGranted: Bool {
        status == .granted
    }
}

enum RecordingPermissionSettingsPane {
    case screenCapture
    case accessibility
    case camera
    case microphone
}

@MainActor
protocol RecordingPermissionSystem: AnyObject {
    func hasScreenCaptureAccess() -> Bool
    func requestScreenCaptureAccess() -> Bool
    func hasAccessibilityAccess() -> Bool
    func requestAccessibilityAccess() -> Bool
    func authorizationStatus(for mediaType: AVMediaType) -> AVAuthorizationStatus
    func requestAccess(for mediaType: AVMediaType) async -> Bool
    func openSettings(_ pane: RecordingPermissionSettingsPane)
}

@MainActor
final class MacOSRecordingPermissionSystem: RecordingPermissionSystem {
    private let settingsURLs: [RecordingPermissionSettingsPane: URL] = [
        .screenCapture: URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )!,
        .accessibility: URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )!,
        .camera: URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        )!,
        .microphone: URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        )!
    ]

    func hasScreenCaptureAccess() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    func requestScreenCaptureAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func hasAccessibilityAccess() -> Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibilityAccess() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func authorizationStatus(for mediaType: AVMediaType) -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: mediaType)
    }

    func requestAccess(for mediaType: AVMediaType) async -> Bool {
        await AVCaptureDevice.requestAccess(for: mediaType)
    }

    func openSettings(_ pane: RecordingPermissionSettingsPane) {
        guard let url = settingsURLs[pane] else { return }
        NSWorkspace.shared.open(url)
    }
}

@MainActor
final class PermissionGate {
    private let system: any RecordingPermissionSystem
    private var hasRequestedScreenCaptureAccessThisSession = false

    convenience init() {
        self.init(system: MacOSRecordingPermissionSystem())
    }

    init(system: any RecordingPermissionSystem) {
        self.system = system
    }

    func readiness(for settings: RecordingSettings) -> RecordingReadiness {
        guard !settings.enabledSources.isEmpty else {
            return RecordingReadiness(
                isReady: false,
                title: "Start Recording",
                detail: "Start disabled: no sources selected.",
                blockers: [
                    PermissionBlocker(
                        source: .screen,
                        permission: "Sources",
                        status: "none selected",
                        recovery: "Enable at least one source."
                    )
                ],
                statusLine: "Selected sources: none"
            )
        }

        let blockers = blockers(for: settings)
        let statusLine = statusLine(for: settings)
        if blockers.isEmpty {
            return RecordingReadiness(
                isReady: true,
                title: "Start Recording",
                detail: "Ready: \(statusLine)",
                blockers: [],
                statusLine: statusLine
            )
        }

        return RecordingReadiness(
            isReady: false,
            title: "Start Recording",
            detail: "Start disabled: \(statusLine)",
            blockers: blockers,
            statusLine: statusLine
        )
    }

    func statusLine(for settings: RecordingSettings) -> String {
        CaptureSource.allCases
            .filter { settings.enabledSources.contains($0) }
            .map { source in
                let request = StatusRequest(source: source, settings: settings)
                return "\(source.rawValue): \(status(request))"
            }
            .joined(separator: " | ")
    }

    struct StatusRequest {
        let source: CaptureSource
        let settings: RecordingSettings
    }

    func status(_ request: StatusRequest) -> String {
        let source = request.source
        let settings = request.settings
        switch source {
        case .screen:
            if settings.usesPickedScreenContent {
                return "selected source ready"
            }
            if settings.screenSourceBinding?.isConcreteSelection == true {
                return system.hasScreenCaptureAccess()
                    ? "selected source ready"
                    : "source selected; needs Screen Recording for full capture"
            }
            return system.hasScreenCaptureAccess() ? "allowed" : "no screen selected"
        case .systemAudio:
            if system.hasScreenCaptureAccess() {
                return "allowed"
            }
            return "needs Screen Recording access"
        case .camera:
            if RemoteCameraProviderID.isRemote(settings.selectedCameraID) {
                return "remote iPhone"
            }
            return Self.authorizationLabel(system.authorizationStatus(for: .video))
        case .microphone:
            return Self.authorizationLabel(system.authorizationStatus(for: .audio))
        }
    }

    var accessibilityStatus: String {
        hasAccessibilityAccess ? "allowed" : "needed for target-window controls"
    }

    var hasAccessibilityAccess: Bool {
        system.hasAccessibilityAccess()
    }

    var hasScreenCaptureAccess: Bool {
        system.hasScreenCaptureAccess()
    }

    var cameraAuthorizationStatus: AVAuthorizationStatus {
        system.authorizationStatus(for: .video)
    }

    var microphoneAuthorizationStatus: AVAuthorizationStatus {
        system.authorizationStatus(for: .audio)
    }

    func requestScreenCaptureAccess() async -> PermissionRequestResult {
        if hasScreenCaptureAccess {
            return PermissionRequestResult(
                status: .granted,
                message: "Screen Recording permission is active."
            )
        }

        if !hasRequestedScreenCaptureAccessThisSession {
            hasRequestedScreenCaptureAccessThisSession = true
            _ = system.requestScreenCaptureAccess()
        }

        if await waitForPermission({ [system] in system.hasScreenCaptureAccess() }) {
            return PermissionRequestResult(
                status: .granted,
                message: "Screen Recording permission is active."
            )
        }

        system.openSettings(.screenCapture)
        return PermissionRequestResult(
            status: .needsSettings,
            message: "Enable Screen Recording for BlitzRecorder, then quit and reopen it."
        )
    }

    func requestAccessibilityAccessForWindowControls() async -> PermissionRequestResult {
        if hasAccessibilityAccess {
            return PermissionRequestResult(
                status: .granted,
                message: "Accessibility permission is active."
            )
        }

        _ = system.requestAccessibilityAccess()
        if await waitForPermission({ [system] in system.hasAccessibilityAccess() }) {
            return PermissionRequestResult(
                status: .granted,
                message: "Accessibility permission is active."
            )
        }

        system.openSettings(.accessibility)
        return PermissionRequestResult(
            status: .needsSettings,
            message: "Enable Accessibility for BlitzRecorder to resize target windows."
        )
    }

    func requestCameraAccess() async -> Bool {
        await requestMediaAccess(.video)
    }

    func requestMicrophoneAccess() async -> Bool {
        await requestMediaAccess(.audio)
    }

    func openScreenCaptureSettings() {
        system.openSettings(.screenCapture)
    }

    func openAccessibilitySettings() {
        system.openSettings(.accessibility)
    }

    func openCameraSettings() {
        system.openSettings(.camera)
    }

    func openMicrophoneSettings() {
        system.openSettings(.microphone)
    }

    func writeDiagnostic(_ readiness: RecordingReadiness) {
        let accessibility = hasAccessibilityAccess ? "allowed" : "not allowed"
        let line = "\(Date()) pid=\(ProcessInfo.processInfo.processIdentifier) "
            + "ready=\(readiness.isReady) Accessibility: \(accessibility) | \(readiness.statusLine)\n"
        let url = URL(fileURLWithPath: "/tmp/BlitzRecorder.permission-state.log")
        guard let data = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            _ = try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    func blockers(for settings: RecordingSettings) -> [PermissionBlocker] {
        var blockers: [PermissionBlocker] = []

        if settings.enabledSources.contains(.screen),
           !settings.usesPickedScreenContent,
           !hasScreenCaptureAccess {
            blockers.append(Self.screenCaptureBlocker(ScreenCaptureBlockerRequest(
                source: .screen,
                hasScreenSourceBinding: settings.screenSourceBinding?.isConcreteSelection == true
            )))
        }

        if settings.enabledSources.contains(.camera),
           !RemoteCameraProviderID.isRemote(settings.selectedCameraID) {
            let status = system.authorizationStatus(for: .video)
            if status != .authorized {
                blockers.append(
                    PermissionBlocker(
                        source: .camera,
                        permission: "Camera",
                        status: Self.authorizationLabel(status),
                        recovery: "Allow Camera for BlitzRecorder in Privacy settings."
                    )
                )
            }
        }

        if settings.enabledSources.contains(.microphone) {
            let status = system.authorizationStatus(for: .audio)
            if status != .authorized {
                blockers.append(
                    PermissionBlocker(
                        source: .microphone,
                        permission: "Microphone",
                        status: Self.authorizationLabel(status),
                        recovery: "Allow Microphone for BlitzRecorder in Privacy settings."
                    )
                )
            }
        }

        return blockers
    }

    func requestScreenCaptureAccessIfNeeded() -> Bool {
        if hasScreenCaptureAccess {
            return true
        }
        guard !hasRequestedScreenCaptureAccessThisSession else {
            return false
        }
        hasRequestedScreenCaptureAccessThisSession = true
        return system.requestScreenCaptureAccess()
    }

    private func requestMediaAccess(_ mediaType: AVMediaType) async -> Bool {
        switch system.authorizationStatus(for: mediaType) {
        case .authorized:
            return true
        case .notDetermined:
            return await system.requestAccess(for: mediaType)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func waitForPermission(_ isGranted: @escaping () -> Bool) async -> Bool {
        if isGranted() {
            return true
        }

        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if isGranted() {
                return true
            }
        }

        return false
    }

    private struct ScreenCaptureBlockerRequest {
        let source: CaptureSource
        let hasScreenSourceBinding: Bool
    }

    private static func screenCaptureBlocker(_ request: ScreenCaptureBlockerRequest) -> PermissionBlocker {
        if request.source == .screen {
            if !request.hasScreenSourceBinding {
                return PermissionBlocker(
                    source: request.source,
                    permission: "Screen source",
                    status: "no app or screen picked",
                    recovery: "Enable Screen Recording, then choose a display, app, or window."
                )
            }
            return PermissionBlocker(
                source: request.source,
                permission: "Screen & System Audio Recording",
                status: "source selected; full-capture access inactive",
                recovery: "Enable Screen Recording to capture the selected source."
            )
        }
        return PermissionBlocker(
            source: request.source,
            permission: "Screen & System Audio Recording",
            status: "Mac audio capture needs Screen Recording access",
            recovery: "macOS lists this under Screen Recording; enable it there or turn System Audio off."
        )
    }

    private static func authorizationLabel(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "authorized"
        case .notDetermined:
            return "not determined"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        @unknown default:
            return "unknown"
        }
    }
}
