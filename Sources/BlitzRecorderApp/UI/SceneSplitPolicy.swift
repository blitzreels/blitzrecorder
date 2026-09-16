import CoreGraphics
import Foundation

enum SceneSplitPolicy {
    static func inferredHeight(from layout: SceneLayout) -> CGFloat? {
        let camera = layout.cameraFrame.standardized
        let screen = layout.screenFrame.standardized
        let screenHeight = 1 - camera.maxY
        guard abs(camera.minX) < 0.005,
              abs(camera.minY) < 0.005,
              abs(camera.width - 1) < 0.005,
              screen.midY > camera.maxY,
              (SceneLayout.minimumScreenSplitHeight...SceneLayout.maximumScreenSplitHeight).contains(screenHeight)
        else {
            return nil
        }
        return screenHeight
    }

    static func showsControl(
        captureLayout: CaptureLayout,
        visibleSources: Set<CaptureSource>,
        sceneLayout: SceneLayout,
        selectedPreset: ScenePreset?
    ) -> Bool {
        guard captureLayout == .vertical,
              visibleSources.isSuperset(of: [.screen, .camera]) else { return false }
        return sceneLayout.screenSplitHeight != nil
            || inferredHeight(from: sceneLayout) != nil
            || selectedPreset == .screenTop50
    }
}
