import BlitzRecorderDomain
import SwiftUI
import XCTest
@testable import BlitzRecorderApp

@MainActor
final class SilencePanePresentationTests: XCTestCase {
    func testPhasesFollowSessionState() {
        XCTAssertEqual(make(.init(loading: true, scanProgress: 0.42)).phase, .scanning(fraction: 0.42))
        XCTAssertEqual(make(.init(waitingForTranscript: true, transcriptStatus: .transcribing)).phase,
                       .analyzingSpeech(step: 3, title: "Finding words"))
        XCTAssertEqual(make(.init(hasChanges: true, cuts: [2...4])).phase, .proposed)
        XCTAssertEqual(make(.init(hasRemovedSilence: true, pauseCount: 129)).phase, .applied)
        XCTAssertEqual(make(.init()).phase, .noPauses)
        if case .unavailable = make(.init(hasAudio: false)).phase {} else { XCTFail("Expected unavailable") }
    }

    func testProgressLineEstimatesRemainingTimeAndSpeechSteps() {
        let scanning = make(.init(loading: true, scanProgress: 0.25))
        XCTAssertEqual(scanning.progressLine(.init(elapsed: 10)), "About 30 s left")
        XCTAssertEqual(scanning.progressLine(.init(elapsed: 1)), "Reading microphone")
        let speech = make(.init(waitingForTranscript: true, transcriptStatus: .diarizing))
        XCTAssertEqual(speech.progressLine(.init(elapsed: 75)), "Step 4 of 4 · 1:15")
    }

    func testStrengthMapsOffCustomAndPacing() {
        XCTAssertEqual(make(.init(suggestsPauses: false)).strength, .off)
        XCTAssertNil(make(.init(customized: true)).strength)
        XCTAssertEqual(make(.init(intensity: 2)).strength, .balanced)
    }

    func testStripColumnsMeasureLevelAndKeptShare() {
        let windows = [SilenceWindow(start: 0, end: 0.5, decibels: -10), SilenceWindow(start: 5, end: 5.5, decibels: -70)]
        let columns = SilenceStripColumns.make(.init(windows: windows, duration: 12, cuts: [5...6]))
        XCTAssertEqual(columns.count, SilenceStripColumns.count)
        XCTAssertEqual(columns[0].level, 1)
        XCTAssertEqual(columns[50].level, 0)
        XCTAssertEqual(columns[50].kept, 0, accuracy: 0.001)
        XCTAssertEqual(columns[0].kept, 1)
        let bars = SilenceTakeStrip.bars(.init(columns: columns, size: CGSize(width: 250, height: 30)))
        XCTAssertEqual(bars.count, SilenceStripColumns.count)
        XCTAssertGreaterThan(bars[1].rect.minX, bars[0].rect.maxX)
    }

    func testRendersEveryState() throws {
        let cuts = stride(from: 6.0, to: 1290, by: 10.1).map { $0...($0 + 6.7) }
        let states: [(String, SilencePanePresentation)] = [
            ("scanning", make(.init(loading: true, scanProgress: 0.42))),
            ("speech", make(.init(waitingForTranscript: true, transcriptStatus: .transcribing))),
            ("proposed", make(.init(hasChanges: true, pauseCount: 128, cuts: cuts, canApply: true))),
            ("applied", make(.init(hasRemovedSilence: true, pauseCount: 128, cuts: cuts))),
            ("none", make(.init())),
            ("unavailable", make(.init(hasAudio: false)))
        ]
        let actions = SilencePaneActions(apply: {}, restore: {}, setPreview: { _ in }, selectStrength: { _ in })
        for (name, presentation) in states {
            let view = VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 20) {
                    SilenceSummaryCard(presentation: presentation, phaseStartedAt: Date().addingTimeInterval(-12))
                    SilenceStrengthSection(presentation: presentation, actions: actions)
                }
                .padding(20)
                Spacer(minLength: 0)
                if presentation.phase.showsFooter {
                    SilenceFooterActions(presentation: presentation, actions: actions)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .overlay(alignment: .top) { Rectangle().fill(BlitzUI.separator).frame(height: 1) }
                }
            }
            .frame(width: 340, height: 640)
            .background(BlitzUI.panelBackground)
            .environment(\.colorScheme, .dark)
            let host = NSHostingView(rootView: view)
            host.appearance = NSAppearance(named: .darkAqua)
            host.setFrameSize(CGSize(width: 340, height: 640))
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(host.fittingSize.width, 340, accuracy: 1)
            guard let directory = ProcessInfo.processInfo.environment["BLITZRECORDER_SILENCE_UI_PROOF"] else { continue }
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent("silence-\(name).png"))
        }
    }

    private struct State {
        var loading = false
        var scanProgress: Double?
        var waitingForTranscript = false
        var transcriptStatus: TranscriptionJobStatus?
        var hasAudio = true
        var hasChanges = false
        var hasRemovedSilence = false
        var pauseCount = 0
        var cuts: [ClosedRange<Double>] = []
        var canApply = false
        var suggestsPauses = true
        var customized = false
        var intensity = 1.0
    }

    private func make(_ state: State) -> SilencePanePresentation {
        let duration = 1296.4
        let timelineCuts = state.cuts.map { TimelineCut(start: $0.lowerBound, end: $0.upperBound, kind: .silence, source: .automatic) }
        let removed = state.cuts.reduce(0) { $0 + $1.upperBound - $1.lowerBound }
        return .make(.init(
            loading: state.loading, scanProgress: state.scanProgress, waitingForTranscript: state.waitingForTranscript,
            transcriptStatus: state.transcriptStatus, hasAudio: state.hasAudio, error: nil,
            hasChanges: state.hasChanges, hasRemovedSilence: state.hasRemovedSilence, isUpdating: false,
            duration: duration,
            metrics: SilenceTimelineMetrics(.init(duration: duration, proposed: timelineCuts,
                                                  saved: state.hasRemovedSilence ? timelineCuts : [])),
            cuts: timelineCuts, windows: speechWindows(duration), previewEnabled: false, suggestsPauses: state.suggestsPauses,
            customized: state.customized, intensity: state.intensity, canApply: state.canApply,
            sourceName: "Microphone"
        ))
        .withPauseCount(state.cuts.isEmpty ? state.pauseCount : state.cuts.count, removed: removed)
    }
}

private func speechWindows(_ duration: Double) -> [SilenceWindow] {
    stride(from: 0.0, to: duration, by: 0.5).map { start in
        let phrase = (sin(start / 3.1) + sin(start / 0.9) * 0.5 + 1.5) / 3
        let pause = start.truncatingRemainder(dividingBy: 10.1) > 6
        return SilenceWindow(start: start, end: start + 0.5, decibels: pause ? -56 : -40 + phrase * 28)
    }
}

private extension SilencePanePresentation {
    func withPauseCount(_ count: Int, removed: Double) -> SilencePanePresentation {
        .init(phase: phase, originalDuration: originalDuration, editedDuration: originalDuration - removed,
              removedDuration: removed, pauseCount: count, cutRanges: cutRanges, columns: columns, hasAppliedCuts: hasAppliedCuts,
              isUpdating: isUpdating, previewEnabled: previewEnabled, strength: strength, canApply: canApply,
              warning: warning, sourceName: sourceName)
    }
}
