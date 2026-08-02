import XCTest
@testable import BlitzRecorderApp

final class AudioLevelPublisherTests: XCTestCase {
    func testUpdateThrottlePublishesAtFifteenFramesPerSecond() {
        var throttle = AudioLevelUpdateThrottle()

        XCTAssertTrue(throttle.shouldPublish(at: 0))
        XCTAssertFalse(throttle.shouldPublish(at: 33_000_000))
        XCTAssertFalse(throttle.shouldPublish(at: 66_666_666))
        XCTAssertTrue(throttle.shouldPublish(at: 66_666_667))
    }
}
