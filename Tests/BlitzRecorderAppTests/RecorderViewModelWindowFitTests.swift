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

    func testScreenSizeSliderPreservesCanvasLayerWithoutAccessibility() {
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
            equals: settings.sceneLayout.screenFrame
        )
        XCTAssertEqual(viewModel.previewStage.sceneLayout.screenFrame, viewModel.settings.sceneLayout.screenFrame)
    }

    func testWindowZoomKeepsSplitFixedAndFitsPhysicalWindowInEveryAspectRatio() {
        for layout in CaptureLayout.allCases {
            let suite = "RecorderWindowZoom.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            var settings = RecordingSettings()
            settings.layout = layout
            settings.selectedScenePreset = nil
            settings.enabledSources = [.screen, .camera]
            settings.sceneLayout = SceneLayout.screenSplitLayout(screenHeight: 0.6)
            settings.screenCrop = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
            settings.screenContentMode = .fill
            settings.screenSourceBinding = .init(kind: .window, displayID: nil,
                bundleIdentifier: "example.zoom-test", applicationName: "Fixture", processID: -1,
                windowID: 0, windowTitle: "Fixture")
            RecordingSettingsStore.save(settings, defaults: defaults)
            let coordinator = RecorderCoordinator(accessController: AccessController(defaults: defaults), defaults: defaults)
            let vm = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
            defer { vm.prepareForWindowClose() }
            let original = vm.settings.sceneLayout
            let display = CGRect(x: 0, y: 0, width: 2560, height: 1440)
            for state in [RecordingState.idle, .recording, .paused] {
                vm.applyState(state)
                for zoom: CGFloat in [0.71, 1.8, 0.5, 2, 1] {
                    vm.setTargetWindowZoom(zoom)
                    XCTAssertEqual(vm.settings.sceneLayout, original, "\(layout), \(state), \(zoom)")
                    XCTAssertEqual(vm.previewStage.sceneLayout, original)
                    XCTAssertEqual(vm.targetWindowZoom, zoom, accuracy: 0.0001)
                    XCTAssertNil(vm.settings.screenCrop)
                    XCTAssertEqual(vm.settings.screenContentMode, .fit)
                    let actual = TargetWindowFitting.plan(screenFrame: display, visibleFrame: display,
                        captureLayout: layout, sceneLayout: vm.settings.sceneLayout,
                        enabledSources: vm.settings.visibleSources, zoom: vm.targetWindowZoom)
                    let expected = TargetWindowFitting.plan(screenFrame: display, visibleFrame: display,
                        captureLayout: layout, sceneLayout: original,
                        enabledSources: vm.settings.visibleSources, zoom: zoom)
                    XCTAssertEqual(actual.windowFrame, expected.windowFrame)
                    XCTAssertEqual(actual.windowFrame.width / actual.windowFrame.height,
                        actual.unscaledWindowFrame.width / actual.unscaledWindowFrame.height, accuracy: 0.001)
                }
            }
            vm.applyState(.finishing)
            vm.setTargetWindowZoom(1.7)
            XCTAssertEqual(vm.targetWindowZoom, 1)
            XCTAssertEqual(vm.settings.sceneLayout, original)
        }
    }

    func testDisplayCaptureCannotSchedulePhysicalWindowZoom() {
        let suite = "RecorderDisplayZoom.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = RecordingSettings()
        settings.screenSourceBinding = .display(id: "1")
        RecordingSettingsStore.save(settings, defaults: defaults)
        let coordinator = RecorderCoordinator(accessController: AccessController(defaults: defaults), defaults: defaults)
        let vm = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
        let original = vm.settings
        vm.setTargetWindowZoom(2)
        XCTAssertEqual(vm.settings.sceneLayout, original.sceneLayout)
        XCTAssertEqual(vm.settings.screenCrop, original.screenCrop)
        XCTAssertEqual(vm.settings.screenContentMode, original.screenContentMode)
        XCTAssertEqual(vm.targetWindowZoom, 2)
        XCTAssertEqual(RecordingSettingsStore.load(defaults: defaults).screenWindowZoom, 2)
        XCTAssertFalse(vm.hasScheduledTargetWindowFit)
    }

    func testPendingWindowFitIsDiscardedWhenSceneGeometryChanges() async throws {
        let suite = "RecorderStaleZoom.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = RecordingSettings()
        settings.screenSourceBinding = .init(kind: .window, displayID: nil,
            bundleIdentifier: "example.zoom-test", applicationName: "Fixture", processID: -1,
            windowID: 0, windowTitle: "Fixture")
        RecordingSettingsStore.save(settings, defaults: defaults)
        let coordinator = RecorderCoordinator(accessController: AccessController(defaults: defaults), defaults: defaults)
        let vm = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
        defer { vm.prepareForWindowClose() }
        vm.setTargetWindowZoom(0.7)
        let scheduledContext = vm.pendingTargetWindowFitContext
        for zoom: CGFloat in [0.8, 0.9, 1.1] { vm.setTargetWindowZoom(zoom) }
        XCTAssertEqual(vm.pendingTargetWindowFitContext, scheduledContext)
        coordinator.settings.sceneLayout.screenFrame.size.height = 0.45
        vm.syncSettings()
        for _ in 0..<40 where vm.hasScheduledTargetWindowFit || vm.pendingTargetWindowFitContext != nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertFalse(vm.hasScheduledTargetWindowFit)
        XCTAssertNil(vm.pendingTargetWindowFitContext)
        XCTAssertEqual(vm.targetWindowZoom, 1.1, accuracy: 0.0001)
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
