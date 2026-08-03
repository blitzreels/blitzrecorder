import XCTest
@testable import BlitzRecorderApp

final class IdleCameraPreviewPolicyTests: XCTestCase {
    func testIdlePreviewStartsWhileAnotherApplicationUsesCamera() {
        XCTAssertTrue(IdleCameraPreviewPolicy.shouldStart(.init(
            appIsActive: true,
            windowIsVisible: true,
            keepsIdleCaptureResourcesActive: true,
            cameraIsRunningSomewhere: true
        )))
    }

    func testIdlePreviewRemainsActiveWhileApplicationIsInactive() {
        XCTAssertTrue(IdleCameraPreviewPolicy.shouldStart(.init(
            appIsActive: false,
            windowIsVisible: true,
            keepsIdleCaptureResourcesActive: true,
            cameraIsRunningSomewhere: false
        )))
    }

    func testIdlePreviewStartsForVisibleActiveRecorderWithAvailableCamera() {
        XCTAssertTrue(IdleCameraPreviewPolicy.shouldStart(.init(
            appIsActive: true,
            windowIsVisible: true,
            keepsIdleCaptureResourcesActive: true,
            cameraIsRunningSomewhere: false
        )))
    }

    func testIdlePreviewStopsOutsideRecorderMode() {
        XCTAssertFalse(IdleCameraPreviewPolicy.shouldStart(.init(
            appIsActive: true,
            windowIsVisible: true,
            keepsIdleCaptureResourcesActive: false,
            cameraIsRunningSomewhere: true
        )))
    }
}
