import BlitzRecorderCore
import CoreGraphics
import Foundation
@testable import BlitzRecorderApp
import XCTest

final class CaptureValueClampsTests: XCTestCase {
    func testPersistedScreenCropDropsFullDisplay() throws {
        XCTAssertNil(CaptureValueClamps.persistedScreenCrop(CGRect(x: 0, y: 0, width: 1, height: 1)))
        let persisted = try XCTUnwrap(
            CaptureValueClamps.persistedScreenCrop(CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.4))
        )
        XCTAssertEqual(persisted.minX, 0.1, accuracy: 0.0001)
        XCTAssertEqual(persisted.minY, 0.2, accuracy: 0.0001)
        XCTAssertEqual(persisted.width, 0.5, accuracy: 0.0001)
        XCTAssertEqual(persisted.height, 0.4, accuracy: 0.0001)
        XCTAssertEqual(CaptureValueClamps.gain(3), 2, accuracy: 0.0001)
        XCTAssertEqual(CaptureValueClamps.canvasPadding(-1), 0, accuracy: 0.0001)
        XCTAssertEqual(CaptureValueClamps.canvasPadding(1), 0.16, accuracy: 0.0001)
    }
}

final class SceneLayerFitTests: XCTestCase {
    func testScreenFillUsesCameraSlotWhenCameraSpansWidth() {
        var layout = SceneLayout()
        layout.cameraFrame = CGRect(x: 0, y: 0, width: 1, height: 0.35)
        layout.screenFrame = CGRect(x: 0.1, y: 0.4, width: 0.8, height: 0.5)
        let request = SceneLayerFit.Request(
            kind: .screen,
            layout: layout,
            visibleSources: [.screen, .camera],
            removesCameraBackgroundAfterRecording: false,
            sourceAspectRatio: 16.0 / 9.0,
            canvasAspectRatio: 9.0 / 16.0,
            scale: 1
        )
        XCTAssertTrue(SceneLayerFit.constrainsScreenFillToCameraSlot(
            layout: layout,
            visibleSources: [.screen, .camera],
            removesCameraBackgroundAfterRecording: false
        ))
        let fitted = SceneLayerFit.frame(request)
        let slot = SceneSlotGeometry.screenSlot(in: layout, enabledSources: [.screen, .camera])
        XCTAssertEqual(fitted.minX, slot.minX, accuracy: 0.0001)
        XCTAssertEqual(fitted.minY, slot.minY, accuracy: 0.0001)
        XCTAssertEqual(fitted.width, slot.width, accuracy: 0.0001)
        XCTAssertEqual(fitted.height, slot.height, accuracy: 0.0001)
    }

    func testCameraFillUsesCanvasFillingFrame() {
        let layout = SceneLayout()
        let request = SceneLayerFit.Request(
            kind: .camera,
            layout: layout,
            visibleSources: [.camera],
            removesCameraBackgroundAfterRecording: false,
            sourceAspectRatio: 16.0 / 9.0,
            canvasAspectRatio: 9.0 / 16.0,
            scale: 1
        )
        XCTAssertEqual(
            SceneLayerFit.frame(request),
            SceneLayout.canvasFillingFrame(sourceAspectRatio: 16.0 / 9.0, canvasAspectRatio: 9.0 / 16.0)
        )
    }
}

