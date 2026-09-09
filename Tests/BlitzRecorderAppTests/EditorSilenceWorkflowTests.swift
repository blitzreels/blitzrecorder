import AVFoundation
import XCTest

@testable import BlitzRecorderApp

final class EditorSilenceWorkflowTests: XCTestCase {
    func testSavingsMergeOverlappingManualAndAutomaticCuts() {
        let manual = TimelineCut(start: 1, end: 4, kind: .manual, source: .user)
        let silence = TimelineCut(start: 3, end: 6, kind: .silence, source: .automatic)
        let metrics = SilenceTimelineMetrics(.init(duration: 10, proposed: [manual, silence], saved: [manual]))
        XCTAssertEqual(metrics.removedDuration, 5, accuracy: 0.001)
        XCTAssertEqual(metrics.outputDuration, 5, accuracy: 0.001)
        XCTAssertEqual(metrics.pauseCount, 1)
        XCTAssertTrue(metrics.hasChanges)
    }

    func testReanalysisWithNewIDsDoesNotOfferToApplyIdenticalCuts() {
        let original = TimelineCut(start: 2, end: 4, kind: .silence, source: .automatic)
        let regenerated = TimelineCut(start: 2, end: 4, kind: .silence, source: .automatic)
        let metrics = SilenceTimelineMetrics(.init(duration: 10, proposed: [regenerated], saved: [original]))
        XCTAssertFalse(metrics.hasChanges)
    }

    func testKeptPauseCanBeSavedEvenWhenItRemovesNoTime() {
        let kept = TimelineCut(start: 2, end: 4, kind: .silence, source: .automatic, isEnabled: false)
        let metrics = SilenceTimelineMetrics(.init(duration: 10, proposed: [kept], saved: []))
        XCTAssertTrue(metrics.hasChanges)
        XCTAssertEqual(metrics.removedDuration, 0)
        XCTAssertEqual(metrics.pauseCount, 0)
        XCTAssertFalse(SilenceTimelineMetrics(.init(duration: 10, proposed: [kept], saved: [kept])).hasChanges)
    }

    func testSilenceRenderingClipsToViewportAndKeepsExactSelectionRange() throws {
        let cuts = [
            TimelineCut(start: 0, end: 1, kind: .silence, source: .automatic),
            TimelineCut(start: 4, end: 7, kind: .silence, source: .automatic),
            TimelineCut(start: 8, end: 9, kind: .silence, source: .automatic, isEnabled: false),
            TimelineCut(start: 5, end: 8, kind: .manual, source: .user),
            TimelineCut(start: .nan, end: 9, kind: .silence, source: .automatic),
        ]
        let bands = SilenceTimelineBands.visible(
            .init(
                cuts: cuts, projection: .init(.init(duration: 10, cuts: [])), pixelsPerSecond: 100,
                viewport: .init(lowerBound: 500, upperBound: 850)
            ))
        XCTAssertEqual(bands.count, 2)
        XCTAssertEqual(bands[0].x, 0)
        XCTAssertEqual(bands[0].width, 200)
        XCTAssertEqual(bands[0].range, EditorTimeRange(start: 4, end: 7))
        XCTAssertEqual(bands[1].width, 50)
        XCTAssertFalse(bands[1].isEnabled)
        XCTAssertEqual(SilenceTimelineBands.selectedRange(.init(bands: bands, x: 10)), bands[0].range)
        XCTAssertEqual(SilenceTimelineBands.selectedRange(.init(bands: bands, x: 325)), bands[1].range)
        XCTAssertNil(SilenceTimelineBands.selectedRange(.init(bands: bands, x: 250)))
        XCTAssertTrue(
            SilenceTimelineBands.visible(
                .init(
                    cuts: cuts, projection: .init(.init(duration: 10, cuts: [])), pixelsPerSecond: 0,
                    viewport: .init(lowerBound: 0, upperBound: 500)
                )
            ).isEmpty)
    }

