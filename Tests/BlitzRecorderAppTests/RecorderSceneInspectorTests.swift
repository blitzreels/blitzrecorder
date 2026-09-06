import XCTest
@testable import BlitzRecorderApp

@MainActor
final class RecorderSceneInspectorTests: XCTestCase {
    func testSplitDividerPreviewsBothRegionsAndCommitsOnlyOnRelease() {
        let setup = makeFixture(customizedSplitSettings())
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }
        let originalLayout = setup.coordinator.settings.sceneLayout
        var captureChanges = 0
        setup.coordinator.onScreenCaptureConfigurationChanged = { captureChanges += 1 }

        setup.viewModel.previewScreenSplitHeight(0.6)
        setup.viewModel.previewScreenSplitHeight(0.65)
        setup.viewModel.syncSettings()

        XCTAssertEqual(setup.coordinator.settings.sceneLayout, originalLayout)
        XCTAssertEqual(captureChanges, 0)
        XCTAssertEqual(setup.viewModel.screenSplitHeight, 0.65, accuracy: 0.001)
        XCTAssertEqual(setup.viewModel.previewStage.sceneLayout.cameraFrame.height, 0.35, accuracy: 0.001)
        XCTAssertEqual(setup.viewModel.previewStage.sceneLayout.screenFrame.minY, 0.35, accuracy: 0.001)

        setup.viewModel.commitScreenSplitPreview()

