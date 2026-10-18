import AppKit
import XCTest
@testable import BlitzRecorderApp

final class CanvasBackgroundCustomTests: XCTestCase {
    func testPresetRawValuesStillDecode() {
        XCTAssertEqual(CanvasBackgroundStyle(rawValue: "ocean"), .ocean)
        XCTAssertEqual(CanvasBackgroundStyle(rawValue: "seasonal-winter-frost"), .seasonalWinterFrost)
        XCTAssertNil(CanvasBackgroundStyle(rawValue: "not-a-background"))
    }

    func testSolidColorRoundTripsThroughRawValue() throws {
        let style = CanvasBackgroundStyle.solid(NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1))
        let decoded = try XCTUnwrap(CanvasBackgroundStyle(rawValue: style.rawValue))
        let color = try XCTUnwrap(decoded.solidColor)
        XCTAssertEqual(color.redComponent, 1, accuracy: 0.01)
        XCTAssertEqual(color.greenComponent, 0.5, accuracy: 0.01)
        XCTAssertEqual(color.blueComponent, 0, accuracy: 0.01)
        XCTAssertFalse(decoded.supportsBackgroundAnimation)
        XCTAssertEqual(decoded.appearance.solidCGColor.components?.first ?? 0, 1, accuracy: 0.01)
    }

    func testBlurIsKeptSeparateFromTheBase() throws {
        let style = CanvasBackgroundStyle.image(fileName: "photo.png").withBlur(.strong)
        let decoded = try XCTUnwrap(CanvasBackgroundStyle(rawValue: style.rawValue))
        XCTAssertEqual(decoded.blur, .strong)
        XCTAssertEqual(decoded.base, .image(fileName: "photo.png"))
        XCTAssertEqual(decoded.withBlur(.none), .image(fileName: "photo.png"))
        XCTAssertTrue(decoded.isImageBased)
    }

    func testCodableUsesTheRawString() throws {
        let style = CanvasBackgroundStyle.peach
        let data = try JSONEncoder().encode([style])
        XCTAssertEqual(String(data: data, encoding: .utf8), "[\"peach\"]")
        XCTAssertEqual(try JSONDecoder().decode([CanvasBackgroundStyle].self, from: data), [style])
    }

    func testImportedImageRendersAndBlurs() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("bg-\(UUID().uuidString).png")
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 32, height: 64))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 32, y: 0, width: 32, height: 64))
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: try XCTUnwrap(ctx.makeImage()))
            .representation(using: .png, properties: [:]))
        try png.write(to: source)
        let style = try CanvasBackgroundLibrary.importImage(from: source)
        defer {
            try? FileManager.default.removeItem(at: source)
            if let url = style.customImageURL { try? FileManager.default.removeItem(at: url) }
        }

        let sharp = try XCTUnwrap(style.appearance.renderCGImage(pixelWidth: 64, pixelHeight: 64))
        let blurred = try XCTUnwrap(style.withBlur(.strong).appearance.renderCGImage(pixelWidth: 64, pixelHeight: 64))
        XCTAssertNotEqual(pixel(sharp, x: 31), pixel(blurred, x: 31))
    }

    @MainActor
    func testPreviewRendersEachNewBackground() async throws {
        let view = PreviewStageView()
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        view.captureLayout = .horizontal
        view.enabledSources = [.screen]
        view.layoutSubtreeIfNeeded()
        for style in [CanvasBackgroundStyle.ocean, .peach, .solid(.systemYellow)] {
            view.canvasBackgroundStyle = style
            let deadline = Date().addingTimeInterval(10)
            while view.renderedBackgroundKey?.style != style, Date() < deadline {
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertEqual(view.renderedBackgroundKey?.style, style)
        }
    }

    private func pixel(_ image: CGImage, x: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.draw(image, in: CGRect(x: -x, y: -32, width: image.width, height: image.height))
        return bytes
    }
}
