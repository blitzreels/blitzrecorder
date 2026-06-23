import CoreGraphics
@testable import BlitzRecorderApp
import XCTest

final class SceneSlotGeometryTests: XCTestCase {
    func testNoCameraUsesFullCanvas() {
        var layout = SceneLayout()
        layout.screenFrame = CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.5)

        let slot = SceneSlotGeometry.screenSlot(in: layout, enabledSources: [.screen])

        XCTAssertRect(slot, equals: CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    func testBottomDockedCameraLeavesScreenSlotAboveIt() {
        var layout = SceneLayout()
        layout.screenFrame = CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        layout.cameraFrame = CGRect(x: 0, y: 0, width: 1, height: 0.3)

        let slot = SceneSlotGeometry.screenSlot(in: layout, enabledSources: [.screen, .camera])

        XCTAssertRect(slot, equals: CGRect(x: 0, y: 0.3, width: 1, height: 0.7))
    }

    func testBottomDockedResizedCameraUsesRemainingHeightEvenWhenScreenFrameIsStale() {
        var layout = SceneLayout()
        layout.screenFrame = CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        layout.cameraFrame = CGRect(x: 0, y: 0, width: 1, height: 0.2339574353)

        let slot = SceneSlotGeometry.screenSlot(in: layout, enabledSources: [.screen, .camera])

        XCTAssertRect(
            slot,
            equals: CGRect(x: 0, y: 0.2339574353, width: 1, height: 0.7660425647)
        )
    }

    func testWideBottomCameraUsesRemainingHeightEvenWhenItDoesNotSpanFullWidth() {
        var layout = SceneLayout()
        layout.screenFrame = CGRect(x: -0.0624, y: 0, width: 1.1248, height: 1)
        layout.cameraFrame = CGRect(x: 0.1207, y: 0.045, width: 0.7585, height: 0.24)

        let slot = SceneSlotGeometry.screenSlot(in: layout, enabledSources: [.screen, .camera])

        XCTAssertRect(slot, equals: CGRect(x: 0, y: 0.285, width: 1, height: 0.715))
    }

    func testSmallBottomCameraUsesLargestFreeAreaAboveIt() {
        var layout = SceneLayout()
        layout.screenFrame = CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        layout.cameraFrame = CGRect(x: 0.35, y: 0.02, width: 0.3, height: 0.28)

        let slot = SceneSlotGeometry.screenSlot(in: layout, enabledSources: [.screen, .camera])

        XCTAssertRect(slot, equals: CGRect(x: 0, y: 0.3, width: 1, height: 0.7))
    }

    func testTopDockedCameraLeavesScreenSlotBelowIt() {
        var layout = SceneLayout()
        layout.screenFrame = CGRect(x: 0, y: 0, width: 1, height: 0.5)
        layout.cameraFrame = CGRect(x: 0, y: 0.72, width: 1, height: 0.28)

        let slot = SceneSlotGeometry.screenSlot(in: layout, enabledSources: [.screen, .camera])

        XCTAssertRect(slot, equals: CGRect(x: 0, y: 0, width: 1, height: 0.72))
    }

    func testLeftDockedCameraLeavesScreenSlotBesideIt() {
        var layout = SceneLayout()
        layout.screenFrame = CGRect(x: 1.0 / 3.0, y: 0, width: 2.0 / 3.0, height: 1)
        layout.cameraFrame = CGRect(x: 0, y: 0, width: 1.0 / 3.0, height: 1)

        let slot = SceneSlotGeometry.screenSlot(in: layout, enabledSources: [.screen, .camera])

        XCTAssertRect(slot, equals: CGRect(x: 1.0 / 3.0, y: 0, width: 2.0 / 3.0, height: 1))
    }

    func testInsetCameraUsesLargestAdjacentFreeSlot() {
        var layout = SceneLayout()
        layout.screenFrame = CGRect(x: 0.1, y: 0.2, width: 0.8, height: 0.6)
        layout.cameraFrame = CGRect(x: 0.62, y: 0.05, width: 0.3, height: 0.2)

        let slot = SceneSlotGeometry.screenSlot(in: layout, enabledSources: [.screen, .camera])

        XCTAssertRect(slot, equals: CGRect(x: 0, y: 0.25, width: 1, height: 0.75))
    }

    func testTargetWindowSlotUsesSceneScreenFrame() {
        var layout = SceneLayout()
        layout.screenFrame = CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        layout.cameraFrame = CGRect(x: 0.12, y: 0.05, width: 0.76, height: 0.25)

        let slot = SceneSlotGeometry.targetWindowSlot(in: layout, enabledSources: [.screen, .camera])

        XCTAssertRect(slot, equals: CGRect(x: 0, y: 0.5, width: 1, height: 0.5))
    }

    func testTargetWindowSlotTracksVisiblePresetSceneScreenFrame() {
        for captureLayout in CaptureLayout.allCases {
            for preset in ScenePreset.allCases where preset.supports(captureLayout) {
                XCTContext.runActivity(named: "\(captureLayout.rawValue) \(preset.rawValue)") { _ in
                    let layout = SceneLayout.presetLayout(preset, for: captureLayout)
                    let slot = SceneSlotGeometry.targetWindowSlot(
                        in: layout,
                        enabledSources: [.screen, .camera]
                    )

                    XCTAssertRect(
                        slot,
                        equals: layout.screenFrame.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
                    )
                }
            }
        }
    }

    func testTargetWindowSlotFillsCanvasWhenScreenIsOnlyVideoSource() {
        var layout = SceneLayout()
        layout.screenFrame = CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.5)

        let slot = SceneSlotGeometry.targetWindowSlot(in: layout, enabledSources: [.screen])

        XCTAssertRect(slot, equals: CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    func testScreenSlotMapsToPhysicalCanvasFrame() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 900, height: 1600)
        let slot = CGRect(x: 0, y: 0.3, width: 1, height: 0.7)

        let frame = SceneSlotGeometry.physicalFrame(
            for: slot,
            in: visibleFrame,
            captureLayout: .vertical
        )

        XCTAssertRect(frame, equals: CGRect(x: 0, y: 480, width: 900, height: 1120))
    }

