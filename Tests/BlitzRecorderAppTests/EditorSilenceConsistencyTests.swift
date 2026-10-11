import AVFoundation
import XCTest
@testable import BlitzRecorderApp

final class EditorSilenceConsistencyTests: XCTestCase {
    func testRealProjectSilenceDisplayMatchesTheRemovalProposal() async throws {
        guard let path = ProcessInfo.processInfo.environment["BLITZ_SILENCE_TEST_PROJECT"] else {
            throw XCTSkip("Provide a project path for a read-only silence display check.")
        }
        let url = URL(fileURLWithPath: path)
        let original = try Data(contentsOf: url)
        let project = try TakeFileStore().loadRecordingProject(at: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let transcript = try decoder.decode(RecordingTranscript.self, from: Data(contentsOf:
            URL(fileURLWithPath: project.takeDirectoryPath).appendingPathComponent("transcript.json")))
        let video = try XCTUnwrap(project.sources.first { $0.role == "screen" && $0.exists })
        let sourceDuration = try await AVURLAsset(url: URL(fileURLWithPath: video.path)).load(.duration)
        let duration = sourceDuration.seconds - project.timelineTrimOffsetSeconds
        let settings = project.edits.silenceSettings ?? .standard
        var tracks: [[SilenceWindow]] = []
        for source in project.sources where ["microphone", "systemAudio"].contains(source.role) && source.exists {
            tracks.append(try await SilenceDetection.cachedWindows(.init(
                audioURL: URL(fileURLWithPath: source.path), takeDuration: duration,
                sourceOffset: project.sourceOffset(forRole: source.role) - project.timelineTrimOffsetSeconds,
                minimumSilence: settings.minimumDuration, thresholdDB: settings.threshold, previousCuts: project.edits.cuts)))
        }
        let windows = SilenceDetection.combinedWindows(tracks)
        let legacy = EditorTranscriptTimeline.items(.init(
            transcript: transcript, windows: windows, threshold: settings.threshold, duration: duration))
        let detected = EditorTranscriptTimeline.items(.init(
            transcript: transcript, windows: windows, threshold: settings.threshold, duration: duration,
            paddingBefore: settings.paddingBefore, paddingAfter: settings.paddingAfter,
            minimumSilence: settings.minimumDuration))
        let proposal = SilenceCutProposal(.init(duration: duration, baseCuts: project.edits.cuts,
            transcriptCuts: detected.filter { $0.kind == .nonDialogue }.map {
                .init(start: $0.range.start, end: $0.range.end, kind: .silence, source: .automatic)
            }, saved: project.edits, suggestsPauses: true))
        let savedProjection = EditorTimelineProjection(.init(duration: duration, cuts: project.edits.cuts))
        let legacyReds = legacy.filter { $0.kind == .nonDialogue
            && savedProjection.displayTime($0.range.end) > savedProjection.displayTime($0.range.start) }
        let subframe = legacyReds.filter {
            ((savedProjection.displayTime($0.range.end) - savedProjection.displayTime($0.range.start)) * 600).rounded() < 1
        }
        let displayed = EditorTranscriptTimeline.classifiedItems(.init(items: detected, cuts: proposal.cuts))
        let current = EditorTranscriptLayout(.init(items: displayed, projection: savedProjection))
        let applied = EditorTranscriptLayout(.init(items: displayed,
            projection: .init(.init(duration: duration, cuts: proposal.cuts))))
        XCTAssertFalse(applied.items.contains { $0.source.kind == .nonDialogue })
        XCTAssertEqual(try Data(contentsOf: url), original)
        print("REAL_SILENCE saved_cuts=\(project.edits.cuts.count) old_red=\(legacyReds.count) subframe=\(subframe.count) pending_red=\(current.items.filter { $0.source.kind == .nonDialogue }.count) after_apply_red=\(applied.items.filter { $0.source.kind == .nonDialogue }.count)")
    }

    func testTranscriptDoesNotShowSilenceExcludedByTheChosenMinimumDuration() {
        let transcript = RecordingTranscriptAssembler.assemble(.init(
            mediaPath: "/recording", generatedAt: .distantPast, duration: 10,
            confidence: 1, text: "hello", suggestedTitle: nil,
            words: [.init(text: "hello", startTime: 0, endTime: 2, confidence: 1)],
            diarizedIntervals: [.init(speakerID: "speaker", startTime: 0, endTime: 2)]))
        let windows = [SilenceWindow(start: 4, end: 4.1, decibels: -10)]
        let proposed = EditorTranscriptTimeline.items(.init(
            transcript: transcript, windows: windows, threshold: -42, duration: 10,
            paddingBefore: 0.3, paddingAfter: 0.3, minimumSilence: 0.5))
        XCTAssertFalse(proposed.contains { $0.kind == .nonDialogue })
        let displayed = EditorTranscriptTimeline.classifiedItems(.init(items: proposed, cuts: []))
        XCTAssertFalse(displayed.contains { $0.kind == .nonDialogue })
    }

    func testManuallyKeptPartIsNotRedAndRemainingSilenceStaysSelectable() {
        let item = EditorTranscriptItem(id: 0, range: .init(start: 2, end: 6), text: "Silence", kind: .nonDialogue)
        let displayed = EditorTranscriptTimeline.classifiedItems(.init(items: [item], cuts: [
            .init(start: 2, end: 3, kind: .silence, source: .automatic),
            .init(start: 3, end: 4, kind: .silence, source: .automatic, isEnabled: false),
            .init(start: 4, end: 6, kind: .silence, source: .automatic)
        ]))
        XCTAssertEqual(displayed.map(\.range), [.init(start: 2, end: 3), .init(start: 4, end: 6)])
        XCTAssertEqual(Set(displayed.map(\.id)).count, 2)
        let layout = EditorTranscriptLayout(.init(items: displayed, projection: .init(.init(duration: 10, cuts: []))))
        XCTAssertNil(layout.item(at: 3.5))
        XCTAssertEqual(layout.item(at: 4.5)?.source.range, .init(start: 4, end: 6))
    }

    func testRemovedSilenceHasNoSubframeRedRemnant() {
        let cut = TimelineCut(start: 4.940000000000001, end: 5.260000000000001,
                              kind: .silence, source: .automatic)
        let layout = EditorTranscriptLayout(.init(
            items: [.init(id: 0, range: .init(start: cut.start, end: cut.end), text: "Silence", kind: .nonDialogue)],
            projection: .init(.init(duration: 10, cuts: [cut]))))
        XCTAssertTrue(layout.items.isEmpty)
    }
}
