import AVFoundation
import ApplicationServices
import AppKit
import BlitzRecorderCore
import CoreGraphics
import Foundation

@MainActor
final class PermissionGate {
    private let system: any RecordingPermissionSystem
    private(set) var hasRequestedScreenCaptureAccessThisSession = false
    private(set) var hasRequestedAccessibilityAccessThisSession = false
    private var isTerminating = false

    convenience init() {
        self.init(system: MacOSRecordingPermissionSystem())
    }

    init(system: any RecordingPermissionSystem) {
        self.system = system
    }

    func stopRequestingPermissions() {
        isTerminating = true
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

    var hasAccessibilityAccess: Bool {
        system.hasAccessibilityAccess()
    }

    var hasScreenCaptureAccess: Bool {
        system.hasScreenCaptureAccess()
    }

    var cameraAuthorizationStatus: AVAuthorizationStatus {
        system.authorizationStatus(for: .video)
    }

    func requestScreenCaptureAccess() async -> PermissionRequestResult {
        guard !isTerminating, !Task.isCancelled else { return cancelledRequest }
        let granted = PermissionRequestResult(
            status: .granted,
            message: "Screen Recording permission is active."
        )
        let needsSettings = PermissionRequestResult(
            status: .needsSettings,
            message: "Enable Screen Recording in System Settings, then reopen BlitzRecorder."
        )
        if hasScreenCaptureAccess { return granted }

        guard !hasRequestedScreenCaptureAccessThisSession else { return needsSettings }
        hasRequestedScreenCaptureAccessThisSession = true
        _ = system.requestScreenCaptureAccess()

        if await waitForPermission({ [system] in system.hasScreenCaptureAccess() }) { return granted }

        guard !isTerminating, !Task.isCancelled else { return cancelledRequest }
        return needsSettings
    }

    func requestAccessibilityAccessForWindowControls() async -> PermissionRequestResult {
        guard !isTerminating, !Task.isCancelled else { return cancelledRequest }
        let granted = PermissionRequestResult(
            status: .granted,
            message: "Accessibility permission is active."
        )
        let needsSettings = PermissionRequestResult(
            status: .needsSettings,
            message: "Enable Accessibility in System Settings to move and resize captured windows."
        )
        if hasAccessibilityAccess { return granted }

        guard !hasRequestedAccessibilityAccessThisSession else { return needsSettings }
        hasRequestedAccessibilityAccessThisSession = true
        _ = system.requestAccessibilityAccess()
        if await waitForPermission({ [system] in system.hasAccessibilityAccess() }) { return granted }

        guard !isTerminating, !Task.isCancelled else { return cancelledRequest }
        return needsSettings
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
            blockers.append(Self.screenCaptureBlocker(
                hasScreenSourceBinding: settings.screenSourceBinding?.isConcreteSelection == true
            ))
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
        guard !isTerminating else { return false }
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
        guard !isTerminating, !Task.isCancelled else { return false }
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
        guard !isTerminating, !Task.isCancelled else { return false }
        if isGranted() {
            return true
        }

        for _ in 0..<10 {
            do {
                try await Task.sleep(nanoseconds: 200_000_000)
            } catch {
                return false
            }
            guard !isTerminating, !Task.isCancelled else { return false }
            if isGranted() {
                return true
            }
        }

        return false
    }

    private var cancelledRequest: PermissionRequestResult {
        PermissionRequestResult(status: .cancelled, message: "")
    }

    private static func screenCaptureBlocker(hasScreenSourceBinding: Bool) -> PermissionBlocker {
        guard hasScreenSourceBinding else {
            return PermissionBlocker(
                source: .screen,
                permission: "Screen source",
                status: "no app or screen picked",
                recovery: "Enable Screen Recording, then choose a display, app, or window."
            )
        }
        return PermissionBlocker(
            source: .screen,
            permission: "Screen & System Audio Recording",
            status: "source selected; full-capture access inactive",
            recovery: "Enable Screen Recording to capture the selected source."
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
