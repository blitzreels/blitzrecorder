import Foundation

enum RecorderError: LocalizedError {
    case noDisplay
    case noCamera
    case writerNotReady
    case mediaWriteFailed(String)
    case captureStreamStopped(String)
    case exportUnavailable
    case microphoneUnavailable
    case cameraDidNotStart
    case screenDidNotStart
    case microphoneDidNotStart
    case speechUnavailable
    case noSourcesSelected
    case outputDirectoryUnavailable(String)
    case screenCapturePermissionRequired
    case screenSourceUnavailable(String)
    case screenSelectionCancelled
    case screenSelectionInProgress
    case backgroundRemovalUnavailable
    case remoteCameraPreviewUnavailable
    case remoteCameraRecordingUnavailable
    case remoteCameraNotConnected
    case remoteCameraSynchronizationFailed(String)
    case remoteCameraTransferFailed(String)

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            "No display was available for screen capture."
        case .noCamera:
            "No camera was available."
        case .writerNotReady:
            "Video setup needs a moment. Try again."
        case .mediaWriteFailed(let reason):
            "Media writing failed: \(reason)"
        case .captureStreamStopped(let reason):
            "Capture stream stopped: \(reason)"
        case .exportUnavailable:
            "The HEVC export session could not be created."
        case .microphoneUnavailable:
            "Microphone access is unavailable."
        case .cameraDidNotStart:
            "Camera did not start producing frames. Check that the selected camera is connected and not in use by another app."
        case .screenDidNotStart:
            "Screen capture did not start producing frames. Check that the selected screen source is open and available."
        case .microphoneDidNotStart:
            "Microphone did not start producing audio. Check that the selected microphone is connected and not in use by another app."
        case .speechUnavailable:
            "Speech transcription is unavailable."
        case .noSourcesSelected:
            "Select at least one source before recording."
        case .outputDirectoryUnavailable(let reason):
            "Export folder is not writable: \(reason)"
        case .screenCapturePermissionRequired:
            "Screen & System Audio Recording permission is required. Enable BlitzRecorder in Privacy settings, then quit and reopen the app."
        case .screenSourceUnavailable(let name):
            "\(name) is not available for capture. Open it or choose another screen source."
        case .screenSelectionCancelled:
            "Screen selection was cancelled."
        case .screenSelectionInProgress:
            "Screen selection is already open."
        case .backgroundRemovalUnavailable:
            "Webcam background removal could not process the camera recording."
        case .remoteCameraPreviewUnavailable:
            "Waiting for iPhone video."
        case .remoteCameraRecordingUnavailable:
            "Remote iPhone recording sync is not implemented yet."
        case .remoteCameraNotConnected:
            "Remote iPhone control link is not connected. Reconnect the iPhone before recording."
        case .remoteCameraSynchronizationFailed(let reason):
            "Remote iPhone recording sync failed: \(reason)"
        case .remoteCameraTransferFailed(let reason):
            "Remote iPhone transfer failed: \(reason)"
        }
    }
}

extension Error {
    var recorderFailureDescription: String {
        let nsError = self as NSError
        var parts = [localizedDescription]

        if let reason = nsError.localizedFailureReason, !reason.isEmpty, reason != localizedDescription {
            parts.append(reason)
        }
        if let suggestion = nsError.localizedRecoverySuggestion, !suggestion.isEmpty {
            parts.append(suggestion)
        }

        if nsError.domain != NSCocoaErrorDomain || nsError.code != 0 {
            parts.append("(\(nsError.domain) \(nsError.code))")
        }

        return parts.joined(separator: " ")
    }
}