final class RecordingStartCopyTests: XCTestCase {
    func testBlockedAndPrerollCopy() {
        XCTAssertEqual(
            RecordingStartCopy.blockedMessage(enabledSourcesEmpty: true),
            "Start failed: Select at least one source before recording."
        )
        XCTAssertEqual(
            RecordingStartCopy.blockedMessage(enabledSourcesEmpty: false),
            "Start failed: Selected sources are not ready."
        )
        XCTAssertEqual(
            RecordingStartCopy.prerollMessage(remaining: 1),
            "Loading scene. Recording starts in 1 second..."
        )
        XCTAssertEqual(
            RecordingStartCopy.prerollMessage(remaining: 2),
            "Loading scene. Recording starts in 2 seconds..."
        )
        XCTAssertEqual(
            RecordingStartCopy.recording(skippedSystemAudio: true, usesLiveCompositor: true),
            "Recording - Mac audio off (needs Screen Recording)"
        )
        XCTAssertEqual(
            RecordingStartCopy.recording(skippedSystemAudio: false, usesLiveCompositor: true),
            "Recording with live compositor..."
        )
        XCTAssertEqual(
            RecordingStartCopy.recording(skippedSystemAudio: false, usesLiveCompositor: false),
            "Recording..."
        )
        XCTAssertEqual(RecordingStartCopy.preparing, "Not recording yet. Hang on while BlitzRecorder prepares capture.")
        XCTAssertEqual(RecordingStartCopy.stopping, "Stopping recording...")
        XCTAssertEqual(RecordingStartCopy.saving, "Saving recording...")
    }
}

final class CaptureDeviceCatalogTests: XCTestCase {
    func testMicrophoneFallbackName() {
        XCTAssertFalse(CaptureDeviceCatalog.microphoneName(selectedID: nil).isEmpty)
    }
}

final class RecordingStartSettingsTests: XCTestCase {
    func testDropsSystemAudioWithoutScreenCaptureAccess() {
        var settings = RecordingSettings()
        settings.enabledSources = [.microphone, .systemAudio]
        settings.savesSourceFiles = false
        let effective = RecordingStartSettings.effective(settings, hasScreenCaptureAccess: false)
        XCTAssertFalse(effective.enabledSources.contains(.systemAudio))
        XCTAssertTrue(effective.savesSourceFiles)
        XCTAssertTrue(effective.enabledSources.contains(.microphone))
        let kept = RecordingStartSettings.effective(settings, hasScreenCaptureAccess: true)
        XCTAssertTrue(kept.enabledSources.contains(.systemAudio))
    }
}

final class SceneSplitPolicyTests: XCTestCase {
    func testInferredHeightRequiresFullWidthCameraOnTop() {
        var layout = SceneLayout()
        layout.cameraFrame = CGRect(x: 0, y: 0, width: 1, height: 0.45)
        layout.screenFrame = CGRect(x: 0, y: 0.45, width: 1, height: 0.55)
        XCTAssertEqual(SceneSplitPolicy.inferredHeight(from: layout) ?? 0, 0.55, accuracy: 0.0001)
        XCTAssertTrue(SceneSplitPolicy.showsControl(
            captureLayout: .vertical,
            visibleSources: [.screen, .camera],
            sceneLayout: layout,
            selectedPreset: nil
        ))
        XCTAssertFalse(SceneSplitPolicy.showsControl(
            captureLayout: .horizontal,
            visibleSources: [.screen, .camera],
            sceneLayout: layout,
            selectedPreset: .screenTop50
        ))
    }
}

final class EditorSourceZoomTests: XCTestCase {
    func testClampedAmountAndLabel() {
        XCTAssertEqual(EditorSourceZoom.clamped(-1), 0, accuracy: 0.0001)
        XCTAssertEqual(EditorSourceZoom.clamped(1), 0.75, accuracy: 0.0001)
        XCTAssertEqual(EditorSourceZoom.amount(0.5), CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(EditorSourceZoom.value(draft: 0.2, amount: CGPoint(x: 0.4, y: 0.4)), 0.2, accuracy: 0.0001)
        XCTAssertEqual(EditorSourceZoom.label(0), "100%")
    }
}

final class EditorExportRecipeTests: XCTestCase {
    func testRecipeComputesOnceForMultipleLayouts() {
        let recipe = EditorExportRecipe.make(.init(
            preset: .balanced,
            sourceResolution: .p1080,
            sourceFramesPerSecond: 60,
            customResolution: .p720,
            customFramesPerSecond: 30,
            customVideoQuality: .web,
            layout: .horizontal,
            layoutCount: 2,
            audioBitrate: 192_000,
            duration: 10
        ))
        XCTAssertEqual(recipe.profile.resolution, .p1080)
        XCTAssertTrue(recipe.summary.contains("2 videos"))
        XCTAssertFalse(recipe.estimatedSize.isEmpty)
    }

