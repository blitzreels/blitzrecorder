import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

struct CameraFrameConformerRequest {
    let outputSize: CGSize?
    let sourceSize: CGSize
    let plan: CameraFrameNormalizationPlan?
}

final class CameraFrameConformer {
    private let outputSize: CGSize?
    private var sourceSize: CGSize
    private var normalizer: CameraFrameNormalizer?
    private var framesUntilNextDetection = 0
    private var transferSession: VTPixelTransferSession?
    private var scaledPool: CVPixelBufferPool?
    private var scaledPoolFormat: OSType?
    private static let detectionInterval = 10

    init(_ request: CameraFrameConformerRequest) {
        outputSize = request.outputSize
        sourceSize = request.sourceSize
        normalizer = request.plan.map(CameraFrameNormalizer.init)
    }

    func conform(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        if size != sourceSize {
            sourceSize = size
            normalizer = nil
            framesUntilNextDetection = 0
        }
        if normalizer == nil, size.height > size.width * 1.1 {
            if framesUntilNextDetection == 0 {
                normalizer = CameraFrameLetterboxDetector.normalizationPlan(.init(pixelBuffer: pixelBuffer))
                    .map(CameraFrameNormalizer.init)
                framesUntilNextDetection = Self.detectionInterval
            } else {
                framesUntilNextDetection -= 1
            }
        }
        guard let cropped = normalizer.map({ $0.normalize(sampleBuffer) }) ?? sampleBuffer else { return nil }
        guard let outputSize,
              let croppedBuffer = CMSampleBufferGetImageBuffer(cropped),
              CGSize(width: CVPixelBufferGetWidth(croppedBuffer), height: CVPixelBufferGetHeight(croppedBuffer))
                != outputSize else {
            return cropped
        }
        return scaled(.init(sampleBuffer: cropped, pixelBuffer: croppedBuffer, outputSize: outputSize))
    }

    private struct ScaleRequest {
        let sampleBuffer: CMSampleBuffer
        let pixelBuffer: CVPixelBuffer
        let outputSize: CGSize
    }

    private func scaled(_ request: ScaleRequest) -> CMSampleBuffer? {
        guard let session = pixelTransferSession(),
              let pool = scaledBufferPool(.init(
                pixelFormat: CVPixelBufferGetPixelFormatType(request.pixelBuffer),
                size: request.outputSize
              )) else { return nil }
        var output: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &output) == kCVReturnSuccess,
              let output,
              VTPixelTransferSessionTransferImage(session, from: request.pixelBuffer, to: output) == noErr else {
            return nil
        }
        var formatDescription: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: output,
            formatDescriptionOut: &formatDescription
        ) == noErr, let formatDescription else { return nil }
        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(request.sampleBuffer),
            presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(request.sampleBuffer),
            decodeTimeStamp: CMSampleBufferGetDecodeTimeStamp(request.sampleBuffer)
        )
        var result: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: output,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &result
        ) == noErr else { return nil }
        return result
    }

    private func pixelTransferSession() -> VTPixelTransferSession? {
        if let transferSession { return transferSession }
        var session: VTPixelTransferSession?
        guard VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault, pixelTransferSessionOut: &session) == noErr,
              let session else { return nil }
        VTSessionSetProperty(
            session,
            key: kVTPixelTransferPropertyKey_ScalingMode,
            value: kVTScalingMode_Letterbox
        )
        transferSession = session
        return session
    }

    private struct ScaledPoolRequest {
        let pixelFormat: OSType
        let size: CGSize
    }

    private func scaledBufferPool(_ request: ScaledPoolRequest) -> CVPixelBufferPool? {
        if scaledPoolFormat == request.pixelFormat, let scaledPool { return scaledPool }
        var pool: CVPixelBufferPool?
        guard CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            [kCVPixelBufferPoolMinimumBufferCountKey: 4] as CFDictionary,
            [
                kCVPixelBufferPixelFormatTypeKey: request.pixelFormat,
                kCVPixelBufferWidthKey: Int(request.size.width),
                kCVPixelBufferHeightKey: Int(request.size.height),
                kCVPixelBufferIOSurfacePropertiesKey: [:],
                kCVPixelBufferMetalCompatibilityKey: true
            ] as CFDictionary,
            &pool
        ) == kCVReturnSuccess, let pool else { return nil }
        scaledPool = pool
        scaledPoolFormat = request.pixelFormat
        return pool
    }
}
