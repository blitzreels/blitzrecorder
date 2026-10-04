import AVFoundation
import XCTest
@testable import BlitzRecorderApp

final class VideoProjectImporterTests: XCTestCase {
    func test4KHEVCImportPreservesResolutionAndFrameRate() async throws {
        let fixture = try SyntheticRecording()
        let source = fixture.root.appendingPathComponent("DJI_4K.mp4")
        let writer = try AVAssetWriter(outputURL: source, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: 3840, AVVideoHeightKey: 2160
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, 3840, 2160, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer), kCVReturnSuccess)
        let pixels = try XCTUnwrap(buffer)
        SyntheticRecording.fill(pixels)
        guard writer.startWriting() else { throw writer.error ?? RecorderError.writerNotReady }
        writer.startSession(atSourceTime: .zero)
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        for frame in 0..<4 {
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing, ProcessInfo.processInfo.systemUptime < deadline else {
                    writer.cancelWriting()
                    throw writer.error ?? RecorderError.writerNotReady
                }
                try await Task.sleep(for: .milliseconds(1))
            }
            XCTAssertTrue(adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: 60)))
        }
        writer.endSession(atSourceTime: CMTime(value: 4, timescale: 60))
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        let project = try await VideoProjectImporter().importVideo(.init(url: source, settings: fixture.settings, onProgress: { _ in }))
        XCTAssertEqual(project.settings.outputResolution, OutputResolution.p2160.rawValue)
        XCTAssertEqual(project.settings.framesPerSecond, 60)
        let imported = try XCTUnwrap(project.sources.first { $0.role == "camera" })
        XCTAssertEqual(try Data(contentsOf: source), try Data(contentsOf: URL(fileURLWithPath: imported.path)))
        let metadata = try XCTUnwrap(VideoProjectImporter.Metadata.load(for: project))
        XCTAssertEqual(metadata.width, 3840)
        XCTAssertEqual(metadata.height, 2160)
    }

    @MainActor
    func testImportOpensAnEditableProjectWithoutChangingCaptureSettings() async throws {
        let fixture = try SyntheticRecording()
        let source = fixture.root.appendingPathComponent("Course lesson.mov")
        try await fixture.writeVideo(.init(url: source, frames: 10))
        let suite = "VideoImportNavigation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        RecordingSettingsStore.save(fixture.settings, defaults: defaults)
        let coordinator = RecorderCoordinator(accessController: AccessController(defaults: defaults), defaults: defaults)
        let vm = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
        vm.studioMode = .projects
        let previousSources = vm.settings.enabledSources
        let previousLayout = vm.settings.layout
        await vm.importVideo(source)
        XCTAssertEqual(vm.studioMode, .edit)
        XCTAssertEqual(vm.lastExportedProject?.title, "Course lesson")
        XCTAssertEqual(vm.settings.enabledSources, previousSources)
        XCTAssertEqual(vm.settings.layout, previousLayout)
        XCTAssertEqual(vm.state, .idle)
        XCTAssertNil(vm.videoImportProgress)
        XCTAssertNil(vm.videoImportError)
        let project = try XCTUnwrap(vm.lastExportedProject)
        let edits = try XCTUnwrap(EditorTimeRange.removing(.init(range: .init(start: 0.1, end: 0.2),
            edits: project.edits, takeDuration: 1.0 / 3)))
        XCTAssertTrue(vm.applyTimelineEdits(.init(edits: edits, actionName: "Cut imported video")))
        XCTAssertTrue(vm.canUndoEditor)
        vm.undoEditor()
        XCTAssertEqual(vm.lastExportedProject?.edits, project.edits)
    }

    func testImportPreservesVideoAndExtractsAudioForEditingAndTranscription() async throws {
        let fixture = try SyntheticRecording()
        let source = try await makeMovie(.init(fixture: fixture, portrait: false, audio: true))
        let original = try Data(contentsOf: source)
        let store = TakeFileStore()
        let project = try await VideoProjectImporter().importVideo(.init(url: source, settings: fixture.settings, onProgress: { _ in }))
        XCTAssertEqual(project.title, "DJI_001")
        XCTAssertEqual(project.settings.layout, CaptureLayout.horizontal.rawValue)
        XCTAssertEqual(Set(project.settings.enabledSources), Set([CaptureSource.camera.rawValue, CaptureSource.microphone.rawValue]))
        XCTAssertNil(project.finalVideoPath)
        XCTAssertTrue(project.exports.isEmpty)
        let camera = try XCTUnwrap(project.sources.first { $0.role == "camera" })
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: camera.path)), original)
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertNotEqual(camera.path, source.path)
        let audio = try XCTUnwrap(project.sources.first { $0.role == "microphone" })
        let audioTracks = try await AVURLAsset(url: URL(fileURLWithPath: audio.path)).loadTracks(withMediaType: .audio)
        XCTAssertEqual(audioTracks.count, 1)
        let metadata = try XCTUnwrap(VideoProjectImporter.Metadata.load(for: project))
        XCTAssertEqual(metadata.width, 640)
        XCTAssertEqual(metadata.height, 360)
        XCTAssertEqual(metadata.duration, 2, accuracy: 0.05)
        XCTAssertEqual(metadata.framesPerSecond, 30, accuracy: 0.1)
        XCTAssertTrue(store.loadProjectHistory(settings: fixture.settings).entries.contains { $0.id == project.id })
        try FileManager.default.removeItem(at: source)
        let reopened = try store.loadRecordingProject(at: URL(fileURLWithPath: project.projectPath))
        XCTAssertEqual(reopened, project)
        let prepared = try await TranscriptionAudioPreparer().prepare(.project(URL(fileURLWithPath: project.projectPath)))
        defer { for track in prepared.tracks { try? FileManager.default.removeItem(at: track.audioURL) } }
        XCTAssertEqual(prepared.tracks.count, 1)
        XCTAssertGreaterThan(prepared.tracks[0].duration, 1.9)

        let settings = store.recordingSettings(from: reopened, baseSettings: fixture.settings, outputFormat: .mp4)
        let take = store.recordingTake(from: reopened, settings: settings, outputFormat: .mp4)
        let cuts = [TimelineCut(start: 0.5, end: 1, kind: .manual, source: .user)]
        let playback = try await Merger.editorPlaybackComposition(take: take, settings: settings,
            sceneEvents: store.sceneEvents(from: reopened), cuts: cuts)
        XCTAssertEqual(playback.duration.seconds, 1.5, accuracy: 0.05)
        let output = fixture.root.appendingPathComponent("import-export.mp4")
        var edits = TimelineEdits.empty
        edits.cuts = cuts
        _ = try store.updateProjectTimelineEdits(.init(projectURL: URL(fileURLWithPath: reopened.projectPath),
            edits: edits, baseSettings: fixture.settings))
        XCTAssertEqual(try store.loadRecordingProject(at: URL(fileURLWithPath: reopened.projectPath)).edits, edits)
        let exported = try await Merger.exportFinalVideo(.init(take: take, settings: settings,
            sceneEvents: store.sceneEvents(from: reopened), backgroundMusic: nil, destinationURL: output,
            progressHandler: nil, timelineEdits: edits))
        let exportedAsset = AVURLAsset(url: exported)
        let exportedDuration = try await exportedAsset.load(.duration)
        let exportedAudio = try await exportedAsset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(exportedDuration.seconds, 1.5, accuracy: 0.05)
        XCTAssertEqual(exportedAudio.count, 1)
    }

    func testPortraitTransformAndSilentVideoSurviveImportAndExport() async throws {
        let fixture = try SyntheticRecording()
        let source = try await makeMovie(.init(fixture: fixture, portrait: true, audio: false))
        let project = try await VideoProjectImporter().importVideo(.init(url: source, settings: fixture.settings, onProgress: { _ in }))
        XCTAssertEqual(project.settings.layout, CaptureLayout.vertical.rawValue)
        XCTAssertEqual(project.settings.enabledSources, [CaptureSource.camera.rawValue])
        let metadata = try XCTUnwrap(VideoProjectImporter.Metadata.load(for: project))
        XCTAssertEqual(metadata.width, 360, accuracy: 0.01)
        XCTAssertEqual(metadata.height, 640, accuracy: 0.01)
        XCTAssertFalse(project.sources.contains { $0.role == "microphone" && $0.exists })
        let store = TakeFileStore()
        let settings = store.recordingSettings(from: project, baseSettings: fixture.settings, outputFormat: .mp4)
        let take = store.recordingTake(from: project, settings: settings, outputFormat: .mp4)
        let output = fixture.root.appendingPathComponent("portrait-export.mp4")
        _ = try await Merger.exportFinalVideo(.init(take: take, settings: settings,
            sceneEvents: store.sceneEvents(from: project), backgroundMusic: nil, destinationURL: output,
            progressHandler: nil, timelineEdits: .empty))
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: output))
        generator.appliesPreferredTrackTransform = true
        let frame = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
        XCTAssertEqual(frame.width, 720)
        XCTAssertEqual(frame.height, 1280)
        var pixel = [UInt8](repeating: 0, count: 4)
        let center = try XCTUnwrap(frame.cropping(to: CGRect(x: 360, y: 640, width: 1, height: 1)))
        pixel.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(center, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        XCTAssertGreaterThan(Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2]), 150)
    }

    func testFailedAndCancelledImportsLeaveNoPartialProject() async throws {
        let fixture = try SyntheticRecording()
        let invalid = fixture.root.appendingPathComponent("broken.mp4")
        try Data("not a video".utf8).write(to: invalid)
        let store = TakeFileStore()
        let history = store.loadProjectHistory(settings: fixture.settings)
        let root = store.scratchRoot(for: fixture.settings)
        let existing = try FileManager.default.contentsOfDirectory(atPath: root.path)
        do {
            _ = try await VideoProjectImporter().importVideo(.init(url: invalid, settings: fixture.settings, onProgress: { _ in }))
            XCTFail("Unreadable media must not create a project")
        } catch { }
        let source = try await makeMovie(.init(fixture: fixture, portrait: false, audio: false))
        let task = Task {
            try await VideoProjectImporter().importVideo(.init(url: source, settings: fixture.settings, onProgress: { progress in
                if progress.stage == "Copying video" { withUnsafeCurrentTask { $0?.cancel() } }
            }))
        }
        do {
            _ = try await task.value
            XCTFail("Cancellation must abort import")
        } catch is CancellationError { }
        XCTAssertEqual(store.loadProjectHistory(settings: fixture.settings), history)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), existing)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testRepeatedImportsCreateIndependentProjects() async throws {
        let fixture = try SyntheticRecording()
        let source = try await makeMovie(.init(fixture: fixture, portrait: false, audio: false))
        let first = try await VideoProjectImporter().importVideo(.init(url: source, settings: fixture.settings, onProgress: { _ in }))
        let second = try await VideoProjectImporter().importVideo(.init(url: source, settings: fixture.settings, onProgress: { _ in }))
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first.takeDirectoryPath, second.takeDirectoryPath)
        XCTAssertEqual(first.title, second.title)
    }

    private struct MovieRequest {
        let fixture: SyntheticRecording
        let portrait: Bool
        let audio: Bool
    }

    private func makeMovie(_ request: MovieRequest) async throws -> URL {
        let url = request.fixture.root.appendingPathComponent("DJI_001.mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 640, AVVideoHeightKey: 360
        ])
        if request.portrait { video.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 360, ty: 0) }
        writer.add(video)
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192_000
        ])
        if request.audio { writer.add(audio) }
        guard writer.startWriting() else { throw writer.error ?? RecorderError.writerNotReady }
        writer.startSession(atSourceTime: .zero)
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        var videoFrame = 0
        var audioFrame = request.audio ? 0 : 60
        while videoFrame < 60 || audioFrame < 60 {
            guard writer.status == .writing, ProcessInfo.processInfo.systemUptime < deadline else {
                writer.cancelWriting()
                throw writer.error ?? RecorderError.writerNotReady
            }
            if videoFrame < 60, video.isReadyForMoreMediaData {
                guard video.append(try request.fixture.videoSample(at: videoFrame)) else { throw writer.error ?? RecorderError.writerNotReady }
                videoFrame += 1
                if videoFrame == 60 { video.markAsFinished() }
            }
            if audioFrame < 60, audio.isReadyForMoreMediaData {
                guard audio.append(try request.fixture.audioSample(at: audioFrame)) else { throw writer.error ?? RecorderError.writerNotReady }
                audioFrame += 1
                if audioFrame == 60 { audio.markAsFinished() }
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? RecorderError.writerNotReady }
        return url
    }
}