    func testRecipeIncludesSpeedAndShrinksEstimate() {
        let normal = EditorExportRecipe.make(.init(
            preset: .balanced,
            sourceResolution: .p1080,
            sourceFramesPerSecond: 30,
            customResolution: .p1080,
            customFramesPerSecond: 30,
            customVideoQuality: .web,
            layout: .horizontal,
            layoutCount: 1,
            audioBitrate: 192_000,
            duration: 10,
            playbackRate: 1
        ))
        let faster = EditorExportRecipe.make(.init(
            preset: .balanced,
            sourceResolution: .p1080,
            sourceFramesPerSecond: 30,
            customResolution: .p1080,
            customFramesPerSecond: 30,
            customVideoQuality: .web,
            layout: .horizontal,
            layoutCount: 1,
            audioBitrate: 192_000,
            duration: 10,
            playbackRate: 2
        ))
        XCTAssertFalse(normal.summary.contains("2.0×"))
        XCTAssertTrue(faster.summary.contains("2.0×"))
        XCTAssertNotEqual(normal.estimatedSize, faster.estimatedSize)
    }
}

final class ProjectExportRenderPlanTests: XCTestCase {
    func testHidesVideoSourcesAndMutesAudio() {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen, .camera, .microphone, .systemAudio]
        settings.microphoneGain = 1
        settings.systemAudioGain = 1
        let hidden = ProjectExportRenderPlan.hiddenCaptureSources([.camera])
        XCTAssertEqual(hidden, [.camera])
        let renderSettings = ProjectExportRenderPlan.settings(
            exportSettings: settings,
            profile: ExportPerformanceProfile.resolved(
                preset: .balanced,
                sourceResolution: .p1080,
                sourceFramesPerSecond: 30,
                customResolution: .p1080,
                customFramesPerSecond: 30,
                customVideoQuality: .high
            ),
            outputLayout: .vertical,
            mutedAudioSources: [.microphone],
            hiddenCaptureSources: hidden
        )
        XCTAssertEqual(renderSettings.layout, .vertical)
        XCTAssertFalse(renderSettings.enabledSources.contains(.camera))
        XCTAssertEqual(renderSettings.microphoneGain, 0, accuracy: 0.0001)
        XCTAssertEqual(renderSettings.systemAudioGain, 1, accuracy: 0.0001)
    }
}

final class RecorderStudioLabelsTests: XCTestCase {
    func testCameraFallsBackToDefault() {
        XCTAssertEqual(
            RecorderStudioLabels.camera(.init(
                isRemoteSelected: false,
                remoteName: nil,
                selectedCameraID: nil,
                localOptions: []
            )),
            "Default camera"
        )
        XCTAssertEqual(
            RecorderStudioLabels.camera(.init(
                isRemoteSelected: true,
                remoteName: nil,
                selectedCameraID: nil,
                localOptions: []
            )),
            "Remote iPhone"
        )
    }
}

final class RecordingStartGateTests: XCTestCase {
    func testSkippedSystemAudioAndScreenPermissionGate() {
        XCTAssertTrue(RecordingStartGate.skippedSystemAudio(
            requested: [.microphone, .systemAudio],
            effective: [.microphone]
        ))
        XCTAssertFalse(RecordingStartGate.skippedSystemAudio(
            requested: [.microphone, .systemAudio],
            effective: [.microphone, .systemAudio]
        ))
        var settings = RecordingSettings()
        settings.enabledSources = [.screen]
        settings.usesPickedScreenContent = false
        XCTAssertTrue(RecordingStartGate.requiresScreenCapturePermission(settings))
        XCTAssertThrowsError(try RecordingStartGate.requireScreenCaptureAccess(settings, hasAccess: false))
        XCTAssertNoThrow(try RecordingStartGate.requireScreenCaptureAccess(settings, hasAccess: true))
        settings.usesPickedScreenContent = true
        XCTAssertNoThrow(try RecordingStartGate.requireScreenCaptureAccess(settings, hasAccess: false))
    }

