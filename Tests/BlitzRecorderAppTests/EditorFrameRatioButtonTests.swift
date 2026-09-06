import AppKit
import SwiftUI
import XCTest
@testable import BlitzRecorderApp

final class EditorFrameRatioButtonTests: XCTestCase {
    @MainActor
    func testEntireVisibleSurfacePressesButton() throws {
        var pressCount = 0
        let host = NSHostingView(rootView: EditorFrameRatioButton(
            title: "4:3",
            isSelected: false,
            action: { pressCount += 1 }
        ))
        host.frame = CGRect(x: 0, y: 0, width: 120, height: 30)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()

        let edgePoints = [
            CGPoint(x: 4, y: 4),
            CGPoint(x: 116, y: 4),
            CGPoint(x: 4, y: 26),
            CGPoint(x: 116, y: 26)
        ]
        for point in edgePoints {
            try click(ButtonClick(point: point, window: window))
        }

        XCTAssertEqual(pressCount, edgePoints.count)
        window.orderOut(nil)
    }
}
