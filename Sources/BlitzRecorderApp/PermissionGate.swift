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
}

struct PermissionBlocker: Equatable {
    let source: CaptureSource
    let permission: String
    let status: String
    let recovery: String

    var sentence: String {
        "\(source.rawValue) blocked by \(permission): \(status). \(recovery)"
    }
}

extension Array where Element == PermissionBlocker {
    var shortSummary: String {
        if contains(where: { $0.permission == "Sources" }) {
            return "Pick a source to record"
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

enum PermissionGate {
    private static var hasRequestedScreenCaptureAccessThisSession = false
    private static let screenCaptureSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
    private static let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    private static let cameraSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!
    private static let microphoneSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!

    static func readiness(for settings: RecordingSettings) -> RecordingReadiness {
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

    static func statusLine(for settings: RecordingSettings) -> String {
        CaptureSource.allCases
            .filter { settings.enabledSources.contains($0) }
            .map { "\($0.rawValue): \(status(for: $0, settings: settings))" }
            .joined(separator: " | ")
    }

    static func status(for source: CaptureSource, settings: RecordingSettings) -> String {
        switch source {
        case .screen:
            if settings.usesPickedScreenContent {
                return "selected with macOS picker"
            }
            return CGPreflightScreenCaptureAccess() ? "allowed" : "needs Screen Recording permission or app restart"
        case .systemAudio:
            return CGPreflightScreenCaptureAccess() ? "allowed" : "needs Screen Recording permission or app restart"
        case .camera:
            if RemoteCameraProviderID.isRemote(settings.selectedCameraID) {
                return "remote iPhone"
            }
            return authorizationLabel(AVCaptureDevice.authorizationStatus(for: .video))
        case .microphone:
            return authorizationLabel(AVCaptureDevice.authorizationStatus(for: .audio))
        }
    }

    static var accessibilityStatus: String {
        AXIsProcessTrusted() ? "allowed" : "needed for target-window controls"
    }

    static var hasAccessibilityAccess: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestAccessibilityAccess() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func requestScreenCaptureAccess() async -> PermissionRequestResult {
        if CGPreflightScreenCaptureAccess() {
            return PermissionRequestResult(
                status: .granted,
                message: "Screen Recording permission is active."
            )
        }

        if !hasRequestedScreenCaptureAccessThisSession {
            hasRequestedScreenCaptureAccessThisSession = true
            _ = CGRequestScreenCaptureAccess()
        }

        if await waitForPermission(CGPreflightScreenCaptureAccess) {
            return PermissionRequestResult(
                status: .granted,
                message: "Screen Recording permission is active."
            )
        }

        NSWorkspace.shared.open(screenCaptureSettingsURL)
        return PermissionRequestResult(
            status: .needsSettings,
            message: "Enable Screen Recording for BlitzRecorder, then quit and reopen it."
        )
    }

    static func requestAccessibilityAccessForWindowControls() async -> PermissionRequestResult {
        if AXIsProcessTrusted() {
            return PermissionRequestResult(
                status: .granted,
                message: "Accessibility permission is active."
            )
        }

        requestAccessibilityAccess()
        if await waitForPermission(AXIsProcessTrusted) {
            return PermissionRequestResult(
                status: .granted,
                message: "Accessibility permission is active."
            )
        }

        NSWorkspace.shared.open(accessibilitySettingsURL)
        return PermissionRequestResult(
            status: .needsSettings,
            message: "Enable Accessibility for BlitzRecorder to resize target windows."
        )
    }

    static func openScreenCaptureSettings() {
        NSWorkspace.shared.open(screenCaptureSettingsURL)
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(accessibilitySettingsURL)
    }

    static func openCameraSettings() {
        NSWorkspace.shared.open(cameraSettingsURL)
    }

    static func openMicrophoneSettings() {
        NSWorkspace.shared.open(microphoneSettingsURL)
    }

    static func writeDiagnostic(_ readiness: RecordingReadiness) {
        let line = "\(Date()) pid=\(ProcessInfo.processInfo.processIdentifier) ready=\(readiness.isReady) \(readiness.statusLine)\n"
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

    static func blockers(for settings: RecordingSettings) -> [PermissionBlocker] {
        var blockers: [PermissionBlocker] = []

        if settings.enabledSources.contains(.screen),
           !settings.usesPickedScreenContent,
           !CGPreflightScreenCaptureAccess() {
            blockers.append(screenCaptureBlocker(source: .screen))
        }

        if settings.enabledSources.contains(.systemAudio),
           !settings.usesPickedScreenContent,
           !CGPreflightScreenCaptureAccess() {
            blockers.append(screenCaptureBlocker(source: .systemAudio))
        }

        if settings.enabledSources.contains(.camera),
           !RemoteCameraProviderID.isRemote(settings.selectedCameraID) {
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            if status != .authorized {
                blockers.append(
                    PermissionBlocker(
                        source: .camera,
                        permission: "Camera",
                        status: authorizationLabel(status),
                        recovery: "Allow Camera for BlitzRecorder in Privacy settings."
                    )
                )
            }
        }

        if settings.enabledSources.contains(.microphone) {
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            if status != .authorized {
                blockers.append(
                    PermissionBlocker(
                        source: .microphone,
                        permission: "Microphone",
                        status: authorizationLabel(status),
                        recovery: "Allow Microphone for BlitzRecorder in Privacy settings."
                    )
                )
            }
        }

        return blockers
    }

    static func requestScreenCaptureAccessIfNeeded() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        guard !hasRequestedScreenCaptureAccessThisSession else {
            return false
        }
        hasRequestedScreenCaptureAccessThisSession = true
        return CGRequestScreenCaptureAccess()
    }

    private static func waitForPermission(
        _ isGranted: @escaping () -> Bool,
        attempts: Int = 10,
        delayNanoseconds: UInt64 = 200_000_000
    ) async -> Bool {
        if isGranted() {
            return true
        }

        for _ in 0..<attempts {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            if isGranted() {
                return true
            }
        }

        return false
    }

    private static func screenCaptureBlocker(source: CaptureSource) -> PermissionBlocker {
        PermissionBlocker(
            source: source,
            permission: "Screen & System Audio Recording",
            status: "not active for this app process",
            recovery: "Use Pick Screen for picker-based capture, or enable Screen Recording and restart BlitzRecorder if it is already enabled."
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
