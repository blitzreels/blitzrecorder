import CoreGraphics

/// Two-camera scenes in the editor: the tiles the scene was laid out with, and laying them out again.
enum EditorSceneTiles {
    struct Context {
        let scene: RecordingScene
        let layout: CaptureLayout
        /// The scene's own source shapes (`EditorPlaybackController.sourceAspectRatios(for:)`).
        let sourceAspectRatios: [SceneLayerKind: CGFloat]
    }

    static func isTiled(_ scene: RecordingScene) -> Bool {
        scene.renderedSources.contains(.camera) && scene.sceneLayout.secondCameraFrame != nil
    }

    static func includesScreen(_ scene: RecordingScene) -> Bool {
        scene.renderedSources.contains(.screen)
    }

    static func cameraAspectRatio(_ context: Context) -> CGFloat {
        context.sourceAspectRatios[.camera] ?? SceneLayout.cameraAspectRatio
    }

    static func current(_ context: Context) -> SceneTiles? {
        context.scene.sceneLayout.matchingTiles(.init(
            includesScreen: includesScreen(context.scene),
            layout: context.layout,
            screenAspectRatio: screenAspectRatio(context),
            cameraAspectRatio: cameraAspectRatio(context)
        ))
    }

    struct Change {
        let tiles: SceneTiles
        let context: Context
    }

    /// The edit that lays both cameras (and the screen) out as these tiles. Pictures fill their tiles, so a
    /// narrower shape trims the sides of each camera instead of leaving bars.
    static func edit(_ change: Change) -> (inout RecordingScene) -> Void {
        let layout = SceneLayout.tiledLayout(.init(
            tiles: change.tiles,
            includesScreen: includesScreen(change.context.scene),
            layout: change.context.layout,
            screenAspectRatio: screenAspectRatio(change.context),
            cameraAspectRatio: cameraAspectRatio(change.context)
        ))
        return { scene in
            scene.sceneLayout.screenFrame = layout.screenFrame
            scene.sceneLayout.cameraFrame = layout.cameraFrame
            scene.sceneLayout.secondCameraFrame = layout.secondCameraFrame
            scene.sceneLayout.cameraMask = .rectangle
            scene.cameraContentMode = .fill
            scene.screenContentMode = .fit
        }
    }

    private static func screenAspectRatio(_ context: Context) -> CGFloat {
        context.sourceAspectRatios[.screen] ?? SceneLayout.defaultScreenAspectRatio
    }
}
