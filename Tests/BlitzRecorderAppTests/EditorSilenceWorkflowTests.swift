import AVFoundation
import XCTest

@testable import BlitzRecorderApp

final class EditorSilenceWorkflowTests: XCTestCase {
    func testManualSoundAndSilenceOverridesPreserveExactRangesAcrossAnalysis() throws {
        let windows = (0..<500).map { index in
            SilenceWindow(
                start: Double(index) / 50, end: Double(index + 1) / 50,
                decibels: (100..<400).contains(index) ? -80 : -20
            )
        }
        let sound = try XCTUnwrap(SilenceDetection.classifying(.init(
            range: .init(start: 4, end: 5), classification: .sound, edits: .empty, duration: 10
        )))
        let edited = try XCTUnwrap(SilenceDetection.classifying(.init(
            range: .init(start: 0.5, end: 1), classification: .silence, edits: sound, duration: 10
        )))
        for threshold in [-60.0, -30.0, -15.0] {
            let cuts = SilenceDetection.cuts(.init(
                windows: windows,
                configuration: .init(
                    audioURL: URL(fileURLWithPath: "/unused"), takeDuration: 10, sourceOffset: 0,
                    minimumSilence: 0.1, thresholdDB: threshold, previousCuts: [],
                    paddingBefore: 0, paddingAfter: 0, overrides: edited.silenceOverrides
                )
            ))
            XCTAssertEqual(SilenceTimelineBands.classification(.init(range: .init(start: 4, end: 5), cuts: cuts)), .sound)
            XCTAssertEqual(SilenceTimelineBands.classification(.init(range: .init(start: 0.5, end: 1), cuts: cuts)), .silence)
            XCTAssertEqual(SilenceTimelineBands.classification(.init(range: .init(start: 2, end: 4), cuts: cuts)), .silence)
            XCTAssertEqual(SilenceTimelineBands.classification(.init(range: .init(start: 5, end: 8), cuts: cuts)), .silence)
        }
        let reversed = try XCTUnwrap(SilenceDetection.classifying(.init(
            range: .init(start: 4.25, end: 4.75), classification: .silence, edits: edited, duration: 10
        )))
        XCTAssertEqual(reversed.silenceOverrides.filter { $0.classification == .sound }.map(\.start), [4, 4.75])
        XCTAssertEqual(reversed.silenceOverrides.filter { $0.classification == .sound }.map(\.end), [4.25, 5])
        XCTAssertEqual(Set(reversed.silenceOverrides.map(\.id)).count, reversed.silenceOverrides.count)
    }

    func testKeepingAppliedSilenceRestoresOnlyThatSectionAndPreservesManualCuts() throws {
        var edits = TimelineEdits.empty
        let manual = TimelineCut(start: 1, end: 2, kind: .manual, source: .user)
        edits.cuts = [manual, .init(start: 3, end: 8, kind: .silence, source: .automatic)]
        let kept = try XCTUnwrap(SilenceDetection.classifying(.init(
            range: .init(start: 4, end: 5), classification: .sound, edits: edits, duration: 10
        )))
        XCTAssertEqual(kept.cuts.first, manual)
        let map = TimelineTimeMap(takeDuration: TimelineTimeMap.time(10), cuts: kept.cuts)
        XCTAssertFalse(map.isRemoved(takeTime: 4.5))
        XCTAssertTrue(map.isRemoved(takeTime: 3.5))
        XCTAssertTrue(map.isRemoved(takeTime: 5.5))
        let analyzed = SilenceDetection.cuts(.init(
            windows: [.init(start: 3, end: 8, decibels: -80)],
            configuration: .init(
                audioURL: URL(fileURLWithPath: "/unused"), takeDuration: 10, sourceOffset: 0,
                minimumSilence: 0.1, thresholdDB: -42, previousCuts: kept.cuts,
                paddingBefore: 0, paddingAfter: 0, overrides: kept.silenceOverrides
            )
        ))
        XCTAssertEqual(SilenceTimelineBands.classification(.init(range: .init(start: 3, end: 4), cuts: analyzed)), .silence)
        XCTAssertEqual(SilenceTimelineBands.classification(.init(range: .init(start: 4, end: 5), cuts: analyzed)), .sound)
        XCTAssertEqual(SilenceTimelineBands.classification(.init(range: .init(start: 5, end: 8), cuts: analyzed)), .silence)
    }

