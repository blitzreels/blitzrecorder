import BlitzRecorderCore
import Foundation

struct CameraCompanionRecordingSnapshot: Equatable {
    var phase: RemoteCameraRecordingPhase
    var activeRecordingURL: URL?
    var activeTransferProgress: RemoteCameraTransferProgress?
    var statusMessage: String
}

struct CameraCompanionTransferManifestRequest {
    var takeID: UUID
    var recordingURL: URL
    var byteCount: Int64
    var sha256: String?
    var resumeOffset: Int64
    var durationSeconds: Double
    var deviceStartTime: UInt64?
    var deviceStopTime: UInt64?
    var hostStartTime: UInt64?
    var hostStopTime: UInt64?
    var hostTimelineStartTime: UInt64?
    var stopReason: String?
    var recordingDiagnostics: RemoteCameraRecordingDiagnostics?
    var recordingSettings: RemoteCameraSettings?
    var recordingFormat: RemoteCameraFormat?
    var recordingCaptureProfileID: RemoteCameraCaptureProfileID?
    var recordingCaptureCodecLabel: String?
    var recordingCaptureFormatLabel: String?
}

struct CameraCompanionRecordingConfigurationSnapshot {
    var settings: RemoteCameraSettings
    var format: RemoteCameraFormat?
    var captureProfileID: RemoteCameraCaptureProfileID
    var captureCodecLabel: String?
    var captureFormatLabel: String?
}

struct CameraCompanionRecordingDependencies {
    var sendEvent: @MainActor (RemoteCameraEvent) -> Void
    var requestTelemetry: @MainActor () -> Void
    var elapsedSeconds: () -> Int
    var waitForSettingsApplication: @MainActor () async -> Void
    var ensureCameraActive: @MainActor () async -> Bool
    var waitForCaptureReadiness: @MainActor (_ timeoutSeconds: Double?) async -> Void
    var isCameraRecording: @MainActor () -> Bool
    var currentConfiguration: @MainActor () -> CameraCompanionRecordingConfigurationSnapshot
    var startCameraRecording: @MainActor (
        _ takeID: UUID,
        _ expectedSettings: RemoteCameraSettings
    ) async throws -> CameraRecordingStartResult
    var stopCameraRecording: @MainActor () async throws -> CameraRecordingResult
    var existingRecordingURL: @MainActor (_ takeID: UUID) -> URL?
    var removeRecording: @MainActor (_ url: URL) -> Void
    var refreshPendingRecordings: @MainActor () -> Void
    var keepsRecordingsAfterMacImport: @MainActor () -> Bool
    var importCompletedStatus: @MainActor () -> String
    var makeTransferManifest: @MainActor (CameraCompanionTransferManifestRequest) -> RemoteCameraTransferManifest
}

extension CameraCompanionTransferManifestRequest {
    func manifest(defaults: CameraCompanionRecordingConfigurationSnapshot) -> RemoteCameraTransferManifest {
        RemoteCameraTransferManifest(
            takeID: takeID,
            recordingID: takeID,
            fileName: recordingURL.lastPathComponent,
            byteCount: byteCount,
            sha256: sha256,
            durationSeconds: durationSeconds,
            resumeOffset: resumeOffset,
            settings: recordingSettings ?? defaults.settings,
            format: recordingFormat ?? defaults.format,
            captureProfileID: recordingCaptureProfileID ?? defaults.captureProfileID,
            captureCodecLabel: recordingCaptureCodecLabel ?? defaults.captureCodecLabel,
            captureFormatLabel: recordingCaptureFormatLabel ?? defaults.captureFormatLabel,
            deviceStartTime: deviceStartTime,
            deviceStopTime: deviceStopTime,
            hostStartTime: hostStartTime,
            hostStopTime: hostStopTime,
            hostTimelineStartTime: hostTimelineStartTime,
            stopReason: stopReason,
            recordingDiagnostics: recordingDiagnostics
        )
    }
}
