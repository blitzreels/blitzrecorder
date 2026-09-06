import AVFoundation
import Darwin
import XCTest
@testable import BlitzRecorderApp

final class RecordingResilienceTests: XCTestCase {
    func testConcurrentSourceFinalizationWaitsForReadableMedia() async throws {
        let fixture = try SyntheticRecording()
        let video = try VideoFileWriter(
            url: fixture.take.screenURL, width: 640, height: 360,
            bitrate: 1_000_000, fps: 30, outputFormat: .mov
        )
        let audio = try AudioSampleFileWriter(url: fixture.take.audioURL)
        for frame in 0..<10 {
            video.append(try fixture.videoSample(at: frame))
            audio.append(try fixture.audioSample(at: frame))
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    let videoResult = try await video.finish()
                    let audioResult = try await audio.finish()
                    for result in [videoResult, audioResult] {
                        XCTAssertTrue(result.wroteMedia)
                        let asset = AVURLAsset(url: try XCTUnwrap(result.url))
                        let duration = try await asset.load(.duration)
                        XCTAssertGreaterThan(duration.seconds, 0)
                    }
                }
            }
            try await group.waitForAll()
        }
    }

    func testConcurrentDirectFinalizationReturnsOneCompletedDestination() async throws {
        let fixture = try SyntheticRecording()
        let existing = Data("existing export".utf8)
        try existing.write(to: fixture.take.finalVideoURL)
        let writer = try DirectMovieWriter(take: fixture.take, settings: fixture.settings)
        writer.appendVideo(sourceTime: CMClockGetTime(CMClockGetHostTimeClock())) { buffer in
            SyntheticRecording.fill(buffer)
            return true
        }
        let results = try await withThrowingTaskGroup(of: MediaWriterCompletion.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    let result = try await writer.finish()
                    let url = try XCTUnwrap(result.url)
                    XCTAssertNotEqual(url, fixture.take.finalVideoURL)
                    let duration = try await AVURLAsset(url: url).load(.duration)
                    XCTAssertGreaterThan(duration.seconds, 0)
                    return result
                }
            }
            var results: [MediaWriterCompletion] = []
            for try await result in group { results.append(result) }
            return results
        }
        XCTAssertEqual(Set(results.compactMap(\.url)).count, 1)
        let repeated = try await writer.finish()
        XCTAssertEqual(repeated, results.first)
        XCTAssertEqual(try Data(contentsOf: fixture.take.finalVideoURL), existing)
    }

    @MainActor
    func testDamagedVideoExportPreservesSourceAndRecoveryProject() async throws {
        let fixture = try SyntheticRecording()
        let damaged = Data("truncated movie".utf8)
        try damaged.write(to: fixture.take.screenURL)
        var settings = fixture.settings
        settings.savesSourceFiles = false
        let outcome = await TakeFinalizer().finalize(
            take: fixture.take,
            settings: settings,
            captureSummary: CaptureSourceRunSummary(completions: [.screen: .wrote(fixture.take.screenURL)])
        )
        guard case .recoveryFiles = outcome else { return XCTFail("Expected recoverable export failure") }
        XCTAssertEqual(try Data(contentsOf: fixture.take.screenURL), damaged)
        XCTAssertNoThrow(try TakeFileStore().loadRecordingProject(at: fixture.take.projectURL))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.take.finalVideoURL.path))
    }

    @MainActor
    func testCancelledExportKeepsSourceAndExistingDestination() async throws {
        let fixture = try SyntheticRecording()
        try await fixture.writeVideo(.init(url: fixture.take.screenURL, frames: 90))
        let original = try Data(contentsOf: fixture.take.screenURL)
        let existing = Data("existing export".utf8)
        try existing.write(to: fixture.take.finalVideoURL)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await Merger.exportFinalVideo(take: fixture.take, settings: fixture.settings)
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled export reported success")
        } catch {
            XCTAssertEqual(try Data(contentsOf: fixture.take.screenURL), original)
            XCTAssertEqual(try Data(contentsOf: fixture.take.finalVideoURL), existing)
            let files = try FileManager.default.contentsOfDirectory(atPath: fixture.take.finalVideoURL.deletingLastPathComponent().path)
            XCTAssertFalse(files.contains { $0.hasPrefix(".blitzrecorder-export-") })
        }
    }

    @MainActor
    func testCancellationDuringExportStopsWithoutPublishingPartialMedia() async throws {
        let fixture = try SyntheticRecording()
        try await fixture.writeVideo(.init(url: fixture.take.screenURL, frames: 300))
        let started = expectation(description: "export began producing frames")
        var reportedStart = false
        let task = Task {
            try await Merger.exportFinalVideo(
                take: fixture.take, settings: fixture.settings,
                progressHandler: { progress in
                    if progress > 0, progress < 1, !reportedStart {
                        reportedStart = true
                        started.fulfill()
                    }
                }
            )
        }
        await fulfillment(of: [started], timeout: 30)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled export reported success")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.take.finalVideoURL.path))
            let files = try FileManager.default.contentsOfDirectory(atPath: fixture.take.finalVideoURL.deletingLastPathComponent().path)
            XCTAssertFalse(files.contains { $0.hasPrefix(".blitzrecorder-export-") })
            let inspection = try await SyntheticRecording.inspectVideo(fixture.take.screenURL)
            XCTAssertEqual(inspection.frames, 300)
        }
    }

    @MainActor
    func testRapidProjectLoadsAndTeardownCannotRestoreStalePlayback() async throws {
        let fixture = try SyntheticRecording()
        try await fixture.writeVideo(.init(url: fixture.take.screenURL, frames: 30))
        let project = try TakeFileStore().loadRecordingProject(at: fixture.take.projectURL)
        let controller = EditorPlaybackController()
        for _ in 0..<10 {
            let load = Task { await controller.load(project: project, baseSettings: fixture.settings) }
            await Task.yield()
            load.cancel()
            controller.teardown()
            await load.value
            XCTAssertFalse(controller.isReady)
            XCTAssertNil(controller.videoPlayer(for: .screen))
        }
        await controller.load(project: project, baseSettings: fixture.settings)
        XCTAssertTrue(controller.isReady)
        XCTAssertEqual(controller.videoPlayer(for: .screen)?.status, .readyToPlay)
        controller.play(from: 0)
        XCTAssertTrue(controller.isPlaying)
        controller.teardown()
    }
}

