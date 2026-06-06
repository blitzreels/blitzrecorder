import AppKit
@testable import BlitzRecorderApp
import XCTest

final class CanvasAppearanceTests: XCTestCase {
    func testRenderCGImageMatchesRequestedPixelSize() {
        let appearance = CanvasBackgroundStyle.aurora.appearance
        let image = appearance.renderCGImage(pixelWidth: 120, pixelHeight: 80)

        XCTAssertNotNil(image)
        XCTAssertEqual(image?.width, 120)
        XCTAssertEqual(image?.height, 80)
    }

    func testBackgroundLayerCarriesRenderedContents() {
        let appearance = CanvasBackgroundStyle.midnight.appearance
        let frame = CGRect(x: 0, y: 0, width: 120, height: 80)
        let layer = appearance.backgroundLayer(frame: frame, scale: 1)

        XCTAssertEqual(layer.frame, frame)
        XCTAssertNotNil(layer.contents)
        XCTAssertNotNil(layer.backgroundColor)
    }

    func testEveryStyleProducesADescriptor() {
        for style in CanvasBackgroundStyle.allCases {
            let descriptor = style.descriptor
            XCTAssertFalse(descriptor.baseStops.isEmpty, "\(style) has no base stops")
            XCTAssertNotNil(style.appearance.renderCGImage(pixelWidth: 16, pixelHeight: 16), "\(style) failed to render")
        }
    }

    func testMacOSWallpaperStylesRenderAsStaticBackgrounds() {
        let styles: [CanvasBackgroundStyle] = [
            .macOSSonoma,
            .macOSSonomaHorizon,
            .macOSRadialSky,
            .macOSIMacBlue,
            .macOSIMacPurple,
            .macOSVentura,
            .macOSMonterey,
            .macOSBigSur
        ]

        for style in styles {
            let image = style.appearance.renderCGImage(pixelWidth: 96, pixelHeight: 144, animationPhase: 0.5)

            XCTAssertFalse(style.supportsBackgroundAnimation, "\(style) should be a static wallpaper")
            XCTAssertEqual(image?.width, 96)
            XCTAssertEqual(image?.height, 144)
            XCTAssertFalse(style.descriptor.baseStops.isEmpty, "\(style) needs a fallback descriptor")
        }
    }

    func testAppearanceRendersCIImageAtRequestedRect() {
        let rect = CGRect(x: 10, y: 20, width: 32, height: 24)
        let image = CanvasBackgroundStyle.ocean.appearance.ciImage(in: rect)

        XCTAssertEqual(image.extent, rect)
    }

    func testAnimationLoopIsSeamless() {
        // Integer-cycle orbits ⇒ phase 0 and phase 1 land on the same point.
        let base = CGPoint(x: 0.3, y: 0.7)
        for index in 0..<5 {
            let start = CanvasAppearance.animatedCenter(base, index: index, phase: 0)
            let end = CanvasAppearance.animatedCenter(base, index: index, phase: 1)
            XCTAssertEqual(start.x, end.x, accuracy: 0.0001)
            XCTAssertEqual(start.y, end.y, accuracy: 0.0001)
        }
    }

    func testAnimationFramesRenderRequestedCount() {
        let frames = CanvasBackgroundStyle.aurora.appearance.animationFrames(pixelWidth: 24, pixelHeight: 24, count: 8)
        XCTAssertEqual(frames.count, 8)
    }

    func testAnimatedFrameDiffersFromStatic() {
        let appearance = CanvasBackgroundStyle.aurora.appearance
        // A non-zero phase should shift at least one blob, so the rendered pixels
        // differ from the static render.
        guard let staticImage = appearance.renderCGImage(pixelWidth: 40, pixelHeight: 40),
              let animatedImage = appearance.renderCGImage(pixelWidth: 40, pixelHeight: 40, animationPhase: 0.4) else {
            return XCTFail("render failed")
        }
        XCTAssertNotEqual(pixelData(of: staticImage), pixelData(of: animatedImage))
    }

    private func pixelData(of image: CGImage) -> Data? {
        guard let provider = image.dataProvider, let data = provider.data else { return nil }
        return data as Data
    }
}
