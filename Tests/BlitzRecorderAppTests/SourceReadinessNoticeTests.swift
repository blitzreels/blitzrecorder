import XCTest
@testable import BlitzRecorderApp

final class SourceReadinessNoticeTests: XCTestCase {
    func testCameraWithoutVideoOffersRetryAndConnectionGuidance() throws {
        let notice = try XCTUnwrap(SourceReadinessNotice.resolve(.init(source: .camera, blockers: [
            .init(source: .camera, permission: "Camera availability", status: "unavailable", recovery: "No video.")
        ])))
        XCTAssertEqual(notice.action?.title, "Retry camera")
        XCTAssertTrue(notice.detail.contains("iPhone"))
        XCTAssertFalse(notice.isWaiting)
    }

    @MainActor
    func testRetryCameraUsesPreviewRecoveryAction() throws {
        let suite = "SourceReadinessNoticeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = RecorderCoordinator(accessController: AccessController(defaults: defaults), defaults: defaults)
        let vm = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
        var retries = 0
        vm.onRetryCameraPreview = { retries += 1 }

        vm.resolveSourceReadiness(.retryCamera)

        XCTAssertEqual(retries, 1)
        vm.applyState(.recording)
        vm.resolveSourceReadiness(.retryCamera)
        XCTAssertEqual(retries, 1)
    }

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