    func testTargetWindowFittingPlanUsesSceneLayoutSlot() {
        var layout = SceneLayout()
        layout.screenFrame = CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        layout.cameraFrame = CGRect(x: 0, y: 0, width: 1, height: 0.5)

        let plan = TargetWindowFitting.plan(
            screenFrame: CGRect(x: 0, y: 0, width: 1600, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1600, height: 900),
            captureLayout: .vertical,
            sceneLayout: layout,
            enabledSources: [.screen, .camera]
        )

        XCTAssertRect(plan.screenSlot, equals: layout.screenFrame)
        XCTAssertRect(plan.canvasFrame, equals: CGRect(x: 547, y: 0, width: 506, height: 900))
        XCTAssertRect(plan.windowFrame, equals: CGRect(x: 547, y: 450, width: 506, height: 450))
        XCTAssertRect(plan.screenCrop, equals: CGRect(x: 0.341875, y: 0, width: 0.31625, height: 0.5))
    }

    func testTargetWindowFittingPlanZoomInUsesSmallerSourceWindow() {
        let plan = TargetWindowFitting.plan(
            screenFrame: CGRect(x: 0, y: 0, width: 1600, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1600, height: 900),
            captureLayout: .vertical,
            screenSlot: SceneSlotGeometry.shortsTopHalfSlot,
            zoom: 1.25
        )

        XCTAssertRect(plan.windowFrame, equals: CGRect(x: 597.6, y: 495, width: 404.8, height: 360))
    }

    func testTargetWindowFittingPlanZoomOutUsesLargerSourceWindow() {
        let plan = TargetWindowFitting.plan(
            screenFrame: CGRect(x: 0, y: 0, width: 1600, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1600, height: 900),
            captureLayout: .vertical,
            screenSlot: SceneSlotGeometry.shortsTopHalfSlot,
            zoom: 0.75
        )

        XCTAssertRect(
            plan.windowFrame,
            equals: CGRect(
                x: 462.6666666667,
                y: 300,
                width: 674.6666666667,
                height: 600
            )
        )
    }

    func testShortsTopHalfSlotMapsToUpperHalfOfVerticalCanvas() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1600, height: 900)

        let frame = SceneSlotGeometry.physicalFrame(
            for: SceneSlotGeometry.shortsTopHalfSlot,
            in: visibleFrame,
            captureLayout: .vertical
        )

        XCTAssertRect(frame, equals: CGRect(x: 547, y: 450, width: 506, height: 450))
    }

    func testShortsTopHalfSlotZoomOutUsesLargerSourceFrame() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1600, height: 900)

        let frame = SceneSlotGeometry.physicalFrame(
            for: SceneSlotGeometry.shortsTopHalfSlot,
            in: visibleFrame,
            captureLayout: .vertical,
            zoom: 0.75
        )

        XCTAssertRect(
            frame,
            equals: CGRect(
                x: 462.6666666667,
                y: 300,
                width: 674.6666666667,
                height: 600
            )
        )
    }

    func testShortsTopHalfSlotZoomInUsesSmallerSourceFrame() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1600, height: 900)

        let frame = SceneSlotGeometry.physicalFrame(
            for: SceneSlotGeometry.shortsTopHalfSlot,
            in: visibleFrame,
            captureLayout: .vertical,
            zoom: 1.25
        )

        XCTAssertRect(frame, equals: CGRect(x: 597.6, y: 495, width: 404.8, height: 360))
    }
}

private func XCTAssertRect(
    _ actual: CGRect,
    equals expected: CGRect,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(actual.origin.x, expected.origin.x, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(actual.origin.y, expected.origin.y, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(actual.size.width, expected.size.width, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(actual.size.height, expected.size.height, accuracy: 0.0001, file: file, line: line)
}
