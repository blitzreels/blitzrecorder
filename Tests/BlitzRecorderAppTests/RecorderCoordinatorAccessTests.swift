import Foundation
import BlitzRecorderCore
@testable import BlitzRecorderApp
import XCTest

@MainActor
final class RecorderCoordinatorAccessTests: XCTestCase {
    func testRecordingStartIsNotBlockedByLegacyExportCount() {
        let defaults = temporaryDefaults()
        let access = AccessController(defaults: defaults)
        for _ in 0..<ProductConfiguration.freeExportLimit {
            access.recordSuccessfulExportIfNeeded()
        }

        XCTAssertTrue(access.canRenderExport)
        XCTAssertEqual(access.usedFreeExports, 0)
    }

    func testReadinessDetailsOpenPermissionsWhenAccessIsFree() {
        let defaults = temporaryDefaults()
        let access = AccessController(defaults: defaults)
        for _ in 0..<ProductConfiguration.freeExportLimit {
            access.recordSuccessfulExportIfNeeded()
        }

        let coordinator = RecorderCoordinator(accessController: access, defaults: defaults)
        let viewModel = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
        var presentedPane: SettingsPane?
        viewModel.onPresentSettings = { presentedPane = $0 }

        viewModel.openReadinessDetails()

        XCTAssertEqual(presentedPane, .permissions)
    }

    func testPickedScreenCanRecordWhenSystemAudioPermissionIsInactive() {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen, .systemAudio]
        settings.usesPickedScreenContent = true

        let blockers = PermissionGate.blockers(for: settings)

