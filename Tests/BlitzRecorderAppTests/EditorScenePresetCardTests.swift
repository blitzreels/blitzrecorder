import AppKit
import SwiftUI
import XCTest
@testable import BlitzRecorderApp

final class EditorScenePresetCardTests: XCTestCase {
    func testFullscreenPresetsSelectTheMatchingVideoSource() {
        XCTAssertEqual(EditorScenePresetSourceCorrection.correction(for: .screenFullscreen), .screenOnly)
        XCTAssertEqual(EditorScenePresetSourceCorrection.correction(for: .webcamFullscreen), .cameraOnly)
        XCTAssertNil(EditorScenePresetSourceCorrection.correction(for: .cameraInset))
    }

    @MainActor
    func testEntireVisibleSplitCardSurfaceAppliesPreset() throws {
        var pressCount = 0
        let host = NSHostingView(rootView: BlitzScenePresetCard(
            preset: .stackedHalves,
            layout: .horizontal,
            isSelected: false,
            isEnabled: true,
            action: { pressCount += 1 }
        ))
        host.frame = CGRect(x: 0, y: 0, width: 130, height: 82)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()

        let points = [
            CGPoint(x: 65, y: 41),
            CGPoint(x: 4, y: 4),
            CGPoint(x: 126, y: 4),
            CGPoint(x: 4, y: 78),
            CGPoint(x: 126, y: 78)
        ]
        for point in points {
            let previousPressCount = pressCount
            try click(ButtonClick(point: point, window: window))
            XCTAssertEqual(
                pressCount,
                previousPressCount + 1,
                "Expected visible card point \(point) to apply the preset."
            )
        }

        XCTAssertEqual(pressCount, points.count)
        window.orderOut(nil)
    }

    private struct ButtonClick {
        let point: CGPoint
        let window: NSWindow
    }

    @MainActor
    private func click(_ request: ButtonClick) throws {
        let down = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: request.point,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: request.window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))
        let up = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: request.point,
            modifierFlags: [],
            timestamp: 0.01,
            windowNumber: request.window.windowNumber,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 0
        ))
        request.window.sendEvent(down)
        request.window.sendEvent(up)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    }
}
