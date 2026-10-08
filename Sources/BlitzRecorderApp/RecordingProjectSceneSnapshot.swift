import CoreGraphics
import Foundation

extension RecordingProject {
    struct RectValue: Codable, Equatable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double

        init(_ rect: CGRect) {
            self.x = Double(rect.minX)
            self.y = Double(rect.minY)
            self.width = Double(rect.width)
            self.height = Double(rect.height)
        }

        var rect: CGRect {
            CGRect(x: x, y: y, width: width, height: height)
        }
    }

    struct PointValue: Codable, Equatable {
        let x: Double
        let y: Double

        init(_ point: CGPoint) {
            self.x = Double(point.x)
            self.y = Double(point.y)
        }

        var point: CGPoint {
            CGPoint(x: x, y: y)
        }
    }

    struct SceneLayoutSnapshot: Codable, Equatable {
        let screenFrame: RectValue
        let cameraFrame: RectValue
        let layerOrder: [String]
        let cameraMask: String?

        init(_ layout: SceneLayout) {
            self.screenFrame = RectValue(layout.screenFrame)
            self.cameraFrame = RectValue(layout.cameraFrame)
            self.layerOrder = layout.layerOrder.map(\.rawValue)
            self.cameraMask = layout.cameraMask.rawValue
        }

        var sceneCameraMask: SceneCameraMask {
            cameraMask.flatMap(SceneCameraMask.init(rawValue:)) ?? .rectangle
        }
    }

    struct ScreenSourceSnapshot: Codable, Equatable {
        let usesPickedContent: Bool
        let fillsSceneFrame: Bool?
        let selectedDisplayID: String?
        let normalizedCrop: RectValue?
        let sourceAspectRatio: Double?

        init(_ geometry: ScreenSourceGeometry) {
            self.usesPickedContent = geometry.usesPickedContent
            self.fillsSceneFrame = geometry.fillsSceneFrame
            self.selectedDisplayID = geometry.selectedDisplayID
            self.normalizedCrop = geometry.normalizedCrop.map(RectValue.init)
            self.sourceAspectRatio = geometry.sourceAspectRatio.map(Double.init)
        }
    }

    struct SceneSnapshot: Codable, Equatable {
        let enabledSources: [String]
        let sceneLayout: SceneLayoutSnapshot
        let screenSourceGeometry: ScreenSourceSnapshot
        let screenCropAmount: PointValue?
        let screenCropPosition: PointValue?
        let cameraCropAmount: PointValue
        let cameraCropPosition: PointValue
        let canvasBackgroundStyle: String
        let canvasBackgroundAnimated: Bool
        let canvasPadding: Double
        let screenCornerRadius: Double?
        let screenShadowEnabled: Bool?
        let screenContentMode: String?
        let cameraContentMode: String
        let cameraFramePadding: Double
        let cameraShadowEnabled: Bool
        let sourceOpacities: [String: Double]
        let fillsCanvasWhenOnlyVideoSource: Bool?

        init(_ scene: RecordingScene) {
            self.enabledSources = scene.enabledSources.map(\.rawValue).sorted()
            self.sceneLayout = SceneLayoutSnapshot(scene.sceneLayout)
            self.screenSourceGeometry = ScreenSourceSnapshot(scene.screenSourceGeometry)
            self.screenCropAmount = PointValue(scene.screenCropAmount)
            self.screenCropPosition = PointValue(scene.screenCropPosition)
            self.cameraCropAmount = PointValue(scene.cameraCropAmount)
            self.cameraCropPosition = PointValue(scene.cameraCropPosition)
            self.canvasBackgroundStyle = scene.canvasBackgroundStyle.rawValue
            self.canvasBackgroundAnimated = scene.canvasBackgroundAnimated
            self.canvasPadding = Double(scene.canvasPadding)
            self.screenCornerRadius = Double(scene.screenCornerRadius)
            self.screenShadowEnabled = scene.screenShadowEnabled
            self.screenContentMode = scene.screenContentMode.rawValue
            self.cameraContentMode = scene.cameraContentMode.rawValue
            self.cameraFramePadding = Double(scene.cameraFramePadding)
            self.cameraShadowEnabled = scene.cameraShadowEnabled
            self.sourceOpacities = Dictionary(uniqueKeysWithValues: scene.sourceOpacities.map { source, opacity in
                (source.rawValue, Double(opacity))
            })
            self.fillsCanvasWhenOnlyVideoSource = scene.fillsCanvasWhenOnlyVideoSource
        }
    }

    struct TransitionSnapshot: Codable, Equatable {
        let duration: Double
        let curve: String

        init(_ transition: RecordingSceneTransition) {
            self.duration = transition.duration
            switch transition.curve {
            case .linear:
                self.curve = "linear"
            case .easeInOut:
                self.curve = "easeInOut"
            }
        }
    }

    struct SceneEventSnapshot: Codable, Equatable {
        let time: Double
        let scene: SceneSnapshot
        let transition: TransitionSnapshot

        init(_ event: RecordingSceneEvent) {
            self.time = event.time
            self.scene = SceneSnapshot(event.scene)
            self.transition = TransitionSnapshot(event.transition)
        }
    }
}

