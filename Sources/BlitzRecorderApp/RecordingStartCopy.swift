import Foundation

enum RecordingStartCopy {
    static func blockedMessage(enabledSourcesEmpty: Bool) -> String {
        if enabledSourcesEmpty {
            return "Start failed: Select at least one source before recording."
        }
        return "Start failed: Selected sources are not ready."
    }

    static func failedMessage(for error: Error) -> String {
        if case RecorderError.screenCapturePermissionRequired = error {
            return "Start failed: Selected sources are not ready."
        }
        return "Start failed: \(error.localizedDescription)"
    }

    static func windowFitSkipped(_ error: Error) -> String {
        "Window fit skipped: \(error.localizedDescription)"
    }

    static func prerollMessage(remaining: Int) -> String {
        let unit = remaining == 1 ? "second" : "seconds"
        return "Loading scene. Recording starts in \(remaining) \(unit)..."
    }

    static let preparing = "Not recording yet. Hang on while BlitzRecorder prepares capture."
    static let stopping = "Stopping recording..."
    static let saving = "Saving recording..."

    static func recording(skippedSystemAudio: Bool, usesLiveCompositor: Bool) -> String {
        if skippedSystemAudio {
            return "Recording - Mac audio off (needs Screen Recording)"
        }
        return usesLiveCompositor ? "Recording with live compositor..." : "Recording..."
    }
}
