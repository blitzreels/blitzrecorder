import AVFoundation
import XCTest
@testable import BlitzRecorderApp

final class AudioBackupCheckTests: XCTestCase {
    private static let sampleRate = 8_000.0
    private static let takeSeconds = 2_400.0
    private static let stallAt = 180.0
    private static let stallSeconds = 2.5

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AudioBackupCheck-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// A 40 min take whose file lost 2.5 s at 3:00: the file is rebuilt with silence there, as long as the backup.
    func testFileThatLostSamplesMidTakeIsRebuiltToTheBackupTimeline() async throws {
        let audioURL = root.appendingPathComponent("audio.wav")
        try writeBackup(.init(audioURL: audioURL, stall: true))
        try writeFile(.init(url: audioURL, seconds: Self.takeSeconds - Self.stallSeconds))

        let outcome = await AudioBackupCheck.verify(request(audioURL))

        guard case .rebuilt = outcome else { return XCTFail("Expected a rebuild, got \(outcome)") }
        await TakeSyncJournal.flush()
        let report = TakeSyncReport(events: TakeSyncJournal.events(in: root))
        XCTAssertEqual(report.lines, [.init(
            text: "Microphone had no sound for 2.50 s at 3:00; silence fills the gap, so it stays in sync", isOpen: false
        )])
        let rebuilt = try AVAudioFile(forReading: audioURL)
        XCTAssertEqual(Double(rebuilt.length) / rebuilt.fileFormat.sampleRate, Self.takeSeconds, accuracy: 0.01)
        XCTAssertEqual(try level(.init(file: rebuilt, at: Self.stallAt + 1)), 0)
        XCTAssertEqual(try level(.init(file: rebuilt, at: Self.stallAt - 1)), 0.5, accuracy: 0.001)
        XCTAssertEqual(try level(.init(file: rebuilt, at: Self.stallAt + Self.stallSeconds + 1)), 0.5, accuracy: 0.001)
        let segments = TakeRecoveryFiles.audioSegments(audioURL: audioURL)
        XCTAssertTrue(TakeRecoveryFiles.isKept(audioSegments: segments))

        let recovery = TakeRecoveryFiles.directory(takeDirectory: root)
        try Data().write(to: TakeRecoveryFiles.journal(takeDirectory: root))
        TakeRecoveryFiles.removeRecovery(takeRecoveryDirectory: recovery)
        XCTAssertFalse(FileManager.default.fileExists(atPath: TakeRecoveryFiles.journal(takeDirectory: root).path))
        XCTAssertFalse(AudioRecoverySegment.finished(in: segments).isEmpty)
    }

    /// The file and its backup normally differ by about 0.1 s at the ends; the file is still built from the
    /// backup so it follows the timestamps, and the backup is not kept.
    func testHealthyFileIsBuiltFromItsBackup() async throws {
        let audioURL = root.appendingPathComponent("audio.wav")
        try writeBackup(.init(audioURL: audioURL, stall: false))
        try writeFile(.init(url: audioURL, seconds: Self.takeSeconds - 0.1))

        let outcome = await AudioBackupCheck.verify(request(audioURL))

        XCTAssertEqual(outcome, .built)
        let built = try AVAudioFile(forReading: audioURL)
        XCTAssertEqual(Double(built.length) / built.fileFormat.sampleRate, Self.takeSeconds, accuracy: 0.01)
        XCTAssertFalse(TakeRecoveryFiles.isKept(audioSegments: TakeRecoveryFiles.audioSegments(audioURL: audioURL)))
        TakeRecoveryFiles.removeRecovery(takeRecoveryDirectory: TakeRecoveryFiles.directory(takeDirectory: root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: TakeRecoveryFiles.directory(takeDirectory: root).path))
    }

    /// A backup that missed audio through its own fault cannot replace a file that looks whole.
    func testFileIsKeptWhenTheBackupMissedAudio() async throws {
        let audioURL = root.appendingPathComponent("audio.wav")
        try writeBackup(.init(audioURL: audioURL, stall: false))
        try writeFile(.init(url: audioURL, seconds: Self.takeSeconds - 0.1))

        let outcome = await AudioBackupCheck.verify(.init(
            audioURL: audioURL, format: .wav, stereoBitrate: 192_000, timelineStart: 0,
            backup: .init(lostChunks: 3, lostSeconds: 0.03)
        ))

        guard case .kept = outcome else { return XCTFail("Expected the file to be kept, got \(outcome)") }
        let kept = try AVAudioFile(forReading: audioURL)
        XCTAssertEqual(Double(kept.length) / kept.fileFormat.sampleRate, Self.takeSeconds - 0.1, accuracy: 0.01)
    }

