import AVFoundation
import CoreMedia
import XCTest
@testable import BlitzRecorderApp

/// The ways a take has gone out of sync, each pinned so it cannot come back unnoticed.
final class SyncReliabilityTests: XCTestCase {
    private static let fps = 30.0

    // MARK: Video timestamps

    /// A camera that stalls 0.5 s and then carries on with even timestamps: later frames move back by 0.5 s.
    func testCameraStallWithEvenTimestampsIsMovedToCaptureTime() {
        var detector = CaptureClockSlipDetector()
        var slips: [CaptureClockSlipDetector.Slip] = []
        for frame in 0..<200 {
            let presentation = Double(frame) / Self.fps
            let arrival = presentation + 0.02 + (frame >= 100 ? 0.5 : 0)
            if let slip = detector.observe(observation(presentation: presentation, arrival: arrival)) { slips.append(slip) }
        }
        XCTAssertEqual(slips.count, 1)
        XCTAssertEqual(slips.first?.seconds ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(detector.correctionSeconds, 0.5, accuracy: 0.001)
    }

    /// Delivery that jitters by up to 30 ms is not a slip.
    func testJitteryDeliveryIsNotASlip() {
        var detector = CaptureClockSlipDetector()
        var generator = SeededGenerator(seed: 7)
        for frame in 0..<600 {
            let presentation = Double(frame) / Self.fps
            let arrival = presentation + 0.02 + Double.random(in: 0..<0.03, using: &generator)
            XCTAssertNil(detector.observe(observation(presentation: presentation, arrival: arrival)))
        }
        XCTAssertEqual(detector.correctionSeconds, 0)
    }

    /// Frames held up for a moment and then delivered in a burst keep their timestamps: the capture was on time.
    func testBacklogThatCatchesUpIsNotASlip() {
        var detector = CaptureClockSlipDetector()
        for frame in 0..<300 {
            let presentation = Double(frame) / Self.fps
            let backlog = (120..<128).contains(frame) ? Double(128 - frame) * 0.04 : 0
            XCTAssertNil(detector.observe(observation(presentation: presentation, arrival: presentation + 0.02 + backlog)))
        }
        XCTAssertEqual(detector.correctionSeconds, 0)
    }

    private func observation(presentation: Double, arrival: Double) -> CaptureClockSlipDetector.Observation {
        .init(
            presentationTime: CMTime(seconds: 1_000 + presentation, preferredTimescale: 1_000_000_000),
            arrivalTime: CMTime(seconds: 1_000 + arrival, preferredTimescale: 1_000_000_000)
        )
    }

    // MARK: Audio backup timeline

    /// Pause and resume leave no hole in the backup, while a stall while recording does.
    func testBackupContinuesSeamlesslyAcrossAPauseButKeepsAStall() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SyncReliability-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let audioURL = root.appendingPathComponent("audio.m4a")
        let origin = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        let writer = AudioRecoverySegmentWriter(.init(
            audioURL: audioURL, timelineStartTime: CMTime(seconds: origin, preferredTimescale: 1_000_000_000)
        ))
        var pts = origin
        let send = { (seconds: Double) throws in
            for _ in 0..<Int((seconds / 0.01).rounded()) {
                writer.append(try Self.audioSample(at: pts))
                pts += 0.01
            }
        }
        try send(2)
        writer.pause()
        pts += 3
        writer.resume()
        try send(2)
        pts += 0.5
        try send(2)
        let report = await writer.finish()

        XCTAssertTrue(report.isComplete)
        let spans = AudioRecoverySegment.finished(in: TakeRecoveryFiles.audioSegments(audioURL: audioURL)).map { segment in
            let file = try? AVAudioFile(forReading: segment.url)
            return AudioBackupCheck.Span(
                start: segment.timelineSeconds,
                duration: file.map { Double($0.length) / $0.fileFormat.sampleRate } ?? 0
            )
        }
        let gaps = AudioBackupCheck.gaps(spans)
        XCTAssertEqual(gaps.count, 1)
        XCTAssertEqual(gaps.first?.at ?? 0, 4, accuracy: 0.02)
        XCTAssertEqual(gaps.first?.seconds ?? 0, 0.5, accuracy: 0.02)
    }

