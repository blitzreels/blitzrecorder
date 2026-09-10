@testable import BlitzRecorderApp
import XCTest

final class IdlePreviewRestartPolicyTests: XCTestCase {
    func testCompletedRecordingRestartsPreviewWithoutAnExtraCooldown() {
        XCTAssertEqual(
            IdlePreviewRestartPolicy.delayNanoseconds(previousState: .finishing, newState: .idle),
            0
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
