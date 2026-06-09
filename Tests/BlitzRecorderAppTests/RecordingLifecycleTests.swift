import AVFoundation
import AudioToolbox
import BlitzRecorderCore
import CoreGraphics
import CoreVideo
import Foundation
import ScreenCaptureKit
import XCTest
@testable import BlitzRecorderApp

final class RecordingLifecycleTests: XCTestCase {
    func testCaptureSourceRunSummaryRequiresVideoMedia() {
        let audioOnly = CaptureSourceRunSummary(completions: [
            .microphone: .wrote(URL(fileURLWithPath: "/tmp/audio.m4a"))
        ])
        XCTAssertFalse(audioOnly.hasVideoMedia)

        let screenVideo = CaptureSourceRunSummary(completions: [
            .screen: .wrote(URL(fileURLWithPath: "/tmp/screen.mov"))
        ])
        XCTAssertTrue(screenVideo.hasVideoMedia)

        let emptyCamera = CaptureSourceRunSummary(completions: [
            .camera: .empty(URL(fileURLWithPath: "/tmp/camera.mov"))
        ])
        XCTAssertFalse(emptyCamera.hasVideoMedia)
    }

    func testCaptureSourceRunSummarySanitizesRemoteIPhoneNoFramesFailure() {
        let summary = CaptureSourceRunSummary(
            completions: [.camera: .empty(URL(fileURLWithPath: "/tmp/camera.mov"))],
            stopFailures: [
                .camera: "Remote iPhone transfer failed: iPhone recording failed before stop: Cannot Complete Action. No video frames captured"
            ]
        )

        XCTAssertEqual(
            summary.stopFailureWarning,
            "Some sources stopped with errors: Camera: iPhone camera did not save usable video. Keep BlitzRecorder Camera open until recording stops, then retry."
        )
    }

    func testTakeFileStoreCreatesAndCleansScratchDirectory() throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.savesSourceFiles = true