final class SyntheticRecording {
    struct VideoRequest {
        let url: URL
        let frames: Int
    }

    let root: URL
    let settings: RecordingSettings
    let take: RecordingTake
    let pixels: CVPixelBuffer

    init(root: URL? = nil) throws {
        self.root = root ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var settings = RecordingSettings()
        settings.outputDirectory = self.root
        settings.enabledSources = [.screen]
        settings.savesSourceFiles = true
        settings.layout = .horizontal
        settings.outputResolution = .p720
        self.settings = settings
        take = try TakeFileStore().createTake(settings: settings)
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            nil, 640, 360, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer
        )
        guard status == kCVReturnSuccess, let buffer else { throw RecorderError.writerNotReady }
        pixels = buffer
        Self.fill(buffer)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    static func fill(_ buffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        if let address = CVPixelBufferGetBaseAddress(buffer) {
            memset(address, 127, CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer))
        }
    }

    func videoSample(at frame: Int) throws -> CMSampleBuffer {
        var description: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: nil, imageBuffer: pixels, formatDescriptionOut: &description
        )
        guard status == noErr, let description else { throw RecorderError.writerNotReady }
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMTime(value: Int64(frame), timescale: 30),
            decodeTimeStamp: .invalid
        )
        var sample: CMSampleBuffer?
        let result = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: nil, imageBuffer: pixels, formatDescription: description,
            sampleTiming: &timing, sampleBufferOut: &sample
        )
        guard result == noErr, let sample else { throw RecorderError.writerNotReady }
        return sample
    }

    func audioSample(at frame: Int) throws -> CMSampleBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600)!
        pcm.frameLength = 1_600
        for channel in 0..<2 {
            memset(pcm.floatChannelData![channel], 0, 1_600 * MemoryLayout<Float>.size)
        }
        var sample: CMSampleBuffer?
        let status = CMAudioSampleBufferCreateWithPacketDescriptions(
            allocator: nil, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil,
            refcon: nil, formatDescription: format.formatDescription, sampleCount: 1_600,
            presentationTimeStamp: CMTime(value: Int64(frame * 1_600), timescale: 48_000),
            packetDescriptions: nil, sampleBufferOut: &sample
        )
        guard status == noErr, let sample else { throw RecorderError.writerNotReady }
        let result = CMSampleBufferSetDataBufferFromAudioBufferList(
            sample, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: 0, bufferList: pcm.audioBufferList
        )
        guard result == noErr else { throw RecorderError.writerNotReady }
        CMSampleBufferSetDataReady(sample)
        return sample
    }

    func writeVideo(_ request: VideoRequest) async throws {
        let writer = try AVAssetWriter(outputURL: request.url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 640, AVVideoHeightKey: 360
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? RecorderError.writerNotReady }
        writer.startSession(atSourceTime: .zero)
        let deadline = ProcessInfo.processInfo.systemUptime + 30
        for frame in 0..<request.frames {
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing, ProcessInfo.processInfo.systemUptime < deadline else {
                    writer.cancelWriting()
                    throw writer.error ?? RecorderError.writerNotReady
                }
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            guard adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else {
                throw writer.error ?? RecorderError.writerNotReady
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? RecorderError.writerNotReady }
    }

    static func inspectVideo(_ url: URL) async throws -> (frames: Int, duration: Double) {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? RecorderError.writerNotReady }
        var frames = 0
        var last = CMTime.invalid
        while let sample = output.copyNextSampleBuffer() {
            let time = CMSampleBufferGetPresentationTimeStamp(sample)
            XCTAssertTrue(time.isNumeric)
            if last.isValid { XCTAssertGreaterThan(CMTimeCompare(time, last), 0) }
            last = time
            frames += 1
        }
        guard reader.status == .completed else { throw reader.error ?? RecorderError.writerNotReady }
        return (frames, try await asset.load(.duration).seconds)
    }
}