enum RecordingProjectSceneCorrection: String, CaseIterable {
    case screenOnly
    case cameraOnly
    case screenAndCamera

    var displayName: String {
        switch self {
        case .screenOnly:
            return "Screen"
        case .cameraOnly:
            return "Camera"
        case .screenAndCamera:
            return "Screen + Camera"
        }
    }

    var symbolName: String {
        switch self {
        case .screenOnly:
            return BlitzSymbols.screen
        case .cameraOnly:
            return BlitzSymbols.camera
        case .screenAndCamera:
            return BlitzSymbols.pictureInPicture
        }
    }

    var videoSources: Set<CaptureSource> {
        switch self {
        case .screenOnly:
            return [.screen]
        case .cameraOnly:
            return [.camera]
        case .screenAndCamera:
            return [.screen, .camera]
        }
    }
}

extension SceneCameraMask {
    init(_ shape: PortableCameraShape) {
        self = shape == .circle ? .circle : .rectangle
    }

    var portableShape: PortableCameraShape {
        self == .circle ? .circle : .rectangle
    }
}

extension RecordingSceneTransition {
    init(snapshot: RecordingProject.TransitionSnapshot) {
        let curve: RecordingSceneTransitionCurve
        switch snapshot.curve {
        case "linear":
            curve = .linear
        default:
            curve = .easeInOut
        }
        self.init(duration: snapshot.duration, curve: curve)
    }
}

extension RecordingScene {
    init?(snapshot: RecordingProject.SceneSnapshot) {
        let enabledSources = Set(snapshot.enabledSources.compactMap(CaptureSource.init(rawValue:)))
        let layerOrder = snapshot.sceneLayout.layerOrder.compactMap(SceneLayerKind.init(rawValue:))
        self.init(
            enabledSources: enabledSources,
            sceneLayout: SceneLayout(
                screenFrame: snapshot.sceneLayout.screenFrame.rect,
                cameraFrame: snapshot.sceneLayout.cameraFrame.rect,
                layerOrder: layerOrder.isEmpty ? [.screen, .camera] : layerOrder,
                cameraMask: snapshot.sceneLayout.sceneCameraMask
            ),
            screenSourceGeometry: ScreenSourceGeometry(
                usesPickedContent: snapshot.screenSourceGeometry.usesPickedContent,
                fillsSceneFrame: snapshot.screenSourceGeometry.fillsSceneFrame ?? false,
                selectedDisplayID: snapshot.screenSourceGeometry.selectedDisplayID,
                normalizedCrop: snapshot.screenSourceGeometry.normalizedCrop.map(\.rect),
                sourceAspectRatio: snapshot.screenSourceGeometry.sourceAspectRatio.map { CGFloat($0) }
            ),
            screenCropAmount: snapshot.screenCropAmount.map(\.point) ?? .zero,
            screenCropPosition: snapshot.screenCropPosition.map(\.point) ?? .zero,
            cameraCropAmount: snapshot.cameraCropAmount.point,
            cameraCropPosition: snapshot.cameraCropPosition.point,
            canvasBackgroundStyle: CanvasBackgroundStyle(rawValue: snapshot.canvasBackgroundStyle) ?? .black,
            canvasBackgroundAnimated: snapshot.canvasBackgroundAnimated,
            canvasPadding: CGFloat(snapshot.canvasPadding),
            screenCornerRadius: CGFloat(snapshot.screenCornerRadius ?? 0),
            screenShadowEnabled: snapshot.screenShadowEnabled ?? false,
            screenContentMode: snapshot.screenContentMode.flatMap(CameraContentMode.init(rawValue:)) ?? .fill,
            cameraContentMode: CameraContentMode(rawValue: snapshot.cameraContentMode) ?? .fill,
            cameraFramePadding: 0,
            cameraShadowEnabled: snapshot.cameraShadowEnabled,
            sourceOpacities: Dictionary(uniqueKeysWithValues: snapshot.sourceOpacities.compactMap { key, value in
                guard let source = CaptureSource(rawValue: key) else { return nil }
                return (source, CGFloat(value))
            }),
            fillsCanvasWhenOnlyVideoSource: snapshot.fillsCanvasWhenOnlyVideoSource ?? false
        )
    }

    func corrected(
        _ correction: RecordingProjectSceneCorrection,
        layout: CaptureLayout
    ) -> RecordingScene {
        var scene = self
        let audioSources = enabledSources.filter { $0 == .microphone || $0 == .systemAudio }
        let preset: ScenePreset

        switch correction {
        case .screenOnly:
            preset = .screenFullscreen
        case .cameraOnly:
            preset = .webcamFullscreen
        case .screenAndCamera:
            preset = layout == .vertical ? .screenTop50 : .cameraInset
        }

        scene.enabledSources = audioSources.union(correction.videoSources)
        if correction.videoSources.contains(.camera) {
            scene.cameraContentMode = .fill
        }
        scene.sceneLayout = SceneLayout.presetLayout(
            preset,
            for: layout,
            screenAspectRatio: scene.screenSourceGeometry.aspectRatio()
        )
        scene.sourceOpacities = scene.sourceOpacities.filter { source, _ in
            scene.enabledSources.contains(source)
        }
        return scene
    }
}
