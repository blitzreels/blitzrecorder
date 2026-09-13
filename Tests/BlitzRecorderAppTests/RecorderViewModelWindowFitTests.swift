import XCTest
@testable import BlitzRecorderApp

@MainActor
final class RecorderViewModelWindowFitTests: XCTestCase {
    func testWindowCloseCancelsPendingUiScaleResize() {
        let suiteName = "RecorderViewModelWindowFitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var settings = RecordingSettings()
        settings.enabledSources = [.screen]
        settings.screenSourceBinding = ScreenSourceBinding(
            kind: .window,
            displayID: nil,
            bundleIdentifier: "com.google.Chrome",
            applicationName: "Google Chrome",
            processID: nil,
            windowID: 1,
            windowTitle: "Example"
        )
        RecordingSettingsStore.save(settings, defaults: defaults)

        let viewModel = RecorderViewModel(
            coordinator: RecorderCoordinator(
                accessController: AccessController(defaults: defaults),
                defaults: defaults
            ),
            previewStage: PreviewStageView()
        )

        viewModel.setTargetWindowZoom(1.5)
        XCTAssertTrue(viewModel.hasScheduledTargetWindowFit)

        viewModel.prepareForWindowClose()

        XCTAssertFalse(viewModel.hasScheduledTargetWindowFit)
    }

    func testUiScaleSupportsTwoXAndSchedulesPhysicalWindowResize() {
        let suiteName = "RecorderViewModelWindowFitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var settings = RecordingSettings()
        settings.enabledSources = [.screen]
        settings.screenSourceBinding = ScreenSourceBinding(
            kind: .application,
            displayID: nil,
            bundleIdentifier: "com.google.Chrome",
            applicationName: "Google Chrome",
            processID: nil,
            windowID: nil,
            windowTitle: nil
        )
        RecordingSettingsStore.save(settings, defaults: defaults)

        let viewModel = RecorderViewModel(
            coordinator: RecorderCoordinator(
                accessController: AccessController(defaults: defaults),
                defaults: defaults
            ),
            previewStage: PreviewStageView()
        )

        viewModel.setTargetWindowZoom(2)

        XCTAssertEqual(viewModel.targetWindowZoom, 2)
        XCTAssertEqual(
            RecordingSettingsStore.load(defaults: defaults).screenWindowZoom,
            2
        )
        XCTAssertTrue(viewModel.hasScheduledTargetWindowFit)
    }

    func testScreenLayerResizeSchedulesPhysicalAppWindowFit() {
        let suiteName = "RecorderViewModelWindowFitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var settings = RecordingSettings()
        settings.enabledSources = [.screen, .camera]
        settings.screenSourceBinding = ScreenSourceBinding(
            kind: .application,
            displayID: nil,
            bundleIdentifier: "com.hnc.Discord",
            applicationName: "Discord",
            processID: nil,
            windowID: nil,
            windowTitle: nil
        )
        RecordingSettingsStore.save(settings, defaults: defaults)
        let previewStage = PreviewStageView()
        let viewModel = RecorderViewModel(
            coordinator: RecorderCoordinator(
                accessController: AccessController(defaults: defaults),
                defaults: defaults
            ),
            previewStage: previewStage
        )

        previewStage.onLayerResizeEnded?(.screen)

        XCTAssertEqual(viewModel.screenCaptureAreaSelection, .activeWindow)
        XCTAssertTrue(viewModel.hasScheduledTargetWindowFit)
    }

    func testHalfUiScaleSchedulesLargerPhysicalSourceWindow() {
        let suiteName = "RecorderViewModelWindowFitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var settings = RecordingSettings()
        settings.enabledSources = [.screen]
        settings.screenSourceBinding = ScreenSourceBinding(
            kind: .application,
            displayID: nil,
            bundleIdentifier: "com.google.Chrome",
            applicationName: "Google Chrome",
            processID: nil,
            windowID: nil,
            windowTitle: nil
        )
        RecordingSettingsStore.save(settings, defaults: defaults)
        let viewModel = RecorderViewModel(
            coordinator: RecorderCoordinator(
                accessController: AccessController(defaults: defaults),
                defaults: defaults
            ),
            previewStage: PreviewStageView()
        )

        viewModel.setTargetWindowZoom(0.5)

        XCTAssertEqual(viewModel.targetWindowZoom, 0.5, accuracy: 0.0001)
        XCTAssertTrue(viewModel.hasScheduledTargetWindowFit)
    }

    func testScreenSizeSliderScalesCanvasLayerWithoutAccessibility() {
        let suiteName = "RecorderViewModelWindowFitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var settings = RecordingSettings()
        settings.enabledSources = [.screen]
        settings.sceneLayout.screenFrame = CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        settings.screenSourceBinding = ScreenSourceBinding(
            kind: .window,
            displayID: nil,
            bundleIdentifier: "us.zoom.xos",
            applicationName: "zoom.us",
            processID: nil,
            windowID: 42,
            windowTitle: "Zoom Meeting"
        )
        RecordingSettingsStore.save(settings, defaults: defaults)
        let viewModel = RecorderViewModel(
            coordinator: RecorderCoordinator(
                accessController: AccessController(defaults: defaults),
                defaults: defaults
            ),
            previewStage: PreviewStageView()
        )

        viewModel.setTargetWindowZoom(2)

        XCTAssertRect(
            viewModel.settings.sceneLayout.screenFrame,
            equals: CGRect(x: 0, y: 0, width: 0.8, height: 0.8)
        )
        XCTAssertEqual(viewModel.previewStage.sceneLayout.screenFrame, viewModel.settings.sceneLayout.screenFrame)
    }
}

private func XCTAssertRect(
    _ actual: CGRect,
    equals expected: CGRect,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(actual.origin.x, expected.origin.x, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(actual.origin.y, expected.origin.y, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(actual.size.width, expected.size.width, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(actual.size.height, expected.size.height, accuracy: 0.0001, file: file, line: line)
}
