import AppKit
import AVFoundation
import Darwin
import XCTest
@testable import BlitzRecorderApp

@MainActor
final class RecordingWorkloadTests: XCTestCase {
    private var environment: [String: String] { ProcessInfo.processInfo.environment }

    func testBenchmarks() async throws {
        try XCTSkipUnless(environment["BLITZRECORDER_WORKLOAD"] == "benchmark", "Run Scripts/run-resilience.py benchmark")
        _ = NSApplication.shared
        var results: [[String: Any]] = []
        for cameraEnabled in [false, true] {
            let fixture = try SyntheticRecording()
            try await fixture.writeVideo(.init(url: fixture.take.screenURL, frames: 90))
            var settings = fixture.settings
            if cameraEnabled {
                try FileManager.default.copyItem(at: fixture.take.screenURL, to: fixture.take.cameraURL)
                settings.enabledSources.insert(.camera)
                settings.outputResolution = .p1080
            }
            try TakeFileStore().writeRecordingProject(
                for: fixture.take, settings: settings,
                sceneEvents: [RecordingSceneEvent(time: 0, scene: RecordingScene(settings: settings))],
                finalVideoURL: nil
            )
            let project = try TakeFileStore().loadRecordingProject(at: fixture.take.projectURL)
            for iteration in 0..<4 {
                print("Benchmark camera=\(cameraEnabled) iteration=\(iteration): load and playback")
                let controller = EditorPlaybackController()
                let loadStart = ProcessInfo.processInfo.systemUptime
                await controller.load(project: project, baseSettings: settings)
                print("Benchmark: player loaded")
                let loadMS = (ProcessInfo.processInfo.systemUptime - loadStart) * 1_000
                XCTAssertTrue(controller.isReady)
                let view = EditorCompositedPlayerView(frame: CGRect(x: 0, y: 0, width: 960, height: 540))
                view.controller = controller
                view.configure(renderSize: controller.renderSize)
                view.refresh()
                print("Benchmark: canvas ready")
                let refreshStart = ProcessInfo.processInfo.systemUptime
                for _ in 0..<3_000 { view.refresh() }
                let refreshUS = (ProcessInfo.processInfo.systemUptime - refreshStart) * 1_000_000 / 3_000
                controller.play(from: 0)
                print("Benchmark: playback started")
                try await Task.sleep(nanoseconds: 150_000_000)
                XCTAssertGreaterThan(controller.displayTime(), 0)
                view.teardown()
                controller.teardown()
                print("Benchmark camera=\(cameraEnabled) iteration=\(iteration): export")
                let exportStart = ProcessInfo.processInfo.systemUptime
                let output = try await Merger.exportFinalVideo(take: fixture.take, settings: settings)
                let exportSeconds = ProcessInfo.processInfo.systemUptime - exportStart
                let inspection = try await SyntheticRecording.inspectVideo(output)
                XCTAssertEqual(inspection.frames, 90, accuracy: 1)
                XCTAssertEqual(inspection.duration, 3, accuracy: 0.1)
                if iteration > 0 {
                    results.append([
                        "fixture": cameraEnabled ? "screen-camera-1080p30" : "screen-720p30",
                        "iteration": iteration,
                        "editor_load_ms": loadMS,
                        "unchanged_layout_us": refreshUS,
                        "export_seconds": exportSeconds,
                        "export_realtime_factor": inspection.duration / exportSeconds
                    ])
                }
                try FileManager.default.removeItem(at: output)
            }
        }
        try saveMetrics(["kind": "benchmark", "fixture_version": 1, "samples": results])
    }