    @MainActor
    func testBackgroundAnalysisKeepsPlaybackAndProjectUntouchedThenAppliesWithUndo() async throws {
        let fixture = try SyntheticRecording()
        try await fixture.writeVideo(.init(url: fixture.take.screenURL, frames: 300))
        try writeAudio(fixture.take.audioURL)
        var settings = fixture.settings
        settings.enabledSources = [.screen, .microphone]
        let store = TakeFileStore()
        let scenes = store.sceneEvents(from: try store.loadRecordingProject(at: fixture.take.projectURL))
        try store.writeRecordingProject(for: fixture.take, settings: settings, sceneEvents: scenes, finalVideoURL: nil)
        let suite = "EditorSilenceWorkflowTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let vm = RecorderViewModel(
            coordinator: RecorderCoordinator(
                accessController: AccessController(defaults: defaults), defaults: defaults),
            previewStage: PreviewStageView()
        )
        vm.settings = settings
        vm.openProject(try XCTUnwrap(store.loadProjectHistory(settings: settings).entries.first))
        let project = try XCTUnwrap(vm.lastExportedProject)
        let originalData = try Data(contentsOf: fixture.take.projectURL)
        let playback = EditorPlaybackController()
        let session = SilenceEditingSession()
        defer {
            session.cancel()
            playback.teardown()
        }
        await playback.load(project: project, baseSettings: settings)
        XCTAssertTrue(playback.isReady)
        playback.setPlaybackVolume(0)
        playback.play(from: 0)
        let player = try XCTUnwrap(playback.videoPlayer(for: .screen))
        XCTAssertTrue(playback.isPlaying)
        session.prepare(.init(vm: vm, playback: playback, project: project))
        XCTAssertEqual(session.audioSourcePaths, [fixture.take.audioURL.path])
        XCTAssertTrue(playback.isPlaying)
        XCTAssertFalse(session.skipSilence)
        let deadline = ContinuousClock.now + .seconds(5)
        while (session.loading || session.calculating) && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(session.loading)
        XCTAssertFalse(session.calculating)
        XCTAssertNil(session.error)
        XCTAssertTrue(session.canApply)
        XCTAssertGreaterThan(session.metrics.removedDuration, 1)
        XCTAssertTrue(playback.isPlaying)
        XCTAssertTrue(playback.videoPlayer(for: .screen) === player)
        XCTAssertEqual(try Data(contentsOf: fixture.take.projectURL), originalData)
        let suggestedCuts = session.cuts
        session.prepare(.init(vm: vm, playback: playback, project: project))
        XCTAssertFalse(session.loading)
        XCTAssertEqual(session.cuts, suggestedCuts)
        XCTAssertTrue(session.apply())
        XCTAssertFalse(session.canApply)
        XCTAssertEqual(vm.editorUndoTitle, "Undo Remove Silence")
        XCTAssertEqual(try store.loadRecordingProject(at: fixture.take.projectURL).edits.cuts, suggestedCuts)
        let editedProject = try XCTUnwrap(vm.lastExportedProject)
        await playback.load(project: editedProject, baseSettings: settings)
        XCTAssertTrue(playback.isReady, playback.loadError ?? "Playback did not recover after removing silence")
        XCTAssertLessThan(playback.outputDuration, playback.duration - 1)
        playback.setPlaybackRate(.normal)
        playback.play(from: 6)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(playback.isPlaying)
        XCTAssertGreaterThanOrEqual(playback.currentTime, 6)
        XCTAssertLessThan(playback.currentTime, 7)
        XCTAssertEqual(playback.currentTime, playback.displayTime(), accuracy: 0.15)
        playback.pauseForEditing()
        vm.undoEditor()
        XCTAssertEqual(
            try store.loadRecordingProject(at: fixture.take.projectURL).edits, project.edits, vm.detailMessage)
        await playback.load(project: try XCTUnwrap(vm.lastExportedProject), baseSettings: settings)
        XCTAssertTrue(playback.isReady)
        XCTAssertEqual(playback.outputDuration, playback.duration, accuracy: 0.01)
        let restoredProject = try XCTUnwrap(vm.lastExportedProject)
        session.prepare(.init(vm: vm, playback: playback, project: restoredProject))
        for _ in 0..<6 {
            session.setPreviewEnabled(true)
            try await Task.sleep(for: .milliseconds(240))
            session.setPreviewEnabled(false)
            await playback.load(project: restoredProject, baseSettings: settings)
        }
        session.cancel()
        await playback.load(project: restoredProject, baseSettings: settings)
        XCTAssertTrue(playback.isReady, playback.loadError ?? "Playback did not recover after repeated preview changes")
        playback.play(from: 1)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(playback.isPlaying)
        XCTAssertEqual(try store.loadRecordingProject(at: fixture.take.projectURL).edits, project.edits)
        playback.pauseForEditing()
        var denseEdits = project.edits
        denseEdits.cuts = (0..<181).map {
            let start = 0.025 + Double($0) * 0.05
            return TimelineCut(start: start, end: start + 0.012, kind: .silence, source: .automatic)
        }
        for _ in 0..<3 {
            XCTAssertTrue(vm.applyTimelineEdits(.init(edits: denseEdits, actionName: "Remove Silence")))
            await playback.load(project: try XCTUnwrap(vm.lastExportedProject), baseSettings: settings)
            XCTAssertTrue(playback.isReady, playback.loadError ?? "Playback failed with 181 silence edits")
            playback.play(from: 7)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertTrue(playback.isPlaying)
            playback.pauseForEditing()
            vm.undoEditor()
            await playback.load(project: try XCTUnwrap(vm.lastExportedProject), baseSettings: settings)
            XCTAssertTrue(playback.isReady)
            XCTAssertEqual(playback.outputDuration, playback.duration, accuracy: 0.01)
        }
    }

    private func writeAudio(_ url: URL) throws {
        let file = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000,
            ])
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 480_000))
        buffer.frameLength = 480_000
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<480_000 {
            let time = Double(index) / 48_000
            samples[index] = (2..<5).contains(time) ? 0 : Float(sin(time * 440 * 2 * .pi) * 0.3)
        }
        try file.write(from: buffer)
    }
}