        XCTAssertNil(setup.viewModel.screenSplitPreviewHeight)
        XCTAssertEqual(captureChanges, 1)
        XCTAssertEqual(setup.coordinator.settings.sceneLayout.screenSplitHeight ?? 0, 0.65, accuracy: 0.001)
        XCTAssertEqual(RecordingSettingsStore.load(defaults: setup.defaults).sceneLayout,
                       setup.coordinator.settings.sceneLayout)
    }

    func testCancellingPendingSplitPreservesRecordingSettings() {
        let setup = makeFixture(customizedSplitSettings())
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }
        let original = setup.coordinator.settings
        setup.viewModel.previewScreenSplitHeight(0.7)

        setup.viewModel.cancelScreenSplitPreview()
        setup.viewModel.commitScreenSplitPreview()

        XCTAssertNil(setup.viewModel.screenSplitPreviewHeight)
        XCTAssertEqual(setup.coordinator.settings.sceneLayout, original.sceneLayout)
        XCTAssertEqual(setup.coordinator.settings.outputResolution, original.outputResolution)
        XCTAssertEqual(setup.coordinator.settings.framesPerSecond, original.framesPerSecond)
        XCTAssertEqual(setup.coordinator.settings.screenWindowZoom, original.screenWindowZoom)
        XCTAssertEqual(setup.coordinator.settings.screenSourceBinding, original.screenSourceBinding)
        XCTAssertEqual(setup.viewModel.previewStage.sceneLayout, original.sceneLayout)
    }

    func testSwitchingScenesCancelsPendingDividerDrag() throws {
        let setup = makeFixture(customizedSplitSettings())
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }
        let originalID = try XCTUnwrap(setup.viewModel.selectedSceneID)
        let otherID = try XCTUnwrap(setup.viewModel.currentScenes.first { $0.id != originalID }?.id)
        let originalLayout = setup.coordinator.settings.sceneLayout
        setup.viewModel.previewScreenSplitHeight(0.7)
        setup.viewModel.selectScene(otherID)
        setup.viewModel.commitScreenSplitPreview()
        setup.viewModel.selectScene(originalID)

        XCTAssertNil(setup.viewModel.screenSplitPreviewHeight)
        XCTAssertEqual(setup.coordinator.settings.sceneLayout, originalLayout)
    }

    func testSplitDividerDragDirectionSnappingAndLimits() {
        XCTAssertEqual(ScreenSplitDividerGeometry.height(.init(
            startHeight: 0.6, translation: 50, canvasHeight: 500
        )), 0.7, accuracy: 0.001)
        XCTAssertEqual(ScreenSplitDividerGeometry.height(.init(
            startHeight: 0.6, translation: -48, canvasHeight: 500
        )), 0.5, accuracy: 0.001)
        XCTAssertEqual(ScreenSplitDividerGeometry.height(.init(
            startHeight: 0.6, translation: 32, canvasHeight: 500
        )), 2.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(ScreenSplitDividerGeometry.height(.init(
            startHeight: 0.6, translation: 1000, canvasHeight: 500
        )), Double(SceneLayout.maximumScreenSplitHeight))
        XCTAssertEqual(ScreenSplitDividerGeometry.height(.init(
            startHeight: 0.6, translation: -1000, canvasHeight: 500
        )), Double(SceneLayout.minimumScreenSplitHeight))
    }

    func testSelectingCustomizedSplitExposesItsHeightWithoutReapplyingPreset() throws {
        let setup = makeFixture(customizedSplitSettings())
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }
        let originalID = try XCTUnwrap(setup.viewModel.selectedSceneID)
        let otherID = try XCTUnwrap(setup.viewModel.currentScenes.first { $0.id != originalID }?.id)
        let layout = setup.coordinator.settings.sceneLayout
        setup.viewModel.selectSource(.screen)

        setup.viewModel.selectScene(otherID)
        setup.viewModel.selectScene(originalID)

        XCTAssertEqual(setup.viewModel.inspectorSelection, .source(.screen))
        XCTAssertTrue(setup.viewModel.showsScreenSplitControl)
        XCTAssertTrue(setup.viewModel.isScenePresetActive(.screenTop50))
        XCTAssertEqual(setup.viewModel.screenSplitHeight, 0.57, accuracy: 0.0001)
        XCTAssertEqual(setup.coordinator.settings.sceneLayout, layout)

        let reopened = RecorderViewModel(
            coordinator: RecorderCoordinator(
                accessController: AccessController(defaults: setup.defaults), defaults: setup.defaults
            ),
            previewStage: PreviewStageView()
        )
        XCTAssertTrue(reopened.showsScreenSplitControl)
        XCTAssertEqual(reopened.screenSplitHeight, 0.57, accuracy: 0.0001)
        XCTAssertEqual(reopened.settings.sceneLayout, layout)
    }

    func testSplitControlsRequireBothVisibleVideoSourcesAndVerticalCanvas() {
        let setup = makeFixture(customizedSplitSettings())
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }
        setup.viewModel.settings.selectedScenePreset = .screenTop50
        for source in [CaptureSource.screen, .camera] {
            setup.viewModel.settings.hiddenSources = [source]
            XCTAssertFalse(setup.viewModel.showsScreenSplitControl)
        }
        setup.viewModel.settings.hiddenSources = []
        setup.viewModel.settings.layout = .horizontal
        XCTAssertFalse(setup.viewModel.showsScreenSplitControl)
    }

    func testInsetAndOverlappingLayoutsDoNotAcquireSplitControls() {
        var settings = customizedSplitSettings()
        settings.sceneLayout = SceneLayout.presetLayout(.cameraInset, for: .vertical)
        let setup = makeFixture(settings)
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }
        XCTAssertFalse(setup.viewModel.showsScreenSplitControl)

        setup.viewModel.settings.sceneLayout.cameraFrame = CGRect(x: 0, y: 0, width: 1, height: 0.43)
        setup.viewModel.settings.sceneLayout.screenFrame = CGRect(x: 0, y: 0, width: 1, height: 0.6)
        XCTAssertFalse(setup.viewModel.showsScreenSplitControl)
    }

    func testSceneChangesKeepTheSelectedSourceAndCanvasContext() throws {
        let setup = makeFixture(customizedSplitSettings())
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }
        let sceneIDs = setup.viewModel.currentScenes.map(\.id)

        for source in [CaptureSource.screen, .camera] {
            setup.viewModel.selectSource(source)
            for sceneID in sceneIDs {
                setup.viewModel.selectScene(sceneID)
                XCTAssertEqual(setup.viewModel.inspectorSelection, .source(source))
            }
            setup.viewModel.duplicateSelectedScene()
            XCTAssertEqual(setup.viewModel.inspectorSelection, .source(source))
        }

        setup.viewModel.selectBackgroundLayer()
        setup.viewModel.selectScene(try XCTUnwrap(sceneIDs.first))
        XCTAssertTrue(setup.viewModel.isBackgroundLayerSelected)
    }

    func testProjectsKeepSelectionSearchAndDetailTabWhenReturningFromRecorder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var settings = customizedSplitSettings()
        settings.outputDirectory = directory
        settings.savesSourceFiles = true
        let setup = makeFixture(settings)
        defer {
            setup.defaults.removePersistentDomain(forName: setup.suite)
            try? FileManager.default.removeItem(at: directory)
        }
        _ = try TakeFileStore().createTake(settings: settings)
        _ = try TakeFileStore().createTake(settings: settings)
        setup.viewModel.showProjects()
        let selectedID = try XCTUnwrap(setup.viewModel.recentProjects.last?.id)
        let navigation = ProjectLibraryNavigationState(
            selectedProjectIDs: [selectedID], selectedDetailTab: .media, searchText: "Recording"
        )
        setup.viewModel.projectLibraryNavigation = navigation

        setup.viewModel.showRecorder()
        setup.viewModel.showProjects()
        setup.viewModel.projectLibraryNavigation.reconcileSelection(
            availableProjectIDs: setup.viewModel.recentProjects.map(\.id)
        )

        XCTAssertEqual(setup.viewModel.projectLibraryNavigation, navigation)
    }

    func testProjectNavigationRecoversWhenSelectedProjectsDisappear() {
        let firstID = UUID()
        let secondID = UUID()
        var navigation = ProjectLibraryNavigationState(
            selectedProjectIDs: [firstID, secondID], selectedDetailTab: .media, searchText: "demo"
        )

        navigation.reconcileSelection(availableProjectIDs: [secondID])
        XCTAssertEqual(navigation.selectedProjectIDs, [secondID])
        XCTAssertEqual(navigation.selectedDetailTab, .overview)
        XCTAssertEqual(navigation.searchText, "demo")

        navigation.selectedDetailTab = .transcript
        navigation.reconcileSelection(availableProjectIDs: [secondID, firstID])
        XCTAssertEqual(navigation.selectedDetailTab, .transcript)

        navigation.reconcileSelection(availableProjectIDs: [firstID])
        XCTAssertEqual(navigation.selectedProjectIDs, [firstID])
        navigation.reconcileSelection(availableProjectIDs: [])
        XCTAssertTrue(navigation.selectedProjectIDs.isEmpty)
    }

    private func customizedSplitSettings() -> RecordingSettings {
        var settings = RecordingSettings()
        settings.layout = .vertical
        settings.enabledSources = [.screen, .camera]
        settings.selectedScenePreset = nil
        settings.sceneLayout.screenFrame = CGRect(x: 0.15, y: 0.5, width: 0.7, height: 0.44)
        settings.sceneLayout.cameraFrame = CGRect(x: 0, y: 0, width: 1, height: 0.43)
        return settings
    }

    private struct Fixture {
        let suite: String
        let defaults: UserDefaults
        let coordinator: RecorderCoordinator
        let viewModel: RecorderViewModel
    }

    private func makeFixture(_ settings: RecordingSettings) -> Fixture {
        let suite = "RecorderSceneInspectorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        RecordingSettingsStore.save(settings, defaults: defaults)
        let coordinator = RecorderCoordinator(accessController: AccessController(defaults: defaults), defaults: defaults)
        return Fixture(
            suite: suite,
            defaults: defaults,
            coordinator: coordinator,
            viewModel: RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
        )
    }
}
