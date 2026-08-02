import AVFoundation
import CoreMedia
import XCTest
@testable import BlitzRecorderApp

final class AudioClockNormalizerTests: XCTestCase {
    func testCorrectsAACDurationToMasterClock() async throws {
        try await assertCorrection(format: .aac)
    }

    func testCorrectsWAVDurationToMasterClock() async throws {
        try await assertCorrection(format: .wav)
    }

    private func assertCorrection(format: SourceAudioFormat) async throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent("audio.\(format.fileExtension)")
        let sourceDurationSeconds = 12.0
        try await writeSilentAudio(
            AudioClockTestFileRequest(
                url: url,
                format: format,
                durationSeconds: sourceDurationSeconds
            )
        )
        let originalDuration = try await AVURLAsset(url: url).load(.duration)
        let rate = 1.005
        let measurement = CaptureClockRateMeasurement(
            sourceDuration: CMTime(seconds: sourceDurationSeconds, preferredTimescale: 1_000_000_000),
            masterDuration: CMTime(
                seconds: sourceDurationSeconds * rate,
                preferredTimescale: 1_000_000_000
            )
        )

        let result = try await AudioClockNormalizer.normalize(.init(
            url: url,
            format: format,
            bitrate: 192_000,
            measurement: measurement
        ))
        let correctedAsset = AVURLAsset(url: url)
        let correctedDuration = try await correctedAsset.load(.duration)
        let tracks = try await correctedAsset.loadTracks(withMediaType: .audio)
        let expectedDuration = originalDuration.seconds * rate

        XCTAssertTrue(result.didCorrect)
        XCTAssertFalse(tracks.isEmpty)
        XCTAssertEqual(correctedDuration.seconds, expectedDuration, accuracy: 0.05)
    }

    private func writeSilentAudio(_ request: AudioClockTestFileRequest) async throws {
        let writer = try AudioSampleFileWriter(
            url: request.url,
            format: request.format
        )
        let framesPerPacket = 4_800
        let sampleRate = 48_000
        let packetCount = Int(request.durationSeconds * Double(sampleRate) / Double(framesPerPacket))
        for packet in 0..<packetCount {
            writer.append(try silentSampleBuffer(.init(
                presentationTime: CMTime(
                    value: CMTimeValue(packet * framesPerPacket),
                    timescale: CMTimeScale(sampleRate)
                ),
                frames: framesPerPacket,
                sampleRate: sampleRate
            )))
        }
        _ = try await writer.finish()
    }

    private func silentSampleBuffer(_ request: AudioClockTestSampleRequest) throws -> CMSampleBuffer {
        var description = AudioStreamBasicDescription(
            mSampleRate: Double(request.sampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var formatDescription: CMAudioFormatDescription?
        let formatStatus = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &description,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard formatStatus == noErr, let formatDescription else {
            throw RecorderError.writerNotReady
        }

        let byteCount = request.frames * Int(description.mBytesPerFrame)
        var blockBuffer: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: byteCount,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: byteCount,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard blockStatus == noErr, let blockBuffer else {
            throw RecorderError.writerNotReady
        }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(request.sampleRate)),
            presentationTimeStamp: request.presentationTime,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: request.frames,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr, let sampleBuffer else {
            throw RecorderError.writerNotReady
        }
        return sampleBuffer
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}

private struct AudioClockTestFileRequest {
    let url: URL
    let format: SourceAudioFormat
    let durationSeconds: Double
}

private struct AudioClockTestSampleRequest {
    let presentationTime: CMTime
    let frames: Int
    let sampleRate: Int
}
