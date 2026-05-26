import AppKit
@testable import BlitzRecorderApp
import XCTest

final class CanvasAppearanceTests: XCTestCase {
    func testAppearanceAppliesSameGradientToLayerAndSwiftUISwatch() {
        let appearance = CanvasBackgroundStyle.aurora.appearance
        let layer = appearance.gradientLayer(frame: CGRect(x: 0, y: 0, width: 120, height: 80))

        XCTAssertEqual(layer.frame, CGRect(x: 0, y: 0, width: 120, height: 80))
        XCTAssertEqual(layer.colors?.count, appearance.layerColors.count)
        XCTAssertEqual(layer.locations, appearance.layerLocations)
        XCTAssertEqual(appearance.swatchColors.count, appearance.layerColors.count)
    }

    func testAppearanceRendersCIImageAtRequestedRect() {
        let rect = CGRect(x: 10, y: 20, width: 32, height: 24)
        let image = CanvasBackgroundStyle.ocean.appearance.ciImage(in: rect)

        XCTAssertEqual(image.extent, rect)
    }
}
