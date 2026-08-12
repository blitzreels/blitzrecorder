@testable import BlitzRecorderApp
import XCTest

final class ScreenPreviewLifecycleTests: XCTestCase {
    func testPersistentDisplayBindingIsAvailableWithoutPickerSession() {
        var settings = RecordingSettings()
        settings.usesPickedScreenContent = false
        settings.screenSourceBinding = .display(id: "4")

        XCTAssertTrue(ScreenPreviewLifecycle.sourceIsAvailable(.init(
            settings: settings,
            hasPersistentScreenCaptureAccess: true,
            hasActivePickedContent: false
        )))
    }

    func testSavedDisplayBindingWithoutCaptureAccessIsUnavailable() {
        var settings = RecordingSettings()
        settings.usesPickedScreenContent = false
        settings.screenSourceBinding = .display(id: "4")

        XCTAssertFalse(ScreenPreviewLifecycle.sourceIsAvailable(.init(
            settings: settings,
            hasPersistentScreenCaptureAccess: false,
            hasActivePickedContent: false
        )))
    }

    func testActivePickerSessionIsAvailableWithoutPersistentAccess() {
        var settings = RecordingSettings()
        settings.usesPickedScreenContent = true

        XCTAssertTrue(ScreenPreviewLifecycle.sourceIsAvailable(.init(
            settings: settings,
            hasPersistentScreenCaptureAccess: false,
            hasActivePickedContent: true
        )))
    }

    func testRetainedPickerFilterDoesNotConfigurePersistentScene() {
        var settings = RecordingSettings()
        settings.usesPickedScreenContent = false

        XCTAssertFalse(ScreenPreviewLifecycle.sourceIsAvailable(.init(
            settings: settings,
            hasPersistentScreenCaptureAccess: true,
            hasActivePickedContent: true
        )))
    }

    @MainActor
    func testSceneRestoresOnlyItsExactPickerSelection() {
        let selectionID = UUID()

        XCTAssertTrue(ScreenSourceSelection.canRestorePickedContent(.init(
            snapshotUsesPickedContent: true,
            hasActiveFilter: true,
            activeSelectionID: selectionID,
            snapshotSelectionID: selectionID
        )))
        XCTAssertFalse(ScreenSourceSelection.canRestorePickedContent(.init(
            snapshotUsesPickedContent: true,
            hasActiveFilter: true,
            activeSelectionID: selectionID,
            snapshotSelectionID: UUID()
        )))
    }

    @MainActor
    func testSceneCannotRestoreStalePickerFlagWithoutActiveFilter() {
        let selectionID = UUID()

        XCTAssertFalse(ScreenSourceSelection.canRestorePickedContent(.init(
            snapshotUsesPickedContent: true,
            hasActiveFilter: false,
            activeSelectionID: selectionID,
            snapshotSelectionID: selectionID
        )))
    }

    func testHiddenConfiguredScreenPreservesRunningPreviewStream() {
        var settings = RecordingSettings()
        settings.enabledSources = [.camera]
        settings.hiddenSources = [.screen]

        let action = ScreenPreviewLifecycle.action(settings: settings)

        XCTAssertEqual(action, .preserveHidden)
    }

    func testRemovedScreenRestartsSoCallerCanStopPreviewStream() {
        var settings = RecordingSettings()
        settings.enabledSources = [.camera]
        settings.hiddenSources = []

        let action = ScreenPreviewLifecycle.action(settings: settings)

        XCTAssertEqual(action, .restart)
    }

    func testReenabledScreenFallsBackToRestartWhenPreviewCannotBeReused() {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen]
        settings.hiddenSources = [.camera]

        let action = ScreenPreviewLifecycle.action(settings: settings)

        XCTAssertEqual(action, .restart)
    }

    func testReenabledScreenReusesHealthyRunningPreview() {
        XCTAssertTrue(ScreenPreviewLifecycle.shouldReuse(.init(
            isRunning: true,
            hasPreviewContent: true,
            screenEnabled: true,
            screenHidden: false,
            captureSignatureMatches: true
        )))
    }

    func testReenabledScreenRestartsStalledRunningPreview() {
        XCTAssertFalse(ScreenPreviewLifecycle.shouldReuse(.init(
            isRunning: true,
            hasPreviewContent: false,
            screenEnabled: true,
            screenHidden: false,
            captureSignatureMatches: true
        )))
    }

    func testReenabledScreenRestartsWhenSelectionChangedWhileHidden() {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen]
        settings.hiddenSources = [.camera]

        let action = ScreenPreviewLifecycle.action(settings: settings)

        XCTAssertEqual(action, .restart)
    }

    func testWindowUnavailableUsesActionableDetailMessage() {
        var settings = RecordingSettings()
        settings.screenSourceBinding = ScreenSourceBinding(
            kind: .window,
            displayID: nil,
            bundleIdentifier: "com.example.App",
            applicationName: "Example",
            processID: nil,
            windowID: 42,
            windowTitle: "Demo"
        )

        let message = ScreenPreviewFailureMessage.detailMessage(
            for: RecorderError.screenSourceUnavailable("Example - Demo"),
            settings: settings
        )

        XCTAssertTrue(message.contains("Selected window unavailable"))
        XCTAssertTrue(message.contains("Example - Demo"))
        XCTAssertTrue(message.contains("is not available for capture"))
    }

    func testPreviewFailureDetailKeepsUnderlyingReason() {
        var settings = RecordingSettings()
        settings.screenSourceBinding = ScreenSourceBinding(
            kind: .application,
            displayID: nil,
            bundleIdentifier: "com.example.App",
            applicationName: "Example",
            processID: 12,
            windowID: nil,
            windowTitle: nil
        )

        let message = ScreenPreviewFailureMessage.detailMessage(
            for: RecorderError.screenSourceUnavailable("Example"),
            settings: settings
        )

        XCTAssertTrue(message.contains("Selected app unavailable"))
        XCTAssertTrue(message.contains("Example"))
        XCTAssertTrue(message.contains("is not available for capture"))
    }

    func testScreenCapturePermissionUsesSpecificDetailMessage() {
        let message = ScreenPreviewFailureMessage.detailMessage(
            for: RecorderError.screenCapturePermissionRequired,
            settings: RecordingSettings()
        )

        XCTAssertTrue(message.contains("Screen Recording permission required"))
    }
}
