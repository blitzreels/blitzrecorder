import CoreGraphics
import Foundation

/// What one part of a multicam project shows: one camera on the whole canvas, or the two framed speakers side by
/// side. The editor's camera picker, the number keys and the importer's opening scenes all make scenes through it,
/// so a speaker is framed the same way wherever they appear.
enum MulticamShot: Hashable {
    case camera(role: String)
    case sideBySide(left: String, right: String)

    /// Each speaker's face centre sits this far down from the top of their tile.
    static let speakerEyeLine: CGFloat = 0.42

    /// How close a shot frames its speakers. A camera that frames one face crops in on it; a wide shot always shows
    /// its whole picture.
    enum Closeness: CaseIterable, Hashable {
        case wide, medium, close

        var title: String {
            switch self {
            case .wide: "Wide"
            case .medium: "Medium"
            case .close: "Close"
            }
        }

        /// The share of the tile height a speaker's face fills; nil shows a lone camera's whole picture.
        func faceHeight(tiled: Bool) -> CGFloat? {
            switch self {
            case .wide: tiled ? 0.16 : nil
            case .medium: 0.22
            case .close: 0.32
            }
        }
    }

    /// How a shot frames its cameras: how close, and for two tiles the space around and between them.
    struct Framing: Hashable {
        var closeness: Closeness
        var spacing: SceneTileSpacing

        /// Side by side starts on head and shoulders with a thin gap; a lone camera shows its whole picture.
        static func standard(for shot: MulticamShot) -> Framing {
            switch shot {
            case .camera: Framing(closeness: .wide, spacing: .small)
            case .sideBySide: Framing(closeness: .medium, spacing: .small)
            }
        }
    }

    /// The shots a multicam project offers, in number-key order: each camera, then the speakers side by side.
    static func shots(for angles: [CameraAngleRecord]) -> [MulticamShot] {
        let cameras = angles.map { MulticamShot.camera(role: $0.role) }
        guard let speakers = speakers(in: angles) else { return cameras }
        return cameras + [.sideBySide(left: speakers.left, right: speakers.right)]
    }

    /// The first two angles that frame one person, left speaker first (the importer numbers them that way).
    static func speakers(in angles: [CameraAngleRecord]) -> (left: String, right: String)? {
        let framed = angles.filter { $0.role != CameraFeeds.mainRole && $0.faceCount == 1 && $0.face != nil }
        guard framed.count >= 2 else { return nil }
        return (framed[0].role, framed[1].role)
    }

    func title(angles: [CameraAngleRecord]) -> String {
        switch self {
        case .camera(let role): angles.record(role: role)?.title ?? role
        case .sideBySide: "Side by side"
        }
    }

    /// The shot a scene shows, when it is one of the project's shots.
    static func current(scene: RecordingScene, angles: [CameraAngleRecord]) -> MulticamShot? {
        let feeds = scene.cameraFeeds
        if scene.sceneLayout.secondCameraFrame != nil {
            return shots(for: angles).first { $0 == .sideBySide(left: feeds.camera, right: feeds.secondCamera) }
        }
        return angles.record(role: feeds.camera) == nil ? nil : .camera(role: feeds.camera)
    }

    struct ApplyRequest {
        let angles: [CameraAngleRecord]
        let canvas: CaptureLayout
        let framing: Framing
    }