        let store = TakeFileStore()
        let take = try store.createTake(
            settings: settings,
            date: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: take.scratchDirectory.path))
        XCTAssertEqual(take.screenURL.lastPathComponent, "screen.mov")
        XCTAssertEqual(take.cameraURL.lastPathComponent, "camera.mov")
        XCTAssertTrue(FileManager.default.fileExists(atPath: take.sourceManifestURL.path))
        XCTAssertEqual(take.finalVideoURL.lastPathComponent, "\(String(take.scratchDirectory.lastPathComponent.prefix(19)))-final.mov")

        store.cleanupIntermediateFiles(for: take, settings: settings)

        XCTAssertFalse(FileManager.default.fileExists(atPath: take.scratchDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: settings.outputDirectory.appendingPathComponent("BlitzRecorder Source Takes").path
        ))
    }

    func testTakeFileStoreWritesSourceTakeManifest() throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.savesSourceFiles = true
        settings.enabledSources = [.screen, .camera, .microphone]
        settings.outputResolution = .p720
        settings.outputVideoFormat = .mp4

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)

        let data = try Data(contentsOf: take.sourceManifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(SourceTakeManifest.self, from: data)

        XCTAssertEqual(manifest.version, 1)
        XCTAssertEqual(manifest.layout, CaptureLayout.vertical.rawValue)
        XCTAssertEqual(manifest.outputResolution, OutputResolution.p720.rawValue)
        XCTAssertEqual(manifest.outputVideoFormat, OutputVideoFormat.mp4.rawValue)
        XCTAssertEqual(manifest.enabledSources, ["Camera", "Microphone", "Screen"])
        XCTAssertTrue(manifest.sources.contains { $0.role == "screen" && $0.path == take.screenURL.path })
        XCTAssertNil(manifest.finalVideoPath)
    }

    func testTakeFileStoreDoesNotWriteSourceTakeManifestByDefault() throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()

        let take = try TakeFileStore().createTake(settings: settings)

        XCTAssertFalse(FileManager.default.fileExists(atPath: take.sourceManifestURL.path))
    }

    func testTakeFileStorePrefixesGeneratedSlugWithTakeDate() throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.savesSourceFiles = true

        let store = TakeFileStore()
        let take = try store.createTake(
            settings: settings,
            date: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let datePrefix = String(take.scratchDirectory.lastPathComponent.prefix(19))

        XCTAssertEqual(
            store.datedSlug(for: take, slug: "better-video-title"),
            "\(datePrefix)-better-video-title"
        )
        XCTAssertEqual(
            store.datedSlug(for: take, slug: "2023-11-14-22-13-20-better-video-title"),
            "2023-11-14-22-13-20-better-video-title"
        )
        XCTAssertEqual(
            store.datedSlug(for: take, slug: nil),
            datePrefix
        )
    }

    func testTitleGeneratorReturnsNilForLowSignalTranscript() async {
        let slug = await TitleGenerator().titleSlug(for: "Um. Yeah. Thank you.")

        XCTAssertNil(slug)
    }

    func testOutputDirectoryPreflightRequiresWritableExportFolder() throws {
        var settings = RecordingSettings()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlitzRecorderTests-\(UUID().uuidString)")
        try "not a directory".write(to: fileURL, atomically: true, encoding: .utf8)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: fileURL)
        }
        settings.outputDirectory = fileURL.appendingPathComponent("child", isDirectory: true)

        XCTAssertThrowsError(try TakeFileStore().prepareOutputDirectory(settings: settings)) { error in
            guard case RecorderError.outputDirectoryUnavailable = error else {
                return XCTFail("Expected outputDirectoryUnavailable, got \(error)")
            }
        }
    }

    func testOutputDirectoryPreflightCreatesWritableScratchRoot() throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()

        let access = try TakeFileStore().prepareOutputDirectory(settings: settings)
        defer { access.stop() }

        XCTAssertTrue(FileManager.default.fileExists(atPath: settings.outputDirectory.path))
    }

    func testOutputDirectoryPreflightExplainsPermissionRecovery() throws {
        var settings = RecordingSettings()
        let blockedDirectory = temporaryDirectory()
        try FileManager.default.createDirectory(at: blockedDirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: blockedDirectory.path)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: blockedDirectory.path)
            try? FileManager.default.removeItem(at: blockedDirectory)
        }
        settings.outputDirectory = blockedDirectory

        XCTAssertThrowsError(try TakeFileStore().prepareOutputDirectory(settings: settings)) { error in
            guard case RecorderError.outputDirectoryUnavailable(let reason) = error else {
                return XCTFail("Expected outputDirectoryUnavailable, got \(error)")
            }
            XCTAssertTrue(reason.contains("Choose this folder again in Export Settings"))
        }
    }

    func testAvailableCapacityFallsBackWhenImportantUsageCapacityIsZero() {
        let capacity = TakeFileStore.availableCapacityForRecording(
            importantUsageCapacity: 0,
            fallbackCapacity: 501_766_684_672,
            fileSystemCapacity: nil
        )

        XCTAssertEqual(capacity, 501_766_684_672)
        XCTAssertGreaterThan(capacity ?? 0, TakeFileStore.minimumAvailableCapacityBytes)
    }

    func testAvailableCapacityFallsBackToFileSystemCapacityForExternalVolumes() {
        let capacity = TakeFileStore.availableCapacityForRecording(
            importantUsageCapacity: 0,
            fallbackCapacity: 0,
            fileSystemCapacity: 501_766_684_672
        )

        XCTAssertEqual(capacity, 501_766_684_672)
        XCTAssertGreaterThan(capacity ?? 0, TakeFileStore.minimumAvailableCapacityBytes)
    }

    func testAvailableCapacityStillBlocksWhenNoCapacityIsReported() {
        let capacity = TakeFileStore.availableCapacityForRecording(
            importantUsageCapacity: 0,
            fallbackCapacity: nil,
            fileSystemCapacity: nil
        )

        XCTAssertEqual(capacity, 0)
        XCTAssertLessThan(capacity ?? .max, TakeFileStore.minimumAvailableCapacityBytes)
    }

    func testRemoteCameraPendingImportStorePersistsRecoveryMetadata() throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()

        let store = RemoteCameraPendingImportStore()
        let takeID = UUID()
        let pendingImport = RemoteCameraPendingImport(
            takeID: takeID,
            serviceID: "iphone-15-pro",
            scratchDirectory: settings.outputDirectory.appendingPathComponent("scratch", isDirectory: true),
            destinationURL: settings.outputDirectory.appendingPathComponent("scratch/camera.mov"),
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            expectedByteCount: nil
        )

        store.upsert(pendingImport, settings: settings)
        XCTAssertEqual(store.all(settings: settings), [pendingImport])

        store.updateExpectedByteCount(takeID: takeID, expectedByteCount: 42, settings: settings)
        XCTAssertEqual(store.all(settings: settings).first?.expectedByteCount, 42)

        store.remove(takeID: takeID, settings: settings)
        XCTAssertTrue(store.all(settings: settings).isEmpty)
    }

    @MainActor
    func testCaptureSourceRunStartPropagatesCameraStartupFailure() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.camera, .microphone]

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        let cameraRecorder = FailingCameraCaptureRecorder(error: RecorderError.cameraDidNotStart)
        let microphoneRecorder = SpyMicrophoneCaptureRecorder()
        let run = CaptureSourceRun(
            take: take,
            settings: settings,
            pickedScreenFilter: nil,
            screenRecorder: NoopScreenCaptureRecorder(),
            cameraRecorder: cameraRecorder,
            audioRecorder: microphoneRecorder,
            systemAudioRecorder: NoopSystemAudioCaptureRecorder()
        )

        do {
            try await run.start()
            XCTFail("Expected Camera startup failure")
        } catch {
            XCTAssertEqual(error.localizedDescription, RecorderError.cameraDidNotStart.localizedDescription)
        }
        XCTAssertEqual(cameraRecorder.startCount, 1)
        XCTAssertEqual(microphoneRecorder.startCount, 1)
    }

    @MainActor
    func testCaptureSourceRunStartCleansUpAttemptedSourcesAfterFailure() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.screen, .microphone]

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        let screenRecorder = SpyScreenCaptureRecorder(stopCompletion: .empty(take.screenURL))
        let microphoneRecorder = FailingStartMicrophoneCaptureRecorder(error: RecorderError.microphoneUnavailable)
        let run = CaptureSourceRun(
            take: take,
            settings: settings,
            pickedScreenFilter: nil,
            screenRecorder: screenRecorder,
            cameraRecorder: FailingCameraCaptureRecorder(error: RecorderError.noCamera),
            audioRecorder: microphoneRecorder,
            systemAudioRecorder: NoopSystemAudioCaptureRecorder()
        )

        do {
            try await run.start()
            XCTFail("Expected microphone startup failure")
        } catch {
            XCTAssertEqual(error.localizedDescription, RecorderError.microphoneUnavailable.localizedDescription)
        }

        XCTAssertEqual(screenRecorder.stopCount, 1)
        XCTAssertEqual(microphoneRecorder.stopCount, 1)
    }

    @MainActor
    func testCaptureSourceRunPassesSharedTimelineStartToSources() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.screen, .microphone]

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        let timelineStart = CMTime(value: 42, timescale: 1_000)
        let screenRecorder = SpyScreenCaptureRecorder(stopCompletion: .empty(take.screenURL))
        let microphoneRecorder = SpyMicrophoneCaptureRecorder()
        let run = CaptureSourceRun(
            take: take,
            settings: settings,
            pickedScreenFilter: nil,
            timelineStartTime: timelineStart,
            screenRecorder: screenRecorder,
            cameraRecorder: FailingCameraCaptureRecorder(error: RecorderError.noCamera),
            audioRecorder: microphoneRecorder,
            systemAudioRecorder: NoopSystemAudioCaptureRecorder()
        )

        let start = try await run.start()
        _ = await run.stop()

        XCTAssertEqual(start.timelineStartTime, timelineStart)
        XCTAssertEqual(screenRecorder.capturedTimelineStartTime, timelineStart)
        XCTAssertEqual(microphoneRecorder.capturedTimelineStartTime, timelineStart)
    }

    @MainActor
    func testCaptureSourceRunCanStartScreenSourceAfterRecordingStarts() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.microphone]

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        let timelineStart = CMTime(value: 42, timescale: 1_000)
        let screenRecorder = SpyScreenCaptureRecorder(stopCompletion: .wrote(take.screenURL))
        let microphoneRecorder = SpyMicrophoneCaptureRecorder()
        let run = CaptureSourceRun(
            take: take,
            settings: settings,
            pickedScreenFilter: nil,
            timelineStartTime: timelineStart,
            screenRecorder: screenRecorder,
            cameraRecorder: FailingCameraCaptureRecorder(error: RecorderError.noCamera),
            audioRecorder: microphoneRecorder,
            systemAudioRecorder: NoopSystemAudioCaptureRecorder()
        )

        try await run.start()
        var updatedSettings = settings
        updatedSettings.enabledSources = [.screen, .microphone]
        try await run.startEnabledSources(settings: updatedSettings, pickedScreenFilter: nil)
        let summary = await run.stop()

        XCTAssertEqual(microphoneRecorder.startCount, 1)
        XCTAssertEqual(screenRecorder.startCount, 1)
        XCTAssertEqual(screenRecorder.capturedTimelineStartTime, timelineStart)
        XCTAssertEqual(summary.completions[.screen], .wrote(take.screenURL))
    }

    @MainActor
    func testCaptureSourceRunUpdatesActiveScreenCaptureSettings() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.screen]

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        let screenRecorder = SpyScreenCaptureRecorder(stopCompletion: .wrote(take.screenURL))
        let run = CaptureSourceRun(
            take: take,
            settings: settings,
            pickedScreenFilter: nil,
            screenRecorder: screenRecorder,
            cameraRecorder: FailingCameraCaptureRecorder(error: RecorderError.noCamera),
            audioRecorder: SpyMicrophoneCaptureRecorder(),
            systemAudioRecorder: NoopSystemAudioCaptureRecorder()
        )

        try await run.start()
        var updatedSettings = settings
        updatedSettings.screenCrop = CGRect(x: 0.25, y: 0.1, width: 0.5, height: 0.6)
        try await run.updateScreenCapture(settings: updatedSettings, pickedScreenFilter: nil)

        XCTAssertEqual(screenRecorder.startCount, 1)
        XCTAssertEqual(screenRecorder.updateCount, 1)
        XCTAssertEqual(screenRecorder.updatedSettings?.screenCrop, updatedSettings.screenCrop)
        _ = await run.stop()
    }

    @MainActor
    func testCaptureSourceRunPausesScreenSourceAddedWhilePaused() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.microphone]

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        let screenRecorder = SpyScreenCaptureRecorder(stopCompletion: .empty(take.screenURL))
        let run = CaptureSourceRun(
            take: take,
            settings: settings,
            pickedScreenFilter: nil,
            screenRecorder: screenRecorder,
            cameraRecorder: FailingCameraCaptureRecorder(error: RecorderError.noCamera),
            audioRecorder: SpyMicrophoneCaptureRecorder(),
            systemAudioRecorder: NoopSystemAudioCaptureRecorder()
        )

        try await run.start()
        run.pause()
        var updatedSettings = settings
        updatedSettings.enabledSources = [.screen, .microphone]
        try await run.startEnabledSources(settings: updatedSettings, pickedScreenFilter: nil)

        XCTAssertEqual(screenRecorder.pauseCount, 1)
        _ = await run.stop()
    }

    @MainActor
    func testCaptureSourceRunStartsScreenFirstAndStopsScreenLast() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.screen, .camera, .microphone, .systemAudio]

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        let order = OrderedCaptureEvents()
        let run = CaptureSourceRun(
            take: take,
            settings: settings,
            pickedScreenFilter: nil,
            screenRecorder: OrderedScreenCaptureRecorder(order: order),
            cameraRecorder: OrderedCameraCaptureRecorder(order: order),
            audioRecorder: OrderedMicrophoneCaptureRecorder(order: order),
            systemAudioRecorder: OrderedSystemAudioCaptureRecorder(order: order)
        )

        try await run.start()
        _ = await run.stop()

        XCTAssertEqual(order.started, [.screen, .microphone, .systemAudio, .camera])
        XCTAssertEqual(order.stopped, [.microphone, .systemAudio, .camera, .screen])
    }

    @MainActor
    func testCaptureSourceRunCanUseRemoteCameraAdapterForCameraSource() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.screen, .camera]
        settings.selectedCameraID = RemoteCameraProviderID.make(for: "iphone-15-pro")

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        let localCamera = FailingCameraCaptureRecorder(error: RecorderError.cameraDidNotStart)
        let remoteCamera = SpyRemoteCameraCaptureRecorder(completion: .wrote(take.cameraURL))
        let run = CaptureSourceRun(
            take: take,
            settings: settings,
            pickedScreenFilter: nil,
            screenRecorder: SpyScreenCaptureRecorder(stopCompletion: .wrote(take.screenURL)),
            cameraRecorder: localCamera,
            remoteCameraRecorder: remoteCamera,
            audioRecorder: SpyMicrophoneCaptureRecorder(),
            systemAudioRecorder: NoopSystemAudioCaptureRecorder()
        )

        let start = try await run.start()
        let summary = await run.stop()

        XCTAssertEqual(localCamera.startCount, 0)
        XCTAssertEqual(remoteCamera.startCount, 1)
        XCTAssertEqual(remoteCamera.stopCount, 1)
        XCTAssertEqual(remoteCamera.capturedHostTimelineStartTime, start.hostTimelineStartTime)
        XCTAssertEqual(remoteCamera.capturedStartSettings?.selectedCameraID, settings.selectedCameraID)
        XCTAssertEqual(summary.completions[.camera], .wrote(take.cameraURL))
    }

    @MainActor
    func testCaptureSourceRunStopPreservesVideoCompletionWhenAudioStopFails() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.screen, .microphone]

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        let screenRecorder = SpyScreenCaptureRecorder(stopCompletion: .wrote(take.screenURL))
        let microphoneRecorder = FailingStopMicrophoneCaptureRecorder(error: RecorderError.microphoneUnavailable)
        let run = CaptureSourceRun(
            take: take,
            settings: settings,
            pickedScreenFilter: nil,
            screenRecorder: screenRecorder,
            cameraRecorder: FailingCameraCaptureRecorder(error: RecorderError.noCamera),
            audioRecorder: microphoneRecorder,
            systemAudioRecorder: NoopSystemAudioCaptureRecorder()
        )

        try await run.start()
        let summary = await run.stop()

        XCTAssertTrue(summary.hasVideoMedia)
        XCTAssertEqual(summary.completions[.screen], .wrote(take.screenURL))
        XCTAssertEqual(summary.stopFailures[.microphone], RecorderError.microphoneUnavailable.localizedDescription)
        XCTAssertTrue(summary.stopFailureWarning?.contains("Microphone") == true)
        XCTAssertEqual(
            summary.savedRecordingStopWarning,
            "Microphone audio could not be finalized. Saved video is intact, but that audio track may be missing."
        )
        XCTAssertEqual(screenRecorder.stopCount, 1)
        XCTAssertEqual(microphoneRecorder.stopCount, 1)
    }

    @MainActor
    func testCaptureSourceRunPreservesCompletedAudioWhenStopReportsError() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.screen, .systemAudio]

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        let systemAudioRecorder = CompletedStopFailureSystemAudioCaptureRecorder(
            completion: .wrote(take.systemAudioURL),
            error: RecorderError.captureStreamStopped("display went away")
        )
        let run = CaptureSourceRun(
            take: take,
            settings: settings,
            pickedScreenFilter: nil,
            screenRecorder: SpyScreenCaptureRecorder(stopCompletion: .wrote(take.screenURL)),
            cameraRecorder: FailingCameraCaptureRecorder(error: RecorderError.noCamera),
            audioRecorder: SpyMicrophoneCaptureRecorder(),
            systemAudioRecorder: systemAudioRecorder
        )

        try await run.start()
        let summary = await run.stop()

        XCTAssertEqual(summary.completions[.systemAudio], .wrote(take.systemAudioURL))
        XCTAssertTrue(summary.stopFailures[.systemAudio]?.contains("display went away") == true)
        XCTAssertNil(summary.savedRecordingStopWarning)
    }

    func testDirectMovieWriterRetimesAudioAgainstHostClock() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.screen, .microphone]
        settings.outputResolution = .p720
        settings.framesPerSecond = 30

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        let writer = try DirectMovieWriter(take: take, settings: settings)
        let distantAudioPTS = CMTime(seconds: 100_000, preferredTimescale: 48_000)
        let audioSample = try makeSilentAudioSampleBuffer(
            presentationTime: distantAudioPTS,
            frames: 480
        )

        writer.appendAudio(audioSample, source: .microphone)

        let start = CMClockGetTime(CMClockGetHostTimeClock())
        for frame in 0..<12 {
            let sourceTime = CMTimeAdd(start, CMTime(value: CMTimeValue(frame), timescale: 30))
            writer.appendVideo(sourceTime: sourceTime) { [weak self] pixelBuffer in
                self?.fill(pixelBuffer, color: (blue: 40, green: 120, red: 220, alpha: 255))
                return true
            }
        }

        let completion = try await writer.finish()

        XCTAssertTrue(completion.wroteMedia)
        XCTAssertTrue(FileManager.default.fileExists(atPath: take.finalVideoURL.path))
    }

    func testVideoFileWriterFallsBackWhenTimelineUsesDifferentClock() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("video.mov")
        let writer = try VideoFileWriter(
            url: url,
            width: 64,
            height: 64,
            bitrate: 1_000_000,
            fps: 30,
            outputFormat: .mov,
            timelineStartTime: CMTime(seconds: 100_000, preferredTimescale: 1_000_000_000)
        )

        for frame in 0..<12 {
            let sampleBuffer = try makeVideoSampleBuffer(
                presentationTime: CMTime(value: CMTimeValue(frame), timescale: 30)
            )
            writer.append(sampleBuffer)
        }

        let completion = try await writer.finish()

        XCTAssertTrue(completion.wroteMedia)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testAudioSampleFileWriterFallsBackWhenTimelineUsesDifferentClock() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("audio.m4a")
        let writer = try AudioSampleFileWriter(
            url: url,
            timelineStartTime: CMTime(seconds: 100_000, preferredTimescale: 1_000_000_000)
        )

        for packet in 0..<12 {
            let sampleBuffer = try makeSilentAudioSampleBuffer(
                presentationTime: CMTime(value: CMTimeValue(packet * 480), timescale: 48_000),
                frames: 480
            )
            writer.append(sampleBuffer)
        }

        let completion = try await writer.finish()

        XCTAssertTrue(completion.wroteMedia)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testAudioSampleFileWriterUsesFirstSampleFormat() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("audio.m4a")
        let writer = try AudioSampleFileWriter(url: url)

        for packet in 0..<12 {
            let sampleBuffer = try makeSilentAudioSampleBuffer(
                presentationTime: CMTime(value: CMTimeValue(packet * 441), timescale: 44_100),
                frames: 441,
                sampleRate: 44_100
            )
            writer.append(sampleBuffer)
        }

        let completion = try await writer.finish()
        let asset = AVURLAsset(url: try XCTUnwrap(completion.url))
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let formatDescriptions = try await XCTUnwrap(audioTracks.first).load(.formatDescriptions)
        let audioDescription = try XCTUnwrap(try XCTUnwrap(formatDescriptions.first).audioStreamBasicDescription)

        XCTAssertTrue(completion.wroteMedia)
        XCTAssertEqual(audioDescription.mSampleRate, 44_100, accuracy: 1)
    }

    func testMergerExportsWithTransparentCameraIntermediate() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.screen, .camera]
        settings.removesCameraBackgroundAfterRecording = true
        settings.framesPerSecond = 30
        settings.outputResolution = .p720

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        try FileManager.default.createDirectory(at: take.scratchDirectory, withIntermediateDirectories: true)

        try writeTestMovie(
            url: take.screenURL,
            codec: .h264,
            color: (blue: 255, green: 0, red: 0, alpha: 255)
        )
        let transparentCameraURL = take.scratchDirectory.appendingPathComponent("camera-background-removed.mov")
        try writeTestMovie(
            url: transparentCameraURL,
            codec: .proRes4444,
            color: (blue: 0, green: 0, red: 255, alpha: 96)
        )
        let processedTake = RecordingTake(
            scratchDirectory: take.scratchDirectory,
            screenURL: take.screenURL,
            cameraURL: transparentCameraURL,
            audioURL: take.audioURL,
            systemAudioURL: take.systemAudioURL,
            transcriptURL: take.transcriptURL,
            finalVideoURL: take.finalVideoURL,
            outputVideoFormat: take.outputVideoFormat,
            titleSlug: take.titleSlug
        )

        let outputURL = try await Merger.exportFinalVideo(take: processedTake, settings: settings)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testMergerSkipsUnreadableCameraFileAndExportsScreenVideo() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.screen, .camera]
        settings.framesPerSecond = 30
        settings.outputResolution = .p720

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        try FileManager.default.createDirectory(at: take.scratchDirectory, withIntermediateDirectories: true)

        try writeTestMovie(
            url: take.screenURL,
            codec: .h264,
            color: (blue: 255, green: 0, red: 0, alpha: 255)
        )
        XCTAssertTrue(FileManager.default.createFile(atPath: take.cameraURL.path, contents: Data()))

        let outputURL = try await Merger.exportFinalVideo(take: take, settings: settings)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        let asset = AVURLAsset(url: outputURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(videoTracks.count, 1)
    }

    func testMergerExportsRemoteCameraWithSubframePositiveTimelineOffset() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.screen, .camera]
        settings.framesPerSecond = 30
        settings.outputResolution = .p720

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        try FileManager.default.createDirectory(at: take.scratchDirectory, withIntermediateDirectories: true)

        try writeTestMovie(
            url: take.screenURL,
            codec: .h264,
            color: (blue: 255, green: 0, red: 0, alpha: 255)
        )
        try writeTestMovie(
            url: take.cameraURL,
            codec: .h264,
            color: (blue: 0, green: 0, red: 255, alpha: 255)
        )
        try writeRemoteCameraManifest(
            for: take.cameraURL,
            hostTimelineStartTime: 1_000_000_000,
            estimatedHostStartTime: 1_219_230_583
        )

        let outputURL = try await Merger.exportFinalVideo(take: take, settings: settings)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testMergerIgnoresHiddenCameraFileWhenExportingScreenOnly() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.screen, .camera]
        settings.hiddenSources = [.camera]
        settings.framesPerSecond = 30
        settings.outputResolution = .p720

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        try FileManager.default.createDirectory(at: take.scratchDirectory, withIntermediateDirectories: true)

        try writeTestMovie(
            url: take.screenURL,
            codec: .h264,
            color: (blue: 255, green: 0, red: 0, alpha: 255)
        )
        try writeTestMovie(
            url: take.cameraURL,
            codec: .h264,
            color: (blue: 0, green: 0, red: 255, alpha: 255),
            frameCount: 3
        )

        let outputURL = try await Merger.exportFinalVideo(take: take, settings: settings)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        let asset = AVURLAsset(url: outputURL)
        let duration = try await asset.load(.duration)
        XCTAssertGreaterThan(duration.seconds, 0.35)
    }

    func testMergerCanRevealInitiallyHiddenScreenAfterSceneSwitch() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.screen, .camera]
        settings.hiddenSources = [.screen]
        settings.sceneLayout = SceneLayout.presetLayout(.webcamFullscreen, for: .vertical)
        settings.canvasBackgroundStyle = .black
        settings.framesPerSecond = 30
        settings.outputResolution = .p720

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        try FileManager.default.createDirectory(at: take.scratchDirectory, withIntermediateDirectories: true)

        try writeTestMovie(
            url: take.screenURL,
            codec: .h264,
            color: (blue: 255, green: 0, red: 0, alpha: 255)
        )
        try writeTestMovie(
            url: take.cameraURL,
            codec: .h264,
            color: (blue: 0, green: 0, red: 255, alpha: 255)
        )

        var stackedSettings = settings
        stackedSettings.hiddenSources = []
        stackedSettings.sceneLayout = SceneLayout.presetLayout(.stackedHalves, for: .vertical)

        let outputURL = try await Merger.exportFinalVideo(
            take: take,
            settings: settings,
            sceneEvents: [
                RecordingSceneEvent(time: 0, scene: RecordingScene(settings: settings)),
                RecordingSceneEvent(time: 0.2, scene: RecordingScene(settings: stackedSettings))
            ]
        )

        let sampledColors = try await samplePixelColors(
            in: outputURL,
            normalizedPoints: [
                CGPoint(x: 0.5, y: 0.1),
                CGPoint(x: 0.5, y: 0.2),
                CGPoint(x: 0.5, y: 0.3),
                CGPoint(x: 0.5, y: 0.8)
            ],
            at: CMTime(seconds: 0.3, preferredTimescale: 600)
        )
        XCTAssertTrue(
            sampledColors.contains { color in
                color.blue > 140 && color.blue > color.red * 2 && color.blue > color.green * 2
            },
            "Expected the initially hidden screen track to render after switching to stacked layout."
        )
    }

    func testMergerCrossfadesSourceVisibilityDuringSceneSwitch() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.screen, .camera]
        settings.hiddenSources = [.camera]
        settings.sceneLayout = SceneLayout.presetLayout(.screenFullscreen, for: .vertical)
        settings.framesPerSecond = 60
        settings.outputResolution = .p720

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        try FileManager.default.createDirectory(at: take.scratchDirectory, withIntermediateDirectories: true)

        try writeTestMovie(
            url: take.screenURL,
            codec: .h264,
            color: (blue: 255, green: 0, red: 0, alpha: 255)
        )
        try writeTestMovie(
            url: take.cameraURL,
            codec: .h264,
            color: (blue: 0, green: 0, red: 255, alpha: 255)
        )

        var cameraSettings = settings
        cameraSettings.hiddenSources = [.screen]
        cameraSettings.sceneLayout = SceneLayout.presetLayout(.webcamFullscreen, for: .vertical)

        let outputURL = try await Merger.exportFinalVideo(
            take: take,
            settings: settings,
            sceneEvents: [
                RecordingSceneEvent(time: 0, scene: RecordingScene(settings: settings)),
                RecordingSceneEvent(
                    time: 0.2,
                    scene: RecordingScene(settings: cameraSettings),
                    transition: RecordingSceneTransition(duration: 0.4, curve: .linear)
                )
            ]
        )

        let sampledColors = try await samplePixelColors(
            in: outputURL,
            normalizedPoints: [CGPoint(x: 0.5, y: 0.5)],
            at: CMTime(seconds: 0.4, preferredTimescale: 600)
        )
        let color = sampledColors[0]
        XCTAssertGreaterThan(color.red, 60, "Expected camera contribution in mid-transition color: \(color)")
        XCTAssertGreaterThan(color.blue, 80, "Expected screen contribution in mid-transition color: \(color)")
        XCTAssertLessThan(color.red, 210, "Expected camera not to fully replace screen mid-transition: \(color)")
        XCTAssertLessThan(color.blue, 210, "Expected screen not to fully replace camera mid-transition: \(color)")
    }

    func testMergerRendersScreenTop50AfterWebcamFullscreenSceneSwitch() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.screen, .camera]
        settings.hiddenSources = [.screen]
        settings.sceneLayout = SceneLayout.presetLayout(.webcamFullscreen, for: .vertical)
        settings.framesPerSecond = 30
        settings.outputResolution = .p720

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        try FileManager.default.createDirectory(at: take.scratchDirectory, withIntermediateDirectories: true)

        try writeTestMovie(
            url: take.screenURL,
            codec: .h264,
            color: (blue: 255, green: 0, red: 0, alpha: 255)
        )
        try writeTestMovie(
            url: take.cameraURL,
            codec: .h264,
            color: (blue: 0, green: 0, red: 255, alpha: 255)
        )

        var splitSettings = settings
        splitSettings.hiddenSources = []
        splitSettings.sceneLayout = SceneLayout.presetLayout(.screenTop50, for: .vertical)

        let outputURL = try await Merger.exportFinalVideo(
            take: take,
            settings: settings,
            sceneEvents: [
                RecordingSceneEvent(time: 0, scene: RecordingScene(settings: settings)),
                RecordingSceneEvent(time: 0.2, scene: RecordingScene(settings: splitSettings))
            ]
        )

        let sampledColors = try await samplePixelColors(
            in: outputURL,
            normalizedPoints: [
                CGPoint(x: 0.5, y: 0.25),
                CGPoint(x: 0.5, y: 0.75)
            ],
            at: CMTime(seconds: 0.3, preferredTimescale: 600)
        )
        let bottomScreen = sampledColors[0]
        let topCamera = sampledColors[1]

        XCTAssertGreaterThan(bottomScreen.blue, 140)
        XCTAssertGreaterThan(topCamera.red, 140)
    }

    func testMergerPreservesCanvasPaddingAndBackgroundInFinalExport() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.screen]
        settings.sceneLayout = SceneLayout.presetLayout(.screenFullscreen, for: .vertical)
        settings.canvasPadding = 0.12
        settings.canvasBackgroundStyle = .ocean
        settings.framesPerSecond = 30
        settings.outputResolution = .p720

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        try FileManager.default.createDirectory(at: take.scratchDirectory, withIntermediateDirectories: true)
        try writeTestMovie(
            url: take.screenURL,
            codec: .h264,
            color: (blue: 0, green: 0, red: 255, alpha: 255)
        )

        let outputURL = try await Merger.exportFinalVideo(take: take, settings: settings)
        let sampledColors = try await samplePixelColors(
            in: outputURL,
            normalizedPoints: [
                CGPoint(x: 0.02, y: 0.5),
                CGPoint(x: 0.5, y: 0.5)
            ],
            at: CMTime(seconds: 0.1, preferredTimescale: 600)
        )

        let paddedEdge = sampledColors[0]
        let screenCenter = sampledColors[1]
        XCTAssertGreaterThan(paddedEdge.green + paddedEdge.blue, 40)
        XCTAssertLessThan(paddedEdge.red, 80)
        XCTAssertGreaterThan(screenCenter.red, 140)
    }

    func testMergerFillsPaddedStackedCameraSlotToRightEdge() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.screen, .camera]
        settings.sceneLayout = SceneLayout.presetLayout(.screenTop50, for: .vertical)
        settings.canvasPadding = 0.08
        settings.canvasBackgroundStyle = .ocean
        settings.framesPerSecond = 30
        settings.outputResolution = .p720

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        try FileManager.default.createDirectory(at: take.scratchDirectory, withIntermediateDirectories: true)
        try writeTestMovie(
            url: take.screenURL,
            codec: .h264,
            color: (blue: 255, green: 0, red: 0, alpha: 255)
        )
        try writeTestMovie(
            url: take.cameraURL,
            codec: .h264,
            color: (blue: 0, green: 0, red: 255, alpha: 255)
        )

        let outputURL = try await Merger.exportFinalVideo(take: take, settings: settings)
        let dimensions = settings.outputResolution.dimensions(for: settings.layout)
        let renderSize = CGSize(width: dimensions.width, height: dimensions.height)
        let cameraRect = SceneLayoutProjection.projectedFrame(
            for: .camera,
            in: CGRect(origin: .zero, size: renderSize),
            sceneLayout: settings.sceneLayout,
            enabledSources: settings.enabledSources,
            canvasPadding: settings.canvasPadding,
            origin: .upperLeft,
            fillsCanvasWhenOnlyVideoSource: true
        )
        let sampledColors = try await samplePixelColors(
            in: outputURL,
            normalizedPoints: [
                CGPoint(
                    x: cameraRect.midX / renderSize.width,
                    y: cameraRect.midY / renderSize.height
                ),
                CGPoint(
                    x: (cameraRect.minX + 6) / renderSize.width,
                    y: cameraRect.midY / renderSize.height
                ),
                CGPoint(
                    x: (cameraRect.maxX - 24) / renderSize.width,
                    y: cameraRect.midY / renderSize.height
                ),
                CGPoint(
                    x: min(0.99, (cameraRect.maxX + 12) / renderSize.width),
                    y: cameraRect.midY / renderSize.height
                )
            ],
            at: CMTime(seconds: 0.1, preferredTimescale: 600)
        )

        let insideRightEdge = sampledColors[2]
        let outsidePadding = sampledColors[3]
        XCTAssertGreaterThan(insideRightEdge.red, 140, "insideRightEdge=\(insideRightEdge)")
        XCTAssertLessThan(insideRightEdge.green + insideRightEdge.blue, 120, "insideRightEdge=\(insideRightEdge)")
        XCTAssertLessThan(outsidePadding.red, 120)
        XCTAssertGreaterThan(outsidePadding.green + outsidePadding.blue, 40)
    }

    func testMergerCameraCropSamplesSelectedSourceAreaInPaddedStackedSlot() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.screen, .camera]
        settings.sceneLayout = SceneLayout.presetLayout(.screenTop50, for: .vertical)
        settings.canvasPadding = 0.02
        settings.canvasBackgroundStyle = .silver
        settings.cameraCropAmount = CGPoint(x: 0.2904946280883587, y: 0.2904946280883587)
        settings.cameraCropPosition = CGPoint(x: -0.0035897796860702453, y: 0.4854035047305225)
        settings.framesPerSecond = 30
        settings.outputResolution = .p720

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        try FileManager.default.createDirectory(at: take.scratchDirectory, withIntermediateDirectories: true)
        try writeTestMovie(
            url: take.screenURL,
            codec: .h264,
            color: (blue: 255, green: 0, red: 0, alpha: 255)
        )
        try writeCoordinateGradientMovie(
            url: take.cameraURL,
            width: 160,
            height: 90
        )

        let outputURL = try await Merger.exportFinalVideo(take: take, settings: settings)
        let dimensions = settings.outputResolution.dimensions(for: settings.layout)
        let renderSize = CGSize(width: dimensions.width, height: dimensions.height)
        let cameraRect = SceneLayoutProjection.projectedFrame(
            for: .camera,
            in: CGRect(origin: .zero, size: renderSize),
            sceneLayout: settings.sceneLayout,
            enabledSources: settings.enabledSources,
            canvasPadding: settings.canvasPadding,
            origin: .upperLeft,
            fillsCanvasWhenOnlyVideoSource: true
        )
        let sampledColor = try await samplePixelColors(
            in: outputURL,
            normalizedPoints: [
                CGPoint(
                    x: cameraRect.midX / renderSize.width,
                    y: cameraRect.midY / renderSize.height
                )
            ],
            at: CMTime(seconds: 0.1, preferredTimescale: 600)
        )[0]
        let expectedCrop = SourceCropGeometry.cropRectangle(
            source: CGRect(x: 0, y: 0, width: 160, height: 90),
            target: cameraRect,
            sourceCropAmount: settings.cameraCropAmount,
            sourceCropPosition: settings.cameraCropPosition
        )
        let expectedColor = try await samplePixelColors(
            in: take.cameraURL,
            normalizedPoints: [
                CGPoint(
                    x: expectedCrop.midX / 160,
                    y: expectedCrop.midY / 90
                )
            ],
            at: CMTime(seconds: 0.1, preferredTimescale: 600)
        )[0]

        XCTAssertEqual(sampledColor.red, expectedColor.red, accuracy: 18)
        XCTAssertEqual(sampledColor.green, expectedColor.green, accuracy: 18)
    }

    func testMergerRoundsPaddedSourceCornersInFinalExport() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.screen]
        settings.sceneLayout = SceneLayout.presetLayout(.screenFullscreen, for: .vertical)
        settings.canvasPadding = 0.12
        settings.canvasBackgroundStyle = .ocean
        settings.framesPerSecond = 30
        settings.outputResolution = .p720

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        try FileManager.default.createDirectory(at: take.scratchDirectory, withIntermediateDirectories: true)
        try writeTestMovie(
            url: take.screenURL,
            codec: .h264,
            color: (blue: 0, green: 0, red: 255, alpha: 255)
        )

        let outputURL = try await Merger.exportFinalVideo(take: take, settings: settings)
        let dimensions = settings.outputResolution.dimensions(for: settings.layout)
        let inset = CGFloat(min(dimensions.width, dimensions.height)) * settings.canvasPadding
        let sampledColors = try await samplePixelColors(
            in: outputURL,
            normalizedPoints: [
                CGPoint(x: (inset + 3) / CGFloat(dimensions.width), y: (inset + 3) / CGFloat(dimensions.height)),
                CGPoint(x: 0.5, y: 0.5)
            ],
            at: CMTime(seconds: 0.1, preferredTimescale: 600)
        )

        let roundedCorner = sampledColors[0]
        let screenCenter = sampledColors[1]
        XCTAssertLessThan(roundedCorner.red, 140)
        XCTAssertGreaterThan(roundedCorner.green + roundedCorner.blue, 120)
        XCTAssertGreaterThan(screenCenter.red, 140)
    }

    func testMergerExportsCameraOnlyRemoteCameraWithoutTimelineGap() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.camera]
        settings.selectedCameraID = RemoteCameraProviderID.make(for: "iphone-15-pro")
        settings.framesPerSecond = 30
        settings.outputResolution = .p720

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        try FileManager.default.createDirectory(at: take.scratchDirectory, withIntermediateDirectories: true)

        try writeTestMovie(
            url: take.cameraURL,
            codec: .h264,
            color: (blue: 0, green: 0, red: 255, alpha: 255)
        )
        try writeRemoteCameraManifest(
            for: take.cameraURL,
            hostTimelineStartTime: 1_000_000_000,
            estimatedHostStartTime: 1_200_000_000
        )

        let outputURL = try await Merger.exportFinalVideo(take: take, settings: settings)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testMergerTrimsCameraOnlyRemotePrerollBeforeTimelineStart() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.camera]
        settings.selectedCameraID = RemoteCameraProviderID.make(for: "iphone-15-pro")
        settings.framesPerSecond = 30
        settings.outputResolution = .p720

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        try FileManager.default.createDirectory(at: take.scratchDirectory, withIntermediateDirectories: true)

        try writeTestMovie(
            url: take.cameraURL,
            codec: .h264,
            color: (blue: 0, green: 0, red: 255, alpha: 255)
        )
        try writeRemoteCameraManifest(
            for: take.cameraURL,
            hostTimelineStartTime: 1_300_000_000,
            estimatedHostStartTime: 1_100_000_000
        )

        let outputURL = try await Merger.exportFinalVideo(take: take, settings: settings)
        let asset = AVURLAsset(url: outputURL)
        let duration = try await asset.load(.duration)

        XCTAssertEqual(duration.seconds, 0.2, accuracy: 0.08)
    }

    func testMergerExportsWithTimelineBackgroundChanges() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.screen]
        settings.framesPerSecond = 30
        settings.outputResolution = .p720
        settings.canvasBackgroundStyle = .black

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        try FileManager.default.createDirectory(at: take.scratchDirectory, withIntermediateDirectories: true)
        try writeTestMovie(
            url: take.screenURL,
            codec: .h264,
            color: (blue: 255, green: 0, red: 0, alpha: 255)
        )

        var changedSettings = settings
        changedSettings.canvasBackgroundStyle = .aurora
        let outputURL = try await Merger.exportFinalVideo(
            take: take,
            settings: settings,
            sceneEvents: [
                RecordingSceneEvent(time: 0, scene: RecordingScene(settings: settings)),
                RecordingSceneEvent(time: 0.2, scene: RecordingScene(settings: changedSettings))
            ]
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testMergerMutesRemoteCameraEmbeddedAudio() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.camera]
        settings.selectedCameraID = RemoteCameraProviderID.make(for: "iphone-15-pro")
        settings.framesPerSecond = 30
        settings.outputResolution = .p720

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        try FileManager.default.createDirectory(at: take.scratchDirectory, withIntermediateDirectories: true)

        try writeTestMovie(
            url: take.cameraURL,
            codec: .h264,
            color: (blue: 0, green: 0, red: 255, alpha: 255),
            includeAudio: true
        )

        let outputURL = try await Merger.exportFinalVideo(take: take, settings: settings)
        let asset = AVURLAsset(url: outputURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        XCTAssertEqual(audioTracks.count, 0)
    }

    func testMergerKeepsMicrophoneAudioWithRemoteCameraEmbeddedAudio() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.camera, .microphone]
        settings.selectedCameraID = RemoteCameraProviderID.make(for: "iphone-15-pro")
        settings.framesPerSecond = 30
        settings.outputResolution = .p720

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        try FileManager.default.createDirectory(at: take.scratchDirectory, withIntermediateDirectories: true)

        try writeTestMovie(
            url: take.cameraURL,
            codec: .h264,
            color: (blue: 0, green: 0, red: 255, alpha: 255),
            includeAudio: true
        )
        try writeSilentAudioFile(url: take.audioURL)

        let outputURL = try await Merger.exportFinalVideo(take: take, settings: settings)
        let asset = AVURLAsset(url: outputURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        XCTAssertEqual(audioTracks.count, 1)
    }

    func testMergerFailsWhenMicrophoneIsEnabledButAudioSidecarIsMissing() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.camera, .microphone]
        settings.selectedCameraID = RemoteCameraProviderID.make(for: "iphone-15-pro")
        settings.framesPerSecond = 30
        settings.outputResolution = .p720

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        try FileManager.default.createDirectory(at: take.scratchDirectory, withIntermediateDirectories: true)
        try writeTestMovie(
            url: take.cameraURL,
            codec: .h264,
            color: (blue: 0, green: 0, red: 255, alpha: 255),
            includeAudio: true
        )

        do {
            _ = try await Merger.exportFinalVideo(take: take, settings: settings)
            XCTFail("Expected export to fail when microphone audio is required but missing")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Microphone audio"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: take.finalVideoURL.path))
    }

    func testCameraBackgroundPostProcessorWritesTransparentIntermediate() async throws {
        let directory = temporaryDirectory()
        let inputURL = directory.appendingPathComponent("camera.mov")
        let outputURL = directory.appendingPathComponent("camera-background-removed.mov")

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try writeTestMovie(
            url: inputURL,
            codec: .h264,
            color: (blue: 0, green: 0, red: 255, alpha: 255)
        )

        let processedURL = try await CameraBackgroundPostProcessor.removeBackground(
            from: inputURL,
            to: outputURL
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: processedURL.path))

        let asset = AVURLAsset(url: processedURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1)
    }

    @MainActor
    func testTakeFinalizerKeepsRecoveryFilesWhenNoVideoFramesWereCaptured() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.screen, .camera]

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        let finalizer = TakeFinalizer(
            speechTranscriber: SpeechTranscriber(),
            titleGenerator: TitleGenerator(),
            fileStore: store
        )

        let outcome = await finalizer.finalize(
            take: take,
            settings: settings,
            captureSummary: CaptureSourceRunSummary(completions: [
                .screen: .empty(take.screenURL),
                .camera: .empty(take.cameraURL)
            ])
        )

        guard case .recoveryFiles(let recoveryTake, let reason) = outcome else {
            return XCTFail("Expected recovery files outcome")
        }
        XCTAssertEqual(reason, "No video frames captured")
        XCTAssertEqual(recoveryTake.scratchDirectory, take.scratchDirectory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: take.scratchDirectory.path))
        XCTAssertTrue(outcome.userMessage.contains("No video frames captured"))
    }

    @MainActor
    func testTakeFinalizerPreservesSourceTakeAfterSuccessfulExport() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.savesSourceFiles = true
        settings.enabledSources = [.screen]
        settings.framesPerSecond = 30
        settings.outputResolution = .p720

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        try writeTestMovie(
            url: take.screenURL,
            codec: .h264,
            color: (blue: 255, green: 0, red: 0, alpha: 255)
        )

        let finalizer = TakeFinalizer(
            speechTranscriber: SpeechTranscriber(),
            titleGenerator: TitleGenerator(),
            fileStore: store
        )
        let outcome = await finalizer.finalize(
            take: take,
            settings: settings,
            captureSummary: CaptureSourceRunSummary(completions: [
                .screen: .wrote(take.screenURL)
            ])
        )

        guard case .saved(let outputURL, let sourceDirectory) = outcome else {
            return XCTFail("Expected saved outcome")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertEqual(sourceDirectory, take.scratchDirectory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: take.scratchDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: take.screenURL.path))

        let data = try Data(contentsOf: take.sourceManifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(SourceTakeManifest.self, from: data)
        XCTAssertEqual(manifest.finalVideoPath, outputURL.path)
        XCTAssertTrue(outcome.userMessage.contains("Source take:"))
    }

    @MainActor
    func testTakeFinalizerKeepsRecoveryFilesWhenMicrophoneAudioIsMissing() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.camera, .microphone]
        settings.selectedCameraID = RemoteCameraProviderID.make(for: "iphone-15-pro")
        settings.framesPerSecond = 30
        settings.outputResolution = .p720

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        try writeTestMovie(
            url: take.cameraURL,
            codec: .h264,
            color: (blue: 0, green: 0, red: 255, alpha: 255),
            includeAudio: true
        )

        let finalizer = TakeFinalizer(
            speechTranscriber: SpeechTranscriber(),
            titleGenerator: TitleGenerator(),
            fileStore: store
        )
        let outcome = await finalizer.finalize(
            take: take,
            settings: settings,
            captureSummary: CaptureSourceRunSummary(completions: [
                .camera: .wrote(take.cameraURL),
                .microphone: .empty(take.audioURL)
            ])
        )

        guard case .recoveryFiles(let recoveryTake, let reason) = outcome else {
            return XCTFail("Expected recovery files when microphone audio is missing")
        }
        XCTAssertEqual(recoveryTake.scratchDirectory, take.scratchDirectory)
        XCTAssertTrue(reason.contains("Microphone audio"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: take.scratchDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: take.finalVideoURL.path))
    }

    @MainActor
    func testTakeFinalizerSavesVideoWhenMicrophoneStopFailed() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.camera, .microphone]
        settings.selectedCameraID = RemoteCameraProviderID.make(for: "iphone-15-pro")
        settings.framesPerSecond = 30
        settings.outputResolution = .p720

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        try writeTestMovie(
            url: take.cameraURL,
            codec: .h264,
            color: (blue: 0, green: 0, red: 255, alpha: 255),
            includeAudio: true
        )

        let finalizer = TakeFinalizer(
            speechTranscriber: SpeechTranscriber(),
            titleGenerator: TitleGenerator(),
            fileStore: store
        )
        let outcome = await finalizer.finalize(
            take: take,
            settings: settings,
            captureSummary: CaptureSourceRunSummary(
                completions: [
                    .camera: .wrote(take.cameraURL)
                ],
                stopFailures: [
                    .microphone: RecorderError.microphoneUnavailable.localizedDescription
                ]
            )
        )

        guard case .saved(let outputURL, _) = outcome else {
            return XCTFail("Expected saved video when microphone stop already failed")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        let asset = AVURLAsset(url: outputURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(audioTracks.count, 0)
    }

    @MainActor
    func testTakeFinalizerKeepsRecoveryFilesWhenVisibleIPhoneCameraMediaIsMissing() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.screen, .camera, .microphone]
        settings.selectedCameraID = RemoteCameraProviderID.make(for: "iphone-15-pro")
        settings.framesPerSecond = 30
        settings.outputResolution = .p720

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        try writeTestMovie(
            url: take.screenURL,
            codec: .h264,
            color: (blue: 255, green: 0, red: 0, alpha: 255)
        )

        let finalizer = TakeFinalizer(
            speechTranscriber: SpeechTranscriber(),
            titleGenerator: TitleGenerator(),
            fileStore: store
        )
        let outcome = await finalizer.finalize(
            take: take,
            settings: settings,
            captureSummary: CaptureSourceRunSummary(
                completions: [
                    .screen: .wrote(take.screenURL),
                    .camera: .empty(take.cameraURL)
                ],
                stopFailures: [
                    .microphone: RecorderError.microphoneUnavailable.localizedDescription
                ]
            )
        )

        guard case .recoveryFiles(let recoveryTake, let reason) = outcome else {
            return XCTFail("Expected recovery files when visible iPhone camera media is missing")
        }

        XCTAssertEqual(recoveryTake.scratchDirectory, take.scratchDirectory)
        XCTAssertTrue(reason.contains("iPhone camera video"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: take.scratchDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: take.finalVideoURL.path))
    }

    @MainActor
    func testTakeFinalizerExportsScreenOnlyWhenHiddenIPhoneCameraMediaIsMissing() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.screen, .camera]
        settings.hiddenSources = [.camera]
        settings.selectedCameraID = RemoteCameraProviderID.make(for: "iphone-15-pro")
        settings.framesPerSecond = 30
        settings.outputResolution = .p720

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        try writeTestMovie(
            url: take.screenURL,
            codec: .h264,
            color: (blue: 255, green: 0, red: 0, alpha: 255)
        )

        let finalizer = TakeFinalizer(
            speechTranscriber: SpeechTranscriber(),
            titleGenerator: TitleGenerator(),
            fileStore: store
        )
        let outcome = await finalizer.finalize(
            take: take,
            settings: settings,
            captureSummary: CaptureSourceRunSummary(
                completions: [
                    .screen: .wrote(take.screenURL),
                    .camera: .empty(take.cameraURL)
                ],
                stopFailures: [:]
            )
        )

        guard case .saved(let outputURL, _) = outcome else {
            return XCTFail("Expected screen-only export to ignore hidden iPhone camera media")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    @MainActor
    func testTakeFinalizerMergesAudioForTransparentCameraOnlyExport() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.camera, .systemAudio]
        settings.removesCameraBackgroundAfterRecording = true
        settings.framesPerSecond = 30
        settings.outputResolution = .p720

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        try writeTestMovie(
            url: take.cameraURL,
            codec: .h264,
            color: (blue: 0, green: 0, red: 255, alpha: 255)
        )
        try writeSilentAudioFile(url: take.systemAudioURL)

        let finalizer = TakeFinalizer(
            speechTranscriber: SpeechTranscriber(),
            titleGenerator: TitleGenerator(),
            fileStore: store
        )
        let outcome = await finalizer.finalize(
            take: take,
            settings: settings,
            captureSummary: CaptureSourceRunSummary(completions: [
                .camera: .wrote(take.cameraURL),
                .systemAudio: .wrote(take.systemAudioURL)
            ])
        )

        guard case .saved(let outputURL, _) = outcome else {
            return XCTFail("Expected saved outcome")
        }

        XCTAssertFalse(outputURL.lastPathComponent.contains("transparent-webcam"))
        let asset = AVURLAsset(url: outputURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(audioTracks.count, 1)
    }

    @MainActor
    func testTakeFinalizerKeepsWrittenSystemAudioDespiteStopWarning() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.screen, .systemAudio]
        settings.framesPerSecond = 30
        settings.outputResolution = .p720

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        try writeTestMovie(
            url: take.screenURL,
            codec: .h264,
            color: (blue: 255, green: 0, red: 0, alpha: 255)
        )
        try writeSilentAudioFile(url: take.systemAudioURL)

        let finalizer = TakeFinalizer(
            speechTranscriber: SpeechTranscriber(),
            titleGenerator: TitleGenerator(),
            fileStore: store
        )
        let outcome = await finalizer.finalize(
            take: take,
            settings: settings,
            captureSummary: CaptureSourceRunSummary(
                completions: [
                    .screen: .wrote(take.screenURL),
                    .systemAudio: .wrote(take.systemAudioURL)
                ],
                stopFailures: [
                    .systemAudio: RecorderError.captureStreamStopped("display went away").localizedDescription
                ]
            )
        )

        guard case .saved(let outputURL, _) = outcome else {
            return XCTFail("Expected saved outcome")
        }

        let asset = AVURLAsset(url: outputURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(audioTracks.count, 1)
    }

    @MainActor
    func testTakeFinalizerSavesVideoWhenSystemAudioHasNoSamples() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.screen, .systemAudio]
        settings.framesPerSecond = 30
        settings.outputResolution = .p720

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        try writeTestMovie(
            url: take.screenURL,
            codec: .h264,
            color: (blue: 255, green: 0, red: 0, alpha: 255)
        )

        let finalizer = TakeFinalizer(
            speechTranscriber: SpeechTranscriber(),
            titleGenerator: TitleGenerator(),
            fileStore: store
        )
        let outcome = await finalizer.finalize(
            take: take,
            settings: settings,
            captureSummary: CaptureSourceRunSummary(completions: [
                .screen: .wrote(take.screenURL),
                .systemAudio: .empty(take.systemAudioURL)
            ])
        )

        guard case .saved(let outputURL, _) = outcome else {
            return XCTFail("Expected saved outcome")
        }

        let asset = AVURLAsset(url: outputURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(audioTracks.count, 0)
    }

    @MainActor
    func testTakeFinalizerMutesRemoteCameraEmbeddedAudio() async throws {
        var settings = RecordingSettings()
        settings.outputDirectory = temporaryDirectory()
        settings.enabledSources = [.camera]
        settings.selectedCameraID = RemoteCameraProviderID.make(for: "iphone-15-pro")
        settings.framesPerSecond = 30
        settings.outputResolution = .p720

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        try writeTestMovie(
            url: take.cameraURL,
            codec: .h264,
            color: (blue: 0, green: 0, red: 255, alpha: 255),
            includeAudio: true
        )

        let finalizer = TakeFinalizer(
            speechTranscriber: SpeechTranscriber(),
            titleGenerator: TitleGenerator(),
            fileStore: store
        )
        let outcome = await finalizer.finalize(
            take: take,
            settings: settings,
            captureSummary: CaptureSourceRunSummary(completions: [
                .camera: .wrote(take.cameraURL)
            ])
        )

        guard case .saved(let outputURL, _) = outcome else {
            return XCTFail("Expected saved outcome")
        }

        let asset = AVURLAsset(url: outputURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(audioTracks.count, 0)
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlitzRecorderTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func writeTestMovie(
        url: URL,
        codec: AVVideoCodecType,
        color: (blue: UInt8, green: UInt8, red: UInt8, alpha: UInt8),
        includeAudio: Bool = false,
        frameCount: Int = 12
    ) throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: codec,
                AVVideoWidthKey: 64,
                AVVideoHeightKey: 64
            ]
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 64,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )
        XCTAssertTrue(writer.canAdd(input))
        writer.add(input)
        let audioInput: AVAssetWriterInput?
        if includeAudio {
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 64_000
                ]
            )
            XCTAssertTrue(writer.canAdd(input))
            writer.add(input)
            audioInput = input
        } else {
            audioInput = nil
        }
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        guard let pool = adaptor.pixelBufferPool else {
            throw RecorderError.writerNotReady
        }
        for frame in 0..<frameCount {
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            guard let pixelBuffer else {
                throw RecorderError.writerNotReady
            }
            fill(pixelBuffer, color: color)
            while !input.isReadyForMoreMediaData {
                usleep(1_000)
            }
            XCTAssertTrue(adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30)))
        }

        if let audioInput {
            let sampleBuffer = try makeSilentAudioSampleBuffer(
                presentationTime: .zero,
                frames: 24_000
            )
            while !audioInput.isReadyForMoreMediaData {
                usleep(1_000)
            }
            XCTAssertTrue(audioInput.append(sampleBuffer))
            audioInput.markAsFinished()
        }
        input.markAsFinished()
        let expectation = expectation(description: "movie writer finished")
        writer.finishWriting {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        if let error = writer.error {
            throw error
        }
    }

    private func writeCoordinateGradientMovie(
        url: URL,
        width: Int,
        height: Int,
        frameCount: Int = 12
    ) throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height
            ]
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )
        XCTAssertTrue(writer.canAdd(input))
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        guard let pool = adaptor.pixelBufferPool else {
            throw RecorderError.writerNotReady
        }
        for frame in 0..<frameCount {
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            guard let pixelBuffer else {
                throw RecorderError.writerNotReady
            }
            fillCoordinateGradient(pixelBuffer)
            while !input.isReadyForMoreMediaData {
                usleep(1_000)
            }
            XCTAssertTrue(adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30)))
        }

        input.markAsFinished()
        let expectation = expectation(description: "gradient movie writer finished")
        writer.finishWriting {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        if let error = writer.error {
            throw error
        }
    }

    private func samplePixelColors(
        in url: URL,
        normalizedPoints: [CGPoint],
        at time: CMTime
    ) async throws -> [(red: Int, green: Int, blue: Int, alpha: Int)] {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 30)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 30)

        let image = try await generator.image(at: time).image
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw RecorderError.exportUnavailable
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        return normalizedPoints.map { point in
            let x = min(width - 1, max(0, Int((point.x * CGFloat(width)).rounded(.down))))
            let y = min(height - 1, max(0, Int((point.y * CGFloat(height)).rounded(.down))))
            let index = (y * width + x) * 4
            return (
                red: Int(pixels[index]),
                green: Int(pixels[index + 1]),
                blue: Int(pixels[index + 2]),
                alpha: Int(pixels[index + 3])
            )
        }
    }

    private func fill(
        _ pixelBuffer: CVPixelBuffer,
        color: (blue: UInt8, green: UInt8, red: UInt8, alpha: UInt8)
    ) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        for y in 0..<height {
            let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                let index = x * 4
                row[index] = color.blue
                row[index + 1] = color.green
                row[index + 2] = color.red
                row[index + 3] = color.alpha
            }
        }
    }

    private func fillCoordinateGradient(_ pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                buffer[offset] = 0
                buffer[offset + 1] = UInt8((CGFloat(y) / CGFloat(max(1, height - 1)) * 255).rounded())
                buffer[offset + 2] = UInt8((CGFloat(x) / CGFloat(max(1, width - 1)) * 255).rounded())
                buffer[offset + 3] = 255
            }
        }
    }

    private func makeVideoSampleBuffer(presentationTime: CMTime) throws -> CMSampleBuffer {
        var pixelBuffer: CVPixelBuffer?
        let pixelBufferStatus = CVPixelBufferCreate(
            kCFAllocatorDefault,
            64,
            64,
            kCVPixelFormatType_32BGRA,
            [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true
            ] as CFDictionary,
            &pixelBuffer
        )
        guard pixelBufferStatus == kCVReturnSuccess, let pixelBuffer else {
            throw RecorderError.writerNotReady
        }

        fill(pixelBuffer, color: (blue: 255, green: 0, red: 0, alpha: 255))

        var formatDescription: CMVideoFormatDescription?
        let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard formatStatus == noErr, let formatDescription else {
            throw RecorderError.writerNotReady
        }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr, let sampleBuffer else {
            throw RecorderError.writerNotReady
        }
        return sampleBuffer
    }

    private func makeSilentAudioSampleBuffer(
        presentationTime: CMTime,
        frames: CMItemCount,
        sampleRate: Double = 48_000
    ) throws -> CMSampleBuffer {
        var description = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var formatDescription: CMAudioFormatDescription?
        let formatStatus = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &description,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard formatStatus == noErr, let formatDescription else {
            throw RecorderError.writerNotReady
        }

        let byteCount = Int(frames) * Int(description.mBytesPerFrame)
        var blockBuffer: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: byteCount,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: byteCount,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard blockStatus == noErr, let blockBuffer else {
            throw RecorderError.writerNotReady
        }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: frames,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr, let sampleBuffer else {
            throw RecorderError.writerNotReady
        }
        return sampleBuffer
    }

    private func writeSilentAudioFile(url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 64_000
            ]
        )
        XCTAssertTrue(writer.canAdd(input))
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        let sampleBuffer = try makeSilentAudioSampleBuffer(
            presentationTime: .zero,
            frames: 24_000
        )
        while !input.isReadyForMoreMediaData {
            usleep(1_000)
        }
        XCTAssertTrue(input.append(sampleBuffer))
        input.markAsFinished()

        let expectation = expectation(description: "audio writer finished")
        writer.finishWriting {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        if let error = writer.error {
            throw error
        }
    }

    private func writeRemoteCameraManifest(
        for cameraURL: URL,
        hostTimelineStartTime: UInt64,
        estimatedHostStartTime: UInt64
    ) throws {
        let manifest = RemoteCameraTransferManifest(
            takeID: UUID(),
            recordingID: UUID(),
            fileName: cameraURL.lastPathComponent,
            byteCount: 0,
            durationSeconds: 0.4,
            hostTimelineStartTime: hostTimelineStartTime,
            estimatedHostStartTime: estimatedHostStartTime
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(manifest)
        try data.write(
            to: cameraURL.deletingPathExtension().appendingPathExtension("remote-camera-manifest.json"),
            options: .atomic
        )
    }
}

