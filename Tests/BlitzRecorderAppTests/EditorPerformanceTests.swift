import AppKit
import AVFoundation
import XCTest
@testable import BlitzRecorderApp

@MainActor
final class EditorPerformanceTests: XCTestCase {
    func testTimelineLookupBenchmark() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BLITZRECORDER_EDITOR_BENCHMARK"] == "1")
        for cutCount in [0, 100, 1_000] {
            let map = TimelineTimeMap(takeDuration: TimelineTimeMap.time(3_600), cuts: (0..<cutCount).map {
                .init(start: Double($0) * 3 + 1, end: Double($0) * 3 + 2, kind: .silence, source: .automatic)
            })
            var checksum = 0.0
            for iteration in 0..<4 {
                let start = ProcessInfo.processInfo.systemUptime
                for index in 0..<3_000 {
                    let takeTime = Double((index * 1_543) % 36_000) / 10
                    let outputTime = map.outputTime(forTake: TimelineTimeMap.time(takeTime))
                    checksum += map.takeTime(forOutput: outputTime).seconds
                    checksum += map.removedRange(containing: takeTime)?.duration ?? 0
                    checksum += map.keptRange(containingOutput: outputTime)?.takeStart.seconds ?? 0
                }
                let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1_000_000 / 3_000
                print("EDITOR_PERF lookup cuts=\(cutCount) iteration=\(iteration) us=\(elapsed)")
            }
            XCTAssertGreaterThan(checksum, 0)
        }
    }

    func testScenePreviewBenchmark() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BLITZRECORDER_EDITOR_BENCHMARK"] == "1")
        _ = NSApplication.shared
        let fixture = try SyntheticRecording()
        try await fixture.writeVideo(.init(url: fixture.take.screenURL, frames: 120))
        try FileManager.default.copyItem(at: fixture.take.screenURL, to: fixture.take.cameraURL)
        var settings = fixture.settings
        settings.enabledSources.insert(.camera)
        for sceneCount in [1, 24, 120] {
            let events = (0..<sceneCount).map { index in
                var scene = RecordingScene(settings: settings)
                scene.screenCropAmount = CGPoint(x: Double(index % 3) * 0.1, y: 0)
                return RecordingSceneEvent(time: Double(index) * 4 / Double(sceneCount), scene: scene)
            }
            try TakeFileStore().writeRecordingProject(for: fixture.take, settings: settings,
                sceneEvents: events, finalVideoURL: nil)
            let project = try TakeFileStore().loadRecordingProject(at: fixture.take.projectURL)
            let controller = EditorPlaybackController()
            await controller.load(project: project, baseSettings: settings)
            XCTAssertTrue(controller.isReady)
            defer { controller.teardown() }
            for hidden in [false, true] {
                controller.setHidden(hidden, kind: .camera)
                for iteration in 0..<4 {
                    var checksum = 0.0
                    let start = ProcessInfo.processInfo.systemUptime
                    for index in 0..<600 {
                        checksum += Double(controller.scene(at: Double(index % 240) / 60)?.screenCropAmount.x ?? 0)
                    }
                    let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1_000_000 / 600
                    print("EDITOR_PERF scene count=\(sceneCount) hidden=\(hidden) iteration=\(iteration) us=\(elapsed)")
                    if sceneCount > 1 { XCTAssertGreaterThan(checksum, 0) }
                    if hidden, sceneCount == 120, iteration > 0 {
                        XCTAssertLessThan(elapsed, 500, "Unchanged preview plans must fit the frame budget")
                    }
                }
            }
        }
    }
}
