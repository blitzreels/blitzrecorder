import AVFoundation
import CoreGraphics
import XCTest
@testable import BlitzRecorderApp

final class ProjectThumbnailSamplingTests: XCTestCase {
    func testThumbnailKeepsBlankOpeningFrameInsteadOfDetailedLaterScene() async throws {
        let fixture = try SyntheticRecording()
        let url = fixture.take.screenURL
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 640, AVVideoHeightKey: 360
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        let deadline = ProcessInfo.processInfo.systemUptime + 15
        for frame in 0..<30 {
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing, ProcessInfo.processInfo.systemUptime < deadline else {
                    writer.cancelWriting()
                    throw RecorderError.writerNotReady
                }
                try await Task.sleep(for: .milliseconds(1))
            }
            var buffer: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferCreate(
                nil, 640, 360, kCVPixelFormatType_32BGRA,
                [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer
            ), kCVReturnSuccess)
            let pixels = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            let address = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixels))
            let stride = CVPixelBufferGetBytesPerRow(pixels)
            let bytes = address.assumingMemoryBound(to: UInt8.self)
            for y in 0..<360 {
                for x in 0..<640 {
                    let value: UInt8 = frame == 0 ? 0 : (x / 8 % 2 == 0 ? 255 : 64)
                    let offset = y * stride + x * 4
                    bytes[offset] = value
                    bytes[offset + 1] = value
                    bytes[offset + 2] = value
                    bytes[offset + 3] = 255
                }
            }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            XCTAssertTrue(adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)

        let generated = await ProjectThumbnailSampling.firstFrame(.init(url: url, startSeconds: 0))
        let image = try XCTUnwrap(generated)
        var luminance: UInt8 = 255
        let context = try XCTUnwrap(CGContext(
            data: &luminance, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 1,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertLessThan(luminance, 10)
        let trimmed = await ProjectThumbnailSampling.firstFrame(.init(url: url, startSeconds: 0.5))
        let trimmedImage = try XCTUnwrap(trimmed)
        context.draw(trimmedImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertGreaterThan(luminance, 50)
    }

    func testMissingVideoHasNoThumbnail() async {
        let image = await ProjectThumbnailSampling.firstFrame(.init(
            url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov"),
            startSeconds: 0
        ))
        XCTAssertNil(image)
    }
}
