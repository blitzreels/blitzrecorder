import BlitzRecorderCore
import Foundation

enum RecordingStartGate {
    static func skippedSystemAudio(
        requested: Set<CaptureSource>,
        effective: Set<CaptureSource>
    ) -> Bool {
        requested.contains(.systemAudio) && !effective.contains(.systemAudio)
    }

    static func requiresScreenCapturePermission(_ settings: RecordingSettings) -> Bool {
        settings.enabledSources.contains(.screen) && !settings.usesPickedScreenContent
    }

    static func remoteTakeID(plan: TakeStartPlan) -> UUID? {
        plan.usesRemoteCamera && plan.usesLiveCompositor ? UUID() : nil
    }

    static func requireScreenCaptureAccess(_ settings: RecordingSettings, hasAccess: Bool) throws {
        guard requiresScreenCapturePermission(settings) else { return }
        guard hasAccess else { throw RecorderError.screenCapturePermissionRequired }
    }

    static func screenNeedsPicking(
        settings: RecordingSettings,
        hasActiveSelection: Bool
    ) -> Bool {
        settings.enabledSources.contains(.screen)
            && !settings.hiddenSources.contains(.screen)
            && !hasActiveSelection
    }

    static func needsUnselectedScreenSource(
        settings: RecordingSettings,
        hasActiveSelection: Bool
    ) -> Bool {
        !hasActiveSelection
            && (settings.enabledSources.contains(.screen)
                || settings.enabledSources.contains(.systemAudio))
    }

    static func unselectedScreenSourceBlocker(_ settings: RecordingSettings) -> PermissionBlocker {
        PermissionBlocker(
            source: settings.enabledSources.contains(.screen) ? .screen : .systemAudio,
            permission: "Screen source",
            status: "not selected for this session",
            recovery: "Choose a display or window with the macOS picker."
        )
    }

    static func readiness(
        permission: RecordingReadiness,
        settings: RecordingSettings,
        hasActiveScreenSourceSelection: Bool,
        remoteBlocker: PermissionBlocker?
    ) -> RecordingReadiness {
        var readiness = permission
        if needsUnselectedScreenSource(settings: settings, hasActiveSelection: hasActiveScreenSourceSelection) {
            readiness = readiness.replacingScreenSourceBlockers(with: unselectedScreenSourceBlocker(settings))
        }
        if let remoteBlocker {
            readiness = readiness.blocking(
                with: remoteBlocker,
                statusSuffix: "Camera: \(remoteBlocker.status)"
            )
        }
        return readiness
    }

    static func shouldSuggestScreenPicker(
        readiness: RecordingReadiness,
        settings: RecordingSettings
    ) -> Bool {
        readiness.blockers.contains {
            $0.source == .screen || $0.source == .systemAudio
        }
            && (settings.enabledSources.contains(.screen)
                || settings.enabledSources.contains(.systemAudio))
    }

    static func shouldPickScreenForStart(
        readiness: RecordingReadiness,
        settings: RecordingSettings
    ) -> Bool {
        readiness.blockers.contains { $0.source == .screen }
            && settings.enabledSources.contains(.screen)
            && !settings.usesPickedScreenContent
            && !settings.enabledSources.contains(.systemAudio)
    }
}

enum RecordingWarning {
    static func combined(_ warnings: [String?], separator: String = " ") -> String? {
        let combined = warnings.compactMap { warning -> String? in
            guard let warning, !warning.isEmpty else { return nil }
            return warning
        }.joined(separator: separator)
        return combined.isEmpty ? nil : combined
    }
}

enum RecordingStopCopy {
    static let noFrames = "Recording failed: No video frames captured."

    static func recovery(_ message: String) -> String {
        "Recording needs recovery: \(message)"
    }

    static func stopFailed(_ error: Error) -> String {
        "Recording failed: Stop failed: \(error.recorderFailureDescription)"
    }

    static func captureFailed(source: CaptureSource, error: Error) -> String {
        "\(source.rawValue) capture failed. Recording stopped to protect the take: "
            + error.recorderFailureDescription
    }

    static func microphoneSwitched(_ name: String) -> String {
        "Microphone disconnected. Switched to \(name); recording continues."
    }

    static func screenSwitched(_ name: String) -> String {
        "Screen switched to \(name). Recording continues."
    }

    static let sourceSwitchStoppedTake = "Source switch failed. Recording stopped to protect the take."
    static let screenCaptureUpdateStoppedTake = "Screen capture update failed. Recording stopped to protect the take."

    static func screenSwitchFailed(_ error: Error) -> String {
        "Could not switch screen. Recording continues with the previous source: "
            + error.recorderFailureDescription
    }
}

enum ActiveCaptureDeviceIDs {
    static func microphone(settings: RecordingSettings) -> String? {
        settings.enabledSources.contains(.microphone)
            ? MicrophoneDeviceSelection.selectedMicrophone(settings: settings)?.uniqueID
            : nil
    }

    static func localCamera(settings: RecordingSettings) -> String? {
        settings.enabledSources.contains(.camera)
            && !RemoteCameraProviderID.isRemote(settings.selectedCameraID)
            ? LocalCameraSessionConfiguration.selectedCamera(settings: settings)?.uniqueID
            : nil
    }
}
