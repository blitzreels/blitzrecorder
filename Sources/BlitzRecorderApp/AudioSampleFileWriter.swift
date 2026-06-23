import AVFoundation
import CoreMedia
import Foundation

final class AudioSampleFileWriter: @unchecked Sendable {
    private let url: URL
    private let queue = DispatchQueue(label: "blitzrecorder.audio-writer")
    private let timelineStartTime: CMTime?
    private let stereoBitrate: Int
    private let format: SourceAudioFormat

    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var firstPresentationTime: CMTime?
    private var lastPresentationTime: CMTime?
    private var pauseStartedAt: CMTime?
    private var pauseOffset = CMTime.zero
    private var paused = false
    private var finished = false
    private var wroteSample = false
    private var writeError: Error?
    private static let maximumTrustedTimelineOffsetSeconds: Double = 30
    private static let maximumLeadingTimelineOffsetSeconds: Double = 0.001

    init(
        url: URL,
        timelineStartTime: CMTime? = nil,
        stereoBitrate: Int = 192_000,
        format: SourceAudioFormat = .aac
    ) throws {
        self.url = url
        self.timelineStartTime = timelineStartTime
        self.stereoBitrate = stereoBitrate
        self.format = format
        try? FileManager.default.removeItem(at: url)
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        queue.async {
            guard !self.finished, CMSampleBufferDataIsReady(sampleBuffer) else { return }

            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard presentationTime.isValid else { return }
            self.lastPresentationTime = presentationTime

            if self.firstPresentationTime == nil {
                self.firstPresentationTime = Self.recordingBaseline(
                    timelineStartTime: self.timelineStartTime,
                    firstSampleTime: presentationTime
                )
                do {
                    try self.prepareWriter(for: sampleBuffer)
                } catch {
                    self.failWriting(error)
                    return
                }
            }

            guard !self.paused,
                  let input = self.input,
                  input.isReadyForMoreMediaData,
                  let adjusted = self.copy(sampleBuffer, relativeTo: presentationTime) else {
                return
            }

            if input.append(adjusted) {
                self.wroteSample = true
            } else {
                self.failWriting(
                    self.writer?.error ?? RecorderError.mediaWriteFailed("Audio writer rejected a sample.")
                )
            }
        }
    }

    func pause() {
        queue.async {
            guard !self.paused else { return }
            self.paused = true
            self.pauseStartedAt = self.lastPresentationTime
        }
    }

    func resume() {
        queue.async {
            guard self.paused else { return }
            if let start = self.pauseStartedAt, let end = self.lastPresentationTime {
                let delta = CMTimeSubtract(end, start)
                if delta.isValid, delta.seconds > 0 {
                    self.pauseOffset = CMTimeAdd(self.pauseOffset, delta)
                }
            }
            self.pauseStartedAt = nil
            self.paused = false
        }
    }

