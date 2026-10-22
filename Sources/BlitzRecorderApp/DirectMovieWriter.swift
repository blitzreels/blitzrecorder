import AVFoundation
import CoreMedia
import Foundation
import VideoToolbox

final class DirectMovieWriter: @unchecked Sendable {
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audioInputs: [CaptureSource: AVAssetWriterInput]
    private let finalURL: URL
    private let temporaryURL: URL
    private let queue = DispatchQueue(label: "blitzrecorder.direct-movie-writer")
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

    func appendVideo(sourceTime: CMTime, render: @escaping (CVPixelBuffer) -> Bool) {
        queue.async {
            guard !self.finished, !self.pauseClock.isPaused, sourceTime.isNumeric else { return }
            guard self.writer.status != .failed else {
                self.failWriting(self.writer.error ?? RecorderError.writerNotReady)
                return
            }
            let presentationTime = self.presentationTime(for: sourceTime)
            guard presentationTime.isNumeric else { return }
            if let lastWrittenVideoTime = self.lastWrittenVideoTime,
               CMTimeCompare(presentationTime, lastWrittenVideoTime) <= 0 {
                return
            }
            guard self.videoInput.isReadyForMoreMediaData,
                  let pool = self.adaptor.pixelBufferPool else {
                return
            }

            var pixelBuffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer) == kCVReturnSuccess,
                  let pixelBuffer,
                  render(pixelBuffer) else {
                return
            }

            if self.adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
                self.wroteVideo = true
                self.lastWrittenVideoTime = presentationTime
            } else {
                self.failWriting(
                    self.writer.error ?? RecorderError.mediaWriteFailed("Direct movie writer rejected a video frame.")
                )
            }
        }
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer, source: CaptureSource) {
        queue.async {
            guard !self.finished,
                  !self.pauseClock.isPaused,
                  self.wroteVideo,
                  CMSampleBufferDataIsReady(sampleBuffer),
                  let input = self.audioInputs[source],
                  input.isReadyForMoreMediaData else {
                return
            }

            let sourceTime = self.currentHostTime()
            guard sourceTime.isValid else { return }
            let presentationTime = self.presentationTime(for: sourceTime)
            guard let adjusted = sampleBuffer.retimed(toPresentationTime: presentationTime) else {
                return
            }
            if !input.append(adjusted) {
                self.failWriting(
                    self.writer.error ?? RecorderError.mediaWriteFailed("Direct movie writer rejected an audio sample.")
                )
            }
        }
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
                guard self.wroteVideo else {
                    self.writer.cancelWriting()
                    try? FileManager.default.removeItem(at: self.temporaryURL)
                    self.finalization.complete(.success(.empty(self.temporaryURL)))
                    return
                }
                self.videoInput.markAsFinished()
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
            }
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
