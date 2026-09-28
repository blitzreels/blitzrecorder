import AppKit
import AVFoundation
import SwiftUI
import XCTest
@testable import BlitzRecorderApp

final class RealEditingJourneyTests: XCTestCase {
    @MainActor
    func testCutExtendUndoReopenAndExportRealParallelSources() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["BLITZRECORDER_JOURNEY_PROJECT"],
              let output = environment["BLITZRECORDER_JOURNEY_OUTPUT"] else {
            throw XCTSkip("Provide an isolated real project copy and validation output directory.")
        }
        let projectURL = URL(fileURLWithPath: path)
        let root = URL(fileURLWithPath: output)
        XCTAssertTrue(projectURL.path.hasPrefix(root.path + "/"))
        guard projectURL.path.hasPrefix(root.path + "/") else { return }
        let store = TakeFileStore()
        let original = try store.loadRecordingProject(at: projectURL)
        let sourceURLs = original.sources.filter { $0.exists }.map { URL(fileURLWithPath: $0.path) }
        let fingerprints = sourceURLs.map { MediaFileFingerprint(url: $0) }
        let suite = "RealEditingJourney.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = RecorderCoordinator(accessController: AccessController(defaults: defaults), defaults: defaults)
        let vm = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
        let automatic = vm.transcriptionController.isAutomaticEnabled
        vm.transcriptionController.isAutomaticEnabled = false
        defer { vm.transcriptionController.isAutomaticEnabled = automatic; vm.prepareForWindowClose() }
        vm.settings.outputDirectory = root
        vm.lastExportedSourceTakeURL = projectURL.deletingLastPathComponent()
        vm.refreshLastExportedProject()
        vm.studioMode = .edit
        let playback = EditorPlaybackController()
        defer { playback.teardown() }
        await playback.load(project: original, baseSettings: vm.settings)
        XCTAssertTrue(playback.isReady, playback.loadError ?? "")
        let duration = playback.duration
        XCTAssertGreaterThan(duration, 12)
        var initial = original.edits
        initial.cuts = [.init(start: 12, end: duration, kind: .manual, source: .user)]
        initial.videoSplits = []
        initial.silenceRemovalApplied = false
        initial.silenceOverrides = []
        XCTAssertTrue(vm.applyTimelineEdits(.init(edits: initial, actionName: "Prepare excerpt")))
        let cut = try XCTUnwrap(EditorTimeRange.removingTogether(.init(ranges: [.init(start: 2, end: 4)],
            kind: .manual, edits: initial, takeDuration: duration)))
        XCTAssertTrue(vm.applyTimelineEdits(.init(edits: cut, actionName: "Delete range")))
        let extended = try XCTUnwrap(EditorVideoCuts.extendingRight(.init(edits: cut,
            clip: .init(start: 0, end: 2), nextClipStart: 4, duration: duration, delta: 1)))
        XCTAssertTrue(vm.applyTimelineEdits(.init(edits: extended, actionName: "Extend clip")))
        vm.undoEditor()
        XCTAssertEqual(vm.lastExportedProject?.edits, cut)
        vm.redoEditor()
        XCTAssertEqual(vm.lastExportedProject?.edits, extended)
        let reopened = try store.loadRecordingProject(at: projectURL)
        XCTAssertEqual(reopened.edits, extended)
        await playback.load(project: reopened, baseSettings: vm.settings)
        XCTAssertTrue(playback.isReady, playback.loadError ?? "")
        XCTAssertEqual(playback.outputDuration, 11, accuracy: 0.01)
        let screen = try XCTUnwrap(playback.videoPlayer(for: .screen))
        let camera = try XCTUnwrap(playback.videoPlayer(for: .camera))
        for player in [screen, camera] {
            let asset = try XCTUnwrap(player.currentItem?.asset)
            let time = try await asset.load(.duration)
            XCTAssertEqual(time.seconds, 11, accuracy: 0.1)
        }
        playback.seek(to: 5)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(screen.currentTime().seconds, camera.currentTime().seconds, accuracy: 0.06)
        let profile = ExportPerformanceProfile.resolved(preset: .custom, sourceResolution: .p1080,
            sourceFramesPerSecond: 30, customResolution: .p1080, customFramesPerSecond: 24, customVideoQuality: .high)
        let result = try await coordinator.exportProjectForAgent(.init(projectURL: projectURL, outputFormat: .mp4,
            performanceProfile: profile, destinationURL: root.appendingPathComponent("journey-1.3x-\(UUID().uuidString).mp4"),
            hiddenVideoSources: [], mutedAudioSources: [], backgroundMusic: nil, playbackRate: 1.3))
        let asset = AVURLAsset(url: result.url)
        let exportDuration = try await asset.load(.duration)
        let videos = try await asset.loadTracks(withMediaType: .video)
        let audios = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(exportDuration.seconds, 11 / 1.3, accuracy: 0.1)
        XCTAssertFalse(audios.isEmpty)
        let exportedFPS = try await XCTUnwrap(videos.first).load(.nominalFrameRate)
        XCTAssertEqual(exportedFPS, 24, accuracy: 0.1)
        XCTAssertEqual(sourceURLs.map { MediaFileFingerprint(url: $0) }, fingerprints)
        vm.refreshLastExportedProject()
        let host = NSHostingView(rootView: EditorView(vm: vm).environmentObject(AppUpdateController()).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1280, height: 900),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        try await Task.sleep(for: .seconds(2))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: root.appendingPathComponent("reopened-editor.png"))
        print("EDITING_JOURNEY source_seconds=\(duration) output_seconds=\(exportDuration.seconds) sources_unchanged=true")
    }
}
