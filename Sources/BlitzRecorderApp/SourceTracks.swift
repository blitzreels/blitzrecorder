import CoreGraphics
import Foundation

/// A numbered file of one source in a take folder, such as `camera-2.mov` or `microphone-1.m4a`.
struct SourceTrackFile: Equatable {
    let role: String
    let url: URL
}

/// Names the numbered tracks of one source kind. Camera angles start at 2 because the main camera stays `camera`;
/// microphones start at 1 because `microphone` is the mix of all of them when there is more than one.
struct NumberedSourceTracks {
    let base: String
    let displayBase: String
    let firstNumber: Int

    static let cameraAngles = NumberedSourceTracks(base: "camera", displayBase: "Camera", firstNumber: 2)
    static let microphones = NumberedSourceTracks(base: "microphone", displayBase: "Microphone", firstNumber: 1)

    func role(number: Int) -> String {
        "\(base)-\(number)"
    }

    func displayName(number: Int) -> String {
        "\(displayBase) \(number)"
    }

    func displayName(index: Int) -> String {
        displayName(number: index + firstNumber)
    }

    func number(role: String) -> Int? {
        let prefix = "\(base)-"
        guard role.hasPrefix(prefix),
              let number = Int(role.dropFirst(prefix.count)),
              number >= firstNumber else { return nil }
        return number
    }

    func files(directory: URL, count: Int, fileExtension: String) -> [SourceTrackFile] {
        (0..<count).map { index in
            let role = role(number: index + firstNumber)
            return SourceTrackFile(role: role, url: directory.appendingPathComponent("\(role).\(fileExtension)"))
        }
    }

    func files(sourceURLByRole: [String: URL]) -> [SourceTrackFile] {
        sourceURLByRole
            .compactMap { role, url in number(role: role).map { (number: $0, file: SourceTrackFile(role: role, url: url)) } }
            .sorted { $0.number < $1.number }
            .map(\.file)
    }
}

extension RecordingSettings {
    /// Extra angles belong to the Camera source: when Camera is off, none of them record.
    var recordedExtraCameraAngleIDs: [String] {
        enabledSources.contains(.camera) ? extraCameraAngleIDs : []
    }

    /// Extra microphones belong to the Microphone source: when Microphone is off, none of them record.
    var recordedExtraMicrophoneIDs: [String] {
        enabledSources.contains(.microphone) ? extraMicrophoneIDs : []
    }

    func cameraAngleSettings(deviceID: String) -> RecordingSettings {
        var settings = self
        settings.selectedCameraID = deviceID
        settings.extraCameraAngleIDs = []
        return settings
    }

    func microphoneTrackSettings(deviceID: String) -> RecordingSettings {
        var settings = self
        settings.selectedMicrophoneID = deviceID
        settings.selectedMicrophoneName = MicrophoneDeviceSelection.preferredName(id: deviceID)
        settings.extraMicrophoneIDs = []
        return settings
    }
}

/// Which recorded camera file fills each camera slot of a scene: `camera` is Camera 1, `camera-2` the first added angle.
struct CameraFeeds: Codable, Equatable {
    static let mainRole = "camera"
    static let firstAngleRole = "camera-2"
    static let main = CameraFeeds(camera: mainRole, secondCamera: firstAngleRole)

    var camera: String
    /// Fills the second camera slot of two-camera layouts.
    var secondCamera: String

    init(camera: String, secondCamera: String) {
        self.camera = camera
        self.secondCamera = secondCamera
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        camera = try container.decodeIfPresent(String.self, forKey: .camera) ?? Self.mainRole
        secondCamera = try container.decodeIfPresent(String.self, forKey: .secondCamera) ?? Self.firstAngleRole
    }

    var usesCameraAngle: Bool { camera != Self.mainRole }

    /// The angle number a feed names: 1 for Camera 1, 2 for `camera-2`.
    static func angleNumber(role: String) -> Int? {
        role == mainRole ? 1 : NumberedSourceTracks.cameraAngles.number(role: role)
    }
}

extension RecordingSettings {
    /// The Mac camera recording an angle role, nil for Camera 1 or an angle that is no longer chosen.
    func cameraAngleDeviceID(role: String) -> String? {
        guard let number = NumberedSourceTracks.cameraAngles.number(role: role) else { return nil }
        let index = number - NumberedSourceTracks.cameraAngles.firstNumber
        return extraCameraAngleIDs.indices.contains(index) ? extraCameraAngleIDs[index] : nil
    }
}

extension SceneLayerKind {
    /// The file role that fills this layer when no camera angle is chosen.
    var defaultFeed: String {
        switch self {
        case .screen: "screen"
        case .camera: CameraFeeds.mainRole
        case .secondCamera: CameraFeeds.firstAngleRole
        }
    }
}

extension RecordingScene {
    /// The second camera is another device, so Camera 1's crop never applies to it.
    func sourceCropAmount(for kind: SceneLayerKind) -> CGPoint {
        switch kind {
        case .screen: screenCropAmount
        case .camera: cameraCropAmount
        case .secondCamera: secondCameraCropAmount
        }
    }

    func sourceCropPosition(for kind: SceneLayerKind) -> CGPoint {
        switch kind {
        case .screen: screenCropPosition
        case .camera: cameraCropPosition
        case .secondCamera: secondCameraCropPosition
        }
    }

    /// The file role this scene shows in a layer, or the layer's own file when that role was not recorded.
    func feed(for kind: SceneLayerKind, available: Set<String>) -> String {
        let feed = switch kind {
        case .screen: kind.defaultFeed
        case .camera: cameraFeeds.camera
        case .secondCamera: cameraFeeds.secondCamera
        }
        return available.contains(feed) ? feed : kind.defaultFeed
    }

    /// Every camera file role a set of scenes shows.
    static func cameraFeeds(in scenes: [RecordingScene]) -> Set<String> {
        Set(scenes.flatMap { scene in
            [scene.cameraFeeds.camera] + (scene.sceneLayout.secondCameraFrame == nil ? [] : [scene.cameraFeeds.secondCamera])
        })
    }
}
