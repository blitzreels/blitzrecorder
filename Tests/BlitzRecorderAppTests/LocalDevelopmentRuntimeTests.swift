import XCTest
@testable import BlitzRecorderApp

final class LocalDevelopmentRuntimeTests: XCTestCase {
    func testVerificationEnvironmentDisablesIdleCapture() {
        let environment = [
            "BLITZRECORDER_DISABLE_IDLE_CAPTURE": "1"
        ]
        XCTAssertTrue(LocalDevelopmentRuntime.disablesIdleCapture(environment: environment))
        XCTAssertTrue(LocalDevelopmentRuntime.isNoninteractiveVerification(environment: environment))
    }

    func testNormalEnvironmentKeepsIdleCaptureEnabled() {
        XCTAssertFalse(LocalDevelopmentRuntime.disablesIdleCapture(environment: [:]))
        XCTAssertFalse(LocalDevelopmentRuntime.disablesIdleCapture(environment: [
            "BLITZRECORDER_DISABLE_IDLE_CAPTURE": "0"
        ]))
        XCTAssertFalse(LocalDevelopmentRuntime.isNoninteractiveVerification(environment: [:]))
    }
}