private final class NoopScreenCaptureRecorder: ScreenCaptureRecording {
    func start(url: URL, settings: RecordingSettings, filter pickedFilter: SCContentFilter?, timelineStartTime: CMTime?) async throws {}
    func update(settings: RecordingSettings, filter pickedFilter: SCContentFilter?) async throws {}
    func pause() {}
    func resume() {}
    func stop() async throws -> MediaWriterCompletion { .empty() }
}

private final class OrderedCaptureEvents {
    private(set) var started: [CaptureSource] = []
    private(set) var stopped: [CaptureSource] = []

    func start(_ source: CaptureSource) {
        started.append(source)
    }

    func stop(_ source: CaptureSource) {
        stopped.append(source)
    }
}

private final class OrderedScreenCaptureRecorder: ScreenCaptureRecording {
    private let order: OrderedCaptureEvents

    init(order: OrderedCaptureEvents) {
        self.order = order
    }

    func start(url: URL, settings: RecordingSettings, filter pickedFilter: SCContentFilter?, timelineStartTime: CMTime?) async throws {
        order.start(.screen)
    }

    func update(settings: RecordingSettings, filter pickedFilter: SCContentFilter?) async throws {}
    func pause() {}
    func resume() {}

    func stop() async throws -> MediaWriterCompletion {
        order.stop(.screen)
        return .empty()
    }
}

