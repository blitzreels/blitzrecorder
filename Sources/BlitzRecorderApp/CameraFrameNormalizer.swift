import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation

struct CameraFrameNormalizationPlan: Equatable {
    let cropRect: CGRect

    var outputSize: CGSize {
        cropRect.size
    }
}

struct CameraFrameLetterboxDetectionRequest {
    let pixelBuffer: CVPixelBuffer
}

struct CameraFrameNormalizationStartupRequest {
    let sourceSize: CGSize
    let bufferedSampleCount: Int
    let normalizationPlan: CameraFrameNormalizationPlan?
}

enum CameraFrameNormalizationStartupDecision: Equatable {
    case waitForMoreSamples
    case start(CameraFrameNormalizationPlan?)
}

enum CameraFrameNormalizationStartupPolicy {
    static let portraitSampleLimit = 8

    static func decision(
        _ request: CameraFrameNormalizationStartupRequest
    ) -> CameraFrameNormalizationStartupDecision {
        if let normalizationPlan = request.normalizationPlan {
            return .start(normalizationPlan)
        }
        if request.sourceSize.width >= request.sourceSize.height * 0.9 {
            return .start(nil)
        }
        if request.bufferedSampleCount < portraitSampleLimit {
            return .waitForMoreSamples
        }
        return .start(nil)
    }
}

enum CameraFrameLetterboxDetector {
    static func normalizationPlan(
        _ request: CameraFrameLetterboxDetectionRequest
    ) -> CameraFrameNormalizationPlan? {
        let pixelBuffer = request.pixelBuffer
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard height > Int(Double(width) * 1.1),
              pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                || pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
              CVPixelBufferGetPlaneCount(pixelBuffer) >= 2 else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let lumaBaseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let luma = lumaBaseAddress.assumingMemoryBound(to: UInt8.self)
        let sampleStep = max(1, width / 128)
        let blackThreshold: UInt8 = pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            ? 36
            : 24

        func nonDarkFraction(_ row: Int) -> Double {
            let rowAddress = luma.advanced(by: row * bytesPerRow)
            var sampleCount = 0
            var nonDarkCount = 0
            for x in stride(from: 0, to: width, by: sampleStep) {
                sampleCount += 1
                if rowAddress[x] > blackThreshold {
                    nonDarkCount += 1
                }
            }
            guard sampleCount > 0 else { return 0 }
            return Double(nonDarkCount) / Double(sampleCount)
        }

        func beginsActiveImage(_ row: Int) -> Bool {
            let probes = [row, row + 2, row + 4].filter { $0 < height }
            return probes.count == 3 && probes.allSatisfy { nonDarkFraction($0) >= 0.15 }
        }

        func endsActiveImage(_ row: Int) -> Bool {
            let probes = [row, row - 2, row - 4].filter { $0 >= 0 }
            return probes.count == 3 && probes.allSatisfy { nonDarkFraction($0) >= 0.15 }
        }

        guard let rawTop = (0..<height).first(where: beginsActiveImage),
              let rawBottom = (0..<height).reversed().first(where: endsActiveImage) else {
            return nil
        }

        let top = rawTop + rawTop % 2
        let bottomExclusive = (rawBottom + 1) - (rawBottom + 1) % 2
        let cropHeight = bottomExclusive - top
        let bottomPadding = height - bottomExclusive
        let minimumPadding = Int(Double(height) * 0.12)
        let symmetryTolerance = max(8, Int(Double(height) * 0.04))
        guard cropHeight > 0,
              top >= minimumPadding,
              bottomPadding >= minimumPadding,
              abs(top - bottomPadding) <= symmetryTolerance else {
            return nil
        }

        let contentAspectRatio = Double(width) / Double(cropHeight)
        guard (1.25...2.4).contains(contentAspectRatio) else {
            return nil
        }

        return CameraFrameNormalizationPlan(
            cropRect: CGRect(x: 0, y: top, width: width, height: cropHeight)
        )
    }
}

final class CameraFrameNormalizer {
    private let plan: CameraFrameNormalizationPlan
    private var pixelBufferPool: CVPixelBufferPool?
    private var poolPixelFormat: OSType?

    init(plan: CameraFrameNormalizationPlan) {
        self.plan = plan
    }

