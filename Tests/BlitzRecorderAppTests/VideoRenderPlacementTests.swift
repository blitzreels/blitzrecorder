import CoreGraphics
@testable import BlitzRecorderApp
import XCTest

final class VideoRenderPlacementTests: XCTestCase {
    func testScreenPlacementUsesAspectFillWithCrop() {
        let placement = VideoRenderPlacement(
            kind: .screen,
            targetRect: CGRect(x: 0, y: 0, width: 1080, height: 1920)
        )

        let transform = placement.transform(
            naturalSize: CGSize(width: 1920, height: 1080),
            preferredTransform: .identity
        )

        XCTAssertEqual(
            placement.cropRectangle(naturalSize: CGSize(width: 1920, height: 1080)),
            CGRect(x: 656.25, y: 0, width: 607.5, height: 1080)
        )
        XCTAssertTransform(
            transform,
            equals: CGAffineTransform(
                a: 1.7777777777777777,
                b: 0,
                c: 0,
                d: 1.7777777777777777,
                tx: -1166.6666666666665,
                ty: 0
            )
        )
    }

    func testScreenPlacementAspectFillsShorterRegionWithCrop() {
        let placement = VideoRenderPlacement(
            kind: .screen,
            targetRect: CGRect(x: 0, y: 700, width: 1080, height: 760)
        )

        let transform = placement.transform(
            naturalSize: CGSize(width: 1920, height: 1080),
            preferredTransform: .identity
        )

        XCTAssertRect(
            placement.cropRectangle(naturalSize: CGSize(width: 1920, height: 1080))!,
            equals: CGRect(x: 192.63157894736844, y: 0, width: 1534.7368421052631, height: 1080)
        )
        XCTAssertTransform(
            transform,
            equals: CGAffineTransform(
                a: 0.7037037037037037,
                b: 0,
                c: 0,
                d: 0.7037037037037037,
                tx: -135.55555555555554,
                ty: 700
            )
        )
    }

    func testCameraPlacementUsesAspectFillWithCenteredCrop() {
        let placement = VideoRenderPlacement(
            kind: .camera,
            targetRect: CGRect(x: 0, y: 0, width: 100, height: 100)
        )

        let cropRectangle = placement.cropRectangle(naturalSize: CGSize(width: 1920, height: 1080))
        let transform = placement.transform(
            naturalSize: CGSize(width: 1920, height: 1080),
            preferredTransform: .identity
        )

        XCTAssertEqual(cropRectangle, CGRect(x: 420, y: 0, width: 1080, height: 1080))
        XCTAssertTransform(
            transform,
            equals: CGAffineTransform(
                a: 0.09259259259259259,
                b: 0,
                c: 0,
                d: 0.09259259259259259,
                tx: -38.888888888888886,
                ty: 0
            )
        )
    }

    func testCameraCropAmountCropsHorizontalCropWindow() {
        let placement = VideoRenderPlacement(
            kind: .camera,
            targetRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            sourceCropAmount: CGPoint(x: 0.25, y: 0)
        )

        let cropRectangle = placement.cropRectangle(naturalSize: CGSize(width: 1920, height: 1080))
        let transform = placement.transform(
            naturalSize: CGSize(width: 1920, height: 1080),
            preferredTransform: .identity
        )

        XCTAssertEqual(cropRectangle, CGRect(x: 555, y: 135, width: 810, height: 810))
        XCTAssertTransform(
            transform,
            equals: CGAffineTransform(
                a: 0.12345679012345678,
                b: 0,
                c: 0,
                d: 0.12345679012345678,
                tx: -68.51851851851852,
                ty: -16.666666666666664
            )
        )
    }

    func testCameraCropAmountCropsVerticalCropWindow() {
        let placement = VideoRenderPlacement(
            kind: .camera,
            targetRect: CGRect(x: 0, y: 0, width: 160, height: 90),
            sourceCropAmount: CGPoint(x: 0, y: 0.25)
        )

        XCTAssertEqual(
            placement.cropRectangle(naturalSize: CGSize(width: 1080, height: 1920)),
            CGRect(x: 135, y: 732.1875, width: 810, height: 455.625)
        )
    }

    func testCameraCropPositionMovesHorizontalCropWindow() {
        let placement = VideoRenderPlacement(
            kind: .camera,
            targetRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            sourceCropPosition: CGPoint(x: 1, y: 0)
        )

        XCTAssertEqual(
            placement.cropRectangle(naturalSize: CGSize(width: 1920, height: 1080)),
            CGRect(x: 840, y: 0, width: 1080, height: 1080)
        )
    }

    func testCameraCropPositionMovesVerticalCropWindow() {
        let placement = VideoRenderPlacement(
            kind: .camera,
            targetRect: CGRect(x: 0, y: 0, width: 160, height: 90),
            sourceCropPosition: CGPoint(x: 0, y: -1)
        )

        XCTAssertEqual(
            placement.cropRectangle(naturalSize: CGSize(width: 1080, height: 1920)),
            CGRect(x: 0, y: 0, width: 1080, height: 607.5)
        )
    }

    func testPreviewSourceFrameUsesSameCropAsRenderPlacement() {
        let frame = SourceCropGeometry.sourceFrame(
            sourceAspectRatio: 16.0 / 9.0,
            bounds: CGRect(x: 0, y: 0, width: 100, height: 100),
            sourceCropAmount: CGPoint(x: 0.25, y: 0),
            sourceCropPosition: .zero
        )

        XCTAssertRect(
            frame,
            equals: CGRect(
                x: -68.51851851851852,
                y: -16.666666666666664,
                width: 237.03703703703704,
                height: 133.33333333333331
            )
        )
    }

    func testPreviewSourceFrameUsesActualSourceAspectRatio() {
        let fourByThreeFrame = SourceCropGeometry.sourceFrame(
            sourceAspectRatio: 4.0 / 3.0,
            bounds: CGRect(x: 0, y: 0, width: 100, height: 100),
            sourceCropAmount: .zero,
            sourceCropPosition: .zero
        )
        let sixteenByNineFrame = SourceCropGeometry.sourceFrame(
            sourceAspectRatio: 16.0 / 9.0,
            bounds: CGRect(x: 0, y: 0, width: 100, height: 100),
            sourceCropAmount: .zero,
            sourceCropPosition: .zero
        )

        XCTAssertRect(
            fourByThreeFrame,
            equals: CGRect(x: -16.666666666666657, y: 0, width: 133.33333333333331, height: 100)
        )
        XCTAssertRect(
            sixteenByNineFrame,
            equals: CGRect(x: -38.888888888888886, y: 0, width: 177.77777777777777, height: 100)
        )
    }
}

private func XCTAssertTransform(
    _ actual: CGAffineTransform,
    equals expected: CGAffineTransform,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(actual.a, expected.a, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(actual.b, expected.b, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(actual.c, expected.c, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(actual.d, expected.d, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(actual.tx, expected.tx, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(actual.ty, expected.ty, accuracy: 0.0001, file: file, line: line)
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