    func testSustainedSyntheticRecording() async throws {
        try XCTSkipUnless(environment["BLITZRECORDER_WORKLOAD"] == "soak", "Run Scripts/run-resilience.py soak")
        let seconds = try XCTUnwrap(environment["BLITZRECORDER_SOAK_SECONDS"].flatMap(Double.init))
        guard seconds >= 10, seconds <= 10_800 else { throw RecorderError.writerNotReady }
        let fixture = try SyntheticRecording()
        let video = try VideoFileWriter(
            url: fixture.take.screenURL, width: 640, height: 360,
            bitrate: 1_000_000, fps: 30, outputFormat: .mov
        )
        let audio = try AudioSampleFileWriter(url: fixture.take.audioURL)
        let expectedFrames = Int(seconds * 30)
        let start = ProcessInfo.processInfo.systemUptime
        var memory: [Double] = []
        for frame in 0..<expectedFrames {
            let delay = start + Double(frame) / 30 - ProcessInfo.processInfo.systemUptime
            if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            try autoreleasepool {
                video.append(try fixture.videoSample(at: frame))
                audio.append(try fixture.audioSample(at: frame))
            }
            if frame.isMultiple(of: 30) {
                memory.append(try footprintMB())
                if frame.isMultiple(of: 900) { print("Synthetic recording: \(frame / 30)s / \(Int(seconds))s") }
            }
        }
        let videoCompletion = try await video.finish()
        let audioCompletion = try await audio.finish()
        XCTAssertTrue(videoCompletion.wroteMedia)
        XCTAssertTrue(audioCompletion.wroteMedia)
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let inspection = try await SyntheticRecording.inspectVideo(fixture.take.screenURL)
        let audioAsset = AVURLAsset(url: fixture.take.audioURL)
        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(audioTracks.count, 1)
        let audioDuration = try await audioAsset.load(.duration).seconds
        let lostFrameRatio = 1 - Double(inspection.frames) / Double(expectedFrames)
        let warmup = min(30, memory.count / 3)
        let growth = (memory.suffix(5).max() ?? 0) - (memory.dropFirst(warmup).prefix(5).min() ?? 0)
        let metrics: [String: Any] = [
            "kind": "soak", "fixture_version": 1, "requested_seconds": seconds,
            "elapsed_seconds": elapsed, "expected_frames": expectedFrames, "decoded_frames": inspection.frames,
            "lost_frame_ratio": lostFrameRatio, "video_seconds": inspection.duration, "audio_seconds": audioDuration,
            "av_drift_seconds": abs(inspection.duration - audioDuration), "footprint_mb": memory,
            "steady_memory_growth_mb": growth
        ]
        try saveMetrics(metrics)
        XCTAssertLessThanOrEqual(lostFrameRatio, 0.01)
        XCTAssertEqual(inspection.duration, seconds, accuracy: 0.1)
        XCTAssertEqual(audioDuration, inspection.duration, accuracy: 0.1)
        XCTAssertLessThanOrEqual(growth, 64)
        XCTAssertLessThanOrEqual(elapsed, seconds * 1.15 + 1)
    }

    func testFullDiskPreservesRecoveryFiles() async throws {
        try XCTSkipUnless(environment["BLITZRECORDER_WORKLOAD"] == "disk", "Run Scripts/run-resilience.py disk")
        let mount = URL(fileURLWithPath: try XCTUnwrap(environment["BLITZRECORDER_TEST_VOLUME"]))
        let values = try mount.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeUUIDStringKey])
        let host = try FileManager.default.temporaryDirectory.resourceValues(forKeys: [.volumeUUIDStringKey])
        guard let capacity = values.volumeTotalCapacity, capacity <= 128 * 1_024 * 1_024,
              values.volumeUUIDString != host.volumeUUIDString,
              try String(contentsOf: mount.appendingPathComponent(".resilience-volume"), encoding: .utf8) == "isolated-test-volume" else {
            throw RecorderError.writerNotReady
        }
        let fixture = try SyntheticRecording(root: mount.appendingPathComponent(UUID().uuidString))
        try await fixture.writeVideo(.init(url: fixture.take.screenURL, frames: 30))
        let original = try Data(contentsOf: fixture.take.screenURL)
        let fillerURL = mount.appendingPathComponent("fill")
        FileManager.default.createFile(atPath: fillerURL.path, contents: nil)
        let filler = try FileHandle(forWritingTo: fillerURL)
        defer {
            try? filler.close()
            try? FileManager.default.removeItem(at: fillerURL)
        }
        let bytes = Data(repeating: 1, count: 4_096)
        var filled = false
        for _ in 0..<(128 * 1_024 * 1_024 / bytes.count) {
            do { try filler.write(contentsOf: bytes) }
            catch {
                let failure = error as NSError
                let underlying = failure.userInfo[NSUnderlyingErrorKey] as? NSError
                guard failure.code == NSFileWriteOutOfSpaceError || underlying?.code == Int(ENOSPC) else { throw error }
                filled = true
                break
            }
        }
        XCTAssertTrue(filled, "The isolated volume must reach ENOSPC")
        let outcome = await TakeFinalizer().finalize(
            take: fixture.take, settings: fixture.settings,
            captureSummary: CaptureSourceRunSummary(completions: [.screen: .wrote(fixture.take.screenURL)])
        )
        guard case .recoveryFiles = outcome else { return XCTFail("Disk-full save must retain recovery files") }
        XCTAssertEqual(try Data(contentsOf: fixture.take.screenURL), original)
        XCTAssertNoThrow(try TakeFileStore().loadRecordingProject(at: fixture.take.projectURL))
        try saveMetrics(["kind": "disk", "enospc_observed": filled, "source_preserved": true])
    }

    private func footprintMB() throws -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { throw RecorderError.writerNotReady }
        return Double(info.phys_footprint) / 1_048_576
    }

    private func saveMetrics(_ values: [String: Any]) throws {
        let directory = URL(fileURLWithPath: try XCTUnwrap(environment["BLITZRECORDER_RESULT_DIRECTORY"]))
        let data = try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent("metrics.json"), options: .atomic)
    }
}
