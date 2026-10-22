import Foundation
import CoreMedia
import ScreenCaptureKit

protocol ScreenCaptureRecording: AnyObject {
    var activeScreenCaptureStream: SCStream? { get }
    var cursorCaptureFrame: CGRect? { get }
    func start(url: URL, settings: RecordingSettings, filter pickedFilter: SCContentFilter?, timelineStartTime: CMTime?) async throws
    func update(settings: RecordingSettings, filter pickedFilter: SCContentFilter?) async throws
    func pause()
    func resume()
    func stop() async throws -> MediaWriterCompletion
}

extension ScreenCaptureRecording {
    var activeScreenCaptureStream: SCStream? { nil }
    var cursorCaptureFrame: CGRect? { nil }
}

protocol CameraCaptureRecording: AnyObject {
    func start(url: URL, settings: RecordingSettings, timelineStartTime: CMTime?) async throws
    func pause()
    func resume()
    func stop() async throws -> MediaWriterCompletion
}

@MainActor
protocol RemoteCameraCaptureRecording: AnyObject {
    func startRemoteCamera(take: RecordingTake, settings: RecordingSettings, hostTimelineStartTime: UInt64) async throws
    func pauseRemoteCamera()
    func resumeRemoteCamera()
    func stopRemoteCamera(take: RecordingTake, settings: RecordingSettings) async throws -> MediaWriterCompletion
}

protocol MicrophoneCaptureRecording: AnyObject {
    var recordingTimelineOffset: CMTime { get }
    func start(url: URL, settings: RecordingSettings, timelineStartTime: CMTime?) async throws
    func pause()
    func resume()
    func switchMicrophone(to deviceID: String) async throws
    func stop() async throws -> MediaWriterCompletion
    func finalizeSynchronization() async throws
    func finalizeSynchronization(_ progress: AudioSynchronizationProgress) async throws
}

struct AudioSynchronizationProgress {
    let onProgress: @Sendable (Double) -> Void
}

protocol SystemAudioCaptureRecording: AnyObject {
    var recordingTimelineOffset: CMTime { get }
    func start(url: URL, settings: RecordingSettings, timelineStartTime: CMTime?) async throws
    func start(_ request: SystemAudioCaptureStartRequest) async throws
    func update(filter pickedScreenFilter: SCContentFilter?) async throws
    func pause()
    func resume()
    func stop() async throws -> MediaWriterCompletion
}

struct SystemAudioCaptureStartRequest {
    let url: URL
    let settings: RecordingSettings
    let pickedScreenFilter: SCContentFilter?
    let timelineStartTime: CMTime?
}

extension MicrophoneCaptureRecording {
    var recordingTimelineOffset: CMTime { .zero }
    func switchMicrophone(to deviceID: String) async throws {
        throw RecorderError.microphoneUnavailable
    }
    func finalizeSynchronization() async throws {}
    func finalizeSynchronization(_ progress: AudioSynchronizationProgress) async throws {
        try await finalizeSynchronization()
    }
}

extension SystemAudioCaptureRecording {
    var recordingTimelineOffset: CMTime { .zero }

    func start(_ request: SystemAudioCaptureStartRequest) async throws {
        try await start(
            url: request.url,
            settings: request.settings,
            timelineStartTime: request.timelineStartTime
        )
    }

    func update(filter pickedScreenFilter: SCContentFilter?) async throws {}
}

extension ScreenRecorder: ScreenCaptureRecording {}
extension CameraRecorder: CameraCaptureRecording {}
extension AudioRecorder: MicrophoneCaptureRecording {}
extension SystemAudioRecorder: SystemAudioCaptureRecording {}
