import CoreGraphics
import CoreVideo
@testable import BlitzRecorderApp
import XCTest

final class LiveCompositorRendererTests: XCTestCase {
    func testScreenShadowIsIndependentFromCanvasPadding() throws {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen]
        settings.outputResolution = .p720
        settings.layout = .vertical
        settings.canvasBackgroundStyle = .studioPaperWhite
        settings.canvasPadding = 0.1
        settings.screenShadowEnabled = true

        let scene = RecordingScene(settings: settings)
        var sceneWithoutShadow = scene
        sceneWithoutShadow.screenShadowEnabled = false
        let dimensions = ScreenCaptureGeometry.outputDimensions(for: settings)
        let screenBuffer = try makePixelBuffer(
            width: 160,
            height: 90,
            color: (blue: 0, green: 0, red: 0, alpha: 255)
        )
        let outputWithShadow = try makePixelBuffer(
            width: dimensions.width,
            height: dimensions.height,
            color: (blue: 0, green: 0, red: 0, alpha: 0)
        )
        let outputWithoutShadow = try makePixelBuffer(
            width: dimensions.width,
            height: dimensions.height,
            color: (blue: 0, green: 0, red: 0, alpha: 0)
        )

        let renderer = LiveCompositorRenderer()
        XCTAssertTrue(renderer.render(
            screenBuffer: screenBuffer,
            cameraBuffer: nil,
            scene: scene,
            settings: settings,
            to: outputWithShadow
        ))
        XCTAssertTrue(renderer.render(
            screenBuffer: screenBuffer,
            cameraBuffer: nil,
            scene: sceneWithoutShadow,
            settings: settings,
            to: outputWithoutShadow
        ))

        let screenRect = SceneRenderGeometry(
            canvas: CGRect(x: 0, y: 0, width: dimensions.width, height: dimensions.height),
            scene: scene,
            origin: .lowerLeft
        ).targetRect(for: .screen)
        let x = Int((screenRect.maxX + 8).rounded(.down))
        let y = Int((CGFloat(dimensions.height) - screenRect.midY).rounded(.down))
        let withShadow = sample(outputWithShadow, x: x, y: y)
        let withoutShadow = sample(outputWithoutShadow, x: x, y: y)