    func testWarningJoinAndStopCopy() {
        XCTAssertEqual(RecordingWarning.combined(["Keep going", nil, "", "Mic dropped"]), "Keep going Mic dropped")
        XCTAssertEqual(RecordingWarning.combined(["Keep going", "Mic dropped"], separator: ". "), "Keep going. Mic dropped")
        XCTAssertNil(RecordingWarning.combined([nil, ""]))
        XCTAssertEqual(RecordingStopCopy.noFrames, "Recording failed: No video frames captured.")
        XCTAssertEqual(RecordingStopCopy.recovery("No video frames captured"), "Recording needs recovery: No video frames captured")
        XCTAssertEqual(
            PermissionStatusRows.actionTitle(blockers: [
                PermissionBlocker(
                    source: .camera,
                    permission: "Camera",
                    status: "denied",
                    recovery: "Grant camera access."
                )
            ]),
            "Request Access"
        )
        XCTAssertEqual(
            PermissionStatusRows.actionTitle(blockers: [
                PermissionBlocker(
                    source: .screen,
                    permission: "Screen Recording",
                    status: "denied",
                    recovery: "Open Settings."
                )
            ]),
            "Open Settings"
        )
        XCTAssertEqual(PermissionStatusRows.actionTitle(blockers: []), "Check Access")
        XCTAssertEqual(RemoteCameraRotationPolicy.supportedDegrees(capabilities: nil), [0, 90, 180, 270])
        XCTAssertEqual(RemoteCameraRotationPolicy.degrees(telemetry: nil), RemoteCameraSettings.defaultRotationDegrees)
        XCTAssertTrue(RemoteCameraRotationPolicy.usesAutomaticRotation(telemetry: nil))
    }

    func testRetainedTakeAndDisabledCaptureDeviceIDs() {
        var emptySources = RecordingSettings()
        emptySources.enabledSources = []
        XCTAssertNil(ActiveCaptureDeviceIDs.microphone(settings: emptySources))
        XCTAssertNil(ActiveCaptureDeviceIDs.localCamera(settings: emptySources))
        var settings = RecordingSettings()
        settings.selectedCameraID = RemoteCameraProviderID.make(for: "iphone")
        settings.enabledSources = [.camera]
        XCTAssertNil(ActiveCaptureDeviceIDs.localCamera(settings: settings))
        XCTAssertNil(TakeFinalizationOutcome.saved(URL(fileURLWithPath: "/tmp/final.mov"), sourceDirectory: nil).retainedTake)
    }

