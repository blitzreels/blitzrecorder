import AppKit
import XCTest

struct ButtonClick {
    let point: CGPoint
    let window: NSWindow
}

@MainActor
func click(_ request: ButtonClick) throws {
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