        XCTAssertLessThan(withShadow.red, withoutShadow.red)
        XCTAssertLessThan(withShadow.green, withoutShadow.green)
        XCTAssertLessThan(withShadow.blue, withoutShadow.blue)
    }

    func testCameraShadowDoesNotDarkenFadedCameraContent() throws {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen, .camera]
        settings.outputResolution = .p720
        settings.layout = .vertical
        settings.cameraShadowEnabled = true
        var layout = SceneLayout.presetLayout(.screenFullscreen, for: .vertical)
        layout.cameraFrame = CGRect(x: 0.35, y: 0.35, width: 0.4, height: 0.225)
        layout.layerOrder = [.screen, .camera]
        settings.sceneLayout = layout

        var sceneWithShadow = RecordingScene(settings: settings)
        sceneWithShadow.sourceOpacities[.camera] = 0.5
        var sceneWithoutShadow = sceneWithShadow
        sceneWithoutShadow.cameraShadowEnabled = false

        let dimensions = ScreenCaptureGeometry.outputDimensions(for: settings)
        let screenBuffer = try makePixelBuffer(width: 64, height: 64, color: (blue: 255, green: 255, red: 255, alpha: 255))
        let cameraBuffer = try makePixelBuffer(width: 64, height: 64, color: (blue: 0, green: 0, red: 255, alpha: 255))
        let outputWithShadow = try makePixelBuffer(width: dimensions.width, height: dimensions.height, color: (blue: 0, green: 0, red: 0, alpha: 0))
        let outputWithoutShadow = try makePixelBuffer(width: dimensions.width, height: dimensions.height, color: (blue: 0, green: 0, red: 0, alpha: 0))

        let renderer = LiveCompositorRenderer()
        XCTAssertTrue(renderer.render(
            screenBuffer: screenBuffer,
            cameraBuffer: cameraBuffer,
            scene: sceneWithShadow,
            settings: settings,
            to: outputWithShadow
        ))
        XCTAssertTrue(renderer.render(
            screenBuffer: screenBuffer,
            cameraBuffer: cameraBuffer,
            scene: sceneWithoutShadow,
            settings: settings,
            to: outputWithoutShadow
        ))

        let cameraRect = SceneRenderGeometry(
            canvas: CGRect(x: 0, y: 0, width: dimensions.width, height: dimensions.height),
            scene: sceneWithShadow,
            origin: .lowerLeft
        ).targetRect(for: .camera)
        let x = Int(cameraRect.midX.rounded(.down))
        let y = Int((CGFloat(dimensions.height) - cameraRect.midY).rounded(.down))

        let withShadow = sample(outputWithShadow, x: x, y: y)
        let withoutShadow = sample(outputWithoutShadow, x: x, y: y)
        XCTAssertEqual(withShadow.red, withoutShadow.red, accuracy: 3)
        XCTAssertEqual(withShadow.green, withoutShadow.green, accuracy: 3)
        XCTAssertEqual(withShadow.blue, withoutShadow.blue, accuracy: 3)
    }

    func testCameraShadowIsSuppressedWhenCameraIsBehindScreen() throws {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen, .camera]
        settings.outputResolution = .p720
        settings.layout = .vertical
        settings.cameraShadowEnabled = true
        settings.canvasBackgroundStyle = .studioPaperWhite
        var layout = SceneLayout.presetLayout(.screenFullscreen, for: .vertical)
        layout.screenFrame = CGRect(x: 0.55, y: 0.1, width: 0.4, height: 0.3)
        layout.cameraFrame = CGRect(x: 0.1, y: 0.35, width: 0.3, height: 0.2)
        layout.layerOrder = [.camera, .screen]
        settings.sceneLayout = layout

        let scene = RecordingScene(settings: settings)
        var sceneWithoutShadow = scene
        sceneWithoutShadow.cameraShadowEnabled = false
        let dimensions = ScreenCaptureGeometry.outputDimensions(for: settings)
        let screenBuffer = try makePixelBuffer(width: 64, height: 64, color: (blue: 0, green: 0, red: 0, alpha: 255))
        let cameraBuffer = try makePixelBuffer(width: 64, height: 64, color: (blue: 0, green: 0, red: 255, alpha: 255))
        let output = try makePixelBuffer(width: dimensions.width, height: dimensions.height, color: (blue: 0, green: 0, red: 0, alpha: 0))
        let outputWithoutShadow = try makePixelBuffer(width: dimensions.width, height: dimensions.height, color: (blue: 0, green: 0, red: 0, alpha: 0))

        let renderer = LiveCompositorRenderer()
        XCTAssertTrue(renderer.render(
            screenBuffer: screenBuffer,
            cameraBuffer: cameraBuffer,
            scene: scene,
            settings: settings,
            to: output
        ))
        XCTAssertTrue(renderer.render(
            screenBuffer: screenBuffer,
            cameraBuffer: cameraBuffer,
            scene: sceneWithoutShadow,
            settings: settings,
            to: outputWithoutShadow
        ))

        let cameraRect = SceneRenderGeometry(
            canvas: CGRect(x: 0, y: 0, width: dimensions.width, height: dimensions.height),
            scene: scene,
            origin: .lowerLeft
        ).targetRect(for: .camera)
        let sampleX = Int((cameraRect.maxX + 8).rounded(.down))
        let sampleY = Int((CGFloat(dimensions.height) - cameraRect.midY).rounded(.down))
        let color = sample(
            output,
            x: sampleX,
            y: sampleY
        )
        let colorWithoutShadow = sample(outputWithoutShadow, x: sampleX, y: sampleY)
        XCTAssertEqual(color.red, colorWithoutShadow.red, accuracy: 3)
        XCTAssertEqual(color.green, colorWithoutShadow.green, accuracy: 3)
        XCTAssertEqual(color.blue, colorWithoutShadow.blue, accuracy: 3)
    }

    func testCircleCameraMaskClipsCameraCornersInCompositedFrame() throws {
        var settings = RecordingSettings()
        settings.outputResolution = .p720
        settings.layout = .horizontal
        settings.canvasBackgroundStyle = .black
        let dimensions = ScreenCaptureGeometry.outputDimensions(for: settings)
        let cameraBuffer = try makePixelBuffer(
            width: 320,
            height: 180,
            color: (blue: 0, green: 255, red: 0, alpha: 255)
        )
        let renderer = LiveCompositorRenderer()

        func render(mask: SceneCameraMask) throws -> (output: CVPixelBuffer, target: CGRect) {
            var layout = SceneLayout.cameraInsetLayout(for: .horizontal, shape: .circle, size: 0.3)
            layout.cameraMask = mask
            let scene = RecordingScene(
                enabledSources: [.camera],
                sceneLayout: layout,
                canvasBackgroundStyle: .black,
                fillsCanvasWhenOnlyVideoSource: false
            )
            let output = try makePixelBuffer(
                width: dimensions.width,
                height: dimensions.height,
                color: (blue: 0, green: 0, red: 0, alpha: 0)
            )
            XCTAssertTrue(renderer.render(
                screenBuffer: nil,
                cameraBuffer: cameraBuffer,
                scene: scene,
                settings: settings,
                to: output
            ))
            let target = SceneRenderGeometry(
                canvas: CGRect(x: 0, y: 0, width: dimensions.width, height: dimensions.height),
                scene: scene,
                origin: .lowerLeft
            ).targetRect(for: .camera)
            return (output, target)
        }

        let circle = try render(mask: .circle)
        let target = circle.target
        let height = CGFloat(dimensions.height)
        let side = min(target.width, target.height)
        let cornerX = Int(target.minX + 3)
        let cornerY = Int(height - target.maxY + 3)
        let nearCornerX = Int(target.minX + side * 0.1)
        let nearCornerY = Int(height - target.maxY + side * 0.1)
        let centerX = Int(target.midX)
        let centerY = Int(height - target.midY)

        XCTAssertLessThan(sample(circle.output, x: nearCornerX, y: nearCornerY).green, 40)
        XCTAssertGreaterThan(sample(circle.output, x: centerX, y: centerY).green, 200)

        let rectangle = try render(mask: .rectangle)
        XCTAssertGreaterThan(sample(rectangle.output, x: nearCornerX, y: nearCornerY).green, 200)
        XCTAssertLessThan(sample(rectangle.output, x: cornerX, y: cornerY).green, 40,
                          "Corner camera keeps the preview's rounded corners in the recording.")
    }

    private func makePixelBuffer(
        width: Int,
        height: Int,
        color: (blue: UInt8, green: UInt8, red: UInt8, alpha: UInt8)
    ) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true,
                kCVPixelBufferIOSurfacePropertiesKey: [:]
            ] as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw RecorderError.writerNotReady
        }
        fill(pixelBuffer, color: color)
        return pixelBuffer
    }

    private func fill(
        _ pixelBuffer: CVPixelBuffer,
        color: (blue: UInt8, green: UInt8, red: UInt8, alpha: UInt8)
    ) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        for y in 0..<height {
            let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                let offset = x * 4
                row[offset] = color.blue
                row[offset + 1] = color.green
                row[offset + 2] = color.red
                row[offset + 3] = color.alpha
            }
        }
    }

    private func sample(_ pixelBuffer: CVPixelBuffer, x: Int, y: Int) -> (red: Int, green: Int, blue: Int) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return (0, 0, 0)
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let clampedX = min(width - 1, max(0, x))
        let clampedY = min(height - 1, max(0, y))
        let row = baseAddress.advanced(by: clampedY * bytesPerRow).assumingMemoryBound(to: UInt8.self)
        let offset = clampedX * 4
        return (red: Int(row[offset + 2]), green: Int(row[offset + 1]), blue: Int(row[offset]))
    }
}