    func testSoundSelectionUsesTheSectionBetweenSilenceBands() {
        let cuts = [
            TimelineCut(start: 2, end: 4, kind: .silence, source: .automatic),
            TimelineCut(start: 7, end: 8, kind: .silence, source: .user, isEnabled: false),
        ]
        XCTAssertEqual(SilenceTimelineBands.soundRange(.init(cuts: cuts, time: 5, duration: 10)), .init(start: 4, end: 7))
        XCTAssertEqual(SilenceTimelineBands.soundRange(.init(cuts: cuts, time: 1, duration: 10)), .init(start: 0, end: 2))
        XCTAssertEqual(SilenceTimelineBands.soundRange(.init(cuts: cuts, time: 9, duration: 10)), .init(start: 8, end: 10))
    }

    func testSavingsMergeOverlappingManualAndAutomaticCuts() {
        let manual = TimelineCut(start: 1, end: 4, kind: .manual, source: .user)
        let silence = TimelineCut(start: 3, end: 6, kind: .silence, source: .automatic)
        let metrics = SilenceTimelineMetrics(.init(duration: 10, proposed: [manual, silence], saved: [manual]))
        XCTAssertEqual(metrics.removedDuration, 5, accuracy: 0.001)
        XCTAssertEqual(metrics.outputDuration, 5, accuracy: 0.001)
        XCTAssertEqual(metrics.pauseCount, 1)
        XCTAssertTrue(metrics.hasChanges)
    }

