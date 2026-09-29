import AppKit
import XCTest
@testable import BlitzRecorderApp

final class RecordingAppIconTests: XCTestCase {
    @MainActor
    func testOnlyLiveRecordingUsesTheBadgeAndEveryStopRestoresTheOriginal() {
        let base = NSImage(size: NSSize(width: 128, height: 128))
        var applied: [NSImage] = []
        let controller = RecordingAppIconController(.init(baseImage: base, applyImage: { applied.append($0) }))
        controller.update(.idle)
        controller.update(.starting)
        XCTAssertEqual(applied.count, 1)
        XCTAssertTrue(applied.last === base)
        controller.update(.recording)
        let recording = applied.last
        XCTAssertFalse(recording === base)
        controller.update(.recording)
        XCTAssertEqual(applied.count, 2)
        controller.update(.paused)
        XCTAssertTrue(applied.last === base)
        controller.update(.recording)
        XCTAssertTrue(applied.last === recording)
        controller.update(.finishing)
        XCTAssertTrue(applied.last === base)
        controller.update(.idle)
        XCTAssertEqual(applied.count, 5)
        controller.update(.recording)
        controller.update(.idle)
        XCTAssertTrue(applied.last === base)
    }

    @MainActor
    func testRedDotIsVisibleAtDockAndSwitcherSizesWithoutChangingBaseImage() throws {
        let base = NSImage(size: NSSize(width: 128, height: 128), flipped: false) { bounds in
            NSColor(srgbRed: 0, green: 0.6, blue: 0.3, alpha: 1).setFill()
            bounds.fill()
            return true
        }
        let original = base.tiffRepresentation
        let badged = RecordingAppIcon.badged(base)
        for size in [32, 48, 128, 256] {
            let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            badged.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
            NSGraphicsContext.restoreGraphicsState()
            let dot = try XCTUnwrap(bitmap.colorAt(x: Int(Double(size) * 0.8), y: Int(Double(size) * 0.2))?
                .usingColorSpace(.deviceRGB))
            XCTAssertGreaterThan(dot.redComponent, 0.9)
            XCTAssertLessThan(dot.greenComponent, 0.4)
            let untouched = try XCTUnwrap(bitmap.colorAt(x: size / 2, y: size / 2)?.usingColorSpace(.deviceRGB))
            XCTAssertLessThan(untouched.redComponent, 0.1)
            XCTAssertGreaterThan(untouched.greenComponent, 0.5)
        }
        XCTAssertEqual(base.tiffRepresentation, original)
    }
}