    func normalize(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard let sourcePixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let destinationPixelBuffer = croppedPixelBuffer(sourcePixelBuffer) else {
            return nil
        }

        var formatDescription: CMVideoFormatDescription?
        let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: destinationPixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard formatStatus == noErr, let formatDescription else {
            return nil
        }

        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sampleBuffer),
            presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
            decodeTimeStamp: CMSampleBufferGetDecodeTimeStamp(sampleBuffer)
        )
        var normalizedSampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: destinationPixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &normalizedSampleBuffer
        )
        guard sampleStatus == noErr else { return nil }
        return normalizedSampleBuffer
    }

    private func croppedPixelBuffer(
        _ sourcePixelBuffer: CVPixelBuffer
    ) -> CVPixelBuffer? {
        let pixelFormat = CVPixelBufferGetPixelFormatType(sourcePixelBuffer)
        guard pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                || pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
              CVPixelBufferGetPlaneCount(sourcePixelBuffer) >= 2 else {
            return nil
        }

        let cropX = Int(plan.cropRect.minX)
        let cropY = Int(plan.cropRect.minY)
        let outputWidth = Int(plan.cropRect.width)
        let outputHeight = Int(plan.cropRect.height)
        guard cropX >= 0,
              cropY >= 0,
              cropX % 2 == 0,
              cropY % 2 == 0,
              outputWidth > 0,
              outputHeight > 0,
              outputWidth % 2 == 0,
              outputHeight % 2 == 0,
              cropX + outputWidth <= CVPixelBufferGetWidth(sourcePixelBuffer),
              cropY + outputHeight <= CVPixelBufferGetHeight(sourcePixelBuffer) else {
            return nil
        }

        let pool = pixelBufferPool(for: pixelFormat)
        var destinationPixelBuffer: CVPixelBuffer?
        let createStatus = pool.map {
            CVPixelBufferPoolCreatePixelBuffer(
                kCFAllocatorDefault,
                $0,
                &destinationPixelBuffer
            )
        } ?? kCVReturnInvalidArgument
        guard createStatus == kCVReturnSuccess, let destinationPixelBuffer else {
            return nil
        }

        CVBufferPropagateAttachments(sourcePixelBuffer, destinationPixelBuffer)
        CVPixelBufferLockBaseAddress(sourcePixelBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(destinationPixelBuffer, [])
        defer {
            CVPixelBufferUnlockBaseAddress(destinationPixelBuffer, [])
            CVPixelBufferUnlockBaseAddress(sourcePixelBuffer, .readOnly)
        }

        for plane in 0..<2 {
            guard let sourceBaseAddress = CVPixelBufferGetBaseAddressOfPlane(sourcePixelBuffer, plane),
                  let destinationBaseAddress = CVPixelBufferGetBaseAddressOfPlane(destinationPixelBuffer, plane) else {
                return nil
            }
            let verticalScale = plane == 0 ? 1 : 2
            let sourceBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(sourcePixelBuffer, plane)
            let destinationBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(destinationPixelBuffer, plane)
            let sourceStartRow = cropY / verticalScale
            let rowCount = outputHeight / verticalScale
            for row in 0..<rowCount {
                memcpy(
                    destinationBaseAddress.advanced(by: row * destinationBytesPerRow),
                    sourceBaseAddress.advanced(
                        by: (sourceStartRow + row) * sourceBytesPerRow + cropX
                    ),
                    outputWidth
                )
            }
        }
        return destinationPixelBuffer
    }

    private func pixelBufferPool(
        for pixelFormat: OSType
    ) -> CVPixelBufferPool? {
        if poolPixelFormat == pixelFormat, let pixelBufferPool {
            return pixelBufferPool
        }

        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            [kCVPixelBufferPoolMinimumBufferCountKey: 4] as CFDictionary,
            [
                kCVPixelBufferPixelFormatTypeKey: pixelFormat,
                kCVPixelBufferWidthKey: Int(plan.outputSize.width),
                kCVPixelBufferHeightKey: Int(plan.outputSize.height),
                kCVPixelBufferIOSurfacePropertiesKey: [:],
                kCVPixelBufferMetalCompatibilityKey: true
            ] as CFDictionary,
            &pool
        )
        guard status == kCVReturnSuccess, let pool else { return nil }
        pixelBufferPool = pool
        poolPixelFormat = pixelFormat
        return pool
    }
}
