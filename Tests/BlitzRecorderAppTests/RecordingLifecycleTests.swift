import AVFoundation
import AudioToolbox
import BlitzRecorderCore
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
        XCTAssertEqual(microphoneRecorder.startCount, 0)
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

        try await run.start()
        _ = await run.stop()

        XCTAssertEqual(screenRecorder.capturedTimelineStartTime, timelineStart)
        XCTAssertEqual(microphoneRecorder.capturedTimelineStartTime, timelineStart)
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
        XCTAssertEqual(screenRecorder.stopCount, 1)
        XCTAssertEqual(microphoneRecorder.stopCount, 1)
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
        includeAudio: Bool = false
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
        for frame in 0..<12 {
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

    private func makeSilentAudioSampleBuffer(
        presentationTime: CMTime,
        frames: CMItemCount
    ) throws -> CMSampleBuffer {
        var description = AudioStreamBasicDescription(
            mSampleRate: 48_000,
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
            duration: CMTime(value: 1, timescale: 48_000),
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
}

private final class NoopScreenCaptureRecorder: ScreenCaptureRecording {
    func start(url: URL, settings: RecordingSettings, filter pickedFilter: SCContentFilter?, timelineStartTime: CMTime?) async throws {}
    func pause() {}
    func resume() {}
    func stop() async throws -> MediaWriterCompletion { .empty() }
}

private final class SpyScreenCaptureRecorder: ScreenCaptureRecording {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var capturedTimelineStartTime: CMTime?
    let stopCompletion: MediaWriterCompletion

    init(stopCompletion: MediaWriterCompletion) {
        self.stopCompletion = stopCompletion
    }

    func start(url: URL, settings: RecordingSettings, filter pickedFilter: SCContentFilter?, timelineStartTime: CMTime?) async throws {
        startCount += 1
        capturedTimelineStartTime = timelineStartTime
    }

    func pause() {}
    func resume() {}

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

private final class SpyMicrophoneCaptureRecorder: MicrophoneCaptureRecording {
    private(set) var startCount = 0
    private(set) var capturedTimelineStartTime: CMTime?

    func start(url: URL, settings: RecordingSettings, timelineStartTime: CMTime?) throws {
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

    func start(url: URL, settings: RecordingSettings, timelineStartTime: CMTime?) throws {
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

    func start(url: URL, settings: RecordingSettings, timelineStartTime: CMTime?) throws {}
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
