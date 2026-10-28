@testable import BlitzRecorderApp
import XCTest

final class AngleAudioSyncTests: XCTestCase {
    private let rate = 8_000.0

    func testFindsALaterStartAcrossDifferentLevelsAndNoise() throws {
        let speech = SpeechLikeSignal(seed: 1).samples(seconds: 150, rate: rate)
        let reference = Array(speech.prefix(Int(120 * rate)))
        let other = noisy(Array(speech[Int(17.35 * rate)..<Int(117.35 * rate)]), gain: 0.3, noise: 0.01, seed: 2)
        let placement = try XCTUnwrap(place(reference: reference, other: other))
        XCTAssertEqual(placement.offset, 17.35, accuracy: 0.012)
        XCTAssertEqual(placement.drift, 0, accuracy: 0.0002)
        XCTAssertTrue(placement.isConfident, "confidence \(placement.confidence), fit error \(placement.fitError)")
    }

    func testFindsAFileThatStartedBeforeTheReference() throws {
        let speech = SpeechLikeSignal(seed: 3).samples(seconds: 140, rate: rate)
        let reference = Array(speech[Int(41.2 * rate)...])
        let other = noisy(Array(speech.prefix(Int(110 * rate))), gain: 2, noise: 0.005, seed: 4)
        let placement = try XCTUnwrap(place(reference: reference, other: other))
        XCTAssertEqual(placement.offset, -41.2, accuracy: 0.012)
        XCTAssertTrue(placement.isConfident)
    }

    func testMeasuresDriftBetweenClocks() throws {
        let speech = SpeechLikeSignal(seed: 5).samples(seconds: 700, rate: rate)
        let reference = Array(speech.prefix(Int(600 * rate)))
        let fast = resampled(Array(speech[Int(30 * rate)..<Int(630 * rate)]), speed: 1.001)
        let placement = try XCTUnwrap(place(reference: reference, other: fast))
        XCTAssertEqual(placement.drift, 0.001, accuracy: 0.0002)
        XCTAssertFalse(placement.isConfident, "a 0.1 % speed difference must be reviewed, not silently trusted")
    }

    func testUnrelatedSoundIsNotTrusted() {
        let reference = SpeechLikeSignal(seed: 7).samples(seconds: 120, rate: rate)
        let other = SpeechLikeSignal(seed: 8).samples(seconds: 100, rate: rate)
        let placement = place(reference: reference, other: other)
        XCTAssertFalse(placement?.isConfident ?? false, "confidence \(placement?.confidence ?? 0)")
    }

    func testLouderSpeechHasTheHigherLevel() {
        let speech = SpeechLikeSignal(seed: 9).samples(seconds: 30, rate: rate)
        let quiet = AngleAudioSync.onsets(.init(samples: speech.map { $0 * 0.1 }, sampleRate: rate))
        let loud = AngleAudioSync.onsets(.init(samples: speech, sampleRate: rate))
        XCTAssertEqual(loud.speechLevel - quiet.speechLevel, 20, accuracy: 0.5)
    }

    /// Set BLITZRECORDER_MULTICAM_FIXTURE to a folder holding a real three-camera shoot to check it end to end:
    /// wide-shot.MOV (reference), plan-emmanuel.MP4 (Osmo Pocket 4) and plan-thomas.MOV (iPhone). ffmpeg puts them
    /// 18.07 s and 72.37 s in; AVFoundation trims the AAC encoder delay that ffmpeg keeps, so it reads the Osmo
    /// 0.03 s later. Two frames at 60 fps covers both.
    func testRealThreeCameraShoot() async throws {
        guard let folder = ProcessInfo.processInfo.environment["BLITZRECORDER_MULTICAM_FIXTURE"] else {
            throw XCTSkip("BLITZRECORDER_MULTICAM_FIXTURE is not set")
        }
        let directory = URL(fileURLWithPath: folder)
        let wide = try await AngleAudioSync.onsets(url: directory.appendingPathComponent("wide-shot.MOV"))
        let osmo = try await AngleAudioSync.onsets(url: directory.appendingPathComponent("plan-emmanuel.MP4"))
        let phone = try await AngleAudioSync.onsets(url: directory.appendingPathComponent("plan-thomas.MOV"))
        let osmoPlacement = try XCTUnwrap(AngleAudioSync.place(.init(reference: wide, other: osmo)))
        let phonePlacement = try XCTUnwrap(AngleAudioSync.place(.init(reference: wide, other: phone)))
        XCTAssertEqual(osmoPlacement.offset, 18.07, accuracy: 0.034)
        XCTAssertEqual(phonePlacement.offset, 72.37, accuracy: 0.034)
        XCTAssertTrue(osmoPlacement.isConfident, "Osmo \(osmoPlacement)")
        XCTAssertTrue(phonePlacement.isConfident, "iPhone \(phonePlacement)")
        XCTAssertGreaterThan(osmo.speechLevel, wide.speechLevel, "the Osmo's close mic is the clearest sound")
    }

    private func place(reference: [Float], other: [Float]) -> AngleAudioSync.Placement? {
        AngleAudioSync.place(.init(
            reference: AngleAudioSync.onsets(.init(samples: reference, sampleRate: rate)),
            other: AngleAudioSync.onsets(.init(samples: other, sampleRate: rate))
        ))
    }

    private func noisy(_ samples: [Float], gain: Float, noise: Float, seed: UInt64) -> [Float] {
        var random = SeededRandom(seed: seed)
        return samples.map { $0 * gain + (random.unit() * 2 - 1) * noise }
    }

    private func resampled(_ samples: [Float], speed: Double) -> [Float] {
        let count = Int(Double(samples.count) / speed)
        return (0..<count).map { index in
            let position = Double(index) * speed
            let low = Int(position), fraction = Float(position - Double(low))
            guard low + 1 < samples.count else { return samples[min(low, samples.count - 1)] }
            return samples[low] * (1 - fraction) + samples[low + 1] * fraction
        }
    }
}

/// Bursts of noise shaped like syllables, with pauses between phrases: enough structure to sync by, and every
/// seed gives a different conversation.
private struct SpeechLikeSignal {
    let seed: UInt64

    func samples(seconds: Double, rate: Double) -> [Float] {
        var random = SeededRandom(seed: seed)
        var output = [Float](repeating: 0, count: Int(seconds * rate))
        var cursor = 0
        while cursor < output.count {
            let syllable = Int((0.08 + Double(random.unit()) * 0.25) * rate)
            let level = 0.1 + random.unit() * 0.6
            for index in 0..<syllable where cursor + index < output.count {
                let envelope = sin(Float.pi * Float(index) / Float(syllable))
                output[cursor + index] = (random.unit() * 2 - 1) * level * envelope
            }
            let pause = random.unit() < 0.15 ? 0.4 + Double(random.unit()) * 0.9 : 0.03 + Double(random.unit()) * 0.12
            cursor += syllable + Int(pause * rate)
        }
        return output
    }
}

private struct SeededRandom {
    var state: UInt64

    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 &+ 1 }

    mutating func unit() -> Float {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return Float((z ^ (z >> 31)) >> 40) / Float(1 << 24)
    }
}
