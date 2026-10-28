import Foundation

struct MicrophoneTrackReplacement {
    let oldDeviceID: String
    let newDeviceID: String
}

@MainActor
extension RecorderCaptureRuntime {
    /// The microphone that records as Microphone 1.
    var mainMicrophoneDeviceID: String? {
        MicrophoneDeviceSelection.selectedMicrophone(settings: settings)?.uniqueID
    }

    func addMicrophoneTrack(deviceID: String) {
        guard state == .idle,
              deviceID != mainMicrophoneDeviceID,
              !settings.extraMicrophoneIDs.contains(deviceID) else { return }
        settings.extraMicrophoneIDs.append(deviceID)
        persistSettings(saveSceneSnapshot: false)
        refreshAudioLevelMonitoring()
    }

    func replaceMicrophoneTrack(_ replacement: MicrophoneTrackReplacement) {
        guard state == .idle,
              replacement.newDeviceID != mainMicrophoneDeviceID,
              !settings.extraMicrophoneIDs.contains(replacement.newDeviceID),
              let index = settings.extraMicrophoneIDs.firstIndex(of: replacement.oldDeviceID) else { return }
        settings.extraMicrophoneIDs[index] = replacement.newDeviceID
        persistSettings(saveSceneSnapshot: false)
        refreshAudioLevelMonitoring()
    }

    func removeMicrophoneTrack(deviceID: String) {
        guard state == .idle else { return }
        settings.extraMicrophoneIDs.removeAll { $0 == deviceID }
        persistSettings(saveSceneSnapshot: false)
        microphoneTracks.stop(keeping: Set(settings.extraMicrophoneIDs))
        refreshAudioLevelMonitoring()
    }

    /// A microphone chosen as Microphone 1 stops being an extra track, so one microphone never records twice.
    func dropMicrophoneTrackUsedAsMainMicrophone() {
        guard let mainMicrophoneDeviceID, settings.extraMicrophoneIDs.contains(mainMicrophoneDeviceID) else { return }
        removeMicrophoneTrack(deviceID: mainMicrophoneDeviceID)
    }
}
