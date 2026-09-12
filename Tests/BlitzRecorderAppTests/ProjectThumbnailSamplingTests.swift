import CoreGraphics
import XCTest
@testable import BlitzRecorderApp

final class ProjectThumbnailSamplingTests: XCTestCase {
    func testSamplesSpanTheRecordingAndStayWithinShortClips() {
        XCTAssertEqual(ProjectThumbnailSampling.times(duration: 3_600), [2, 900, 2_160])
        XCTAssertEqual(ProjectThumbnailSampling.times(duration: .nan), [0])
        XCTAssertTrue(ProjectThumbnailSampling.times(duration: 0.05).allSatisfy { $0 >= 0 && $0 < 0.05 })
    }

    func testDetailedFrameOutranksBlankOpeningFrame() throws {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 64, height: 36, bitsPerComponent: 8, bytesPerRow: 64,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ))
        context.setFillColor(gray: 0.1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 36))
        let blank = try XCTUnwrap(context.makeImage())
        context.setFillColor(gray: 0.9, alpha: 1)
        for x in stride(from: 0, to: 64, by: 8) {
            context.fill(CGRect(x: x, y: 0, width: 4, height: 36))
        }
        let detailed = try XCTUnwrap(context.makeImage())
        XCTAssertGreaterThan(ProjectThumbnailSampling.detailScore(detailed), ProjectThumbnailSampling.detailScore(blank))
    }
}
