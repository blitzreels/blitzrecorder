import AVFoundation
import CoreVideo
@testable import BlitzRecorderApp
import XCTest

final class CameraFrameNormalizationTests: XCTestCase {
    func testDetectsOsmoStyleLandscapeImageInsidePortraitBuffer() throws {
        let pixelBuffer = try makePixelBuffer(.init(
            width: 180,
            height: 320,
            activeRect: CGRect(x: 0, y: 110, width: 180, height: 100)
        ))

        let plan = CameraFrameLetterboxDetector.normalizationPlan(.init(
            pixelBuffer: pixelBuffer
        ))

        XCTAssertEqual(plan?.cropRect, CGRect(x: 0, y: 110, width: 180, height: 100))
        XCTAssertEqual(plan?.outputSize, CGSize(width: 180, height: 100))
    }

    func testKeepsNormalPortraitCameraBufferUnchanged() throws {
        let pixelBuffer = try makePixelBuffer(.init(
            width: 180,
            height: 320,
            activeRect: CGRect(x: 0, y: 0, width: 180, height: 320)
        ))

        let plan = CameraFrameLetterboxDetector.normalizationPlan(.init(
            pixelBuffer: pixelBuffer
        ))

        XCTAssertNil(plan)
    }

    func testKeepsEntirelyDarkFrameUnchanged() throws {
        let pixelBuffer = try makePixelBuffer(.init(
            width: 180,
            height: 320,
            activeRect: nil
        ))

        let plan = CameraFrameLetterboxDetector.normalizationPlan(.init(
            pixelBuffer: pixelBuffer
        ))

        XCTAssertNil(plan)
    }

    func testCropsBiPlanarSampleAndPreservesPresentationTime() throws {
        let pixelBuffer = try makePixelBuffer(.init(
            width: 180,
            height: 320,
            activeRect: CGRect(x: 0, y: 110, width: 180, height: 100)
        ))
        let sampleBuffer = try makeSampleBuffer(.init(
            pixelBuffer: pixelBuffer,
            presentationTime: CMTime(value: 37, timescale: 25)
        ))
        let plan = try XCTUnwrap(CameraFrameLetterboxDetector.normalizationPlan(.init(
            pixelBuffer: pixelBuffer
        )))

        let normalized = try XCTUnwrap(
            CameraFrameNormalizer(plan: plan).normalize(sampleBuffer)
        )
        let normalizedPixelBuffer = try XCTUnwrap(CMSampleBufferGetImageBuffer(normalized))

        XCTAssertEqual(CVPixelBufferGetWidth(normalizedPixelBuffer), 180)
        XCTAssertEqual(CVPixelBufferGetHeight(normalizedPixelBuffer), 100)
        XCTAssertEqual(
            CMSampleBufferGetPresentationTimeStamp(normalized),
            CMTime(value: 37, timescale: 25)
        )
        XCTAssertEqual(lumaValue(.init(pixelBuffer: normalizedPixelBuffer, x: 90, y: 50)), 128)
    }

    func testPortraitStartupWaitsForEnoughSamplesToDetectLetterboxing() {
        let firstDecision = CameraFrameNormalizationStartupPolicy.decision(.init(
            sourceSize: CGSize(width: 1080, height: 1920),
            bufferedSampleCount: 1,
            normalizationPlan: nil
        ))
        let finalDecision = CameraFrameNormalizationStartupPolicy.decision(.init(
            sourceSize: CGSize(width: 1080, height: 1920),
            bufferedSampleCount: CameraFrameNormalizationStartupPolicy.portraitSampleLimit,
            normalizationPlan: nil
        ))

        XCTAssertEqual(firstDecision, .waitForMoreSamples)
        XCTAssertEqual(finalDecision, .start(nil))
    }

    func testPortraitStartupBeginsAsSoonAsLetterboxingIsDetected() {
        let plan = CameraFrameNormalizationPlan(
            cropRect: CGRect(x: 0, y: 656, width: 1080, height: 608)
        )

        let decision = CameraFrameNormalizationStartupPolicy.decision(.init(
            sourceSize: CGSize(width: 1080, height: 1920),
            bufferedSampleCount: 2,
            normalizationPlan: plan
        ))

        XCTAssertEqual(decision, .start(plan))
    }

    func testLandscapeStartupDoesNotWaitForDetection() {
        let decision = CameraFrameNormalizationStartupPolicy.decision(.init(
            sourceSize: CGSize(width: 1920, height: 1080),
            bufferedSampleCount: 1,
            normalizationPlan: nil
        ))

        XCTAssertEqual(decision, .start(nil))
    }

    private struct PixelBufferRequest {
        let width: Int
        let height: Int
        let activeRect: CGRect?
    }

    private struct SampleBufferRequest {
        let pixelBuffer: CVPixelBuffer
        let presentationTime: CMTime
    }

    private struct LumaValueRequest {
        let pixelBuffer: CVPixelBuffer
        let x: Int
        let y: Int
    }

    private func makePixelBuffer(
        _ request: PixelBufferRequest
    ) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            request.width,
            request.height,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw RecorderError.writerNotReady
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        for plane in 0..<CVPixelBufferGetPlaneCount(pixelBuffer) {
            guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, plane) else {
                continue
            }
            memset(
                baseAddress,
                plane == 0 ? 0 : 128,
                CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, plane)
                    * CVPixelBufferGetHeightOfPlane(pixelBuffer, plane)
            )
        }

        if let activeRect = request.activeRect,
           let lumaBaseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) {
            let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            for y in Int(activeRect.minY)..<Int(activeRect.maxY) {
                memset(
                    lumaBaseAddress.advanced(by: y * bytesPerRow + Int(activeRect.minX)),
                    128,
                    Int(activeRect.width)
                )
            }
        }
        return pixelBuffer
    }

    private func makeSampleBuffer(
        _ request: SampleBufferRequest
    ) throws -> CMSampleBuffer {
        var formatDescription: CMVideoFormatDescription?
        let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: request.pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard formatStatus == noErr, let formatDescription else {
            throw RecorderError.writerNotReady
        }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 25),
            presentationTimeStamp: request.presentationTime,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: request.pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr, let sampleBuffer else {
            throw RecorderError.writerNotReady
        }
        return sampleBuffer
    }

    private func lumaValue(
        _ request: LumaValueRequest
    ) -> UInt8 {
        CVPixelBufferLockBaseAddress(request.pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(request.pixelBuffer, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(request.pixelBuffer, 0) else {
            return 0
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(request.pixelBuffer, 0)
        return baseAddress
            .advanced(by: request.y * bytesPerRow + request.x)
            .assumingMemoryBound(to: UInt8.self)
            .pointee
    }
}
