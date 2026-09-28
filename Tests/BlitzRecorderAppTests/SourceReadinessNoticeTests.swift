import XCTest
@testable import BlitzRecorderApp

final class SourceReadinessNoticeTests: XCTestCase {
    func testMissingSelectionAsksForSourceInsteadOfPermission() throws {
        for source in [CaptureSource.screen, .systemAudio] {
            let notice = try XCTUnwrap(SourceReadinessNotice.resolve(.init(source: source, blockers: [
                .init(source: source, permission: "Screen source", status: "not selected for this session",
                      recovery: "Choose a display or window with the macOS picker.")
            ])))
            XCTAssertEqual(notice.action, .chooseScreen)
            XCTAssertFalse(notice.title.localizedCaseInsensitiveContains("permission"))
        }
    }

    func testDeniedPermissionOpensSettingsInsteadOfRepeatingThePrompt() throws {
        for source in [CaptureSource.camera, .microphone] {
            let notice = try XCTUnwrap(SourceReadinessNotice.resolve(.init(source: source, blockers: [
                .init(source: source, permission: source == .camera ? "Camera" : "Microphone",
                      status: "denied", recovery: "Allow access in System Settings.")
            ])))
            XCTAssertEqual(notice.action, source == .camera ? .cameraSettings : .microphoneSettings)
        }
    }

    func testUndecidedPermissionOffersTheNativePrompt() throws {
        for source in [CaptureSource.camera, .microphone] {
            let notice = try XCTUnwrap(SourceReadinessNotice.resolve(.init(source: source, blockers: [
                .init(source: source, permission: source == .camera ? "Camera" : "Microphone",
                      status: "not determined", recovery: "Allow access.")
            ])))
            XCTAssertEqual(notice.action, source == .camera ? .requestCamera : .requestMicrophone)
        }
    }

    func testCameraStartupIsNotReportedAsDeniedAccess() throws {
        let notice = try XCTUnwrap(SourceReadinessNotice.resolve(.init(source: .camera, blockers: [
            .init(source: .camera, permission: "Camera availability", status: "starting", recovery: "Wait.")
        ])))
        XCTAssertTrue(notice.isWaiting)
        XCTAssertNil(notice.action)
    }

    func testDisconnectedPhoneDoesNotAskForMacCameraPermission() throws {
        let notice = try XCTUnwrap(SourceReadinessNotice.resolve(.init(source: .camera, blockers: [
            .init(source: .camera, permission: "Remote iPhone", status: "not connected", recovery: "Reconnect iPhone.")
        ])))
        XCTAssertEqual(notice.action, .manageDevices)
    }

    func testSourceDoesNotInheritAnotherSourcesFailure() {
        XCTAssertNil(SourceReadinessNotice.resolve(.init(source: .microphone, blockers: [
            .init(source: .camera, permission: "Camera", status: "denied", recovery: "Allow camera.")
        ])))
    }
}