private final class OrderedCameraCaptureRecorder: CameraCaptureRecording {
    private let order: OrderedCaptureEvents

    init(order: OrderedCaptureEvents) {
        self.order = order
    }

    func start(url: URL, settings: RecordingSettings, timelineStartTime: CMTime?) async throws {
        order.start(.camera)
    }

    func pause() {}
    func resume() {}

    func stop() async throws -> MediaWriterCompletion {
        order.stop(.camera)
        return .empty()
    }
}

private final class OrderedMicrophoneCaptureRecorder: MicrophoneCaptureRecording {
    private let order: OrderedCaptureEvents

    init(order: OrderedCaptureEvents) {
        self.order = order
    }

    func start(url: URL, settings: RecordingSettings, timelineStartTime: CMTime?) async throws {
        order.start(.microphone)
    }

    func pause() {}
    func resume() {}

    func stop() async throws -> MediaWriterCompletion {
        order.stop(.microphone)
        return .empty()
    }
}

private final class OrderedSystemAudioCaptureRecorder: SystemAudioCaptureRecording {
    private let order: OrderedCaptureEvents

    init(order: OrderedCaptureEvents) {
        self.order = order
    }

    func start(url: URL, settings: RecordingSettings, timelineStartTime: CMTime?) async throws {
        order.start(.systemAudio)
    }

