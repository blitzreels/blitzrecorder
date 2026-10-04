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
        let restored = applied.last
        controller.update(.starting)
        XCTAssertEqual(applied.count, 1)
        XCTAssertTrue(applied.last === restored)
        controller.update(.recording)
        let recording = applied.last
        XCTAssertFalse(recording === restored)
        controller.update(.recording)
        XCTAssertEqual(applied.count, 2)
        controller.update(.paused)
        XCTAssertTrue(applied.last === restored)
        controller.update(.recording)
        XCTAssertTrue(applied.last === recording)
        controller.update(.finishing)
        XCTAssertTrue(applied.last === restored)
        controller.update(.idle)
        XCTAssertEqual(applied.count, 5)
        controller.update(.recording)
        controller.update(.idle)
        XCTAssertTrue(applied.last === restored)
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

extension RecordingAppIconTests {
    @MainActor
    func testRestoringIconUsesAFrozenSnapshotOfTheOriginalArtwork() throws {
        let base = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { bounds in
            NSColor.systemGreen.setFill()
            bounds.fill()
            return true
        }
        let expected = try XCTUnwrap(base.tiffRepresentation)
        var applied: NSImage?
        let controller = RecordingAppIconController(.init(baseImage: base, applyImage: { applied = $0 }))
        controller.update(.recording)
        base.size = NSSize(width: 8, height: 8)
        controller.update(.idle)
        XCTAssertEqual(applied?.size, NSSize(width: 32, height: 32))
        let originalPixels = try XCTUnwrap(NSBitmapImageRep(data: expected))
        let restoredPixels = try XCTUnwrap(applied?.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let originalColor = try XCTUnwrap(originalPixels.colorAt(x: 2, y: 2)?.usingColorSpace(.deviceRGB))
        let restoredColor = try XCTUnwrap(restoredPixels.colorAt(x: 2, y: 2)?.usingColorSpace(.deviceRGB))
        XCTAssertEqual(restoredColor.greenComponent, originalColor.greenComponent, accuracy: 0.01)
        XCTAssertEqual(restoredColor.redComponent, originalColor.redComponent, accuracy: 0.01)
    }
}
