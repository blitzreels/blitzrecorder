import CoreGraphics
import CoreImage
import AVFoundation
import XCTest
@testable import BlitzRecorderApp

final class CameraPopoutTests: XCTestCase {
    private let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
    private let extent = CGRect(x: 0, y: 0, width: 200, height: 100)

    func testRoomIsPreservedOnlyInsidePanelAndHeadCrossesTopEdge() {
        let source = CIImage(color: CIColor(red: 0.3, green: 0.5, blue: 0.7)).cropped(to: extent)
        let person = CIImage(color: .white).cropped(to: CGRect(x: 80, y: 45, width: 40, height: 50))
            .composited(over: CIImage(color: .black).cropped(to: extent))
        let result = CameraPopoutRenderer.composite(.init(image: source, personMask: person, style: style()))
        XCTAssertEqual(pixel(.init(image: result, point: CGPoint(x: 25, y: 40)))[3], 255)
        XCTAssertEqual(pixel(.init(image: result, point: CGPoint(x: 25, y: 90)))[3], 0)
        XCTAssertEqual(pixel(.init(image: result, point: CGPoint(x: 100, y: 90)))[3], 255)
        for y in [79, 81] {
            let actual = pixel(.init(image: result, point: CGPoint(x: 100, y: y)))
            let expected = pixel(.init(image: source, point: CGPoint(x: 100, y: y)))
            for channel in 0..<4 {
                XCTAssertEqual(Double(actual[channel]), Double(expected[channel]), accuracy: 1)
            }
        }
        XCTAssertEqual(pixel(.init(image: result, point: CGPoint(x: 1, y: 1)))[3], 0)
    }

    func testMissingPersonKeepsRoomWithoutLeakingBackgroundAbovePanel() {
        let source = CIImage(color: .red).cropped(to: extent)
        let result = CameraPopoutRenderer.composite(.init(image: source,
            personMask: CIImage(color: .black).cropped(to: extent), style: style()))
        XCTAssertEqual(pixel(.init(image: result, point: CGPoint(x: 100, y: 30)))[3], 255)
        XCTAssertEqual(pixel(.init(image: result, point: CGPoint(x: 100, y: 90)))[3], 0)
    }

    func testMaskFollowsZoomAndCropWithoutMovingSourcePixels() {
        let source = CIImage(color: .green).cropped(to: extent)
        let placement = CameraPopoutStyle(.init(target: CGRect(x: 30, y: 70, width: 200, height: 100),
            cropAmount: CGPoint(x: 0.5, y: 0.5), cropPosition: CGPoint(x: 0.5, y: -0.5),
            fitsSource: false, cornerRadius: 0, headroom: CameraPopoutStyle.defaultHeadroom))
        let crop = placement.placement.sourceCropRectangle(sourceExtent: extent)
        let result = CameraPopoutRenderer.composite(.init(image: source,
            personMask: CIImage(color: .black).cropped(to: extent), style: placement))
        XCTAssertEqual(pixel(.init(image: result, point: CGPoint(x: crop.midX, y: crop.minY + crop.height * 0.4)))[3], 255)
        XCTAssertEqual(pixel(.init(image: result, point: CGPoint(x: crop.midX, y: crop.minY + crop.height * 0.9)))[3], 0)
    }

    func testSceneAndPortableProjectRoundTripPopout() throws {
        var layout = SceneLayout.cameraInsetLayout(for: .vertical, shape: .popout)
        layout.cameraMask = .popout
        let scene = RecordingScene(enabledSources: [.screen, .camera], sceneLayout: layout)
        let data = try JSONEncoder().encode(RecordingProject.SceneSnapshot(scene))
        let decoded = try JSONDecoder().decode(RecordingProject.SceneSnapshot.self, from: data)
        XCTAssertEqual(try XCTUnwrap(RecordingScene(snapshot: decoded)), scene)
        XCTAssertEqual(SceneCameraMask(SceneCameraMask.popout.portableShape), .popout)
        XCTAssertEqual(layout.cameraInsetShape(in: .vertical), .popout)
    }

    func testPopoutKeepsOriginalCameraBackgroundDuringRecording() {
        var settings = RecordingSettings()
        settings.removesCameraBackgroundAfterRecording = true
        let result = RecordingSceneMutation.applyingCameraInset(alignment: .bottomRight,
            shape: .popout, size: 0.9, to: settings, screenAspectRatio: 16.0 / 9, cameraAspectRatio: 16.0 / 9)
        XCTAssertFalse(result.settings.removesCameraBackgroundAfterRecording)
        XCTAssertEqual(result.settings.sceneLayout.cameraMask, .popout)
    }

