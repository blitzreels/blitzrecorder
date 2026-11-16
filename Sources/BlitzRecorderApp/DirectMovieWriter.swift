import AVFoundation
import CoreMedia
import Foundation
import os
import VideoToolbox

private let movieWriterLog = Logger(subsystem: "dev.blitzreels.blitzrecorder", category: "movie-writer")

final class DirectMovieWriter: @unchecked Sendable {
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audioInputs: [CaptureSource: AVAssetWriterInput]
    private let finalURL: URL
    private let temporaryURL: URL
    private let queue = DispatchQueue(label: "blitzrecorder.direct-movie-writer")
    /// Frames are composed here, so a slow frame never holds up sound on the writer queue.
    private let renderQueue = DispatchQueue(label: "blitzrecorder.direct-movie-render", qos: .userInitiated)
    private let framesInFlight = OSAllocatedUnfairLock(initialState: 0)
    private static let maximumFramesInFlight = 2

    private var audioBacklogs: [CaptureSource: PendingAudioBacklog] = [:]

    private struct RenderedFrame {
        let pixelBuffer: CVPixelBuffer
        let presentationTime: CMTime
    }
    private let recordingStartHostTime: CMTime

    private var pauseClock = MediaWriterPauseClock()
    private let finalization = MediaWriterFinalization()
    private var finished = false
    private var wroteVideo = false
    private var lastWrittenVideoTime: CMTime?
    private var writeError: Error?
    private var hasReportedFailure = false
    var onFailure: (@MainActor (Error) -> Void)?