    func pause() {}
    func resume() {}

    func stop() async throws -> MediaWriterCompletion {
        order.stop(.systemAudio)
        return .empty()
    }
}

private final class SpyScreenCaptureRecorder: ScreenCaptureRecording {
    private(set) var startCount = 0
    private(set) var updateCount = 0
    private(set) var stopCount = 0
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    private(set) var updatedSettings: RecordingSettings?
    private(set) var capturedTimelineStartTime: CMTime?
    let stopCompletion: MediaWriterCompletion

    init(stopCompletion: MediaWriterCompletion) {
        self.stopCompletion = stopCompletion
    }

    func start(url: URL, settings: RecordingSettings, filter pickedFilter: SCContentFilter?, timelineStartTime: CMTime?) async throws {
        startCount += 1
        capturedTimelineStartTime = timelineStartTime
    }

    func update(settings: RecordingSettings, filter pickedFilter: SCContentFilter?) async throws {
        updateCount += 1
        updatedSettings = settings
    }

    func pause() {
        pauseCount += 1
    }

    func resume() {
        resumeCount += 1
    }

    func stop() async throws -> MediaWriterCompletion {
        stopCount += 1
        return stopCompletion
    }
}

private final class FailingCameraCaptureRecorder: CameraCaptureRecording {
    let error: Error
    private(set) var startCount = 0