    func testNarrowSoundSegmentsRemainSelectableAtSilenceBoundaries() {
        let cuts = [
            TimelineCut(start: 2, end: 4, kind: .silence, source: .automatic),
            TimelineCut(start: 4.1, end: 6, kind: .silence, source: .automatic),
        ]
        let bands = SilenceTimelineBands.visible(.init(
            cuts: cuts, projection: .init(.init(duration: 10, cuts: [])), pixelsPerSecond: 20,
            viewport: .init(lowerBound: 0, upperBound: 200)
        ))
        for time in [4.0, 4.025, 4.05, 4.075] {
            XCTAssertNil(SilenceTimelineBands.selectedRange(.init(bands: bands, x: time * 20)))
            XCTAssertEqual(
                SilenceTimelineBands.soundRange(.init(cuts: cuts, time: time, duration: 10)),
                .init(start: 4, end: 4.1)
            )
        }
        XCTAssertEqual(SilenceTimelineBands.selectedRange(.init(bands: bands, x: 82)), .init(start: 4.1, end: 6))
        for time in [Double.nan, -Double.infinity, -1, 2, 3, 4.1, 11] {
            XCTAssertNil(SilenceTimelineBands.soundRange(.init(cuts: cuts, time: time, duration: 10)))
        }
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
        let overlay = SilenceTimelineBands.overlayRuns(
            .init(
                cuts: (0..<200_000).map {
                    TimelineCut(
                        start: Double($0) * 0.016, end: Double($0) * 0.016 + 0.008,
                        kind: .silence, source: .automatic)
                },
                projection: .init(.init(duration: 3_240, cuts: [])),
                pixelsPerSecond: 1_200 / 3_240,
                viewport: .init(lowerBound: 0, upperBound: 1_200)
            ),
            selections: [])
        XCTAssertLessThanOrEqual(overlay.count, 1_200)
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
        session.customized = true
        session.paddingBefore = 0.2
        session.paddingAfter = 0.2
        session.setSuggestionsEnabled(false)
        try await settle(session)
        XCTAssertTrue(session.cuts.isEmpty)
        XCTAssertFalse(session.suggestsPauses)
        XCTAssertEqual(try Data(contentsOf: fixture.take.projectURL), originalData)
        session.setSuggestionsEnabled(true)
        try await settle(session)
        XCTAssertTrue(session.suggestsPauses)
        XCTAssertEqual(session.paddingBefore, 0.2)
        XCTAssertTrue(session.customized)
        XCTAssertGreaterThan(session.metrics.removedDuration, 1)
        session.selectPacing(.natural)
        try await settle(session)
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
            let previewDeadline = ContinuousClock.now + .milliseconds(100)
            while playback.isReady, playback.outputDuration == playback.duration,
                ContinuousClock.now < previewDeadline {
                try await Task.sleep(for: .milliseconds(5))
            }
            XCTAssertTrue(!playback.isReady || playback.outputDuration < playback.duration,
                "A preview toggle must start loading without an extra debounce")
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

    @MainActor
    func testClassificationTogglePersistsWithUndoRedoAndDoesNotRemoveFootageUntilApplied() async throws {
        let fixture = try SyntheticRecording()
        try await fixture.writeVideo(.init(url: fixture.take.screenURL, frames: 300))
        try writeAudio(fixture.take.audioURL)
        var settings = fixture.settings
        settings.enabledSources = [.screen, .microphone]
        let store = TakeFileStore()
        let scenes = store.sceneEvents(from: try store.loadRecordingProject(at: fixture.take.projectURL))
        try store.writeRecordingProject(for: fixture.take, settings: settings, sceneEvents: scenes, finalVideoURL: nil)
        let suite = "SilenceClassificationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let vm = RecorderViewModel(
            coordinator: RecorderCoordinator(accessController: AccessController(defaults: defaults), defaults: defaults),
            previewStage: PreviewStageView()
        )
        vm.settings = settings
        vm.openProject(try XCTUnwrap(store.loadProjectHistory(settings: settings).entries.first))
        let project = try XCTUnwrap(vm.lastExportedProject)
        let playback = EditorPlaybackController()
        let session = SilenceEditingSession()
        let reopened = SilenceEditingSession()
        defer {
            session.cancel()
            reopened.cancel()
            playback.teardown()
        }
        await playback.load(project: project, baseSettings: settings)
        session.prepare(.init(vm: vm, playback: playback, project: project))
        try await settle(session)
        let pause = try XCTUnwrap(session.cuts.first { $0.kind == .silence && $0.isEnabled })
        let range = EditorTimeRange(start: pause.start, end: pause.end)
        session.toggle(range)
        XCTAssertEqual(session.classification(range), .sound)
        XCTAssertEqual(vm.editorUndoTitle, "Undo Mark as Sound")
        XCTAssertEqual(try store.loadRecordingProject(at: fixture.take.projectURL).edits.cuts, project.edits.cuts)
        XCTAssertEqual(playback.outputDuration, playback.duration, accuracy: 0.01)

        vm.undoEditor()
        session.prepare(.init(vm: vm, playback: playback, project: try XCTUnwrap(vm.lastExportedProject)))
        try await settle(session)
        XCTAssertEqual(session.classification(range), .silence)
        vm.redoEditor()
        session.prepare(.init(vm: vm, playback: playback, project: try XCTUnwrap(vm.lastExportedProject)))
        try await settle(session)
        XCTAssertEqual(session.classification(range), .sound)
        session.cancel()

        reopened.prepare(.init(
            vm: vm, playback: playback, project: try store.loadRecordingProject(at: fixture.take.projectURL)
        ))
        try await settle(reopened)
        XCTAssertEqual(reopened.classification(range), .sound)
        reopened.threshold = -25
        reopened.recalculate()
        try await settle(reopened)
        XCTAssertEqual(reopened.classification(range), .sound)

        let removedBeforeMarking = reopened.metrics.removedDuration
        let sound = EditorTimeRange(start: 0.25, end: 1.25)
        reopened.toggle(sound)
        XCTAssertEqual(reopened.classification(sound), .silence)
        XCTAssertTrue(try store.loadRecordingProject(at: fixture.take.projectURL).edits.enabledCuts.isEmpty)
        XCTAssertTrue(reopened.apply())
        let applied = try store.loadRecordingProject(at: fixture.take.projectURL)
        let map = TimelineTimeMap(takeDuration: TimelineTimeMap.time(playback.duration), cuts: applied.edits.cuts)
        XCTAssertEqual(map.removedDuration - removedBeforeMarking, 1, accuracy: 0.001)
        XCTAssertFalse(map.isRemoved(takeTime: (range.start + range.end) / 2))
        XCTAssertTrue(map.isRemoved(takeTime: 0.75))
        reopened.toggle(sound)
        let restored = try store.loadRecordingProject(at: fixture.take.projectURL)
        XCTAssertFalse(TimelineTimeMap(takeDuration: map.takeDuration, cuts: restored.edits.cuts).isRemoved(takeTime: 0.75))
        let wholeRecording = EditorTimeRange(start: 0, end: playback.duration)
        reopened.classify(.init(range: wholeRecording, classification: .silence))
        reopened.setPreviewEnabled(true)
        XCTAssertNotNil(reopened.error)
        XCTAssertTrue(reopened.canClassify)
        reopened.toggle(wholeRecording)
        XCTAssertEqual(reopened.classification(wholeRecording), .sound)
        XCTAssertNil(reopened.error)
    }