    func finish() async throws -> MediaWriterCompletion {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard !self.finished else {
                    if let writeError = self.writeError {
                        try? FileManager.default.removeItem(at: self.url)
                        continuation.resume(throwing: writeError)
                    } else {
                        continuation.resume(returning: self.wroteSample ? .wrote(self.url) : .empty(self.url))
                    }
                    return
                }
                self.finished = true
                guard self.wroteSample else {
                    self.writer?.cancelWriting()
                    try? FileManager.default.removeItem(at: self.url)
                    continuation.resume(returning: .empty(self.url))
                    return
                }
                guard let writer = self.writer, let input = self.input else {
                    continuation.resume(returning: .empty(self.url))
                    return
                }
                input.markAsFinished()
                writer.finishWriting {
                    if let error = writer.error {
                        try? FileManager.default.removeItem(at: self.url)
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: .wrote(self.url))
                    }
                }
            }
        }
    }

    private func prepareWriter(for sampleBuffer: CMSampleBuffer) throws {
        guard writer == nil, input == nil else { return }

        let writer = try AVAssetWriter(outputURL: url, fileType: format.avFileType)
        let outputSettings = outputSettings(for: sampleBuffer)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = true

        guard writer.canAdd(input) else {
            throw RecorderError.writerNotReady
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? RecorderError.writerNotReady
        }
        writer.startSession(atSourceTime: .zero)
        self.writer = writer
        self.input = input
    }

    private func outputSettings(for sampleBuffer: CMSampleBuffer) -> [String: Any] {
        let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)
        let streamDescription = formatDescription.flatMap {
            CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee
        }
        let sampleRate = streamDescription?.mSampleRate ?? 48_000
        let channelCount = max(1, min(2, Int(streamDescription?.mChannelsPerFrame ?? 2)))
        if format.isLossless {
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channelCount,
                AVLinearPCMBitDepthKey: 24,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        }
        return [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVEncoderBitRateKey: channelCount == 1 ? stereoBitrate / 2 : stereoBitrate
        ]
    }

    private func failWriting(_ error: Error) {
        writeError = error
        finished = true
        writer?.cancelWriting()
        try? FileManager.default.removeItem(at: url)
    }

    private func copy(_ sampleBuffer: CMSampleBuffer, relativeTo presentationTime: CMTime) -> CMSampleBuffer? {
        guard let firstPresentationTime else { return nil }

        let elapsed = CMTimeSubtract(presentationTime, firstPresentationTime)
        guard CMTimeCompare(elapsed, .zero) >= 0 else {
            return nil
        }
        var outputTime = CMTimeSubtract(elapsed, pauseOffset)
        if CMTimeCompare(outputTime, .zero) < 0 {
            outputTime = .zero
        }

        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: 0,
            arrayToFill: nil,
            entriesNeededOut: &count
        )
        if count <= 0 {
            count = 1
        }

        var timing = Array(
            repeating: CMSampleTimingInfo(
                duration: CMSampleBufferGetDuration(sampleBuffer),
                presentationTimeStamp: presentationTime,
                decodeTimeStamp: CMSampleBufferGetDecodeTimeStamp(sampleBuffer)
            ),
            count: count
        )

        timing.withUnsafeMutableBufferPointer { buffer in
            _ = CMSampleBufferGetSampleTimingInfoArray(
                sampleBuffer,
                entryCount: count,
                arrayToFill: buffer.baseAddress,
                entriesNeededOut: &count
            )
        }

        let delta = CMTimeSubtract(outputTime, presentationTime)
        for index in timing.indices {
            if timing[index].presentationTimeStamp.isValid {
                timing[index].presentationTimeStamp = CMTimeAdd(timing[index].presentationTimeStamp, delta)
            } else {
                timing[index].presentationTimeStamp = outputTime
            }

            if timing[index].decodeTimeStamp.isValid {
                timing[index].decodeTimeStamp = CMTimeAdd(timing[index].decodeTimeStamp, delta)
            }
        }

        var adjusted: CMSampleBuffer?
        let status = timing.withUnsafeBufferPointer { buffer in
            CMSampleBufferCreateCopyWithNewTiming(
                allocator: kCFAllocatorDefault,
                sampleBuffer: sampleBuffer,
                sampleTimingEntryCount: count,
                sampleTimingArray: buffer.baseAddress,
                sampleBufferOut: &adjusted
            )
        }

        guard status == noErr else { return nil }
        return adjusted
    }

    private static func recordingBaseline(timelineStartTime: CMTime?, firstSampleTime: CMTime) -> CMTime {
        guard let timelineStartTime,
              timelineStartTime.isValid,
              firstSampleTime.isValid else {
            return firstSampleTime
        }

        let offset = CMTimeSubtract(firstSampleTime, timelineStartTime).seconds
        guard offset.isFinite,
              abs(offset) <= maximumTrustedTimelineOffsetSeconds else {
            NSLog(
                "Audio writer ignoring mismatched timeline start offset %.3fs; using first sample time.",
                offset
            )
            return firstSampleTime
        }

        if offset > maximumLeadingTimelineOffsetSeconds {
            NSLog(
                "Audio writer trimming %.3fs source startup gap; using first sample time.",
                offset
            )
            return firstSampleTime
        }

        if offset < -maximumLeadingTimelineOffsetSeconds {
            NSLog(
                "Audio writer ignoring leading timeline start offset %.3fs; using first sample time.",
                offset
            )
            return firstSampleTime
        }

        return timelineStartTime
    }
}
