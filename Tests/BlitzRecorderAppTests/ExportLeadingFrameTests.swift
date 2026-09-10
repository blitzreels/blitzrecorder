import AVFoundation
import XCTest
@testable import BlitzRecorderApp

final class ExportLeadingFrameTests: XCTestCase {
    func testFallbackCannotFillLaterMissingFramesOrStartBeforeTheSource() async throws {
        let fixture = try SyntheticRecording()
        try await fixture.writeVideo(.init(url: fixture.take.screenURL, frames: 30))
        let leading = ExportLeadingFrame(.init(asset: AVURLAsset(url: fixture.take.screenURL), sourceStart: .zero,
            compositionStart: CMTime(seconds: 1, preferredTimescale: 600), frameDuration: CMTime(value: 1, timescale: 30)))
        XCTAssertNil(leading.image(at: .zero))
        let first = try XCTUnwrap(leading.image(at: CMTime(seconds: 1, preferredTimescale: 600)))
        XCTAssertTrue(first === leading.image(at: CMTime(seconds: 1.001, preferredTimescale: 600)))
        XCTAssertNil(leading.image(at: CMTime(seconds: 1.1, preferredTimescale: 600)))
    }
}
