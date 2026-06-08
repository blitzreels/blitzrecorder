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

    private var pauseStartedAt: CMTime?
    private var pauseOffset = CMTime.zero
    private var paused = false
    private var finished = false
    private var wroteVideo = false
    private var writeError: Error?

    init(take: RecordingTake, settings: RecordingSettings) throws {
        finalURL = take.finalVideoURL
        temporaryURL = take.scratchDirectory
            .appendingPathComponent(".direct-export-\(UUID().uuidString).\(take.outputVideoFormat.fileExtension)")
        try? FileManager.default.removeItem(at: temporaryURL)

        writer = try AVAssetWriter(outputURL: temporaryURL, fileType: take.outputVideoFormat.avFileType)

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
            guard !self.finished, !self.paused, sourceTime.isValid else { return }
            let presentationTime = self.presentationTime(for: sourceTime)
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
                  !self.paused,
                  self.wroteVideo,
                  CMSampleBufferDataIsReady(sampleBuffer),
                  let input = self.audioInputs[source],
                  input.isReadyForMoreMediaData else {
                return
            }

            let sourceTime = self.currentHostTime()
            guard sourceTime.isValid else { return }
            let presentationTime = self.presentationTime(for: sourceTime)
            guard let adjusted = Self.copy(sampleBuffer, toPresentationTime: presentationTime) else {
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
            guard !self.paused else { return }
            self.paused = true
            self.pauseStartedAt = self.currentHostTime()
        }
    }

    func resume() {
        queue.async {
            guard self.paused else { return }
            if let start = self.pauseStartedAt {
                let delta = CMTimeSubtract(self.currentHostTime(), start)
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
                        try? FileManager.default.removeItem(at: self.temporaryURL)
                        continuation.resume(throwing: writeError)
                    } else {
                        continuation.resume(returning: self.wroteVideo ? .wrote(self.finalURL) : .empty(self.temporaryURL))
                    }
                    return
                }
                self.finished = true
                if let writeError = self.writeError {
                    try? FileManager.default.removeItem(at: self.temporaryURL)
                    continuation.resume(throwing: writeError)
                    return
                }
                guard self.wroteVideo else {
                    self.writer.cancelWriting()
                    try? FileManager.default.removeItem(at: self.temporaryURL)
                    continuation.resume(returning: .empty(self.temporaryURL))
                    return
                }

                self.videoInput.markAsFinished()
                self.audioInputs.values.forEach { $0.markAsFinished() }
                self.writer.finishWriting {
                    if let error = self.writer.error {
                        try? FileManager.default.removeItem(at: self.temporaryURL)
                        continuation.resume(throwing: error)
                        return
                    }

                    do {
                        try FileManager.default.createDirectory(
                            at: self.finalURL.deletingLastPathComponent(),
                            withIntermediateDirectories: true
                        )
                        let outputURL = Self.uniqueFileURL(self.finalURL)
                        try FileManager.default.moveItem(at: self.temporaryURL, to: outputURL)
                        continuation.resume(returning: .wrote(outputURL))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    private func failWriting(_ error: Error) {
        writeError = error
        finished = true
        writer.cancelWriting()
        try? FileManager.default.removeItem(at: temporaryURL)
    }

    private func presentationTime(for sourceTime: CMTime) -> CMTime {
        let elapsed = CMTimeSubtract(sourceTime, recordingStartHostTime)
        let adjusted = CMTimeSubtract(elapsed, pauseOffset)
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

    private static func copy(_ sampleBuffer: CMSampleBuffer, toPresentationTime presentationTime: CMTime) -> CMSampleBuffer? {
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
                presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
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

        let sourceTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let delta = CMTimeSubtract(presentationTime, sourceTime)
        for index in timing.indices {
            if timing[index].presentationTimeStamp.isValid {
                timing[index].presentationTimeStamp = CMTimeAdd(timing[index].presentationTimeStamp, delta)
            } else {
                timing[index].presentationTimeStamp = presentationTime
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

    private static func uniqueFileURL(_ url: URL) -> URL {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            return url
        }

        let directory = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        let pathExtension = url.pathExtension
        var index = 2
        while true {
            let candidate = directory.appendingPathComponent("\(baseName)-\(index).\(pathExtension)")
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }
}