    init(take: RecordingTake, settings: RecordingSettings) throws {
        finalURL = take.finalVideoURL
        temporaryURL = take.scratchDirectory
            .appendingPathComponent("interrupted-recording-\(UUID().uuidString).\(take.outputVideoFormat.fileExtension)")

        writer = try AVAssetWriter(outputURL: temporaryURL, fileType: take.outputVideoFormat.avFileType)
        writer.movieFragmentInterval = CMTime(seconds: 10, preferredTimescale: 600)
        writer.initialMovieFragmentInterval = CMTime(seconds: 1, preferredTimescale: 600)

        let dimensions = ScreenCaptureGeometry.outputDimensions(for: settings)
        let compression: [String: Any] = [
            AVVideoAverageBitRateKey: settings.finalVideoBitrate,
            AVVideoExpectedSourceFrameRateKey: settings.framesPerSecond,
            AVVideoAllowFrameReorderingKey: false,
            AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main_AutoLevel as String
        ]
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: dimensions.width,
            AVVideoHeightKey: dimensions.height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ],
            AVVideoCompressionPropertiesKey: compression
        ]

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(videoInput) else {
            throw RecorderError.writerNotReady
        }
        writer.add(videoInput)

        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: dimensions.width,
                kCVPixelBufferHeightKey as String: dimensions.height,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )

        var inputs: [CaptureSource: AVAssetWriterInput] = [:]
        if settings.enabledSources.contains(.microphone) {
            inputs[.microphone] = try Self.makeAudioInput(for: writer, bitrate: settings.finalAudioBitrate)
        }
        if settings.enabledSources.contains(.systemAudio) {
            inputs[.systemAudio] = try Self.makeAudioInput(for: writer, bitrate: settings.finalAudioBitrate)
        }
        audioInputs = inputs

        guard writer.startWriting() else {
            throw writer.error ?? RecorderError.writerNotReady
        }
        recordingStartHostTime = CMClockGetTime(CMClockGetHostTimeClock())
        writer.startSession(atSourceTime: .zero)
    }

    /// Composes a frame off the writer queue. When two frames are already being composed, this one is skipped
    /// instead of queued, so a slow scene drops frames rather than building up delay.
    func appendVideo(sourceTime: CMTime, render: @escaping (CVPixelBuffer) -> Bool) {
        guard sourceTime.isNumeric, framesInFlight.withLock({ count in
            guard count < Self.maximumFramesInFlight else { return false }
            count += 1
            return true
        }) else { return }
        renderQueue.async {
            defer { self.framesInFlight.withLock { $0 -= 1 } }
            guard let presentationTime = self.queue.sync(execute: { self.nextVideoPresentationTime(for: sourceTime) }),
                  let pool = self.adaptor.pixelBufferPool else { return }
            var pixelBuffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer) == kCVReturnSuccess,
                  let pixelBuffer,
                  render(pixelBuffer) else { return }
            self.queue.async { self.appendRenderedFrame(.init(pixelBuffer: pixelBuffer, presentationTime: presentationTime)) }
        }
    }

    private func nextVideoPresentationTime(for sourceTime: CMTime) -> CMTime? {
        guard !finished, !pauseClock.isPaused else { return nil }
        guard writer.status != .failed else {
            failWriting(writer.error ?? RecorderError.writerNotReady)
            return nil
        }
        let presentationTime = presentationTime(for: sourceTime)
        guard presentationTime.isNumeric, videoInput.isReadyForMoreMediaData else { return nil }
        if let lastWrittenVideoTime, CMTimeCompare(presentationTime, lastWrittenVideoTime) <= 0 { return nil }
        return presentationTime
    }

    private func appendRenderedFrame(_ frame: RenderedFrame) {
        guard !finished, !pauseClock.isPaused, writer.status != .failed,
              videoInput.isReadyForMoreMediaData else { return }
        if let lastWrittenVideoTime, CMTimeCompare(frame.presentationTime, lastWrittenVideoTime) <= 0 { return }
        if adaptor.append(frame.pixelBuffer, withPresentationTime: frame.presentationTime) {
            wroteVideo = true
            lastWrittenVideoTime = frame.presentationTime
        } else {
            failWriting(writer.error ?? RecorderError.mediaWriteFailed("Direct movie writer rejected a video frame."))
        }
    }

    /// Sound is timed when it arrives, not when the writer gets to it, so a busy writer cannot shift it.
    func appendAudio(_ sampleBuffer: CMSampleBuffer, source: CaptureSource) {
        let arrivedAt = currentHostTime()
        queue.async {
            guard !self.finished,
                  !self.pauseClock.isPaused,
                  self.wroteVideo,
                  arrivedAt.isValid,
                  CMSampleBufferDataIsReady(sampleBuffer),
                  let input = self.audioInputs[source],
                  let retimed = sampleBuffer.retimed(toPresentationTime: self.presentationTime(for: arrivedAt)) else {
                return
            }
            var backlog = self.audioBacklogs[source, default: PendingAudioBacklog()]
            backlog.add(retimed)
            let result = backlog.drain(into: input)
            self.audioBacklogs[source] = backlog
            if result.rejected { self.failAudioWrite() }
        }
    }

    private func failAudioWrite() {
        failWriting(writer.error ?? RecorderError.mediaWriteFailed("Direct movie writer rejected an audio sample."))
    }

    /// Runs after the video input is finished, so the writer no longer holds sound back to keep it in step with
    /// video that will not come.
    private func flushAudioBacklogs() {
        var dropped = 0
        for (source, input) in audioInputs {
            guard var backlog = audioBacklogs[source] else { continue }
            let result = backlog.flush(into: input)
            dropped += backlog.droppedCount
            audioBacklogs[source] = backlog
            if result.rejected {
                failAudioWrite()
                return
            }
        }
        if dropped > 0 { movieWriterLog.error("Dropped \(dropped, privacy: .public) audio buffers") }
    }

    func pause() {
        queue.async {
            self.pauseClock.pause(at: self.currentHostTime())
        }
    }

    func resume() {
        queue.async {
            self.pauseClock.resume(at: self.currentHostTime())
        }
    }

    func finish() async throws -> MediaWriterCompletion {
        try await withCheckedThrowingContinuation { continuation in
            renderQueue.async { self.queue.async {
                guard self.finalization.begin(continuation) else { return }
                self.finished = true
                if self.writer.status == .failed, self.writeError == nil {
                    self.failWriting(self.writer.error ?? RecorderError.writerNotReady)
                }
                if let writeError = self.writeError {
                    self.finalization.complete(.failure(writeError))
                    return
                }
                guard self.wroteVideo else {
                    self.writer.cancelWriting()
                    try? FileManager.default.removeItem(at: self.temporaryURL)
                    self.finalization.complete(.success(.empty(self.temporaryURL)))
                    return
                }
                self.videoInput.markAsFinished()
                self.flushAudioBacklogs()
                if let writeError = self.writeError {
                    self.finalization.complete(.failure(writeError))
                    return
                }
                self.audioInputs.values.forEach { $0.markAsFinished() }
                self.writer.finishWriting {
                    self.queue.async {
                        guard self.writer.status == .completed else {
                            self.finalization.complete(.failure(self.writer.error ?? RecorderError.writerNotReady))
                            return
                        }
                        do {
                            try FileManager.default.createDirectory(
                                at: self.finalURL.deletingLastPathComponent(),
                                withIntermediateDirectories: true
                            )
                            let outputURL = TakeFileStore().uniqueFileURL(self.finalURL)
                            try FileManager.default.moveItem(at: self.temporaryURL, to: outputURL)
                            self.finalization.complete(.success(.wrote(outputURL)))
                        } catch {
                            self.finalization.complete(.failure(error))
                        }
                    }
                }
            } }
        }
    }

    private func failWriting(_ error: Error) {
        writeError = error
        finished = true
        if !wroteVideo {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: temporaryURL)
        }
        guard !hasReportedFailure else { return }
        hasReportedFailure = true
        let onFailure = onFailure
        Task { @MainActor in
            onFailure?(error)
        }
    }

    private func presentationTime(for sourceTime: CMTime) -> CMTime {
        let elapsed = CMTimeSubtract(sourceTime, recordingStartHostTime)
        let adjusted = CMTimeSubtract(elapsed, pauseClock.offset)
        return CMTimeCompare(adjusted, .zero) < 0 ? .zero : adjusted
    }

    private func currentHostTime() -> CMTime {
        CMClockGetTime(CMClockGetHostTimeClock())
    }

    private static func makeAudioInput(for writer: AVAssetWriter, bitrate: Int) throws -> AVAssetWriterInput {
        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: bitrate
            ]
        )
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {
            throw RecorderError.writerNotReady
        }
        writer.add(input)
        return input
    }
}
