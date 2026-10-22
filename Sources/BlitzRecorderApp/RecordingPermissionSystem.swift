import AVFoundation
import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

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
