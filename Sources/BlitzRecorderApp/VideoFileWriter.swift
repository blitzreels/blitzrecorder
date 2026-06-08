import AVFoundation
import CoreMedia
import Foundation
import VideoToolbox

final class VideoFileWriter: @unchecked Sendable {
    private let url: URL
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let queue = DispatchQueue(label: "recorder.video-writer")
    private let timelineStartTime: CMTime?

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
        width: Int,
        height: Int,
        bitrate: Int,
        fps: Int,
        outputFormat: OutputVideoFormat,
        timelineStartTime: CMTime? = nil
    ) throws {
        self.url = url
        self.timelineStartTime = timelineStartTime
        try? FileManager.default.removeItem(at: url)

        writer = try AVAssetWriter(outputURL: url, fileType: outputFormat.avFileType)

        let compression: [String: Any] = [
            AVVideoAverageBitRateKey: bitrate,
            AVVideoExpectedSourceFrameRateKey: fps,
            AVVideoAllowFrameReorderingKey: false,
            AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main_AutoLevel as String
        ]

        let outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compression
        ]

        input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = true

        guard writer.canAdd(input) else {
            throw RecorderError.writerNotReady
        }
        writer.add(input)
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        queue.async {
            guard !self.finished, CMSampleBufferDataIsReady(sampleBuffer) else {
                return
            }

            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard presentationTime.isValid else {
                return
            }
            self.lastPresentationTime = presentationTime

            if self.firstPresentationTime == nil {
                self.firstPresentationTime = Self.recordingBaseline(
                    timelineStartTime: self.timelineStartTime,
                    firstSampleTime: presentationTime
                )
                guard self.writer.startWriting() else {
                    self.failWriting(self.writer.error ?? RecorderError.writerNotReady)
                    return
                }
                self.writer.startSession(atSourceTime: .zero)
            }

            guard !self.paused else {
                return
            }

            guard self.input.isReadyForMoreMediaData,
                  let adjusted = self.copy(sampleBuffer, relativeTo: presentationTime) else {
                return
            }

            if self.input.append(adjusted) {
                self.wroteSample = true
            } else {
                self.failWriting(
                    self.writer.error ?? RecorderError.mediaWriteFailed("Video writer rejected a sample.")
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
                    self.writer.cancelWriting()
                    try? FileManager.default.removeItem(at: self.url)
                    continuation.resume(returning: .empty(self.url))
                    return
                }
                self.input.markAsFinished()
                self.writer.finishWriting {
                    if let error = self.writer.error {
                        try? FileManager.default.removeItem(at: self.url)
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: .wrote(self.url))
                    }
                }
            }
        }
    }

    private func failWriting(_ error: Error) {
        writeError = error
        finished = true
        writer.cancelWriting()
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

        guard status == noErr else {
            return nil
        }
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
                "Video writer ignoring mismatched timeline start offset %.3fs; using first sample time.",
                offset
            )
            return firstSampleTime
        }

        if offset > maximumLeadingTimelineOffsetSeconds {
            NSLog(
                "Video writer trimming %.3fs source startup gap; using first sample time.",
                offset
            )
            return firstSampleTime
        }

        return timelineStartTime
    }
}