    /// A source clock 100 ppm off: each segment is stretched to meet the next, so no join inserts or cuts audio.
    func testStitcherAbsorbsClockDriftWithoutSilence() throws {
        let audioURL = root.appendingPathComponent("audio.wav")
        let directory = TakeRecoveryFiles.audioSegments(audioURL: audioURL)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1))
        let spacing = 5.0005
        for index in 0..<120 {
            let url = directory.appendingPathComponent(
                AudioRecoverySegment.fileName(index: index + 1, timelineSeconds: Double(index) * spacing)
            )
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer(.init(format: format, seconds: 5, level: 0.5)))
            file.close()
        }
        let output = root.appendingPathComponent("stitched.wav")

        let result = try XCTUnwrap(AudioRecoveryStitcher.stitch(.init(
            directory: directory, outputURL: output, format: .wav, stereoBitrate: 192_000, timelineStart: 0
        )))

        XCTAssertEqual(result.silenceSeconds, 0)
        XCTAssertEqual(result.timelineEnd, 119 * spacing + 5, accuracy: 0.001)
        let file = try AVAudioFile(forReading: output)
        XCTAssertEqual(try level(.init(file: file, at: 119 * spacing - 0.001)), 0.5, accuracy: 0.001)
    }

    func testStretchLeavesRealGapsToSilence() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1))
        let segment = try buffer(.init(format: format, seconds: 5, level: 0.5))
        let drift = AudioRecoveryStitcher.stretched(.init(buffer: segment, seconds: 5.001))
        XCTAssertEqual(drift.frameLength, AVAudioFrameCount((5.001 * Self.sampleRate).rounded()))
        XCTAssertEqual(drift.floatChannelData?[0][Int(drift.frameLength) - 1] ?? 0, 0.5, accuracy: 0.0001)
        let gap = AudioRecoveryStitcher.stretched(.init(buffer: segment, seconds: 5.1))
        XCTAssertEqual(gap.frameLength, segment.frameLength)
    }

    func testDecisionIgnoresSmallClockDriftButNotAHole() {
        let drifting = (0..<480).map { index in
            AudioBackupCheck.Span(start: Double(index) * 5.0005, duration: 5)
        }
        XCTAssertTrue(AudioBackupCheck.gaps(drifting).isEmpty)
        XCTAssertEqual(AudioBackupCheck.decide(.init(fileSeconds: 2_400, backup: drifting, backupIsComplete: true)), .build)
        guard case .keep = AudioBackupCheck.decide(.init(fileSeconds: 2_400, backup: drifting, backupIsComplete: false)) else {
            return XCTFail("An incomplete backup must not replace a whole file")
        }

        var stalled = drifting
        stalled[36] = .init(start: stalled[36].start + 0.06, duration: 5)
        XCTAssertEqual(AudioBackupCheck.gaps(stalled).count, 1)
        guard case .rebuild = AudioBackupCheck.decide(.init(fileSeconds: 2_400, backup: stalled, backupIsComplete: false)) else {
            return XCTFail("A 0.06 s hole must rebuild the file")
        }
    }

    private func request(_ audioURL: URL) -> AudioBackupCheck.Request {
        .init(audioURL: audioURL, format: .wav, stereoBitrate: 192_000, timelineStart: 0, backup: .init())
    }

    private struct Backup {
        let audioURL: URL
        let stall: Bool
    }

    /// One-minute segments of a constant 0.5 level, like the recorder's 5 s ones but fewer files.
    private func writeBackup(_ backup: Backup) throws {
        let directory = TakeRecoveryFiles.audioSegments(audioURL: backup.audioURL)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1))
        var spans: [(start: Double, seconds: Double)] = []
        var start = 0.0
        var recorded = 0.0
        let audioSeconds = Self.takeSeconds - (backup.stall ? Self.stallSeconds : 0)
        while recorded < audioSeconds - 0.0001 {
            let boundary = backup.stall && start < Self.stallAt ? Self.stallAt - start : 60.0
            let seconds = min(boundary, 60, audioSeconds - recorded)
            spans.append((start, seconds))
            recorded += seconds
            start += seconds
            if backup.stall, abs(start - Self.stallAt) < 0.0001 { start += Self.stallSeconds }
        }
        for (index, span) in spans.enumerated() {
            let url = directory.appendingPathComponent(AudioRecoverySegment.fileName(index: index + 1, timelineSeconds: span.start))
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer(.init(format: format, seconds: span.seconds, level: 0.5)))
            file.close()
        }
    }

    private struct FileRequest {
        let url: URL
        let seconds: Double
    }

    private func writeFile(_ request: FileRequest) throws {
        let settings = SourceAudioFormat.wav.outputSettings(.init(sampleRate: Self.sampleRate, channelCount: 1,
                                                                  stereoBitrate: 192_000))
        let file = try AVAudioFile(forWriting: request.url, settings: settings, commonFormat: .pcmFormatFloat32,
                                   interleaved: false)
        try file.write(from: buffer(.init(format: file.processingFormat, seconds: request.seconds, level: 0.5)))
    }

    private struct BufferRequest {
        let format: AVAudioFormat
        let seconds: Double
        let level: Float
    }

    private func buffer(_ request: BufferRequest) throws -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount((request.seconds * request.format.sampleRate).rounded())
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: request.format, frameCapacity: frames))
        buffer.frameLength = frames
        buffer.floatChannelData?[0].update(repeating: request.level, count: Int(frames))
        return buffer
    }

    private struct LevelProbe {
        let file: AVAudioFile
        let at: Double
    }

    private func level(_ probe: LevelProbe) throws -> Float {
        let file = probe.file
        file.framePosition = AVAudioFramePosition(probe.at * file.processingFormat.sampleRate)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16))
        try file.read(into: buffer, frameCount: 16)
        return buffer.floatChannelData?[0][8] ?? -1
    }
}
