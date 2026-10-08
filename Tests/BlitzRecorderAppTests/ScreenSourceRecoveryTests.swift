import AppKit
import ScreenCaptureKit
import XCTest
@testable import BlitzRecorderApp

@MainActor
final class ScreenSourceRecoveryTests: XCTestCase {
    func testTransientMissingSourceRecoversWithoutWarning() {
        var tracker = ScreenSourceAvailabilityTracker()
        let binding = ScreenSourceBinding.display(id: "1")
        let now = Date()
        XCTAssertNil(tracker.unavailableSource(.init(binding: binding, isPresent: false, now: now)))
        XCTAssertNil(tracker.unavailableSource(.init(binding: binding, isPresent: true,
                                                    now: now.addingTimeInterval(1))))
        XCTAssertNil(tracker.unavailableSource(.init(binding: binding, isPresent: false,
                                                    now: now.addingTimeInterval(3))))
    }

    func testPersistentLossShowsWarningAndReappearanceClearsIt() {
        var tracker = ScreenSourceAvailabilityTracker()
        let binding = ScreenSourceBinding.display(id: "1")
        let now = Date()
        XCTAssertNil(tracker.unavailableSource(.init(binding: binding, isPresent: false, now: now)))
        XCTAssertNil(tracker.unavailableSource(.init(binding: binding, isPresent: false,
                                                    now: now.addingTimeInterval(1))))
        XCTAssertEqual(tracker.unavailableSource(.init(binding: binding, isPresent: false,
                                                      now: now.addingTimeInterval(2))), binding)
        XCTAssertNil(tracker.unavailableSource(.init(binding: binding, isPresent: true,
                                                    now: now.addingTimeInterval(3))))
    }

    func testNewSelectionDoesNotInheritMissingSourceTimer() {
        var tracker = ScreenSourceAvailabilityTracker()
        let now = Date()
        _ = tracker.unavailableSource(.init(binding: .display(id: "1"), isPresent: false, now: now))
        XCTAssertNil(tracker.unavailableSource(.init(binding: .display(id: "2"), isPresent: false,
                                                    now: now.addingTimeInterval(4))))
    }

    func testLookupRetriesTemporaryWindowLoss() async throws {
        var attempts = 0
        let result = try await ScreenSourceLookup.resolve {
            attempts += 1
            if attempts < 3 { throw RecorderError.screenSourceUnavailable("Chrome") }
            return "Chrome"
        }
        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(result, "Chrome")
    }

    func testLookupStopsAfterPersistentWindowLoss() async {
        var attempts = 0
        do {
            let _: String = try await ScreenSourceLookup.resolve {
                attempts += 1
                throw RecorderError.screenSourceUnavailable("Chrome")
            }
            XCTFail("Expected the missing-source error")
        } catch RecorderError.screenSourceUnavailable {
            XCTAssertEqual(attempts, 3)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLookupDoesNotRetryPermissionFailure() async {
        var attempts = 0
        do {
            let _: String = try await ScreenSourceLookup.resolve {
                attempts += 1
                throw RecorderError.screenCapturePermissionRequired
            }
            XCTFail("Expected the permission error")
        } catch RecorderError.screenCapturePermissionRequired {
            XCTAssertEqual(attempts, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCancelledLookupDoesNotStartAnotherAttempt() async {
        let task = Task { () throws -> String in
            try await ScreenSourceLookup.resolve {
                withUnsafeCurrentTask { $0?.cancel() }
                throw RecorderError.screenSourceUnavailable("Chrome")
            }
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testOneMissingWindowPollDoesNotShowUnavailable() throws {
        let suite = "ScreenSourceRecoveryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = RecorderCoordinator(accessController: AccessController(defaults: defaults), defaults: defaults)
        let vm = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
        defer { vm.prepareForWindowClose() }
        vm.settings.enabledSources = [.screen]
        vm.settings.screenSourceBinding = .init(kind: .window, displayID: nil,
            bundleIdentifier: "example.missing", applicationName: "Missing", processID: -1,
            windowID: UInt32.max, windowTitle: "Window")
        vm.refreshScreenSourceAvailability()
        XCTAssertNil(vm.unavailableScreenSource)
    }

    func testLiveChromePreviewPreservesApplicationSelection() async throws {
        guard ProcessInfo.processInfo.environment["BLITZRECORDER_TEST_SCREEN_RECOVERY"] == "1" else {
            throw XCTSkip("Enable the live Chrome screen recovery test explicitly.")
        }
        guard CGPreflightScreenCaptureAccess() else { throw XCTSkip("Screen Recording access is required.") }
        let content = try await SCShareableContent.current
        let chrome = try XCTUnwrap(content.applications.first { $0.bundleIdentifier == "com.google.Chrome" })
        let suite = "ScreenSourceRecoveryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let studio = RecorderStudioConfiguration(defaults: defaults)
        let runtime = RecorderCaptureRuntime(studio: studio, permissionGate: PermissionGate(),
                                             recents: .init(defaults: defaults))
        let binding = ScreenSourceBinding(kind: .application, displayID: nil,
            bundleIdentifier: chrome.bundleIdentifier, applicationName: chrome.applicationName,
            processID: chrome.processID, windowID: nil, windowTitle: nil)
        studio.settings.screenSourceBinding = binding
        studio.settings.enabledSources = [.screen]
        studio.settings.hiddenSources = []
        studio.settings.usesPickedScreenContent = false
        studio.persist()
        runtime.idleCaptureResourcesEnabled = true
        try await runtime.startScreenPreview { _ in }
        await runtime.stopScreenPreview()
        XCTAssertEqual(studio.settings.screenSourceBinding, binding)
        XCTAssertEqual(RecordingSettingsStore.load(defaults: defaults).screenSourceBinding, binding)
    }
}
