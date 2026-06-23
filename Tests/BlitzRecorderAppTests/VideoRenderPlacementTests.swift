import CoreGraphics
@testable import BlitzRecorderApp
import XCTest

final class VideoRenderPlacementTests: XCTestCase {
    func testSceneRenderPlacementPolicyResolvesTargetCropAndRadius() {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen, .camera]
        settings.canvasPadding = 0.1
        settings.cameraCropAmount = CGPoint(x: 0.25, y: 0)
        settings.cameraCropPosition = CGPoint(x: 0.2, y: -0.1)
        settings.sceneLayout.cameraFrame = CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        let scene = RecordingScene(settings: settings)

        let placement = SceneRenderGeometry(
            canvas: CGRect(x: 0, y: 0, width: 100, height: 200),
            scene: scene,
            origin: .upperLeft
        ).activePlacements.first { $0.kind == .camera }

        XCTAssertRect(placement?.targetRect ?? .zero, equals: CGRect(x: 26, y: 86, width: 32, height: 64))
        XCTAssertEqual(placement?.cornerRadius, 8)
        XCTAssertEqual(placement?.videoPlacement.sourceCropAmount, CGPoint(x: 0.25, y: 0))
        XCTAssertEqual(placement?.videoPlacement.sourceCropPosition, CGPoint(x: 0.2, y: -0.1))
        XCTAssertEqual(placement?.videoPlacement.contentMode, .aspectFill)
    }

    func testSceneRenderPlacementPolicyIgnoresLegacyCameraFramePadding() {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen, .camera]
        settings.canvasPadding = 0.1
        settings.cameraFramePadding = 0.1
        settings.cameraContentMode = .fit
        settings.sceneLayout.cameraFrame = CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)

        let placement = SceneRenderGeometry(
            canvas: CGRect(x: 0, y: 0, width: 100, height: 200),
            scene: RecordingScene(settings: settings),
            origin: .upperLeft
        ).activePlacements.first { $0.kind == .camera }

        XCTAssertRect(placement?.targetRect ?? .zero, equals: CGRect(x: 26, y: 86, width: 32, height: 64))
        XCTAssertEqual(placement?.videoPlacement.contentMode, .aspectFit)
    }

    func testPaddedScreenPlacementFitsSourceWithoutCropping() {
        var settings = RecordingSettings()
        settings.layout = .vertical
        settings.enabledSources = [.screen]
        settings.sceneLayout = SceneLayout.presetLayout(.screenFullscreen, for: .vertical)
        settings.canvasPadding = 0.1
        let geometry = SceneRenderGeometry(
            canvas: CGRect(x: 0, y: 0, width: 1080, height: 1920),
            scene: RecordingScene(settings: settings),
            origin: .upperLeft
        )
        let target = CGRect(x: 108, y: 108, width: 864, height: 1704)

        let placement = geometry.videoPlacement(for: .screen)
        let crop = placement.cropRectangle(naturalSize: CGSize(width: 1920, height: 1080))

        XCTAssertRect(
            geometry.targetRect(for: .screen),
            equals: CGRect(x: 108, y: 717, width: 864, height: 486)
        )
        XCTAssertRect(crop ?? .zero, equals: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        XCTAssertTrue(target.contains(geometry.targetRect(for: .screen)))
    }

    func testPaddedScreenPlacementKeepsExplicitCropFillingTarget() {
        var settings = RecordingSettings()
        settings.layout = .vertical
        settings.enabledSources = [.screen]
        settings.sceneLayout = SceneLayout.presetLayout(.screenFullscreen, for: .vertical)
        settings.canvasPadding = 0.1
        settings.screenCrop = CGRect(x: 0.34, y: 0, width: 0.32, height: 1)
        let geometry = SceneRenderGeometry(
            canvas: CGRect(x: 0, y: 0, width: 1080, height: 1920),
            scene: RecordingScene(settings: settings),
            origin: .upperLeft
        )

        let placement = geometry.videoPlacement(for: .screen)

        XCTAssertRect(
            geometry.targetRect(for: .screen),
            equals: CGRect(x: 108, y: 108, width: 864, height: 1704)
        )
        XCTAssertNotNil(placement.cropRectangle(naturalSize: CGSize(width: 1920, height: 1080)))
    }

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

    func testCameraFitModeShowsFullWideSourceInsidePortraitFrame() {
        let placement = VideoRenderPlacement(
            kind: .camera,
            targetRect: CGRect(x: 0, y: 0, width: 1080, height: 1920),
            contentMode: .aspectFit
        )

        XCTAssertNil(placement.cropRectangle(naturalSize: CGSize(width: 1920, height: 1080)))
        XCTAssertRect(
            placement.sourceFrame(sourceAspectRatio: 16.0 / 9.0),
            equals: CGRect(x: 0, y: 656.25, width: 1080, height: 607.5)
        )
    }

    func testEditorLayerFramesUseVisibleCameraFitFrame() {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen, .camera]
        settings.cameraContentMode = .fit
        settings.sceneLayout.cameraFrame = CGRect(x: 0, y: 0, width: 1, height: 1)
        let frames = EditorPlaybackComposition.normalizedLayerFrames(
            scene: RecordingScene(settings: settings),
            renderSize: CGSize(width: 100, height: 200),
            activeLayerOrder: [.camera],
            hiding: [],
            sourceAspectRatios: [.camera: 16.0 / 9.0]
        )

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames.first?.kind, .camera)
        XCTAssertRect(
            frames.first?.frame ?? .zero,
            equals: CGRect(x: 0, y: 0.359375, width: 1, height: 0.28125)
        )
    }

    func testVisibleCameraSourceRectUsesFitFrame() {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen, .camera]
        settings.cameraContentMode = .fit
        settings.sceneLayout.cameraFrame = CGRect(x: 0, y: 0, width: 1, height: 1)
        let geometry = SceneRenderGeometry(
            canvas: CGRect(x: 0, y: 0, width: 100, height: 200),
            scene: RecordingScene(settings: settings),
            origin: .upperLeft
        )

        XCTAssertRect(
            geometry.visibleSourceRect(for: .camera, sourceAspectRatio: 16.0 / 9.0),
            equals: CGRect(x: 0, y: 71.875, width: 100, height: 56.25)
        )
    }

    func testSourceMaskPathUsesVisibleCameraFitFrame() {
        var settings = RecordingSettings()
        settings.enabledSources = [.camera]
        settings.cameraContentMode = .fit
        settings.canvasPadding = 0.1
        settings.sceneLayout.cameraFrame = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        let geometry = SceneRenderGeometry(
            canvas: CGRect(x: 0, y: 0, width: 100, height: 200),
            scene: RecordingScene(settings: settings),
            origin: .upperLeft
        )

        XCTAssertRect(
            geometry.sourceMaskPath(sourceAspectRatios: [.camera: 16.0 / 9.0])?.boundingBoxOfPath ?? .zero,
            equals: CGRect(x: 10, y: 77.5, width: 80, height: 45)
        )
    }

    func testHiddenLayerFramesReflowRemainingSourceLikeExport() {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen, .camera]
        settings.layout = .vertical
        settings.sceneLayout = SceneLayout.presetLayout(.screenTop50, for: .vertical)
        let frames = EditorPlaybackComposition.normalizedLayerFrames(
            scene: RecordingScene(settings: settings),
            renderSize: CGSize(width: 100, height: 200),
            activeLayerOrder: [.screen, .camera],
            hiding: [.camera],
            sourceAspectRatios: [.screen: 16.0 / 9.0, .camera: 16.0 / 9.0]
        )

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames.first?.kind, .screen)
        XCTAssertRect(frames.first?.frame ?? .zero, equals: CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    func testCompositionCropRectangleAlignsFourByThreeCameraToEvenPixels() {
        let placement = VideoRenderPlacement(
            kind: .camera,
            targetRect: CGRect(x: 0, y: 0, width: 2160, height: 3840)
        )

        XCTAssertEqual(
            placement.cropRectangle(naturalSize: CGSize(width: 4032, height: 3024)),
            CGRect(x: 1165.5, y: 0, width: 1701, height: 3024)
        )
        XCTAssertEqual(
            placement.pixelAlignedCropRectangle(naturalSize: CGSize(width: 4032, height: 3024)),
            CGRect(x: 1164, y: 0, width: 1704, height: 3024)
        )
    }

    func testRotatedSourceCropUsesDisplayOrientedCoordinatesForPlacement() {
        let placement = VideoRenderPlacement(
            kind: .camera,
            targetRect: CGRect(x: 0, y: 0, width: 1080, height: 1920)
        )
        let naturalSize = CGSize(width: 1920, height: 1080)
        let preferredTransform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)
        let orientedCrop = placement.pixelAlignedOrientedCropRectangle(
            naturalSize: naturalSize,
            preferredTransform: preferredTransform
        )
        let sourceCrop = placement.pixelAlignedSourceCropRectangle(
            naturalSize: naturalSize,
            preferredTransform: preferredTransform
        )
        let transform = placement.transform(
            naturalSize: naturalSize,
            preferredTransform: preferredTransform,
            cropRectangle: orientedCrop
        )

        XCTAssertEqual(orientedCrop, CGRect(x: 0, y: 0, width: 1080, height: 1920))
        XCTAssertEqual(sourceCrop, CGRect(x: 0, y: 0, width: 1920, height: 1080))
        XCTAssertRect(
            CGRect(origin: .zero, size: naturalSize).applying(transform),
            equals: CGRect(x: 0, y: 0, width: 1080, height: 1920)
        )
    }

    func testPixelAlignedCropAspectFillsTargetInsteadOfLeavingEdgePadding() {
        let target = CGRect(x: 14.4, y: 654.4, width: 691.2, height: 611.2)
        let placement = VideoRenderPlacement(
            kind: .camera,
            targetRect: target,
            sourceCropAmount: CGPoint(x: 0.2904946280883587, y: 0.2904946280883587),
            sourceCropPosition: CGPoint(x: -0.0035897796860702453, y: 0.4854035047305225)
        )
        let sourceSize = CGSize(width: 160, height: 90)
        let crop = placement.pixelAlignedCropRectangle(naturalSize: sourceSize)
        let transform = placement.transform(
            naturalSize: sourceSize,
            preferredTransform: .identity,
            cropRectangle: crop
        )
        let transformedCrop = try! XCTUnwrap(crop).applying(transform)

        XCTAssertLessThanOrEqual(transformedCrop.minX, target.minX + 0.0001)
        XCTAssertLessThanOrEqual(transformedCrop.minY, target.minY + 0.0001)
        XCTAssertGreaterThanOrEqual(transformedCrop.maxX, target.maxX - 0.0001)
        XCTAssertGreaterThanOrEqual(transformedCrop.maxY, target.maxY - 0.0001)
        XCTAssertEqual(transformedCrop.midX, target.midX, accuracy: 0.0001)
        XCTAssertEqual(transformedCrop.midY, target.midY, accuracy: 0.0001)
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