    func apply(to scene: inout RecordingScene, _ request: ApplyRequest) {
        scene.enabledSources.remove(.screen)
        scene.enabledSources.insert(.camera)
        scene.sourceOpacities[.camera] = 1
        switch self {
        case .camera(let role):
            var layout = SceneLayout()
            layout.cameraFrame = CGRect(x: 0, y: 0, width: 1, height: 1)
            scene.sceneLayout = layout
            scene.cameraFeeds = CameraFeeds(camera: role, secondCamera: scene.cameraFeeds.secondCamera)
            scene.cameraContentMode = .fit
            scene.cameraCropAmount = .zero
            scene.cameraCropPosition = .zero
            if request.framing.closeness.faceHeight(tiled: false) != nil,
               request.angles.record(role: role)?.face != nil {
                scene.cameraContentMode = .fill
            }
        case .sideBySide(let left, let right):
            var layout = SceneLayout.tiledLayout(.init(
                tiles: SceneTiles(spacing: request.framing.spacing, shape: .fill), includesScreen: false,
                layout: request.canvas, screenAspectRatio: SceneLayout.defaultScreenAspectRatio,
                cameraAspectRatio: CGFloat(request.angles.record(role: left)?.aspectRatio ?? 16.0 / 9.0)
            ))
            layout.cameraMask = .rectangle
            scene.sceneLayout = layout
            scene.cameraFeeds = CameraFeeds(camera: left, secondCamera: right)
            scene.cameraContentMode = .fill
        }
        Self.frameSpeakers(in: &scene, request)
    }

    /// The framing a scene was made with, when it is this shot framed one of the offered ways.
    func framing(of scene: RecordingScene, _ request: FramingRequest) -> Framing? {
        let spacings: [SceneTileSpacing] = if case .sideBySide = self { SceneTileSpacing.allCases } else { [.small] }
        let candidates = spacings.flatMap { spacing in Closeness.allCases.map { Framing(closeness: $0, spacing: spacing) } }
        return candidates.first { framing in
            var candidate = scene
            apply(to: &candidate, .init(angles: request.angles, canvas: request.canvas, framing: framing))
            return candidate.framesMatch(scene)
        }
    }

    struct FramingRequest {
        let angles: [CameraAngleRecord]
        let canvas: CaptureLayout
    }

    /// Crops each camera tile of a scene on the face of the angle it shows, so both speakers sit at the same size
    /// on the same eye line. A tile whose angle has no single face shows its whole picture.
    static func frameSpeakers(in scene: inout RecordingScene, _ request: ApplyRequest) {
        let tiled = scene.sceneLayout.secondCameraFrame != nil
        func crop(role: String, frame: CGRect) -> (amount: CGPoint, position: CGPoint) {
            guard let angle = request.angles.record(role: role), let face = angle.face, angle.faceCount == 1,
                  let faceHeight = request.framing.closeness.faceHeight(tiled: tiled) else {
                return (.zero, .zero)
            }
            return CameraAngleFraming.crop(.init(
                face: face, sourceAspectRatio: CGFloat(angle.aspectRatio),
                tileAspectRatio: frame.width * request.canvas.aspectRatio / max(frame.height, 0.0001),
                faceHeight: faceHeight, eyeLine: speakerEyeLine
            ))
        }
        let first = crop(role: scene.cameraFeeds.camera, frame: scene.sceneLayout.cameraFrame)
        scene.cameraCropAmount = first.amount
        scene.cameraCropPosition = first.position
        if let secondFrame = scene.sceneLayout.secondCameraFrame {
            let second = crop(role: scene.cameraFeeds.secondCamera, frame: secondFrame)
            scene.secondCameraCropAmount = second.amount
            scene.secondCameraCropPosition = second.position
        }
    }
}

private extension RecordingScene {
    func framesMatch(_ other: RecordingScene) -> Bool {
        func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.002 }
        func near(_ a: CGPoint, _ b: CGPoint) -> Bool { near(a.x, b.x) && near(a.y, b.y) }
        func near(_ a: CGRect, _ b: CGRect) -> Bool {
            near(a.minX, b.minX) && near(a.minY, b.minY) && near(a.width, b.width) && near(a.height, b.height)
        }
        let second = (sceneLayout.secondCameraFrame, other.sceneLayout.secondCameraFrame)
        let secondMatches = switch second {
        case (nil, nil): true
        case (let a?, let b?): near(a, b) && near(secondCameraCropAmount, other.secondCameraCropAmount)
            && near(secondCameraCropPosition, other.secondCameraCropPosition)
        default: false
        }
        return secondMatches && near(sceneLayout.cameraFrame, other.sceneLayout.cameraFrame)
            && near(cameraCropAmount, other.cameraCropAmount) && near(cameraCropPosition, other.cameraCropPosition)
    }
}
