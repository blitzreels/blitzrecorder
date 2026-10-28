import AVFoundation
@testable import BlitzRecorderApp
import XCTest

final class VoiceIsolationTests: XCTestCase {
    func testProjectsSavedBeforeVoiceIsolationKeepTheNoiseFilter() throws {
        let saved = #"{"isEnabled":true,"strength":0.65,"normalizesSpeech":false,"ducksMusic":true}"#
        let settings = try JSONDecoder().decode(VoiceCleanupSettings.self, from: Data(saved.utf8))
        XCTAssertEqual(settings.method, .noiseFilter)
        XCTAssertEqual(VoiceCleanupLevel(settings: settings), .medium)
        var isolated = VoiceCleanupLevel.voiceOnly.applied(to: settings)
        XCTAssertEqual(isolated.method, .voiceIsolation)
        XCTAssertTrue(isolated.ducksMusic, "choosing a level keeps the other cleanup choices")
        XCTAssertEqual(try JSONDecoder().decode(VoiceCleanupSettings.self, from: JSONEncoder().encode(isolated)), isolated)
        isolated = VoiceCleanupLevel.light.applied(to: isolated)
        XCTAssertEqual(isolated.method, .noiseFilter)
        XCTAssertEqual(VoiceCleanupLevel(settings: isolated), .light)
    }

    func testIsolationKeepsTheSourcesExactLength() throws {
        try XCTSkipUnless(VoiceIsolation.isAvailable, "This Mac has no voice isolation model")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("input.caf")
        let output = directory.appendingPathComponent("output.caf")
        let rate = 48_000.0
        let count = 150_017
        let samples = (0..<count).map { index -> Float in
            let time = Double(index) / rate
            return Float(0.2 * sin(2 * .pi * 180 * time) * (0.5 + 0.5 * sin(2 * .pi * 3 * time)))
        }
        try write(samples, rate: rate, to: input)
        try VoiceIsolation.process(.init(source: input, destination: output, progress: { _ in }))
        XCTAssertEqual(try AVAudioFile(forReading: output).length, AVAudioFramePosition(count))
    }

    /// Set BLITZRECORDER_NOISY_SPEECH_FIXTURE to a WAV of someone talking in a crowded room to check the result.
    func testIsolationRemovesACrowdAndKeepsTheVoiceOnTheLips() async throws {
        guard let path = ProcessInfo.processInfo.environment["BLITZRECORDER_NOISY_SPEECH_FIXTURE"] else {
            throw XCTSkip("BLITZRECORDER_NOISY_SPEECH_FIXTURE is not set")
        }
        try XCTSkipUnless(VoiceIsolation.isAvailable, "This Mac has no voice isolation model")
        let input = URL(fileURLWithPath: path)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("isolated-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: output) }
        try VoiceIsolation.process(.init(source: input, destination: output, progress: { _ in }))
        let (original, rate) = try mono(input)
        let (isolated, _) = try mono(output)
        XCTAssertEqual(original.count, isolated.count)
        let before = levels(original, rate: rate), after = levels(isolated, rate: rate)
        print("voice isolation gap", before.speech - before.quiet, "->", after.speech - after.quiet, "dB")
        XCTAssertGreaterThan(before.quiet - after.quiet, 10, "the crowd between words is at least 10 dB quieter")
        XCTAssertGreaterThan(after.speech - after.quiet, before.speech - before.quiet + 8)
        XCTAssertLessThanOrEqual(abs(lagMilliseconds(original, isolated, rate: rate)), 1, "no delay left after compensation")

        var settings = VoiceCleanupLevel.voiceOnly.applied(to: VoiceCleanupSettings())
        settings.isEnabled = true
        let cleaned = try await VoiceCleanupProcessor.shared.processed(.init(url: input, settings: settings, progress: { _ in }))
        let duration = try await AVURLAsset(url: cleaned).load(.duration).seconds
        XCTAssertEqual(duration, Double(original.count) / rate, accuracy: 0.1)
    }

    private func write(_ samples: [Float], rate: Double, to url: URL) throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)))
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    /// One read can return less than asked, so the file is read in blocks until its end.
    private func mono(_ url: URL) throws -> ([Float], Double) {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 65_536))
        let channels = Int(buffer.format.channelCount)
        var samples: [Float] = []
        while file.framePosition < file.length {
            try file.read(into: buffer)
            guard buffer.frameLength > 0, let data = buffer.floatChannelData else { break }
            for index in 0..<Int(buffer.frameLength) {
                samples.append((0..<channels).reduce(0) { $0 + data[$1][index] } / Float(channels))
            }
        }
        return (samples, file.processingFormat.sampleRate)
    }

    /// The quietest tenth and the loudest tenth of 100 ms steps, in dB.
    private func levels(_ samples: [Float], rate: Double) -> (quiet: Double, speech: Double) {
        let step = Int(rate / 10)
        let decibels = stride(from: 0, to: samples.count - step, by: step).map { start -> Double in
            let slice = samples[start..<(start + step)]
            return 20 * log10(Double(sqrt(slice.reduce(0) { $0 + $1 * $1 } / Float(step))) + 1e-9)
        }.sorted()
        return (decibels[decibels.count / 10], decibels[decibels.count * 9 / 10])
    }

    private func lagMilliseconds(_ original: [Float], _ processed: [Float], rate: Double) -> Double {
        let start = Int(5 * rate), length = Int(5 * rate), search = Int(0.2 * rate)
        var best = (lag: 0, value: -Float.greatestFiniteMagnitude)
        for lag in stride(from: -search, through: search, by: 1) {
            var dot: Float = 0
            for index in stride(from: start, to: start + length, by: 4) { dot += original[index] * processed[index + lag] }
            if dot > best.value { best = (lag, dot) }
        }
        return Double(best.lag) / rate * 1_000
    }
}
