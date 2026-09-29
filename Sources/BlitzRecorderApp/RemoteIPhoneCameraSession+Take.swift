import BlitzRecorderCore
import BlitzRecorderTransport
import Foundation

extension RemoteIPhoneCameraSession {
    func beginTake(takeID: UUID, take: RecordingTake) {
        runtime.beginTake(
            takeID: takeID,
            serviceID: selectedRemoteServiceID(),
            take: take,
            settings: readSettings()
        )
    }

    func removePendingImport(takeID: UUID) {
        runtime.removePendingImport(takeID: takeID, settings: readSettings())
    }

    func cancelCommand() {
        runtime.cancelCommand()
    }

    func abandonTake(takeID: UUID) {
        runtime.abandonTake(takeID: takeID)
    }

    func markTimelineStart(takeID: UUID, hostTimelineStartTime: UInt64) {
        runtime.markTimelineStart(takeID: takeID, hostTimelineStartTime: hostTimelineStartTime)
    }

    func prepare(takeID: UUID, hostStartTime: UInt64) async throws -> UInt64 {
        try await runtime.prepare(takeID: takeID, hostStartTime: hostStartTime)
    }

    func start(takeID: UUID, hostStartTime: UInt64, hostTimelineStartTime: UInt64?) async throws -> UInt64 {
        try await runtime.start(
            takeID: takeID,
            hostStartTime: hostStartTime,
            hostTimelineStartTime: hostTimelineStartTime
        )
    }

    func stopAndImport(take: RecordingTake) async throws -> MediaWriterCompletion {
        try await runtime.stopAndImport(take: take, settings: readSettings())
    }
}

extension RemoteIPhoneCameraSession: RemoteCameraCaptureRecording {
    func startRemoteCamera(
        take: RecordingTake,
        settings: RecordingSettings,
        hostTimelineStartTime: UInt64
    ) async throws {
        let takeID = UUID()
        let serviceID = RemoteCameraProviderID.serviceID(from: settings.selectedCameraID)
        var startCommandSent = false
        runtime.beginTake(
            takeID: takeID,
            serviceID: serviceID,
            take: take,
            settings: settings
        )
        sendSettings()

        do {
            _ = try await prepare(
                takeID: takeID,
                hostStartTime: DispatchTime.now().uptimeNanoseconds
            )
            markTimelineStart(takeID: takeID, hostTimelineStartTime: hostTimelineStartTime)
            startCommandSent = true
            _ = try await start(
                takeID: takeID,
                hostStartTime: DispatchTime.now().uptimeNanoseconds,
                hostTimelineStartTime: hostTimelineStartTime
            )
        } catch {
            cancelCommand()
            if !startCommandSent {
                removePendingImport(takeID: takeID)
            }
            abandonTake(takeID: takeID)
            throw error
        }
    }

    func pauseRemoteCamera() {}

    func resumeRemoteCamera() {}

    func stopRemoteCamera(take: RecordingTake, settings: RecordingSettings) async throws -> MediaWriterCompletion {
        onMessage?("Waiting for iPhone media...")
        return try await runtime.stopAndImport(take: take, settings: settings)
    }
}
