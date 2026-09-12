import XCTest
@testable import BlitzRecorderApp

final class AppUpdateControllerTests: XCTestCase {
    func testAcceptsSignedHTTPSFeedConfiguration() {
        XCTAssertTrue(AppUpdateController.hasSparkleConfiguration(
            feedURLString: "https://blitzrecorder.com/appcast.xml",
            publicKey: "public-key"
        ))
    }

    func testRejectsMissingOrInsecureFeedConfiguration() {
        XCTAssertFalse(AppUpdateController.hasSparkleConfiguration(
            feedURLString: "http://blitzrecorder.com/appcast.xml",
            publicKey: "public-key"
        ))
        XCTAssertFalse(AppUpdateController.hasSparkleConfiguration(
            feedURLString: "https://blitzrecorder.com/appcast.xml",
            publicKey: "   "
        ))
    }
}

@MainActor
final class AppUpdateWorkflowTests: XCTestCase {
    func testStartupChecksImmediatelyAndStartsOnlyOnce() {
        let driver = UpdateDriverStub()
        let controller = AppUpdateController(driver: driver)
        controller.start()
        controller.start()
        XCTAssertEqual(driver.startCount, 1)
        XCTAssertEqual(driver.backgroundCheckCount, 1)
        XCTAssertEqual(controller.status, .checking)
        XCTAssertTrue(controller.isConfigured)
    }

    func testStartupRespectsAutomaticCheckingPreference() {
        let driver = UpdateDriverStub()
        driver.automaticallyChecksForUpdates = false
        let controller = AppUpdateController(driver: driver)
        controller.start()
        XCTAssertEqual(driver.backgroundCheckCount, 0)
        XCTAssertFalse(controller.automaticChecksEnabled)
        controller.setAutomaticChecksEnabled(true)
        XCTAssertTrue(driver.automaticallyChecksForUpdates)
        XCTAssertTrue(controller.automaticChecksEnabled)
    }

    func testFirstManualCheckStartsUpdaterWithoutCompetingBackgroundCheck() {
        let driver = UpdateDriverStub()
        let controller = AppUpdateController(driver: driver)
        controller.checkForUpdates(nil)
        XCTAssertEqual(driver.startCount, 1)
        XCTAssertEqual(driver.manualCheckCount, 1)
        XCTAssertEqual(driver.backgroundCheckCount, 0)
    }

    func testManualCheckDuringStartupWaitsForReadinessWithoutAnotherClick() {
        let driver = UpdateDriverStub()
        driver.canCheckForUpdates = false
        let controller = AppUpdateController(driver: driver)
        controller.start()
        controller.checkForUpdates(nil)
        controller.checkForUpdates(nil)
        XCTAssertTrue(controller.hasPendingManualCheck)
        XCTAssertFalse(controller.canCheckForUpdates)
        XCTAssertEqual(driver.manualCheckCount, 0)
        driver.canCheckForUpdates = true
        XCTAssertEqual(driver.manualCheckCount, 1)
        XCTAssertFalse(controller.hasPendingManualCheck)
        driver.onReadinessChange?()
        XCTAssertEqual(driver.manualCheckCount, 1)
    }

    func testManualCheckCanFocusAnAlreadyCheckingUpdaterWhenSparkleIsReady() {
        let driver = UpdateDriverStub()
        let controller = AppUpdateController(driver: driver)
        controller.start()
        XCTAssertTrue(controller.canCheckForUpdates)
        controller.checkForUpdates(nil)
        XCTAssertEqual(driver.manualCheckCount, 1)
    }

    func testDownloadedUpdateKeepsRestartActionUntilRequested() {
        let driver = UpdateDriverStub()
        let controller = AppUpdateController(driver: driver)
        var installCount = 0
        controller.prepareInstallation(.init(version: "1.2.3", install: { installCount += 1 }))
        controller.finishUpdateCycle(error: nil)
        XCTAssertEqual(controller.status, .readyToInstall("1.2.3"))
        XCTAssertEqual(controller.actionTitle, "Restart and Update")
        XCTAssertEqual(installCount, 0)
        controller.checkForUpdates(nil)
        XCTAssertEqual(installCount, 1)
        XCTAssertEqual(driver.manualCheckCount, 0)
    }

    func testRecordingBlocksRestartAndKeepsUpdateAvailable() {
        let controller = AppUpdateController(driver: UpdateDriverStub())
        var installCount = 0
        controller.prepareInstallation(.init(version: "1.2.3", install: { installCount += 1 }))
        controller.installationBlockedReason = "Finish recording before restarting."
        controller.checkForUpdates(nil)
        XCTAssertEqual(installCount, 0)
        XCTAssertFalse(controller.canCheckForUpdates)
        XCTAssertEqual(controller.detail, "Finish recording before restarting.")
        controller.installationBlockedReason = nil
        controller.checkForUpdates(nil)
        XCTAssertEqual(installCount, 1)
    }

    func testStartupFailureCanBeRetriedFromFirstManualCheck() {
        let driver = UpdateDriverStub()
        driver.startError = NSError(domain: "UpdaterTests", code: 1)
        let controller = AppUpdateController(driver: driver)
        controller.start()
        XCTAssertFalse(controller.isConfigured)
        if case .failed = controller.status {} else { XCTFail("Expected visible startup error") }
        driver.startError = nil
        controller.checkForUpdates(nil)
        XCTAssertEqual(driver.startCount, 2)
        XCTAssertEqual(driver.manualCheckCount, 1)
    }

    func testFailureClearsStaleInstallHandlerAndAllowsRetry() {
        let driver = UpdateDriverStub()
        let controller = AppUpdateController(driver: driver)
        var installCount = 0
        controller.prepareInstallation(.init(version: "1.2.3", install: { installCount += 1 }))
        controller.finishUpdateCycle(error: NSError(domain: "UpdaterTests", code: 2))
        XCTAssertNil(controller.updateVersion)
        controller.checkForUpdates(nil)
        XCTAssertEqual(installCount, 0)
        XCTAssertEqual(driver.manualCheckCount, 1)
    }
}

@MainActor
private final class UpdateDriverStub: AppUpdateDriving {
    var canCheckForUpdates = true { didSet { onReadinessChange?() } }
    var automaticallyChecksForUpdates = true
    var onReadinessChange: (() -> Void)?
    var startError: (any Error)?
    private(set) var startCount = 0
    private(set) var manualCheckCount = 0
    private(set) var backgroundCheckCount = 0

    func start() throws {
        startCount += 1
        if let startError { throw startError }
    }

    func checkForUpdates() { manualCheckCount += 1 }
    func checkForUpdatesInBackground() { backgroundCheckCount += 1 }
}
