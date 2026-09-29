import CoreGraphics
import Foundation

struct RecordingScene: Equatable {
    var enabledSources: Set<CaptureSource>
    var sceneLayout: SceneLayout
    var screenSourceGeometry: ScreenSourceGeometry
    var screenCropAmount: CGPoint
    var screenCropPosition: CGPoint
    var cameraCropAmount: CGPoint
    var cameraCropPosition: CGPoint
    var canvasBackgroundStyle: CanvasBackgroundStyle
    var canvasBackgroundAnimated: Bool
    var canvasPadding: CGFloat
    var screenCornerRadius: CGFloat
    var screenShadowEnabled: Bool
    var screenContentMode: CameraContentMode
    var cameraContentMode: CameraContentMode
    var cameraFramePadding: CGFloat
    var cameraShadowEnabled: Bool
    var sourceOpacities: [CaptureSource: CGFloat]
    var fillsCanvasWhenOnlyVideoSource: Bool

    init(settings: RecordingSettings) {
        self.init(
            enabledSources: settings.visibleSources,
            sceneLayout: settings.sceneLayout,
            screenSourceGeometry: ScreenSourceGeometry(settings: settings),
            screenCropAmount: .zero,
            screenCropPosition: .zero,
            cameraCropAmount: settings.cameraCropAmount,
            cameraCropPosition: settings.cameraCropPosition,
            canvasBackgroundStyle: settings.canvasBackgroundStyle,
            canvasBackgroundAnimated: settings.canvasBackgroundAnimated,
            canvasPadding: settings.canvasPadding,
            screenCornerRadius: settings.screenCornerRadius,
            screenShadowEnabled: settings.screenShadowEnabled,
            screenContentMode: settings.screenContentMode,
            cameraContentMode: settings.cameraContentMode,
            cameraFramePadding: 0,
            cameraShadowEnabled: settings.cameraShadowEnabled,
            fillsCanvasWhenOnlyVideoSource: settings.enabledSources.intersection([.screen, .camera]).count == 1
        )
    }

    init(
        enabledSources: Set<CaptureSource>,
        sceneLayout: SceneLayout,
        screenSourceGeometry: ScreenSourceGeometry = ScreenSourceGeometry(),
        screenCropAmount: CGPoint = .zero,
        screenCropPosition: CGPoint = .zero,
        cameraCropAmount: CGPoint = .zero,
        cameraCropPosition: CGPoint = .zero,
        canvasBackgroundStyle: CanvasBackgroundStyle = .black,
        canvasBackgroundAnimated: Bool = false,
        canvasPadding: CGFloat = 0,
        screenCornerRadius: CGFloat = 0,
        screenShadowEnabled: Bool = false,
        screenContentMode: CameraContentMode = .fill,
        cameraContentMode: CameraContentMode = .fill,
        cameraFramePadding: CGFloat = 0,
        cameraShadowEnabled: Bool = false,
        sourceOpacities: [CaptureSource: CGFloat] = [:],
        fillsCanvasWhenOnlyVideoSource: Bool = false
    ) {
        self.enabledSources = enabledSources
        self.sceneLayout = sceneLayout
        self.screenSourceGeometry = screenSourceGeometry
        self.screenCropAmount = screenCropAmount
        self.screenCropPosition = screenCropPosition
        self.cameraCropAmount = cameraCropAmount
        self.cameraCropPosition = cameraCropPosition
        self.canvasBackgroundStyle = canvasBackgroundStyle
        self.canvasBackgroundAnimated = canvasBackgroundAnimated
        self.canvasPadding = canvasPadding
        self.screenCornerRadius = screenCornerRadius
        self.screenShadowEnabled = screenShadowEnabled
        self.screenContentMode = screenContentMode
        self.cameraContentMode = cameraContentMode
        self.cameraFramePadding = 0
        self.cameraShadowEnabled = cameraShadowEnabled
        self.sourceOpacities = sourceOpacities
        self.fillsCanvasWhenOnlyVideoSource = fillsCanvasWhenOnlyVideoSource
    }

    func sourceOpacity(for source: CaptureSource) -> CGFloat {
        guard enabledSources.contains(source) else { return 0 }
        return min(1, max(0, sourceOpacities[source] ?? 1))
    }

    var renderedSources: Set<CaptureSource> {
        let visible = enabledSources.filter { sourceOpacity(for: $0) > 0.001 }
        return visible.isEmpty ? enabledSources : Set(visible)
    }
}

enum RecordingSceneTransitionCurve: Equatable {
    case linear
    case easeInOut

    func value(at progress: CGFloat) -> CGFloat {
        let progress = min(1, max(0, progress))
        switch self {
        case .linear:
            return progress
        case .easeInOut:
            return progress * progress * (3 - 2 * progress)
        }
    }
}

struct RecordingSceneTransition: Equatable {
    var duration: TimeInterval
    var curve: RecordingSceneTransitionCurve

    static let cut = RecordingSceneTransition(duration: 0, curve: .linear)
    static let sceneSwitch = RecordingSceneTransition(duration: 0.35, curve: .easeInOut)

    init(duration: TimeInterval, curve: RecordingSceneTransitionCurve = .easeInOut) {
        self.duration = max(0, duration)
        self.curve = curve
    }

    var isCut: Bool {
        duration <= 0
    }

    func progress(elapsed: TimeInterval) -> CGFloat {
        guard duration > 0 else { return 1 }
        return curve.value(at: CGFloat(elapsed / duration))
    }
}

struct RecordingSceneEvent: Equatable {
    let time: TimeInterval
    let scene: RecordingScene
    let transition: RecordingSceneTransition

    init(
        time: TimeInterval,
        scene: RecordingScene,
        transition: RecordingSceneTransition = .cut
    ) {
        self.time = time
        self.scene = scene
        self.transition = transition
    }
}
