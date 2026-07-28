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
}
