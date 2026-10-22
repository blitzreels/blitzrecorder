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
    private var lastWrittenPresentationTime: CMTime?
    private var pauseClock = MediaWriterPauseClock()
    private let finalization = MediaWriterFinalization()
    private var finished = false
    private var wroteSample = false
    private var writeError: Error?
    private var hasReportedFailure = false
    var onFailure: (@MainActor (Error) -> Void)?
    private static let maximumTrustedTimelineOffsetSeconds: Double = 30

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
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: url.path])
        }
        writer = try AVAssetWriter(outputURL: url, fileType: outputFormat.avFileType)
        writer.movieFragmentInterval = CMTime(seconds: 10, preferredTimescale: 600)
        writer.initialMovieFragmentInterval = CMTime(seconds: 1, preferredTimescale: 600)

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
            guard self.writer.status != .failed else {
                self.failWriting(self.writer.error ?? RecorderError.writerNotReady)
                return
            }

            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard presentationTime.isNumeric else {
                return
            }

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

            guard !self.pauseClock.isPaused else {
                return
            }

            guard self.input.isReadyForMoreMediaData,
                  let adjusted = self.copy(sampleBuffer, relativeTo: presentationTime) else {
                return
            }

            let outputTime = CMSampleBufferGetPresentationTimeStamp(adjusted)
            guard outputTime.isNumeric else { return }
            if let lastWrittenPresentationTime = self.lastWrittenPresentationTime,
               CMTimeCompare(outputTime, lastWrittenPresentationTime) <= 0 {
                return
            }

            if self.input.append(adjusted) {
                self.wroteSample = true
                self.lastWrittenPresentationTime = outputTime
            } else {
                self.failWriting(
                    self.writer.error ?? RecorderError.mediaWriteFailed("Video writer rejected a sample.")
                )
            }
        }
    }

    func pause() {
        let hostTime = CMClockGetTime(CMClockGetHostTimeClock())
        queue.async {
            self.pauseClock.pause(at: hostTime)
        }
    }

    func resume() {
        let hostTime = CMClockGetTime(CMClockGetHostTimeClock())
        queue.async {
            self.pauseClock.resume(at: hostTime)
        }
    }

    func finish() async throws -> MediaWriterCompletion {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard self.finalization.begin(continuation) else { return }
                self.finished = true
                if self.writer.status == .failed, self.writeError == nil {
                    self.failWriting(self.writer.error ?? RecorderError.writerNotReady)
                }
                if let writeError = self.writeError {
                    self.finalization.complete(.failure(writeError))
                    return
                }
                guard self.wroteSample else {
                    self.writer.cancelWriting()
                    try? FileManager.default.removeItem(at: self.url)
                    self.finalization.complete(.success(.empty(self.url)))
                    return
                }
                self.input.markAsFinished()
                self.writer.finishWriting {
                    self.queue.async {
                        guard self.writer.status == .completed else {
                            self.finalization.complete(.failure(self.writer.error ?? RecorderError.writerNotReady))
                            return
                        }
                        self.finalization.complete(.success(.wrote(self.url)))
                    }
                }
            }
        }
    }

    private func failWriting(_ error: Error) {
        writeError = error
        finished = true
        if !wroteSample {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
        }
        guard !hasReportedFailure else { return }
        hasReportedFailure = true
        let onFailure = onFailure
        Task { @MainActor in
            onFailure?(error)
        }
    }

    private func copy(_ sampleBuffer: CMSampleBuffer, relativeTo presentationTime: CMTime) -> CMSampleBuffer? {
        guard let firstPresentationTime else { return nil }

        let elapsed = CMTimeSubtract(presentationTime, firstPresentationTime)
        guard CMTimeCompare(elapsed, .zero) >= 0 else {
            return nil
        }
        var outputTime = CMTimeSubtract(elapsed, pauseClock.offset)
        if CMTimeCompare(outputTime, .zero) < 0 {
            outputTime = .zero
        }
        return sampleBuffer.retimed(toPresentationTime: outputTime)
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

        return timelineStartTime
    }
}
