import BlitzRecorderCore

struct CameraCompanionEnergyPolicy: Equatable {
    var isSceneActive: Bool
    var isPairedWithMac: Bool
    var isCameraRecording: Bool
    var recordingPhase: RemoteCameraRecordingPhase

    var keepsDeviceAwake: Bool {
        isSceneActive && needsHighEnergyMode
    }

    var shouldSuspendCameraSession: Bool {
        !isPairedWithMac && !isCameraRecording && !recordingPhase.needsCameraSession
    }

    private var needsHighEnergyMode: Bool {
        isPairedWithMac || isCameraRecording || recordingPhase.usesActiveDeviceResources
    }
}

private extension RemoteCameraRecordingPhase {
    var usesActiveDeviceResources: Bool {
        switch self {
        case .preparing, .recording, .stopping, .transferring:
            return true
        case .idle, .pendingImport, .failed:
            return false
        }
    }

    var needsCameraSession: Bool {
        switch self {
        case .preparing, .recording, .stopping:
            return true
        case .idle, .transferring, .pendingImport, .failed:
            return false
        }
    }
}