    private static func audioSample(at seconds: Double) throws -> CMSampleBuffer {
        let frames = 480
        var description = AudioStreamBasicDescription(
            mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 4,
            mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0
        )
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: nil, asbd: &description, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
            extensions: nil, formatDescriptionOut: &format
        )
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: frames * 4, blockAllocator: nil, customBlockSource: nil,
            offsetToData: 0, dataLength: frames * 4, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block
        )
        let blockBuffer = try XCTUnwrap(block)
        CMBlockBufferFillDataBytes(with: 0, blockBuffer: blockBuffer, offsetIntoDestination: 0, dataLength: frames * 4)
        var sample: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: blockBuffer, formatDescription: try XCTUnwrap(format), sampleCount: frames,
            presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 1_000_000_000),
            packetDescriptions: nil, sampleBufferOut: &sample
        )
        return try XCTUnwrap(sample)
    }

    // MARK: Sync test detectors

    /// Beeps under a voice-like hum are found within 5 ms.
    func testToneOnsetsAreFoundUnderOtherSound() {
        let rate = 48_000.0
        let onsets = [1.0, 3.3, 5.2, 7.9]
        var samples = (0..<Int(rate * 9)).map { index -> Float in
            let time = Double(index) / rate
            return Float(0.05 * sin(2 * .pi * 180 * time) + 0.03 * sin(2 * .pi * 2_400 * time))
        }
        for onset in onsets {
            for index in Int(onset * rate)..<Int((onset + 0.1) * rate) {
                samples[index] += Float(0.3 * sin(2 * .pi * SyncTestAnalysis.toneFrequency * Double(index) / rate))
            }
        }
        let found = SyncTestAnalysis.toneOnsets(.init(samples: samples, sampleRate: rate))
        XCTAssertEqual(found.count, onsets.count)
        for (expected, actual) in zip(onsets, found) { XCTAssertEqual(actual, expected, accuracy: 0.005) }
    }

    func testFlashOnsetsAreTheFirstLitFrame() {
        let flashes = [2.0, 4.3]
        let frames = (0..<(30 * 6)).map { frame -> SyncTestAnalysis.Sample in
            let time = Double(frame) / Self.fps
            let lit = flashes.contains { time >= $0 - 0.001 && time < $0 + 0.1 }
            return .init(seconds: time, value: lit ? 0.95 : 0.07)
        }
        let found = SyncTestAnalysis.flashOnsets(frames)
        XCTAssertEqual(found.count, 2)
        for (expected, actual) in zip(flashes, found) { XCTAssertEqual(actual, expected, accuracy: 1 / Self.fps) }
    }

    /// A track that loses 2.44 s mid-test, the stall that started this work, shows as one step, not lost claps.
    func testMatchingFollowsAJumpAndReportsIt() throws {
        var claps: [Double] = []
        var time = 3.0
        for index in 0..<50 {
            claps.append(time)
            time += SyncTestAnalysis.clapIntervals[index % SyncTestAnalysis.clapIntervals.count]
        }
        let screen = try XCTUnwrap(SyncTestAnalysis.match(.init(claps: claps, onsets: claps.map { $0 + 0.016 })))
        let microphone = try XCTUnwrap(SyncTestAnalysis.match(.init(
            claps: claps, onsets: claps.enumerated().map { index, clap in clap + 0.03 - (index >= 25 ? 2.44 : 0) }
        )))
        XCTAssertEqual(microphone.matched.count, 50)
        let comparison = try XCTUnwrap(SyncTestAnalysis.compare(.init(track: microphone, reference: screen)))
        XCTAssertEqual(comparison.largestStep, 2.44, accuracy: 0.001)
        XCTAssertEqual(comparison.drift, -2.44, accuracy: 0.001)
        XCTAssertFalse(comparison.isInSync)

        let nudged = try XCTUnwrap(SyncTestAnalysis.match(.init(
            claps: claps, onsets: claps.enumerated().map { index, clap in clap + 0.03 - (index >= 25 ? 0.08 : 0) }
        )))
        XCTAssertEqual(nudged.matched.count, 50)

        let steady = try XCTUnwrap(SyncTestAnalysis.match(.init(claps: claps, onsets: claps.map { $0 + 0.036 })))
        let inSync = try XCTUnwrap(SyncTestAnalysis.compare(.init(track: steady, reference: screen)))
        XCTAssertEqual(inSync.offset, 0.02, accuracy: 0.001)
        XCTAssertTrue(inSync.isInSync)
    }

    /// A track seconds off still pairs with the right claps, because the gaps between claps are uneven.
    func testMatchingFindsALargeOffset() throws {
        var claps: [Double] = []
        var time = 3.0
        for index in 0..<40 {
            claps.append(time)
            time += SyncTestAnalysis.clapIntervals[index % SyncTestAnalysis.clapIntervals.count]
        }
        let late = try XCTUnwrap(SyncTestAnalysis.match(.init(claps: claps, onsets: claps.map { $0 + 2.44 })))
        XCTAssertEqual(late.matched.count, 40)
        XCTAssertEqual(SyncTestAnalysis.median(late.matched), 2.44, accuracy: 0.001)
    }

    // MARK: Sync report

    func testReportSaysWhatWasRepairedAndWhatIsStillOff() {
        let report = TakeSyncReport(events: [
            .init(track: "audio.m4a", kind: .audioGap, at: 125, seconds: 0.8, detail: nil),
            .init(track: "audio.m4a", kind: .audioKept, at: nil, seconds: nil, detail: "the backup missed audio"),
            .init(track: "camera.mov", kind: .clockSlip, at: 61, seconds: 0.31, detail: nil),
            .init(track: "screen.mov", kind: .trackLength, at: nil, seconds: 0.05, detail: nil),
            .init(track: "system-audio.m4a", kind: .trackLength, at: nil, seconds: -0.6, detail: nil),
        ])
        XCTAssertEqual(report.lines, [
            .init(text: "Microphone had no sound for 0.80 s at 2:05 and may play early after it", isOpen: true),
            .init(text: "Camera fell 0.31 s behind at 1:01 and was moved back to the time it was filmed", isOpen: false),
            .init(text: "System audio is 0.60 s shorter than the recording", isOpen: true),
        ])
        XCTAssertFalse(report.isInSync)
    }

    func testCleanTakeIsReportedInSync() {
        let report = TakeSyncReport(events: [
            .init(track: "audio.m4a", kind: .audioBuilt, at: nil, seconds: nil, detail: nil),
            .init(track: "audio.m4a", kind: .trackLength, at: nil, seconds: -0.07, detail: nil),
            .init(track: "camera.mov", kind: .trackLength, at: nil, seconds: 0.02, detail: nil),
        ])
        XCTAssertTrue(report.lines.isEmpty)
        XCTAssertTrue(report.isInSync)
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}
