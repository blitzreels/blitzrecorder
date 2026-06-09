@testable import BlitzRecorderApp
import XCTest

final class IdlePreviewRestartPolicyTests: XCTestCase {
    func testFinishingToIdleDelaysPreviewRestart() {
        XCTAssertEqual(
            IdlePreviewRestartPolicy.delayNanoseconds(previousState: .finishing, newState: .idle),
            IdlePreviewRestartPolicy.postFinishingDelayNanoseconds
        )
    }

    func testOtherIdleTransitionsRestartPreviewImmediately() {
        XCTAssertEqual(
            IdlePreviewRestartPolicy.delayNanoseconds(previousState: .starting, newState: .idle),
            0
        )
        XCTAssertEqual(
            IdlePreviewRestartPolicy.delayNanoseconds(previousState: .recording, newState: .idle),
            0
        )
        XCTAssertEqual(
            IdlePreviewRestartPolicy.delayNanoseconds(previousState: .idle, newState: .idle),
            0
        )
    }
}
