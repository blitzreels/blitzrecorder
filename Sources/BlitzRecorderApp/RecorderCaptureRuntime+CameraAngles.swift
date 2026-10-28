import AVFoundation
import Foundation

struct CameraAngleReplacement {
    let oldDeviceID: String
    let newDeviceID: String
}

@MainActor
extension RecorderCaptureRuntime {
    /// The Mac camera that records as Camera 1; nil when an iPhone is Camera 1.
    var mainLocalCameraDeviceID: String? {
        guard !isRemoteCameraSelected else { return nil }
        return LocalCameraSessionConfiguration.selectedCamera(settings: settings)?.uniqueID
    }

    func addCameraAngle(deviceID: String) {
        guard state == .idle,
              deviceID != mainLocalCameraDeviceID,
              !settings.extraCameraAngleIDs.contains(deviceID) else { return }
        settings.extraCameraAngleIDs.append(deviceID)
        persistSettings(saveSceneSnapshot: false)
        studio.refreshCameraAngleScenes()
    }

    func replaceCameraAngle(_ replacement: CameraAngleReplacement) {
        guard state == .idle,
              replacement.newDeviceID != mainLocalCameraDeviceID,
              !settings.extraCameraAngleIDs.contains(replacement.newDeviceID),
              let index = settings.extraCameraAngleIDs.firstIndex(of: replacement.oldDeviceID) else { return }
        settings.extraCameraAngleIDs[index] = replacement.newDeviceID
        persistSettings(saveSceneSnapshot: false)
        releaseUnusedCameraAngles()
    }

    func removeCameraAngle(deviceID: String) {
        guard state == .idle else { return }
        settings.extraCameraAngleIDs.removeAll { $0 == deviceID }
        persistSettings(saveSceneSnapshot: false)
        studio.refreshCameraAngleScenes()
        releaseUnusedCameraAngles()
    }

    /// A camera chosen as Camera 1 stops being an extra angle, so one camera never records twice.
    func dropCameraAngleUsedAsMainCamera() {
        guard let mainLocalCameraDeviceID, settings.extraCameraAngleIDs.contains(mainLocalCameraDeviceID) else { return }
        removeCameraAngle(deviceID: mainLocalCameraDeviceID)
    }

    func cameraAnglePreviewLayer(deviceID: String) async throws -> AVCaptureVideoPreviewLayer {
        try await cameraAngles.previewLayer(deviceID: deviceID, settings: settings)
    }

    func setCameraAngleThumbnailHandler(deviceID: String, handler: @escaping CameraRecorder.ThumbnailHandler) {
        cameraAngles.setThumbnailHandler(deviceID: deviceID, handler: handler)
    }

    /// Stops an angle's idle session unless the stage is showing that angle.
    func stopCameraAnglePreview(deviceID: String) {
        let stageDeviceIDs = [settings.cameraFeeds.camera, settings.cameraFeeds.secondCamera]
            .compactMap(settings.cameraAngleDeviceID(role:))
        guard state == .idle, !stageDeviceIDs.contains(deviceID) else { return }
        Task { await cameraAngles.stopPreview(deviceID: deviceID) }
    }

    private func releaseUnusedCameraAngles() {
        let kept = Set(settings.extraCameraAngleIDs)
        Task { await cameraAngles.release(keeping: kept) }
    }
}
