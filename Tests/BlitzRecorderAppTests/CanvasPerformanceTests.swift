import AppKit
import XCTest
@testable import BlitzRecorderApp

@MainActor
final class CanvasPerformanceTests: XCTestCase {
    func testRepeatedCanvasSettingsSynchronization() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BLITZRECORDER_CANVAS_BENCHMARK"] == "1")
        let view = PreviewStageView()
        view.frame = CGRect(x: 0, y: 0, width: 1000, height: 700)
        view.captureLayout = .vertical
        view.enabledSources = [.screen, .camera]
        let layout = SceneLayout.presetLayout(.stackedHalves, for: .vertical)
        view.sceneLayout = layout
        view.layoutSubtreeIfNeeded()
        let initialFrame = view.renderedCameraFrameForTesting
        let start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<1000 {
            view.sceneLayout = layout
            view.enabledSources = [.screen, .camera]
            view.screenCrop = nil
            view.cameraCropAmount = .zero
            view.cameraCropPosition = .zero
            view.canvasPadding = 0
            view.screenContentMode = .fill
            view.cameraContentMode = .fill
            view.cameraFramePadding = 0
            view.cameraShadowEnabled = false
            view.showsRuleOfThirdsOverlay = false
            view.socialSafeZoneOverlay = .none
            view.layoutSubtreeIfNeeded()
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        print("CANVAS_PERF unchanged_sync_1000_ms=\(elapsed * 1000)")
        XCTAssertEqual(view.renderedCameraFrameForTesting, initialFrame)
    }
}
