import XCTest
@testable import BlitzRecorderApp

final class IdleCameraPreviewPolicyTests: XCTestCase {
    func testIdlePreviewStopsWhileApplicationIsInactive() {
        XCTAssertFalse(IdleCameraPreviewPolicy.shouldStart(.init(
            appIsActive: false,
            windowIsVisible: true,
            keepsIdleCaptureResourcesActive: true
        )))
    }

    func testIdlePreviewStopsWhenRecorderWindowIsHidden() {
        XCTAssertFalse(IdleCameraPreviewPolicy.shouldStart(.init(
            appIsActive: true,
            windowIsVisible: false,
            keepsIdleCaptureResourcesActive: true
        )))
    }

    func testIdlePreviewStartsForVisibleActiveRecorderWithAvailableCamera() {
        XCTAssertTrue(IdleCameraPreviewPolicy.shouldStart(.init(
            appIsActive: true,
            windowIsVisible: true,
            keepsIdleCaptureResourcesActive: true
        )))
    }

    func testIdlePreviewStopsOutsideRecorderMode() {
        XCTAssertFalse(IdleCameraPreviewPolicy.shouldStart(.init(
            appIsActive: true,
            windowIsVisible: true,
            keepsIdleCaptureResourcesActive: false
        )))
    }
}
