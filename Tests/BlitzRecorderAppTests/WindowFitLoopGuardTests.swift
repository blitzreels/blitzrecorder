import XCTest
@testable import BlitzRecorderApp

final class WindowFitLoopGuardTests: XCTestCase {
    func testPausesAKeyAfterRepeatedFitsAndResets() {
        var guardrail = WindowFitLoopGuard()
        let start = Date(timeIntervalSince1970: 0)
        for offset in 0..<WindowFitLoopGuard.limit {
            XCTAssertEqual(guardrail.admit(.init(key: "w", now: start.addingTimeInterval(Double(offset)), origin: .automatic)), .allow)
        }
        XCTAssertEqual(guardrail.admit(.init(key: "w", now: start.addingTimeInterval(5), origin: .automatic)), .pauseNow)
        XCTAssertEqual(guardrail.admit(.init(key: "w", now: start.addingTimeInterval(60), origin: .automatic)), .paused)
        XCTAssertEqual(guardrail.admit(.init(key: "other", now: start.addingTimeInterval(60), origin: .automatic)), .allow)
        guardrail.reset()
        XCTAssertEqual(guardrail.admit(.init(key: "w", now: start.addingTimeInterval(61), origin: .automatic)), .allow)
    }

    func testSpacedOutFitsNeverPause() {
        var guardrail = WindowFitLoopGuard()
        let start = Date(timeIntervalSince1970: 0)
        for index in 0..<20 {
            XCTAssertEqual(guardrail.admit(.init(key: "w", now: start.addingTimeInterval(Double(index) * 10), origin: .automatic)), .allow)
        }
    }

    func testRepeatedUserAdjustmentsDoNotConsumeAutomaticFitBudget() {
        var guardrail = WindowFitLoopGuard()
        let now = Date(timeIntervalSince1970: 0)
        for _ in 0..<20 {
            XCTAssertEqual(guardrail.admit(.init(key: "w", now: now, origin: .userInitiated)), .allow)
        }
        for _ in 0..<WindowFitLoopGuard.limit {
            XCTAssertEqual(guardrail.admit(.init(key: "w", now: now, origin: .automatic)), .allow)
        }
        XCTAssertEqual(guardrail.admit(.init(key: "w", now: now, origin: .automatic)), .pauseNow)
    }

    func testUserFitResumesOnlyItsPausedWindow() {
        var guardrail = WindowFitLoopGuard()
        let now = Date(timeIntervalSince1970: 0)
        for key in ["w", "other"] {
            for _ in 0..<WindowFitLoopGuard.limit {
                XCTAssertEqual(guardrail.admit(.init(key: key, now: now, origin: .automatic)), .allow)
            }
            XCTAssertEqual(guardrail.admit(.init(key: key, now: now, origin: .automatic)), .pauseNow)
        }
        XCTAssertEqual(guardrail.admit(.init(key: "w", now: now, origin: .userInitiated)), .allow)
        XCTAssertEqual(guardrail.admit(.init(key: "w", now: now, origin: .automatic)), .allow)
        XCTAssertEqual(guardrail.admit(.init(key: "other", now: now, origin: .automatic)), .paused)
    }
}
