import ScreenCaptureKit
@testable import BlitzRecorderApp
import XCTest

final class ScreenContentPickerTests: XCTestCase {
    func testAutomaticFitPickerOnlyAllowsWindowSelection() {
        XCTAssertEqual(
            ScreenContentPickerSelectionPolicy.appWindow.allowedModes,
            .singleWindow
        )
    }

    func testAutomaticFitRejectsDisplaySelectionsReturnedBySystemPicker() {
        XCTAssertFalse(ScreenContentPickerSelectionPolicy.appWindow.accepts(.display))
        XCTAssertTrue(ScreenContentPickerSelectionPolicy.appWindow.accepts(.application))
        XCTAssertTrue(ScreenContentPickerSelectionPolicy.appWindow.accepts(.window))
    }

    func testFullScreenPickerOnlyAllowsDisplaySelection() {
        XCTAssertEqual(
            ScreenContentPickerSelectionPolicy.fullScreen.allowedModes,
            .singleDisplay
        )
        XCTAssertTrue(ScreenContentPickerSelectionPolicy.fullScreen.accepts(.display))
        XCTAssertFalse(ScreenContentPickerSelectionPolicy.fullScreen.accepts(.window))
    }

    func testPickerPoliciesAcceptUnknownBindingOnSupportedOlderMacOS() {
        XCTAssertTrue(ScreenContentPickerSelectionPolicy.appWindow.accepts(nil))
        XCTAssertTrue(ScreenContentPickerSelectionPolicy.fullScreen.accepts(nil))
        XCTAssertTrue(ScreenContentPickerSelectionPolicy.anyScreenContent.accepts(nil))
    }

    func testPickerPolicyRetainsSourceKindWhenOlderMacOSCannotInspectFilter() {
        XCTAssertEqual(ScreenContentPickerSelectionPolicy.appWindow.fallbackSourceKind, .window)
        XCTAssertEqual(ScreenContentPickerSelectionPolicy.fullScreen.fallbackSourceKind, .display)
        XCTAssertNil(ScreenContentPickerSelectionPolicy.anyScreenContent.fallbackSourceKind)
    }

    func testOnlyAppWindowPickerTriggersAutomaticWindowFit() {
        XCTAssertTrue(ScreenContentPickerSelectionPolicy.appWindow.shouldAutoFitPickedWindow)
        XCTAssertFalse(ScreenContentPickerSelectionPolicy.fullScreen.shouldAutoFitPickedWindow)
        XCTAssertFalse(ScreenContentPickerSelectionPolicy.anyScreenContent.shouldAutoFitPickedWindow)
    }

    func testRecordingSourceSwitchAllowsDisplayAndWindowSelection() {
        XCTAssertTrue(ScreenContentPickerSelectionPolicy.anyScreenContent.allowedModes.contains(.singleDisplay))
        XCTAssertTrue(ScreenContentPickerSelectionPolicy.anyScreenContent.allowedModes.contains(.singleWindow))
    }

    func testRecordingSourceSwitchDoesNotRequestInitialFitDefault() {
        XCTAssertFalse(ScreenContentPickerSelectionPolicy.anyScreenContent.shouldAutoFitPickedWindow)
    }

    func testActiveRecordingRetargetsExistingStream() {
        XCTAssertEqual(
            ScreenContentPickerPresentationMode.resolve(hasActiveStream: true),
            .updateActiveStream
        )
    }

    func testIdleSelectionStartsNewPickerSession() {
        XCTAssertEqual(
            ScreenContentPickerPresentationMode.resolve(hasActiveStream: false),
            .newSelection
        )
    }
}
