import XCTest
@testable import BlitzRecorderApp

final class AppContentZoomTargetResolverTests: XCTestCase {
    func testPickedContentTargetsPickedWindowProcess() async {
        var settings = RecordingSettings()
        settings.usesPickedScreenContent = true
        settings.screenSourceBinding = applicationBinding(processID: 222)

        let processID = await AppContentZoomTargetResolver.processID(
            settings: settings,
            pickedWindowProcessID: { 111 },
            applicationProcessID: { _ in 222 },
            windowProcessID: { _ in 333 },
            frontWindowProcessID: { _ in 444 }
        )

        XCTAssertEqual(processID, 111)
    }

    func testPickedContentDoesNotFallBackToStaleApplicationBinding() async {
        var settings = RecordingSettings()
        settings.usesPickedScreenContent = true
        settings.screenSourceBinding = applicationBinding(processID: 222)
        var applicationBindingWasRead = false

        let processID = await AppContentZoomTargetResolver.processID(
            settings: settings,
            pickedWindowProcessID: { nil },
            applicationProcessID: { binding in
                applicationBindingWasRead = true
                return binding.processID
            },
            windowProcessID: { _ in 333 },
            frontWindowProcessID: { _ in 444 }
        )

        XCTAssertNil(processID)
        XCTAssertFalse(applicationBindingWasRead)
    }

    func testPickedContentFallsBackToFrontWindowWhenOnlyDisplayIsSelected() async {
        var settings = RecordingSettings()
        settings.usesPickedScreenContent = true
        settings.selectedDisplayID = "selected-display"
        settings.screenSourceBinding = .display(id: "bound-display")
        var requestedDisplayID: String?

        let processID = await AppContentZoomTargetResolver.processID(
            settings: settings,
            pickedWindowProcessID: { nil },
            applicationProcessID: { _ in 222 },
            windowProcessID: { _ in 333 },
            frontWindowProcessID: { displayID in
                requestedDisplayID = displayID
                return 444
            }
        )

        XCTAssertEqual(processID, 444)
        XCTAssertEqual(requestedDisplayID, "bound-display")
    }

    func testApplicationBindingTargetsApplicationProcess() async {
        var settings = RecordingSettings()
        settings.screenSourceBinding = applicationBinding(processID: 222)

        let processID = await AppContentZoomTargetResolver.processID(
            settings: settings,
            pickedWindowProcessID: { 111 },
            applicationProcessID: { binding in binding.processID },
            windowProcessID: { _ in 333 },
            frontWindowProcessID: { _ in 444 }
        )

        XCTAssertEqual(processID, 222)
    }

    func testWindowBindingTargetsWindowProcess() async {
        var settings = RecordingSettings()
        settings.screenSourceBinding = windowBinding()

        let processID = await AppContentZoomTargetResolver.processID(
            settings: settings,
            pickedWindowProcessID: { 111 },
            applicationProcessID: { _ in 222 },
            windowProcessID: { _ in 333 },
            frontWindowProcessID: { _ in 444 }
        )

        XCTAssertEqual(processID, 333)
    }

    func testDisplayBindingTargetsFrontWindowOnBoundDisplay() async {
        var settings = RecordingSettings()
        settings.selectedDisplayID = "selected-display"
        settings.screenSourceBinding = .display(id: "bound-display")
        var requestedDisplayID: String?

        let processID = await AppContentZoomTargetResolver.processID(
            settings: settings,
            pickedWindowProcessID: { 111 },
            applicationProcessID: { _ in 222 },
            windowProcessID: { _ in 333 },
            frontWindowProcessID: { displayID in
                requestedDisplayID = displayID
                return 444
            }
        )

        XCTAssertEqual(processID, 444)
        XCTAssertEqual(requestedDisplayID, "bound-display")
    }

    func testNilBindingTargetsFrontWindowOnSelectedDisplay() async {
        var settings = RecordingSettings()
        settings.selectedDisplayID = "selected-display"
        settings.screenSourceBinding = nil
        var requestedDisplayID: String?

        let processID = await AppContentZoomTargetResolver.processID(
            settings: settings,
            pickedWindowProcessID: { 111 },
            applicationProcessID: { _ in 222 },
            windowProcessID: { _ in 333 },
            frontWindowProcessID: { displayID in
                requestedDisplayID = displayID
                return 444
            }
        )

        XCTAssertEqual(processID, 444)
        XCTAssertEqual(requestedDisplayID, "selected-display")
    }

    private func applicationBinding(processID: pid_t) -> ScreenSourceBinding {
        ScreenSourceBinding(
            kind: .application,
            displayID: nil,
            bundleIdentifier: "com.example.App",
            applicationName: "Example App",
            processID: processID,
            windowID: nil,
            windowTitle: nil
        )
    }

    private func windowBinding() -> ScreenSourceBinding {
        ScreenSourceBinding(
            kind: .window,
            displayID: nil,
            bundleIdentifier: "com.example.App",
            applicationName: "Example App",
            processID: nil,
            windowID: 42,
            windowTitle: "Main"
        )
    }
}
