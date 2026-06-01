import Foundation
@testable import BlitzRecorderApp
import XCTest

@MainActor
final class RecorderCoordinatorAccessTests: XCTestCase {
    func testRecordingStartIsBlockedAfterFreeExportsAreUsed() {
        let defaults = temporaryDefaults()
        let access = AccessController(defaults: defaults)
        access.recordSuccessfulExportIfNeeded()
        access.recordSuccessfulExportIfNeeded()
        access.recordSuccessfulExportIfNeeded()

        let coordinator = RecorderCoordinator(accessController: access, defaults: defaults)
        var messages: [String] = []
        coordinator.onMessage = { messages.append($0) }

        coordinator.start()

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertEqual(messages, ["Free exports used. Subscribe for unlimited renders."])
        XCTAssertEqual(access.usedFreeExports, 3)
    }

    func testReadinessDetailsOpenPlanAfterFreeExportsAreUsed() {
        let defaults = temporaryDefaults()
        let access = AccessController(defaults: defaults)
        access.recordSuccessfulExportIfNeeded()
        access.recordSuccessfulExportIfNeeded()
        access.recordSuccessfulExportIfNeeded()

        let coordinator = RecorderCoordinator(accessController: access, defaults: defaults)
        let viewModel = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())

        viewModel.openReadinessDetails()

        XCTAssertEqual(viewModel.appTab, .creator)
    }

    func testViewModelAppliesSavedOutputAfterStopWarning() {
        let defaults = temporaryDefaults()
        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults),
            defaults: defaults
        )
        let viewModel = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
        let outputURL = temporaryDirectory().appendingPathComponent("final-video.mp4")
        let sourceTakeURL = temporaryDirectory().appendingPathComponent("source-take", isDirectory: true)

        viewModel.applySavedRecordingOutput(
            SavedRecordingOutput(
                url: outputURL,
                sourceDirectory: sourceTakeURL,
                warning: "Some sources stopped with errors: System Audio: Capture stream stopped: display went away"
            )
        )

        XCTAssertEqual(viewModel.lastExportedURL, outputURL)
        XCTAssertEqual(viewModel.lastExportedSourceTakeURL?.path, sourceTakeURL.path)
        XCTAssertEqual(
            viewModel.lastExportWarning,
            "Some sources stopped with errors: System Audio: Capture stream stopped: display went away"
        )
        XCTAssertNil(viewModel.idleStatusMessage)
    }

    func testViewModelAppliesRecoveryOutputAndClearsSavedOutput() {
        let defaults = temporaryDefaults()
        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults),
            defaults: defaults
        )
        let viewModel = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
        let outputURL = temporaryDirectory().appendingPathComponent("final-video.mp4")
        let recoveryURL = temporaryDirectory().appendingPathComponent("source-take", isDirectory: true)

        viewModel.applySavedRecordingOutput(
            SavedRecordingOutput(url: outputURL, sourceDirectory: nil, warning: nil)
        )
        viewModel.applyRecoveryOutput(
            RecordingRecoveryOutput(
                takeDirectory: recoveryURL,
                reason: "Export failed: no video track",
                canRetryExport: true
            )
        )

        XCTAssertNil(viewModel.lastExportedURL)
        XCTAssertNil(viewModel.lastExportedSourceTakeURL)
        XCTAssertNil(viewModel.lastExportWarning)
        XCTAssertEqual(viewModel.lastRecoveryOutput?.takeDirectory.path, recoveryURL.path)
        XCTAssertEqual(viewModel.lastRecoveryOutput?.reason, "Export failed: no video track")
        XCTAssertEqual(viewModel.lastRecoveryOutput?.canRetryExport, true)
    }

    func testStartingStateClearsPostRecordingStatus() {
        let defaults = temporaryDefaults()
        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults),
            defaults: defaults
        )
        let viewModel = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())

        viewModel.applySavedRecordingOutput(
            SavedRecordingOutput(
                url: temporaryDirectory().appendingPathComponent("final-video.mp4"),
                sourceDirectory: nil,
                warning: "Warning"
            )
        )
        viewModel.applyRecoveryOutput(
            RecordingRecoveryOutput(
                takeDirectory: temporaryDirectory(),
                reason: "Export failed",
                canRetryExport: true
            )
        )

        viewModel.applyState(.starting)

        XCTAssertNil(viewModel.lastExportedURL)
        XCTAssertNil(viewModel.lastExportedSourceTakeURL)
        XCTAssertNil(viewModel.lastExportWarning)
        XCTAssertNil(viewModel.lastRecoveryOutput)
    }

    func testStartingStateTellsUserRecordingHasNotStarted() {
        let defaults = temporaryDefaults()
        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults),
            defaults: defaults
        )
        let viewModel = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())

        viewModel.applyState(.starting)

        XCTAssertEqual(viewModel.sessionProgressTitle, "Getting Ready")
        XCTAssertEqual(
            viewModel.sessionProgressDetail,
            "Not recording yet. Hang on while BlitzRecorder prepares capture."
        )
        XCTAssertEqual(viewModel.elapsedSeconds, 0)
    }

    func testScreenFullscreenPresetDoesNotFitTargetWindowAutomatically() {
        let defaults = temporaryDefaults()
        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults),
            defaults: defaults
        )
        var messages: [String] = []
        coordinator.onMessage = { messages.append($0) }
        let viewModel = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())

        viewModel.setScenePreset(.screenFullscreen)

        XCTAssertTrue(viewModel.settings.enabledSources.contains(.screen))
        XCTAssertTrue(viewModel.settings.enabledSources.contains(.camera))
        XCTAssertTrue(viewModel.settings.hiddenSources.contains(.camera))
        XCTAssertNil(viewModel.settings.screenCrop)
        XCTAssertTrue(messages.isEmpty)
    }

    func testPreviewLayerSelectionSelectsMatchingSource() {
        let defaults = temporaryDefaults()
        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults),
            defaults: defaults
        )
        let previewStage = PreviewStageView()
        let viewModel = RecorderViewModel(coordinator: coordinator, previewStage: previewStage)

        viewModel.selectSource(.screen)
        previewStage.onLayerSelected?(.camera)

        XCTAssertEqual(viewModel.selectedLayer, .camera)
        XCTAssertEqual(viewModel.selectedSource, .camera)
        XCTAssertEqual(previewStage.selectedLayer, .camera)
    }

    func testRecordingStartIsBlockedBeforeStartingWhenSourcesAreNotReady() {
        let defaults = temporaryDefaults()
        let access = AccessController(defaults: defaults)
        let coordinator = RecorderCoordinator(accessController: access, defaults: defaults)
        var messages: [String] = []
        coordinator.onMessage = { messages.append($0) }

        for source in CaptureSource.allCases {
            coordinator.removeSource(source)
        }

        coordinator.start()

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertEqual(messages, ["Start failed: Select at least one source before recording."])
    }

    private func temporaryDefaults() -> UserDefaults {
        let suiteName = "dev.blitzreels.blitzrecorder.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlitzRecorderTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}
