import AppKit
import AVFoundation
import XCTest
@testable import BlitzRecorderApp

@MainActor
final class AppResponsivenessTests: XCTestCase {
    private func requireBenchmark() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BLITZRECORDER_APP_BENCHMARK"] == "1")
    }

    func testLongCursorProjectMainActorResponsiveness() async throws {
        try requireBenchmark()
        _ = NSApplication.shared
        let fixture = try SyntheticRecording()
        try await fixture.writeVideo(.init(url: fixture.take.screenURL, frames: 90))
        let samples = (0..<216_000).map { index in
            RecordingCursorSample(time: Double(index) / 60, x: Double(index % 300) / 300,
                                  y: 0.5, clicked: index.isMultiple(of: 120), rendered: true)
        }
        try JSONEncoder().encode(RecordingCursorTrack(version: 2, samples: samples))
            .write(to: fixture.take.scratchDirectory.appendingPathComponent("cursor-track.json"))
        let project = try TakeFileStore().loadRecordingProject(at: fixture.take.projectURL)
        let controller = EditorPlaybackController()
        defer { controller.teardown() }
        var longestGap = 0.0
        let heartbeat = Task { @MainActor in
            var previous = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(5)) } catch { break }
                let now = ProcessInfo.processInfo.systemUptime
                longestGap = max(longestGap, now - previous)
                previous = now
            }
        }
        await Task.yield()
        let start = ProcessInfo.processInfo.systemUptime
        await controller.load(project: project, baseSettings: fixture.settings)
        await Task.yield()
        heartbeat.cancel()
        await heartbeat.value
        print("APP_PERF cursor load_ms=\((ProcessInfo.processInfo.systemUptime-start)*1000) main_gap_ms=\(longestGap*1000)")
        XCTAssertTrue(controller.isReady)
        XCTAssertNotNil(controller.cursorTrack.sample(.init(time: 1, style: .standard)))
        XCTAssertLessThan(longestGap, 0.1, "Cursor loading must keep the main actor responsive")
    }

    func testRealLongWaveformReopen() async throws {
        try requireBenchmark()
        let path = ProcessInfo.processInfo.environment["BLITZRECORDER_BENCHMARK_AUDIO"]
        try XCTSkipIf(path == nil)
        let url = URL(fileURLWithPath: try XCTUnwrap(path))
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path))
        for iteration in 0..<2 {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            let start = ProcessInfo.processInfo.systemUptime
            let waveform = await EditorAudioWaveform.load(.init(asset: asset, duration: duration))
            print("APP_PERF waveform iteration=\(iteration) duration=\(duration) seconds=\(ProcessInfo.processInfo.systemUptime-start)")
            XCTAssertFalse(try XCTUnwrap(waveform).overview.isEmpty)
        }
    }

    func testRealRecordingSeekBursts() async throws {
        try requireBenchmark()
        let path = ProcessInfo.processInfo.environment["BLITZRECORDER_BENCHMARK_PROJECT"]
        try XCTSkipIf(path == nil)
        let project = try TakeFileStore().loadRecordingProject(at: URL(fileURLWithPath: try XCTUnwrap(path)))
        let controller = EditorPlaybackController()
        defer { controller.teardown() }
        await controller.load(project: project, baseSettings: RecordingSettings())
        XCTAssertTrue(controller.isReady)
        let item = try XCTUnwrap(controller.videoPlayer(for: .screen)?.currentItem)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        item.add(output)
        for iteration in 0..<5 {
            let target = controller.duration * (iteration.isMultiple(of: 2) ? 0.71 : 0.29)
            let start = ProcessInfo.processInfo.systemUptime
            for index in 0..<100 {
                controller.scrub(to: target * Double(index + 1) / 100)
            }
            controller.endScrub()
            let deadline = start + 5
            var received = false
            var displayed = CMTime.invalid
            while ProcessInfo.processInfo.systemUptime < deadline {
                let time = CMTime(seconds: target, preferredTimescale: 600)
                if output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: &displayed) != nil,
                   abs(displayed.seconds - target) < 0.11 {
                    received = true
                    break
                }
                try await Task.sleep(for: .milliseconds(5))
            }
            print("APP_PERF seeking iteration=\(iteration) frame_ms=\((ProcessInfo.processInfo.systemUptime-start)*1000) received=\(received)")
            XCTAssertTrue(received, "The requested frame must be decoded after the seek burst")
        }
        item.remove(output)
    }

    func testFourKTextOverlayRefresh() async throws {
        try requireBenchmark()
        _ = NSApplication.shared
        let fixture = try SyntheticRecording()
        try await fixture.writeVideo(.init(url: fixture.take.screenURL, frames: 90))
        let edits = TimelineEdits(cuts: [], textOverlays: (0..<3).map {
            TextOverlay(start: 0, end: 3, text: "Title \($0)",
                        frame: CGRect(x: 0.1, y: 0.15 + Double($0) * 0.2, width: 0.8, height: 0.15),
                        style: .title, fadeSeconds: 0)
        }, zoom: .empty)
        let project = try TakeFileStore().updateProjectTimelineEdits(.init(
            projectURL: fixture.take.projectURL, edits: edits, baseSettings: fixture.settings))
        let controller = EditorPlaybackController()
        let view = EditorCompositedPlayerView(frame: CGRect(x: 0, y: 0, width: 960, height: 540))
        defer { view.teardown(); controller.teardown() }
        await controller.load(project: project, baseSettings: fixture.settings)
        XCTAssertTrue(controller.isReady)
        view.controller = controller
        view.configure(renderSize: CGSize(width: 3840, height: 2160))
        view.refresh()
        let start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<30 { view.refresh() }
        let milliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1000 / 30
        print("APP_PERF text_4k refresh_ms=\(milliseconds)")
        XCTAssertLessThan(milliseconds, 5, "Unchanged titles must fit comfortably in the frame budget")
    }

    func testRealRecordingOneMinuteExport() async throws {
        try requireBenchmark()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BLITZRECORDER_EXPORT_BENCHMARK"] == "1")
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["BLITZRECORDER_BENCHMARK_PROJECT"])
        let store = TakeFileStore()
        let project = try store.loadRecordingProject(at: URL(fileURLWithPath: path))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var settings = store.recordingSettings(from: project, baseSettings: RecordingSettings(), outputFormat: .mp4)
        settings.outputResolution = .p1080
        settings.outputDirectory = root
        let take = store.recordingTake(from: project, settings: settings, outputFormat: .mp4)
        let sources = project.sources.map { URL(fileURLWithPath: $0.path) } + [URL(fileURLWithPath: path)]
        let before = sources.map { MediaFileFingerprint(url: $0) }
        let events = store.sceneEvents(from: project)
        let playback = try await Merger.editorPlaybackComposition(take: take, settings: settings, sceneEvents: events)
        let excerptStart = min(10, max(0, playback.duration.seconds - 60))
        let duration = min(60, playback.duration.seconds - excerptStart)
        var edits = project.edits
        edits.cuts = [
            .init(start: 0, end: excerptStart, kind: .manual, source: .user),
            .init(start: excerptStart + duration, end: playback.duration.seconds, kind: .manual, source: .user)
        ]
        let start = ProcessInfo.processInfo.systemUptime
        let output = try await Merger.exportFinalVideo(.init(take: take, settings: settings, sceneEvents: events,
            backgroundMusic: nil, destinationURL: root.appendingPathComponent("benchmark.mp4"),
            progressHandler: nil, timelineEdits: edits))
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let inspection = try await SyntheticRecording.inspectVideo(output)
        print("APP_PERF export start_s=\(excerptStart) media_s=\(inspection.duration) wall_s=\(elapsed) frames=\(inspection.frames)")
        XCTAssertEqual(inspection.duration, duration, accuracy: 0.1)
        XCTAssertGreaterThan(inspection.frames, 1)
        XCTAssertEqual(sources.map { MediaFileFingerprint(url: $0) }, before)
    }

}