    init(error: Error) {
        self.error = error
    }

    func start(url: URL, settings: RecordingSettings, timelineStartTime: CMTime?) async throws {
        startCount += 1
        throw error
    }

    func pause() {}
    func resume() {}
    func stop() async throws -> MediaWriterCompletion { .empty() }
}

private final class SpyRemoteCameraCaptureRecorder: RemoteCameraCaptureRecording {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    private(set) var capturedHostTimelineStartTime: UInt64?
    private(set) var capturedStartSettings: RecordingSettings?
    private(set) var capturedStopSettings: RecordingSettings?
    let completion: MediaWriterCompletion

    init(completion: MediaWriterCompletion) {
        self.completion = completion
    }

    func startRemoteCamera(take: RecordingTake, settings: RecordingSettings, hostTimelineStartTime: UInt64) async throws {
        startCount += 1
        capturedStartSettings = settings
        capturedHostTimelineStartTime = hostTimelineStartTime
    }

    func pauseRemoteCamera() {
        pauseCount += 1
    }

    func resumeRemoteCamera() {
        resumeCount += 1
    }

    func stopRemoteCamera(take: RecordingTake, settings: RecordingSettings) async throws -> MediaWriterCompletion {
        stopCount += 1
        capturedStopSettings = settings
        return completion
    }
}

