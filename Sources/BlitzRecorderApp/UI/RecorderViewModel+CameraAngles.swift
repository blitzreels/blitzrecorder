import AVFoundation
import Foundation

/// An extra Mac camera recorded next to Camera 1.
struct CameraAngleItem: Identifiable, Equatable {
    let deviceID: String
    let name: String
    let deviceName: String
    let kind: CameraSourceKind
    let isConnected: Bool

    var id: String { deviceID }
}

@MainActor
extension RecorderViewModel {
    var cameraAngles: [CameraAngleItem] {
        settings.extraCameraAngleIDs.enumerated().map { index, deviceID in
            let option = localCameraOptions.first { $0.id == deviceID }
            return CameraAngleItem(
                deviceID: deviceID,
                name: NumberedSourceTracks.cameraAngles.displayName(index: index),
                deviceName: option.map { CameraOptionName.plain($0.name) } ?? "Unplugged",
                kind: option?.cameraKind ?? .external,
                isConnected: option != nil
            )
        }
    }

    /// Mac cameras that can become the next angle: connected, not Camera 1 and not already an angle.
    /// Desk View is left out: it is a crop of an iPhone camera, not another angle.
    var cameraAngleCandidates: [SourceOption] {
        let mainDeviceID = coordinator.mainLocalCameraDeviceID
        let used = Set(settings.extraCameraAngleIDs)
        return localCameraOptions.filter {
            $0.id != mainDeviceID && !used.contains($0.id) && $0.cameraKind != .deskView
        }
    }

    /// The device recording as Camera 2 in the current two-camera scene.
    var secondCameraDeviceName: String? {
        guard let deviceID = settings.cameraAngleDeviceID(role: settings.cameraFeeds.secondCamera) else { return nil }
        return cameraAngles.first { $0.deviceID == deviceID }?.deviceName
    }

    var mainCameraTitle: String {
        settings.extraCameraAngleIDs.isEmpty ? "Camera" : NumberedSourceTracks.cameraAngles.displayName(number: 1)
    }

    func addCameraAngle(_ deviceID: String) {
        coordinator.addCameraAngle(deviceID: deviceID)
        sceneLibraryRevision += 1
        syncSettingsAfterSceneChange()
    }

    func replaceCameraAngle(_ replacement: CameraAngleReplacement) {
        coordinator.replaceCameraAngle(replacement)
        syncSettings()
    }

    func removeCameraAngle(_ deviceID: String) {
        coordinator.removeCameraAngle(deviceID: deviceID)
        sceneLibraryRevision += 1
        syncSettingsAfterSceneChange()
    }

    func cameraAnglePreviewLayer(_ deviceID: String) async throws -> AVCaptureVideoPreviewLayer {
        try await coordinator.cameraAnglePreviewLayer(deviceID: deviceID)
    }

    func stopCameraAnglePreview(_ deviceID: String) {
        coordinator.stopCameraAnglePreview(deviceID: deviceID)
    }
}

/// A camera's name without the "(Continuity)" or "(Desk View)" tag the catalog adds for the camera menu.
enum CameraOptionName {
    static func plain(_ optionName: String) -> String {
        optionName
            .replacingOccurrences(of: " (Continuity)", with: "")
            .replacingOccurrences(of: " (Desk View)", with: "")
    }
}
