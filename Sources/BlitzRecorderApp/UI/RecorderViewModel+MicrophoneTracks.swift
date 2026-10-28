import Foundation

/// An extra microphone recorded next to Microphone 1 and mixed with it.
struct MicrophoneTrackItem: Identifiable, Equatable {
    let deviceID: String
    let name: String
    let deviceName: String
    let isConnected: Bool

    var id: String { deviceID }
}

@MainActor
extension RecorderViewModel {
    var microphoneTracks: [MicrophoneTrackItem] {
        settings.extraMicrophoneIDs.enumerated().map { index, deviceID in
            let option = availableMicrophones.first { $0.id == deviceID }
            return MicrophoneTrackItem(
                deviceID: deviceID,
                name: NumberedSourceTracks.microphones.displayName(index: index + 1),
                deviceName: option?.name ?? "Unplugged",
                isConnected: option != nil
            )
        }
    }

    /// Microphones that can be added: connected, not Microphone 1 and not already a track.
    var microphoneTrackCandidates: [SourceOption] {
        let mainDeviceID = coordinator.mainMicrophoneDeviceID
        let used = Set(settings.extraMicrophoneIDs)
        return availableMicrophones.filter { $0.id != mainDeviceID && !used.contains($0.id) }
    }

    var mainMicrophoneTitle: String {
        settings.extraMicrophoneIDs.isEmpty ? "Microphone" : NumberedSourceTracks.microphones.displayName(number: 1)
    }

    /// The microphone built into or paired with a camera, such as an Osmo Pocket's (and its DJI Mic).
    func pairedMicrophone(cameraDeviceID: String) -> SourceOption? {
        guard let camera = localCameraOptions.first(where: { $0.id == cameraDeviceID }) else { return nil }
        return CaptureDevicePairing.microphone(.init(camera: camera, microphones: availableMicrophones))
    }

    /// The microphone recording with a camera, by its title: "Microphone 1", "Microphone 2", or nil when unused.
    func recordingMicrophoneTitle(deviceID: String) -> String? {
        if deviceID == coordinator.mainMicrophoneDeviceID { return mainMicrophoneTitle }
        return microphoneTracks.first { $0.deviceID == deviceID }?.name
    }

    func addMicrophoneTrack(_ deviceID: String) {
        coordinator.addMicrophoneTrack(deviceID: deviceID)
        syncSettings()
    }

    func replaceMicrophoneTrack(_ replacement: MicrophoneTrackReplacement) {
        coordinator.replaceMicrophoneTrack(replacement)
        syncSettings()
    }

    func removeMicrophoneTrack(_ deviceID: String) {
        coordinator.removeMicrophoneTrack(deviceID: deviceID)
        syncSettings()
    }
}