        XCTAssertFalse(blockers.contains { $0.source == .systemAudio })
    }

    func testDisplayAutoIsNotConcreteScreenSelection() {
        XCTAssertFalse(ScreenSourceBinding.display(id: nil).isConcreteSelection)
        XCTAssertTrue(ScreenSourceBinding.display(id: "display-1").isConcreteSelection)
    }

    func testScreenSourceBlockerSummaryDoesNotCallPickerStatePermissionRequired() {
        let blockers = [
            PermissionBlocker(
                source: .screen,
                permission: "Screen source",
                status: "no app or screen picked",
                recovery: "Pick a screen or app to record."
            )
        ]

        XCTAssertEqual(blockers.shortSummary, "Pick a screen or app to record")
        XCTAssertEqual(
            blockers.first?.sentence,
            "Screen blocked by Screen source: no app or screen picked. Pick a screen or app to record."
        )
    }

    func testSelectedScreenSourceBlockerSeparatesSelectionFromPermission() {
        let blocker = PermissionBlocker(
            source: .screen,
            permission: "Screen & System Audio Recording",
            status: "source selected; full-capture access inactive",
            recovery: "Use Pick Screen for picker-based capture."
        )

        XCTAssertEqual(
            blocker.sentence,
            "Screen source selected; full-capture access is inactive. Use Pick Screen for picker-based capture."
        )
    }

    func testSystemAudioBlockerDoesNotBlameScreenSourceSelection() {
        let blocker = PermissionBlocker(
            source: .systemAudio,
            permission: "Screen & System Audio Recording",
            status: "Mac audio capture needs Screen Recording access",
            recovery: "Enable Screen Recording, or turn System Audio off."
        )

        XCTAssertEqual(
            blocker.sentence,
            "System Audio needs Screen Recording access. Enable Screen Recording, or turn System Audio off."
        )
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

    func testViewModelOpensEditorForSavedOutputWithProject() throws {
        let defaults = temporaryDefaults()
        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults),
            defaults: defaults
        )
        let viewModel = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.savesSourceFiles = true
        let take = try TakeFileStore().createTake(settings: settings)
        let outputURL = take.scratchDirectory.appendingPathComponent("final.mov")

        viewModel.applySavedRecordingOutput(
            SavedRecordingOutput(url: outputURL, sourceDirectory: take.scratchDirectory, warning: nil)
        )

        XCTAssertNotNil(viewModel.lastExportedProject)
        guard case .edit = viewModel.studioMode else {
            XCTFail("Expected saved project output to open Edit")
            return
        }
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

    func testAppOnlyCaptureToggleRestoresLastApplicationSource() {
        let defaults = temporaryDefaults()
        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults),
            defaults: defaults
        )
        let viewModel = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
        let appBinding = ScreenSourceBinding(
            kind: .application,
            displayID: "display-1",
            bundleIdentifier: "com.google.Chrome",
            applicationName: "Google Chrome",
            processID: 123,
            windowID: nil,
            windowTitle: nil
        )

        viewModel.setScreenSource(appBinding)
        XCTAssertEqual(viewModel.settings.screenSourceBinding, appBinding)
        XCTAssertTrue(viewModel.canUseAppOnlyCapture)

        viewModel.setAppOnlyCapture(false)
        XCTAssertEqual(viewModel.settings.screenSourceBinding?.kind, .display)
        XCTAssertEqual(viewModel.settings.screenSourceBinding?.displayID, "display-1")

        viewModel.setAppOnlyCapture(true)
        XCTAssertEqual(viewModel.settings.screenSourceBinding, appBinding)
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

    func testFillingSelectedScreenLayerUsesAvailableSlotWithoutTargetWindow() {
        let defaults = temporaryDefaults()
        var settings = RecordingSettings()
        settings.layout = .vertical
        settings.enabledSources = [.screen, .camera]
        settings.sceneLayout.screenFrame = CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        RecordingSettingsStore.save(settings, defaults: defaults)

        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults),
            defaults: defaults
        )
        var messages: [String] = []
        coordinator.onMessage = { messages.append($0) }
        let viewModel = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())

        viewModel.selectSource(.screen)
        viewModel.fitSelectedLayer()

        XCTAssertRect(
            viewModel.settings.sceneLayout.screenFrame,
            equals: SceneSlotGeometry.screenSlot(
                in: settings.sceneLayout,
                enabledSources: settings.enabledSources
            )
        )
        XCTAssertTrue(messages.isEmpty)
    }

    func testScreenWindowFitControlsRequireAccessibility() {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen]
        settings.screenSourceBinding = ScreenSourceBinding(
            kind: .window,
            displayID: nil,
            bundleIdentifier: "com.apple.Safari",
            applicationName: "Safari",
            processID: nil,
            windowID: 42,
            windowTitle: "Landing Page"
        )

        XCTAssertFalse(RecorderViewModel.canShowScreenWindowFitControls(
            settings: settings,
            targetWindowInfo: nil,
            hasAccessibilityAccess: false,
            canEditScene: true
        ))
    }

    func testScreenWindowFitControlsShowForWindowBindingWithAccessibility() {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen]
        settings.screenSourceBinding = ScreenSourceBinding(
            kind: .window,
            displayID: nil,
            bundleIdentifier: "com.apple.Safari",
            applicationName: "Safari",
            processID: nil,
            windowID: 42,
            windowTitle: "Landing Page"
        )

        XCTAssertTrue(RecorderViewModel.canShowScreenWindowFitControls(
            settings: settings,
            targetWindowInfo: nil,
            hasAccessibilityAccess: true,
            canEditScene: true
        ))
    }

    func testScreenWindowFitControlsShowForApplicationBindingWithAccessibility() {
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

        XCTAssertTrue(RecorderViewModel.canShowScreenWindowFitControls(
            settings: settings,
            targetWindowInfo: nil,
            hasAccessibilityAccess: true,
            canEditScene: true
        ))
    }

    func testScreenWindowFitControlsShowForPickedScreenContentWithAccessibility() {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen]
        settings.usesPickedScreenContent = true

        XCTAssertTrue(RecorderViewModel.canShowScreenWindowFitControls(
            settings: settings,
            targetWindowInfo: nil,
            hasAccessibilityAccess: true,
            canEditScene: true
        ))
    }

    func testWindowOnlyDoesNotFallbackToAppCaptureWhenNoWindowSourceExists() {
        let defaults = temporaryDefaults()
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
        viewModel.availableScreenSources = [
            ScreenSourceOption(
                binding: .display(id: "display-1"),
                title: "Display 1",
                subtitle: "",
                systemImage: "display",
                icon: nil
            )
        ]

        viewModel.setWindowOnlyCapture()

        XCTAssertEqual(viewModel.settings.screenSourceBinding?.kind, .application)
        XCTAssertEqual(viewModel.settings.screenSourceBinding?.applicationName, "Google Chrome")
        XCTAssertEqual(viewModel.detailMessage, "No window source available for Google Chrome.")
    }

    func testSliderWindowZoomKeepsWindowModeSelected() {
        let defaults = temporaryDefaults()
        var settings = RecordingSettings()
        settings.enabledSources = [.screen]
        settings.screenSourceBinding = .display(id: "display-1")
        RecordingSettingsStore.save(settings, defaults: defaults)
        let viewModel = RecorderViewModel(
            coordinator: RecorderCoordinator(
                accessController: AccessController(defaults: defaults),
                defaults: defaults
            ),
            previewStage: PreviewStageView()
        )

        viewModel.setTargetWindowZoom(1.25)

        XCTAssertEqual(viewModel.screenCaptureAreaSelection, .activeWindow)
        XCTAssertEqual(viewModel.targetWindowZoom, 1.25)
    }

    func testStepWindowZoomKeepsWindowModeSelected() {
        let defaults = temporaryDefaults()
        var settings = RecordingSettings()
        settings.enabledSources = [.screen]
        settings.screenSourceBinding = .display(id: "display-1")
        RecordingSettingsStore.save(settings, defaults: defaults)
        let viewModel = RecorderViewModel(
            coordinator: RecorderCoordinator(
                accessController: AccessController(defaults: defaults),
                defaults: defaults
            ),
            previewStage: PreviewStageView()
        )

        viewModel.zoomTargetWindowFit(by: 0.05)

        XCTAssertEqual(viewModel.screenCaptureAreaSelection, .activeWindow)
        XCTAssertEqual(viewModel.targetWindowZoom, 1.05, accuracy: 0.0001)
    }

    func testResetWindowZoomKeepsWindowModeSelected() {
        let defaults = temporaryDefaults()
        var settings = RecordingSettings()
        settings.enabledSources = [.screen]
        settings.screenSourceBinding = .display(id: "display-1")
        RecordingSettingsStore.save(settings, defaults: defaults)
        let viewModel = RecorderViewModel(
            coordinator: RecorderCoordinator(
                accessController: AccessController(defaults: defaults),
                defaults: defaults
            ),
            previewStage: PreviewStageView()
        )

        viewModel.setTargetWindowZoom(1.25)
        viewModel.resetTargetWindowZoom()

        XCTAssertEqual(viewModel.screenCaptureAreaSelection, .activeWindow)
        XCTAssertEqual(viewModel.targetWindowZoom, 1, accuracy: 0.0001)
    }

    func testAppWindowSelectionPrefersFocusedWindowOverLargerAuxiliaryWindow() {
        let selected = AppWindowSelection.primary(
            from: [
                AppWindowSelectionCandidate(
                    id: 0,
                    frame: CGRect(x: 0, y: 0, width: 500, height: 500),
                    isStandard: true
                ),
                AppWindowSelectionCandidate(
                    id: 1,
                    frame: CGRect(x: 0, y: 0, width: 1200, height: 900),
                    isStandard: true
                )
            ],
            focusedID: 0,
            mainID: 1
        )

        XCTAssertEqual(selected?.id, 0)
    }

    func testAppWindowSelectionFallsBackWhenFocusedWindowIsTooSmall() {
        let selected = AppWindowSelection.primary(
            from: [
                AppWindowSelectionCandidate(
                    id: 0,
                    frame: CGRect(x: 0, y: 0, width: 260, height: 180),
                    isStandard: true
                ),
                AppWindowSelectionCandidate(
                    id: 1,
                    frame: CGRect(x: 0, y: 0, width: 900, height: 700),
                    isStandard: true
                )
            ],
            focusedID: 0,
            mainID: nil
        )

        XCTAssertEqual(selected?.id, 1)
    }

    func testScreenWindowFitControlsHideDisplayWithoutDetectedTargetWindow() {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen]
        settings.screenSourceBinding = .display(id: "display-1")

        XCTAssertFalse(RecorderViewModel.canShowScreenWindowFitControls(
            settings: settings,
            targetWindowInfo: nil,
            hasAccessibilityAccess: true,
            canEditScene: true
        ))
    }

    func testReadableScreenWindowTitleCleansNoisyTitles() {
        XCTAssertEqual(
            RecorderCoordinator.readableScreenWindowTitle("  Project\nSettings\t- BlitzRecorder  "),
            "Project Settings - BlitzRecorder"
        )
        XCTAssertNil(RecorderCoordinator.readableScreenWindowTitle(""))
        XCTAssertNil(RecorderCoordinator.readableScreenWindowTitle("   "))
        XCTAssertNil(RecorderCoordinator.readableScreenWindowTitle("Untitled window"))
    }

    func testReadableScreenApplicationNameDropsBlankAndGenericNames() {
        XCTAssertEqual(
            RecorderCoordinator.readableScreenApplicationName("  Google\nChrome  "),
            "Google Chrome"
        )
        XCTAssertNil(RecorderCoordinator.readableScreenApplicationName(""))
        XCTAssertNil(RecorderCoordinator.readableScreenApplicationName("   "))
        XCTAssertNil(RecorderCoordinator.readableScreenApplicationName("Application"))
    }

    func testIgnoredScreenApplicationFiltersHelpersButKeepsUserApps() {
        XCTAssertTrue(RecorderCoordinator.isIgnoredScreenApplication(
            bundleIdentifier: "com.apple.controlcenter",
            applicationName: "Control Center"
        ))
        XCTAssertTrue(RecorderCoordinator.isIgnoredScreenApplication(
            bundleIdentifier: nil,
            applicationName: "AutoFill (Discord)"
        ))
        XCTAssertTrue(RecorderCoordinator.isIgnoredScreenApplication(
            bundleIdentifier: nil,
            applicationName: ""
        ))
        XCTAssertFalse(RecorderCoordinator.isIgnoredScreenApplication(
            bundleIdentifier: "com.google.Chrome",
            applicationName: "Google Chrome"
        ))
        XCTAssertFalse(RecorderCoordinator.isIgnoredScreenApplication(
            bundleIdentifier: "com.apple.Terminal",
            applicationName: "Terminal"
        ))
        XCTAssertFalse(RecorderCoordinator.isIgnoredScreenApplication(
            bundleIdentifier: "com.hnc.Discord",
            applicationName: "Discord"
        ))
    }

    func testScreenApplicationKeyPrefersBundleThenProcessThenName() {
        XCTAssertEqual(
            RecorderCoordinator.screenApplicationKey(
                bundleIdentifier: "com.google.Chrome",
                processID: 12,
                applicationName: "Google Chrome"
            ),
            "bundle:com.google.Chrome"
        )
        XCTAssertEqual(
            RecorderCoordinator.screenApplicationKey(
                bundleIdentifier: nil,
                processID: 12,
                applicationName: "Google Chrome"
            ),
            "pid:12"
        )
        XCTAssertEqual(
            RecorderCoordinator.screenApplicationKey(
                bundleIdentifier: nil,
                processID: nil,
                applicationName: "Google Chrome"
            ),
            "name:Google Chrome"
        )
    }

    func testIgnoredScreenWindowFiltersSystemChrome() {
        XCTAssertTrue(RecorderCoordinator.isIgnoredScreenWindow(
            bundleIdentifier: "com.apple.controlcenter",
            applicationName: "Control Center",
            title: "Control Center"
        ))
        XCTAssertTrue(RecorderCoordinator.isIgnoredScreenWindow(
            bundleIdentifier: "com.apple.systemuiserver",
            applicationName: "SystemUIServer",
            title: "StatusItem 42"
        ))
        XCTAssertTrue(RecorderCoordinator.isIgnoredScreenWindow(
            bundleIdentifier: nil,
            applicationName: "StatusIndicator",
            title: "StatusIndicator"
        ))
        XCTAssertFalse(RecorderCoordinator.isIgnoredScreenWindow(
            bundleIdentifier: "com.apple.Safari",
            applicationName: "Safari",
            title: "Apple"
        ))
        XCTAssertFalse(RecorderCoordinator.isIgnoredScreenWindow(
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            applicationName: "Slack",
            title: "Launch"
        ))
    }

    func testBeginScreenCropEditingClearsPortraitCropForHorizontalLayout() {
        let defaults = temporaryDefaults()
        var settings = RecordingSettings()
        settings.layout = .horizontal
        settings.enabledSources = [.screen]
        settings.sceneLayout = SceneLayout.presetLayout(.screenFullscreen, for: .horizontal)
        settings.screenCrop = CGRect(x: 0.34, y: 0, width: 0.32, height: 1)
        RecordingSettingsStore.save(settings, defaults: defaults)

        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults),
            defaults: defaults
        )

        coordinator.beginScreenCropEditing()

        XCTAssertNil(coordinator.settings.screenCrop)
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

    func testFreeAccessBlocksPaidOutputControls() {
        let defaults = temporaryDefaults()
        let access = AccessController(defaults: defaults)
        let coordinator = RecorderCoordinator(accessController: access, defaults: defaults)
        var messages: [String] = []
        coordinator.onMessage = { messages.append($0) }

        coordinator.setOutputResolution(.p2160)
        coordinator.setFramesPerSecond(60)

        XCTAssertEqual(coordinator.settings.outputResolution, .p1080)
        XCTAssertEqual(coordinator.settings.framesPerSecond, 30)
        XCTAssertEqual(
            messages,
            [
                "4K export is locked. Get Early Price, then paste your key in Account.",
                "60 fps export is locked. Get Early Price, then paste your key in Account."
            ]
        )
    }

    func testFreeAccessBlocksRemoteCameraSelection() {
        let defaults = temporaryDefaults()
        let access = AccessController(defaults: defaults)
        let coordinator = RecorderCoordinator(accessController: access, defaults: defaults)
        var messages: [String] = []
        coordinator.onMessage = { messages.append($0) }

        coordinator.setCamera(id: RemoteCameraProviderID.make(for: "iphone-15-pro"))

        XCTAssertNil(coordinator.settings.selectedCameraID)
        XCTAssertEqual(messages, ["iPhone camera is locked. Get Early Price, then paste your key in Account."])
    }

    func testFreeAccessBlocksDirectRemoteCameraConnection() {
        let defaults = temporaryDefaults()
        let access = AccessController(defaults: defaults)
        let coordinator = RecorderCoordinator(accessController: access, defaults: defaults)
        var messages: [String] = []
        coordinator.onMessage = { messages.append($0) }

        coordinator.connectDirectRemoteCamera(host: "127.0.0.1", portString: "49152")

        XCTAssertNil(coordinator.settings.selectedCameraID)
        XCTAssertEqual(messages, ["iPhone camera is locked. Get Early Price, then paste your key in Account."])
    }

    func testFreeAccessDowngradesPersistedPaidSettingsOnLaunch() {
        let defaults = temporaryDefaults()
        var settings = RecordingSettings()
        settings.outputResolution = .p2160
        settings.framesPerSecond = 60
        settings.selectedCameraID = RemoteCameraProviderID.make(for: "iphone-15-pro")
        RecordingSettingsStore.save(settings, defaults: defaults)

        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults),
            defaults: defaults
        )

        XCTAssertEqual(coordinator.settings.outputResolution, .p1080)
        XCTAssertEqual(coordinator.settings.framesPerSecond, 30)
        XCTAssertNil(coordinator.settings.selectedCameraID)

        let restoredSettings = RecordingSettingsStore.load(defaults: defaults)
        XCTAssertEqual(restoredSettings.outputResolution, .p1080)
        XCTAssertEqual(restoredSettings.framesPerSecond, 30)
        XCTAssertNil(restoredSettings.selectedCameraID)
    }

    func testSavedLicenseKeyDefersPaidSettingsDowngradeOnLaunch() {
        let defaults = temporaryDefaults()
        var settings = RecordingSettings()
        settings.outputResolution = .p2160
        settings.framesPerSecond = 60
        settings.selectedCameraID = RemoteCameraProviderID.make(for: "iphone-15-pro")
        RecordingSettingsStore.save(settings, defaults: defaults)
        defaults.set("BRL1_saved", forKey: "access.blitzRecorderLicenseKey")

        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults),
            defaults: defaults
        )

        XCTAssertEqual(coordinator.settings.outputResolution, .p2160)
        XCTAssertEqual(coordinator.settings.framesPerSecond, 60)
        XCTAssertEqual(
            RemoteCameraProviderID.serviceID(from: coordinator.settings.selectedCameraID),
            "iphone-15-pro"
        )
    }

    func testActiveLicenseAllowsPaidOutputControls() {
        let defaults = temporaryDefaults()
        let access = AccessController(defaults: defaults)
        access.hasActiveLicense = true
        let coordinator = RecorderCoordinator(accessController: access, defaults: defaults)
        var messages: [String] = []
        coordinator.onMessage = { messages.append($0) }

        coordinator.setOutputResolution(.p2160)
        coordinator.setFramesPerSecond(60)

        XCTAssertEqual(coordinator.settings.outputResolution, .p2160)
        XCTAssertEqual(coordinator.settings.framesPerSecond, 60)
        XCTAssertTrue(messages.isEmpty)
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
}
