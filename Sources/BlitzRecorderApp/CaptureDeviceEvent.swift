import Foundation

enum CaptureDeviceEvent {
    struct ConnectedActions: Equatable {
        var refreshAudio: Bool
        var notifyCamera: Bool
    }

    struct DisconnectedActions: Equatable {
        var recoverMicrophone: Bool
        var failCamera: Bool
        var refreshIdleAudio: Bool
    }

    static func connected(
        hasAudio: Bool,
        hasVideo: Bool,
        isIdle: Bool
    ) -> ConnectedActions {
        guard isIdle else {
            return ConnectedActions(refreshAudio: false, notifyCamera: false)
        }
        return ConnectedActions(refreshAudio: hasAudio, notifyCamera: hasVideo)
    }

    static func disconnected(
        isActiveMicrophone: Bool,
        isActiveLocalCamera: Bool,
        isIdle: Bool
    ) -> DisconnectedActions {
        DisconnectedActions(
            recoverMicrophone: isActiveMicrophone,
            failCamera: isActiveLocalCamera,
            refreshIdleAudio: isIdle
        )
    }
}

enum RecordingStartFailure {
    struct Cleanup: Equatable {
        var removePendingImport: Bool
        var abandonRemoteTake: Bool
        var cleanupTakeFiles: Bool
    }

    static func cleanup(
        createdTake: Bool,
        remoteStartCommandSent: Bool,
        hasRemoteTakeID: Bool
    ) -> Cleanup {
        Cleanup(
            removePendingImport: hasRemoteTakeID && !remoteStartCommandSent,
            abandonRemoteTake: hasRemoteTakeID,
            cleanupTakeFiles: createdTake && !remoteStartCommandSent
        )
    }
}
