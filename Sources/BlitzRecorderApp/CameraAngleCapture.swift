import AVFoundation
import CoreMedia
import Foundation

/// One `CameraRecorder` per extra Mac camera. Its session feeds both the studio thumbnail and the take file.
@MainActor
final class CameraAngleRecorders {
    private var recorders: [String: CameraRecorder] = [:]

    func recorder(deviceID: String) -> CameraRecorder {
        if let recorder = recorders[deviceID] { return recorder }
        let recorder = CameraRecorder(fallsBackToDefaultCamera: false)
        recorders[deviceID] = recorder
        return recorder
    }

    func previewLayer(deviceID: String, settings: RecordingSettings) async throws -> AVCaptureVideoPreviewLayer {
        try await recorder(deviceID: deviceID).makePreviewLayer(settings: settings.cameraAngleSettings(deviceID: deviceID))
    }

    func setThumbnailHandler(deviceID: String, handler: @escaping CameraRecorder.ThumbnailHandler) {
        recorder(deviceID: deviceID).setThumbnailHandler(handler)
    }

    func stopPreview(deviceID: String) async {
        await recorders[deviceID]?.stopSession()
    }

    func release(keeping deviceIDs: Set<String>) async {
        let removed = recorders.filter { !deviceIDs.contains($0.key) }
        for (deviceID, recorder) in removed {
            recorders[deviceID] = nil
            await recorder.stopSession()
        }
    }

    func run(take: RecordingTake, settings: RecordingSettings) -> CameraAngleRun {
        let deviceIDs = settings.recordedExtraCameraAngleIDs
        let targets = zip(deviceIDs, take.cameraAngleFiles).enumerated().map { index, pair in
            (
                name: NumberedSourceTracks.cameraAngles.displayName(index: index),
                file: pair.1,
                recorder: recorder(deviceID: pair.0),
                settings: settings.cameraAngleSettings(deviceID: pair.0)
            )
        }
        let run = CameraAngleRun(angles: targets.map {
            CameraAngleRun.Angle(name: $0.name, file: $0.file, recorder: $0.recorder, settings: $0.settings)
        })
        for target in targets {
            target.recorder.failureHandler = { [weak run] error in
                run?.noteFailure(angleName: target.name, error: error)
            }
        }
        return run
    }
}

/// Records the extra angles of one take on the take timeline. A failed angle never fails the take:
/// its failure is kept and reported when the take stops.
@MainActor
final class CameraAngleRun {
    struct Angle {
        let name: String
        let file: SourceTrackFile
        let recorder: CameraCaptureRecording
        let settings: RecordingSettings
    }

    private let angles: [Angle]
    private var recordingAngles: [Angle] = []
    private var failures: [String] = []

    init(angles: [Angle]) {
        self.angles = angles
    }

    static var none: CameraAngleRun { CameraAngleRun(angles: []) }

    func start(timelineStartTime: CMTime) async {
        let startups = angles.map { angle in
            (angle, Task { @MainActor in
                try await angle.recorder.start(
                    url: angle.file.url,
                    settings: angle.settings,
                    timelineStartTime: timelineStartTime
                )
            })
        }
        for (angle, startup) in startups {
            do {
                try await startup.value
                recordingAngles.append(angle)
            } catch {
                failures.append("\(angle.name): \(error.recorderFailureDescription)")
                _ = try? await angle.recorder.stop()
            }
        }
    }

    func noteFailure(angleName: String, error: Error) {
        failures.append("\(angleName): \(error.recorderFailureDescription)")
    }

    func pause() {
        recordingAngles.forEach { $0.recorder.pause() }
    }

    func resume() {
        recordingAngles.forEach { $0.recorder.resume() }
    }

    /// Stops every angle and returns one line per angle that did not save video.
    func stop() async -> [String] {
        let stopping = recordingAngles.map { angle in
            (angle, Task { @MainActor in try await angle.recorder.stop() })
        }
        recordingAngles = []
        for (angle, stop) in stopping {
            do {
                if try await stop.value.wroteMedia == false {
                    failures.append("\(angle.name): No video was captured from this camera.")
                }
            } catch {
                failures.append("\(angle.name): \(error.recorderFailureDescription)")
            }
        }
        defer { failures = [] }
        return failures
    }
}
