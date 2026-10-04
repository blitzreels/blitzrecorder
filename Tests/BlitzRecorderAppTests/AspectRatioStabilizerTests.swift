import XCTest
@testable import BlitzRecorderApp

final class AspectRatioStabilizerTests: XCTestCase {
    func testAlternatingFramesFromTheLogNeverMoveTheLayout() {
        var stabilizer = AspectRatioStabilizer()
        XCTAssertEqual(stabilizer.feed(2.0830), 2.0830)
        for index in 0..<200 {
            let value: CGFloat = index.isMultiple(of: 2) ? 1.8156 : 2.0833
            XCTAssertEqual(stabilizer.feed(value), 2.0830, accuracy: 0.0001)
        }
    }

    func testARealChangeLandsOnceAfterItHolds() {
        var stabilizer = AspectRatioStabilizer()
        _ = stabilizer.feed(1.7778)
        var outputs: [CGFloat] = []
        for _ in 0..<12 { outputs.append(stabilizer.feed(2.0833)) }
        XCTAssertEqual(Set(outputs.prefix(AspectRatioStabilizer.requiredFrames - 1)), [1.7778])
        XCTAssertEqual(outputs.last ?? 0, 2.0833, accuracy: 0.0001)
        XCTAssertEqual(Set(outputs).count, 2)
    }

    @MainActor
    func testPreviewStageHoldsThroughAlternation() {
        let stage = PreviewStageView()
        stage.applyLiveFrameAspectRatio(2.0830)
        for index in 0..<60 {
            stage.applyLiveFrameAspectRatio(index.isMultiple(of: 2) ? 1.8156 : 2.0833)
        }
        XCTAssertEqual(stage.screenSourceAspectRatio, 2.0830, accuracy: 0.0001)
    }
}
