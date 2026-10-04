import XCTest
@testable import BlitzRecorderApp

final class WindowFitLoopGuardTests: XCTestCase {
    func testPausesAKeyAfterRepeatedFitsAndResets() {
        var guardrail = WindowFitLoopGuard()
        let start = Date(timeIntervalSince1970: 0)
        for offset in 0..<WindowFitLoopGuard.limit {
            XCTAssertEqual(guardrail.admit(.init(key: "w", now: start.addingTimeInterval(Double(offset)))), .allow)
        }
        XCTAssertEqual(guardrail.admit(.init(key: "w", now: start.addingTimeInterval(5))), .pauseNow)
        XCTAssertEqual(guardrail.admit(.init(key: "w", now: start.addingTimeInterval(60))), .paused)
        XCTAssertEqual(guardrail.admit(.init(key: "other", now: start.addingTimeInterval(60))), .allow)
        guardrail.reset()
        XCTAssertEqual(guardrail.admit(.init(key: "w", now: start.addingTimeInterval(61))), .allow)
    }

    func testSpacedOutFitsNeverPause() {
        var guardrail = WindowFitLoopGuard()
        let start = Date(timeIntervalSince1970: 0)
        for index in 0..<20 {
            XCTAssertEqual(guardrail.admit(.init(key: "w", now: start.addingTimeInterval(Double(index) * 10))), .allow)
        }
    }
}