    @MainActor
    func testBatchClassificationLeavesGapsUntouchedAndUndoesAsOneEdit() async throws {
        let fixture = try SyntheticRecording()
        try await fixture.writeVideo(.init(url: fixture.take.screenURL, frames: 300))
        try writeAudio(fixture.take.audioURL)
        var settings = fixture.settings
        settings.enabledSources = [.screen, .microphone]
        let store = TakeFileStore()
        let scenes = store.sceneEvents(from: try store.loadRecordingProject(at: fixture.take.projectURL))
        try store.writeRecordingProject(for: fixture.take, settings: settings, sceneEvents: scenes, finalVideoURL: nil)
        let suite = "SilenceBatchClassificationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let vm = RecorderViewModel(
            coordinator: RecorderCoordinator(accessController: AccessController(defaults: defaults), defaults: defaults),
            previewStage: PreviewStageView()
        )
        vm.settings = settings
        vm.openProject(try XCTUnwrap(store.loadProjectHistory(settings: settings).entries.first))
        let project = try XCTUnwrap(vm.lastExportedProject)
        let playback = EditorPlaybackController()
        let session = SilenceEditingSession()
        defer {
            session.cancel()
            playback.teardown()
        }
        await playback.load(project: project, baseSettings: settings)
        session.prepare(.init(vm: vm, playback: playback, project: project))
        try await settle(session)
        let ranges = [EditorTimeRange(start: 0.25, end: 1.25), EditorTimeRange(start: 8, end: 9)]
        session.classifyTogether(ranges.map { .init(range: $0, classification: .silence) })
        let marked = try store.loadRecordingProject(at: fixture.take.projectURL).edits
        XCTAssertEqual(marked.silenceOverrides.map { EditorTimeRange(start: $0.start, end: $0.end) }, ranges)
        XCTAssertTrue(ranges.allSatisfy { session.classification($0) == .silence })
        XCTAssertEqual(session.classification(.init(start: 5.5, end: 7.5)), .sound)
        XCTAssertEqual(marked.cuts, project.edits.cuts)
        XCTAssertEqual(vm.editorUndoTitle, "Undo Mark as Silence")
        vm.undoEditor()
        XCTAssertEqual(try store.loadRecordingProject(at: fixture.take.projectURL).edits, project.edits)
        vm.redoEditor()
        XCTAssertEqual(try store.loadRecordingProject(at: fixture.take.projectURL).edits, marked)
        session.prepare(.init(vm: vm, playback: playback, project: try XCTUnwrap(vm.lastExportedProject)))
        try await settle(session)
        let sound = EditorTimeRange(start: 6, end: 7)
        session.toggleRanges([ranges[0], sound])
        XCTAssertEqual(session.classification(ranges[0]), .sound)
        XCTAssertEqual(session.classification(sound), .silence)
        XCTAssertEqual(vm.editorUndoTitle, "Undo Switch Sound and Silence")
        vm.undoEditor()
        XCTAssertEqual(try store.loadRecordingProject(at: fixture.take.projectURL).edits, marked)
        session.prepare(.init(vm: vm, playback: playback, project: try XCTUnwrap(vm.lastExportedProject)))
        try await settle(session)
        session.classifyTogether([
            .init(range: ranges[0], classification: .sound),
            .init(range: .init(start: .nan, end: 9), classification: .sound),
        ])
        XCTAssertEqual(try store.loadRecordingProject(at: fixture.take.projectURL).edits, marked)
    }

    func testOlderProjectsDecodeWithoutClassificationOverrides() throws {
        let snapshot = try JSONDecoder().decode(RecordingProject.TimelineEditsSnapshot.self, from: Data("{}".utf8))
        XCTAssertTrue(snapshot.edits.silenceOverrides.isEmpty)
        let edits = try XCTUnwrap(SilenceDetection.classifying(.init(
            range: .init(start: 1, end: 2), classification: .sound, edits: .empty, duration: 10
        )))
        let encoded = try JSONEncoder().encode(RecordingProject.TimelineEditsSnapshot(edits))
        XCTAssertEqual(try JSONDecoder().decode(RecordingProject.TimelineEditsSnapshot.self, from: encoded).edits, edits)
    }

    @MainActor
    private func settle(_ session: SilenceEditingSession) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while (session.loading || session.calculating) && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(session.loading)
        XCTAssertFalse(session.calculating)
        XCTAssertNil(session.error)
    }
}