    func testStopPresentationAndPickerActivation() throws {
        XCTAssertEqual(
            RecordingStopPresentation.liveComposited(
                wroteMedia: false,
                finalURL: nil,
                take: nil,
                warning: nil
            ),
            .noFrames
        )
        var settings = RecordingSettings()
        settings.enabledSources = [.camera]
        settings.hiddenSources = [.screen]
        settings.screenCrop = CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
        settings.screenContentMode = .fill
        let enabled = PickScreenContentRequest.enablingScreen(settings, activatesScreenSource: true)
        XCTAssertTrue(enabled.enabledSources.contains(.screen))
        XCTAssertFalse(enabled.hiddenSources.contains(.screen))
        XCTAssertNil(enabled.screenCrop)
        let finished = PickScreenContentRequest.finishing(
            enabled,
            pickedAspectRatio: 16.0 / 9.0,
            activatesScreenSource: true,
            isIdle: true
        )
        XCTAssertEqual(finished.screenSourceAspectRatio ?? 0, 16.0 / 9.0, accuracy: 0.0001)
        XCTAssertEqual(finished.screenContentMode, .fit)
        XCTAssertEqual(
            PickScreenContentRequest.applied(
                to: settings,
                activatesScreenSource: true,
                pickedAspectRatio: 16.0 / 9.0,
                isIdle: true
            ) { $0 }.screenContentMode,
            .fit
        )
        XCTAssertEqual(
            PermissionPrimaryAction.resolve(blockers: [
                PermissionBlocker(
                    source: .camera,
                    permission: "Camera",
                    status: "denied",
                    recovery: "Grant camera access."
                )
            ]),
            .requestAccess
        )
        XCTAssertEqual(
            RecorderStudioLabels.screenSourceActivationMessage(
                usesPickedScreenContent: true,
                hasPersistentBinding: true
            ),
            "Screen source saved. Using picker grant for this session."
        )
        var screenSettings = RecordingSettings()
        screenSettings.enabledSources = [.screen]
        XCTAssertTrue(RecordingStartGate.screenNeedsPicking(settings: screenSettings, hasActiveSelection: false))
        XCTAssertFalse(RecordingStartGate.screenNeedsPicking(settings: screenSettings, hasActiveSelection: true))
        XCTAssertEqual(
            RecorderStudioEditPolicy.idleStatus(
                state: .idle,
                lastExportedURL: nil,
                detailMessage: "Mic dropped"
            ),
            "Mic dropped"
        )
        XCTAssertNil(
            RecorderStudioEditPolicy.idleStatus(
                state: .idle,
                lastExportedURL: nil,
                detailMessage: "Saved: take.mov"
            )
        )
        XCTAssertFalse(
            ScreenSourceCatalog.canUseAppOnlyCapture(
                current: .display(id: "1"),
                lastApplication: nil,
                available: []
            )
        )
        XCTAssertEqual(
            RemoteCameraPreviewGeometry.displayAspectRatio(width: 1920, height: 1080, rotationDegrees: 0),
            9.0 / 16.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            RecordingStopCopy.screenSwitched("Safari"),
            "Screen switched to Safari. Recording continues."
        )
        let permission = RecordingReadiness(
            isReady: true,
            title: "Ready",
            detail: "ok",
            blockers: [],
            statusLine: "ok"
        )
        var pickerSettings = RecordingSettings()
        pickerSettings.enabledSources = [.screen]
        let gated = RecordingStartGate.readiness(
            permission: permission,
            settings: pickerSettings,
            hasActiveScreenSourceSelection: false,
            remoteBlocker: nil
        )
        XCTAssertFalse(gated.isReady)
        XCTAssertEqual(gated.blockers.first?.permission, "Screen source")
        XCTAssertEqual(
            PermissionStatusRows.setupSummary(readiness: permission, enabledSourcesEmpty: false),
            "All selected sources are ready."
        )
        var presetSettings = RecordingSettings()
        presetSettings.enabledSources = [.screen]
        presetSettings.screenCrop = CGRect(x: 0, y: 0, width: 1, height: 1)
        let mutated = RecordingSceneMutation.applyingPreset(
            .webcamFullscreen,
            to: presetSettings,
            screenAspectRatio: 16.0 / 9.0,
            cameraAspectRatio: 9.0 / 16.0
        )
        XCTAssertTrue(mutated.hiddenSources.contains(.screen))
        XCTAssertFalse(mutated.hiddenSources.contains(.camera))
        XCTAssertNil(mutated.screenCrop)
        let restored = EditorExportRecipe.restored(
            snapshot: RecordingProject.ExportRecipeSnapshot(
                preset: ExportPerformancePreset.balanced.rawValue,
                format: OutputVideoFormat.mov.rawValue,
                resolution: OutputResolution.p1080.rawValue,
                framesPerSecond: 30,
                quality: ExportVideoQuality.high.rawValue
            )
        )
        XCTAssertEqual(restored?.preset, .balanced)
        XCTAssertEqual(restored?.framesPerSecond, 30)
        XCTAssertEqual(restored?.playbackRate, .normal)
        let decoded = try JSONDecoder().decode(
            RecordingProject.ExportRecipeSnapshot.self,
            from: Data(#"{"preset":"Balanced","format":"MOV","resolution":"1080p","framesPerSecond":30,"quality":"High"}"#.utf8)
        )
        XCTAssertEqual(decoded.playbackRate, 1, accuracy: 0.0001)
        XCTAssertNil(EditorExportRecipe.restored(snapshot: nil))
        XCTAssertEqual(
            CaptureDeviceEvent.connected(hasAudio: true, hasVideo: true, isIdle: false),
            .init(refreshAudio: false, notifyCamera: false)
        )
        XCTAssertEqual(
            CaptureDeviceEvent.connected(hasAudio: true, hasVideo: true, isIdle: true),
            .init(refreshAudio: true, notifyCamera: true)
        )
        XCTAssertEqual(
            RecordingStartFailure.cleanup(
                createdTake: true,
                remoteStartCommandSent: true,
                hasRemoteTakeID: true
            ),
            .init(removePendingImport: false, abandonRemoteTake: true, cleanupTakeFiles: false)
        )
        XCTAssertEqual(
            RecordingStartFailure.cleanup(
                createdTake: true,
                remoteStartCommandSent: false,
                hasRemoteTakeID: true
            ),
            .init(removePendingImport: true, abandonRemoteTake: true, cleanupTakeFiles: true)
        )
    }

    func testSceneSnapshotApplyAndExportPreset() {
        var sceneSettings = RecordingSettings()
        sceneSettings.enabledSources = [.screen, .microphone]
        sceneSettings.cameraFramePadding = 12
        sceneSettings.selectedCameraID = "old"
        var snapshot = RecordingSceneSnapshot(settings: sceneSettings)
        snapshot.enabledVideoSources = [.camera]
        snapshot.selectedCameraID = "cam-2"
        snapshot.canvasBackgroundAnimated = true
        snapshot.canvasBackgroundStyle = .black
        let applied = snapshot.applying(to: sceneSettings)
        XCTAssertTrue(applied.enabledSources.contains(.microphone))
        XCTAssertTrue(applied.enabledSources.contains(.camera))
        XCTAssertFalse(applied.enabledSources.contains(.screen))
        XCTAssertEqual(applied.selectedCameraID, "cam-2")
        XCTAssertEqual(applied.cameraFramePadding, 0)
        XCTAssertFalse(applied.canvasBackgroundAnimated)
        XCTAssertFalse(snapshot.restoresConcreteScreenSource)
        snapshot.usesPickedScreenContent = true
        XCTAssertTrue(snapshot.restoresConcreteScreenSource)

        let appliedPreset = EditorExportRecipe.applyingPreset(
            .balanced,
            sourceResolution: .p1080,
            sourceFramesPerSecond: 30,
            customResolution: .p720,
            customFramesPerSecond: 24,
            customQuality: .high,
            currentFormat: .mov
        )
        XCTAssertEqual(appliedPreset.preset, .balanced)
        XCTAssertEqual(appliedPreset.format, .mov)
        XCTAssertEqual(ExportVideoQuality.high.resolvedOutputFormat(.mp4), .mp4)
        XCTAssertEqual(ExportVideoQuality.proRes.resolvedOutputFormat(.mp4), .mov)
    }

    func testStartWindowFitPresetRetargetAndPreviewFrame() {
        XCTAssertEqual(
            ScreenWindowFit.RecordingStartPlan.make(
                visibleScreen: false,
                hasAccessibility: true,
                usesPickedScreenContent: true,
                pickedKind: .window,
                binding: nil
            ),
            .skip
        )
        XCTAssertEqual(
            ScreenWindowFit.RecordingStartPlan.make(
                visibleScreen: true,
                hasAccessibility: true,
                usesPickedScreenContent: true,
                pickedKind: .window,
                binding: nil
            ),
            .picked
        )
        XCTAssertEqual(
            ScreenWindowFit.RecordingStartPlan.make(
                visibleScreen: true,
                hasAccessibility: true,
                usesPickedScreenContent: true,
                pickedKind: .display,
                binding: nil
            ),
            .skip
        )
        let window = ScreenSourceBinding(
            kind: .window,
            displayID: "1",
            bundleIdentifier: "com.example.App",
            applicationName: "Example",
            processID: 42,
            windowID: 7,
            windowTitle: "Example"
        )
        XCTAssertEqual(
            ScreenWindowFit.RecordingStartPlan.make(
                visibleScreen: true,
                hasAccessibility: true,
                usesPickedScreenContent: false,
                pickedKind: nil,
                binding: window
            ),
            .binding(window)
        )
        XCTAssertEqual(
            ScreenWindowFit.RecordingStartPlan.make(
                visibleScreen: true,
                hasAccessibility: true,
                usesPickedScreenContent: false,
                pickedKind: nil,
                binding: .display(id: "1")
            ),
            .skip
        )
        XCTAssertTrue(PickScreenContentRequest.updatesActiveCapture(.recording))
        XCTAssertTrue(PickScreenContentRequest.updatesActiveCapture(.paused))
        XCTAssertFalse(PickScreenContentRequest.updatesActiveCapture(.idle))
        XCTAssertEqual(
            RecordingSceneMutation.presetActivation(
                .webcamFullscreen,
                isScreenConfigured: false,
                hasActiveScreenSourceSelection: false
            ),
            .pickScreenThenApply
        )
        XCTAssertEqual(
            RecordingSceneMutation.presetActivation(
                .webcamFullscreen,
                isScreenConfigured: true,
                hasActiveScreenSourceSelection: false
            ),
            .apply
        )
        XCTAssertEqual(
            RecordingSceneMutation.screenSourceActivation(
                isScreenConfigured: false,
                hasActiveScreenSourceSelection: false
            ),
            .pickScreenThenApply
        )
        XCTAssertEqual(
            RecordingSceneMutation.screenSourceActivation(
                isScreenConfigured: false,
                hasActiveScreenSourceSelection: true
            ),
            .apply
        )
        XCTAssertTrue(
            CaptureSourceRetargetFailure.shouldStopTake(for: CaptureSourceRetargetFailure(
                rollbackFailed: true,
                underlyingError: NSError(domain: "test", code: 1)
            ))
        )
        XCTAssertFalse(
            CaptureSourceRetargetFailure.shouldStopTake(for: CaptureSourceRetargetFailure(
                rollbackFailed: false,
                underlyingError: NSError(domain: "test", code: 1)
            ))
        )
        XCTAssertFalse(CaptureSourceRetargetFailure.shouldStopTake(for: NSError(domain: "test", code: 2)))
        XCTAssertEqual(
            RecordingStopCopy.screenCaptureUpdateStoppedTake,
            "Screen capture update failed. Recording stopped to protect the take."
        )
        let frame = RemoteCameraPreviewFrame(width: 1920, height: 1080, rotationDegrees: 0)
        XCTAssertEqual(frame.width, 1920)
        XCTAssertEqual(frame.aspectRatio, 9.0 / 16.0, accuracy: 0.0001)
        XCTAssertEqual(ProjectExportFilename.variantSuffix(for: .square), "square")
        XCTAssertEqual(ProjectExportFilename.variantSuffix(for: .vertical), "vertical")
        XCTAssertEqual(ProjectExportFilename.variantSuffix(for: .horizontal), "landscape")
        XCTAssertFalse(RecordingStopPresentation.shouldCleanupTakeFiles(.noFrames))
        XCTAssertTrue(
            RecordingStopPresentation.shouldCleanupTakeFiles(.saved(SavedRecordingOutput(
                url: URL(fileURLWithPath: "/tmp/export.mov"),
                sourceDirectory: nil,
                warning: nil
            )))
        )

        var landscape = RecordingSettings()
        landscape.layout = .horizontal
        landscape.screenCrop = CGRect(x: 0.1, y: 0.1, width: 0.4, height: 0.8)
        XCTAssertNotNil(RecordingSceneMutation.clearingIncompatibleScreenCrop(landscape))
        landscape.screenCrop = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.4)
        XCTAssertNil(RecordingSceneMutation.clearingIncompatibleScreenCrop(landscape))
        landscape.layout = .vertical
        landscape.screenCrop = CGRect(x: 0.1, y: 0.1, width: 0.4, height: 0.8)
        XCTAssertNil(RecordingSceneMutation.clearingIncompatibleScreenCrop(landscape))

        let verticalDefaults = RecordingSceneMutation.defaultsForLayout(
            .vertical,
            screenAspectRatio: 16.0 / 9.0,
            cameraAspectRatio: 9.0 / 16.0
        )
        XCTAssertEqual(verticalDefaults.preset, ScenePreset.defaultPreset(for: .vertical))
        XCTAssertEqual(
            verticalDefaults.layout,
            SceneLayout.defaultLayout(
                for: .vertical,
                screenAspectRatio: 16.0 / 9.0,
                cameraAspectRatio: 9.0 / 16.0
            )
        )
        XCTAssertEqual(EditorSessionMetrics.timelineDuration(playbackDuration: 12, lastEventTime: 3), 12)
        XCTAssertEqual(EditorSessionMetrics.timelineDuration(playbackDuration: 0, lastEventTime: 4), 5)
        XCTAssertEqual(EditorSessionMetrics.timelineDuration(playbackDuration: 0, lastEventTime: 0), 0)
        XCTAssertEqual(
            EditorSessionMetrics.canvasAspectRatio(renderSize: CGSize(width: 1920, height: 1080), layout: .vertical),
            16.0 / 9.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            EditorSessionMetrics.canvasAspectRatio(renderSize: .zero, layout: .vertical),
            9.0 / 16.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(EditorSessionMetrics.ratioLabel(nil), "—")
        XCTAssertEqual(EditorSessionMetrics.ratioLabel(.horizontal), CaptureLayout.horizontal.shortLabel)

        XCTAssertEqual(
            PreviewStageDrawing.maskPath(for: CGRect(x: 0, y: 0, width: 10, height: 10), radius: 0),
            CGPath(rect: CGRect(x: 0, y: 0, width: 10, height: 10), transform: nil)
        )
        let fullscreenRadius = PreviewStageDrawing.maskCornerRadius(
            visibleRect: CGRect(x: 0, y: 0, width: 200, height: 200),
            isCamera: true,
            isFullscreen: true,
            isFullWidth: false
        )
        XCTAssertEqual(fullscreenRadius, 0)
        let cameraShape = PreviewStageDrawing.sourceShape(
            isCamera: true,
            bounds: CGRect(x: 0, y: 0, width: 200, height: 200),
            isFullscreen: true,
            isFullWidth: false
        )
        XCTAssertEqual(cameraShape.cornerRadius, 0)
        XCTAssertEqual(cameraShape.borderWidth, 0)
    }
}

@MainActor
final class RecorderStudioConfigurationTests: XCTestCase {
    func testIdleMicrophoneAndLayoutCropClearPersist() {
        let suiteName = "studio.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let studio = RecorderStudioConfiguration(defaults: defaults)
        studio.applyIdleMicrophone(id: "mic-1")
        XCTAssertEqual(studio.settings.selectedMicrophoneID, "mic-1")
        XCTAssertEqual(RecordingSettingsStore.load(defaults: defaults).selectedMicrophoneID, "mic-1")

        studio.settings.layout = .vertical
        studio.settings.screenCrop = CGRect(x: 0.4, y: 0, width: 0.2, height: 16.0 / 45.0)
        studio.setLayout(.horizontal)
        XCTAssertEqual(studio.settings.layout, .horizontal)
        XCTAssertNil(studio.settings.screenCrop)
    }

    func testScreenReconfigurationGenerations() {
        let reconfiguration = ActiveScreenCaptureReconfiguration()
        XCTAssertEqual(reconfiguration.nextConfigurationGeneration(), 1)
        XCTAssertNil(reconfiguration.queuePickerConfigurationIfNeeded())
        reconfiguration.pickerTransactionTask = Task {}
        XCTAssertEqual(reconfiguration.queuePickerConfigurationIfNeeded(), 1)
        XCTAssertTrue(reconfiguration.shouldApply(generation: 1, state: .recording))
        reconfiguration.cancelConfiguration()
        XCTAssertFalse(reconfiguration.shouldApply(generation: 1, state: .recording))
    }
}
