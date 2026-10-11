import AVFoundation
import XCTest
@testable import BlitzRecorderApp

final class EditorAudioAnalysisTests: XCTestCase {
    private struct AudioWrite {
        let url: URL
        let silent: Bool
    }

    private func writeAudio(_ request: AudioWrite) throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
        buffer.frameLength = 48_000
        for index in 0..<48_000 {
            buffer.floatChannelData![0][index] = request.silent ? 0 : Float(sin(Double(index) * 2 * .pi * 440 / 48_000) * 0.2)
        }
        let file = try AVAudioFile(forWriting: request.url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128_000
        ])
        try file.write(from: buffer)
    }

    private func asset(_ fixture: SyntheticRecording) throws -> EditorAsset {
        var settings = fixture.settings
        settings.enabledSources = [.screen, .systemAudio]
        let store = TakeFileStore()
        let scenes = store.sceneEvents(from: try store.loadRecordingProject(at: fixture.take.projectURL))
        try store.writeRecordingProject(for: fixture.take, settings: settings, sceneEvents: scenes, finalVideoURL: nil)
        return try XCTUnwrap(EditorAsset.assets(project: store.loadRecordingProject(at: fixture.take.projectURL),
            finalVideoURL: nil).first { $0.kind == .systemAudio })
    }

    @MainActor
    func testAnalysisFailureKeepsMetadataAndRetryRecoversAfterEditorLoadCompleted() async throws {
        let fixture = try SyntheticRecording()
        try writeAudio(.init(url: fixture.take.systemAudioURL, silent: false))
        let asset = try asset(fixture)
        let analyzer = FlakyAnalyzer()
        let library = EditorMediaLibrary(analyzeAudio: { try await analyzer.analyze($0) })
        await library.loadAssets([asset])
        guard case .failed = library.audioActivity[asset.id] else { return XCTFail("Expected an analysis failure") }
        XCTAssertGreaterThan(library.durations[asset.id] ?? 0, 0)
        XCTAssertNotNil(library.timelineWaveforms[asset.id])
        await library.loadAssets([asset])
        let attemptsBeforeRetry = await analyzer.attempts
        XCTAssertEqual(attemptsBeforeRetry, 1)
        await library.retryAudioActivity(asset)
        guard case .ready(let ranges) = library.audioActivity[asset.id] else { return XCTFail("Expected recovery") }
        XCTAssertEqual(ranges.count, 1)
        let attemptsAfterRetry = await analyzer.attempts
        XCTAssertEqual(attemptsAfterRetry, 2)
        XCTAssertTrue(library.loadingIDs.isEmpty)
    }

    @MainActor
    func testUnreadableFileReportsFailureAndRepairedSilentFileIsSuccessfulEmptyAnalysis() async throws {
        let fixture = try SyntheticRecording()
        try Data("unreadable audio".utf8).write(to: fixture.take.systemAudioURL)
        let asset = try asset(fixture)
        let library = EditorMediaLibrary()
        await library.loadAssets([asset])
        guard case .failed = library.audioActivity[asset.id] else { return XCTFail("Unreadable audio is not silence") }
        try writeAudio(.init(url: fixture.take.systemAudioURL, silent: true))
        await library.retryAudioActivity(asset)
        XCTAssertEqual(library.audioActivity[asset.id], .ready([]))
    }

    @MainActor
    func testCancelledAnalysisCannotOverwriteImmediateRestart() async throws {
        let fixture = try SyntheticRecording()
        try writeAudio(.init(url: fixture.take.systemAudioURL, silent: false))
        let asset = try asset(fixture)
        let gate = AnalysisGate()
        let library = EditorMediaLibrary(analyzeAudio: { await gate.analyze($0) })
        let old = Task { await library.loadAssets([asset]) }
        await gate.waitUntilStarted()
        XCTAssertEqual(library.audioActivity[asset.id], .loading)
        old.cancel()
        await library.loadAssets([asset])
        let expected = EditorAudioActivity.State.ready([.init(start: 0, end: 1)])
        XCTAssertEqual(library.audioActivity[asset.id], expected)
        await gate.release()
        await old.value
        XCTAssertEqual(library.audioActivity[asset.id], expected)
    }

    @MainActor
    func testCancelledAnalysisReturnsToPendingAndCanLoadAgain() async throws {
        let fixture = try SyntheticRecording()
        try writeAudio(.init(url: fixture.take.systemAudioURL, silent: false))
        let asset = try asset(fixture)
        let gate = AnalysisGate()
        let library = EditorMediaLibrary(analyzeAudio: { await gate.analyze($0) })
        let old = Task { await library.loadAssets([asset]) }
        await gate.waitUntilStarted()
        old.cancel()
        await gate.release()
        await old.value
        XCTAssertNil(library.audioActivity[asset.id])
        await library.loadAssets([asset])
        XCTAssertEqual(library.audioActivity[asset.id], .ready([.init(start: 0, end: 1)]))
    }
}

private actor FlakyAnalyzer {
    var attempts = 0

    func analyze(_ asset: EditorAsset) async throws -> [EditorTimeRange] {
        attempts += 1
        if attempts == 1 { throw SilenceDetectionError.noAudio }
        return try await EditorAudioActivity.load(asset)
    }
}

private actor AnalysisGate {
    private var attempts = 0
    private var pending: CheckedContinuation<Void, Never>?
    private var observers: [CheckedContinuation<Void, Never>] = []

    func analyze(_ asset: EditorAsset) async -> [EditorTimeRange] {
        attempts += 1
        if attempts == 1 {
            await withCheckedContinuation {
                pending = $0
                observers.forEach { $0.resume() }
                observers.removeAll()
            }
            return [.init(start: 9, end: 10)]
        }
        return [.init(start: 0, end: 1)]
    }

    func waitUntilStarted() async {
        if pending != nil { return }
        await withCheckedContinuation { observers.append($0) }
    }

    func release() {
        pending?.resume()
        pending = nil
    }
}
