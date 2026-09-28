import AVFoundation
import XCTest
@testable import BlitzRecorderApp

final class LongRecordingPerformanceTests: XCTestCase {
    func testSynchronizationOfRealLongAudioWhenRequested() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["BLITZRECORDER_BENCHMARK_AUDIO"], let output = env["BLITZRECORDER_PERF_OUTPUT"] else {
            throw XCTSkip("Provide a real audio file and isolated benchmark output.")
        }
        let source = URL(fileURLWithPath: path)
        let fingerprint = MediaFileFingerprint(url: source)
        let copy = URL(fileURLWithPath: output).appendingPathComponent("normalized-audio.m4a")
        if FileManager.default.fileExists(atPath: copy.path) { try FileManager.default.removeItem(at: copy) }
        try FileManager.default.copyItem(at: source, to: copy)
        let duration = try await AVURLAsset(url: copy).load(.duration)
        let start = ContinuousClock.now
        let result = try await AudioClockNormalizer.normalize(.init(url: copy, format: .aac, bitrate: 192_000,
            measurement: .init(sourceDuration: duration, masterDuration: CMTimeMultiplyByFloat64(duration, multiplier: 1.0005))))
        let elapsed = start.duration(to: .now)
        XCTAssertTrue(result.didCorrect)
        XCTAssertEqual(MediaFileFingerprint(url: source), fingerprint)
        let corrected = try await AVURLAsset(url: copy).load(.duration)
        XCTAssertEqual(corrected.seconds, duration.seconds * 1.0005, accuracy: 0.06)
        print("LONG_PERF synchronization duration_s=\(duration.seconds) wall=\(elapsed)")
    }

    func testRealTranscriptionStageTimingsWhenRequested() async throws {
        guard let path = ProcessInfo.processInfo.environment["BLITZRECORDER_PERF_TRANSCRIPTION"] else {
            throw XCTSkip("Enable an installed-model transcription benchmark explicitly.")
        }
        guard LocalTranscriptionModelStore().isInstalled else { throw XCTSkip("Local models are not installed.") }
        let engine = LocalTranscriptionEngine()
        let start = ContinuousClock.now
        let result = try await engine.transcribe(.init(source: .recording(URL(fileURLWithPath: path)),
            model: .parakeet, language: .automatic, speakerCount: .automatic,
            onUpdate: { update in print("LONG_PERF transcription stage=\(update.stage) elapsed=\(start.duration(to: .now))") }))
        XCTAssertFalse(result.text.isEmpty)
        XCTAssertTrue((result.words ?? []).allSatisfy { $0.startTime >= 0 && $0.endTime <= result.duration + 0.1 })
        print("LONG_PERF transcription media_s=\(result.duration) words=\(result.wordCount) wall=\(start.duration(to: .now))")
    }
}
