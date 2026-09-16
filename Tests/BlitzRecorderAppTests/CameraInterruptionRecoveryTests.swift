import AVFoundation
import CoreVideo
@testable import BlitzRecorderApp
import XCTest

final class CameraInterruptionRecoveryTests: XCTestCase {
    func testCameraInterruptionContinuesWithBlackFramesWhenScreenRemainsHealthy() {
        let decision = CaptureFailureRecovery.decision(.init(
            source: .camera,
            enabledSources: [.screen, .camera, .microphone]
        ))

        XCTAssertEqual(decision, .continueWithBlackCamera)
    }

    func testCameraInterruptionStopsCameraOnlyTake() {
        let decision = CaptureFailureRecovery.decision(.init(
            source: .camera,
            enabledSources: [.camera, .microphone]
        ))

        XCTAssertEqual(decision, .stopTake)
    }

    func testScreenInterruptionRemainsFatal() {
        let decision = CaptureFailureRecovery.decision(.init(
            source: .screen,
            enabledSources: [.screen, .camera, .microphone]
        ))

        XCTAssertEqual(decision, .stopTake)
    }

    func testCameraInterruptionStopsDuringLiveCompositorOrRemoteCamera() {
        XCTAssertEqual(
            CaptureFailureRecovery.decision(.init(
                source: .camera,
                enabledSources: [.screen, .camera],
                usesLiveCompositor: true
            )),
            .stopTake
        )
        XCTAssertEqual(
            CaptureFailureRecovery.decision(.init(
                source: .camera,
                enabledSources: [.screen, .camera],
                usesRemoteCamera: true
            )),
            .stopTake
        )
    }

    func testBlackFrameGeneratorProducesRetimedBlackCameraFrame() throws {
        let generator = try CameraBlackFrameGenerator(.init(
            width: 64,
            height: 64,
            pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            framesPerSecond: 30
        ))
        let presentationTime = CMTime(seconds: 2, preferredTimescale: 600)

        let sampleBuffer = try XCTUnwrap(generator.sampleBuffer(at: presentationTime))
        let pixelBuffer = try XCTUnwrap(CMSampleBufferGetImageBuffer(sampleBuffer))

        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(sampleBuffer), presentationTime)
        XCTAssertTrue(Self.isBlack(pixelBuffer))
    }

    func testBlackFrameGeneratorExtendsEncodedCameraMedia() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraInterruptionRecoveryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("camera.mov")
        let writer = try VideoFileWriter(
            url: outputURL,
            width: 64,
            height: 64,
            bitrate: 1_000_000,
            fps: 30,
            outputFormat: .mov
        )
        let generator = try CameraBlackFrameGenerator(.init(
            width: 64,
            height: 64,
            pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            framesPerSecond: 30
        ))

        for frame in 0..<60 {
            let presentationTime = CMTime(value: CMTimeValue(frame), timescale: 30)
            writer.append(try XCTUnwrap(generator.sampleBuffer(at: presentationTime)))
            try await Task.sleep(for: .milliseconds(10))
        }

        let completion = try await writer.finish()
        let duration = try await AVURLAsset(url: outputURL).load(.duration)

        XCTAssertTrue(completion.wroteMedia)
        XCTAssertGreaterThan(duration.seconds, 1.9)
    }

    private static func isBlack(_ pixelBuffer: CVPixelBuffer) -> Bool {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard CVPixelBufferGetPlaneCount(pixelBuffer) == 2,
              let luma = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
              let chroma = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) else {
            return false
        }
        let lumaBytes = luma.assumingMemoryBound(to: UInt8.self)
        let chromaBytes = chroma.assumingMemoryBound(to: UInt8.self)
        let lumaCount = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            * CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let chromaCount = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
            * CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
        return (0..<lumaCount).allSatisfy { lumaBytes[$0] == 0 }
            && (0..<chromaCount).allSatisfy { chromaBytes[$0] == 128 }
    }
}
