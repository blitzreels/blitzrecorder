@preconcurrency import AVFoundation
import CoreImage
import Foundation
import Vision

enum CameraBackgroundPostProcessor {
    static func removeBackground(
        from inputURL: URL,
        to outputURL: URL,
        progressHandler: (@MainActor (Double) -> Void)? = nil
    ) async throws -> URL {
        try? FileManager.default.removeItem(at: outputURL)

        let asset = AVURLAsset(url: inputURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw RecorderError.backgroundRemovalUnavailable
        }

        let duration = try await asset.load(.duration)
        let preferredTransform = try await track.load(.preferredTransform)

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else {
            throw RecorderError.backgroundRemovalUnavailable
        }
        reader.add(readerOutput)

        guard reader.startReading(),
              let firstSampleBuffer = readerOutput.copyNextSampleBuffer(),
              let firstPixelBuffer = CMSampleBufferGetImageBuffer(firstSampleBuffer) else {
            throw reader.error ?? RecorderError.backgroundRemovalUnavailable
        }

        let width = CVPixelBufferGetWidth(firstPixelBuffer)
        let height = CVPixelBufferGetHeight(firstPixelBuffer)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.proRes4444,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height
            ]
        )
        videoInput.expectsMediaDataInRealTime = false
        videoInput.transform = preferredTransform

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )

        guard writer.canAdd(videoInput) else {
            throw RecorderError.writerNotReady
        }
        writer.add(videoInput)
        guard writer.startWriting() else {
            throw writer.error ?? RecorderError.writerNotReady
        }
        writer.startSession(atSourceTime: .zero)

        let context = CIContext(options: [.cacheIntermediates: false])
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let sequenceHandler = VNSequenceRequestHandler()

        var frameCount = 0
        do {
            try appendMattedFrame(
                firstSampleBuffer,
                pixelBuffer: firstPixelBuffer,
                videoInput: videoInput,
                adaptor: adaptor,
                context: context,
                request: request,
                sequenceHandler: sequenceHandler
            )
            frameCount += 1
            await reportProgress(for: firstSampleBuffer, duration: duration, progressHandler: progressHandler)

            while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                try Task.checkCancellation()
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
                try appendMattedFrame(
                    sampleBuffer,
                    pixelBuffer: pixelBuffer,
                    videoInput: videoInput,
                    adaptor: adaptor,
                    context: context,
                    request: request,
                    sequenceHandler: sequenceHandler
                )
                frameCount += 1
                if frameCount.isMultiple(of: 10) {
                    await reportProgress(for: sampleBuffer, duration: duration, progressHandler: progressHandler)
                }
            }

            guard reader.status == .completed else {
                throw reader.error ?? RecorderError.backgroundRemovalUnavailable
            }
            videoInput.markAsFinished()
            try await finish(writer)
            await progressHandler?(1)
            return outputURL
        } catch {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    private static func appendMattedFrame(
        _ sampleBuffer: CMSampleBuffer,
        pixelBuffer: CVPixelBuffer,
        videoInput: AVAssetWriterInput,
        adaptor: AVAssetWriterInputPixelBufferAdaptor,
        context: CIContext,
        request: VNGeneratePersonSegmentationRequest,
        sequenceHandler: VNSequenceRequestHandler
    ) throws {
        guard let pool = adaptor.pixelBufferPool else {
            throw RecorderError.writerNotReady
        }
        while !videoInput.isReadyForMoreMediaData {
            usleep(1_000)
        }

        var outputBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer) == kCVReturnSuccess,
              let outputBuffer else {
            throw RecorderError.writerNotReady
        }

        let outputImage = CameraBackgroundMatte.mattedImage(
            for: pixelBuffer,
            request: request,
            sequenceHandler: sequenceHandler
        )
        context.render(outputImage, to: outputBuffer)

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard presentationTime.isValid,
              adaptor.append(outputBuffer, withPresentationTime: presentationTime) else {
            throw RecorderError.writerNotReady
        }
    }

    @MainActor
    private static func reportProgress(
        for sampleBuffer: CMSampleBuffer,
        duration: CMTime,
        progressHandler: (@MainActor (Double) -> Void)?
    ) {
        guard let progressHandler,
              duration.isValid,
              duration.seconds > 0 else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard time.isValid else { return }
        progressHandler(min(1, max(0, time.seconds / duration.seconds)))
    }

    private static func finish(_ writer: AVAssetWriter) async throws {
        let writerBox = SendableAssetWriter(writer)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writerBox.writer.finishWriting {
                if let error = writerBox.writer.error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

private struct SendableAssetWriter: @unchecked Sendable {
    let writer: AVAssetWriter

    init(_ writer: AVAssetWriter) {
        self.writer = writer
    }
}
