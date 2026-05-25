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
}