private final class SpyMicrophoneCaptureRecorder: MicrophoneCaptureRecording {
    private(set) var startCount = 0
    private(set) var capturedTimelineStartTime: CMTime?

    func start(url: URL, settings: RecordingSettings, timelineStartTime: CMTime?) async throws {
        startCount += 1
        capturedTimelineStartTime = timelineStartTime
    }

    func pause() {}
    func resume() {}
    func stop() async throws -> MediaWriterCompletion { .empty() }
}

private final class FailingStartMicrophoneCaptureRecorder: MicrophoneCaptureRecording {
    let error: Error
    private(set) var stopCount = 0

    init(error: Error) {
        self.error = error
    }

    func start(url: URL, settings: RecordingSettings, timelineStartTime: CMTime?) async throws {
        throw error
    }

    func pause() {}
    func resume() {}

    func stop() async throws -> MediaWriterCompletion {
        stopCount += 1
        return .empty()
    }
}

private final class FailingStopMicrophoneCaptureRecorder: MicrophoneCaptureRecording {
    let error: Error
    private(set) var stopCount = 0

    init(error: Error) {
        self.error = error
    }

    func start(url: URL, settings: RecordingSettings, timelineStartTime: CMTime?) async throws {}
    func pause() {}
    func resume() {}

    func stop() async throws -> MediaWriterCompletion {
        stopCount += 1
        throw error
    }
}

private final class NoopSystemAudioCaptureRecorder: SystemAudioCaptureRecording {
    func start(url: URL, settings: RecordingSettings, timelineStartTime: CMTime?) async throws {}
    func pause() {}
    func resume() {}
    func stop() async throws -> MediaWriterCompletion { .empty() }
}

private final class CompletedStopFailureSystemAudioCaptureRecorder: SystemAudioCaptureRecording {
    let completion: MediaWriterCompletion
    let error: Error

    init(completion: MediaWriterCompletion, error: Error) {
        self.completion = completion
        self.error = error
    }

    func start(url: URL, settings: RecordingSettings, timelineStartTime: CMTime?) async throws {}
    func pause() {}
    func resume() {}

    func stop() async throws -> MediaWriterCompletion {
        throw CaptureSourceStopFailure(completion: completion, underlyingError: error)
    }
}