    func testRealCameraExportProof() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let sourcePath = environment["BLITZ_POPOUT_CAMERA_SOURCE"],
              let outputPath = environment["BLITZ_POPOUT_OUTPUT"] else {
            throw XCTSkip("Provide a camera source and isolated output directory for the visual proof.")
        }
        let output = URL(fileURLWithPath: outputPath)
        let fixture = try await SyntheticTake()
        var settings = fixture.settings
        settings.outputDirectory = output
        settings.enabledSources = [.screen, .camera]
        settings.outputResolution = .p720
        settings.framesPerSecond = 24
        settings.sceneLayout = SceneLayout.cameraInsetLayout(for: .vertical, shape: .popout, size: 0.9)
        settings.sceneLayout.cameraMask = .popout
        settings.screenContentMode = .fit
        settings.sceneLayout.screenFrame = CGRect(x: 0.05, y: 0.4, width: 0.9, height: 0.55)
        settings.cameraCornerRadius = 0.08
        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: sourcePath), to: take.cameraURL)
        try FileManager.default.copyItem(at: fixture.take.screenURL, to: take.screenURL)
        let events = [RecordingSceneEvent(time: 0, scene: RecordingScene(settings: settings))]
        try store.writeRecordingProject(for: take, settings: settings, sceneEvents: events, finalVideoURL: nil)
        let export = try await Merger.exportFinalVideo(.init(take: take, settings: settings,
            sceneEvents: events, backgroundMusic: nil, destinationURL: output.appendingPathComponent("popout.mp4"),
            progressHandler: nil, timelineEdits: .empty, playbackRate: 1))
        let asset = AVURLAsset(url: export)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 720, height: 1280))
        let fps = try await track.load(.nominalFrameRate)
        XCTAssertEqual(fps, 24, accuracy: 0.01)
        print("POPOUT_PROJECT=\(take.projectURL.path)")
        print("POPOUT_EXPORT=\(export.path)")
    }

    func testRealCameraPreviewPerformance() async throws {
        guard let sourcePath = ProcessInfo.processInfo.environment["BLITZ_POPOUT_CAMERA_SOURCE"] else {
            throw XCTSkip("Provide a camera source to measure local preview processing.")
        }
        let asset = AVURLAsset(url: URL(fileURLWithPath: sourcePath))
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        let renderer = CameraPopoutRenderer()
        let renderContext = CIContext(options: [.cacheIntermediates: false])
        var elapsed: [Double] = []
        var processed = 0
        while processed < 72, let sample = output.copyNextSampleBuffer(),
              let buffer = CMSampleBufferGetImageBuffer(sample) {
            let source = CIImage(cvPixelBuffer: buffer)
            let scale = min(1, 960 / max(source.extent.width, source.extent.height))
            let input = source.transformed(by: .init(scaleX: scale, y: scale))
            let placement = CameraPopoutStyle(.init(target: input.extent, cropAmount: .zero,
                cropPosition: .zero, fitsSource: false, cornerRadius: 24, headroom: CameraPopoutStyle.defaultHeadroom))
            let start = CFAbsoluteTimeGetCurrent()
            let image = renderer.image(.init(image: input, style: placement))
            XCTAssertNotNil(renderContext.createCGImage(image, from: image.extent))
            let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000
            if processed > 2 { elapsed.append(duration) }
            processed += 1
        }
        reader.cancelReading()
        XCTAssertEqual(processed, 72)
        let sorted = elapsed.sorted()
        let mean = elapsed.reduce(0, +) / Double(elapsed.count)
        let p95 = sorted[Int(Double(sorted.count - 1) * 0.95)]
        print("POPOUT_PREVIEW_MS mean=\(mean) p95=\(p95) frames=\(elapsed.count)")
    }

    private func style() -> CameraPopoutStyle {
        CameraPopoutStyle(.init(target: extent, cropAmount: .zero, cropPosition: .zero,
                               fitsSource: false, cornerRadius: 12,
                               headroom: CameraPopoutStyle.defaultHeadroom))
    }

    private struct PixelRequest {
        let image: CIImage
        let point: CGPoint
    }

    private func pixel(_ request: PixelRequest) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        context.render(request.image, toBitmap: &bytes, rowBytes: 4,
                       bounds: CGRect(origin: request.point, size: CGSize(width: 1, height: 1)),
                       format: .RGBA8, colorSpace: nil)
        return bytes
    }
}
